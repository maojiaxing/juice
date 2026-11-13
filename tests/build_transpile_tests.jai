// ---------------------------------------------------------------------------
// Build transpile wiring tests (ticket 027): the b5 dependency strip front,
// the b7 entry selection, the declared-pipeline assembly (src/transpile_
// config.jai), the TRANSPILE/COMPILE lifecycle hook dispatch of
// build_prepared_workspace and the Testing module view directory emission —
// plus the real-otter-exe E2E on the build-with-tests fixture (old juice
// build.jai inline test semantics, rewritten not copied). Pinned behavior:
// a test-free closure compiles the original entry with zero transpile, a
// test-bearing closure views all-or-nothing with the load rewrites; the
// dependency strip front rewrites only shims of test-bearing dependencies
// into deps/<name>/ views; the dispatch fires before (forward, across
// registrations) -> at (replaces the built-in) | built-in -> after
// (forward); any hook failure (false or ERROR diagnostic) aborts the build
// (HANDLER_FAILED through the dispatcher).
//
// Key constraint (same as the other sibling test files): src modules are
// bootstrap #load targets / entry closure members — test blocks would be
// illegal inside them, so this module stays test-free and its tests live
// here (tests/), per the test organization rule: referenced by no #load,
// collected into the test program by Test discovery's full-package scan.
// This file contains only test blocks and their helper declarations (all
// prefixed bt_ — the single-namespace convention); zero production code
// coupling. Good-test standard: only external behavior is pinned (given
// package roots / hook tables -> views / trace / entries / exit codes).
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";

// ===========================================================================
// Recording hook machinery
// ===========================================================================
//
// The build host owns the lifecycle context and fills the plugin_state
// slots null (host-owned storage, the 021 slot protocol), so per-hook state
// cannot travel through the slots here — and Jai has no closures. One named
// procedure per recording behavior appends to the shared trace instead.

BT_TRACE: [..] string;

bt_reset :: () {
    array_reset(*BT_TRACE);
    // The capture sink belongs to the COMPILE at recorder; clearing it here
    // keeps tests that never reach the COMPILE stage from observing a
    // previous test's capture.
    array_reset(*BT_CAPTURED_ENTRIES);
}

bt_record :: (label: string) {
    array_add(*BT_TRACE, copy_string(label));
}

// The COMPILE at recorder captures the stage's entries for assertions.
BT_CAPTURED_ENTRIES: [..] string;

bt_capture_entries :: (ctx: *Lifecycle_Context) {
    stage := cast(*Build_Compile_Stage) ctx.artifact_paths;
    array_reset(*BT_CAPTURED_ENTRIES);
    for e: stage.entries array_add(*BT_CAPTURED_ENTRIES, copy_string(e));
}

bt_hook_t_before_a :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("t-before-a");
    return true;
}

bt_hook_t_before_b :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("t-before-b");
    return true;
}

bt_hook_t_after_a :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("t-after-a");
    return true;
}

bt_hook_c_before_a :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("c-before-a");
    return true;
}

bt_hook_c_before_b :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("c-before-b");
    return true;
}

bt_hook_c_after_a :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("c-after-a");
    return true;
}

// The TRANSPILE at recorder: replaces the built-in front and fills one
// entry per plan (the at hook owns the stage's outputs).
bt_hook_t_at_fill :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("t-at");
    stage := cast(*Build_Transpile_Stage) ctx.views;
    for _: stage.prepared.artifact_plans array_add(*stage.entries, "hook-entry");
    return true;
}

// The COMPILE at recorder: replaces the built-in loop.
bt_hook_c_at_record :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("c-at");
    bt_capture_entries(ctx);
    return true;
}

// The slot probe: the build host fills slots null (host-owned storage).
bt_hook_state_probe :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record(ifx state == null then "state-null" else "state-set");
    return true;
}

// Failure and diagnostic behaviors.
bt_hook_fail :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("fail");
    return false;
}

bt_hook_error :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("error");
    array_add(ctx.diagnostics, .{level = .ERROR, message = "bt error"});
    return true;
}

bt_hook_warning :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("warning");
    array_add(ctx.diagnostics, .{level = .WARNING, message = "bt warning"});
    return true;
}

// Hook and table assembly helpers.
bt_hook :: (stage: Lifecycle_Stage, position: Hook_Position, hook: #type (ctx: *Lifecycle_Context, state: *void) -> bool) -> Lifecycle_Hook {
    return .{stage = stage, position = position, hook = hook};
}

bt_table :: (hooks: [] Lifecycle_Hook) -> [..] Hook_Registration {
    table: [..] Hook_Registration;
    register_hooks(*table, hooks);
    return table;
}

// A prepared workspace over a fresh scratch root (the revalidation gate
// probes real files): one plan with an existing test-free entry. The
// fixture write's failure surfaces through the downstream assertions (the
// expect macro's bare return cannot abort a value-returning helper).
bt_prepared :: (root: string) -> Juice.Prepared_Workspace {
    build_seam_write(root, "src/main.jai", "main :: () {}\n");
    plan := build_seam_plan(root, "src/main.jai");
    return build_seam_prepared(root, plan);
}

