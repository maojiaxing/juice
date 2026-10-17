// ===========================================================================
// Monorepo (workspace member) E2E tests.
//
// User revision (2026-10-14): the monorepo E2E tests live in this file, not
// inlined in the command files (build/clean/test.jai). Test discovery's
// full-package scan includes this file and runs it in the same test program
// as the src inline tests; the child scenario helpers (run_juice_child,
// run_juice_test, expect_exit, output_matches, child_output_contains,
// shim_content_for, make_test_link) live in tests/test_support.jai
// (program-level visible).
//
// The fixture family tests/data/workspace-* exists for these tests.
// ===========================================================================

#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import "Testing";

// ---------------------------------------------------------------------------
// Discovery validation matrix: one E2E per failure branch, asserting the
// concrete error message through the real juice.exe. A direct test is not
// feasible — the manifest evaluator's module directory derives from the
// running executable, which points at the jai compiler (not juice) inside
// the test program (the in-process direct test of the path gate lives in
// src/workspace.jai's "Workspace member path validity gate").
//
// Two defensive branches are outside the matrix: `Workspace member
// directory does not exist` (normalize_existing_path only normalizes
// lexically, it never verifies existence) and `escapes package root` (the
// path validity gate already rejects every reachable spelling: escape
// components, absolute paths and volume designators; junctions/symlinks are
// intercepted by the earlier safe-directory check).
// ---------------------------------------------------------------------------

test "E2E: discovery rejects an invalid root manifest" {
    result, output, _ := run_juice_child("workspace-bad-root-manifest", "build");
    expect(expect_exit("bad-root-manifest", result, 1, "build child"));
    expect(child_output_contains("bad-root-manifest", output, "[juice ERROR] Existing package.jai is invalid."));
}

test "E2E: discovery rejects a member path with escape components" {
    result, output, _ := run_juice_child("workspace-bad-escape", "build");
    expect(expect_exit("bad-escape", result, 1, "build child"));
    expect(child_output_contains("bad-escape", output, "[juice ERROR] Invalid workspace member path: ../outside"));
}

// Verified by measurement: a member directory that does not exist hits the
// not-a-safe-real-directory branch — normalize_existing_path never verifies
// existence, and the inspection finding !exists takes the same branch.
test "E2E: discovery rejects a member directory that does not exist" {
    result, output, _ := run_juice_child("workspace-bad-missing-dir", "build");
    expect(expect_exit("bad-missing-dir", result, 1, "build child"));
    expect(child_output_contains("bad-missing-dir", output, "[juice ERROR] Workspace member is not a safe real directory: ghost_member"));
}

test "E2E: discovery rejects a member without a manifest" {
    result, output, _ := run_juice_child("workspace-bad-no-manifest", "build");
    expect(expect_exit("bad-no-manifest", result, 1, "build child"));
    expect(child_output_contains("bad-no-manifest", output, "[juice ERROR] Workspace member lacks package.jai:"));
}

test "E2E: discovery rejects an invalid member manifest" {
    result, output, _ := run_juice_child("workspace-bad-invalid-manifest", "build");
    expect(expect_exit("bad-invalid-manifest", result, 1, "build child"));
    expect(child_output_contains("bad-invalid-manifest", output, "[juice ERROR] Workspace member manifest is invalid:"));
}

// "member_lib/." differs textually from "member_lib" but normalizes to the
// same directory (a measured spelling).
test "E2E: discovery rejects duplicate member paths" {
    result, output, _ := run_juice_child("workspace-bad-duplicate", "build");
    expect(expect_exit("bad-duplicate", result, 1, "build child"));
    expect(child_output_contains("bad-duplicate", output, "[juice ERROR] Duplicate workspace member path: member_lib/."));
}

// Edge case: the root lists "." as a member — normalization makes it equal
// to the root, which entered the member list first, hitting the duplicate
// branch (pins current behavior).
test "E2E: discovery rejects the root listed as its own member" {
    result, output, _ := run_juice_child("workspace-edge-self", "build");
    expect(expect_exit("edge-self", result, 1, "build child"));
    expect(child_output_contains("edge-self", output, "[juice ERROR] Duplicate workspace member path: ."));
}

// Edge case: a member's manifest declares members of its own — the current
// implementation only iterates the root's members list, nested declarations
// are silently ignored, and discovery and build succeed (pins current
// behavior, consistent with CONTEXT.md's "members are declared by the root
// package").
test "E2E: a member declaring its own members is ignored" {
    fixture_root := tprint("%1/tests/data/workspace-edge-nested", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));

    result, output, _ := run_juice_child("workspace-edge-nested", "build");
    expect(expect_exit("edge-nested", result, 0, "build child"));
    expect(child_output_contains("edge-nested", output, "Build completed successfully!"));
    expect(file_exists(tprint("%1/target/edge_nested.exe", fixture_root)));
}

