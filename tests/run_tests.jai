#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// Run command tests (ticket 013, migrated to ticket 0093's contract): run is no
// longer a build prerequisite chain. It selects one package, selects one program
// inside it (explicit name > declared default_run > the only program), compiles
// only that program and passes the arguments after `--` to it verbatim.
//
// The unit cases drive the selection/launch seams; the E2E cases spawn the real
// executable on the run-* fixtures, where the second declared program does not
// compile — a run that compiled every program would fail loudly.
// ---------------------------------------------------------------------------

// A heap-backed plan list plus the package declaration the selection reads
// (default_run and the package name), shaped like the command's own
// Selected_Package.
run_selected_package :: (names: [] string, package_name: string, default_run: string, root_dir: string) -> Selected_Package {
    selected: Selected_Package;
    selected.package.name = copy_string(package_name);
    selected.package.default_run = copy_string(default_run);
    selected.package.dir = root_dir;
    selected.relative_path = ".";
    plans: [..] Artifact_Plan;
    for name: names {
        plan: Artifact_Plan;
        plan.target = .{name = copy_string(name)};
        plan.target_dir = tprint("%1/target", root_dir);
        plan.artifact_path = tprint("%1/target/%2.exe", root_dir, name);
        array_add(*plans, plan);
    }
    selected.plans = plans;
    return selected;
}

run_selection_explicit_name :: () {
    selected := run_selected_package(string.["alpha", "beta"], "demo", "", "root");

    plan, chosen := select_run_plan(selected, string.["beta"]);
    expect(chosen && plan.target.name == "beta");
    plan, chosen = select_run_plan(selected, string.["alpha"]);
    expect(chosen && plan.target.name == "alpha");

    // Spec section 2 rule 8: every name comparison key is ASCII case-insensitive
    // and keeps the declared spelling for reporting, so a different case names the
    // same program. (This case asserted the opposite until 0098 S18: it failed on
    // both trees because the selector already followed the uniform rule — the A14
    // row in docs/implementation/package-declaration-acceptance.md repeated the
    // stale claim.)
    plan_upper, upper_ok := select_run_plan(selected, string.["Alpha"]);
    expect(upper_ok && plan_upper.target.name == "alpha");
    _, missing_ok := select_run_plan(selected, string.["missing"]);
    expect(!missing_ok);
} @test

run_selection_default_run :: () {
    selected := run_selected_package(string.["one", "two"], "demo", "two", "root");
    plan, chosen := select_run_plan(selected, string.[]);
    expect(chosen && plan.target.name == "two");

    // An explicit name still wins over default_run.
    plan, chosen = select_run_plan(selected, string.["one"]);
    expect(chosen && plan.target.name == "one");

    // An invalid default_run never falls back to a program.
    selected.package.default_run = "does-not-exist";
    _, invalid_default_ok := select_run_plan(selected, string.[]);
    expect(!invalid_default_ok);
} @test

run_selection_cardinality :: () {
    // The only program needs no explicit choice.
    single := run_selected_package(string.["only"], "different-package-name", "", "root");
    plan, chosen := select_run_plan(single, string.[]);
    expect(chosen && plan.target.name == "only");

    // Two programs and no default_run: no guessing (no first-item and no
    // package-name fallback).
    multiple := run_selected_package(string.["alpha", "demo"], "demo", "", "root");
    _, multiple_ok := select_run_plan(multiple, string.[]);
    expect(!multiple_ok);

    zero := run_selected_package(string.[], "demo", "", "root");
    _, zero_ok := select_run_plan(zero, string.[]);
    expect(!zero_ok);
} @test

run_selection_separator_passthrough :: () {
    reset_run_seam();
    selected := run_selected_package(string.["good"], "demo", "", "root");
    plan, chosen := select_run_plan(selected, string.[]);
    expect(chosen);

    // Everything after `--` reaches the program unchanged, including tokens that
    // look like juice's own options.
    passed := string.["alpha", "--offline", "-p", "--", " spaced value "];
    expect(launch_selected_plan(plan, "root", passed, test_launch_artifact));
    expect(test_launch_count == 1);
    expect(test_launched_root == "root");
    expect(test_launched_arguments.count == passed.count);
    for argument, index: passed {
        expect(test_launched_arguments[index] == argument);
    }
} @test

