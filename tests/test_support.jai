// ---------------------------------------------------------------------------
// Test support: the one allowed home for test-program shared declarations.
// Pure test support code lives here in tests/, not src/ (moved from
// src/test_support.jai by user revision, 2026-10). It collects every shared
// declaration migrated from the old tests/ test files' top level — helpers,
// recording fakes and record globals, GOLDEN_CASES and the other test
// constants — referenced by both the src inline test blocks and the Testing
// self-tests (Test discovery's full-package scan includes this file in the
// test program, so its declarations are program-level shared).
//
// Discipline: test shared declarations are allowed only in this file; other
// files (src/ especially) keep no test-only declarations at top level
// (top-level declarations in src files would survive STRIP into the release
// product); modules/Testing.jai keeps no test helpers at top level.
//
// This file is not #loaded by src/main.jai -> outside the Build entry
// closure -> never transpiled, never compiled, never in the release product.
// On the test program path this file is test-free, so its EXPAND view is
// identical output. The scan exclusion set (root-level target/, tests/data/,
// modules/) does not include tests/ itself, so the full-package scan
// includes this file normally.
//
// This file contains the Testing module self-test support segment, framed by
// machine marker comment lines (the marker names appear at the segment's
// start and end below, each prefixed with `//`; note: this spot and every
// other comment must not contain the full text of a marker line — the
// generator locates markers by substring, and a false hit would cut the
// wrong segment). src/commands/test.jai's testing_module_support_block cuts
// the whole segment into the module compile view by these markers. The
// markers are the cut's stable anchors: renaming comments inside the segment
// never breaks the cut; move the markers along when moving declarations
// inside the segment.
// ---------------------------------------------------------------------------

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
#import "Juice";

// ===========================================================================
// The Testing module self-test support segment: the module compile view is
// this segment plus the generator's leading #scope_file and file-level
// imports. The module is a sealed scope (how_to 151), so declarations the
// self-test blocks reference must live in the module's own scope; every
// declaration in this segment (record globals, child scenario helpers,
// self-contained juice_root) must sit between the two machine markers — a
// missing marker or a declaration moved outside the segment breaks the
// module self-test compile. The child scenario helpers are also shared by
// test blocks outside this file (test support program-level sharing).
// ===========================================================================

// __testing_module_support_begin__

