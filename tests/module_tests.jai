#import "Basic";
#import "Testing";
#import "File_Utilities";
#import "Process";
#import "String";

// (The JAI_COMPILER_VERSION pre-resolution anchor — the ticket 016
// deviation 2 deadlock guard — is retired by ticket 017: the suite no
// longer references the #run constant in-process; version_tests' E2E child
// pins the baked value byte for byte.)

// ---------------------------------------------------------------------------
// Struct face tests: exercise src/module.jai — otter's own definition source
// for the package declaration compatibility face (spec section 2.1). The
// declarations enter this test program's application scope through Test
// discovery's full-package scan (the same mechanism that compiles src
// inline tests); this file deliberately never #imports "Juice", so every
// assertion pins otter's definition-source declarations (the src
// implementations consume the published face through the Juice binding).
// ---------------------------------------------------------------------------

test "Face: zero-value Package carries the declared defaults" {
    pkg: Package;
    expect(pkg.name == "");
    expect(pkg.version == "");
    expect(pkg.type == .UNSPECIFIED);
    expect(pkg.description == "");
    expect(pkg.build_script == "");
    expect(pkg.targets.count == 0);
    expect(pkg.dependencies.count == 0);
    expect(pkg.workspace.members.count == 0);
    expect(pkg.workspace.exclude.count == 0);
    expect(pkg.plugins.count == 0);
    expect(pkg.dir == "");
}

test "Face: Package_Type values match the protocol numbering" {
    // The evaluator prints the enum's integer value as the TYPE record;
    // these numbers are part of the protocol (LIB=0, BIN=1, UNSPECIFIED=2).
    expect(cast(s64) Package_Type.LIB == 0);
    expect(cast(s64) Package_Type.BIN == 1);
    expect(cast(s64) Package_Type.UNSPECIFIED == 2);

    pkg: Package;
    pkg.type = .BIN;
    expect(cast(s64) pkg.type == 1);
    pkg.type = .LIB;
    expect(cast(s64) pkg.type == 0);
}

test "Face: Dependency fields default to empty strings" {
    dep: Dependency;
    expect(dep.name == "");
    expect(dep.version == "");
    expect(dep.source == "");
    expect(dep.package == "");
}

test "Face: a full literal declaration round-trips" {
    // The exact literal shape a package.jai author writes (slice fields
    // accept fixed-array literals by decay) — every field reads back.
    pkg := Package.{
        name         = "face-fixture",
        version      = "0.9.0",
        type         = .BIN,
        description  = "A full declaration.",
        build_script = "build.py",
        plugins      = .[
            .{ id = "load",       version = "1" },
            .{ id = "test-block", version = "2" },
        ],
        targets      = Target.[
            .{ name = "app", main_file = "src/main.jai" },
        ],
        dependencies = Dependency.[
            .{ name = "dep_a", version = "0.1", source = "",        package = "" },
            .{ name = "dep_b", version = "0.2", source = "../sib",  package = "renamed" },
        ],
        workspace    = .{ members = string.["packages/a", "packages/b"], exclude = string.["packages/skip"] },
    };

    expect(pkg.name == "face-fixture");
    expect(pkg.version == "0.9.0");
    expect(pkg.type == .BIN);
    expect(pkg.description == "A full declaration.");
    expect(pkg.build_script == "build.py");
    expect(pkg.plugins.count == 2);
    expect(pkg.plugins[0].id == "load" && pkg.plugins[0].version == "1");
    expect(pkg.plugins[1].id == "test-block" && pkg.plugins[1].version == "2");
    expect(pkg.plugins[0].options.count == 0);
    expect(pkg.targets.count == 1);
    expect(pkg.targets[0].name == "app" && pkg.targets[0].main_file == "src/main.jai");
    expect(pkg.dependencies.count == 2);
    expect(pkg.dependencies[0].name == "dep_a" && pkg.dependencies[0].version == "0.1"
        && pkg.dependencies[0].source == "" && pkg.dependencies[0].package == "");
    expect(pkg.dependencies[1].name == "dep_b" && pkg.dependencies[1].version == "0.2"
        && pkg.dependencies[1].source == "../sib" && pkg.dependencies[1].package == "renamed");
    expect(pkg.workspace.members.count == 2);
    expect(pkg.workspace.members[0] == "packages/a" && pkg.workspace.members[1] == "packages/b");
    expect(pkg.workspace.exclude.count == 1 && pkg.workspace.exclude[0] == "packages/skip");
    expect(pkg.dir == "");
}

