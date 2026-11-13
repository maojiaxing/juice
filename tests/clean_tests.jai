#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// Clean command tests (ticket 012): the validate-all-then-delete
// orchestration over the recording fakes (old juice commands/clean.jai
// inline test semantics, migrated to the sibling test file — src modules
// stay test-free for the bootstrap #load discipline), the production
// validation gate (clean_path_is_safe) over a scratch tree, and E2E
// scenarios on the real otter exe (the clean-fixture workspace and scratch
// roots — old juice test_support run_juice_child semantics).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Orchestration over the recording validate/delete fakes: path collection
// (root target + every member target), validate-all-before-any-delete, and
// the delete loop that keeps going past a failure.
// ---------------------------------------------------------------------------

test "Clean validates workspace scope before deletion" {
    discovery: Juice.Workspace_Discovery;
    discovery.has_package = true;
    discovery.root_dir = "root";
    discovery.member_packages = Juice.Package.[.{name = "root", dir = "root"}, .{name = "member", dir = "root/member"}];
    reset_clean_test(2);
    expect(clean_discovered_workspace("", discovery, test_validate_clean_path, test_delete_clean_path));
    expect(!test_clean_deleted_too_early && test_clean_deleted.count == 2);
    expect(test_clean_deleted[0] == "root/target" && test_clean_deleted[1] == "root/member/target");
}

test "Clean without a manifest uses the current root" {
    discovery: Juice.Workspace_Discovery;
    reset_clean_test(1);
    expect(clean_discovered_workspace("root", discovery, test_validate_clean_path, test_delete_clean_path));
    expect(!test_clean_deleted_too_early && test_clean_deleted.count == 1);
    expect(test_clean_deleted[0] == "root/target");
}

test "Unsafe Clean path prevents every deletion" {
    discovery: Juice.Workspace_Discovery;
    discovery.has_package = true;
    discovery.root_dir = "root";
    discovery.member_packages = Juice.Package.[.{name = "root", dir = "root"}, .{name = "member", dir = "root/member"}];
    reset_clean_test(2);
    test_clean_invalid_path = "root/member/target";
    expect(!clean_discovered_workspace("", discovery, test_validate_clean_path, test_delete_clean_path));
    expect(test_clean_validated.count == 2 && test_clean_deleted.count == 0);
}

test "Clean continues after a deletion fails" {
    discovery: Juice.Workspace_Discovery;
    discovery.has_package = true;
    discovery.root_dir = "root";
    discovery.member_packages = Juice.Package.[.{name = "root", dir = "root"}, .{name = "member", dir = "root/member"}];
    reset_clean_test(2);
    test_clean_failed_delete = "root/target";
    expect(!clean_discovered_workspace("", discovery, test_validate_clean_path, test_delete_clean_path));
    expect(!test_clean_deleted_too_early && test_clean_deleted.count == 2);
    expect(test_clean_deleted[0] == "root/target" && test_clean_deleted[1] == "root/member/target");
}

// ---------------------------------------------------------------------------
// The production validation gate (clean_path_is_safe) over a scratch tree:
// pure path inspection, no subprocess. The junction case creates a real
// mklink junction (SKIP when the machine refuses link creation).
// ---------------------------------------------------------------------------

test "Clean path safety accepts a nonexistent path" {
    scratch := otter_scratch("clean-safety-missing");
    delete_directory_full(scratch);
    defer delete_directory_full(scratch);
    expect(make_directory_if_it_does_not_exist(scratch, recursive = true));
    expect(clean_path_is_safe(package_target_dir(scratch)));
}

test "Clean path safety accepts a real directory" {
    scratch := otter_scratch("clean-safety-directory");
    delete_directory_full(scratch);
    defer delete_directory_full(scratch);
    expect(make_directory_if_it_does_not_exist(package_target_dir(scratch), recursive = true));
    expect(clean_path_is_safe(package_target_dir(scratch)));
}