// ---------------------------------------------------------------------------
// Path base: the package root every fixture and scratch path derives from.
// The base is juice's invocation cwd — juice runs at the package root,
// workspace discovery derives the root from the process cwd, and the
// generated test metaprogram carries it into the build options:
// intermediate_path = <root>/target. The old implementation derived the
// repository root from the test file's location (the test program entry
// target/transpile, two levels up); it was dropped with the migration: it
// bound itself to the generated files' layout, unrelated to the shared
// declarations' organization.
//
// Self-contained shape: this segment is cut wholesale into the Testing
// module compile view — the module is a sealed scope and cannot see
// src/path_safety's lexical_absolute_path declaration, so it is not called
// here. The test metaprogram sets intermediate_path to the absolute target
// directory ("/" separated); stripping the trailing separator yields the
// package root, no path normalization needed.
// ---------------------------------------------------------------------------
juice_root :: () -> string {
    options := get_build_options();
    // path_strip_filename keeps the trailing separator (String module
    // semantics); stripped, the result is an absolute path — same posture as
    // src/scan_walk.jai's scan_entry_parent.
    root := path_strip_filename(options.intermediate_path);
    while root.count > 0 && (root[root.count - 1] == #char "/" || root[root.count - 1] == #char "\\") root.count -= 1;
    return root;
}

// The Testing module self-tests' record globals (migrated from the old
// tests/ test files' top-level declarations).
g_reached := false;
g_first_reached := false;
g_second_reached := false;
g_defer_ran := false;

// The tests below drive Testing's run()/finish() directly, which resets the
// global register. Each test drains leftover failures at its start into the
// accumulator so the final latch test can still fail the suite — otherwise a
// failure registered before a finish() call would be silently masked (in the
// old per-executable harness each process was isolated). The scenario's own
// counts are checked directly by the assertions instead.
testing_module_failures: s64 = 0;

// Absolute path of juice.exe in the repository's target directory. The
// package root comes from juice_root(): the test program executes at compile
// time in the jai compiler child of juice, where the process working
// directory is the entry file's directory (target/transpile), not the
// invocation cwd. Historically four identical per-source-prefix copies
// existed (juice_exe/test_command_juice_exe/testing_juice_exe/
// tp_juice_exe); merged into this one.
juice_exe :: () -> string {
    return tprint("%1/target/juice.exe", juice_root());
}

// Child scenarios: the real juice.exe running `juice test` on a fixture
// package. fixture_base distinguishes the fixture trees (tests/data/ for the
// command scenarios, tests/data/transpile/run/ for the transpile run matrix,
// tests/data/testing-child/ for the Testing self-tests). Historically
// tp_run_juice_test was identical to this implementation (only the fixture
// base dir differed); merged.
run_juice_test :: (fixture: string, pattern := "", fixture_base := "tests/data/") -> Process_Result, string, string {
    juice := juice_exe();
    fixture_abs := tprint("%1/%2%3", juice_root(), fixture_base, fixture);
    args: [..] string;
    array_add(*args, juice);
    array_add(*args, "test");
    if pattern != "" array_add(*args, pattern);
    result, output, errors, _ := run_command(..args, working_directory = fixture_abs, capture_and_return_output = true);
    return result, output, errors;
}

testing_child_run :: (scenario: string) -> Process_Result, string, string {
    result, output, errors := run_juice_test(scenario, "", "tests/data/testing-child/");
    return result, output, errors;
}

// Exit code check (shared by the child scenarios): historically four
// identical per-source-prefix copies existed
// (expect_child_exit/expect_exit/testing_expect_exit/tp_expect_exit),
// differing only in the failure diagnostic prefix; merged into one with the
// prefix kept as a parameter for each diagnostic text.
expect_exit :: (name: string, result: Process_Result, want: s32, tag := "child") -> bool {
    if result.type == .EXITED && result.exit_code == want return true;
    print("[%1 %2] exit result %3/%4, want %5\n", tag, name, result.type, result.exit_code, want);
    return false;
}

// Normalize CRLF to LF so expected blocks are compared line by line
// regardless of the child process's native line endings. Historically three
// verbatim copies existed (normalize_crlf/testing_normalize_crlf/
// tp_normalize_crlf); merged into this one.
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

// Output assertion (shared by the child scenarios): checks each needle's
// presence/absence (want). Historically three identical per-source-prefix
// copies existed (output_matches/testing_output_matches/
// tp_output_matches), differing only in the failure diagnostic prefix;
// merged into one with the prefix kept as a parameter.
output_matches :: (name: string, output: string, needles: [] string, want := true, tag := "child") -> bool {
    normalized := normalize_crlf(output);
    for needle: needles {
        found := find_index_from_left(normalized, needle) >= 0;
        if found != want {
            print("[%1 %2] output %3 '%4'\n", tag, name, ifx found then "unexpectedly contains" else "missing", needle);
            print("  output was:\n%\n", output);
            return false;
        }
    }
    return true;
}

// 1-based line/column of the first occurrence of `needle` in `file`; 0,0 if
// the source cannot be read or the needle is missing. Used to build expected
// failure lines without hardcoding line numbers. Historically
// testing_line_col was verbatim identical to this implementation; merged.
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

// __testing_module_support_end__

// ===========================================================================
// Declarations migrated from the old tests/ test files' top level — the
// run/clean/compile recording fakes, the build transpile seam and the E2E
// child scenario helpers
// ===========================================================================

test_launch_count: s64;
test_launched_plan: Artifact_Plan;
test_launched_root: string;
test_launch_success: bool;

test_launch_artifact :: (plan: Artifact_Plan, package_root: string) -> bool {
    test_launch_count += 1;
    test_launched_plan = plan;
    test_launched_root = package_root;
    return test_launch_success;
}

test_clean_validated: [..] string;
test_clean_deleted: [..] string;
test_clean_invalid_path: string;
test_clean_failed_delete: string;
test_clean_expected_validations: s64;
test_clean_deleted_too_early: bool;

reset_clean_test :: (expected_validations: s64) {
    array_reset(*test_clean_validated);
    array_reset(*test_clean_deleted);
    test_clean_invalid_path = "";
    test_clean_failed_delete = "";
    test_clean_expected_validations = expected_validations;
    test_clean_deleted_too_early = false;
}

test_validate_clean_path :: (path: string) -> bool {
    array_add(*test_clean_validated, path);
    return path != test_clean_invalid_path;
}

test_delete_clean_path :: (path: string) -> bool {
    if test_clean_validated.count != test_clean_expected_validations test_clean_deleted_too_early = true;
    array_add(*test_clean_deleted, path);
    return path != test_clean_failed_delete;
}

test_compile_count: s64;
test_compiled_plan: Artifact_Plan;
test_compiled_driver_root: string;
test_compiled_entry: string;
test_compile_success: bool;

test_compile_artifact :: (root_dir: string, plan: Artifact_Plan, entry: string) -> bool {
    test_compile_count += 1;
    test_compiled_plan = plan;
    test_compiled_driver_root = root_dir;
    test_compiled_entry = entry;
    return test_compile_success;
}

// Fake transpile step: records every call and returns a canned view with a
// flat (collision-free by construction) key. The orchestration feeds the key
// through the pure path function; the fake only fills in content. The build
// and test seams' fakes share one key function (historically
// build_fake_key/fake_key were two identical copies differing only in
// prefix; merged) — the fake keys only circulate inside the seams, and the
// test blocks rebuild expected paths with the same function.
fake_key :: (rel: string) -> string {
    result := copy_string(rel);
    for i: 0..result.count-1 {
        if result[i] == #char "/" result[i] = #char "_";
    }
    return tprint("key-%1", result);
}

test_build_transpile_calls: s64;
test_build_transpiled_files: [..] string;
test_build_transpiled_rewrites: [..] string;
test_build_fake_diagnostic: string;

fake_build_transpile :: (file: Build_Source_File, load_targets: [] Load_Target) -> Build_File_Output {
    test_build_transpile_calls += 1;
    array_add(*test_build_transpiled_files, file.rel_path);
    for target: load_targets {
        array_add(*test_build_transpiled_rewrites, tprint("%1 -> %2", target.from, target.to));
    }
    output: Build_File_Output;
    output.view = tprint("// fake build view of %1\n", file.rel_path);
    output.key = fake_key(file.rel_path);
    if test_build_fake_diagnostic != "" {
        array_add(*output.diagnostics, .{line = 2, column = 1, message = test_build_fake_diagnostic});
    }
    return output;
}

test_build_compile_calls: s64;
test_build_compiled_entries: [..] string;
test_build_compile_success: bool;

fake_build_compile :: (root_dir: string, plan: Artifact_Plan, entry: string) -> bool {
    test_build_compile_calls += 1;
    array_add(*test_build_compiled_entries, entry);
    return test_build_compile_success;
}

reset_build_seam :: () {
    test_compile_count = 0;
    test_compile_success = true;
    test_build_transpile_calls = 0;
    array_reset(*test_build_transpiled_files);
    array_reset(*test_build_transpiled_rewrites);
    test_build_fake_diagnostic = "";
    test_build_compile_calls = 0;
    array_reset(*test_build_compiled_entries);
    test_build_compile_success = true;
}

// A prepared workspace over a real temp fixture root: the transpile front
// probes real files even in seam tests (same posture as the revalidation
// gate running over the real filesystem).
build_seam_plan :: (root: string, main_file: string) -> Artifact_Plan {
    plan: Artifact_Plan;
    plan.target = .{name = "app", main_file = main_file, source_path = tprint("%1/%2", root, main_file)};
    plan.target_dir = tprint("%1/target", root);
    plan.artifact_path = tprint("%1/target/app.exe", root);
    return plan;
}

build_seam_prepared :: (root: string, plan: Artifact_Plan) -> Prepared_Workspace {
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    // The plan must live in a heap-backed array: a static literal here would
    // leave the slice pointing at this frame's stack.
    plans: [..] Artifact_Plan;
    array_add(*plans, plan);
    prepared.artifact_plans = plans;
    return prepared;
}

build_seam_write :: (root: string, rel: string, content: string) -> bool {
    path := tprint("%1/%2", root, rel);
    if !make_directory_if_it_does_not_exist(path_strip_filename(path), recursive = true) return false;
    return write_entire_file(path, content);
}

run_juice_child :: (fixture: string, command: string, target := "") -> (Process_Result, string, string) {
    juice := juice_exe();
    fixture_abs := tprint("%1/tests/data/%2", juice_root(), fixture);
    args: [..] string;
    array_add(*args, juice);
    array_add(*args, command);
    if target != "" array_add(*args, target);
    result, output, errors, _ := run_command(..args, working_directory = fixture_abs, capture_and_return_output = true);
    return result, output, errors;
}

child_output_contains :: (name: string, output: string, needle: string) -> bool {
    if find_index_from_left(output, needle) >= 0 return true;
    print("[build child %1] output missing '%2'\n  output was:\n%\n", name, needle, output);
    return false;
}

// ===========================================================================
// Declarations migrated from the old tests/ test files' top level — the
// recording handlers and the test registries
// ===========================================================================

test_a_calls: s64 = 0;
test_b_calls: s64 = 0;
test_c_calls: s64 = 0;
test_d_calls: s64 = 0;
test_fail_calls: s64 = 0;

reset_dispatch_counters :: () {
    test_a_calls = 0;
    test_b_calls = 0;
    test_c_calls = 0;
    test_d_calls = 0;
    test_fail_calls = 0;
}

test_handler_a :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_a_calls += 1;
    return true;
}

