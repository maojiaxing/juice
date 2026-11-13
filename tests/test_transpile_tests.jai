// ---------------------------------------------------------------------------
// Test command transpile wiring tests (ticket 028): the t3 per-file EXPAND
// step with global numbering, the Testing module compile view family (t9),
// the TRANSPILE/COMPILE orchestration seam matrix (real transpile over
// scratch packages with recording collect/spawn fakes — the old juice
// seam-test posture), the TRANSPILE/COMPILE lifecycle hook dispatch (the
// 027-shape matrix) and the real-otter-exe E2E family (test blocks ->
// EXPAND -> @test -> note enumeration -> execution, the failure coordinate
// mapping, the pattern filter, the dependency strip face and the
// in-package Testing module self-tests).
//
// Key constraint (same as the other sibling test files): src modules are
// bootstrap #load targets / entry closure members — test blocks would be
// illegal inside them, so this module stays test-free and its tests live
// here (tests/), per the test organization rule: referenced by no #load,
// collected into the test program by Test discovery's full-package scan.
// This file contains only test blocks and their helper declarations (all
// prefixed tt_ — the single-namespace convention); zero production code
// coupling. Good-test standard: only external behavior is pinned (given
// package roots / hook tables -> views / products / trace / exit codes).
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";

// ===========================================================================
// Shared helpers: scratch roots, scan records, seam runs
// ===========================================================================

tt_scratch :: (name: string) -> string {
    root := otter_scratch(tprint("tt-%1", name));
    delete_directory_full(root);
    return root;
}

tt_file :: (root: string, rel: string) -> Scan_File {
    return .{ rel_path = rel, abs_path = path_slashes(tprint("%1/%2", root, rel)) };
}

// A prepared workspace over a root string — the test command consumes only
// the discovery snapshot (test_command_prepared in test_support.jai).
tt_prepared :: (root: string) -> Juice.Prepared_Workspace {
    return test_command_prepared(root);
}

// Run the orchestration over a scratch package with the recording
// collect/spawn fakes (test_support.jai): real transpile, generated
// products, no compiler child.
tt_run :: (root: string, files: [] Scan_File, pattern := "") -> bool {
    reset_test_command_seam();
    test_test_collect_files = files;
    test_test_spawn_exit_code = 0;
    prepared := tt_prepared(root);
    return test_prepared_workspace(*prepared, pattern, Hook_Registration.[], test_collect_test_files, test_spawn_test_compiler);
}

// A scratch package with one test block file (the dispatch matrix's
// built-in-front fixture).
tt_scratch_package :: (name: string) -> string {
    root := tt_scratch(name);
    build_seam_write(root, "src/a.jai", "#import \"Basic\";\n\ntest \"one\" {\n    expect(true);\n}\n");
    return root;
}

tt_scratch_files :: (root: string) -> [..] Scan_File {
    // Heap-backed: a runtime-computed array literal would land on this
    // frame's stack and dangle past the return.
    files: [..] Scan_File;
    array_add(*files, tt_file(root, "src/a.jai"));
    return files;
}

// ===========================================================================
// Recording hook machinery (the 027 build-side shape, test stages)
// ===========================================================================

TT_TRACE: [..] string;

tt_reset :: () {
    array_reset(*TT_TRACE);
}

tt_record :: (label: string) {
    array_add(*TT_TRACE, copy_string(label));
}

// The COMPILE at recorder captures the stage state for assertions.
TT_CAPTURED_VIEWS: [..] string;
TT_CAPTURED_DIR: string;
TT_CAPTURED_PATTERN: string;
TT_CAPTURED_FILE_COUNT: s64;

tt_capture :: (stage: *Test_Compile_Stage) {
    array_reset(*TT_CAPTURED_VIEWS);
    for v: stage.view_paths array_add(*TT_CAPTURED_VIEWS, copy_string(v));
    TT_CAPTURED_DIR = stage.transpile_dir;
    TT_CAPTURED_PATTERN = stage.pattern;
    TT_CAPTURED_FILE_COUNT = stage.files.count;
}

tt_hook_t_before_a :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    tt_record("t-before-a");
    return true;
}

tt_hook_t_before_b :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    tt_record("t-before-b");
    return true;
}

tt_hook_t_after_a :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    tt_record("t-after-a");
    return true;
}

tt_hook_c_before_a :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    tt_record("c-before-a");
    return true;
}

tt_hook_c_before_b :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    tt_record("c-before-b");
    return true;
}

tt_hook_c_after_a :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    tt_record("c-after-a");
    return true;
}

// The TRANSPILE at recorder: replaces the built-in front and fills the
// stage's outputs itself (the at hook owns the stage's outputs).
tt_hook_t_at_fill :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    tt_record("t-at");
    stage := cast(*Test_Transpile_Stage) ctx.views;
    stage.transpile_dir = "hook-transpile";
    array_add(*stage.view_paths, "hook-view");
    return true;
}

// The COMPILE at recorder: replaces the built-in front.
tt_hook_c_at_record :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    tt_record("c-at");
    tt_capture(cast(*Test_Compile_Stage) ctx.artifact_paths);
    return true;
}

// The slot probe: the test host fills slots null (host-owned storage).
tt_hook_state_probe :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    tt_record(ifx state == null then "state-null" else "state-set");
    return true;
}

// Failure and diagnostic behaviors.
tt_hook_fail :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    tt_record("fail");
    return false;
}

tt_hook_error :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    tt_record("error");
    array_add(ctx.diagnostics, .{level = .ERROR, message = "tt error"});
    return true;
}

tt_hook_warning :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    tt_record("warning");
    array_add(ctx.diagnostics, .{level = .WARNING, message = "tt warning"});
    return true;
}

// Hook and table assembly helpers.
tt_hook :: (stage: Lifecycle_Stage, position: Hook_Position, hook: #type (ctx: *Lifecycle_Context, state: *void) -> bool) -> Lifecycle_Hook {
    return .{stage = stage, position = position, hook = hook};
}

tt_table :: (hooks: [] Lifecycle_Hook) -> [..] Hook_Registration {
    table: [..] Hook_Registration;
    register_hooks(*table, hooks);
    return table;
}

// Dispatch through a table with the recording fakes.
tt_dispatch :: (root: string, files: [] Scan_File, pattern: string, table: [] Hook_Registration) -> bool {
    reset_test_command_seam();
    test_test_collect_files = files;
    test_test_spawn_exit_code = 0;
    prepared := tt_prepared(root);
    return test_prepared_workspace(*prepared, pattern, table, test_collect_test_files, test_spawn_test_compiler);
}

// ---------------------------------------------------------------------------
// PRESTEP consumption (ticket 057): the recording fake pre-step plugin across
// the same lifecycle hook face (it reads the stage through ctx.prestep and
// fills the tables through the stage-level API). No jaix dependency.
// ---------------------------------------------------------------------------

TT_PRESTEP_SUBSTITUTIONS: [..] Source_Substitution;
TT_PRESTEP_DROPS: [..] string;
TT_PRESTEP_ROOT: string;
TT_PRESTEP_MEMBERS: [..] string;