bt_scratch :: (name: string) -> string {
    root := otter_scratch(tprint("bt-%1", name));
    delete_directory_full(root);
    return root;
}

// The declaration-driven pipeline for a prepared workspace (the command's
// single resolution; build_plan_entry consumes the result — ticket 056).
bt_pipeline :: (prepared: *Juice.Prepared_Workspace) -> [] Transpile_Plugin {
    return resolve_package_plugins(prepared.discovery.root_package.plugins).pipeline;
}

// ---------------------------------------------------------------------------
// PRESTEP consumption (ticket 057): the recording fake pre-step plugin across
// the same lifecycle hook face (it reads the stage through ctx.prestep and
// fills the tables through the stage-level API). No jaix dependency.
// ---------------------------------------------------------------------------

BT_PRESTEP_SUBSTITUTIONS: [..] Source_Substitution;
BT_PRESTEP_DROPS: [..] string;
BT_PRESTEP_ROOT: string;
BT_PRESTEP_MEMBERS: [..] string;

bt_prestep_reset :: () {
    array_reset(*BT_PRESTEP_SUBSTITUTIONS);
    array_reset(*BT_PRESTEP_DROPS);
    BT_PRESTEP_ROOT = "";
    array_reset(*BT_PRESTEP_MEMBERS);
}

bt_hook_p_before_fill :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("p-before");
    stage := cast(*Prestep_Stage) ctx.prestep;
    BT_PRESTEP_ROOT = stage.root_dir;
    array_reset(*BT_PRESTEP_MEMBERS);
    for dir: stage.member_dirs array_add(*BT_PRESTEP_MEMBERS, copy_string(dir));
    for s: BT_PRESTEP_SUBSTITUTIONS {
        if !prestep_add_substitution(ctx, s.original, s.replacement) return false;
    }
    for d: BT_PRESTEP_DROPS {
        if !prestep_add_drop(ctx, d) return false;
    }
    return true;
}

bt_hook_p_after :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("p-after");
    return true;
}

bt_hook_p_fail :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("p-fail");
    return false;
}

// Adds a conflicting row and returns true on purpose: the stage-level API's
// ERROR diagnostic alone must fail the stage (the dispatch's ordinary rule).
bt_hook_p_conflict_returns_true :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    bt_record("p-conflict");
    if !prestep_add_substitution(ctx, "src/main.jai", "C:/mirror/one.jai") return false;
    ok := prestep_add_substitution(ctx, "src/main.jai", "C:/mirror/two.jai");
    bt_record(ifx ok then "second-accepted" else "second-rejected");
    return true;
}

// ===========================================================================
// transpile_config: the declared plugin resolution
// ===========================================================================

test "The declared plugin resolver preserves declaration order" {
    resolved := resolve_package_plugins(.[
        .{id = "test-block", version = "1.0.0"},
        .{id = "load", version = "1.0.0"},
    ]);
    expect(resolved.ok);
    expect(resolved.pipeline.count == 2);
    expect(resolved.pipeline[0].name == "test-block");
    expect(resolved.pipeline[1].name == "load");
}

test "The declared plugin resolver yields the default pipeline for zero transpile declarations" {
    // The resolver's face default (ticket 056): no declared transpile face
    // means [load, test-block] — the same pipeline the executor's empty
    // convention resolves to, so a view and its key always agree.
    resolved := resolve_package_plugins(.[]);
    expect(resolved.ok);
    expect(resolved.diagnostics.count == 0);
    expect(resolved.pipeline.count == 2);
    expect(resolved.pipeline[0].name == "load");
    expect(resolved.pipeline[1].name == "test-block");
    expect(resolve_pipeline(resolved.pipeline).count == 2);

    // A member-plugin declaration (not a built-in id) is skipped by the
    // command-side adapter (Phase-1 boundary: member values exist only in
    // the generated test metaprogram / Phase-2 host) and does not disturb
    // the default pipeline.
    member := resolve_package_plugins(.[
        .{id = "juice-plugin-lint", version = "0.1.0"},
    ]);
    expect(member.ok);
    expect(member.pipeline.count == 2);
    expect(member.pipeline[0].name == "load" && member.pipeline[1].name == "test-block");
}

test "The command-side resolver skips non-builtin ids and rejects bad builtin versions" {
    resolved := resolve_package_plugins(.[
        .{id = "load", version = "1.0.0"},
        .{id = "mystery", version = "1.0.0"},
    ]);
    expect(resolved.ok);
    expect(resolved.pipeline.count == 1);
    expect(resolved.pipeline[0].name == "load");

    // A declared built-in version must equal the plugin's own version (the
    // resolver's semantic gate; member versions are checked where their
    // values exist).
    bad := resolve_package_plugins(.[
        .{id = "load", version = "9.9.9"},
    ]);
    expect(!bad.ok);
    expect(bad.diagnostics.count == 1);
    expect(bad.diagnostics[0].message == "plugin version mismatch: load (declared 9.9.9, plugin 1.0.0)");
}