test_handler_b :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_b_calls += 1;
    return true;
}

test_handler_c :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_c_calls += 1;
    return true;
}

test_handler_d :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_d_calls += 1;
    return true;
}

test_handler_fail :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_fail_calls += 1;
    return false;
}

strict_arguments_are_invalid :: (arguments: [] string) -> bool {
    return false;
}

TEST_REGISTRY_SIMPLE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.[], handler = test_handler_b},
];

TEST_REGISTRY_DUPLICATE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], handler = test_handler_a},
    .{name = "a", description = "Command A Duplicate", usage = "test a", prerequisites = string.[], handler = test_handler_b},
];

TEST_REGISTRY_MISSING_PREREQ :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.["nonexistent"], handler = test_handler_a},
];

TEST_REGISTRY_CYCLE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.["b"], handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.["a"], handler = test_handler_b},
];

TEST_REGISTRY_DIAMOND :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.["a"], handler = test_handler_b},
    .{name = "c", description = "Command C", usage = "test c", prerequisites = string.["a"], handler = test_handler_c},
    .{name = "d", description = "Command D", usage = "test d", prerequisites = string.["b", "c"], handler = test_handler_d},
];

TEST_REGISTRY_FAILURE :: Command.[
    .{name = "failing", description = "Failing Command", usage = "test failing", prerequisites = string.[], handler = test_handler_fail},
    .{name = "target", description = "Target Command", usage = "test target", prerequisites = string.["failing"], handler = test_handler_b},
];

