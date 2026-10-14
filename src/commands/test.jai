#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
#import "Juice";
#import "Testing";

// `juice test`: full-package discovery (ticket 0019) -> transpile -> driver
// -> metaprogram -> compile-time execution -> report and exit code, end to
// end. Views live content-addressed under target/transpile/<hash>/<rel>
// (ticket 0020): an existing view is a cache hit and stays untouched, a
// missing one is transpiled and written. Driver and metaprogram are
// regenerated on every run and are not cached.

TEST_COMMAND :: Command.{
    name          = "test",
    description   = "Run unit tests in the root package",
    usage         = "juice test [pattern]",
    prerequisites = string.[],
    handler       = test_command,
    validate_arguments = test_arguments_are_valid,
};

test_arguments_are_valid :: (arguments: [] string) -> bool {
    return arguments.count <= 1;
}

test_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if !command_arguments_are_valid(TEST_COMMAND, arguments) return false;
    // 票 0049 缺陷修正：force_dependencies——LIB 无 effective target 时
    // 测试程序仍经 import shim 引用依赖，Test 必须准备 dependencies。
    prepared := ensure_workspace_prepared(ctx.root_dir, ctx.cache_dir, *ctx.workspace, force_dependencies = true);
    if prepared == null return false;
    pattern := ifx arguments.count == 1 then arguments[0] else "";
    files, ok := collect_test_files(prepared);
    if !ok return false;
    return test_prepared_workspace(prepared, pattern, files);
}

// One test source file: the package-relative path ("/" separated, mirrors the
// package directory structure) and the absolute path of the source file.
Test_Source_File :: struct {
    rel_path: string;
    abs_path: string;
}

// The transpile step's output for one file: the expand-mode view text, the
// content-addressed cache key (pure function over path + source + mode +
// version) and the test entries found in it.
Test_File_Output :: struct {
    view:        string;
    key:         string;
    tests:       [..] Test_Entry;
    diagnostics: [..] Transpile_Diagnostic;
}

// The compile seam mirrors build's compile seam: production handlers use the
// default (real jai invocation of the generated metaprogram); tests cross the
// same interface with a recording adapter instead of invoking the compiler.
transpile_test_file :: (file: Test_Source_File, next_test_number: s64) -> Test_File_Output {
    output: Test_File_Output;
    source, ok := read_entire_file(file.abs_path);
    if !ok {
        array_add(*output.diagnostics, .{line = 0, column = 0, message = tprint("无法读取测试源文件: %1", file.abs_path)});
        return output;
    }
    ctx: Transpile_Context;
    ctx.mode = .EXPAND;
    ctx.path = file.rel_path;
    ctx.next_test_number = next_test_number;
    result := transpile_source(source, ctx);
    output.view = result.view;
    output.key = transpile_view_key(file.rel_path, source, .EXPAND, Load_Target.[], JUICE_VERSION);
    output.tests = result.tests;
    output.diagnostics = result.diagnostics;
    return output;
}

compile_test_program :: (transpile_dir: string, driver_path: string, metaprogram_path: string) -> bool {
    // -quiet strips the compiler's banner and stats; the test program's
    // compile-time output (start lines, failures, summary) passes through
    // untouched, and the jai exit code carries pass/fail (issues/0006).
    result := run_command("jai", "-quiet", to_forward_slashes(metaprogram_path));
    if result.exit_code != 0 {
        print("[juice ERROR] Test compilation failed.\n");
        return false;
    }
    return true;
}

