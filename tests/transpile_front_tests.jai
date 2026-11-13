// ---------------------------------------------------------------------------
// Strip front tests (ticket 026): the closure probe, the all-or-nothing
// viewing decision, the view computation state machine (both layouts — the
// PLAIN bootstrap strategy and the content-addressed runtime strategy with
// cache-hit-skip), the dependency subtree landing, the production transpile
// step and the Testing module STRIP special case (old juice
// tests/transpile_front_tests.jai semantics, rewritten not copied — the
// content-addressed and dependency landing blocks are this ticket's own
// surface). The probe matrix runs against the real default pipeline (the
// built-in #load edges + test-block anchors), so the viewing decisions pin
// the pipeline_has_anchors aggregation end to end.
//
// Key constraint (same as the other sibling test files): src modules are
// bootstrap #load targets / entry closure members — test blocks would be
// illegal inside them, so the modules stay test-free and their tests live
// here (tests/), per the test organization rule: referenced by no #load,
// collected into the test program by Test discovery's full-package scan.
// This file contains only test blocks and their helper declarations; zero
// production code coupling. Good-test standard: only external behavior is
// pinned (given package root / entry / pipeline -> view on disk / key /
// probe result), never the computation internals.
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";

// ===========================================================================
// Helpers
// ===========================================================================

// A deterministic fake key (path-safe: slashes become underscores) — the
// fake keys only circulate inside the seams, and the tests rebuild expected
// paths with the same function.
tfront_fake_key :: (rel: string) -> string {
    result := copy_string(rel);
    for i: 0..result.count-1 {
        if result[i] == #char "/" result[i] = #char "_";
    }
    return tprint("key-%1", result);
}

// The recording transpile seam: a fake view per file and the fake key. The
// signature matches Strip_View_State.transpile exactly.
tfront_fake_transpile :: (file: Build_Source_File, load_targets: [] Load_Target, pipeline: [] Transpile_Plugin) -> Build_File_Output {
    output: Build_File_Output;
    output.view = tprint("// fake view of %1\n", file.rel_path);
    output.key = tfront_fake_key(file.rel_path);
    return output;
}

// A fresh view-computation state over a closure (all files uncomputed),
// defaulting to the fake transpile seam.
tfront_state :: (closure: [] Build_Closure_File, transpile_dir: string, layout: Strip_View_Layout) -> Strip_View_State {
    state: Strip_View_State;
    state.closure = closure;
    state.transpile = tfront_fake_transpile;
    state.transpile_dir = transpile_dir;
    state.layout = layout;
    for _: closure {
        array_add(*state.states, 0);
        array_add(*state.view_paths, "");
    }
    return state;
}

// ===========================================================================
// The production transpile step
// ===========================================================================

// The real per-file step strips fixture test blocks and derives the
// content-addressed key from the pure function.
test "Real build transpile step strips fixture tests" {
    root := otter_scratch("front-transpile-step");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"math.jai\";\n\nmain :: () {}\n\ntest \"greeting\" {\n}\n"));

    target: Load_Target;
    target.from = "src/math.jai";
    target.to = "C:/virtual/target/transpile/hash0001/src/math.jai";
    output := transpile_build_file(.{rel_path = "src/main.jai", abs_path = tprint("%1/src/main.jai", root)}, Load_Target.[target]);
    expect(output.diagnostics.count == 0);
    expect(find_index_from_left(output.view, "// juice: test stripped: test \"greeting\" {") >= 0);
    expect(find_index_from_left(output.view, "juice_test_") < 0);
    expect(find_index_from_left(output.view, "C:/virtual/target/transpile/hash0001/src/math.jai") >= 0);
    source, ok := read_entire_file(tprint("%1/src/main.jai", root));
    expect(ok);
    expect(output.key == transpile_view_key("src/main.jai", source, .STRIP, Load_Target.[target], VIEW_CONTRACT_VERSION));
}