TEST_REGISTRY_ARGUMENTS :: Command.[
    .{name = "sideeffect", description = "Side Effect Command", usage = "test sideeffect", prerequisites = string.[], handler = test_handler_a},
    .{name = "strict", description = "Strict Command", usage = "test strict", prerequisites = string.["sideeffect"], validate_arguments = strict_arguments_are_invalid, handler = test_handler_b},
];

// ===========================================================================
// Declarations migrated from the old tests/ test files' top level — the
// discovery/resolution/dependency recording fakes and the import shim helper
// ===========================================================================

test_discovery_attempts: s64 = 0;
test_fake_discovery_ok: bool = false;
test_fake_discovery: Workspace_Discovery;

test_fake_discover :: (root_dir: string, cache_dir: string) -> Workspace_Discovery, bool {
    test_discovery_attempts += 1;
    return test_fake_discovery, test_fake_discovery_ok;
}

test_plan_resolution_success: bool = false;
test_resolved_plans: [] Artifact_Plan;
test_dependency_attempts: s64 = 0;
test_dependency_ok: bool = false;
test_dependency_snapshot: [] Package;

test_fake_resolve :: (pkg: Package) -> Artifact_Plan_Result {
    if !test_plan_resolution_success return .{success = false, error_message = copy_string("resolution failure")};
    return .{success = true, plans = test_resolved_plans};
}

test_fake_prepare_dependencies :: (root_dir: string, cache_dir: string, member_packages: [] Package) -> bool {
    test_dependency_attempts += 1;
    test_dependency_snapshot = member_packages;
    return test_dependency_ok;
}

reset_preparation_test :: () {
    test_discovery_attempts = 0;
    test_fake_discovery_ok = false;
    test_fake_discovery = .{};
    test_plan_resolution_success = false;
    test_resolved_plans = Artifact_Plan.[];
    test_dependency_attempts = 0;
    test_dependency_ok = false;
    test_dependency_snapshot = Package.[];
}

test_fetched_dependency_names: [..] string;
test_fetch_result: bool = false;
test_linked_member_names: [..] string;
test_link_result: bool = false;

test_fake_fetch :: (root_dir: string, cache_dir: string, dep: Dependency) -> bool {
    array_add(*test_fetched_dependency_names, copy_string(dep.name));
    return test_fetch_result;
}

test_fake_link_member :: (root_dir: string, member: Package) -> bool {
    array_add(*test_linked_member_names, copy_string(member.name));
    return test_link_result;
}