// The orchestration seam (spec 0013 Testing Decisions): the production
// handler uses the default transpile and compile operations; tests inject
// recording fakes, exactly like the build compile seam. 票 0038：Test 不再
// 接收任何路径——货载透传清零，编译 seam 只收生成产物路径。
test_prepared_workspace :: (
    prepared: *Prepared_Workspace,
    pattern: string,
    files: [] Test_Source_File,
    transpile: #type (file: Test_Source_File, next_test_number: s64) -> Test_File_Output = transpile_test_file,
    compile: #type (transpile_dir: string, driver_path: string, metaprogram_path: string) -> bool = compile_test_program,
    dep_transpile: #type (file: Build_Source_File, load_targets: [] Load_Target) -> Build_File_Output = transpile_build_file
) -> bool {
    // 1. Transpile every file in list order, numbering tests globally.
    //    Diagnostics are rejected with the original file coordinates.
    outputs: [..] Test_File_Output;
    matches: [..] Test_Entry;
    next_number: s64 = 1;
    for file: files {
        output := transpile(file, next_number);
        if output.diagnostics.count > 0 {
            for diagnostic: output.diagnostics {
                print("[juice ERROR] %1:%2,%3: %4\n", file.rel_path, diagnostic.line, diagnostic.column, diagnostic.message);
            }
            return false;
        }
        array_add(*outputs, output);
        for test: output.tests {
            if pattern == "" || find_index_from_left(test.name, pattern) >= 0 {
                array_add(*matches, test);
            }
        }
        next_number += output.tests.count;
    }

    // 2. Empty semantics (issues/0006): no test blocks succeed with an
    //    explanation and skip the build. The pattern-matched check runs
    //    after the Testing module special case below: a pattern may match
    //    only the module's self-test blocks.
    if next_number == 1 {
        print("[juice Test] No tests found.\n");
        return true;
    }

    // 3. Content-addressed view paths for every discovered file (ticket
    //    0020): every path derives from the per-file key the transpile step
    //    returned; an existing view is a cache hit and stays untouched
    //    (content addressing makes stale views unreachable, so there is
    //    nothing to invalidate or clean), a missing one is written with the
    //    package-relative structure mirrored inside the hash directory. The
    //    paths are computed up front: the Testing module special case below
    //    refers to the test support view by rel_path.
    transpile_dir := transpile_tree_dir(prepared.discovery.root_dir);
    view_paths: [..] string;
    for file, index: files {
        array_add(*view_paths, transpile_view_path(transpile_dir, outputs[index].key, file.rel_path));
    }

    // 4. Testing 断言模块特例（票 0033，视图计算内聚于 testing_module_view，
    //    票 0039）：模块源文件内联 test block 后不可被 jai 直接编译，生成器
    //    把 `#import "Testing"` 的解析目标换成生成的编译视图（metaprogram
    //    的 import_path 前置其目录，同一模块只加载一份，全局计数不分裂）。
    //    此处只做支撑段视图查找、自测块的 pattern 过滤与全局编号续接；写盘
    //    仍在 zero-match 检查之后的既有位置（步骤 6）。
    support_view_text := "";
    for f, index: files {
        if f.rel_path == "tests/test_support.jai" support_view_text = outputs[index].view;
    }
    module_view_result, module_ok := testing_module_view(prepared.discovery.root_dir, support_view_text, next_number);
    if !module_ok return false;
    if module_view_result.enabled {
        for entry: module_view_result.tests {
            if pattern == "" || find_index_from_left(entry.name, pattern) >= 0 {
                array_add(*matches, entry);
            }
        }
        next_number = module_view_result.next_test_number;
    }

    if matches.count == 0 {
        print("[juice Test] No tests matched '%'.\n", pattern);
        return true;
    }

    print("[juice Test] Found %1 tests; compiling test program...\n", matches.count);

    // 5. Views land content-addressed under target/transpile/<hash>/<rel>.
    if !make_directory_if_it_does_not_exist(transpile_dir, recursive = true) {
        print("[juice ERROR] Could not create the transpile cache directory: %\n", transpile_dir);
        return false;
    }
    for index: 0..view_paths.count-1 {
        view_path := view_paths[index];
        // The parent must exist before the existence check: the inspection
        // scans the parent directory, and a missing parent would make
        // visit_files log a spurious "Unable to open directory" error.
        if !make_directory_if_it_does_not_exist(path_strip_filename(view_path), recursive = true) {
            print("[juice ERROR] Could not create view directory for %\n", files[index].rel_path);
            return false;
        }
        if path_exists_as_regular_file(view_path) continue;
        if !write_entire_file(view_path, outputs[index].view) {
            print("[juice ERROR] Could not write view for %\n", files[index].rel_path);
            return false;
        }
    }

    // 6. The Testing module compile view: a session product like driver.jai
    //    (regenerated on every run, never cached — its content is the module
    //    view plus the driver-specific support block, not the pure transpile
    //    output). Its directory is prepended to the metaprogram's import
    //    path, so every `#import "Testing"` resolves to this file. It lives
    //    under target/ directly — outside the transpile tree, whose direct
    //    children the cache-tree tests assert to be exactly the hash
    //    directories plus driver.jai/first.jai. 计算在 testing_module_view
    //    （票 0039），此处只写盘——保持在 zero-match 检查之后的既有位置。
    // 哨兵："" 表示「未启用编译视图特例」（module_view_result.enabled 为
    // false），与各生成器的 testing_view_dir/testing_module_view 同一约定。
    testing_module_dir := "";
    testing_module_view_path := "";
    if module_view_result.enabled {
        testing_module_dir = module_view_result.dir;
        if !make_directory_if_it_does_not_exist(testing_module_dir, recursive = true) {
            print("[juice ERROR] Could not create Testing module view directory: %\n", testing_module_dir);
            return false;
        }
        testing_module_view_path = module_view_result.view_path;
        if !write_entire_file(testing_module_view_path, module_view_result.view_text) {
            print("[juice ERROR] Could not write Testing module view.\n");
            return false;
        }
    }

    // 7. Driver and metaprogram are products of this run's test list, so
    //    they are regenerated and written on every run, never cached.
    driver_path := tprint("%1/driver.jai", transpile_dir);
    metaprogram_path := tprint("%1/first.jai", transpile_dir);
    if !write_entire_file(driver_path, generate_test_driver(files, view_paths, matches, testing_module_view_path)) {
        print("[juice ERROR] Could not write test driver.\n");
        return false;
    }
    metaprogram: Compiler_Metaprogram_Options;
    metaprogram.workspace_name    = "Juice Test Program";
    metaprogram.no_output         = true;
    metaprogram.intermediate_path = tprint("%1/target", prepared.discovery.root_dir);
    // 票 0048：与 build 共用 compiler_import_directories——依赖 shim 所在
    // 的 target/packages 必须在搜索路径，root 测试程序才能 #import 依赖
    // （含 workspace member）。此前只注入 modules 目录，解析必败。
    metaprogram.import_dirs       = compiler_import_directories(packages_dir(prepared.discovery.root_dir));
    metaprogram.build_file        = driver_path;
    metaprogram.testing_view_dir  = testing_module_dir;
    if !write_entire_file(metaprogram_path, generate_compiler_metaprogram(metaprogram)) {
        print("[juice ERROR] Could not write test metaprogram.\n");
        return false;
    }

    // 8. Dependency strip front（票 0049）: the test program compiles
    //    dependency sources through import shims; closures containing test
    //    blocks are stripped exactly like build's. Dependency tests are
    //    neither discovered nor executed — the discovery scan never enters
    //    dependency packages — this step only makes them compilable.
    if !prepare_dependency_strip_views(prepared.discovery.root_dir, dep_transpile) return false;
    return compile(transpile_dir, driver_path, metaprogram_path);
}

// Testing 断言模块编译视图的计算（票 0033 特例，计算内聚于本函数，票
// 0039）：模块源文件内联 test block 后不可被 jai 直接编译，测试程序必须
// 把 `#import "Testing"` 的解析目标换成生成的编译视图。package 自身的
// modules/Testing.jai 存在时（in_package），视图用 EXPAND 模式并追加
// #load test_support 视图的 Testing 自测段——模块是密封作用域（how_to
// 151），模块内 #load 的文件挂模块的 Module scope，自测块引用测试支撑
// 声明由此可见；其测试块同时收进测试列表（全局编号续接）。用户 package
// 无此文件时视图用 STRIP 模式（test-free，断言语义同源文件），测试报告
// 与计数零变更。模块不存在、读取失败或 test-free 时返回未启用结果（原样
// #import 模块源文件）。只计算不写盘：写盘留在编排的 zero-match 检查
// 之后（session product 语义与既有行为逐字节一致）。
Testing_Module_View_Result :: struct {
    enabled:          bool;           // 未启用 = 原样 #import 模块源文件
    in_package:       bool;
    dir:              string;         // 写盘目录 target/testing-module
    view_path:        string;         // 写盘文件 dir/Testing.jai
    view_text:        string;         // EXPAND（+支撑段）或 STRIP 视图文本
    tests:            [..] Test_Entry; // in-package 自测块（编号已续接）
    next_test_number: s64;            // 续接后的全局编号
}