// Only literal in-package #load targets are rewritten: non-literal and
// out-of-package statements stay verbatim.
test "Build strip keeps unrewritable loads verbatim" {
    root := otter_scratch("front-keep-verbatim");
    delete_directory_full(root);
    defer delete_directory_full(root);
    source := "#load \"helper.jai\";\n#load CONST_NAME;\n#load \"../../outside.jai\";\n#load \"other\" + \".jai\";\n";
    expect(build_seam_write(root, "src/main.jai", source));
    target: Load_Target;
    target.from = "src/helper.jai";
    target.to = "X:/virtual/views/helper.jai";
    output := transpile_build_file(.{rel_path = "src/main.jai", abs_path = tprint("%1/src/main.jai", root)}, Load_Target.[target]);
    expect(output.diagnostics.count == 0);
    expect(find_index_from_left(output.view, "#load \"X:/virtual/views/helper.jai\";") >= 0);
    expect(find_index_from_left(output.view, "#load CONST_NAME;") >= 0);
    expect(find_index_from_left(output.view, "#load \"../../outside.jai\";") >= 0);
    expect(find_index_from_left(output.view, "#load \"other\" + \".jai\";") >= 0);
}

// ===========================================================================
// PLAIN layout (the bootstrap strategy): <base>/<rel> always written
// ===========================================================================

// The entry lands on disk like every other file (the bootstrap "generate +
// child process" strategy compiles the entry view via add_build_file).
test "Strip front: PLAIN layout writes the entry view to disk" {
    root := otter_scratch("front-plain-entry");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"helper.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/helper.jai", "helper :: () -> s32 { return 1; }\n\ntest \"helper test\" {\n}\n"));

    closure, ok := probe_package_closure(root, "src/main.jai");
    expect(ok && closure_has_tests(closure) && closure.count == 2);

    state := tfront_state(closure, tprint("%1/bootstrap", target_transpile_dir(root)), .PLAIN);
    entry_index, found := closure_index(*state, "src/main.jai");
    expect(found);
    entry_path, ok2 := view_of_file(*state, entry_index);
    expect(ok2 && entry_path == tprint("%1/bootstrap/src/main.jai", target_transpile_dir(root)));
    // Both the entry and the child views land on disk (dependency order:
    // helper before entry).
    expect(file_exists(entry_path));
    expect(file_exists(tprint("%1/bootstrap/src/helper.jai", target_transpile_dir(root))));
}

// The PLAIN layout has no cache semantics: an existing view is rewritten
// every time (the opposite of CONTENT_ADDRESSED's skip-existing).
test "Strip front: PLAIN layout always rewrites existing views" {
    root := otter_scratch("front-plain-rewrite");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"helper.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/helper.jai", "helper :: () -> s32 { return 1; }\n\ntest \"helper test\" {\n}\n"));

    // Stale view placeholder: the PLAIN always-write semantics must rewrite
    // it (CONTENT_ADDRESSED would skip it).
    helper_view := tprint("%1/bootstrap/src/helper.jai", target_transpile_dir(root));
    expect(build_seam_write(root, "target/transpile/bootstrap/src/helper.jai", "// stale\n"));

    closure, ok := probe_package_closure(root, "src/main.jai");
    expect(ok && closure.count == 2);

    state := tfront_state(closure, tprint("%1/bootstrap", target_transpile_dir(root)), .PLAIN);
    entry_index, found := closure_index(*state, "src/main.jai");
    expect(found);
    _, ok2 := view_of_file(*state, entry_index);
    expect(ok2);
    helper_text, read_ok := read_entire_file(helper_view);
    expect(read_ok && helper_text == "// fake view of src/helper.jai\n");
}

// ===========================================================================
// CONTENT_ADDRESSED layout (the runtime strategy): <hash>/<rel> + hit skip
// ===========================================================================

// Views land at the content-addressed paths derived from the per-file keys,
// in dependency order (children first); a second run over the same closure
// hits the cache and skips the write — the existing view bytes stay
// untouched.
test "Strip front: content-addressed views land under their hash dirs and hits skip the write" {
    root := otter_scratch("front-addressed-skip");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"helper.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/helper.jai", "helper :: () -> s32 { return 1; }\n\ntest \"helper test\" {\n}\n"));

    closure, ok := probe_package_closure(root, "src/main.jai");
    expect(ok && closure.count == 2);
    tree := transpile_tree_dir(root);

    state := tfront_state(closure, tree, .CONTENT_ADDRESSED);
    entry_index, found := closure_index(*state, "src/main.jai");
    expect(found);
    entry_path, ok2 := view_of_file(*state, entry_index);
    expect(ok2 && entry_path == transpile_view_path(tree, tfront_fake_key("src/main.jai"), "src/main.jai"));
    expect(file_exists(entry_path));
    // The child view landed at its own hash directory first (the fake key
    // names the hash).
    child_path := transpile_view_path(tree, tfront_fake_key("src/helper.jai"), "src/helper.jai");
    expect(file_exists(child_path));
    child_text, read_ok := read_entire_file(child_path);
    expect(read_ok && child_text == "// fake view of src/helper.jai\n");

    // Cache-hit skip: a fresh computation over the same closure finds the
    // existing views and skips the writes — a stale file stays byte for
    // byte.
    expect(write_entire_file(child_path, "// stale\n"));
    fresh := tfront_state(closure, tree, .CONTENT_ADDRESSED);
    fresh_index, found2 := closure_index(*fresh, "src/main.jai");
    expect(found2);
    _, ok3 := view_of_file(*fresh, fresh_index);
    expect(ok3);
    stale_text, stale_ok := read_entire_file(child_path);
    expect(stale_ok && stale_text == "// stale\n");
}

