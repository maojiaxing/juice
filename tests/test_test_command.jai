#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
#import "Juice";
#import "Testing";

// ---------------------------------------------------------------------------
// Tests for the `juice test` pipeline (tickets 0018/0019). The in-process
// tests drive the orchestration seam with recording fakes (transpile step
// called per file, fake views flow into the generated driver, compile seam
// receives the generated products) and exercise the full discovery scan
// (exclusion set, member boundaries, links, deterministic order); the child
// scenarios run the real juice.exe end to end on the fixture packages under
// tests/data/ (all-pass, failing, pattern filtering, zero tests, zero
// matches, discovery exclusions, member-as-own-root, byte-stable repeats)
// and verify exit codes plus the exact output contract ([juice Test] phase
// line, [test] start lines, mapped failure coordinates, N passed M failed
// summary).
// ---------------------------------------------------------------------------

// Absolute path of juice.exe in the repository's target directory. The package
// root comes from juice_root() (defined in test_commands.jai): the test
// program executes at compile time, where the working directory is the entry
// file's directory (target/transpile), not the package root.
test_command_juice_exe :: () -> string {
    return tprint("%1/target/juice.exe", juice_root());
}

// ---------------------------------------------------------------------------
// Recording fakes over the orchestration seam
// ---------------------------------------------------------------------------

test_transpiled_files: [..] Test_Source_File;
test_transpiled_numbers: [..] s64;
test_fake_tests_per_file: s64 = 1;
test_fake_diagnostic: string = "";

// Each file yields test_count tests named "<rel> test <n>" plus, optionally,
// one canned diagnostic (for the rejection path). The key is canned too (flat
// by construction): the orchestration only feeds it through the pure path
// function.
fake_key :: (rel: string) -> string {
    result := copy_string(rel);
    for i: 0..result.count-1 {
        if result[i] == #char "/" result[i] = #char "_";
    }
    return tprint("key-%1", result);
}

fake_transpile :: (file: Test_Source_File, next_test_number: s64) -> Test_File_Output {
    array_add(*test_transpiled_files, file);
    array_add(*test_transpiled_numbers, next_test_number);
    output: Test_File_Output;
    output.view = tprint("// fake view of %1\n", file.rel_path);
    output.key = fake_key(file.rel_path);
    for i: 0..test_fake_tests_per_file-1 {
        entry: Test_Entry;
        entry.name = tprint("%1 test %2", file.rel_path, i);
        entry.number = next_test_number + i;
        array_add(*output.tests, entry);
    }
    if test_fake_diagnostic != "" {
        array_add(*output.diagnostics, .{line = 3, column = 1, message = test_fake_diagnostic});
    }
    return output;
}

test_compile_calls: s64;
test_compile_transpile_dir: string;
test_compile_driver_path: string;
test_compile_metaprogram_path: string;
test_seam_compile_success: bool;

fake_compile :: (driver: *Build_Driver, transpile_dir: string, driver_path: string, metaprogram_path: string) -> bool {
    test_compile_calls += 1;
    test_compile_transpile_dir = transpile_dir;
    test_compile_driver_path = driver_path;
    test_compile_metaprogram_path = metaprogram_path;
    return test_seam_compile_success;
}

seam_files :: () -> [] Test_Source_File {
    return Test_Source_File.[
        .{rel_path = "src/a.jai", abs_path = "seam-root/src/a.jai"},
        .{rel_path = "src/b.jai", abs_path = "seam-root/src/b.jai"},
    ];
}

seam_prepared :: (root := "") -> Prepared_Workspace {
    prepared: Prepared_Workspace;
    seam_root := root;
    if seam_root == "" seam_root = tprint("%1/target/seam-root", juice_root());
    prepared.discovery.root_dir = seam_root;
    return prepared;
}

reset_seam_test :: () {
    delete_directory_full(tprint("%1/target/seam-root", juice_root()));
    array_reset(*test_transpiled_files);
    array_reset(*test_transpiled_numbers);
    test_fake_tests_per_file = 1;
    test_fake_diagnostic = "";
    test_compile_calls = 0;
    test_compile_transpile_dir = "";
    test_compile_driver_path = "";
    test_compile_metaprogram_path = "";
    test_seam_compile_success = true;
}

file_contains :: (path: string, needle: string) -> bool {
    content, ok := read_entire_file(path);
    if !ok return false;
    return find_index_from_left(content, needle) >= 0;
}

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