testing_module_view :: (package_root: string, support_view: string, next_test_number: s64) -> Testing_Module_View_Result, bool {
    result: Testing_Module_View_Result;
    result.next_test_number = next_test_number;

    module_file, module_in_package := testing_module_source(package_root);
    if module_file.abs_path == "" return result, true;

    source, ok := read_entire_file(module_file.abs_path);
    if !ok || !source_has_test_block(source) return result, true;

    result.enabled = true;
    result.in_package = module_in_package;
    if module_in_package {
        // package 自身的模块：EXPAND 视图（编号续接全局序列），自测块
        // 进测试列表。
        module_result := transpile_test_file(module_file, next_test_number);
        if module_result.diagnostics.count > 0 {
            for diagnostic: module_result.diagnostics {
                print("[juice ERROR] %1:%2,%3: %4\n", module_file.rel_path, diagnostic.line, diagnostic.column, diagnostic.message);
            }
            return result, false;
        }
        result.view_text = module_result.view;
        result.tests = module_result.tests;
        result.next_test_number = next_test_number + module_result.tests.count;

        // EXPAND 编译视图追加自测支撑段：test_support 视图整体内嵌会把
        // 其 #import 链与声明挂进模块 export 列表（与 driver #load 的同一
        // 视图在 Application 重复），因此只切取 Testing 自测段（helper
        // 声明与记录全局），并配文件级 import 与自足 root（见
        // testing_module_support_block）。
        if support_view == "" {
            print("[juice ERROR] Testing 自测需要 tests/test_support.jai 视图，但未发现该文件。\n");
            return result, false;
        }
        support_block := testing_module_support_block(support_view);
        if support_block == "" {
            print("[juice ERROR] tests/test_support.jai 缺少 Testing 自测段标记。\n");
            return result, false;
        }
        result.view_text = tprint("%1\n\n%2", result.view_text, support_block);
    } else {
        // 用户 package 的断言模块来源：STRIP 视图（test-free 编译视图）。
        strip_ctx: Transpile_Context;
        strip_ctx.mode = .STRIP;
        strip_ctx.path = module_file.rel_path;
        stripped := transpile_source(source, strip_ctx);
        if stripped.diagnostics.count > 0 {
            for diagnostic: stripped.diagnostics {
                print("[juice ERROR] %1:%2,%3: %4\n", module_file.rel_path, diagnostic.line, diagnostic.column, diagnostic.message);
            }
            return result, false;
        }
        result.view_text = stripped.view;
    }

    result.dir = to_forward_slashes(tprint("%1/target/testing-module", package_root));
    result.view_path = to_forward_slashes(tprint("%1/Testing.jai", result.dir));
    return result, true;
}

// The Testing assertion module's source file for the generator special case
// (ticket 0033): the package's own modules/Testing.jai when present
// (in_package = true, its self-test blocks join the test list), otherwise
// the module next to the running executable (user packages). Returns an
// empty abs_path when no module exists. The rel_path is always
// "modules/Testing.jai": the module view's file name must stay Testing.jai
// so the import path resolves it as the Testing module.
testing_module_source :: (package_root: string) -> (file: Test_Source_File, in_package: bool) {
    rel := "modules/Testing.jai";
    pkg_path := tprint("%1/%2", package_root, rel);
    if path_exists_as_regular_file(pkg_path) {
        file: Test_Source_File;
        file.rel_path = rel;
        file.abs_path = to_forward_slashes(pkg_path);
        return file, true;
    }
    global_path := tprint("%1/Testing.jai", juice_modules_dir());
    if path_exists_as_regular_file(global_path) {
        file: Test_Source_File;
        file.rel_path = rel;
        file.abs_path = to_forward_slashes(global_path);
        return file, false;
    }
    return .{}, false;
}

// The self-test support block appended to the EXPAND module compile view
// (ticket 0033): the Testing self-test segment of the test support view, cut
// out by the stable machine markers in tests/test_support.jai — 段标记是稳定
// 锚点，段内注释改名不再破坏切段——under #scope_file so the declarations
// stay in the module compile view's file scope (they must not enter the
// module's export list — the driver #loads the same view into the
// application scope and duplicates there would clash). The segment carries
// its own self-contained juice_root (the module is a sealed scope and cannot
// see the src/path_safety declarations the rest of the test support file
// relies on). Returns "" when a marker is missing.
testing_module_support_block :: (support_view: string) -> string {
    // 定位标记行：标记必须独占其行，按「换行 + 标记」锚定，注释正文中的
    // 提及不会误命中。
    begin := find_index_from_left(support_view, "\n// __testing_module_support_begin__");
    if begin < 0 return "";
    begin += 1;
    end := find_index_from_left(support_view, "\n// __testing_module_support_end__");
    if end < 0 return "";
    end += 1;
    // 段含结束标记行整行（标记注释随段进入模块视图，注明来源与纪律）。
    while end < support_view.count && support_view[end] != #char "\n" end += 1;
    if end < support_view.count end += 1;
    segment := slice(support_view, begin, end - begin);

    builder: String_Builder;
    print_to_builder(*builder, "#scope_file;\n");
    print_to_builder(*builder, "#import \"Basic\";\n");
    print_to_builder(*builder, "#import \"Compiler\";\n");
    print_to_builder(*builder, "#import \"File\";\n");
    print_to_builder(*builder, "#import \"Process\";\n");
    print_to_builder(*builder, "#import \"String\";\n");
    print_to_builder(*builder, "\n");
    print_to_builder(*builder, "%", segment);
    return builder_to_string(*builder);
}

// Driver (docs/transpiled-output-formatting.md §2): an entry-point-free
// generated file with four parameterized points — the view list (every
// discovered package file exactly once, in list order, content-addressed
// cache paths), the path-mapping table injected before the run list, the
// pattern-filtered test list, and the finish()/assert close. The injection
// uses array_reset/array_add with bare names: the current compiler cannot
// convert a static array literal to the dynamic path_mapping array, and a
// plain #import does not open a `Testing.` namespace (ticket 0017 findings).
//
// testing_module_view (ticket 0033 special case, default "" = off): the
// absolute path of the generated Testing module compile view. When set, the
// module's self-test blocks run through it and its path-mapping entry prints
// module failure coordinates as the package-relative "modules/Testing.jai".
// 哨兵约定："" 表示「未启用编译视图特例」——与共享 Metaprogram generator
// 的 testing_view_dir、bootstrap build.jai 的 testing_view_dir 同一约定
// （生成输出与特例前逐字节一致，票 0036）。
generate_test_driver :: (files: [] Test_Source_File, view_paths: [] string, matches: [] Test_Entry, testing_module_view: string = "") -> string {
    builder: String_Builder;
    print_to_builder(*builder, "#import \"Basic\";\n\n");
    for i: 0..view_paths.count-1 {
        print_to_builder(*builder, "#load %1;\n", quote_jai_string(view_paths[i]));
    }
    print_to_builder(*builder, "\n#import \"Testing\";\n\n#run {\n");
    print_to_builder(*builder, "    array_reset(*path_mapping);\n");
    for i: 0..files.count-1 {
        print_to_builder(*builder, "    array_add(*path_mapping, .{ view = %1, original = %2 });\n",
            quote_jai_string(view_paths[i]),
            quote_jai_string(files[i].rel_path));
    }
    if testing_module_view != "" {
        print_to_builder(*builder, "    array_add(*path_mapping, .{ view = %1, original = %2 });\n",
            quote_jai_string(testing_module_view),
            quote_jai_string("modules/Testing.jai"));
    }
    for test: matches {
        print_to_builder(*builder, "    run(%1, juice_test_%2);\n", quote_jai_string(test.name), test.number);
    }
    print_to_builder(*builder, "    if finish() != 0 assert(false);\n}\n");
    return builder_to_string(*builder);
}

// The metaprogram itself is generated by the shared Metaprogram generator
// (src/metaprogram.jai, 票 0036): NO_OUTPUT so the test program has no entry
// point, import_path gets the Testing module directory, intermediate_path is
// the package target directory (compiler intermediates land under target/,
// not a .build directory next to the metaprogram), and the driver is added
// after the intercept begins. The byte-for-byte output contract is locked by
// tests/data/transpile/golden/*/first.jai (docs/transpiled-output-formatting.md
// §3).