tt_prestep_reset :: () {
    array_reset(*TT_PRESTEP_SUBSTITUTIONS);
    array_reset(*TT_PRESTEP_DROPS);
    TT_PRESTEP_ROOT = "";
    array_reset(*TT_PRESTEP_MEMBERS);
}

tt_hook_p_before_fill :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    tt_record("p-before");
    stage := cast(*Prestep_Stage) ctx.prestep;
    TT_PRESTEP_ROOT = stage.root_dir;
    array_reset(*TT_PRESTEP_MEMBERS);
    for dir: stage.member_dirs array_add(*TT_PRESTEP_MEMBERS, copy_string(dir));
    for s: TT_PRESTEP_SUBSTITUTIONS {
        if !prestep_add_substitution(ctx, s.original, s.replacement) return false;
    }
    for d: TT_PRESTEP_DROPS {
        if !prestep_add_drop(ctx, d) return false;
    }
    return true;
}

tt_hook_p_after :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    tt_record("p-after");
    return true;
}

// ===========================================================================
// t3: the per-file EXPAND step (over the static test-blocks fixture)
// ===========================================================================

test "Test transpile: EXPAND renames blocks and derives the content-addressed key" {
    root := path_slashes(tprint("%1/tests/data/test-blocks", otter_root()));
    file := tt_file(root, "src/greet.jai");
    output := transpile_test_file(file, 1);
    expect(output.diagnostics.count == 0 && output.tests.count == 2);
    expect(output.tests[0].name == "greeting" && output.tests[0].number == 1);
    expect(output.tests[1].name == tprint("src/greet.jai:%1", output.tests[1].line) && output.tests[1].number == 2);
    expect(find_index_from_left(output.view, "juice_test_1 :: () -> () {") >= 0);
    expect(find_index_from_left(output.view, "juice_test_2 :: () -> () {") >= 0);
    expect(find_index_from_left(output.view, "} @test") >= 0);
    source, ok := read_entire_file(file.abs_path);
    expect(ok);
    expect(output.key == transpile_view_key("src/greet.jai", source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION));
}

test "Test transpile: the global numbering continues across files" {
    root := path_slashes(tprint("%1/tests/data/test-blocks", otter_root()));
    greet := transpile_test_file(tt_file(root, "src/greet.jai"), 1);
    math := transpile_test_file(tt_file(root, "src/math.jai"), 1 + greet.tests.count);
    expect(greet.tests.count == 2);
    expect(math.tests.count == 2);
    // The caller threads the next start across files (ticket 023's
    // caller-side contract, wired by the t3 front).
    expect(math.tests[0].number == 3 && math.tests[0].name == "addition");
    expect(math.tests[1].number == 4);
    expect(find_index_from_left(math.view, "juice_test_3 :: () -> () {") >= 0);
    expect(find_index_from_left(math.view, "juice_test_4 :: () -> () {") >= 0);
}

test "Test transpile: a missing file reports a diagnostic" {
    output := transpile_test_file(.{rel_path = "src/none.jai", abs_path = "C:/no-such/file.jai"}, 1);
    expect(output.diagnostics.count == 1);
    expect(find_index_from_left(output.diagnostics[0].message, "无法读取测试源文件") >= 0);
    expect(output.view == "" && output.key == "" && output.tests.count == 0);
}

test "Test transpile: the declared pipeline enters the cache key" {
    root := path_slashes(tprint("%1/tests/data/test-blocks", otter_root()));
    file := tt_file(root, "src/greet.jai");
    default_output := transpile_test_file(file, 1);

    // The built-in declaration in the default order equals the undeclared
    // default (same pipeline description, same key).
    explicit_pipeline: [..] Transpile_Plugin;
    array_add(*explicit_pipeline, load_plugin());
    array_add(*explicit_pipeline, test_block_plugin());
    explicit_output := transpile_test_file(file, 1, explicit_pipeline);
    expect(explicit_output.diagnostics.count == 0);
    expect(explicit_output.key == default_output.key);

    // The reversed pipeline is a different pipeline description: same view
    // content, different key.
    reversed_pipeline: [..] Transpile_Plugin;
    array_add(*reversed_pipeline, test_block_plugin());
    array_add(*reversed_pipeline, load_plugin());
    reversed_output := transpile_test_file(file, 1, reversed_pipeline);
    expect(reversed_output.diagnostics.count == 0);
    expect(reversed_output.key != default_output.key);
}

// ===========================================================================
// t9: the Testing module compile view family
// ===========================================================================

test "Testing module source: the in-package module wins over the global one" {
    root := tt_scratch("tm-source");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "modules/Testing.jai", "test \"self\" { }\n"));
    file, in_package := testing_module_source(root);
    expect(in_package && file.rel_path == "modules/Testing.jai");
    expect(file.abs_path == path_slashes(tprint("%1/modules/Testing.jai", root)));
}

// The global module branch (adjacent to the running executable) cannot be
// unit-tested directly at compile time: during compile-time execution
// juice_modules_dir() resolves to the jai compiler's own modules directory,
// which carries no Testing.jai. That branch is covered end to end by the
// E2E child scenarios (real juice.exe on fixture packages — the published
// target/modules/Testing.jai landed by ensure_published_modules).

test "Testing module view: an absent module stays disabled" {
    root := tt_scratch("tm-absent");
    defer delete_directory_full(root);
    result, ok := testing_module_view(root, "", 1);
    expect(ok && !result.enabled);
    expect(result.dir == "" && result.view_path == "" && result.tests.count == 0);
    expect(result.next_test_number == 1);
}

test "Testing module view: a test-free module stays disabled" {
    root := tt_scratch("tm-testfree");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "modules/Testing.jai", "// no test blocks\n"));
    result, ok := testing_module_view(root, "", 1);
    expect(ok && !result.enabled);
    expect(result.dir == "" && result.view_path == "" && result.tests.count == 0);
    expect(result.next_test_number == 1);
}

test "Testing module view: in-package self-tests join with the support block" {
    root := tt_scratch("tm-inpackage");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "modules/Testing.jai", "test \"self one\" { }\ntest \"self two\" { }\n"));
    support_view := "\n// __testing_module_support_begin__\nhelper :: () {}\n// __testing_module_support_end__\n";
    result, ok := testing_module_view(root, support_view, 7);
    expect(ok && result.enabled && result.in_package);
    expect(result.tests.count == 2);
    expect(result.tests[0].name == "self one" && result.tests[0].number == 7 && result.tests[1].number == 8);
    expect(result.next_test_number == 9);
    expect(result.dir == path_slashes(target_testing_module_dir(package_target_dir(root))));
    expect(result.view_path == path_slashes(tprint("%1/Testing.jai", target_testing_module_dir(package_target_dir(root)))));
    expect(find_index_from_left(result.view_text, "juice_test_7 :: () -> () {") >= 0);
    expect(find_index_from_left(result.view_text, "__testing_module_support_begin__") >= 0);
}

test "Testing module view: missing support markers fail the computation" {
    root := tt_scratch("tm-nomarkers");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "modules/Testing.jai", "test \"self\" { }\n"));
    result, ok := testing_module_view(root, "// no markers\n", 1);
    expect(!ok && result.enabled);
}

