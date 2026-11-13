#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// Run command tests (ticket 013): the target selection matrix (explicit
// exact match > single plan > package-name plan, spelling case-sensitive),
// the launch seam face of run_prepared_workspace, the run_artifact_plan
// failure gates (unsafe path / missing artifact — the real spawn is the E2E
// path), and the real-child E2E scenarios on the run-* fixtures. The run
// handler's workspace preparation is the build chain's own (011/008); the
// argument guard is locked by the CLI E2E suite.
// ---------------------------------------------------------------------------

// A heap-backed plan list (static literals would leave the slice pointing at
// the frame's stack — build_seam_prepared's discipline).
run_plans :: (names: [] string) -> [] Juice.Artifact_Plan {
    plans: [..] Juice.Artifact_Plan;
    for name: names {
        plan: Juice.Artifact_Plan;
        plan.target = .{name = copy_string(name)};
        plan.target_dir = "root/target";
        plan.artifact_path = tprint("root/target/%1.exe", name);
        array_add(*plans, plan);
    }
    return plans;
}

run_seam_prepared :: (plans: [] Juice.Artifact_Plan, package_name: string, root_dir: string) -> Juice.Prepared_Workspace {
    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = root_dir;
    prepared.discovery.root_package.name = package_name;
    prepared.artifact_plans = plans;
    return prepared;
}

test "Run launches the selected prepared artifact" {
    plans := run_plans(string.["alpha", "demo"]);
    prepared := run_seam_prepared(plans, "demo", "root");
    reset_run_seam();

    // No requested target with multiple plans: the package-name plan wins.
    expect(run_prepared_workspace(*prepared, "", test_launch_artifact));
    expect(test_launch_count == 1 && test_launched_plan.artifact_path == plans[1].artifact_path);
    expect(test_launched_root == "root" && test_launched_plan.target_dir == plans[1].target_dir);
    // An explicit target selects by exact name.
    expect(run_prepared_workspace(*prepared, "alpha", test_launch_artifact));
    expect(test_launch_count == 2 && test_launched_plan.artifact_path == plans[0].artifact_path);
}

test "Run defaults to the only target" {
    plans := run_plans(string.["only"]);
    prepared := run_seam_prepared(plans, "different-package-name", "root");
    reset_run_seam();

    expect(run_prepared_workspace(*prepared, "", test_launch_artifact));
    expect(test_launch_count == 1 && test_launched_plan.artifact_path == plans[0].artifact_path);
}

test "Invalid Run selection never launches" {
    plans := run_plans(string.["alpha", "beta"]);
    prepared := run_seam_prepared(plans, "demo", "root");
    reset_run_seam();

    // No package-name plan in a multi-plan package: no selection.
    expect(!run_prepared_workspace(*prepared, "", test_launch_artifact));
    // Unknown target: no selection.
    expect(!run_prepared_workspace(*prepared, "missing", test_launch_artifact));
    // Selection is spelling-exact: declaration uniqueness is
    // case-insensitive, the command-line spelling is not.
    expect(!run_prepared_workspace(*prepared, "Alpha", test_launch_artifact));
    // Zero plans: no selection.
    prepared.artifact_plans = Juice.Artifact_Plan.[];
    expect(!run_prepared_workspace(*prepared, "", test_launch_artifact));
    expect(test_launch_count == 0);
}

test "Run propagates launch failure" {
    plans := run_plans(string.["demo"]);
    prepared := run_seam_prepared(plans, "demo", "root");
    reset_run_seam();
    test_launch_success = false;

    expect(!run_prepared_workspace(*prepared, "", test_launch_artifact));
    expect(test_launch_count == 1);
}

test "Run refuses an unsafe artifact plan" {
    root := path_slashes(otter_root());
    plan: Juice.Artifact_Plan;
    plan.target = .{name = "app", main_file = "src/main.jai"};
    plan.target_dir = package_target_dir(root);
    plan.artifact_path = path_slashes(tprint("%1/../escape/app.exe", root));

    expect(!run_artifact_plan(plan, root));
}

test "Run reports a missing artifact" {
    root := path_slashes(otter_scratch("run-missing-artifact"));
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(root, recursive = true));

    plan: Juice.Artifact_Plan;
    plan.target = .{name = "app", main_file = "src/main.jai"};
    plan.target_dir = package_target_dir(root);
    plan.artifact_path = path_slashes(target_artifact_path(package_target_dir(root), "app"));

    expect(!run_artifact_plan(plan, root));
}

// ---------------------------------------------------------------------------
// E2E child scenarios: the real otter exe on the run-* fixtures —
// run's prerequisite build chain, the launch, and the exit-code passthrough.
// run_otter_child_at seeds the bootstrap modules so the exe's manifest
// evaluator children resolve the Juice module face.
// ---------------------------------------------------------------------------

test "E2E: run builds the fixture and launches the artifact" {
    fixture_root := path_slashes(tprint("%1/tests/data/run-fixture", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, _ := run_otter_child_at(fixture_root, string.["run"]);
    expect(expect_exit("run", result, 0, "run child"));
    // The prerequisite chain: run's dispatcher plan ran build first, which
    // compiled the target.
    expect(child_output_contains("run", output, "[juice Build] Compiling Target 'run-fixture' (src/main.jai) -> target/..."));
    expect(child_output_contains("run", output, "[juice] Build completed successfully!"));
    // The launch: run prints the launch line and the artifact's own output.
    expect(child_output_contains("run", output, "[juice Run] Launching"));
    expect(child_output_contains("run", output, "hello from run-fixture"));
}

test "E2E: run selects an explicit target by exact name" {
    fixture_root := path_slashes(tprint("%1/tests/data/run-fixture", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, _ := run_otter_child_at(fixture_root, string.["run", "run-fixture"]);
    expect(expect_exit("run explicit", result, 0, "run child"));
    expect(child_output_contains("run explicit", output, "[juice Run] Launching"));
    expect(child_output_contains("run explicit", output, "hello from run-fixture"));
}

test "E2E: run maps a failing artifact exit to command failure" {
    fixture_root := path_slashes(tprint("%1/tests/data/run-fail", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, _ := run_otter_child_at(fixture_root, string.["run"]);
    expect(expect_exit("run fail", result, 1, "run child"));
    // The artifact's output passes through to the juice stdout.
    expect(child_output_contains("run fail", output, "about to fail"));
    expect(child_output_contains("run fail", output, "[juice ERROR] Command 'run' failed while executing 'run'."));
}