// Full discovery scan (ticket 0019, issue 0003): recursively collects every
// lowercase ".jai" test source from the package root. Dot entries are
// excluded at any depth; the root-level target/ (managed products),
// tests/data/ (fixture directory), modules/ (module directory) and the scan
// root's own manifest are excluded; workspace member subtrees are pruned via
// the discovery snapshot (members run their tests as their own root);
// symlinks and junctions are not followed. Enumeration order is the scan
// order: a deterministic DFS where each directory yields its files first
// (lexicographic by name) and then recurses into its subdirectories
// (lexicographic) — enumeration, call and report order derive from it.
collect_test_files :: (prepared: *Prepared_Workspace) -> [] Test_Source_File, bool {
    collect: Collect_Context;
    collect.root = prepared.discovery.root_dir;
    // Member boundaries come from the workspace discovery snapshot (root
    // package first); the scan consumes it without merging into discovery.
    for pkg, index: prepared.discovery.member_packages {
        if index == 0 continue;
        array_add(*collect.member_dirs, copy_string(pkg.dir));
    }
    visited := visit_files(collect.root, true, *collect, collect_test_file_visitor,
        visit_files = true, visit_directories = true,
        visit_symlinks = false, follow_directory_symlinks = false);
    if !visited {
        print("[juice ERROR] Could not scan package root for test sources: %\n", collect.root);
        return Test_Source_File.[], false;
    }
    return enumerate_test_files(*collect), true;
}

// Raw walk entries plus the member boundaries consumed from the discovery
// snapshot; the deterministic enumeration happens after the walk.
Collect_Context :: struct {
    root:        string;
    member_dirs: [..] string;
    files:       [..] Scan_Entry;
    dirs:        [..] Scan_Entry;
}

Scan_Entry :: struct {
    short_name: string;
    full_name:  string;
}

collect_test_file_visitor :: (info: *File_Visit_Info, collect: *Collect_Context) {
    if info.is_directory {
        if !collect_directory_is_scanned(info, collect) {
            info.descend_into_directory = false;
            return;
        }
        entry: Scan_Entry;
        entry.short_name = copy_string(info.short_name);
        entry.full_name  = copy_string(info.full_name);
        array_add(*collect.dirs, entry);
        return;
    }
    if collect_file_is_excluded(info, collect) return;
    entry: Scan_Entry;
    entry.short_name = copy_string(info.short_name);
    entry.full_name  = copy_string(info.full_name);
    array_add(*collect.files, entry);
}

