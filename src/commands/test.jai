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

    // 2. Empty semantics (issues/0006): no test blocks, or a pattern that
    //    matches nothing, succeed with an explanation and skip the build.
    if next_number == 1 {
        print("[juice Test] No tests found.\n");
        return true;
    }
    if matches.count == 0 {
        print("[juice Test] No tests matched '%'.\n", pattern);
        return true;
    }

    print("[juice Test] Found %1 tests; compiling test program...\n", matches.count);

    // 3. Views land content-addressed under target/transpile/<hash>/<rel>
    //    (ticket 0020): every path derives from the per-file key the
    //    transpile step returned; an existing view is a cache hit and stays
    //    untouched (content addressing makes stale views unreachable, so
    //    there is nothing to invalidate or clean), a missing one is written
    //    with the package-relative structure mirrored inside the hash
    //    directory.
    transpile_dir := test_transpile_dir(prepared);
    view_paths: [..] string;
    for file, index: files {
        array_add(*view_paths, transpile_view_path(transpile_dir, outputs[index].key, file.rel_path));
    }
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

    // 4. Driver and metaprogram are products of this run's test list, so
    //    they are regenerated and written on every run, never cached.
    driver_path := tprint("%1/driver.jai", transpile_dir);
    metaprogram_path := tprint("%1/first.jai", transpile_dir);
    if !write_entire_file(driver_path, generate_test_driver(files, view_paths, matches)) {
        print("[juice ERROR] Could not write test driver.\n");
        return false;
    }
    if !write_entire_file(metaprogram_path, generate_test_metaprogram(driver_path, juice_modules_dir(), tprint("%1/target", prepared.discovery.root_dir))) {
        print("[juice ERROR] Could not write test metaprogram.\n");
        return false;
    }
    return compile(driver, transpile_dir, driver_path, metaprogram_path);
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
generate_test_driver :: (files: [] Test_Source_File, view_paths: [] string, matches: [] Test_Entry) -> string {
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
generate_test_metaprogram :: (driver_path: string, modules_dir: string, target_dir: string) -> string {
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

// ---------------------------------------------------------------------------
// 内联测试（票 0034 自旧 tests/ 迁移）：`juice test` 管道
// 的编排 seam（记录 fake：转译步骤按文件调用、fake 视图流入生成的 driver、
// compile seam 收到生成产物）、全量 discovery 扫描（排除集、member 边界、
// 链接跳过、确定性顺序）与 fixture package 的 E2E child 场景。共享声明
// （test_command_juice_exe、seam 记录 fake 与记录全局、缓存树扫描 helper、
// E2E child 场景 helper）见 src/test_support.jai。
// ---------------------------------------------------------------------------

test "Seam: transpile step drives fake views into a compiled driver" {
    reset_seam_test();
    driver: Build_Driver;
    prepared := seam_prepared();
    expect(test_prepared_workspace(*driver, *prepared, "", seam_files(), fake_transpile, fake_compile));

    // The transpile step ran once per file with the running global number.
    expect(test_transpiled_files.count == 2);
    expect(test_transpiled_files[0].rel_path == "src/a.jai" && test_transpiled_files[1].rel_path == "src/b.jai");
    expect(test_transpiled_numbers[0] == 1 && test_transpiled_numbers[1] == 2);

    // The fake views were written content-addressed into the transpile tree,
    // mirroring the package structure inside the key directory.
    transpile_dir := test_transpile_dir(*prepared);
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
    driver: Build_Driver;
    prepared := seam_prepared();
    transpile_dir := test_transpile_dir(*prepared);
    stale_path := tprint("%1/%2/src/a.jai", transpile_dir, fake_key("src/a.jai"));
    expect(make_directory_if_it_does_not_exist(path_strip_filename(stale_path), recursive = true));
    expect(write_entire_file(stale_path, "// stale cached view\n"));

    expect(test_prepared_workspace(*driver, *prepared, "", seam_files(), fake_transpile, fake_compile));

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
    driver: Build_Driver;
    prepared := seam_prepared();
    expect(test_prepared_workspace(*driver, *prepared, "b.jai", seam_files(), fake_transpile, fake_compile));
    driver_path := tprint("%1/driver.jai", test_transpile_dir(*prepared));
    expect(test_compile_calls == 1);
    expect(file_contains(driver_path, "run(\"src/b.jai test 0\", juice_test_2);"));
    expect(!file_contains(driver_path, "run(\"src/a.jai test 0\", juice_test_1);"));
    delete_directory_full(tprint("%1/target/seam-root", juice_root()));
}

test "Seam: zero matches skip the compile" {
    reset_seam_test();
    driver: Build_Driver;
    prepared := seam_prepared();
    expect(test_prepared_workspace(*driver, *prepared, "nomatch", seam_files(), fake_transpile, fake_compile));
    delete_directory_full(tprint("%1/target/seam-root", juice_root()));
    expect(test_compile_calls == 0);
}

test "Seam: zero tests skip the compile" {
    reset_seam_test();
    driver: Build_Driver;
    prepared := seam_prepared();
    test_fake_tests_per_file = 0;
    expect(test_prepared_workspace(*driver, *prepared, "", seam_files(), fake_transpile, fake_compile));
    delete_directory_full(tprint("%1/target/seam-root", juice_root()));
    expect(test_compile_calls == 0);
}

test "Seam: transpile diagnostics fail before compiling" {
    reset_seam_test();
    driver: Build_Driver;
    prepared := seam_prepared();
    test_fake_diagnostic = "test block 仅允许文件顶层";
    expect(!test_prepared_workspace(*driver, *prepared, "", seam_files(), fake_transpile, fake_compile));
    delete_directory_full(tprint("%1/target/seam-root", juice_root()));
    expect(test_compile_calls == 0);
}

test "Seam: compile failure propagates" {
    reset_seam_test();
    driver: Build_Driver;
    prepared := seam_prepared();
    test_seam_compile_success = false;
    result := test_prepared_workspace(*driver, *prepared, "", seam_files(), fake_transpile, fake_compile);
    delete_directory_full(tprint("%1/target/seam-root", juice_root()));
    expect(!result && test_compile_calls == 1);
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
    driver: Build_Driver;
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = tprint("%1/tests/data/test-package", juice_root());
    files, ok := collect_test_files(*driver, *prepared);
    expect(ok && files.count == 3);
    expect(files[0].rel_path == "src/main.jai");
    expect(files[1].rel_path == "src/math.jai");
    expect(files[2].rel_path == "tests/util_test.jai");
    for file: files {
        expect(file.abs_path == tprint("%1/tests/data/test-package/%2", juice_root(), file.rel_path));
    }
}

test "Collection rejects a missing package root" {
    driver: Build_Driver;
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = tprint("%1/tests/data/no-such-package", juice_root());
    _, ok := collect_test_files(*driver, *prepared);
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
    driver: Build_Driver;
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = tprint("%1/tests/data/scan-fixture", juice_root());
    prepared.discovery.member_packages = Package.[
        .{name = "scan-fixture", dir = prepared.discovery.root_dir},
        .{name = "member-a", dir = tprint("%1/tests/data/scan-fixture/member-a", juice_root())},
    ];
    files, ok := collect_test_files(*driver, *prepared);
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
// src/test_support.jai）。Returns false when the machine refuses link
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

    driver: Build_Driver;
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = lexical_absolute_path(root);
    files, ok := collect_test_files(*driver, *prepared);
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
    expect(TEST_COMMAND.name == "test" && TEST_COMMAND.visible);
    expect(TEST_COMMAND.usage == "juice test [pattern]");
    expect(TEST_COMMAND.prerequisites.count == 1 && TEST_COMMAND.prerequisites[0] == "prepare-workspace");
    expect(TEST_COMMAND.handler == test_command);
    expect(TEST_COMMAND.validate_arguments == test_arguments_are_valid);
    expect(TEST_COMMAND.validate_arguments(string.[]) && TEST_COMMAND.validate_arguments(string.["x"]));
    expect(!TEST_COMMAND.validate_arguments(string.["x", "y"]));
}

test "Test command argument and preparation guards" {
    ctx: Command_Context;
    expect(!TEST_COMMAND.handler(*ctx, string.["one", "two"]));
    // Zero arguments with an empty workspace state: the missing prepared
    // workspace must be reported without touching anything else.
    expect(!TEST_COMMAND.handler(*ctx, string.[]));
}

// ---------------------------------------------------------------------------
// E2E child scenarios (real juice.exe on the fixture packages)。Child 场景
// helper（run_juice_test、expect_exit、normalize_crlf、output_matches、
// fixture_line_col）见 src/test_support.jai。
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
// regenerated driver.jai / first.jai products。Cache_Dir_Scan 结构、
// cache_dir_scan_visitor、sort_strings、cache_dir_entries 见
// src/test_support.jai。

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
    scan, ok3 := cache_dir_entries(transpile_dir);
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
    scan2, ok4 := cache_dir_entries(transpile_dir);
    expect(ok4 && scan2.files.count == 2 && scan2.dirs.count == expected_keys.count);
    sort_strings(scan2.dirs);
    for i: 0..sorted_expected.count-1 {
        expect(scan2.dirs[i] == sorted_expected[i]);
        view_path := transpile_view_path(transpile_dir, expected_keys[i], rel_files[i]);
        view, ok5 := read_entire_file(view_path);
        expect(ok5 && view == expected_views[i]);
    }
}

// cache_dir_entries 见 src/test_support.jai。

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
    juice := test_command_juice_exe();
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

    juice := test_command_juice_exe();
    fixture_abs := tprint("%1/tests/data/test-package", juice_root());
    clean_result, _, _, _ := run_command(juice, "clean", working_directory = fixture_abs, capture_and_return_output = true);
    expect(expect_exit("clean", clean_result, 0));
    // file_exists stays silent on missing paths, unlike the path_safety
    // inspection which logs "Unable to open directory" for them.
    expect(!file_exists(transpile_dir));
    expect(!file_exists(tprint("%1/tests/data/test-package/target", juice_root())));
}