test "The resolved pipeline is exactly the view key's pipeline description" {
    // The acceptance pin: the key computed from the resolver's pipeline is
    // the key the transpile front produces (same description -> same key;
    // a reorder changes it).
    source := "x := 1;\n";
    default_resolved := resolve_package_plugins(.[]);
    reversed := resolve_package_plugins(.[
        .{id = "test-block", version = "1.0.0"},
        .{id = "load", version = "1.0.0"},
    ]);
    expect(default_resolved.ok && reversed.ok);
    key_default := transpile_view_key("src/a.jai", source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION, default_resolved.pipeline);
    key_default_again := transpile_view_key("src/a.jai", source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION, default_resolved.pipeline);
    key_reversed := transpile_view_key("src/a.jai", source, .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION, reversed.pipeline);
    expect(key_default == key_default_again);
    expect(key_default != key_reversed);
}

// ===========================================================================
// b5: the dependency strip front
// ===========================================================================

test "Dependency strip: shim load target parses the generated shape" {
    entry, ok := shim_load_target(dependency_shim_content("packrat", "C:/repo/src/module.jai"));
    expect(ok && entry == "C:/repo/src/module.jai");
    _, parsed := shim_load_target("// hand-written\nsome_decl :: 1;\n");
    expect(!parsed);
}

test "Dependency strip: a test-free dependency keeps its shim untouched" {
    root := bt_scratch("dep-clean");
    defer delete_directory_full(root);
    dep := tprint("%1/dep", root);
    expect(build_seam_write(dep, "src/module.jai", "#load \"extra.jai\";\nmain_decl :: () -> s32 { return 1; }\n"));
    expect(build_seam_write(dep, "src/extra.jai", "extra_decl :: () -> s32 { return 2; }\n"));
    expect(build_seam_write(root, "target/packages/depx.jai", dependency_shim_content("depx", tprint("%1/src/module.jai", dep))));

    expect(prepare_dependency_strip_views(root));
    // The shim stays byte-identical (no strip, no rewrite) and no transpile
    // tree was created.
    shim, ok := read_entire_file(tprint("%1/depx.jai", packages_dir(root)));
    expect(ok && shim == dependency_shim_content("depx", tprint("%1/src/module.jai", dep)));
    expect(!file_exists(transpile_tree_dir(root)));
}

test "Dependency strip: a test-bearing dependency is viewed and its shim rewritten" {
    root := bt_scratch("dep-view");
    defer delete_directory_full(root);
    dep := tprint("%1/dep", root);
    expect(build_seam_write(dep, "src/module.jai", "#load \"extra.jai\";\nmain_decl :: () -> s32 { return extra_decl(); }\n"));
    expect(build_seam_write(dep, "src/extra.jai", "extra_decl :: () -> s32 { return 2; }\n\ntest \"dep test\" {\n    assert(extra_decl() == 2);\n}\n"));
    expect(build_seam_write(root, "target/packages/depx.jai", dependency_shim_content("depx", tprint("%1/src/module.jai", dep))));

    expect(prepare_dependency_strip_views(root));

    // The shim now #loads the entry's strip view under the dependency
    // subtree; the entry view's in-package load rewrites to the child view;
    // the dependency's test block is stripped — no @test, no juice_test_N
    // (the dependency-tests-neither-discovered-nor-executed face).
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
    expect(ok3);
    expect(find_index_from_left(child_text, "// juice: test stripped") >= 0);
    expect(find_index_from_left(child_text, "@test") < 0);
}

test "Dependency strip: a hand-written shim is left to the compiler" {
    root := bt_scratch("dep-handwritten");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "target/packages/depx.jai", "// hand-written\nsome_decl :: 1;\n"));

    expect(prepare_dependency_strip_views(root));
    shim, ok := read_entire_file(tprint("%1/depx.jai", packages_dir(root)));
    expect(ok && shim == "// hand-written\nsome_decl :: 1;\n");
    expect(!file_exists(transpile_tree_dir(root)));
}

test "Dependency strip: a missing entry is skipped" {
    root := bt_scratch("dep-missing");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "target/packages/depx.jai", dependency_shim_content("depx", tprint("%1/no-such/src/module.jai", root))));

    expect(prepare_dependency_strip_views(root));
    shim, ok := read_entire_file(tprint("%1/depx.jai", packages_dir(root)));
    expect(ok && shim == dependency_shim_content("depx", tprint("%1/no-such/src/module.jai", root)));
    expect(!file_exists(transpile_tree_dir(root)));
}

// ===========================================================================
// b7: the entry selection front
// ===========================================================================

test "Build entry: a test-free closure compiles the original entry" {
    root := bt_scratch("entry-clean");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"helper.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/helper.jai", "helper :: () -> s32 { return 1; }\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    entry, ok := build_plan_entry(*prepared, plan, bt_pipeline(*prepared));
    expect(ok && entry == path_slashes(plan.target.source_path));
    // Zero transpile, zero cache: nothing under the transpile tree.
    expect(!file_exists(transpile_tree_dir(root)));
}