// Directory part of a walk entry without the trailing separator
// (path_strip_filename keeps it; the walk roots and dir names do not).
scan_entry_parent :: (full_name: string) -> string {
    parent := path_strip_filename(full_name);
    while parent.count > 0 && (parent[parent.count - 1] == #char "/" || parent[parent.count - 1] == #char "\\") parent.count -= 1;
    return parent;
}

// Directory-side exclusions (issue 0003): dot entries at any depth; the
// root-level target/, tests/data/ and modules/ (same-named directories at
// other depths are user code); workspace member subtrees; and links of any
// kind — visit_files already skips symlink entries itself, Windows junctions
// surface as plain directories there, so they are inspected explicitly in
// line with the path_safety posture.
collect_directory_is_scanned :: (info: *File_Visit_Info, collect: *Collect_Context) -> bool {
    if info.short_name.count > 0 && info.short_name[0] == #char "." return false;
    rel := test_file_rel_path(info.full_name, collect.root);
    if paths_equal(rel, "target") || paths_equal(rel, "tests/data") || paths_equal(rel, "modules") return false;
    for member: collect.member_dirs {
        if paths_equal(info.full_name, member) return false;
    }
    entry := inspect_path_entry(info.full_name);
    return !entry.is_symlink && !entry.is_junction;
}

// File-side exclusions: dot entries at any depth, non-lowercase-.jai
// extensions, and the scan root's own manifest (issue 0003: a nested source
// file that happens to be named package.jai is user code and stays scanned).
collect_file_is_excluded :: (info: *File_Visit_Info, collect: *Collect_Context) -> bool {
    if info.short_name.count > 0 && info.short_name[0] == #char "." return true;
    if !ends_with(info.short_name, ".jai") return true;
    if info.short_name == "package.jai" && paths_equal(scan_entry_parent(info.full_name), collect.root) return true;
    return false;
}

// Deterministic DFS enumeration in scan order (issue 0003): within each
// directory, files first (lexicographic by name), then subdirectories
// (lexicographic), recursing. This order derives the transpile enumeration,
// the driver call order and the report order.
enumerate_test_files :: (collect: Collect_Context) -> [..] Test_Source_File {
    out: [..] Test_Source_File;
    stack: [..] string;
    array_add(*stack, copy_string(collect.root));
    while stack.count > 0 {
        dir := stack[stack.count - 1];
        stack.count -= 1;
        dir_files: [..] Scan_Entry;
        dir_subdirs: [..] Scan_Entry;
        for entry: collect.files {
            if paths_equal(scan_entry_parent(entry.full_name), dir) array_add(*dir_files, entry);
        }
        for entry: collect.dirs {
            if paths_equal(scan_entry_parent(entry.full_name), dir) array_add(*dir_subdirs, entry);
        }
        sort_scan_entries(dir_files);
        sort_scan_entries(dir_subdirs);
        for entry: dir_files {
            file: Test_Source_File;
            file.abs_path = path_slashes(entry.full_name);
            file.rel_path = test_file_rel_path(entry.full_name, collect.root);
            array_add(*out, file);
        }
        // Push in reverse so the subdirectories pop in sorted order.
        i := dir_subdirs.count;
        while i > 0 {
            i -= 1;
            array_add(*stack, dir_subdirs[i].full_name);
        }
    }
    return out;
}

sort_scan_entries :: (entries: [] Scan_Entry) {
    for i: 1..entries.count-1 {
        if i >= entries.count break;
        key := entries[i];
        j := i - 1;
        while j >= 0 && compare(entries[j].short_name, key.short_name) > 0 {
            entries[j+1] = entries[j];
            j -= 1;
        }
        entries[j+1] = key;
    }
}

// Package-relative path of a scanned absolute path: everything after the
// package root prefix, "/" separated.
test_file_rel_path :: (absolute: string, root: string) -> string {
    rel := path_slashes(absolute);
    prefix := path_slashes(root);
    if prefix.count > 0 && prefix[prefix.count - 1] == #char "/" prefix.count -= 1;
    if rel.count > prefix.count return slice(rel, prefix.count + 1, rel.count - prefix.count - 1);
    return rel;
}

// ---------------------------------------------------------------------------
// 内联测试（票 0034 自旧 tests/ 迁移）：`juice test` 管道
// 的编排 seam（记录 fake：转译步骤按文件调用、fake 视图流入生成的 driver、
// compile seam 收到生成产物）、全量 discovery 扫描（排除集、member 边界、
// 链接跳过、确定性顺序）与 fixture package 的 E2E child 场景。共享声明
// （juice_exe、seam 记录 fake 与记录全局、缓存树扫描 helper、
// E2E child 场景 helper）见 tests/test_support.jai。
// ---------------------------------------------------------------------------

test "Seam: transpile step drives fake views into a compiled driver" {
    reset_seam_test();
    prepared := seam_prepared();
    expect(test_prepared_workspace(*prepared, "", seam_files(), fake_transpile, fake_compile));

    // The transpile step ran once per file with the running global number.
    expect(test_transpiled_files.count == 2);
    expect(test_transpiled_files[0].rel_path == "src/a.jai" && test_transpiled_files[1].rel_path == "src/b.jai");
    expect(test_transpiled_numbers[0] == 1 && test_transpiled_numbers[1] == 2);

    // The fake views were written content-addressed into the transpile tree,
    // mirroring the package structure inside the key directory.
    transpile_dir := transpile_tree_dir(prepared.discovery.root_dir);
    view_a := tprint("%1/%2/src/a.jai", transpile_dir, fake_key("src/a.jai"));
    view_b := tprint("%1/%2/src/b.jai", transpile_dir, fake_key("src/b.jai"));
    expect(file_contains(view_a, "// fake view of src/a.jai"));
    expect(file_contains(view_b, "// fake view of src/b.jai"));

    // The driver references every view, injects the path mapping, runs the
    // matched tests, and closes with the finish()/assert gate.
    driver_path := tprint("%1/driver.jai", transpile_dir);
    for file: seam_files() {
        view_path := tprint("%1/%2/%3", transpile_dir, fake_key(file.rel_path), file.rel_path);
        expect(file_contains(driver_path, tprint("#load \"%1\";", view_path)));
        expect(file_contains(driver_path, tprint("view = \"%1\", original = \"%2\"", view_path, file.rel_path)));
    }
    expect(file_contains(driver_path, "run(\"src/a.jai test 0\", juice_test_1);"));
    expect(file_contains(driver_path, "run(\"src/b.jai test 0\", juice_test_2);"));
    expect(file_contains(driver_path, "if finish() != 0 assert(false);"));

    // The metaprogram drives the driver with the Testing import path.
    expect(file_contains(tprint("%1/first.jai", transpile_dir), "options.output_type = .NO_OUTPUT;"));
    expect(file_contains(tprint("%1/first.jai", transpile_dir), "add_build_file"));

    // The compile seam received the generated products exactly once.
    expect(test_compile_calls == 1);
    expect(test_compile_transpile_dir == transpile_dir);
    expect(test_compile_driver_path == driver_path);
    expect(test_compile_metaprogram_path == tprint("%1/first.jai", transpile_dir));
    delete_directory_full(tprint("%1/target/seam-root", juice_root()));
}

// Cache-hit semantics (ticket 0020): a view that already exists at its
// content-addressed path is a hit and stays untouched — the orchestration
// writes only the missing views.
test "Seam: a cache hit leaves the existing view untouched" {
    reset_seam_test();
    prepared := seam_prepared();
    transpile_dir := transpile_tree_dir(prepared.discovery.root_dir);
    stale_path := tprint("%1/%2/src/a.jai", transpile_dir, fake_key("src/a.jai"));
    expect(make_directory_if_it_does_not_exist(path_strip_filename(stale_path), recursive = true));
    expect(write_entire_file(stale_path, "// stale cached view\n"));

    expect(test_prepared_workspace(*prepared, "", seam_files(), fake_transpile, fake_compile));

    // The pre-existing view was not overwritten; the missing one was written.
    expect(file_contains(stale_path, "// stale cached view"));
    expect(!file_contains(stale_path, "// fake view of src/a.jai"));
    view_b := tprint("%1/%2/src/b.jai", transpile_dir, fake_key("src/b.jai"));
    expect(file_contains(view_b, "// fake view of src/b.jai"));
    expect(test_compile_calls == 1);
    delete_directory_full(tprint("%1/target/seam-root", juice_root()));
}

test "Seam: pattern filters the generated test list" {
    reset_seam_test();
    prepared := seam_prepared();
    expect(test_prepared_workspace(*prepared, "b.jai", seam_files(), fake_transpile, fake_compile));
    driver_path := tprint("%1/driver.jai", transpile_tree_dir(prepared.discovery.root_dir));
    expect(test_compile_calls == 1);
    expect(file_contains(driver_path, "run(\"src/b.jai test 0\", juice_test_2);"));
    expect(!file_contains(driver_path, "run(\"src/a.jai test 0\", juice_test_1);"));
    delete_directory_full(tprint("%1/target/seam-root", juice_root()));
}

test "Seam: zero matches skip the compile" {
    reset_seam_test();
    prepared := seam_prepared();
    expect(test_prepared_workspace(*prepared, "nomatch", seam_files(), fake_transpile, fake_compile));
    delete_directory_full(tprint("%1/target/seam-root", juice_root()));
    expect(test_compile_calls == 0);
}

test "Seam: zero tests skip the compile" {
    reset_seam_test();
    prepared := seam_prepared();
    test_fake_tests_per_file = 0;
    expect(test_prepared_workspace(*prepared, "", seam_files(), fake_transpile, fake_compile));
    delete_directory_full(tprint("%1/target/seam-root", juice_root()));
    expect(test_compile_calls == 0);
}

test "Seam: transpile diagnostics fail before compiling" {
    reset_seam_test();
    prepared := seam_prepared();
    test_fake_diagnostic = "test block 仅允许文件顶层";
    expect(!test_prepared_workspace(*prepared, "", seam_files(), fake_transpile, fake_compile));
    delete_directory_full(tprint("%1/target/seam-root", juice_root()));
    expect(test_compile_calls == 0);
}

test "Seam: compile failure propagates" {
    reset_seam_test();
    prepared := seam_prepared();
    test_seam_compile_success = false;
    result := test_prepared_workspace(*prepared, "", seam_files(), fake_transpile, fake_compile);
    delete_directory_full(tprint("%1/target/seam-root", juice_root()));
    expect(!result && test_compile_calls == 1);
}

// ---------------------------------------------------------------------------
// Testing 模块视图计算（票 0039）：来源探测、哨兵禁用、EXPAND+支撑段与
// 全局 STRIP 的直接单测。写盘编排路径由 E2E（Testing 自测与 fixture
// package 场景）覆盖。
// ---------------------------------------------------------------------------

test "Testing module source: in-package module wins over the global one" {
    root := tprint("%1/target/tm-source-inpackage", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "modules/Testing.jai", "test \"self\" { }\n"));
    file, in_package := testing_module_source(root);
    expect(in_package && file.rel_path == "modules/Testing.jai");
    expect(file.abs_path == to_forward_slashes(tprint("%1/modules/Testing.jai", root)));
}

// 全局模块分支（exe 邻接）在编译期不可直接单测：编译期执行时
// juice_modules_dir() 解析到 jai 编译器自身的 modules 目录。该分支由
// E2E child 场景（真实 juice.exe 于 fixture package）端到端覆盖。