test "Face: built-in plugin id constants" {
    // The v1 built-in id set (the manifest declaration gate's allowlist
    // during Phase 1; member plugin ids join it in Phase 2).
    expect(TRANSPILE_PLUGIN_LOAD_ID == "load");
    expect(TRANSPILE_PLUGIN_TEST_BLOCK_ID == "test-block");
}

test "Face: plugin declaration options are typed rows" {
    decl: Plugin_Declaration;
    decl.id = "load";
    decl.version = "1";
    rows: [..] Plugin_Option;
    array_add(*rows, .{ key = "k", value = "v" });
    decl.options = rows;
    expect(decl.options.count == 1);
    expect(decl.options[0].key == "k" && decl.options[0].value == "v");
}

// ---------------------------------------------------------------------------
// Testing API surface tests (ticket 016): the expect/expect_eq/fail/run/
// finish/path_mapping contract exercised through both faces otter carries at
// runtime — the definition source's prefixed public names (src/module.jai,
// entering this program through Test discovery's full-package scan) and the
// imported Testing face (`#import "Testing"`: the published flat face in the
// self-hosted loop, ticket 005; the prefixed names stay as the publication
// transform's input and keep their unit tests — spec 006 decision 3). The
// in-process pairs drive both faces through the state semantics (the
// reference Testing module's own self-test matrix, mirrored one scenario at
// a time); the child scenarios below drive the printed-format contract
// (start lines, failure coordinates, the path_mapping rewrite, the summary)
// through a generated driver that imports the published Testing face and
// #loads the fixture — the published bare-face single-leg shape (ticket 036
// retired the sibling repository comparison harness; nothing here reads the
// old repository).
//
// The drain discipline is the reference module's: every state test starts by
// draining both faces' registers into the failure accumulators, so a test
// that aborts mid-way cannot mask its leftovers — the closing latch drains
// once more (the imported driver's finish()/assert gate covers only the
// imported face; the definition-source face has no driver gate) and checks
// both accumulators.
// ---------------------------------------------------------------------------

imported_testing_module_failures: s64 = 0;
definition_testing_module_failures: s64 = 0;

// The paired scenario procedures: one body per face per scenario. Jai has
// no closures, so the bodies touch globals instead of capturing locals (the
// same visibility model as transpiled test blocks).
g_definition_reached := false;
g_definition_first_reached := false;
g_definition_second_reached := false;
g_definition_defer_ran := false;
g_imported_reached := false;
g_imported_first_reached := false;
g_imported_second_reached := false;
g_imported_defer_ran := false;

definition_expect_pass :: () {
    Testing_expect(1 + 1 == 2);
    Testing_expect_eq("abc", "abc");
    Testing_expect_eq(2.5, 2.5);
    g_definition_reached = true;
}

imported_expect_pass :: () {
    expect(1 + 1 == 2);
    expect_eq("abc", "abc");
    expect_eq(2.5, 2.5);
    g_imported_reached = true;
}

definition_abort_first :: () {
    Testing_expect(3 > 4);
    g_definition_first_reached = true;
}

imported_abort_first :: () {
    expect(3 > 4);
    g_imported_first_reached = true;
}

definition_next_runs :: () {
    g_definition_second_reached = true;
}

imported_next_runs :: () {
    g_imported_second_reached = true;
}

definition_fail_always :: () {
    Testing_fail("always");
    g_definition_reached = true;
}

imported_fail_always :: () {
    fail("always");
    g_imported_reached = true;
}

definition_defer_abort :: () {
    defer g_definition_defer_ran = true;
    Testing_expect(1 == 2);
}