// The junction case is manufactured at runtime: the workspace-ok shape is
// replicated in a target/ scratch dir with member_lib replaced by a junction
// pointing at the real directory -> hits the not-a-safe-real-directory
// branch. When make_test_link fails (the machine refuses mklink), the
// established SKIP convention applies.
test "E2E: discovery rejects a junctioned member directory" {
    scratch := tprint("%1/target/workspace-junction", juice_root());
    delete_directory_full(scratch);
    defer delete_directory_full(scratch);

    expect(make_directory_if_it_does_not_exist(tprint("%1/member_target/src", scratch), recursive = true));
    expect(write_entire_file(tprint("%1/member_target/package.jai", scratch),
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"member_lib\",\n    version = \"0.1.0\",\n    type    = .LIB,\n};\n"));
    expect(write_entire_file(tprint("%1/member_target/src/module.jai", scratch), "#import \"Basic\";\n"));
    expect(make_directory_if_it_does_not_exist(tprint("%1/src", scratch), recursive = true));
    expect(write_entire_file(tprint("%1/package.jai", scratch),
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"junction_root\",\n    version = \"0.1.0\",\n    type    = .BIN,\n    workspace = .{\n        members = string.[\"member_lib\"],\n    },\n};\n"));
    expect(write_entire_file(tprint("%1/src/main.jai", scratch), "#import \"Basic\";\n\nmain :: () {\n    print(\"fixture main\\n\");\n}\n"));

    if !make_test_link(tprint("%1/member_lib", scratch), tprint("%1/member_target", scratch), directory = true, junction = true) {
        print("[junction] SKIP: this machine refuses mklink; junction rejection not exercised\n");
        return;
    }

    result, output, _, _ := run_command(juice_exe(), "build", working_directory = scratch, capture_and_return_output = true);
    expect(expect_exit("junction", result, 1, "build child"));
    expect(child_output_contains("junction", output, "[juice ERROR] Workspace member is not a safe real directory:"));
}

// ---------------------------------------------------------------------------
// Monorepo build E2E: the root depends on a member -> linked, not fetched ->
// shims point at the import entries of the two layouts -> a real build -> the
// artifact calls both member functions. The member_lib closure contains test
// blocks (the entry itself + extra.jai) -> the dependency strip front views
// it and rewrites its shim; the root entry closure is test-free, no root
// views of its own.
// ---------------------------------------------------------------------------

test "E2E: monorepo build links members and builds the root" {
    fixture_root := tprint("%1/tests/data/workspace-ok", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));

    result, output, _ := run_juice_child("workspace-ok", "build");
    expect(expect_exit("monorepo-build", result, 0, "build child"));
    expect(child_output_contains("monorepo-build", output, "Compiling Target 'ws_root' (src/main.jai) -> target/..."));

    // Linked, not fetched: member_extra (test-free) keeps its shim pointing
    // at the import entry verbatim; member_lib's shim is rewritten by the
    // dependency strip front to the entry strip view.
    packages_dir := tprint("%1/target/packages", fixture_root);
    lib_content, lib_ok := shim_content_for(packages_dir, "member_lib");
    expect(lib_ok);
    expect(find_index_from_left(lib_content, "#load ") >= 0);
    expect(find_index_from_left(lib_content, "target/transpile/deps/member_lib/") >= 0);
    expect(find_index_from_left(lib_content, "module.jai\";") >= 0);
    extra_content, extra_ok := shim_content_for(packages_dir, "member_extra");
    expect(extra_ok);
    expect(find_index_from_left(extra_content, "#load ") >= 0 && find_index_from_left(extra_content, "member_extra/module.jai") >= 0);

    // Artifact run: both member functions are actually called (stripping
    // does not change the product's semantics).
    artifact := tprint("%1/target/ws_root.exe", fixture_root);
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("monorepo-artifact", run_result, 0, "build child"));
    expect(child_output_contains("monorepo-artifact", run_output, "ws_root: hello from member_lib | hello from member_extra"));

    // The dependency strip views land under
    // target/transpile/deps/member_lib/... with the test block stripped (the
    // pure-contract path is byte-reconstructible); the root entry closure is
    // test-free — the transpile tree exists but holds only the deps subtree.
    // rel is relative to the member package root (the src/ directory, where
    // the entry sits).
    extra_source, read_ok := read_entire_file(tprint("%1/member_lib/src/extra.jai", fixture_root));
    expect(read_ok);
    extra_key := transpile_view_key("extra.jai", extra_source, .STRIP, Load_Target.[], JUICE_VERSION);
    extra_view := tprint("%1/target/transpile/deps/member_lib/%2/extra.jai", fixture_root, extra_key);
    expect(path_exists_as_regular_file(extra_view));
    extra_view_text, view_ok := read_entire_file(extra_view);
    expect(view_ok && find_index_from_left(extra_view_text, "// juice: test stripped") >= 0);
}