test "Testing module view: a test-free module stays disabled" {
    root := tprint("%1/target/tm-view-testfree", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "modules/Testing.jai", "// no test blocks\n"));
    result, ok := testing_module_view(root, "", 1);
    expect(ok && !result.enabled);
    expect(result.dir == "" && result.view_path == "" && result.tests.count == 0);
    expect(result.next_test_number == 1);
}

// In-package 模块：EXPAND 视图 + 支撑段切取，自测块编号续接全局序列。
test "Testing module view: in-package self-tests join with the support block" {
    root := tprint("%1/target/tm-view-inpackage", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "modules/Testing.jai", "test \"self one\" { }\ntest \"self two\" { }\n"));
    support_view := "\n// __testing_module_support_begin__\nhelper :: () {}\n// __testing_module_support_end__\n";
    result, ok := testing_module_view(root, support_view, 7);
    expect(ok && result.enabled && result.in_package);
    expect(result.tests.count == 2);
    expect(result.tests[0].name == "self one" && result.tests[0].number == 7 && result.tests[1].number == 8);
    expect(result.next_test_number == 9);
    expect(result.dir == to_forward_slashes(tprint("%1/target/testing-module", root)));
    expect(result.view_path == to_forward_slashes(tprint("%1/target/testing-module/Testing.jai", root)));
    expect(find_index_from_left(result.view_text, "juice_test_7 :: () -> () {") >= 0);
    expect(find_index_from_left(result.view_text, "__testing_module_support_begin__") >= 0);
}

test "Testing module view: missing support markers fail the computation" {
    root := tprint("%1/target/tm-view-nomarkers", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "modules/Testing.jai", "test \"self\" { }\n"));
    result, ok := testing_module_view(root, "// no markers\n", 1);
    expect(!ok && result.enabled);
}

// The transpile seam crosses the same interface as production: the real step
// reads the file, expands test blocks, reports diagnostics, and derives the
// content-addressed cache key from the pure function.
test "Real transpile step expands fixture tests" {
    output := transpile_test_file(.{rel_path = "src/main.jai", abs_path = tprint("%1/tests/data/test-package/src/main.jai", juice_root())}, 1);
    expect(output.diagnostics.count == 0 && output.tests.count == 2);
    expect(output.tests[0].name == "greeting" && output.tests[1].name == tprint("src/main.jai:%1", output.tests[1].line));
    expect(find_index_from_left(output.view, "juice_test_1 :: () -> () {") >= 0);
    source, ok := read_entire_file(tprint("%1/tests/data/test-package/src/main.jai", juice_root()));
    expect(ok);
    expect(output.key == transpile_view_key("src/main.jai", source, .EXPAND, Load_Target.[], JUICE_VERSION));
}

// The walking-skeleton collection: the fixture package's files in
// lexicographic order, without the manifest.
test "Collection lists fixture files in lexicographic order" {
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = tprint("%1/tests/data/test-package", juice_root());
    files, ok := collect_test_files(*prepared);
    expect(ok && files.count == 3);
    expect(files[0].rel_path == "src/main.jai");
    expect(files[1].rel_path == "src/math.jai");
    expect(files[2].rel_path == "tests/util_test.jai");
    for file: files {
        expect(file.abs_path == tprint("%1/tests/data/test-package/%2", juice_root(), file.rel_path));
    }
}

test "Collection rejects a missing package root" {
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = tprint("%1/tests/data/no-such-package", juice_root());
    _, ok := collect_test_files(*prepared);
    expect(!ok);
}

// Full discovery rules over the static scan fixture (ticket 0019): recursive
// lowercase-.jai discovery in deterministic scan order (per directory: files
// first, then subdirectories, both lexicographic). Excluded: dot entries at
// any depth, the root-level target/, tests/data/ and modules/, the root
// manifest, and the member-a subtree (boundary from the discovery snapshot).
// Included despite same names elsewhere: src/target/, src/modules/,
// src/data/ and a nested package.jai source file (issue 0003).
test "Collection applies the exclusion set in scan order" {
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = tprint("%1/tests/data/scan-fixture", juice_root());
    prepared.discovery.member_packages = Package.[
        .{name = "scan-fixture", dir = prepared.discovery.root_dir},
        .{name = "member-a", dir = tprint("%1/tests/data/scan-fixture/member-a", juice_root())},
    ];
    files, ok := collect_test_files(*prepared);
    expect(ok);
    expected := string.[
        "a_root.jai",
        "lib_deep/package.jai",
        "src/b.jai",
        "src/data/d.jai",
        "src/modules/e.jai",
        "src/target/c.jai",
        "tests/e.jai",
    ];
    if files.count != expected.count {
        print("[collect] got %1 files, want %2\n", files.count, expected.count);
        for file: files print("[collect] got %\n", file.rel_path);
    }
    expect(files.count == expected.count);
    for i: 0..expected.count-1 {
        expect(files[i].rel_path == expected[i]);
        expect(files[i].abs_path == tprint("%1/tests/data/scan-fixture/%2", juice_root(), expected[i]));
    }
}

// Creates a directory/file link with mklink（make_test_link 见
// tests/test_support.jai）。Returns false when the machine refuses link
// creation (needs developer mode or elevation).