imported_defer_abort :: () {
    defer g_imported_defer_ran = true;
    expect(1 == 2);
}

definition_early_return :: () {
    x := 1;
    if x == 1 return;
    Testing_expect(false, "unreachable");
}

imported_early_return :: () {
    x := 1;
    if x == 1 return;
    expect(false, "unreachable");
}

definition_will_fail :: () {
    Testing_expect(false, "will-fail");
}

imported_will_fail :: () {
    expect(false, "will-fail");
}

test "Testing face: expect and expect_eq pass and continue (definition source vs imported face)" {
    imported_testing_module_failures += finish();
    definition_testing_module_failures += Testing_finish();
    g_definition_reached = false;
    g_imported_reached = false;

    Testing_run("t-expect-pass", definition_expect_pass);
    definition_n := Testing_finish();

    run("t-expect-pass", imported_expect_pass);
    imported_n := finish();

    expect(g_definition_reached && definition_n == 0);
    expect(g_imported_reached && imported_n == 0);
}

test "Testing face: failure aborts the current test, the suite continues (definition source vs imported face)" {
    imported_testing_module_failures += finish();
    definition_testing_module_failures += Testing_finish();
    g_definition_first_reached = false;
    g_definition_second_reached = false;
    g_imported_first_reached = false;
    g_imported_second_reached = false;

    Testing_run("t-abort", definition_abort_first);
    Testing_run("t-next", definition_next_runs);
    definition_n := Testing_finish();

    run("t-abort", imported_abort_first);
    run("t-next", imported_next_runs);
    imported_n := finish();

    expect(!g_definition_first_reached && g_definition_second_reached && definition_n == 1);
    expect(!g_imported_first_reached && g_imported_second_reached && imported_n == 1);
}

test "Testing face: fail always registers and aborts (definition source vs imported face)" {
    imported_testing_module_failures += finish();
    definition_testing_module_failures += Testing_finish();
    g_definition_reached = false;
    g_imported_reached = false;

    Testing_run("t-fail", definition_fail_always);
    definition_n := Testing_finish();

    run("t-fail", imported_fail_always);
    imported_n := finish();

    expect(!g_definition_reached && definition_n == 1);
    expect(!g_imported_reached && imported_n == 1);
}

test "Testing face: defer runs when an assertion aborts the test (definition source vs imported face)" {
    imported_testing_module_failures += finish();
    definition_testing_module_failures += Testing_finish();
    g_definition_defer_ran = false;
    g_imported_defer_ran = false;

    Testing_run("t-defer", definition_defer_abort);
    definition_n := Testing_finish();

    run("t-defer", imported_defer_abort);
    imported_n := finish();

    expect(g_definition_defer_ran && definition_n == 1);
    expect(g_imported_defer_ran && imported_n == 1);
}

test "Testing face: bare return ends the test as passed (definition source vs imported face)" {
    imported_testing_module_failures += finish();
    definition_testing_module_failures += Testing_finish();

    Testing_run("t-early", definition_early_return);
    definition_n := Testing_finish();

    run("t-early", imported_early_return);
    imported_n := finish();

    expect(definition_n == 0);
    expect(imported_n == 0);
}

test "Testing face: finish returns the failure count and resets state (definition source vs imported face)" {
    imported_testing_module_failures += finish();
    definition_testing_module_failures += Testing_finish();

    Testing_run("t-failing", definition_will_fail);
    definition_n := Testing_finish();
    Testing_run("t-passing", definition_expect_pass);
    definition_n2 := Testing_finish();

    run("t-failing", imported_will_fail);
    imported_n := finish();
    run("t-passing", imported_expect_pass);
    imported_n2 := finish();

    expect(definition_n == 1 && definition_n2 == 0);
    expect(imported_n == 1 && imported_n2 == 0);
}

