#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
#import "Juice";

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
    prerequisites = string.["prepare-workspace"],
    visible       = true,
    handler       = test_command,
    validate_arguments = test_arguments_are_valid,
};

test_arguments_are_valid :: (arguments: [] string) -> bool {
    return arguments.count <= 1;
}

test_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if !command_arguments_are_valid(TEST_COMMAND, arguments) return false;
    prepared := get_prepared_workspace(*ctx.workspace);
    if prepared == null {
        print("[juice ERROR] Command 'test' requires workspace preparation.\n");
        return false;
    }
    pattern := ifx arguments.count == 1 then arguments[0] else "";
    files, ok := collect_test_files(ctx.driver, prepared);
    if !ok return false;
    return test_prepared_workspace(ctx.driver, prepared, pattern, files);
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

compile_test_program :: (driver: *Build_Driver, transpile_dir: string, driver_path: string, metaprogram_path: string) -> bool {
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
// recording fakes, exactly like the build compile seam.
test_prepared_workspace :: (
    driver: *Build_Driver,
    prepared: *Prepared_Workspace,
    pattern: string,
    files: [] Test_Source_File,
    transpile: #type (file: Test_Source_File, next_test_number: s64) -> Test_File_Output = transpile_test_file,
    compile: #type (driver: *Build_Driver, transpile_dir: string, driver_path: string, metaprogram_path: string) -> bool = compile_test_program
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
    transpile_dir := test_transpile_dir(prepared);
    view_paths: [..] string;
    for file, index: files {
        array_add(*view_paths, transpile_view_path(transpile_dir, outputs[index].key, file.rel_path));
    }

    // 4. Testing 断言模块特例（票 0033）：模块源文件内联 test block 后不可
    //    被 jai 直接编译，生成器把 `#import "Testing"` 的解析目标换成生成
    //    的编译视图（metaprogram 的 import_path 前置其目录，同一模块只加
    //    载一份，全局计数不分裂）。package 自身的 modules/Testing.jai 存
    //    在时（in_package），视图用 EXPAND 模式并追加 `#load` test_support
    //    视图——模块是密封作用域（how_to 151），模块内 #load 的文件挂模块
    //    的 Module scope，自测块引用测试支撑声明由此可见；其测试块同时收
    //    进测试列表（全局编号续接）。用户 package 无此文件时视图用 STRIP
    //    模式（test-free，断言语义同源文件），测试报告与计数零变更。模块
    //    test-free 时走原路径（原样 #import 模块源文件）。
    module_file, module_in_package := testing_module_source(prepared);
    use_testing_view := false;
    module_source := "";
    if module_file.abs_path != "" {
        source, ok := read_entire_file(module_file.abs_path);
        if ok {
            module_source = source;
            if source_has_test_block(source) use_testing_view = true;
        }
    }
    testing_module_view := "";
    module_view := "";
    if use_testing_view {
        if module_in_package {
            // package 自身的模块：EXPAND 视图（编号续接全局序列），自测块
            // 进测试列表。
            module_result := transpile_test_file(module_file, next_number);
            if module_result.diagnostics.count > 0 {
                for diagnostic: module_result.diagnostics {
                    print("[juice ERROR] %1:%2,%3: %4\n", module_file.rel_path, diagnostic.line, diagnostic.column, diagnostic.message);
                }
                return false;
            }
            module_view = module_result.view;
            for entry: module_result.tests {
                if pattern == "" || find_index_from_left(entry.name, pattern) >= 0 {
                    array_add(*matches, entry);
                }
            }
            next_number += module_result.tests.count;
            // EXPAND 编译视图追加自测支撑段：模块是密封作用域（how_to
            // 151），自测块引用的 helper 必须驻模块自身作用域。test_support
            // 视图整体内嵌会把其 #import 链与声明挂进模块 export 列表（与
            // driver #load 的同一视图在 Application 重复），因此只切取
            // Testing 自测段（helper 声明与记录全局），并配文件级 import
            // 与自足 root（见 testing_module_support_block）。
            support_view_text := "";
            for f, index: files {
                if f.rel_path == "src/test_support.jai" support_view_text = outputs[index].view;
            }
            if support_view_text == "" {
                print("[juice ERROR] Testing 自测需要 src/test_support.jai 视图，但未发现该文件。\n");
                return false;
            }
            support_block := testing_module_support_block(support_view_text);
            if support_block == "" {
                print("[juice ERROR] src/test_support.jai 缺少 Testing 自测段标记。\n");
                return false;
            }
            module_view = tprint("%1\n\n%2", module_view, support_block);
        } else {
            // 用户 package 的断言模块来源：STRIP 视图（test-free 编译视图）。
            strip_ctx: Transpile_Context;
            strip_ctx.mode = .STRIP;
            strip_ctx.path = module_file.rel_path;
            stripped := transpile_source(module_source, strip_ctx);
            if stripped.diagnostics.count > 0 {
                for diagnostic: stripped.diagnostics {
                    print("[juice ERROR] %1:%2,%3: %4\n", module_file.rel_path, diagnostic.line, diagnostic.column, diagnostic.message);
                }
                return false;
            }
            module_view = stripped.view;
        }
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

    // 5. The Testing module compile view: a session product like driver.jai
    //    (regenerated on every run, never cached — its content is the module
    //    view plus the driver-specific support block, not the pure transpile
    //    output). Its directory is prepended to the metaprogram's import
    //    path, so every `#import "Testing"` resolves to this file. It lives
    //    under target/ directly — outside the transpile tree, whose direct
    //    children the cache-tree tests assert to be exactly the hash
    //    directories plus driver.jai/first.jai.
    testing_module_dir := "";
    if use_testing_view {
        testing_module_dir = to_forward_slashes(tprint("%1/target/testing-module", prepared.discovery.root_dir));
        if !make_directory_if_it_does_not_exist(testing_module_dir, recursive = true) {
            print("[juice ERROR] Could not create Testing module view directory: %\n", testing_module_dir);
            return false;
        }
        testing_module_view = to_forward_slashes(tprint("%1/Testing.jai", testing_module_dir));
        if !write_entire_file(testing_module_view, module_view) {
            print("[juice ERROR] Could not write Testing module view.\n");
            return false;
        }
    }

    // 6. Driver and metaprogram are products of this run's test list, so
    //    they are regenerated and written on every run, never cached.
    driver_path := tprint("%1/driver.jai", transpile_dir);
    metaprogram_path := tprint("%1/first.jai", transpile_dir);
    if !write_entire_file(driver_path, generate_test_driver(files, view_paths, matches, testing_module_view)) {
        print("[juice ERROR] Could not write test driver.\n");
        return false;
    }
    if !write_entire_file(metaprogram_path, generate_test_metaprogram(driver_path, juice_modules_dir(), tprint("%1/target", prepared.discovery.root_dir), testing_module_dir)) {
        print("[juice ERROR] Could not write test metaprogram.\n");
        return false;
    }
    return compile(driver, transpile_dir, driver_path, metaprogram_path);
}

// The Testing assertion module's source file for the generator special case
// (ticket 0033): the package's own modules/Testing.jai when present
// (in_package = true, its self-test blocks join the test list), otherwise
// the module next to the running executable (user packages). Returns an
// empty abs_path when no module exists. The rel_path is always
// "modules/Testing.jai": the module view's file name must stay Testing.jai
// so the import path resolves it as the Testing module.
testing_module_source :: (prepared: *Prepared_Workspace) -> (file: Test_Source_File, in_package: bool) {
    rel := "modules/Testing.jai";
    pkg_path := tprint("%1/%2", prepared.discovery.root_dir, rel);
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
// (ticket 0033): file-scoped imports plus the Testing self-test segment of
// the test support view, under #scope_file so the declarations stay in the
// module compile view's file scope (they must not enter the module's export
// list — the driver #loads the same view into the application scope and
// duplicates there would clash). The segment's helpers call juice_root();
// the test support file's own juice_root depends on src/path_safety
// declarations the sealed module cannot see, so the block provides a
// self-contained root instead: the test metaprogram sets intermediate_path
// to the package target directory (absolute), so stripping the tail yields
// the package root without path normalization. Returns "" when the segment
// marker is missing.
testing_module_support_block :: (support_view: string) -> string {
    marker := "// tests/test_testing.jai 顶层迁移";
    pos := find_index_from_left(support_view, marker);
    if pos < 0 return "";
    // Back to the start of the marker's line, then to the start of the
    // separator line above it.
    while pos > 0 && support_view[pos - 1] != #char "\n" pos -= 1;
    if pos > 0 {
        pos -= 1;
        while pos > 0 && support_view[pos - 1] != #char "\n" pos -= 1;
    }
    // The segment ends where the next migration section begins.
    end_marker := "// tests/test_transpiler.jai 顶层迁移";
    end_pos := find_index_from_left(support_view, end_marker);
    if end_pos < 0 {
        end_pos = support_view.count;
    } else {
        while end_pos > 0 && support_view[end_pos - 1] != #char "\n" end_pos -= 1;
    }
    segment := slice(support_view, pos, end_pos - pos);

    builder: String_Builder;
    print_to_builder(*builder, "#scope_file;\n");
    print_to_builder(*builder, "#import \"Basic\";\n");
    print_to_builder(*builder, "#import \"Compiler\";\n");
    print_to_builder(*builder, "#import \"File\";\n");
    print_to_builder(*builder, "#import \"Process\";\n");
    print_to_builder(*builder, "#import \"String\";\n");
    print_to_builder(*builder, "\n");
    print_to_builder(*builder, "juice_root :: () -> string {\n");
    print_to_builder(*builder, "    options := get_build_options();\n");
    print_to_builder(*builder, "    root := path_strip_filename(options.intermediate_path);\n");
    print_to_builder(*builder, "    while root.count > 0 && (root[root.count - 1] == #char \"/\" || root[root.count - 1] == #char \"\\\\\") root.count -= 1;\n");
    print_to_builder(*builder, "    return root;\n");
    print_to_builder(*builder, "}\n");
    print_to_builder(*builder, "\n");
    print_to_builder(*builder, "%", segment);
    return builder_to_string(*builder);
}

// The transpile subtree root: views, driver and metaprogram all live under
// <package root>/target/transpile/ (Target directory, CONTEXT.md). Derived
// from the package root because Test consumes the prepared workspace without
// the artifact plan (LIB packages have none).
test_transpile_dir :: (prepared: *Prepared_Workspace) -> string {
    return to_forward_slashes(tprint("%1/target/transpile", prepared.discovery.root_dir));
}

juice_modules_dir :: () -> string {
    exe_path := get_path_of_running_executable();
    bin_dir := path_strip_filename(exe_path);
    if bin_dir.count > 0 && bin_dir[bin_dir.count - 1] == #char "/" bin_dir.count -= 1;
    return to_forward_slashes(tprint("%1/../modules", bin_dir));
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

// Metaprogram (docs/transpiled-output-formatting.md §3): NO_OUTPUT so the
// test program has no entry point, import_path gets the Testing module
// directory, intermediate_path is the package target directory (compiler
// intermediates land under target/, not a .build directory next to the
// metaprogram), and the driver is added after the intercept begins. The
// message loop only consumes messages — the current jai exits non-zero on
// its own when an intercepted workspace has errors, and calling exit() from
// a metaprogram would kill the process before jai flushes the collected
// print output (ticket 0015 finding).
//
// testing_view_dir (ticket 0033 special case, default "" = off): when the
// Testing module source contains inline test blocks it cannot be compiled
// directly; the directory holding its EXPAND view (which contains a file
// named Testing.jai) is prepended to the import path, so `#import "Testing"`
// resolves to the view instead of the module source file.
generate_test_metaprogram :: (driver_path: string, modules_dir: string, target_dir: string, testing_view_dir: string = "") -> string {
    builder: String_Builder;
    print_to_builder(*builder, "#import \"Basic\";\n");
    print_to_builder(*builder, "#import \"Compiler\";\n\n");
    print_to_builder(*builder, "#run {\n");
    print_to_builder(*builder, "    set_build_options_dc(.{do_output = false});\n");
    print_to_builder(*builder, "    workspace := compiler_create_workspace(\"Juice Test Program\");\n");
    print_to_builder(*builder, "    if !workspace return;\n");
    print_to_builder(*builder, "    options := get_build_options(workspace);\n");
    print_to_builder(*builder, "    options.output_type = .NO_OUTPUT;\n");
    print_to_builder(*builder, "    options.intermediate_path = %1;\n", quote_jai_string(to_forward_slashes(target_dir)));
    print_to_builder(*builder, "    import_paths: [..] string;\n");
    print_to_builder(*builder, "    array_add(*import_paths, .. options.import_path);\n");
    if testing_view_dir != "" {
        print_to_builder(*builder, "    array_add(*import_paths, %1);\n", quote_jai_string(testing_view_dir));
    }
    print_to_builder(*builder, "    array_add(*import_paths, %1);\n", quote_jai_string(modules_dir));
    print_to_builder(*builder, "    options.import_path = import_paths;\n");
    print_to_builder(*builder, "    set_build_options(options, workspace);\n");
    print_to_builder(*builder, "    compiler_begin_intercept(workspace);\n");
    print_to_builder(*builder, "    add_build_file(%1, workspace);\n", quote_jai_string(driver_path));
    print_to_builder(*builder, "    while true {\n");
    print_to_builder(*builder, "        msg := compiler_wait_for_message();\n");
    print_to_builder(*builder, "        if !msg continue;\n");
    print_to_builder(*builder, "        if msg.workspace == workspace {\n");
    print_to_builder(*builder, "            if msg.kind == {\n");
    print_to_builder(*builder, "                case .ERROR;\n");
    print_to_builder(*builder, "                case .COMPLETE;\n");
    print_to_builder(*builder, "                    break;\n");
    print_to_builder(*builder, "            }\n");
    print_to_builder(*builder, "        }\n");
    print_to_builder(*builder, "    }\n");
    print_to_builder(*builder, "    compiler_end_intercept(workspace);\n");
    print_to_builder(*builder, "}\n");
    return builder_to_string(*builder);
}

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
collect_test_files :: (driver: *Build_Driver, prepared: *Prepared_Workspace) -> [] Test_Source_File, bool {
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