test "Testing module support block: the cut keeps the marker-delimited segment" {
    expect(testing_module_support_block("// no markers\n") == "");
    block := testing_module_support_block("\n// __testing_module_support_begin__\nhelper_decl :: () -> s32 { return 1; }\n// __testing_module_support_end__\n");
    expect(find_index_from_left(block, "#scope_file;") >= 0);
    expect(find_index_from_left(block, "helper_decl :: () -> s32 { return 1; }") >= 0);
    expect(find_index_from_left(block, "#import \"Basic\";") >= 0);
    expect(find_index_from_left(block, "no markers") < 0);
}

// ===========================================================================
// The orchestration seam matrix (real transpile, recording collect/spawn)
// ===========================================================================

test "Test front: views land content-addressed with global numbering" {
    root := tt_scratch("front-views");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/a.jai", "#import \"Basic\";\n\ntest \"one\" {\n    expect(true);\n}\n"));
    expect(build_seam_write(root, "src/b.jai", "#import \"Basic\";\n\ntest \"two\" {\n    expect(true);\n}\n\ntest \"three\" {\n    expect(true);\n}\n"));
    files := Scan_File.[tt_file(root, "src/a.jai"), tt_file(root, "src/b.jai")];
    expect(tt_run(root, files));
    expect(test_test_collect_calls == 1 && test_test_spawn_calls == 1);
    expect(test_test_spawn_path == tprint("%1/test_runner.jai", transpile_tree_dir(root)));

    // Every file's view lives at the pure-function-derived path and carries
    // the EXPAND renames; the global numbering accumulates across files in
    // list order.
    transpile_dir := transpile_tree_dir(root);
    a_source, ok := read_entire_file(tprint("%1/src/a.jai", root));
    expect(ok);
    a_key := transpile_view_key("src/a.jai", a_source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION);
    a_view := transpile_view_path(transpile_dir, a_key, "src/a.jai");
    expect(file_contains(a_view, "juice_test_1 :: () -> () {"));
    expect(file_contains(a_view, "} @test"));
    b_source, ok2 := read_entire_file(tprint("%1/src/b.jai", root));
    expect(ok2);
    b_key := transpile_view_key("src/b.jai", b_source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION);
    b_view := transpile_view_path(transpile_dir, b_key, "src/b.jai");
    expect(file_contains(b_view, "juice_test_2 :: () -> () {"));
    expect(file_contains(b_view, "juice_test_3 :: () -> () {"));

    // The generated runner embeds the driver source and the view isolation
    // set in one file (the driver fold): the front-level contract pinned
    // here is the view list order (the driver #load order) and the absence
    // of original source paths. The driver text itself is byte-locked in
    // test_runner_tests.jai.
    runner, ok3 := read_entire_file(tprint("%1/test_runner.jai", transpile_dir));
    expect(ok3);
    package_views := test_program_package_view_paths(runner);
    expect(package_views.count == 2);
    expect(package_views[0] == a_view && package_views[1] == b_view);
    expect(find_index_from_left(runner, tprint("\"%1/src/a.jai\"", root)) < 0);
}

test "Test front: a cache hit leaves the existing view untouched" {
    root := tt_scratch("front-cache");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/a.jai", "#import \"Basic\";\n\ntest \"one\" {\n    expect(true);\n}\n"));
    files := Scan_File.[tt_file(root, "src/a.jai")];

    // Pre-plant a stale view at the content-addressed path.
    source, ok := read_entire_file(tprint("%1/src/a.jai", root));
    expect(ok);
    key := transpile_view_key("src/a.jai", source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION);
    stale_path := transpile_view_path(transpile_tree_dir(root), key, "src/a.jai");
    expect(make_directory_if_it_does_not_exist(path_strip_filename(stale_path), recursive = true));
    expect(write_entire_file(stale_path, "// stale cached view\n"));

    expect(tt_run(root, files));
    expect(test_test_spawn_calls == 1);
    // The pre-existing view was not overwritten (content addressing makes
    // stale views unreachable — nothing to invalidate).
    expect(file_contains(stale_path, "// stale cached view"));
    expect(!file_contains(stale_path, "juice_test_1"));
}

test "Test front: transpile diagnostics fail before compiling" {
    root := tt_scratch("front-diag");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/a.jai", "proc :: () {\n    test \"bad\" { }\n}\n"));
    files := Scan_File.[tt_file(root, "src/a.jai")];
    expect(!tt_run(root, files));
    expect(test_test_spawn_calls == 0);
    expect(!file_exists(transpile_tree_dir(root)));
}

test "Test front: the generated products embed the view isolation and mapping" {
    root := tt_scratch("front-products");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/a.jai", "#import \"Basic\";\n\ntest \"one\" {\n    expect(true);\n}\n"));
    expect(build_seam_write(root, "src/b.jai", "#import \"Basic\";\n\ntest \"two\" {\n    expect(true);\n}\n"));
    files := Scan_File.[tt_file(root, "src/a.jai"), tt_file(root, "src/b.jai")];
    expect(tt_run(root, files));

    transpile_dir := transpile_tree_dir(root);
    a_source, ok := read_entire_file(tprint("%1/src/a.jai", root));
    expect(ok);
    a_key := transpile_view_key("src/a.jai", a_source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION);
    a_view := transpile_view_path(transpile_dir, a_key, "src/a.jai");
    b_source, ok2 := read_entire_file(tprint("%1/src/b.jai", root));
    expect(ok2);
    b_key := transpile_view_key("src/b.jai", b_source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION);
    b_view := transpile_view_path(transpile_dir, b_key, "src/b.jai");

    // The metaprogram embeds the isolation set (the compiled views exactly
    // as the driver #loads them), the path mapping pairs, the numbering
    // base, the pattern constant, the intermediate directory and the
    // embedded driver string.
    metaprogram_path := tprint("%1/test_runner.jai", transpile_dir);
    expect(file_contains(metaprogram_path, tprint("string.[\"%1\", \"%2\"]", a_view, b_view)));
    expect(file_contains(metaprogram_path, tprint(".{ view = \"%1\", original = \"src/a.jai\" }", a_view)));
    expect(file_contains(metaprogram_path, tprint(".{ view = \"%1\", original = \"src/b.jai\" }", b_view)));
    expect(file_contains(metaprogram_path, "collect_test_entries(collected_sources, package_view_paths, whitelist_paths, 1)"));
    expect(file_contains(metaprogram_path, "pattern: string = \"\";"));
    expect(file_contains(metaprogram_path, tprint("options.intermediate_path = \"%1\";", target_build_dir(package_target_dir(root)))));
    expect(file_contains(metaprogram_path, "add_build_string("));

    // No Testing module wiring (the scratch package has none): the
    // whitelist stays empty and no view directory is prepended.
    expect(file_contains(metaprogram_path, "whitelist_paths: [] string = string.[];"));
    expect(!file_contains(metaprogram_path, "testing-module"));
}

test "Test front: the pattern reaches the generated metaprogram" {
    root := tt_scratch("front-pattern");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/a.jai", "#import \"Basic\";\n\ntest \"one\" {\n    expect(true);\n}\n"));
    files := Scan_File.[tt_file(root, "src/a.jai")];
    expect(tt_run(root, files, "one"));
    expect(file_contains(tprint("%1/test_runner.jai", transpile_tree_dir(root)), "pattern: string = \"one\";"));
}