// Creates a directory/file link with mklink. Returns false when the machine
// refuses link creation (needs developer mode or elevation).
make_test_link :: (link: string, target: string, directory: bool, junction: bool) -> bool {
    args: [..] string;
    array_add(*args, "cmd");
    array_add(*args, "/c");
    array_add(*args, "mklink");
    if junction {
        array_add(*args, "/J");
    } else if directory {
        array_add(*args, "/D");
    }
    // Backslashes throughout: cmd's builtin mklink parses forward-slash
    // path segments as option switches (same reason rmdir calls do).
    array_add(*args, path_backslashes(link));
    array_add(*args, path_backslashes(target));
    result := run_command(..args);
    return result.exit_code == 0;
}

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
// E2E child scenarios (real juice.exe on the fixture packages)
// ---------------------------------------------------------------------------

run_juice_test :: (fixture: string, pattern := "") -> Process_Result, string, string {
    juice := test_command_juice_exe();
    fixture_abs := tprint("%1/tests/data/%2", juice_root(), fixture);
    args: [..] string;
    array_add(*args, juice);
    array_add(*args, "test");
    if pattern != "" array_add(*args, pattern);
    result, output, errors, _ := run_command(..args, working_directory = fixture_abs, capture_and_return_output = true);
    return result, output, errors;
}

expect_exit :: (name: string, result: Process_Result, want: s32) -> bool {
    if result.type == .EXITED && result.exit_code == want return true;
    print("[child %1] exit result %2/%3, want %4\n", name, result.type, result.exit_code, want);
    return false;
}

// Normalize CRLF to LF so expected blocks are compared line by line
// regardless of the child process's native line endings.
normalize_crlf :: (s: string) -> string {
    has_cr := false;
    for ch: s {
        if ch == #char "\r" {
            has_cr = true;
            break;
        }
    }
    if !has_cr return s;
    builder: String_Builder;
    cursor := 0;
    i := 0;
    while i < s.count {
        if s[i] == #char "\r" {
            print_to_builder(*builder, "%", slice(s, cursor, i - cursor));
            print_to_builder(*builder, "\n");
            if i + 1 < s.count && s[i+1] == #char "\n" i += 1;
            cursor = i + 1;
        }
        i += 1;
    }
    if cursor < s.count print_to_builder(*builder, "%", slice(s, cursor, s.count - cursor));
    return builder_to_string(*builder);
}

output_matches :: (name: string, output: string, needles: [] string, want := true) -> bool {
    normalized := normalize_crlf(output);
    for needle: needles {
        found := find_index_from_left(normalized, needle) >= 0;
        if found != want {
            print("[child %1] output %2 '%3'\n", name, ifx found then "unexpectedly contains" else "missing", needle);
            print("  output was:\n%\n", output);
            return false;
        }
    }
    return true;
}

// 1-based line/column of the first occurrence of `needle` in `file`.
fixture_line_col :: (file: string, needle: string) -> (line: s64, col: s64) {
    source, ok := read_entire_file(file);
    if !ok return 0, 0;
    index := find_index_from_left(source, needle);
    if index < 0 return 0, 0;
    line := 1;
    line_start := 0;
    for i: 0..index-1 {
        if source[i] == #char "\n" {
            line += 1;
            line_start = i + 1;
        }
    }
    return line, index - line_start + 1;
}

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
// regenerated driver.jai / first.jai products.
Cache_Dir_Scan :: struct {
    dirs:  [..] string;
    files: [..] string;
}

cache_dir_scan_visitor :: (info: *File_Visit_Info, scan: *Cache_Dir_Scan) {
    if info.is_directory {
        array_add(*scan.dirs, copy_string(info.short_name));
    } else {
        array_add(*scan.files, copy_string(info.short_name));
    }
}

sort_strings :: (items: [] string) {
    for i: 1..items.count-1 {
        if i >= items.count break;
        key := items[i];
        j := i - 1;
        while j >= 0 && compare(items[j], key) > 0 {
            items[j+1] = items[j];
            j -= 1;
        }
        items[j+1] = key;
    }
}

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

cache_dir_entries :: (dir: string) -> (Cache_Dir_Scan, bool) {
    scan: Cache_Dir_Scan;
    visited := visit_files(dir, false, *scan, cache_dir_scan_visitor, visit_files = true, visit_directories = true);
    return scan, visited;
}

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