test "Build entry: a test-bearing closure views all-or-nothing with load rewrites" {
    root := bt_scratch("entry-view");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"math.jai\";\n\nmain :: () { print(\"hi\\n\"); }\n"));
    expect(build_seam_write(root, "src/math.jai", "add :: (a: s64, b: s64) -> s64 { return a + b; }\n\ntest \"addition\" {\n}\n"));
    expect(build_seam_write(root, "src/unloaded.jai", "test \"never viewed\" {\n}\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    entry, ok := build_plan_entry(*prepared, plan, bt_pipeline(*prepared));
    expect(ok && find_index_from_left(entry, "/target/transpile/") >= 0);

    // The entry view embeds the child view's path (the Merkle rewrite); the
    // child view's test block is stripped.
    entry_text, ok2 := read_entire_file(entry);
    expect(ok2);
    math_view, parsed := shim_load_target(entry_text);
    expect(parsed && find_index_from_left(math_view, "/target/transpile/") >= 0);
    math_text, ok3 := read_entire_file(math_view);
    expect(ok3 && find_index_from_left(math_text, "// juice: test stripped") >= 0);

    // Files outside the closure are never viewed: nothing landed at the
    // unloaded file's key.
    unloaded_source, ok4 := read_entire_file(tprint("%1/src/unloaded.jai", root));
    expect(ok4);
    unloaded_key := transpile_view_key("src/unloaded.jai", unloaded_source, .STRIP, Load_Target.[], VIEW_CONTRACT_VERSION);
    expect(!file_exists(transpile_view_path(transpile_tree_dir(root), unloaded_key, "src/unloaded.jai")));
}

test "Build entry: transpile diagnostics fail the entry selection" {
    root := bt_scratch("entry-diag");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "test \"top\" { }\n\nproc :: () {\n    test \"bad\" { }\n}\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    _, ok := build_plan_entry(*prepared, plan, bt_pipeline(*prepared));
    expect(!ok);
}

test "Build entry: the declared pipeline changes the view keys" {
    root := bt_scratch("entry-pipeline");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"math.jai\";\n\nmain :: () { print(\"hi\\n\"); }\n"));
    expect(build_seam_write(root, "src/math.jai", "add :: (a: s64, b: s64) -> s64 { return a + b; }\n\ntest \"addition\" {\n}\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    entry_default, ok := build_plan_entry(*prepared, plan, bt_pipeline(*prepared));
    expect(ok);

    // The explicit built-in declaration in the default order equals the
    // undeclared default (same pipeline description, same keys).
    prepared.discovery.root_package = .{name = "demo", version = "1", plugins = .[
        .{id = "load", version = "1.0.0"},
        .{id = "test-block", version = "1.0.0"},
    ]};
    entry_explicit, ok2 := build_plan_entry(*prepared, plan, bt_pipeline(*prepared));
    expect(ok2 && entry_explicit == entry_default);

    // The reversed declaration reaches the pipeline reversed: the views are
    // identical (the transforms are order-independent on these files) but
    // the pipeline description differs, so the keys differ.
    prepared.discovery.root_package = .{name = "demo", version = "1", plugins = .[
        .{id = "test-block", version = "1.0.0"},
        .{id = "load", version = "1.0.0"},
    ]};
    entry_reversed, ok3 := build_plan_entry(*prepared, plan, bt_pipeline(*prepared));
    expect(ok3 && entry_reversed != entry_default);
}

// ===========================================================================
// b7 + PRESTEP (ticket 057): the entry selection's substitution/drop
// consumption — the pre-step tables travel into build_plan_entry; a
// substituted entry compiles the replacement directly (no probe, no strip),
// a dropped entry fails.
// ===========================================================================

test "Build entry: a substituted entry compiles the replacement and skips the probe" {
    root := bt_scratch("entry-substitute");
    defer delete_directory_full(root);
    // The original entry carries a test block — a probe would view the whole
    // closure in STRIP; the replacement is the pre-step's compile-ready
    // source and must be used verbatim.
    expect(build_seam_write(root, "src/main.jai", "#load \"math.jai\";\n\nmain :: () { print(\"orig\\n\"); }\n\ntest \"orig\" {\n}\n"));
    expect(build_seam_write(root, "src/math.jai", "add :: (a: s64, b: s64) -> s64 { return a + b; }\n"));
    replacement := path_slashes(tprint("%1/target/mirror/src/main.jai", root));
    expect(build_seam_write(root, "target/mirror/src/main.jai", "main :: () { print(\"mirror\\n\"); }\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    pstage: Prestep_Stage;
    array_add(*pstage.substitutions, .{original = "src/main.jai", replacement = replacement});

    entry, ok := build_plan_entry(*prepared, plan, bt_pipeline(*prepared), *pstage);
    expect(ok && entry == replacement);
    // Zero probe, zero strip: nothing landed under the transpile tree.
    expect(!file_exists(transpile_tree_dir(root)));
}

test "Build entry: a dropped entry fails before any probe" {
    root := bt_scratch("entry-drop");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"math.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/math.jai", "add :: (a: s64, b: s64) -> s64 { return a + b; }\n\ntest \"dep\" {\n}\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    pstage: Prestep_Stage;
    array_add(*pstage.drops, "src/main.jai");

    entry, ok := build_plan_entry(*prepared, plan, bt_pipeline(*prepared), *pstage);
    expect(!ok && entry == "");
    expect(!file_exists(transpile_tree_dir(root)));
}

test "Build entry: a pre-step hit on another file leaves the entry untouched" {
    // The pre-step table covers the root package's files; only an entry hit
    // changes the build's compile input — other rows are ignored here (the
    // build compiles the entry's own closure).
    root := bt_scratch("entry-miss");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"math.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/math.jai", "add :: (a: s64, b: s64) -> s64 { return a + b; }\n\ntest \"dep\" {\n}\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    pstage: Prestep_Stage;
    array_add(*pstage.substitutions, .{original = "src/other.jai", replacement = "C:/mirror/other.jai"});
    array_add(*pstage.drops, "src/unused.jai");

    entry, ok := build_plan_entry(*prepared, plan, bt_pipeline(*prepared), *pstage);
    // The test-bearing closure was probed and viewed (the entry became its
    // strip view) — the unrelated rows changed nothing.
    expect(ok && find_index_from_left(entry, "/target/transpile/") >= 0);
}

test "Compile: a substituted entry reaches the compiler as the replacement path" {
    root := bt_scratch("entry-substitute-compile");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "main :: () {}\n"));
    replacement := path_slashes(tprint("%1/target/mirror/src/main.jai", root));
    expect(build_seam_write(root, "target/mirror/src/main.jai", "main :: () {}\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    pstage: Prestep_Stage;
    array_add(*pstage.substitutions, .{original = "src/main.jai", replacement = replacement});
    entry, ok := build_plan_entry(*prepared, plan, bt_pipeline(*prepared), *pstage);
    expect(ok && entry == replacement);

    // The compile metaprogram names the replacement, never the original
    // source: the compiler input is the pre-step's file.
    reset_compile_seam();
    test_spawn_artifact = plan.artifact_path;
    expect(compile_artifact_plan(root, plan, entry, test_spawn_build_compiler));
    expect(test_spawn_calls == 1);
    content, read_ok := read_entire_file(test_spawn_metaprogram_path);
    expect(read_ok);
    expect(find_index_from_left(content, tprint("add_build_file(\"%1\", workspace);", replacement)) >= 0);
    expect(find_index_from_left(content, tprint("add_build_file(\"%1\", workspace);", path_slashes(plan.target.source_path))) < 0);
}

// ===========================================================================
// The PRESTEP/TRANSPILE/COMPILE hook dispatch (the 004 decision 17
// representative subset extended by ticket 057's pre-step stage)
// ===========================================================================

test "Build dispatch: hooks fire in stage order and registration order" {
    root := bt_scratch("dispatch-order");
    defer delete_directory_full(root);
    prepared := bt_prepared(root);
    bt_reset();

    // Two registrations: registration order pins the before order across
    // registrations (forward, 021); the at hooks replace both built-in
    // implementations.
    table: [..] Hook_Registration;
    register_hooks(*table, .[
        bt_hook(.TRANSPILE, .before, bt_hook_t_before_a),
        bt_hook(.TRANSPILE, .at,     bt_hook_t_at_fill),
        bt_hook(.TRANSPILE, .after,  bt_hook_t_after_a),
        bt_hook(.COMPILE,  .before,  bt_hook_c_before_a),
        bt_hook(.COMPILE,  .at,      bt_hook_c_at_record),
        bt_hook(.COMPILE,  .after,   bt_hook_c_after_a),
    ]);
    register_hooks(*table, .[
        bt_hook(.TRANSPILE, .before, bt_hook_t_before_b),
        bt_hook(.COMPILE,  .before,  bt_hook_c_before_b),
    ]);

    expect(build_prepared_workspace(*prepared, table, test_artifact_is_running, test_artifact_handoff));
    expect(BT_TRACE.count == 8);
    expect(BT_TRACE[0] == "t-before-a" && BT_TRACE[1] == "t-before-b");
    expect(BT_TRACE[2] == "t-at" && BT_TRACE[3] == "t-after-a");
    expect(BT_TRACE[4] == "c-before-a" && BT_TRACE[5] == "c-before-b");
    expect(BT_TRACE[6] == "c-at" && BT_TRACE[7] == "c-after-a");
    // The hook-filled entries reached the compile stage through the stage
    // state channel.
    expect(BT_CAPTURED_ENTRIES.count == 1);
    expect(BT_CAPTURED_ENTRIES[0] == "hook-entry");
}

test "Build dispatch: with no at mount the built-in front runs between the hooks" {
    root := bt_scratch("dispatch-builtin");
    defer delete_directory_full(root);
    // A test-bearing closure: the built-in front's views are observable.
    expect(build_seam_write(root, "src/main.jai", "#load \"math.jai\";\n\nmain :: () { print(\"hi\\n\"); }\n"));
    expect(build_seam_write(root, "src/math.jai", "add :: (a: s64, b: s64) -> s64 { return a + b; }\n\ntest \"addition\" {\n}\n"));
    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    bt_reset();

    table := bt_table(.[
        bt_hook(.TRANSPILE, .before, bt_hook_t_before_a),
        bt_hook(.TRANSPILE, .after,  bt_hook_t_after_a),
        bt_hook(.COMPILE,  .at,      bt_hook_c_at_record),
    ]);

    expect(build_prepared_workspace(*prepared, table, test_artifact_is_running, test_artifact_handoff));
    expect(BT_TRACE.count == 3);
    expect(BT_TRACE[0] == "t-before-a" && BT_TRACE[1] == "t-after-a" && BT_TRACE[2] == "c-at");
    // The built-in front ran between the before and after hooks: the
    // closure was viewed and the COMPILE stage received the entry view.
    expect(BT_CAPTURED_ENTRIES.count == 1);
    expect(find_index_from_left(BT_CAPTURED_ENTRIES[0], "/target/transpile/") >= 0);
    expect(path_exists_as_regular_file(BT_CAPTURED_ENTRIES[0]));
}

test "Build dispatch: a mounted at hook replaces the built-in implementation" {
    root := bt_scratch("dispatch-at");
    defer delete_directory_full(root);
    prepared := bt_prepared(root);
    bt_reset();

    table := bt_table(.[
        bt_hook(.TRANSPILE, .at, bt_hook_t_at_fill),
        bt_hook(.COMPILE,  .at, bt_hook_c_at_record),
    ]);

    expect(build_prepared_workspace(*prepared, table, test_artifact_is_running, test_artifact_handoff));
    expect(BT_TRACE.count == 2);
    expect(BT_TRACE[0] == "t-at" && BT_TRACE[1] == "c-at");
    // The built-in front was skipped: no probe, no transpile tree.
    expect(!file_exists(transpile_tree_dir(root)));
    // The hook-owned entries reached the compile stage.
    expect(BT_CAPTURED_ENTRIES.count == 1);
    expect(BT_CAPTURED_ENTRIES[0] == "hook-entry");
}

test "Build dispatch: a before hook failure aborts before the built-in runs" {
    root := bt_scratch("dispatch-before-fail");
    defer delete_directory_full(root);
    prepared := bt_prepared(root);
    bt_reset();

    table := bt_table(.[
        bt_hook(.TRANSPILE, .before, bt_hook_t_before_a),
        bt_hook(.TRANSPILE, .before, bt_hook_fail),
        bt_hook(.COMPILE,  .at,      bt_hook_c_at_record),
    ]);

    expect(!build_prepared_workspace(*prepared, table, test_artifact_is_running, test_artifact_handoff));
    // Fail fast: the failing hook is the last to run — the built-in front
    // and every later hook (the COMPILE at included) never fire.
    expect(BT_TRACE.count == 2);
    expect(BT_TRACE[0] == "t-before-a" && BT_TRACE[1] == "fail");
    expect(!file_exists(transpile_tree_dir(root)));
}

test "Build dispatch: an ERROR diagnostic fails the stage, a WARNING passes" {
    root := bt_scratch("dispatch-diag");
    defer delete_directory_full(root);
    prepared := bt_prepared(root);
    bt_reset();

    table := bt_table(.[
        bt_hook(.TRANSPILE, .before, bt_hook_error),
        bt_hook(.TRANSPILE, .before, bt_hook_t_before_a),
    ]);
    expect(!build_prepared_workspace(*prepared, table, test_artifact_is_running, test_artifact_handoff));
    // The ERROR aborts the dispatch: the later before hook never fires.
    expect(BT_TRACE.count == 1 && BT_TRACE[0] == "error");

    bt_reset();
    table2 := bt_table(.[
        bt_hook(.TRANSPILE, .before, bt_hook_warning),
        bt_hook(.TRANSPILE, .at,     bt_hook_t_at_fill),
        bt_hook(.COMPILE,  .at,      bt_hook_c_at_record),
    ]);
    expect(build_prepared_workspace(*prepared, table2, test_artifact_is_running, test_artifact_handoff));
    expect(BT_TRACE.count == 3);
    expect(BT_TRACE[0] == "warning" && BT_TRACE[1] == "t-at" && BT_TRACE[2] == "c-at");
}

test "Build dispatch: an at hook failure aborts the build" {
    root := bt_scratch("dispatch-at-fail");
    defer delete_directory_full(root);
    prepared := bt_prepared(root);
    bt_reset();

    table := bt_table(.[
        bt_hook(.TRANSPILE, .at,    bt_hook_fail),
        bt_hook(.TRANSPILE, .after, bt_hook_t_after_a),
        bt_hook(.COMPILE,  .at,     bt_hook_c_at_record),
    ]);

    expect(!build_prepared_workspace(*prepared, table, test_artifact_is_running, test_artifact_handoff));
    // The at failure aborts before the after hook and every later stage.
    expect(BT_TRACE.count == 1 && BT_TRACE[0] == "fail");
}

test "Build dispatch: an after hook failure aborts the build" {
    root := bt_scratch("dispatch-after-fail");
    defer delete_directory_full(root);
    prepared := bt_prepared(root);
    bt_reset();

    table := bt_table(.[
        bt_hook(.TRANSPILE, .at,    bt_hook_t_at_fill),
        bt_hook(.TRANSPILE, .after, bt_hook_fail),
        bt_hook(.COMPILE,  .at,     bt_hook_c_at_record),
    ]);

    expect(!build_prepared_workspace(*prepared, table, test_artifact_is_running, test_artifact_handoff));
    expect(BT_TRACE.count == 2);
    expect(BT_TRACE[0] == "t-at" && BT_TRACE[1] == "fail");
    // The COMPILE stage never ran after the failure (no c-at entry).
}

test "Build dispatch: zero plans run no stage and fire no hook" {
    prepared: Juice.Prepared_Workspace;
    prepared.artifact_plans = Juice.Artifact_Plan.[];
    bt_reset();
    bt_prestep_reset();

    table := bt_table(.[
        bt_hook(.PRESTEP,  .before, bt_hook_p_before_fill),
        bt_hook(.PRESTEP,  .after,  bt_hook_p_after),
        bt_hook(.TRANSPILE, .before, bt_hook_t_before_a),
        bt_hook(.COMPILE,  .at,      bt_hook_c_at_record),
    ]);

    expect(build_prepared_workspace(*prepared, table, test_artifact_is_running, test_artifact_handoff));
    // The zero-plan short circuit precedes PRESTEP: the pre-step hooks never
    // fire (the same posture as every later stage).
    expect(BT_TRACE.count == 0);
}

test "Build dispatch: the host fills plugin_state slots null" {
    root := bt_scratch("dispatch-slots");
    defer delete_directory_full(root);
    prepared := bt_prepared(root);
    bt_reset();

    table := bt_table(.[
        bt_hook(.TRANSPILE, .before, bt_hook_state_probe),
        bt_hook(.TRANSPILE, .at,     bt_hook_t_at_fill),
        bt_hook(.COMPILE,  .at,      bt_hook_c_at_record),
    ]);

    expect(build_prepared_workspace(*prepared, table, test_artifact_is_running, test_artifact_handoff));
    // The host owns the slot storage and constructs it null (the 021 slot
    // protocol's construction-time null convention).
    expect(BT_TRACE.count == 3);
    expect(BT_TRACE[0] == "state-null");
    expect(BT_TRACE[1] == "t-at" && BT_TRACE[2] == "c-at");
}

test "Build dispatch: the pre-step tables travel into the entry selection" {
    // The fake pre-step plugin fills the substitution through the same hook
    // face; the built-in b7 front consumes it — the compile stage receives
    // the replacement path, with no closure probe and no strip view.
    root := bt_scratch("dispatch-prestep");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"math.jai\";\n\nmain :: () { print(\"orig\\n\"); }\n\ntest \"orig\" {\n}\n"));
    expect(build_seam_write(root, "src/math.jai", "add :: (a: s64, b: s64) -> s64 { return a + b; }\n"));
    replacement := path_slashes(tprint("%1/target/mirror/src/main.jai", root));
    expect(build_seam_write(root, "target/mirror/src/main.jai", "main :: () { print(\"mirror\\n\"); }\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    // The discovery snapshot's member packages start with the root (the
    // workspace convention); the pre-step stage's member_dirs carries the
    // rest.
    members: [..] Juice.Package;
    array_add(*members, .{name = "demo", dir = root});
    member_dir := path_slashes(tprint("%1/packages/member-a", root));
    array_add(*members, .{name = "member-a", dir = member_dir});
    prepared.discovery.member_packages = members;

    bt_reset();
    bt_prestep_reset();
    array_add(*BT_PRESTEP_SUBSTITUTIONS, .{original = "src/main.jai", replacement = replacement});
    reset_build_seam();

    table := bt_table(.[
        bt_hook(.PRESTEP, .before, bt_hook_p_before_fill),
        bt_hook(.PRESTEP, .after,  bt_hook_p_after),
        bt_hook(.COMPILE, .at,     bt_hook_c_at_record),
    ]);
    expect(build_prepared_workspace(*prepared, table, test_artifact_is_running, test_artifact_handoff));
    // PRESTEP (before -> after) fires between b4/LNK1104 and TRANSPILE; the
    // stage saw the root and member directories.
    expect(BT_TRACE.count == 3);
    expect(BT_TRACE[0] == "p-before" && BT_TRACE[1] == "p-after" && BT_TRACE[2] == "c-at");
    expect(BT_PRESTEP_ROOT == root);
    expect(BT_PRESTEP_MEMBERS.count == 1 && BT_PRESTEP_MEMBERS[0] == member_dir);
    // The substituted entry reached the compile stage directly; the probe
    // and the whole strip-view front were skipped.
    expect(BT_CAPTURED_ENTRIES.count == 1 && BT_CAPTURED_ENTRIES[0] == replacement);
    expect(!file_exists(transpile_tree_dir(root)));
}

test "Build dispatch: a dropped entry fails the build" {
    root := bt_scratch("dispatch-prestep-drop");
    defer delete_directory_full(root);
    prepared := bt_prepared(root);
    bt_reset();
    bt_prestep_reset();
    array_add(*BT_PRESTEP_DROPS, "src/main.jai");
    reset_build_seam();

    table := bt_table(.[
        bt_hook(.PRESTEP, .before, bt_hook_p_before_fill),
        bt_hook(.COMPILE, .at,     bt_hook_c_at_record),
    ]);
    expect(!build_prepared_workspace(*prepared, table, test_artifact_is_running, test_artifact_handoff));
    expect(BT_TRACE.count == 1 && BT_TRACE[0] == "p-before");
    expect(BT_CAPTURED_ENTRIES.count == 0);
}

test "Build dispatch: a conflicting pre-step row fails the build even on a true return" {
    // The stage-level conflict rule records an ERROR diagnostic; the
    // dispatch's ERROR check fails the build although the hook returned true.
    root := bt_scratch("dispatch-prestep-conflict");
    defer delete_directory_full(root);
    prepared := bt_prepared(root);
    bt_reset();
    reset_build_seam();

    table := bt_table(.[
        bt_hook(.PRESTEP, .before, bt_hook_p_conflict_returns_true),
        bt_hook(.TRANSPILE, .at,   bt_hook_t_at_fill),
        bt_hook(.COMPILE,  .at,    bt_hook_c_at_record),
    ]);
    expect(!build_prepared_workspace(*prepared, table, test_artifact_is_running, test_artifact_handoff));
    expect(BT_TRACE.count == 2);
    expect(BT_TRACE[0] == "p-conflict" && BT_TRACE[1] == "second-rejected");
    // The TRANSPILE and COMPILE stages never ran.
    expect(!file_exists(transpile_tree_dir(root)));
}

test "Build dispatch: a PRESTEP hook failure aborts before the transpile front" {
    root := bt_scratch("dispatch-prestep-fail");
    defer delete_directory_full(root);
    prepared := bt_prepared(root);
    bt_reset();
    reset_build_seam();

    table := bt_table(.[
        bt_hook(.PRESTEP, .before, bt_hook_p_fail),
        bt_hook(.TRANSPILE, .at,   bt_hook_t_at_fill),
        bt_hook(.COMPILE,  .at,    bt_hook_c_at_record),
    ]);
    expect(!build_prepared_workspace(*prepared, table, test_artifact_is_running, test_artifact_handoff));
    expect(BT_TRACE.count == 1 && BT_TRACE[0] == "p-fail");
    expect(!file_exists(transpile_tree_dir(root)));
}

// ===========================================================================
// b8: the Testing module view directory emission
// ===========================================================================

test "The metaprogram prepends the Testing module view directory" {
    options: Compiler_Metaprogram_Options;
    options.workspace_name    = "Juice Build";
    options.executable_name   = "app";
    options.output_path       = "X:/demo/target";
    options.intermediate_path = "X:/demo/target";
    options.import_dirs       = string.["X:/demo/modules"];
    options.build_file        = "X:/demo/src/main.jai";
    options.testing_view_dir  = "X:/demo/target/transpile/testing-module";
    generated := generate_compiler_metaprogram(options);
    // The view directory is prepended before the shared import directories
    // so `#import "Testing"` resolves to the test-free view instead of the
    // module source file.
    expect(find_index_from_left(generated, "    array_add(*import_paths, \"X:/demo/target/transpile/testing-module\");\n    array_add(*import_paths, \"X:/demo/modules\");") >= 0);
}

// ===========================================================================
// E2E: the real otter exe on the build-with-tests fixture
// ===========================================================================

test "E2E: build-with-tests strips test blocks and produces a runnable artifact" {
    fixture_root := path_slashes(tprint("%1/tests/data/build-with-tests", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, _ := run_otter_child_at(fixture_root, string.["build"]);
    expect(expect_exit("build-with-tests", result, 0, "build child"));
    expect(child_output_contains("build-with-tests", output, "[juice Build] Compiling Target 'build-with-tests' (src/main.jai) -> target/..."));
    expect(child_output_contains("build-with-tests", output, "[juice] Build completed successfully!"));

    // The artifact exists and behaves like the original program.
    artifact := target_artifact_path(package_target_dir(fixture_root), "build-with-tests");
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("build-with-tests artifact", run_result, 0, "build child"));
    expect(child_output_contains("build-with-tests artifact", run_output, "hello from build-with-tests: 2 + 3 = 5"));

    // Both closure files have strip views at their pure-contract paths: the
    // math view's test block is stripped (no @test), the main view's load
    // target rewrites to the math view.
    transpile_dir := transpile_tree_dir(fixture_root);
    math_source, ok := read_entire_file(tprint("%1/src/math.jai", fixture_root));
    expect(ok);
    math_key := transpile_view_key("src/math.jai", math_source, .STRIP, Load_Target.[], VIEW_CONTRACT_VERSION);
    math_view := transpile_view_path(transpile_dir, math_key, "src/math.jai");
    expect(path_exists_as_regular_file(math_view));
    math_text, ok2 := read_entire_file(math_view);
    expect(ok2);
    expect(find_index_from_left(math_text, "// juice: test stripped") >= 0);
    expect(find_index_from_left(math_text, "@test") < 0);

    main_source, ok3 := read_entire_file(tprint("%1/src/main.jai", fixture_root));
    expect(ok3);
    main_key := transpile_view_key("src/main.jai", main_source, .STRIP, Load_Target.[.{from = "src/math.jai", to = math_view}], VIEW_CONTRACT_VERSION);
    main_view := transpile_view_path(transpile_dir, main_key, "src/main.jai");
    expect(path_exists_as_regular_file(main_view));
    main_text, ok4 := read_entire_file(main_view);
    expect(ok4 && find_index_from_left(main_text, math_view) >= 0);
}