test "Test front: the driver imports the published Testing face" {
    root := tt_scratch("front-face");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/plain.jai", "helper :: () -> s32 { return 1; }\n"));

    // The single face shape (ticket 035): the embedded driver always
    // imports the published Testing face; the retired source-face #load
    // and the discovered-face skip do not exist any more.
    files := Scan_File.[tt_file(root, "src/plain.jai")];
    expect(tt_run(root, files));
    runner, ok := read_entire_file(tprint("%1/test_runner.jai", transpile_tree_dir(root)));
    expect(ok);
    expect(find_index_from_left(runner, "add_build_string(") >= 0);
    expect(find_index_from_left(runner, "Testing") >= 0);
    expect(find_index_from_left(runner, "/target/transpile/") >= 0);
    expect(find_index_from_left(runner, "/src/module.jai") < 0);
}

test "Test front: the in-package Testing module wires the whitelist and view directory" {
    root := tt_scratch("front-module");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "modules/Testing.jai",
        "#import \"Basic\";\n\n#scope_export\n\nmodule_decl :: () -> s32 { return support_value(); }\n\ntest \"module self test\" {\n    assert(support_value() == 7);\n}\n"));
    expect(build_seam_write(root, "tests/test_support.jai",
        "#import \"Basic\";\n\n// __testing_module_support_begin__\nsupport_value :: () -> s32 { return 7; }\n// __testing_module_support_end__\n"));
    expect(build_seam_write(root, "src/consumer.jai", "#import \"Basic\";\n\ntest \"consumer\" {\n    expect(true);\n}\n"));
    files := Scan_File.[tt_file(root, "src/consumer.jai"), tt_file(root, "tests/test_support.jai")];
    expect(tt_run(root, files));

    // The module compile view: EXPAND with the continued numbering (the
    // consumer's block is juice_test_1) plus the support block.
    module_view := tprint("%1/Testing.jai", target_testing_module_dir(package_target_dir(root)));
    expect(file_contains(module_view, "juice_test_2 :: () -> () {"));
    expect(file_contains(module_view, "__testing_module_support_begin__"));

    // The metaprogram whitelists the module view (its @test notes join the
    // enumeration), prepends its directory (so `#import "Testing"` resolves
    // to the view) and maps its path back to modules/Testing.jai.
    metaprogram_path := tprint("%1/test_runner.jai", transpile_tree_dir(root));
    expect(file_contains(metaprogram_path, tprint("whitelist_paths: [] string = string.[\"%1\"];", module_view)));
    expect(file_contains(metaprogram_path, tprint("array_add(*import_paths, \"%1\");", target_testing_module_dir(package_target_dir(root)))));
    expect(file_contains(metaprogram_path, tprint(".{ view = \"%1\", original = \"modules/Testing.jai\" }", module_view)));
}

test "Test front: the dependency strip front rewrites test-bearing shims" {
    root := tt_scratch("front-deps");
    defer delete_directory_full(root);
    dep := tprint("%1/dep", root);
    expect(build_seam_write(dep, "module.jai", "#load \"extra.jai\";\ndep_value :: () -> s32 { return extra_value(); }\n"));
    expect(build_seam_write(dep, "extra.jai", "extra_value :: () -> s32 { return 42; }\n\ntest \"dep self test\" {\n    fail(\"must never run\");\n}\n"));
    expect(build_seam_write(root, "target/packages/depx.jai", dependency_shim_content("depx", tprint("%1/module.jai", dep))));
    expect(build_seam_write(root, "src/a.jai", "#import \"Basic\";\n\ntest \"root test\" {\n    expect(true);\n}\n"));
    files := Scan_File.[tt_file(root, "src/a.jai")];
    expect(tt_run(root, files));
    expect(test_test_spawn_calls == 1);

    // The shim now #loads the entry's strip view under the dependency
    // subtree; the closure's test block is stripped — no @test (the
    // dependency-tests-neither-discovered-nor-executed face).
    shim, ok := read_entire_file(tprint("%1/depx.jai", packages_dir(root)));
    expect(ok);
    entry_view, parsed := shim_load_target(shim);
    expect(parsed && find_index_from_left(entry_view, "/deps/depx/") >= 0);
    expect(path_exists_as_regular_file(entry_view));
    entry_text, ok2 := read_entire_file(entry_view);
    expect(ok2);
    child_view, parsed2 := shim_load_target(entry_text);
    expect(parsed2 && find_index_from_left(child_view, "/deps/depx/") >= 0);
    child_text, ok3 := read_entire_file(child_view);
    expect(ok3 && find_index_from_left(child_text, "// juice: test stripped") >= 0);
    expect(find_index_from_left(child_text, "@test") < 0);
}

test "Test front: a nonzero compiler exit fails the command" {
    root := tt_scratch("front-spawn-fail");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/a.jai", "#import \"Basic\";\n\ntest \"one\" {\n    expect(true);\n}\n"));
    files := Scan_File.[tt_file(root, "src/a.jai")];
    reset_test_command_seam();
    test_test_collect_files = files;
    test_test_spawn_exit_code = 1;
    prepared := tt_prepared(root);
    expect(!test_prepared_workspace(*prepared, "", Hook_Registration.[], test_collect_test_files, test_spawn_test_compiler));
    expect(test_test_spawn_calls == 1);
}

// The real collection composed into the orchestration: the static fixture's
// scan order and member pruning flow into the written driver (the member
// subtree never appears), and the products land under the fixture's
// target/transpile — removed after the test so the static fixture stays
// clean.
test "Test front: the real collection composes into the generated products" {
    root := path_slashes(tprint("%1/tests/data/scan-fixture", otter_root()));
    defer delete_directory_full(transpile_tree_dir(root));
    prepared := tt_prepared(root);
    prepared.discovery.member_packages = Juice.Package.[
        .{name = "scan-fixture", dir = prepared.discovery.root_dir},
        .{name = "member-a", dir = tprint("%1/member-a", root)},
    ];
    reset_test_command_seam();
    expect(test_prepared_workspace(*prepared, "", Hook_Registration.[], collect_test_files, test_spawn_test_compiler));
    expect(test_test_spawn_calls == 1);
    runner, ok := read_entire_file(tprint("%1/test_runner.jai", transpile_tree_dir(root)));
    expect(ok);
    expect(find_index_from_left(runner, "member-a") < 0);
    expect(find_index_from_left(runner, "target/h.jai") < 0);
    package_views := test_program_package_view_paths(runner);
    a_root := -1;
    deep := -1;
    tests_e := -1;
    for view, index: package_views {
        if ends_with(view, "/a_root.jai") a_root = index;
        if ends_with(view, "/lib_deep/package.jai") deep = index;
        if ends_with(view, "/tests/e.jai") tests_e = index;
    }
    expect(a_root >= 0 && deep >= 0 && tests_e >= 0 && a_root < deep && deep < tests_e);
}