// Consumers resolve "#import <name>" through a generated shim in the
// dependency directory; the shim loads the dependency's real entry by path,
// so any source directory name and any of the three layouts work.
shim_content_for :: (packages_dir: string, name: string) -> string, bool {
    shim_path := tprint("%1/%2.jai", packages_dir, name);
    if !file_exists(shim_path) return "", false;
    content, ok := read_entire_file(shim_path);
    return content, ok;
}

// ===========================================================================
// Declarations migrated from the old tests/ test files' top level — the LIB
// fixture package construction
// ===========================================================================

// A LIB package is an import source: it declares no executable targets and
// resolves to zero plans once its module.jai import entry is verified.
library_fixture_package :: () -> Package {
    pkg: Package;
    pkg.name    = "libdemo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data/lib-module", juice_root());
    pkg.type    = .LIB;
    return pkg;
}

// ===========================================================================
// Declarations migrated from the old tests/ test files' top level — the test
// orchestration seam's recording fakes and the cache-tree scan helpers
// ===========================================================================

test_transpiled_files: [..] Test_Source_File;
test_transpiled_numbers: [..] s64;
test_fake_tests_per_file: s64 = 1;
test_fake_diagnostic: string = "";

// Each file yields test_count tests named "<rel> test <n>" plus, optionally,
// one canned diagnostic (for the rejection path). The key is canned too (flat
// by construction): the orchestration only feeds it through the pure path
// function.
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

fake_compile :: (transpile_dir: string, driver_path: string, metaprogram_path: string) -> bool {
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

// Directory scan (shared by the transpile tree and the golden case
// directories): collects direct children as files/directories. Historically
// the Cache_Dir_Scan/Case_Dir_Scan structure pairs and their visitors
// existed as separate identical copies; merged.
Dir_Scan :: struct {
    dirs:  [..] string;
    files: [..] string;
}

dir_scan_visitor :: (info: *File_Visit_Info, scan: *Dir_Scan) {
    if info.is_directory {
        array_add(*scan.dirs, copy_string(info.short_name));
    } else {
        array_add(*scan.files, copy_string(info.short_name));
    }
}

dir_scan_entries :: (dir: string) -> (Dir_Scan, bool) {
    scan: Dir_Scan;
    visited := visit_files(dir, false, *scan, dir_scan_visitor, visit_files = true, visit_directories = true);
    return scan, visited;
}

// Bytewise lexicographic comparison (strcmp semantics) and insertion sort.
// Historically sort_strings (based on String.compare) and
// tp_sort_strings/tp_string_less (transpile tests) coexisted as two
// same-semantics implementations; merged into this one explicit bytewise
// comparison.
string_less :: (a: string, b: string) -> bool {
    n := min(a.count, b.count);
    for i: 0..n-1 {
        if a[i] != b[i] return a[i] < b[i];
    }
    return a.count < b.count;
}

sort_strings :: (items: [] string) {
    for i: 1..items.count-1 {
        if i >= items.count break;
        key := items[i];
        j := i - 1;
        while j >= 0 && string_less(key, items[j]) {
            items[j+1] = items[j];
            j -= 1;
        }
        items[j+1] = key;
    }
}

// ===========================================================================
// Declarations migrated from the old tests/ test files' top level — the
// golden/negative harness and the compile-and-run matrix helpers
// ===========================================================================

// ---------------------------------------------------------------------------
// Golden baselines (docs/transpiled-output-formatting.md §4). Every case dir
// holds one or more input *.jai files plus the expected view files
// (<name>.view.jai); negative cases hold the expected rendered diagnostics
// (diagnostic.txt). Rewrite the baselines by running `juice test` with the
// JUICE_UPDATE_GOLDEN environment variable set to any non-empty value (CI
// never sets it).
// ---------------------------------------------------------------------------

GOLDEN_CASES :: string.[
    "expand-basic",
    "loads",
    "immunity",
    "one-line",
    "test-free",
    "strip-basic",
    "multi",
];

NEGATIVE_CASES :: string.[
    "nested-in-proc",
    "nested-in-struct",
    "multiline-head",
    "shared-load-before",
    "shared-load-after",
    "strip-trailing",
    "unterminated",
];

// (GetEnvironmentVariableA comes from src/xdg.jai, loaded as a test view.)

wants_update :: () -> bool {
    #if OS == .WINDOWS {
        buffer: [512] u8;
        result := GetEnvironmentVariableA("JUICE_UPDATE_GOLDEN", buffer.data, 512);
        if result > 0 && result < 512 return true;
    }
    return false;
}

