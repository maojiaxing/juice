// ---------------------------------------------------------------------------
// Strip front tests (created for the strip front; 2 blocks moved in from
// commands/build.jai; living in tests/ per the 2026-10-14 test organization
// rule).
//
// Key constraint (same as transpile_tests.jai): src/transpile_front.jai is
// build.jai's #load target — test blocks would be illegal inside a
// metaprogram compile-time text inclusion, so that file must stay test-free.
// The test blocks therefore cannot be inlined and live in tests/ (this
// file): referenced by no #load (outside the entry closure, outside the
// release product), collected into the test program by Test discovery's
// full-package scan. This file contains only test blocks; zero production
// code coupling.
//
// Shared declarations (juice_root, build_seam_write, fake_build_transpile
// and the other seam fakes and record globals) live in
// tests/test_support.jai, program-level shared in the test program.
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// The production transpile step (moved here from commands/build.jai)
// ---------------------------------------------------------------------------

// The real per-file step strips fixture test blocks and derives the
// content-addressed key from the pure function.
test "Real build transpile step strips fixture tests" {
    target: Load_Target;
    target.from = "src/math.jai";
    target.to = "C:/virtual/target/transpile/hash0001/src/math.jai";
    output := transpile_build_file(.{rel_path = "src/main.jai", abs_path = tprint("%1/tests/data/test-package/src/main.jai", juice_root())}, Load_Target.[target]);
    expect(output.diagnostics.count == 0);
    expect(find_index_from_left(output.view, "// juice: test stripped: test \"greeting\" {") >= 0);
    expect(find_index_from_left(output.view, "juice_test_") < 0);
    expect(find_index_from_left(output.view, "C:/virtual/target/transpile/hash0001/src/math.jai") >= 0);
    source, ok := read_entire_file(tprint("%1/tests/data/test-package/src/main.jai", juice_root()));
    expect(ok);
    expect(output.key == transpile_view_key("src/main.jai", source, .STRIP, Load_Target.[target], JUICE_VERSION));
}

// Only literal in-package #load targets are rewritten: non-literal and
// out-of-package statements stay verbatim.
test "Build strip keeps unrewritable loads verbatim" {
    root := tprint("%1/target/build-strip-verbatim", juice_root());
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

// ---------------------------------------------------------------------------
// PLAIN layout (the bootstrap strategy): <base>/<rel> always written
// ---------------------------------------------------------------------------

// The entry lands on disk like every other file (bootstrap switched to
// "generate + child process": the generated metaprogram compiles the entry
// view via add_build_file — the PLAIN layout no longer has an
// "entry into memory" branch, and diagnostics are exact file+line).
test "Strip front: PLAIN layout writes the entry view to disk" {
    root := tprint("%1/target/front-plain-entry", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"helper.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/helper.jai", "helper :: () -> s32 { return 1; }\n\ntest \"helper test\" {\n}\n"));

    reset_build_seam();
    closure, ok := probe_package_closure(root, "src/main.jai");
    expect(ok && closure_has_tests(closure) && closure.count == 2);

    state: Strip_View_State;
    state.closure = closure;
    state.transpile = fake_build_transpile;
    state.transpile_dir = tprint("%1/target/transpile/bootstrap", root);
    state.layout = .PLAIN;
    for _: closure {
        array_add(*state.states, 0);
        array_add(*state.view_paths, "");
    }
    entry_index, found := closure_index(*state, "src/main.jai");
    expect(found);
    entry_path, ok2 := view_of_file(*state, entry_index);
    expect(ok2 && entry_path == tprint("%1/target/transpile/bootstrap/src/main.jai", root));
    // Both the entry and the child views land on disk (dependency order:
    // helper before entry).
    expect(file_exists(entry_path));
    expect(file_exists(tprint("%1/target/transpile/bootstrap/src/helper.jai", root)));
}