test "Clean path safety rejects a regular file" {
    scratch := otter_scratch("clean-safety-file");
    delete_directory_full(scratch);
    defer delete_directory_full(scratch);
    expect(make_directory_if_it_does_not_exist(scratch, recursive = true));
    path := package_target_dir(scratch);
    expect(write_entire_file(path, "not a directory"));
    expect(!clean_path_is_safe(path));
}

test "Clean path safety rejects a junction" {
    scratch := otter_scratch("clean-safety-junction");
    delete_directory_full(scratch);
    defer delete_directory_full(scratch);
    expect(make_directory_if_it_does_not_exist(scratch, recursive = true));
    real := tprint("%1/real", scratch);
    expect(make_directory_if_it_does_not_exist(real, recursive = true));
    junction := package_target_dir(scratch);
    if !make_test_link(junction, real, false, true) {
        print("SKIP: mklink unavailable (needs developer mode or elevation)\n");
        return;
    }
    expect(!clean_path_is_safe(junction));
}

// ---------------------------------------------------------------------------
// E2E child scenarios: the real otter exe over the clean-fixture workspace
// (and scratch roots). run_otter_child_at seeds the bootstrap modules so
// the exe's manifest evaluator children resolve the Juice module face. The
// fixture never commits target/; junk is manufactured at runtime and the
// defers clean it back up (fixture tree stays zero-pollution).
// ---------------------------------------------------------------------------