expand_ctx :: (path := "src/foo.jai", next := 1) -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = .EXPAND;
    ctx.path = path;
    ctx.next_test_number = next;
    return ctx;
}

strip_ctx :: (path := "src/foo.jai", targets: [] Load_Target) -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = path;
    ctx.next_test_number = 1;
    ctx.load_targets = targets;
    return ctx;
}

count_lines :: (s: string) -> s64 {
    n := 1;
    for ch: s {
        if ch == #char "\n" n += 1;
    }
    return n;
}

Case_Config :: struct {
    mode:        Transpile_Mode = .EXPAND;
    path:        string;
    next_number: s64 = 1;
    load_targets: [..] Load_Target;
}

read_case_config :: (dir: string) -> Case_Config {
    config: Case_Config;
    content, ok := read_entire_file(tprint("%1/config.txt", dir), log_errors = false);
    if !ok return config;
    lines := split(content, "\n");
    for line: lines {
        trimmed := trim(line);
        if trimmed == "" || starts_with(trimmed, "#") continue;
        eq := -1;
        for i: 0..trimmed.count-1 {
            if trimmed[i] == #char "=" {
                eq = i;
                break;
            }
        }
        if eq <= 0 continue;
        key := slice(trimmed, 0, eq);
        value := slice(trimmed, eq + 1, trimmed.count - eq - 1);
        if key == "mode" {
            if value == "strip" config.mode = .STRIP;
        } else if key == "path" {
            config.path = copy_string(value);
        } else if key == "next_number" {
            number, parsed, _ := string_to_int(value);
            if parsed config.next_number = number;
        } else if key == "load_target" {
            eq2 := -1;
            for i: 0..value.count-1 {
                if value[i] == #char "=" {
                    eq2 = i;
                    break;
                }
            }
            if eq2 > 0 {
                array_add(*config.load_targets, .{
                    from = copy_string(slice(value, 0, eq2)),
                    to = copy_string(slice(value, eq2 + 1, value.count - eq2 - 1)),
                });
            }
        }
    }
    return config;
}

// A case directory's input files in production scan order: within each
// directory, files first (lexicographic by name),
// then subdirectories (lexicographic), recursing. The driver golden derives
// its view list, mapping table and test numbering from this exact order.
collect_case_files :: (dir: string) -> [..] string {
    files: [..] string;
    collect_case_files_rec(dir, "", *files);
    return files;
}

collect_case_files_rec :: (dir: string, rel_prefix: string, files: *[..] string) {
    scan, visited := dir_scan_entries(dir);
    if !visited return;
    sort_strings(scan.files);
    sort_strings(scan.dirs);
    for name: scan.files {
        // driver.jai / first.jai are the case's own expected products,
        // never inputs.
        if ends_with(name, ".jai") && !ends_with(name, ".view.jai") && name != "driver.jai" && name != "first.jai" {
            array_add(files, tprint("%1%2", rel_prefix, name));
        }
    }
    for name: scan.dirs {
        if name.count > 0 && name[0] == #char "." continue;
        collect_case_files_rec(tprint("%1/%2", dir, name), tprint("%1%2/", rel_prefix, name), files);
    }
}

// The package root the generated products refer to. Expected files spell it
// as the <abs> placeholder (docs/transpiled-output-formatting.md §4.2).
golden_root :: () -> string {
    return juice_root();
}

// Replace every occurrence of the absolute root prefix with "<abs>", so the
// generated driver/metaprogram text compares byte for byte against the
// machine-independent expected files.
normalize_golden_abs :: (text: string) -> string {
    root := golden_root();
    result := text;
    while true {
        index := find_index_from_left(result, root);
        if index < 0 break;
        result = tprint("%1<abs>%2", slice(result, 0, index), slice(result, index + root.count, result.count - index - root.count));
    }
    return result;
}

compare_or_update :: (expected_path: string, actual: string, update: bool) -> bool {
    if update {
        ok := write_entire_file(expected_path, actual);
        print("[GOLDEN UPDATE] wrote %\n", expected_path);
        return ok;
    }
    expected, ok := read_entire_file(expected_path);
    if !ok {
        print("[GOLDEN FAIL] %: expected file missing\n", expected_path);
        return false;
    }
    if expected == actual {
        print("[GOLDEN PASS] %\n", expected_path);
        return true;
    }
    print("[GOLDEN FAIL] % (expected % bytes, actual % bytes)\n", expected_path, expected.count, actual.count);
    first_diff := 0;
    while first_diff < expected.count && first_diff < actual.count && expected[first_diff] == actual[first_diff] first_diff += 1;
    from := max(first_diff - 30, 0);
    print("  expected: ...%...\n", slice(expected, from, min(90, expected.count - from)));
    print("  actual:   ...%...\n", slice(actual, from, min(90, actual.count - from)));
    return false;
}