// The PLAIN layout has no cache semantics: an existing view is rewritten
// every time (the opposite of CONTENT_ADDRESSED's skip-existing).
test "Strip front: PLAIN layout always rewrites existing views" {
    root := tprint("%1/target/front-plain-rewrite", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"helper.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/helper.jai", "helper :: () -> s32 { return 1; }\n\ntest \"helper test\" {\n}\n"));

    // Stale view placeholder: the PLAIN always-write semantics must rewrite
    // it (CONTENT_ADDRESSED would skip it).
    helper_view := tprint("%1/target/transpile/bootstrap/src/helper.jai", root);
    expect(build_seam_write(root, "target/transpile/bootstrap/src/helper.jai", "// stale\n"));

    reset_build_seam();
    closure, ok := probe_package_closure(root, "src/main.jai");
    expect(ok && closure.count == 2);

    state: Strip_View_State;
    state.closure = closure;
    state.transpile = fake_build_transpile;
    state.transpile_dir = tprint("%1/target/transpile/bootstrap", root);
    state.layout = .PLAIN;
    for _: closure {
        array_add(*state.states, 0);
        array_add(*state.view_paths, "");
    }
    entry_index, found := closure_index(*state, "src/main.jai");
    expect(found);
    _, ok2 := view_of_file(*state, entry_index);
    expect(ok2);
    helper_text, read_ok := read_entire_file(helper_view);
    expect(read_ok && helper_text == "// fake build view of src/helper.jai\n");
}

// ---------------------------------------------------------------------------
// Probing and the all-or-nothing decision
// ---------------------------------------------------------------------------

// The all-or-nothing decision: any file containing a test block views the
// whole closure; an all-test-free closure gets zero transpile.
test "Strip front: closure_has_tests detects any test block" {
    root := tprint("%1/target/front-has-tests", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/clean.jai", "x :: 1;\n"));
    expect(build_seam_write(root, "src/dirty.jai", "test \"t\" {\n}\n"));

    clean, ok1 := probe_package_closure(root, "src/clean.jai");
    expect(ok1 && !closure_has_tests(clean));
    dirty, ok2 := probe_package_closure(root, "src/dirty.jai");
    expect(ok2 && closure_has_tests(dirty));
}

// A missing entry file fails the probe (files empty, ok false) and the
// caller skips the build.
test "Strip front probe: a missing entry file fails the probe" {
    root := tprint("%1/target/front-probe-missing", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    closure, ok := probe_package_closure(root, "src/nope.jai");
    expect(!ok && closure.count == 0);
}

// ---------------------------------------------------------------------------
// The Testing module STRIP special case (consolidated here: bootstrap and
// the Build command share it)
// ---------------------------------------------------------------------------

// A test-free module: zero action (returns the "" sentinel, no view
// directory created).
test "Strip front: Testing module view disabled for a test-free module" {
    root := tprint("%1/target/front-testing-clean", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "mods/Testing.jai", "expect :: (cond: bool) {}\n"));

    dir := testing_module_strip_view_dir(root, tprint("%1/mods/Testing.jai", root));
    expect(dir == "");
    expect(!file_exists(tprint("%1/target/testing-module", root)));
}

// A module containing test blocks: the STRIP view is written to
// <root>/target/testing-module/Testing.jai (same path as the test command's
// compile view), and the return value is its directory.
test "Strip front: Testing module STRIP view writes to the package target" {
    root := tprint("%1/target/front-testing-view", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "mods/Testing.jai", "expect :: (cond: bool) {}\n\ntest \"self\" {\n    expect(true);\n}\n"));

    dir := testing_module_strip_view_dir(root, tprint("%1/mods/Testing.jai", root));
    expect(dir == tprint("%1/target/testing-module", root));
    view, ok := read_entire_file(tprint("%1/Testing.jai", dir));
    expect(ok);
    source, read_ok := read_entire_file(tprint("%1/mods/Testing.jai", root));
    expect(read_ok);
    expected := transpile_source(source, .{mode = .STRIP, path = "modules/Testing.jai"});
    expect(view == expected.view);
}