// ===========================================================================
// t3 + PRESTEP (ticket 057): the per-file substitution/drop consumption —
// a substituted file reads its EXPAND source from the replacement while
// rel_path, numbering and path_mapping keep the original; a dropped file
// never enters the test program; an unmatched file reads its original.
// ===========================================================================

test "Test front: a substituted file expands the replacement source under the original path" {
    root := tt_scratch("prestep-substitute");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/a.jai", "#import \"Basic\";\n\noriginal_only :: () -> s32 { return 1; }\n\ntest \"original\" {\n    expect(true);\n}\n"));
    expect(build_seam_write(root, "src/b.jai", "#import \"Basic\";\n\ntest \"second\" {\n    expect(true);\n}\n"));
    replacement := path_slashes(tprint("%1/target/mirror/src/a.jai", root));
    expect(build_seam_write(root, "target/mirror/src/a.jai", "#import \"Basic\";\n\nreplacement_only :: () -> s32 { return 2; }\n\ntest \"replacement\" {\n    expect(true);\n}\n"));

    tt_reset();
    tt_prestep_reset();
    array_add(*TT_PRESTEP_SUBSTITUTIONS, .{original = "src/a.jai", replacement = replacement});
    table := tt_table(.[
        tt_hook(.PRESTEP, .before, tt_hook_p_before_fill),
        tt_hook(.PRESTEP, .after,  tt_hook_p_after),
    ]);
    files := Scan_File.[tt_file(root, "src/a.jai"), tt_file(root, "src/b.jai")];
    expect(tt_dispatch(root, files, "", table));
    expect(test_test_spawn_calls == 1);
    // PRESTEP fired between the zero-file short circuit and TRANSPILE.
    expect(TT_TRACE.count == 2 && TT_TRACE[0] == "p-before" && TT_TRACE[1] == "p-after");

    // The substituted file's view lands under its ORIGINAL rel_path and
    // carries the replacement's source; numbering continues across the
    // list (a's replacement test is juice_test_1, b's original is
    // juice_test_2).
    transpile_dir := transpile_tree_dir(root);
    replacement_source, ok := read_entire_file(replacement);
    expect(ok);
    a_key := transpile_view_key("src/a.jai", replacement_source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION);
    a_view := transpile_view_path(transpile_dir, a_key, "src/a.jai");
    expect(path_exists_as_regular_file(a_view));
    expect(file_contains(a_view, "replacement_only"));
    expect(file_contains(a_view, "juice_test_1 :: () -> () {"));
    b_source, ok2 := read_entire_file(tprint("%1/src/b.jai", root));
    expect(ok2);
    b_key := transpile_view_key("src/b.jai", b_source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION);
    b_view := transpile_view_path(transpile_dir, b_key, "src/b.jai");
    expect(path_exists_as_regular_file(b_view));
    expect(file_contains(b_view, "juice_test_2 :: () -> () {"));

    // The runner embeds both views' #loads and maps each view back to the
    // ORIGINAL package-relative path (the replacement never leaks into the
    // mapping).
    metaprogram, meta_ok := read_entire_file(tprint("%1/test_runner.jai", transpile_dir));
    expect(meta_ok);
    package_views := test_program_package_view_paths(metaprogram);
    expect(package_views.count == 2 && package_views[0] == a_view && package_views[1] == b_view);
    expect(find_index_from_left(metaprogram, tprint(".{ view = \"%1\", original = \"src/a.jai\" }", a_view)) >= 0);
    expect(find_index_from_left(metaprogram, tprint(".{ view = \"%1\", original = \"src/b.jai\" }", b_view)) >= 0);
    expect(find_index_from_left(metaprogram, "target/mirror") < 0);
}

test "Test front: a dropped file never enters the test program" {
    root := tt_scratch("prestep-drop");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/a.jai", "#import \"Basic\";\n\ntest \"dropped\" {\n    expect(true);\n}\n"));
    expect(build_seam_write(root, "src/b.jai", "#import \"Basic\";\n\ntest \"kept\" {\n    expect(true);\n}\n"));

    tt_prestep_reset();
    array_add(*TT_PRESTEP_DROPS, "src/a.jai");
    table := tt_table(.[
        tt_hook(.PRESTEP, .before, tt_hook_p_before_fill),
    ]);
    files := Scan_File.[tt_file(root, "src/a.jai"), tt_file(root, "src/b.jai")];
    expect(tt_dispatch(root, files, "", table));
    expect(test_test_spawn_calls == 1);

    // The dropped file produced no view and no path mapping: the runner
    // loads only b's view, the generated text carries only b's pair, and the
    // surviving file keeps the numbering base (juice_test_1 — the dropped
    // file never consumed a number).
    transpile_dir := transpile_tree_dir(root);
    a_source, ok := read_entire_file(tprint("%1/src/a.jai", root));
    expect(ok);
    a_key := transpile_view_key("src/a.jai", a_source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION);
    a_view := transpile_view_path(transpile_dir, a_key, "src/a.jai");
    expect(!file_exists(a_view));
    b_source, ok2 := read_entire_file(tprint("%1/src/b.jai", root));
    expect(ok2);
    b_key := transpile_view_key("src/b.jai", b_source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION);
    b_view := transpile_view_path(transpile_dir, b_key, "src/b.jai");
    expect(file_contains(b_view, "juice_test_1 :: () -> () {"));

    metaprogram, meta_ok := read_entire_file(tprint("%1/test_runner.jai", transpile_dir));
    expect(meta_ok);
    package_views := test_program_package_view_paths(metaprogram);
    expect(package_views.count == 1 && package_views[0] == b_view);
    expect(find_index_from_left(metaprogram, "/src/a.jai") < 0);
    expect(find_index_from_left(metaprogram, ".{ view = \"") >= 0);
    expect(find_index_from_left(metaprogram, "original = \"src/a.jai\"") < 0);
    expect(find_index_from_left(metaprogram, "original = \"src/b.jai\"") >= 0);

    // The filtered list is what the COMPILE stage sees: its file and view
    // counts drop to the surviving file (the COMPILE at recorder replaces
    // the compile front, so the products above stay the last word).
    tt_reset();
    capture_table := tt_table(.[
        tt_hook(.PRESTEP, .before, tt_hook_p_before_fill),
        tt_hook(.COMPILE, .at,     tt_hook_c_at_record),
    ]);
    expect(tt_dispatch(root, files, "", capture_table));
    expect(TT_CAPTURED_FILE_COUNT == 1);
    expect(TT_CAPTURED_VIEWS.count == 1 && TT_CAPTURED_VIEWS[0] == b_view);
}