run_selection_launch_failure :: () {
    reset_run_seam();
    test_launch_success = false;
    plan: Artifact_Plan;
    plan.target = .{name = "demo"};

    expect(!launch_selected_plan(plan, "root", string.[], test_launch_artifact));
    expect(test_launch_count == 1);
    test_launch_success = true;
} @test

run_selection_unsafe_artifact :: () {
    root := path_slashes(otter_root());
    plan: Artifact_Plan;
    plan.target = .{name = "app", main_file = "src/main.jai"};
    plan.target_dir = package_target_dir(root);
    plan.artifact_path = path_slashes(tprint("%1/../escape/app.exe", root));

    expect(!run_artifact_plan(plan, root, string.[]));
} @test

run_selection_missing_artifact :: () {
    root := path_slashes(otter_scratch("run-missing-artifact"));
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(root, recursive = true));

    plan: Artifact_Plan;
    plan.target = .{name = "app", main_file = "src/main.jai"};
    plan.target_dir = package_target_dir(root);
    plan.artifact_path = path_slashes(target_artifact_path(package_target_dir(root), "app"));

    expect(!run_artifact_plan(plan, root, string.[]));
} @test

// ---------------------------------------------------------------------------
// E2E child scenarios: the real executable on the run-* fixtures.
// ---------------------------------------------------------------------------

run_selection_only_selected_program_cli :: () {
    fixture_root := path_slashes(tprint("%1/tests/data/run-select", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, errors := run_otter_child_at(fixture_root, string.["run", "good"]);
    combined := tprint("%\n%", output, errors);
    expect(expect_exit("run-select", result, 0, "run child"));
    expect(output_matches("run-select", combined, string.[
        "[juice Build] Compiling Target 'good' (src/good.jai) -> target/...",
        "[juice Run] Launching",
        "GOOD RUN",
    ]));
    // The other declared program is never compiled: its source cannot parse, so
    // its absence from the output is proof, not an accident of ordering.
    expect(output_matches("run-select", combined, string.["broken.jai", "Compiling Target 'broken'"], want = false));
    expect(file_exists(target_artifact_path(package_target_dir(fixture_root), "good")));
    expect(!file_exists(target_artifact_path(package_target_dir(fixture_root), "broken")));
} @test

run_selection_separator_cli :: () {
    fixture_root := path_slashes(tprint("%1/tests/data/run-select", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, errors := run_otter_child_at(fixture_root, string.["run", "good", "--", "alpha", "--offline", "-p beta"]);
    combined := tprint("%\n%", output, errors);
    expect(expect_exit("run-separator", result, 0, "run child"));
    // Verbatim: juice's own option spellings are the program's arguments here.
    expect(output_matches("run-separator", combined, string.["ARG alpha", "ARG --offline", "ARG -p beta"]));
} @test

run_selection_ambiguous_cli :: () {
    fixture_root := path_slashes(tprint("%1/tests/data/run-select", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, errors := run_otter_child_at(fixture_root, string.["run"]);
    combined := tprint("%\n%", output, errors);
    expect(expect_exit("run-ambiguous", result, 1, "run child"));
    expect(output_matches("run-ambiguous", combined, string.["no default_run", "good", "broken"]));
    expect(output_matches("run-ambiguous", combined, string.["Compiling Target"], want = false));
} @test

run_selection_default_run_cli :: () {
    fixture_root := path_slashes(tprint("%1/tests/data/run-default", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, errors := run_otter_child_at(fixture_root, string.["run"]);
    combined := tprint("%\n%", output, errors);
    expect(expect_exit("run-default", result, 0, "run child"));
    expect(output_matches("run-default", combined, string.["TWO RUN", "Compiling Target 'two'"]));
    expect(output_matches("run-default", combined, string.["Compiling Target 'one'"], want = false));
} @test

run_selection_failure_exit_cli :: () {
    fixture_root := path_slashes(tprint("%1/tests/data/run-fail", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, errors := run_otter_child_at(fixture_root, string.["run"]);
    combined := tprint("%\n%", output, errors);
    expect(expect_exit("run fail", result, 1, "run child"));
    // The artifact's output passes through to the juice stdout.
    expect(output_matches("run fail", combined, string.["about to fail", "[juice ERROR] Command 'run' failed while executing 'run'."]));
} @test