case_context :: (config: Case_Config, case_name: string, file: string) -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = config.mode;
    ctx.path = ifx config.path != "" then config.path else tprint("%1/%2", case_name, file);
    ctx.next_test_number = config.next_number;
    ctx.load_targets = config.load_targets;
    return ctx;
}

run_golden_cases :: (update: bool) -> bool {
    all_ok := true;
    for case_name: GOLDEN_CASES {
        dir := tprint("%1/tests/data/transpile/golden/%2", juice_root(), case_name);
        config := read_case_config(dir);
        files := collect_case_files(dir);
        if files.count == 0 {
            print("[GOLDEN FAIL] %1: no input files\n", dir);
            all_ok = false;
            continue;
        }
        next := config.next_number;
        // Driver inputs accumulated in enumeration order: every file exactly
        // once, its case-relative path, and the content-addressed test-mode
        // view path (the driver is a test-program product; the key derives
        // from the same source the view was generated from).
        driver_files: [..] Test_Source_File;
        driver_view_paths: [..] string;
        matches: [..] Test_Entry;
        for file: files {
            source, ok := read_entire_file(tprint("%1/%2", dir, file));
            if !ok {
                print("[GOLDEN FAIL] %1/%2: cannot read input\n", dir, file);
                all_ok = false;
                continue;
            }
            ctx := case_context(config, case_name, file);
            ctx.next_test_number = next;
            result := transpile_source(source, ctx);
            if result.diagnostics.count > 0 {
                for d: result.diagnostics {
                    print("[GOLDEN FAIL] %1/%2: diagnostic %3:%4,%5: %6\n", dir, file, ctx.path, d.line, d.column, d.message);
                }
                all_ok = false;
                continue;
            }
            next += result.tests.count;
            if !compare_or_update(tprint("%1/%2.view.jai", dir, file), result.view, update) all_ok = false;

            key := transpile_view_key(ctx.path, source, .EXPAND, Load_Target.[], JUICE_VERSION);
            array_add(*driver_view_paths, tprint("%1/target/transpile/%2/%3", golden_root(), key, ctx.path));
            file_rec: Test_Source_File;
            file_rec.rel_path = ctx.path;
            array_add(*driver_files, file_rec);
            for entry: result.tests array_add(*matches, entry);
        }
        // Every case locks the generated driver and metaprogram too
        // (docs/transpiled-output-formatting.md §4.1); absolute paths are
        // normalized to the <abs> placeholder before comparing.
        driver_text := generate_test_driver(driver_files, driver_view_paths, matches);
        if !compare_or_update(tprint("%1/driver.jai", dir), normalize_golden_abs(driver_text), update) all_ok = false;
        // The shared Metaprogram generator's test shape: absolute paths are
        // normalized to the <abs> placeholder and compared byte for byte
        // against the expected file — the byte-identity invariant is locked
        // by the golden fixtures.
        metaprogram: Compiler_Metaprogram_Options;
        metaprogram.workspace_name    = "Juice Test Program";
        metaprogram.no_output         = true;
        metaprogram.intermediate_path = tprint("%1/target", golden_root());
        metaprogram.import_dirs       = string.[tprint("%1/modules", golden_root())];
        metaprogram.build_file        = tprint("%1/target/transpile/driver.jai", golden_root());
        first_text := generate_compiler_metaprogram(metaprogram);
        if !compare_or_update(tprint("%1/first.jai", dir), normalize_golden_abs(first_text), update) all_ok = false;
    }
    return all_ok;
}

run_negative_cases :: (update: bool) -> bool {
    all_ok := true;
    for case_name: NEGATIVE_CASES {
        dir := tprint("%1/tests/data/transpile/negative/%2", juice_root(), case_name);
        config := read_case_config(dir);
        files := collect_case_files(dir);
        rendered: String_Builder;
        total := 0;
        for file: files {
            source, ok := read_entire_file(tprint("%1/%2", dir, file));
            if !ok {
                print("[NEGATIVE FAIL] %1/%2: cannot read input\n", dir, file);
                all_ok = false;
                continue;
            }
            ctx := case_context(config, case_name, file);
            result := transpile_source(source, ctx);
            total += result.diagnostics.count;
            for d: result.diagnostics {
                print_to_builder(*rendered, "%1:%2,%3: %4\n", ctx.path, d.line, d.column, d.message);
            }
        }
        if total == 0 {
            print("[NEGATIVE FAIL] %1: expected diagnostics, got none\n", dir);
            all_ok = false;
            continue;
        }
        if !compare_or_update(tprint("%1/diagnostic.txt", dir), builder_to_string(*rendered), update) all_ok = false;
    }
    return all_ok;
}