test "Test front: an unmatched file reads its original source" {
    // The pre-step table covers other paths only: the collected file's
    // EXPAND source stays its original source (the view key pins the input
    // bytes).
    root := tt_scratch("prestep-miss");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/a.jai", "#import \"Basic\";\n\noriginal_only :: () -> s32 { return 1; }\n\ntest \"one\" {\n    expect(true);\n}\n"));

    tt_prestep_reset();
    array_add(*TT_PRESTEP_SUBSTITUTIONS, .{original = "src/other.jai", replacement = path_slashes(tprint("%1/target/mirror/src/other.jai", root))});
    array_add(*TT_PRESTEP_DROPS, "src/unused.jai");
    table := tt_table(.[
        tt_hook(.PRESTEP, .before, tt_hook_p_before_fill),
    ]);
    expect(tt_dispatch(root, Scan_File.[tt_file(root, "src/a.jai")], "", table));
    expect(test_test_spawn_calls == 1);

    source, ok := read_entire_file(tprint("%1/src/a.jai", root));
    expect(ok);
    key := transpile_view_key("src/a.jai", source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION);
    view := transpile_view_path(transpile_tree_dir(root), key, "src/a.jai");
    expect(path_exists_as_regular_file(view));
    expect(file_contains(view, "original_only"));
    expect(file_contains(view, "juice_test_1 :: () -> () {"));
}

// ===========================================================================
// The PRESTEP/TRANSPILE/COMPILE hook dispatch (the 004 decision 17
// representative subset extended by ticket 057's pre-step stage, the ticket
// 027 build-side shape)
// ===========================================================================

test "Test dispatch: hooks fire in stage order and registration order" {
    root := tt_scratch_package("dispatch-order");
    defer delete_directory_full(root);
    tt_reset();

    // Two registrations: registration order pins the before order across
    // registrations (forward, 021); the at hooks replace both built-in
    // implementations.
    table: [..] Hook_Registration;
    register_hooks(*table, .[
        tt_hook(.TRANSPILE, .before, tt_hook_t_before_a),
        tt_hook(.TRANSPILE, .at,     tt_hook_t_at_fill),
        tt_hook(.TRANSPILE, .after,  tt_hook_t_after_a),
        tt_hook(.COMPILE,  .before,  tt_hook_c_before_a),
        tt_hook(.COMPILE,  .at,      tt_hook_c_at_record),
        tt_hook(.COMPILE,  .after,   tt_hook_c_after_a),
    ]);
    register_hooks(*table, .[
        tt_hook(.TRANSPILE, .before, tt_hook_t_before_b),
        tt_hook(.COMPILE,  .before,  tt_hook_c_before_b),
    ]);

    expect(tt_dispatch(root, tt_scratch_files(root), "pat", table));
    expect(TT_TRACE.count == 8);
    expect(TT_TRACE[0] == "t-before-a" && TT_TRACE[1] == "t-before-b");
    expect(TT_TRACE[2] == "t-at" && TT_TRACE[3] == "t-after-a");
    expect(TT_TRACE[4] == "c-before-a" && TT_TRACE[5] == "c-before-b");
    expect(TT_TRACE[6] == "c-at" && TT_TRACE[7] == "c-after-a");
    // The hook-filled views, the transpile dir, the file count and the
    // pattern reached the compile stage through the stage state channel.
    expect(TT_CAPTURED_VIEWS.count == 1 && TT_CAPTURED_VIEWS[0] == "hook-view");
    expect(TT_CAPTURED_DIR == "hook-transpile");
    expect(TT_CAPTURED_FILE_COUNT == 1 && TT_CAPTURED_PATTERN == "pat");
}

test "Test dispatch: with no at mount the built-in front runs between the hooks" {
    root := tt_scratch_package("dispatch-builtin");
    defer delete_directory_full(root);
    tt_reset();

    table := tt_table(.[
        tt_hook(.TRANSPILE, .before, tt_hook_t_before_a),
        tt_hook(.TRANSPILE, .after,  tt_hook_t_after_a),
        tt_hook(.COMPILE,  .at,      tt_hook_c_at_record),
    ]);

    expect(tt_dispatch(root, tt_scratch_files(root), "", table));
    expect(TT_TRACE.count == 3);
    expect(TT_TRACE[0] == "t-before-a" && TT_TRACE[1] == "t-after-a" && TT_TRACE[2] == "c-at");
    // The built-in front ran between the before and after hooks: the view
    // landed and the COMPILE stage received the content-addressed path.
    expect(TT_CAPTURED_VIEWS.count == 1);
    expect(find_index_from_left(TT_CAPTURED_VIEWS[0], "/target/transpile/") >= 0);
    expect(path_exists_as_regular_file(TT_CAPTURED_VIEWS[0]));
    expect(TT_CAPTURED_DIR == transpile_tree_dir(root));
}

test "Test dispatch: a mounted at hook replaces the built-in implementation" {
    root := tt_scratch_package("dispatch-at");
    defer delete_directory_full(root);
    tt_reset();

    table := tt_table(.[
        tt_hook(.TRANSPILE, .at, tt_hook_t_at_fill),
        tt_hook(.COMPILE,  .at, tt_hook_c_at_record),
    ]);

    expect(tt_dispatch(root, tt_scratch_files(root), "", table));
    expect(TT_TRACE.count == 2);
    expect(TT_TRACE[0] == "t-at" && TT_TRACE[1] == "c-at");
    // The built-in front was skipped: no transpile tree, no driver, no
    // spawn.
    expect(!file_exists(transpile_tree_dir(root)));
    expect(test_test_spawn_calls == 0);
    // The hook-owned views reached the compile stage.
    expect(TT_CAPTURED_VIEWS.count == 1 && TT_CAPTURED_VIEWS[0] == "hook-view");
}

test "Test dispatch: a before hook failure aborts before the built-in runs" {
    root := tt_scratch_package("dispatch-before-fail");
    defer delete_directory_full(root);
    tt_reset();

    table := tt_table(.[
        tt_hook(.TRANSPILE, .before, tt_hook_t_before_a),
        tt_hook(.TRANSPILE, .before, tt_hook_fail),
        tt_hook(.COMPILE,  .at,      tt_hook_c_at_record),
    ]);

    expect(!tt_dispatch(root, tt_scratch_files(root), "", table));
    // Fail fast: the failing hook is the last to run — the built-in front
    // and every later hook (the COMPILE at included) never fire.
    expect(TT_TRACE.count == 2);
    expect(TT_TRACE[0] == "t-before-a" && TT_TRACE[1] == "fail");
    expect(!file_exists(transpile_tree_dir(root)));
}

test "Test dispatch: an ERROR diagnostic fails the stage, a WARNING passes" {
    root := tt_scratch_package("dispatch-diag");
    defer delete_directory_full(root);
    tt_reset();

    table := tt_table(.[
        tt_hook(.TRANSPILE, .before, tt_hook_error),
        tt_hook(.TRANSPILE, .before, tt_hook_t_before_a),
    ]);
    expect(!tt_dispatch(root, tt_scratch_files(root), "", table));
    // The ERROR aborts the dispatch: the later before hook never fires.
    expect(TT_TRACE.count == 1 && TT_TRACE[0] == "error");

    tt_reset();
    table2 := tt_table(.[
        tt_hook(.TRANSPILE, .before, tt_hook_warning),
        tt_hook(.TRANSPILE, .at,     tt_hook_t_at_fill),
        tt_hook(.COMPILE,  .at,      tt_hook_c_at_record),
    ]);
    expect(tt_dispatch(root, tt_scratch_files(root), "", table2));
    expect(TT_TRACE.count == 3);
    expect(TT_TRACE[0] == "warning" && TT_TRACE[1] == "t-at" && TT_TRACE[2] == "c-at");
}