test "E2E: clean removes root and member target directories" {
    fixture_root := path_slashes(tprint("%1/tests/data/clean-fixture", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    defer delete_directory_full(package_target_dir(tprint("%1/member_lib", fixture_root)));

    // Manufacture junk at runtime: one real target/ for the root and one
    // for member_lib; member_extra gets none (its nonexistent target/
    // must not fail the clean — delete_directory_full returns true for
    // nonexistent paths).
    expect(make_directory_if_it_does_not_exist(package_target_dir(fixture_root), recursive = true));
    expect(write_entire_file(target_artifact_path(package_target_dir(fixture_root), "junk"), "junk"));
    expect(make_directory_if_it_does_not_exist(package_target_dir(tprint("%1/member_lib", fixture_root)), recursive = true));
    expect(write_entire_file(tprint("%1/junk.lib", package_target_dir(tprint("%1/member_lib", fixture_root))), "junk"));

    result, output, _ := run_otter_child_at(fixture_root, string.["clean"]);
    expect(expect_exit("clean-e2e", result, 0, "clean child"));
    expect(child_output_contains("clean-e2e", output, "[juice Clean] Workspace cleaned."));

    // The whole directories are gone (junk included).
    expect(!file_exists(package_target_dir(fixture_root)));
    expect(!file_exists(package_target_dir(tprint("%1/member_lib", fixture_root))));

    // Non-target content stays byte-identical (clean never overreaches).
    expect(file_exists(tprint("%1/package.jai", fixture_root)));
    expect(file_exists(tprint("%1/src/main.jai", fixture_root)));
    expect(file_exists(tprint("%1/member_lib/package.jai", fixture_root)));
    expect(file_exists(tprint("%1/member_lib/src/module.jai", fixture_root)));
    expect(file_exists(tprint("%1/member_extra/package.jai", fixture_root)));
    expect(file_exists(tprint("%1/member_extra/module.jai", fixture_root)));
}

test "E2E: clean refuses an unsafe target path and deletes nothing" {
    fixture_root := path_slashes(tprint("%1/tests/data/clean-fixture", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    defer delete_directory_full(package_target_dir(tprint("%1/member_lib", fixture_root)));
    defer file_delete(package_target_dir(tprint("%1/member_lib", fixture_root)));

    // Manufacture junk at runtime: a real root target/, and a regular file
    // squatting at member_lib/target. The production validation gate
    // rejects the squatting file (a deletion target must be a directory),
    // so the whole clean aborts before any deletion — the root junk must
    // survive even though its own path validated fine.
    expect(make_directory_if_it_does_not_exist(package_target_dir(fixture_root), recursive = true));
    expect(write_entire_file(target_artifact_path(package_target_dir(fixture_root), "junk"), "junk"));
    expect(write_entire_file(package_target_dir(tprint("%1/member_lib", fixture_root)), "not a directory"));

    result, output, _ := run_otter_child_at(fixture_root, string.["clean"]);
    expect(expect_exit("clean-unsafe", result, 1, "clean child"));
    expect(output_matches("clean-unsafe", output, string.[
        "[juice Clean] Cleaning output directories...",
        "[juice Clean] Workspace cleaned.",
    ], want = false));

    // Nothing was deleted: the root junk and the squatting file survive.
    expect(file_exists(target_artifact_path(package_target_dir(fixture_root), "junk")));
    expect(file_exists(package_target_dir(tprint("%1/member_lib", fixture_root))));
}

test "E2E: clean refuses a junction target path and deletes nothing" {
    fixture_root := path_slashes(tprint("%1/tests/data/clean-fixture", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    defer delete_directory_full(package_target_dir(tprint("%1/member_lib", fixture_root)));

    // Manufacture junk at runtime, then make member_lib/target a junction:
    // the validation gate refuses to delete through a junction and the
    // whole clean aborts, root junk included.
    expect(make_directory_if_it_does_not_exist(package_target_dir(fixture_root), recursive = true));
    expect(write_entire_file(target_artifact_path(package_target_dir(fixture_root), "junk"), "junk"));
    if !make_test_link(package_target_dir(tprint("%1/member_lib", fixture_root)), package_target_dir(fixture_root), false, true) {
        print("SKIP: mklink unavailable (needs developer mode or elevation)\n");
        return;
    }

    result, output, _ := run_otter_child_at(fixture_root, string.["clean"]);
    expect(expect_exit("clean-junction", result, 1, "clean child"));
    expect(child_output_contains("clean-junction", output, "[juice ERROR] Refusing to delete symlink/junction: "));

    // Nothing was deleted: the root junk survives.
    expect(file_exists(target_artifact_path(package_target_dir(fixture_root), "junk")));
}

test "E2E: clean without a manifest cleans the root target" {
    scratch := path_slashes(otter_scratch("clean-e2e-no-manifest"));
    delete_directory_full(scratch);
    defer delete_directory_full(scratch);
    expect(make_directory_if_it_does_not_exist(package_target_dir(scratch), recursive = true));
    expect(write_entire_file(tprint("%1/junk.bin", package_target_dir(scratch)), "junk"));

    result, output, _ := run_otter_child_at(scratch, string.["clean"]);
    expect(expect_exit("clean-no-manifest", result, 0, "clean child"));
    expect(child_output_contains("clean-no-manifest", output, "[juice Clean] Workspace cleaned."));
    expect(!file_exists(package_target_dir(scratch)));
}

test "E2E: clean discovery failure deletes nothing" {
    fixture_root := path_slashes(tprint("%1/tests/data/workspace-bad-root-manifest", otter_root()));

    result, output, _ := run_otter_child_at(fixture_root, string.["clean"]);
    expect(expect_exit("clean-discovery-failure", result, 1, "clean child"));
    expect(child_output_contains("clean-discovery-failure", output, "[juice ERROR] Existing package.jai is invalid."));
    expect(child_output_contains("clean-discovery-failure", output, "[juice ERROR] Clean discovery failed; no files were deleted."));
    expect(output_matches("clean-discovery-failure", output, string.["[juice Clean] Cleaning output directories..."], want = false));
    // Clean never creates anything on a failed discovery.
    expect(!file_exists(package_target_dir(fixture_root)));
}

test "E2E: clean rejects extra arguments" {
    scratch := path_slashes(otter_scratch("clean-e2e-args"));
    delete_directory_full(scratch);
    defer delete_directory_full(scratch);
    expect(make_directory_if_it_does_not_exist(scratch, recursive = true));

    result, output, _ := run_otter_child_at(scratch, string.["clean", "unexpected"]);
    expect(expect_exit("clean-args", result, 1, "clean child"));
    expect(output_matches("clean-args", output, string.["[juice ERROR] Usage: juice clean"]));
    // The guard rejects before discovery or deletion: nothing was created.
    expect(!file_exists(package_target_dir(scratch)));
}