// No link following (issue 0003): a symlinked directory, a junctioned
// directory and a symlinked file all stay out of the scan, while the real
// targets are still discovered through their own paths.
test "Collection skips symlinks and junctions" {
    root := tprint("%1/target/scan-links", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    real_dir := lexical_absolute_path(tprint("%1/real", root));
    expect(make_directory_if_it_does_not_exist(real_dir, recursive = true));
    expect(write_entire_file(tprint("%1/with_test.jai", real_dir), ""));
    expect(write_entire_file(tprint("%1/real_file.jai", lexical_absolute_path(root)), ""));

    link_ok := true;
    link_ok = make_test_link(tprint("%1/link_dir", lexical_absolute_path(root)), real_dir, directory = true, junction = false) && link_ok;
    link_ok = make_test_link(tprint("%1/junction_dir", lexical_absolute_path(root)), real_dir, directory = true, junction = true) && link_ok;
    link_ok = make_test_link(tprint("%1/link_file.jai", lexical_absolute_path(root)), tprint("%1/real_file.jai", lexical_absolute_path(root)), directory = false, junction = false) && link_ok;
    if !link_ok {
        print("[collect] SKIP: this machine refuses mklink; link exclusion not exercised\n");
        return;
    }

    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = lexical_absolute_path(root);
    files, ok := collect_test_files(*prepared);
    expect(ok);
    expected := string.["real_file.jai", "real/with_test.jai"];
    if files.count != expected.count {
        print("[collect] got %1 files, want %2\n", files.count, expected.count);
        for file: files print("[collect] got %\n", file.rel_path);
    }
    expect(files.count == expected.count);
    for i: 0..expected.count-1 {
        expect(files[i].rel_path == expected[i]);
    }
}

// ---------------------------------------------------------------------------
// Command declaration and argument guards
// ---------------------------------------------------------------------------

test "Test command declaration and argument contract" {
    expect(TEST_COMMAND.name == "test");
    expect(TEST_COMMAND.usage == "juice test [pattern]");
    expect(TEST_COMMAND.prerequisites.count == 0);
    expect(TEST_COMMAND.handler == test_command);
    expect(TEST_COMMAND.validate_arguments == test_arguments_are_valid);
    expect(TEST_COMMAND.validate_arguments(string.[]) && TEST_COMMAND.validate_arguments(string.["x"]));
    expect(!TEST_COMMAND.validate_arguments(string.["x", "y"]));
}

test "Test command argument guard" {
    ctx: Command_Context;
    expect(!TEST_COMMAND.handler(*ctx, string.["one", "two"]));
}

// ---------------------------------------------------------------------------
// E2E child scenarios (real juice.exe on the fixture packages)。Child 场景
// helper（run_juice_test、expect_exit、normalize_crlf、output_matches、
// fixture_line_col）见 tests/test_support.jai。
// ---------------------------------------------------------------------------

test "E2E: all-pass fixture package runs every test" {
    result, output, _ := run_juice_test("test-package");
    expect(expect_exit("pass", result, 0));
    expect(output_matches("pass", output, string.["[juice Test] Found 5 tests; compiling test program..."]));

    // The anonymous test reports as src/main.jai:<line of its `test` token>.
    anon_line, _ := fixture_line_col(tprint("%1/tests/data/test-package/src/main.jai", juice_root()), "test {");
    expect(anon_line != 0);
    expected := tprint(
        "[test] greeting\n[test] src/main.jai:%1\n[test] addition\n[test] addition with negatives\n[test] standalone file test\n5 passed, 0 failed\n",
        anon_line);
    expect(output_matches("pass", output, string.[expected]));
}

test "E2E: failing package exits 1 with mapped coordinates" {
    result, output, errors := run_juice_test("test-package-fail");
    expect(expect_exit("fail", result, 1));
    expect(output_matches("fail", output, string.["[juice Test] Found 1 tests; compiling test program...", "[test] broken math", "0 passed, 1 failed"]));

    line, col := fixture_line_col(tprint("%1/tests/data/test-package-fail/src/math.jai", juice_root()), "expect_eq(add(2, 3), 99)");
    expect(line != 0);
    // The failure line points at the original package-relative coordinates:
    // the driver-injected mapping table rewrote the view path.
    expect(output_matches("fail", output, string.[tprint("src/math.jai:%1:%2: expect_eq failed: expected 5, got 99", line, col)]));

    // The failure closes through the finish()/assert compile-error channel.
    expect(output_matches("fail", errors, string.["Assertion failed!"]));
}

test "E2E: pattern filters the executed tests" {
    result, output, _ := run_juice_test("test-package", "addition");
    expect(expect_exit("pattern", result, 0));
    expect(output_matches("pattern", output, string.["[juice Test] Found 2 tests; compiling test program...", "[test] addition\n[test] addition with negatives\n2 passed, 0 failed\n"]));
    expect(output_matches("pattern", output, string.["[test] greeting"], want = false));
}

test "E2E: zero match succeeds with an explanation" {
    result, output, _ := run_juice_test("test-package", "nomatch");
    expect(expect_exit("zero-match", result, 0));
    expect(output_matches("zero-match", output, string.["[juice Test] No tests matched 'nomatch'."]));
    expect(output_matches("zero-match", output, string.["[test]"], want = false));
}

// The pattern matches the final report name, including an anonymous test's
// `path:line` name.
test "E2E: pattern matches an anonymous path name" {
    result, output, _ := run_juice_test("test-package", "src/main.jai");
    expect(expect_exit("anon-pattern", result, 0));
    expect(output_matches("anon-pattern", output, string.["[juice Test] Found 1 tests; compiling test program..."]));
    anon_line, _ := fixture_line_col(tprint("%1/tests/data/test-package/src/main.jai", juice_root()), "test {");
    expect(anon_line != 0);
    expect(output_matches("anon-pattern", output, string.[tprint("[test] src/main.jai:%1\n1 passed, 0 failed\n", anon_line)]));
}

// Substring matching is case-sensitive (aligned with target selection).
test "E2E: pattern matching is case-sensitive" {
    result, output, _ := run_juice_test("test-package", "ADDITION");
    expect(expect_exit("case-sensitive", result, 0));
    expect(output_matches("case-sensitive", output, string.["[juice Test] No tests matched 'ADDITION'."]));
}

test "E2E: zero-test package skips the compile" {
    result, output, _ := run_juice_test("test-package-empty");
    expect(expect_exit("empty", result, 0));
    expect(output_matches("empty", output, string.["[juice Test] No tests found."]));
    expect(output_matches("empty", output, string.["[test]", "compiling test program"], want = false));
}

// Full discovery end to end (ticket 0019): recursive scan with nested
// directories, standalone and embedded test files, deep same-named
// directories still scanned, the root-level exclusion set never entering the
// scan (the excluded files are invalid Jai, so any regression fails the
// compile), and the member/dependency subtree staying out of the root run.
test "E2E: full discovery applies the exclusion set" {
    result, output, _ := run_juice_test("scan-package");
    expect(expect_exit("scan", result, 0));
    expect(output_matches("scan", output, string.["[juice Test] Found 5 tests; compiling test program..."]));
    expected := "[test] root test\n[test] deep nested test\n[test] deep modules dir test\n[test] deep target dir test\n[test] standalone test file\n5 passed, 0 failed\n";
    expect(output_matches("scan", output, string.[expected]));
    expect(output_matches("scan", output, string.["must never run", "[test] member test", "[test] member standalone test"], want = false));
}

// A workspace member runs its own tests when it is its own package root.
test "E2E: member runs its tests as its own root" {
    result, output, _ := run_juice_test("scan-package/member-a");
    expect(expect_exit("member", result, 0));
    expect(output_matches("member", output, string.["[juice Test] Found 2 tests; compiling test program..."]));
    expect(output_matches("member", output, string.["[test] member test\n[test] member standalone test\n2 passed, 0 failed\n"]));
}

// Deterministic scan order means repeated runs are byte-stable.
test "E2E: repeated scans are byte-stable" {
    result1, output1, _ := run_juice_test("scan-package");
    expect(expect_exit("stable-1", result1, 0));
    result2, output2, _ := run_juice_test("scan-package");
    expect(expect_exit("stable-2", result2, 0));
    if normalize_crlf(output1) != normalize_crlf(output2) {
        print("[child stable] outputs differ across runs\n  first:\n%\n  second:\n%\n", output1, output2);
    }
    expect(normalize_crlf(output1) == normalize_crlf(output2));
}

// ---------------------------------------------------------------------------
// E2E content-addressed cache scenarios (ticket 0020)
// ---------------------------------------------------------------------------

// Direct children of the transpile tree: hash directories and the
// regenerated driver.jai / first.jai products。Dir_Scan 结构、
// dir_scan_visitor、sort_strings、dir_scan_entries 见
// tests/test_support.jai。

test "E2E: cached views match the pure contract and hit on repeats" {
    result, output, _ := run_juice_test("test-package");
    expect(expect_exit("cache", result, 0));
    expect(output_matches("cache", output, string.["5 passed, 0 failed\n"]));

    // Every discovered file's view lives at the pure-function-derived path
    // and matches the pure transpile output byte for byte. The global test
    // numbering accumulates across files in list order, so the expected
    // views are recomputed the same way.
    transpile_dir := tprint("%1/tests/data/test-package/target/transpile", juice_root());
    rel_files := string.["src/main.jai", "src/math.jai", "tests/util_test.jai"];
    expected_keys: [..] string;
    expected_views: [..] string;
    next_number: s64 = 1;
    for rel: rel_files {
        source, ok := read_entire_file(tprint("%1/tests/data/test-package/%2", juice_root(), rel));
        expect(ok);
        array_add(*expected_keys, transpile_view_key(rel, source, .EXPAND, Load_Target.[], JUICE_VERSION));
        ctx: Transpile_Context;
        ctx.mode = .EXPAND;
        ctx.path = rel;
        ctx.next_test_number = next_number;
        result := transpile_source(source, ctx);
        array_add(*expected_views, result.view);
        next_number += result.tests.count;
    }
    for i: 0..rel_files.count-1 {
        view_path := transpile_view_path(transpile_dir, expected_keys[i], rel_files[i]);
        expect(path_exists_as_regular_file(view_path));
        view, ok2 := read_entire_file(view_path);
        expect(ok2 && view == expected_views[i]);
    }
    // The regenerated (uncached) products live at the tree root.
    expect(path_exists_as_regular_file(tprint("%1/driver.jai", transpile_dir)));
    expect(path_exists_as_regular_file(tprint("%1/first.jai", transpile_dir)));
    // The tree holds exactly the expected hash directories, nothing else.
    scan, ok3 := dir_scan_entries(transpile_dir);
    expect(ok3);
    if scan.files.count != 2 || scan.dirs.count != expected_keys.count {
        print("[child cache] transpile tree has %1 dirs, %2 files; want %3, 2\n", scan.dirs.count, scan.files.count, expected_keys.count);
    }
    expect(scan.files.count == 2 && scan.dirs.count == expected_keys.count);
    sort_strings(scan.dirs);
    sorted_expected: [..] string;
    for key: expected_keys array_add(*sorted_expected, key);
    sort_strings(sorted_expected);
    for i: 0..sorted_expected.count-1 {
        expect(scan.dirs[i] == sorted_expected[i]);
    }

    // A repeat run with unchanged content hits the same hash directories:
    // the tree contents are identical, nothing new appears.
    result2, output2, _ := run_juice_test("test-package");
    expect(expect_exit("cache-hit", result2, 0));
    expect(normalize_crlf(output) == normalize_crlf(output2));
    scan2, ok4 := dir_scan_entries(transpile_dir);
    expect(ok4 && scan2.files.count == 2 && scan2.dirs.count == expected_keys.count);
    sort_strings(scan2.dirs);
    for i: 0..sorted_expected.count-1 {
        expect(scan2.dirs[i] == sorted_expected[i]);
        view_path := transpile_view_path(transpile_dir, expected_keys[i], rel_files[i]);
        view, ok5 := read_entire_file(view_path);
        expect(ok5 && view == expected_views[i]);
    }
}

// dir_scan_entries 见 tests/test_support.jai。

// Content addressing without active cleanup: changing a source creates a new
// hash directory next to the old one, and both hold their views.
test "E2E: a content change creates a new hash directory" {
    root := tprint("%1/target/cache-e2e-package", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(tprint("%1/src", root), recursive = true));
    expect(write_entire_file(tprint("%1/package.jai", root),
        "PACKAGE :: Package.{\n    name    = \"cache-e2e\",\n    version = \"0.1.0\",\n    type    = .BIN,\n};\n"));
    source1 := "#import \"Testing\";\n\nadd :: (a: s32, b: s32) -> s32 {\n    return a + b;\n}\n\ntest \"addition\" {\n    expect_eq(add(2, 3), 5);\n}\n";
    expect(write_entire_file(tprint("%1/src/check.jai", root), source1));

    root_abs := lexical_absolute_path(root);
    juice := juice_exe();
    result1, output1, _, _ := run_command(juice, "test", working_directory = root_abs, capture_and_return_output = true);
    expect(expect_exit("cache-change-1", result1, 0));
    expect(output_matches("cache-change-1", output1, string.["[juice Test] Found 1 tests; compiling test program...", "1 passed, 0 failed\n"]));

    key1 := transpile_view_key("src/check.jai", source1, .EXPAND, Load_Target.[], JUICE_VERSION);
    transpile_dir := tprint("%1/target/transpile", root_abs);
    view1 := transpile_view_path(transpile_dir, key1, "src/check.jai");
    expect(path_exists_as_regular_file(view1));

    source2 := tprint("%1\ntest \"subtraction\" {\n    expect_eq(add(5, 2), 7);\n}\n", source1);
    expect(write_entire_file(tprint("%1/src/check.jai", root), source2));
    result2, output2, _, _ := run_command(juice, "test", working_directory = root_abs, capture_and_return_output = true);
    expect(expect_exit("cache-change-2", result2, 0));
    expect(output_matches("cache-change-2", output2, string.["[juice Test] Found 2 tests; compiling test program...", "2 passed, 0 failed\n"]));

    key2 := transpile_view_key("src/check.jai", source2, .EXPAND, Load_Target.[], JUICE_VERSION);
    expect(key1 != key2);
    view2 := transpile_view_path(transpile_dir, key2, "src/check.jai");
    expect(path_exists_as_regular_file(view2));
    // No active cleanup: the stale hash directory stays until `clean`.
    expect(path_exists_as_regular_file(view1));
}

// Clean recursively deletes the whole target directory, which covers the
// transpile subtree (no residue, no separate cleanup path).
test "E2E: clean removes the transpile cache with the target directory" {
    result, output, _ := run_juice_test("test-package");
    expect(expect_exit("clean-setup", result, 0));
    transpile_dir := tprint("%1/tests/data/test-package/target/transpile", juice_root());
    expect(path_exists_as_directory(transpile_dir));

    juice := juice_exe();
    fixture_abs := tprint("%1/tests/data/test-package", juice_root());
    clean_result, _, _, _ := run_command(juice, "clean", working_directory = fixture_abs, capture_and_return_output = true);
    expect(expect_exit("clean", clean_result, 0));
    // file_exists stays silent on missing paths, unlike the path_safety
    // inspection which logs "Unable to open directory" for them.
    expect(!file_exists(transpile_dir));
    expect(!file_exists(tprint("%1/tests/data/test-package/target", juice_root())));
}