test "Test dispatch: an at hook failure aborts the test" {
    root := tt_scratch_package("dispatch-at-fail");
    defer delete_directory_full(root);
    tt_reset();

    table := tt_table(.[
        tt_hook(.TRANSPILE, .at,    tt_hook_fail),
        tt_hook(.TRANSPILE, .after, tt_hook_t_after_a),
        tt_hook(.COMPILE,  .at,     tt_hook_c_at_record),
    ]);

    expect(!tt_dispatch(root, tt_scratch_files(root), "", table));
    // The at failure aborts before the after hook and every later stage.
    expect(TT_TRACE.count == 1 && TT_TRACE[0] == "fail");
}

test "Test dispatch: an after hook failure aborts the test" {
    root := tt_scratch_package("dispatch-after-fail");
    defer delete_directory_full(root);
    tt_reset();

    table := tt_table(.[
        tt_hook(.TRANSPILE, .at,    tt_hook_t_at_fill),
        tt_hook(.TRANSPILE, .after, tt_hook_fail),
        tt_hook(.COMPILE,  .at,     tt_hook_c_at_record),
    ]);

    expect(!tt_dispatch(root, tt_scratch_files(root), "", table));
    expect(TT_TRACE.count == 2);
    expect(TT_TRACE[0] == "t-at" && TT_TRACE[1] == "fail");
    // The COMPILE stage never ran after the failure (no c-at entry).
}

test "Test dispatch: zero files run no stage and fire no hook" {
    tt_reset();
    tt_prestep_reset();

    table := tt_table(.[
        tt_hook(.PRESTEP,  .before, tt_hook_p_before_fill),
        tt_hook(.PRESTEP,  .after,  tt_hook_p_after),
        tt_hook(.TRANSPILE, .before, tt_hook_t_before_a),
        tt_hook(.COMPILE,  .at,      tt_hook_c_at_record),
    ]);
    reset_test_command_seam();
    test_test_collect_files = Scan_File.[];
    prepared := tt_prepared(otter_scratch("tt-dispatch-zero"));
    expect(test_prepared_workspace(*prepared, "", table, test_collect_test_files, test_spawn_test_compiler));
    // The zero-file short circuit precedes PRESTEP: the pre-step hooks never
    // fire (the same posture as every later stage).
    expect(TT_TRACE.count == 0);
    expect(test_test_spawn_calls == 0);
}

test "Test dispatch: the host fills plugin_state slots null" {
    root := tt_scratch_package("dispatch-slots");
    defer delete_directory_full(root);
    tt_reset();

    table := tt_table(.[
        tt_hook(.TRANSPILE, .before, tt_hook_state_probe),
        tt_hook(.TRANSPILE, .at,     tt_hook_t_at_fill),
        tt_hook(.COMPILE,  .at,      tt_hook_c_at_record),
    ]);

    expect(tt_dispatch(root, tt_scratch_files(root), "", table));
    // The host owns the slot storage and constructs it null (the 021 slot
    // protocol's construction-time null convention).
    expect(TT_TRACE.count == 3);
    expect(TT_TRACE[0] == "state-null");
    expect(TT_TRACE[1] == "t-at" && TT_TRACE[2] == "c-at");
}

test "Test dispatch: PRESTEP fires before TRANSPILE with the stage's directories" {
    root := tt_scratch_package("dispatch-prestep");
    defer delete_directory_full(root);
    tt_reset();
    tt_prestep_reset();

    // The committed discovery snapshot: the root first, then one member —
    // the pre-step stage's member_dirs carries the member only.
    prepared := tt_prepared(root);
    members: [..] Juice.Package;
    array_add(*members, .{name = "demo", dir = root});
    member_dir := path_slashes(tprint("%1/packages/member-a", root));
    array_add(*members, .{name = "member-a", dir = member_dir});
    prepared.discovery.member_packages = members;

    reset_test_command_seam();
    test_test_collect_files = tt_scratch_files(root);
    table := tt_table(.[
        tt_hook(.PRESTEP,  .before, tt_hook_p_before_fill),
        tt_hook(.PRESTEP,  .after,  tt_hook_p_after),
        tt_hook(.TRANSPILE, .at,     tt_hook_t_at_fill),
        tt_hook(.COMPILE,  .at,      tt_hook_c_at_record),
    ]);
    expect(test_prepared_workspace(*prepared, "", table, test_collect_test_files, test_spawn_test_compiler));
    // The stage order: PRESTEP (before -> after) between the zero-file
    // short circuit and TRANSPILE; the whole chain keeps registration order.
    expect(TT_TRACE.count == 4);
    expect(TT_TRACE[0] == "p-before" && TT_TRACE[1] == "p-after");
    expect(TT_TRACE[2] == "t-at" && TT_TRACE[3] == "c-at");
    expect(TT_PRESTEP_ROOT == root);
    expect(TT_PRESTEP_MEMBERS.count == 1 && TT_PRESTEP_MEMBERS[0] == member_dir);
}

test "Test dispatch: a conflicting pre-step table fails the test command" {
    // The same path in both tables: the stage-level ERROR fails the command
    // before any compile (the fake hook returns the API's false).
    root := tt_scratch_package("dispatch-prestep-conflict");
    defer delete_directory_full(root);
    tt_reset();
    tt_prestep_reset();
    array_add(*TT_PRESTEP_SUBSTITUTIONS, .{original = "src/a.jai", replacement = "C:/mirror/a.jai"});
    array_add(*TT_PRESTEP_DROPS, "src/a.jai");

    table := tt_table(.[
        tt_hook(.PRESTEP, .before, tt_hook_p_before_fill),
        tt_hook(.COMPILE, .at,     tt_hook_c_at_record),
    ]);
    expect(!tt_dispatch(root, tt_scratch_files(root), "", table));
    expect(TT_TRACE.count == 1 && TT_TRACE[0] == "p-before");
    expect(test_test_spawn_calls == 0);
}



// ===========================================================================
// E2E: the real otter exe on the 1c fixtures (test blocks -> EXPAND -> @test
// -> note enumeration -> execution)
// ===========================================================================