// The dependency closure landing: views go under deps/<name>/<hash>/<rel>,
// the entry's #load is rewritten to the child's view path (the Merkle
// chain), and the child's test block is stripped away — the dependency
// tests-neither-discovered-nor-executed face.
test "Strip front: dependency closures land under deps/<name> with stripped tests and rewritten loads" {
    root := otter_scratch("front-dependency");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"helper.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/helper.jai", "helper :: () -> s32 { return 1; }\n\ntest \"helper test\" {\n}\n"));

    closure, ok := probe_package_closure(root, "src/main.jai");
    expect(ok && closure_has_tests(closure) && closure.count == 2);
    tree := transpile_tree_dir(root);

    // The real production step over the dependency closure (dep_name set).
    state: Strip_View_State;
    state.closure = closure;
    state.transpile = transpile_build_file;
    state.transpile_dir = tree;
    state.dep_name = "shim-pkg";
    state.layout = .CONTENT_ADDRESSED;
    for _: closure {
        array_add(*state.states, 0);
        array_add(*state.view_paths, "");
    }
    entry_index, found := closure_index(*state, "src/main.jai");
    expect(found);
    entry_path, ok2 := view_of_file(*state, entry_index);
    expect(ok2);

    // The entry view path stays under the dependency subtree and mirrors the
    // package-relative structure.
    expect(starts_with(entry_path, tprint("%1/deps/shim-pkg/", tree)));
    expect(ends_with(entry_path, "/src/main.jai"));

    // The child view path is the entry's load rewrite target (the real
    // Merkle chain: the parent view embeds the child's key-addressed path).
    helper_source, read_ok := read_entire_file(tprint("%1/src/helper.jai", root));
    expect(read_ok);
    child_key := transpile_view_key("src/helper.jai", helper_source, .STRIP, Load_Target.[], VIEW_CONTRACT_VERSION);
    child_path := transpile_dependency_view_path(tree, child_key, "shim-pkg", "src/helper.jai");
    expect(file_exists(child_path));
    entry_view, entry_ok := read_entire_file(entry_path);
    expect(entry_ok);
    expect(find_index_from_left(entry_view, tprint("#load \"%1\";", child_path)) >= 0);

    // The dependency's test block is stripped from its view: no expanded
    // procedure, no @test note — only the placeholder comment remains.
    child_view, child_ok := read_entire_file(child_path);
    expect(child_ok);
    expect(find_index_from_left(child_view, "// juice: test stripped: test \"helper test\" {") >= 0);
    expect(find_index_from_left(child_view, "juice_test_") < 0);
    expect(find_index_from_left(child_view, "@test") < 0);
}

// ===========================================================================
// Probing and the all-or-nothing decision
// ===========================================================================

// The all-or-nothing decision: any file containing a test block views the
// whole closure; an all-test-free closure compiles its sources verbatim.
// The probe aggregates over the real default pipeline (built-in #load edges
// + test-block anchors), and an explicit pipeline parameter probes the same
// way.
test "Strip front: closure_has_tests detects any test block" {
    root := otter_scratch("front-has-tests");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/clean.jai", "x :: 1;\n"));
    expect(build_seam_write(root, "src/dirty.jai", "test \"t\" {\n}\n"));

    clean, ok1 := probe_package_closure(root, "src/clean.jai");
    expect(ok1 && !closure_has_tests(clean));
    dirty, ok2 := probe_package_closure(root, "src/dirty.jai");
    expect(ok2 && closure_has_tests(dirty));
    // The explicit default pipeline probes the same decisions.
    clean_explicit, ok3 := probe_package_closure(root, "src/clean.jai", "[juice ERROR] ", default_transpile_pipeline());
    expect(ok3 && !closure_has_tests(clean_explicit));
}