test "Testing face: path_mapping resets to empty passthrough" {
    // The rewrite table is filled by the generated driver's injected runner
    // (the imported face's table by the outer test driver), so the empty
    // default is pinned via the reset here, not the construction state. The
    // rewrite behavior itself is the mapped child scenario below.
    array_reset(*Testing_path_mapping);
    expect(Testing_path_mapping.count == 0);
    pair: Testing_Path_Pair;
    pair.view = "C:/view/a.jai";
    pair.original = "src/a.jai";
    array_add(*Testing_path_mapping, pair);
    expect(Testing_path_mapping.count == 1);
    expect(Testing_path_mapping[0].view == "C:/view/a.jai" && Testing_path_mapping[0].original == "src/a.jai");
    array_reset(*Testing_path_mapping);
    expect(Testing_path_mapping.count == 0);
}

// --- Child scenario support: the printed-format contract runs through a
// generated driver in the published single-face shape (ticket 036): a bare
// `#import "Testing"` resolving to the published flat face's strip view (the
// module source carries inline self-test blocks that raw imports cannot
// compile) plus a #load of the fixture. The fixture bodies call the bare
// names, exactly like an old-juice-style user package; the driver injects
// the path_mapping rewrite table and runs the scenario list. The retired
// comparison legs (the prefixed #load leg and the sibling repository's
// Testing module strip view) are gone — the published bare face is the only
// leg. ---

// One scenario entry: the report name plus the fixture procedure name.
Face_Scenario_Entry :: struct {
    name: string;
    proc: string;
}