// ---------------------------------------------------------------------------
// Monorepo clean E2E: target junk is manufactured at runtime (fixtures never
// commit target/), the root's and members' whole target directories are
// deleted, sources stay, and a member without target/ does not fail
// (delete_directory_full returns true for nonexistent paths, see
// src/dependency.jai).
// ---------------------------------------------------------------------------

test "E2E: clean removes root and member target directories" {
    fixture_root := tprint("%1/tests/data/workspace-ok", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));
    defer delete_directory_full(tprint("%1/member_lib/target", fixture_root));

    // Manufacture junk at runtime: one real target/ for the root and one for
    // member_lib; member_extra gets none.
    expect(make_directory_if_it_does_not_exist(tprint("%1/target", fixture_root), recursive = true));
    expect(write_entire_file(tprint("%1/target/junk.exe", fixture_root), "junk"));
    expect(make_directory_if_it_does_not_exist(tprint("%1/member_lib/target", fixture_root), recursive = true));
    expect(write_entire_file(tprint("%1/member_lib/target/junk.lib", fixture_root), "junk"));

    result, output, _ := run_juice_child("workspace-ok", "clean");
    expect(expect_exit("monorepo-clean", result, 0, "clean child"));
    expect(child_output_contains("monorepo-clean", output, "[juice Clean] Workspace cleaned."));

    // The whole directories are gone (junk included).
    expect(!file_exists(tprint("%1/target", fixture_root)));
    expect(!file_exists(tprint("%1/member_lib/target", fixture_root)));

    // Non-target content stays byte-identical (clean never overreaches).
    expect(file_exists(tprint("%1/package.jai", fixture_root)));
    expect(file_exists(tprint("%1/src/main.jai", fixture_root)));
    expect(file_exists(tprint("%1/member_lib/package.jai", fixture_root)));
    expect(file_exists(tprint("%1/member_lib/src/module.jai", fixture_root)));
    expect(file_exists(tprint("%1/member_extra/package.jai", fixture_root)));
    expect(file_exists(tprint("%1/member_extra/module.jai", fixture_root)));
}

// ---------------------------------------------------------------------------
// Monorepo test E2E: the root's test program #imports a lib member — the
// full chain: discovery -> dependency preparation (shims) -> view compile ->
// compile-time execution. The member's own tests (tests/ and src inline) do
// not run under the root (the member boundary reasserts itself); the src
// inline test blocks compile as STRIP views through the dependency strip
// front. This scenario exposed a defect where the test compile missed the
// target/packages import path (fixed).
// ---------------------------------------------------------------------------

test "E2E: monorepo root tests import a member library" {
    fixture_root := tprint("%1/tests/data/workspace-ok", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));
    defer delete_directory_full(tprint("%1/member_lib/target", fixture_root));

    result, output, _ := run_juice_test("workspace-ok");
    expect(expect_exit("monorepo-test", result, 0));
    expect(output_matches("monorepo-test", output, string.["[juice Test] Found 1 tests; compiling test program..."]));
    expect(output_matches("monorepo-test", output, string.["[test] root test imports the member\n1 passed, 0 failed\n"]));
    expect(output_matches("monorepo-test", output, string.["member test must not run in root", "member inline test", "member extra inline test"], want = false));
    // The dependency strip applies on the test path too: the member_lib
    // closure views land in the deps subtree.
    expect(path_exists_as_directory(tprint("%1/target/transpile/deps/member_lib", fixture_root)));
}

// A member with src inline test blocks discovers and runs all its tests
// normally when it is its own root (the entry inline block + the blocks in
// the entry closure's files + the standalone tests/ blocks, in scan order).
test "E2E: member with inline tests runs them as its own root" {
    fixture_root := tprint("%1/tests/data/workspace-ok", juice_root());
    defer delete_directory_full(tprint("%1/member_lib/target", fixture_root));

    result, output, _ := run_juice_test("workspace-ok/member_lib");
    expect(expect_exit("member-own", result, 0));
    expect(output_matches("member-own", output, string.["[juice Test] Found 3 tests; compiling test program..."]));
    expect(output_matches("member-own", output, string.[
        "[test] member extra inline test\n[test] member inline test\n[test] member test must not run in root\n3 passed, 0 failed\n"]));
}

// A LIB member (0 effective targets) running tests as its own root: Test
// still prepares dependencies via force_dependencies — the test program
// references another member (member_extra -> member_lib) through its shim;
// the old "0 plans means no shims" gate made that import resolution always
// fail.
test "E2E: lib member tests import a dependency without targets" {
    fixture_root := tprint("%1/tests/data/workspace-ok", juice_root());
    defer delete_directory_full(tprint("%1/member_extra/target", fixture_root));

    result, output, _ := run_juice_test("workspace-ok/member_extra");
    expect(expect_exit("lib-member-dep", result, 0));
    expect(output_matches("lib-member-dep", output, string.["[juice Test] Found 1 tests; compiling test program..."]));
    expect(output_matches("lib-member-dep", output, string.["[test] lib member test imports its dependency\n1 passed, 0 failed\n"]));
}