// The closure DFS lists files in preorder: the entry first, then each load
// target's subtree in statement order.
test "Strip front: the probe lists the closure in DFS preorder" {
    root := otter_scratch("front-probe-order");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"a.jai\";\n#load \"b.jai\";\n"));
    expect(build_seam_write(root, "src/a.jai", "a :: 1;\n"));
    expect(build_seam_write(root, "src/b.jai", "b :: 1;\n"));

    closure, ok := probe_package_closure(root, "src/main.jai");
    expect(ok && closure.count == 3);
    expect(closure[0].file.rel_path == "src/main.jai");
    expect(closure[1].file.rel_path == "src/a.jai");
    expect(closure[2].file.rel_path == "src/b.jai");
}

// A missing entry file fails the probe (files empty, ok false) and the
// caller skips the build.
test "Strip front probe: a missing entry file fails the probe" {
    root := otter_scratch("front-probe-missing");
    delete_directory_full(root);
    defer delete_directory_full(root);
    closure, ok := probe_package_closure(root, "src/nope.jai");
    expect(!ok && closure.count == 0);
}

// ===========================================================================
// View computation failure paths
// ===========================================================================

// A hand-built closure whose literal #load graph has a cycle fails the view
// computation instead of recursing forever.
test "Strip front: view_of_file rejects a load cycle" {
    a: Build_Closure_File;
    a.file = .{rel_path = "src/a.jai", abs_path = "X:/pkg/src/a.jai"};
    array_add(*a.loads, "src/b.jai");
    b: Build_Closure_File;
    b.file = .{rel_path = "src/b.jai", abs_path = "X:/pkg/src/b.jai"};
    array_add(*b.loads, "src/a.jai");
    closure: [..] Build_Closure_File;
    array_add(*closure, a);
    array_add(*closure, b);

    state := tfront_state(closure, "X:/pkg/target/transpile", .PLAIN);
    entry_index, found := closure_index(*state, "src/a.jai");
    expect(found);
    _, ok := view_of_file(*state, entry_index);
    expect(!ok);
}

// A closure referencing an in-package #load target outside the closure
// fails the view computation (the path rewrite cannot be resolved).
test "Strip front: view_of_file rejects a missing in-package view target" {
    a: Build_Closure_File;
    a.file = .{rel_path = "src/a.jai", abs_path = "X:/pkg/src/a.jai"};
    array_add(*a.loads, "src/b.jai");
    closure: [..] Build_Closure_File;
    array_add(*closure, a);

    state := tfront_state(closure, "X:/pkg/target/transpile", .PLAIN);
    entry_index, found := closure_index(*state, "src/a.jai");
    expect(found);
    _, ok := view_of_file(*state, entry_index);
    expect(!ok);
}

// ===========================================================================
// The Testing module STRIP special case
// ===========================================================================

// A test-free module: zero action (returns the "" sentinel, no view
// directory created).
test "Strip front: Testing module view disabled for a test-free module" {
    root := otter_scratch("front-testing-clean");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "mods/Testing.jai", "expect :: (cond: bool) {}\n"));

    dir := testing_module_strip_view_dir(root, tprint("%1/mods/Testing.jai", root));
    expect(dir == "");
    expect(!file_exists(target_testing_module_dir(package_target_dir(root))));
}

// A module containing test blocks: the STRIP view is written to
// <root>/target/transpile/testing-module/Testing.jai (same path as the test command's
// compile view), and the return value is its directory.
test "Strip front: Testing module STRIP view writes to the package target" {
    root := otter_scratch("front-testing-view");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "mods/Testing.jai", "expect :: (cond: bool) {}\n\ntest \"self\" {\n    expect(true);\n}\n"));

    dir := testing_module_strip_view_dir(root, tprint("%1/mods/Testing.jai", root));
    expect(dir == target_testing_module_dir(package_target_dir(root)));
    view, ok := read_entire_file(tprint("%1/Testing.jai", dir));
    expect(ok);
    source, read_ok := read_entire_file(tprint("%1/mods/Testing.jai", root));
    expect(read_ok);
    expected := transpile_source(source, .{mode = .STRIP, path = "modules/Testing.jai"});
    expect(view == expected.view);
}