// ===========================================================================
// jaix pre-step test support: the sibling jaix-cli product path (juice_exe
// same family), the PATH injection for the production "jaix" lookup, the
// driver-file cleanup for the child scenarios and the recording seam fakes
// ===========================================================================

// Absolute path of the jaix CLI executable in the sibling jaix-cli
// repository's target directory (juice_exe same family): the dev-layout
// product the pre-step E2E scenarios resolve through the production PATH
// lookup (the demo fixture's marker exe stays empty).
jaix_exe :: () -> string {
    return tprint("%1/../jaix-cli/target/jaix.exe", juice_root());
}

#if OS == .WINDOWS {
    kernel32_env :: #system_library "kernel32";
    SetEnvironmentVariableA :: (lpName: *u8, lpValue: *u8) -> s32 #foreign kernel32_env;
}

// Ensure the jaix CLI's directory sits at the front of the test program's
// PATH so juice child processes resolve the pre-step's "jaix" through the
// production PATH lookup — the injection mechanism is the process
// environment, zero production deviation. Idempotent: repeated calls keep
// one prefix entry. Windows-only; on other platforms the pre-step E2E
// scenarios need a PATH-provided jaix.
prepend_jaix_to_path :: () {
    #if OS == .WINDOWS {
        dir := path_strip_filename(jaix_exe());
        while dir.count > 0 && (dir[dir.count - 1] == #char "/" || dir[dir.count - 1] == #char "\\") dir.count -= 1;
        current := get_env("PATH");
        prefix := tprint("%1;", dir);
        if !starts_with(current, prefix) {
            SetEnvironmentVariableA(temp_c_string("PATH"), temp_c_string(tprint("%1%2", prefix, current)));
        }
    }
}

// jaix's CLI driver files land in the child process's working directory
// (dot-prefixed `.jaix-<hash>.jai`, one per transpile call — 049 decision 12
// naming, 0056 dot prefix), so an in-place child scenario leaves them at
// the fixture root. Deletes every root-level .jai file that is not one of
// the fixture's two manifests (the fixture keeps its sources in src/) — the
// name-unrelated cleanup matches the dot-prefixed names unchanged.
clean_jaix_driver_files :: (fixture_root: string) {
    scan, visited := dir_scan_entries(fixture_root);
    if !visited return;
    for name: scan.files {
        if !ends_with(name, ".jai") continue;
        if name == "package.jai" || name == "jaix.config.jai" continue;
        file_delete(tprint("%1/%2", fixture_root, name));
    }
}

// ---------------------------------------------------------------------------
// The jaix pre-step seam's recording fakes (the jaix front seam tests and
// the build wiring tests share them): the spawn fake records each per-file
// call as one "exe|input|output|config" string and returns the canned exit
// code and stderr; the prestep fake records the build orchestration's call.
// ---------------------------------------------------------------------------

test_jaix_spawn_calls: s64;
test_jaix_spawned: [..] string;
test_jaix_spawn_exit: s64 = 0;
test_jaix_spawn_stderr: string = "";

fake_jaix_spawn :: (exe: string, input: string, output: string, config: string) -> (exit_code: s64, stderr: string) {
    test_jaix_spawn_calls += 1;
    array_add(*test_jaix_spawned, tprint("%1|%2|%3|%4", exe, input, output, config));
    return test_jaix_spawn_exit, test_jaix_spawn_stderr;
}

reset_jaix_spawn :: () {
    test_jaix_spawn_calls = 0;
    array_reset(*test_jaix_spawned);
    test_jaix_spawn_exit = 0;
    test_jaix_spawn_stderr = "";
}

test_jaix_prestep_calls: s64;
test_jaix_prestep_success: bool = true;

fake_jaix_prestep :: (prepared: *Prepared_Workspace, transpile: #type (exe: string, input: string, output: string, config: string) -> (exit_code: s64, stderr: string)) -> bool {
    test_jaix_prestep_calls += 1;
    return test_jaix_prestep_success;
}