test "E2E: the test-block fixture expands, discovers and runs every test" {
    fixture_root := path_slashes(tprint("%1/tests/data/test-blocks", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    result, output, _ := run_otter_child_at(fixture_root, string.["test"]);
    expect(expect_exit("test-blocks", result, 0));
    expect(output_matches("test-blocks", output, string.[
        "[test] juice_test_1",
        "[test] juice_test_2",
        "[test] juice_test_3",
        "[test] juice_test_4",
        "4 passed, 0 failed",
    ]));

    // The deterministic order: the numeric-aware name sort on the generated
    // names (the numbering follows the scan order — greet.jai first).
    n1 := find_index_from_left(output, "[test] juice_test_1");
    n2 := find_index_from_left(output, "[test] juice_test_2");
    n3 := find_index_from_left(output, "[test] juice_test_3");
    n4 := find_index_from_left(output, "[test] juice_test_4");
    expect(n1 >= 0 && n1 < n2 && n2 < n3 && n3 < n4);

    // The views land at the pure-contract paths: greet.jai's EXPAND view
    // carries the renamed blocks and the @test notes.
    transpile_dir := transpile_tree_dir(fixture_root);
    greet_source, ok := read_entire_file(tprint("%1/src/greet.jai", fixture_root));
    expect(ok);
    greet_key := transpile_view_key("src/greet.jai", greet_source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION);
    greet_view := transpile_view_path(transpile_dir, greet_key, "src/greet.jai");
    expect(path_exists_as_regular_file(greet_view));
    expect(file_contains(greet_view, "juice_test_1 :: () -> () {"));
    expect(file_contains(greet_view, "juice_test_2 :: () -> () {"));
    expect(file_contains(greet_view, "} @test"));
    // The regenerated (uncached) product lives at the tree root: one runner
    // with the driver embedded.
    expect(file_exists(tprint("%1/test_runner.jai", transpile_dir)));
    // The runner loads the views, never the original sources.
    runner, ok2 := read_entire_file(tprint("%1/test_runner.jai", transpile_dir));
    expect(ok2);
    package_views := test_program_package_view_paths(runner);
    found_greet := false;
    for view: package_views {
        if view == greet_view found_greet = true;
    }
    expect(found_greet);
    expect(find_index_from_left(runner, tprint("#load \"%1/src/greet.jai\";", fixture_root)) < 0);
}

test "E2E: a failing test-block reports the original file:line and exits 1" {
    fixture_root := path_slashes(tprint("%1/tests/data/test-blocks-fail", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    result, output, _ := run_otter_child_at(fixture_root, string.["test"]);
    expect(expect_exit("test-blocks-fail", result, 1));

    line, col := fixture_line_col(tprint("%1/src/math.jai", fixture_root), "expect_eq(add(2, 3), 99)");
    expect(line != 0);
    // The failure line points at the original package-relative coordinates:
    // the driver-injected mapping table rewrote the view path (the EXPAND
    // pass preserves line numbers).
    expect(output_matches("test-blocks-fail", output, string.[
        "[test] juice_test_1",
        tprint("src/math.jai:%1:%2: expect_eq failed: expected 5, got 99", line, col),
        "0 passed, 1 failed",
        "[juice ERROR] Test compilation failed.",
    ]));
    // The real view path never leaks through the mapping.
    expect(output_matches("test-blocks-fail", output, string.["target/transpile"], want = false));
}

test "E2E: the pattern filters the generated test-block names" {
    fixture_root := path_slashes(tprint("%1/tests/data/test-blocks", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    result, output, _ := run_otter_child_at(fixture_root, string.["test", "juice_test_3"]);
    expect(expect_exit("test-blocks pattern", result, 0));
    expect(output_matches("test-blocks pattern", output, string.["[test] juice_test_3", "1 passed, 0 failed"]));
    expect(output_matches("test-blocks pattern", output, string.["[test] juice_test_2", "[test] juice_test_4"], want = false));
}

test "E2E: dependency tests are neither discovered nor executed" {
    fixture_root := path_slashes(tprint("%1/tests/data/test-dep-root", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    result, output, _ := run_otter_child_at(fixture_root, string.["test"]);
    expect(expect_exit("test-dep-root", result, 0));
    expect(output_matches("test-dep-root", output, string.["[test] juice_test_1", "1 passed, 0 failed"]));
    // The dependency's test block never reaches the test program.
    expect(output_matches("test-dep-root", output, string.["dep self test", "must never run"], want = false));

    // The shim was rewritten to the entry strip view; the closure's test
    // block is stripped (no @test).
    shim, ok := read_entire_file(tprint("%1/test_dep.jai", packages_dir(fixture_root)));
    expect(ok);
    entry_view, parsed := shim_load_target(shim);
    expect(parsed && find_index_from_left(entry_view, "/deps/test_dep/") >= 0);
    expect(path_exists_as_regular_file(entry_view));
    entry_text, ok2 := read_entire_file(entry_view);
    expect(ok2);
    child_view, parsed2 := shim_load_target(entry_text);
    expect(parsed2 && find_index_from_left(child_view, "/deps/test_dep/") >= 0);
    child_text, ok3 := read_entire_file(child_view);
    expect(ok3 && find_index_from_left(child_text, "// juice: test stripped") >= 0);
    expect(find_index_from_left(child_text, "@test") < 0);
}

test "E2E: the in-package Testing module self-tests run through the compile view" {
    root := otter_scratch("tt-e2e-module");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"test-module-self\",\n    version = \"0.1.0\",\n    type    = .BIN,\n};\n"));
    expect(build_seam_write(root, "modules/Testing.jai",
        "#import \"Basic\";\n\n#scope_export\n\n// A tiny in-package Testing face: the compile view special case (t9)\n// EXPANDs this file with continued numbering and appends the test support\n// segment, so the self-test runs through the generated compile view. Since\n// ticket 035 the generated driver imports this module for the bare names\n// (the single register), so the module must carry the run/finish/\n// path_mapping API the injected runner drives.\nTesting_Path_Pair :: struct {\n    view:     string;\n    original: string;\n}\n\npath_mapping : [..] Testing_Path_Pair;\n\npassed_count: s32 = 0;\n\nexpect_eq :: (expected: $T, actual: T) {\n    if expected != actual assert(false);\n}\n\nrun :: (name: string, proc: () -> ()) {\n    print(\"[test] %\\n\", name);\n    proc();\n    passed_count += 1;\n}\n\nfinish :: () -> s32 {\n    print(\"% passed, 0 failed\\n\", passed_count);\n    passed_count = 0;\n    return 0;\n}\n\nmodule_decl :: () -> s32 {\n    return support_value();\n}\n\ntest \"module self test\" {\n    assert(support_value() == 7);\n}\n"));
    expect(build_seam_write(root, "tests/test_support.jai",
        "#import \"Basic\";\n\n// __testing_module_support_begin__\nsupport_value :: () -> s32 {\n    return 7;\n}\n// __testing_module_support_end__\n"));
    expect(build_seam_write(root, "src/consumer.jai",
        "#import \"Basic\";\n#import \"Testing\";\n\n// The consumer imports the package's own Testing module: the metaprogram\n// prepends the compile view directory, so the import resolves to the\n// EXPAND view instead of the raw module source (whose inline test block\n// cannot compile directly).\nconsume_module :: () -> s32 {\n    return module_decl();\n}\n\ntest \"consumer uses the module\" {\n    expect_eq(consume_module(), 7);\n}\n"));
    result, output, _ := run_otter_child_at(root, string.["test"]);
    expect(expect_exit("test-module-self", result, 0));
    // The consumer's test (juice_test_1) and the module's self-test
    // (juice_test_2, discovered through the whitelist) both run.
    expect(output_matches("test-module-self", output, string.[
        "[test] juice_test_1",
        "[test] juice_test_2",
        "2 passed, 0 failed",
    ]));
    // The module compile view carries the continued numbering and the
    // support block, written at its established place.
    module_view := tprint("%1/Testing.jai", target_testing_module_dir(package_target_dir(root)));
    expect(file_contains(module_view, "juice_test_2 :: () -> () {"));
    expect(file_contains(module_view, "__testing_module_support_begin__"));
}