testing_face_driver_code :: (fixture_path: string, entries: [] Face_Scenario_Entry) -> string {
    builder: String_Builder;
    append(*builder, "#import \"Basic\";\n");
    append(*builder, "#import \"Testing\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(fixture_path));
    append(*builder, "\";\n\n");
    append(*builder, "#run {\n    main();\n}\n\nmain :: () {\n");
    append(*builder, "    array_reset(*path_mapping);\n");
    append(*builder, "    array_add(*path_mapping, .{view = \"");
    append(*builder, path_slashes(fixture_path));
    append(*builder, "\", original = \"src/scenarios.jai\"});\n");
    for entry: entries {
        append(*builder, "    run(\"");
        append(*builder, entry.name);
        append(*builder, "\", ");
        append(*builder, entry.proc);
        append(*builder, ");\n");
    }
    append(*builder, "    n := finish();\n    print(\"failures=%\\n\", n);\n");
    append(*builder, "}\n");
    return builder_to_string(*builder);
}

run_testing_face_child :: (scenario: string, fixture_rel: string, entries: [] Face_Scenario_Entry) -> (Process_Result, string, string) {
    ensure_published_modules();
    fixture_path := path_slashes(tprint("%1/%2", otter_root(), fixture_rel));
    cache := otter_scratch(tprint("testing-face-e2e-cache/%1", scenario));
    // Session cache: regenerated every run, so stale products from an
    // earlier harness shape can never shadow the current one.
    delete_directory_full(cache);
    make_directory_if_it_does_not_exist(cache, recursive = true);
    // The published Testing face is test-free (the definition source's
    // self-tests are cut at publication), so the modules directory itself is
    // the import root — no strip view.
    testing_view_dir := plugin_face_modules_dir();
    if !file_exists(tprint("%1/Testing.jai", testing_view_dir)) return .{exit_code = -1}, "published Testing module missing", "";
    driver := tprint("%1/driver.jai", cache);
    write_entire_file(driver, testing_face_driver_code(fixture_path, entries));
    result, output, errors, _ := run_command("jai", driver, "-import_dir", testing_view_dir, "-quiet", working_directory = otter_root(), capture_and_return_output = true);
    return result, output, errors;
}

// 1-based line and column of the first occurrence of the needle in the
// file — the expected failure coordinates are computed from the fixture,
// never hardcoded (the reference helper semantics).
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

pass_entries :: Face_Scenario_Entry.[
    .{name = "addition", proc = "addition"},
    .{name = "equality", proc = "equality"},
];

fail_entries :: Face_Scenario_Entry.[
    .{name = "aborts",        proc = "aborts"},
    .{name = "eq-fails",      proc = "eq_fails"},
    .{name = "named-failure", proc = "named_failure"},
    .{name = "prints-message", proc = "prints_message"},
    .{name = "custom-eq",     proc = "custom_eq"},
];

mapped_entries :: Face_Scenario_Entry.[
    .{name = "mapped-fail", proc = "mapped_fail"},
];

test "Testing face child: pass scenario output matches the published face" {
    result, output, _ := run_testing_face_child("pass", "tests/data/testing-face/pass/src/scenarios.jai", pass_entries);
    expect(expect_exit("testing-face-pass", result, 0));
    expected := "[test] addition\n[test] equality\n2 passed, 0 failed\nfailures=0\n";
    // The whole semantic block is pinned as a substring: jai's compile-time
    // notices ("creating library ...") survive -quiet and precede the
    // program prints (the established child-output posture).
    expect(child_output_contains("testing-face-pass", output, expected));
}

test "Testing face child: fail scenario output matches the published face" {
    result, output, _ := run_testing_face_child("fail", "tests/data/testing-face/fail/src/scenarios.jai", fail_entries);
    expect(expect_exit("testing-face-fail", result, 0));

    fixture_file := tprint("%1/tests/data/testing-face/fail/src/scenarios.jai", otter_root());
    l1, c1 := fixture_line_col(fixture_file, "expect(false);");
    l2, c2 := fixture_line_col(fixture_file, "expect_eq(3, 5);");
    l3, c3 := fixture_line_col(fixture_file, "fail(\"boom\")");
    l4, c4 := fixture_line_col(fixture_file, "expect(false, \"got % and %\", 7, 9)");
    l5, c5 := fixture_line_col(fixture_file, "expect_eq(3, 5, \"custom mismatch\")");
    expect(l1 != 0 && l2 != 0 && l3 != 0 && l4 != 0 && l5 != 0);

    // The failure coordinates map back to the package-relative fixture path
    // through the driver-injected rewrite table.
    expected := tprint(
        "[test] aborts\nsrc/scenarios.jai:%1:%2: expect failed\n[test] eq-fails\nsrc/scenarios.jai:%3:%4: expect_eq failed: expected 3, got 5\n[test] named-failure\nsrc/scenarios.jai:%5:%6: boom\n[test] prints-message\nsrc/scenarios.jai:%7:%8: got 7 and 9\n[test] custom-eq\nsrc/scenarios.jai:%9:%10: custom mismatch\n0 passed, 5 failed\nfailures=5\n",
        l1, c1, l2, c2, l3, c3, l4, c4, l5, c5);
    expect(child_output_contains("testing-face-fail", output, expected));
    // The real view path never leaks through the mapping.
    expect(output_matches("testing-face-fail", output, string.[fixture_file], want = false));
}

test "Testing face child: mapped scenario rewrites the failure path" {
    result, output, _ := run_testing_face_child("mapped", "tests/data/testing-face/mapped/src/scenarios.jai", mapped_entries);
    expect(expect_exit("testing-face-mapped", result, 0));

    fixture_file := tprint("%1/tests/data/testing-face/mapped/src/scenarios.jai", otter_root());
    l, c := fixture_line_col(fixture_file, "expect(2 + 2 == 5)");
    expect(l != 0);
    // The failure line reports the mapped package-relative coordinates:
    // the driver-injected rewrite table replaced the view path.
    expected := tprint(
        "[test] mapped-fail\nsrc/scenarios.jai:%1:%2: expect failed\n0 passed, 1 failed\nfailures=1\n",
        l, c);
    expect(child_output_contains("testing-face-mapped", output, expected));
    expect(output_matches("testing-face-mapped", output, string.[fixture_file], want = false));
}

// Latch for the suite-level failure gate on the imported face: the
// in-process tests above drain both registers via finish(), so any failure
// they drained — or left by an earlier test — is re-checked here and trips
// the driver's finish()/assert gate instead of being masked.
test "Testing face registers stay clean between tests" {
    imported_testing_module_failures += finish();
    definition_testing_module_failures += Testing_finish();
    expect(imported_testing_module_failures == 0);
    expect(definition_testing_module_failures == 0);
}
