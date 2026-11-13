#import "Basic";
#import "Testing";

// (The JAI_COMPILER_VERSION pre-resolution anchor — the ticket 016
// deviation 2 deadlock guard — is retired by ticket 017: neither the
// test-block form nor a top-level constant could beat the driver's
// typecheck-ahead race as the suite grew, so the suite no longer references
// the #run constant in-process at all — version_tests' E2E child pins the
// baked value byte for byte.)

// ---------------------------------------------------------------------------
// Build command tests (ticket 011, updated by ticket 027): the b1-b8 chain's
// seam faces — the revalidation gate (b4), the orchestration (zero-plan
// no-op, the LNK1104 running-detection decision, the lifecycle hook
// dispatch), the built-in compile loop (b8: per-plan forwarding, fail-fast
// through the internal compile seam), the compile step's seams (b8: entry
// check, metaprogram generation, spawn, artifact check), the metaprogram
// generator's byte-locked executable shape, and the LNK1104 probe/handoff
// decision logic. The real-child E2E scenarios run the built otter exe on
// the build-* fixtures (old juice test_support run_juice_child semantics).
// b1 (argument guard) is locked by the CLI E2E suite; b2 is the workspace
// layer's own matrix (008). The transpile front (b5 dependency strip + b7
// entry selection) and the TRANSPILE/COMPILE hook dispatch matrix live in
// tests/build_transpile_tests.jai (ticket 027); b6 stays not-wired.
// ---------------------------------------------------------------------------

// The executable shape of the generated compile metaprogram, byte for byte
// (the old juice metaprogram_tests inline lock discipline): the aligned
// option lines, the import directory emission order, the message loop.
EXPECTED_METAPROGRAM :: "#import \"Basic\";\n#import \"Compiler\";\n\n#run {\n    set_build_options_dc(.{do_output = false});\n    workspace := compiler_create_workspace(\"Juice Build\");\n    if !workspace return;\n    options := get_build_options(workspace);\n    options.output_executable_name = \"app\";\n    options.output_path            = \"X:/demo/target\";\n    options.intermediate_path      = \"X:/demo/target\";\n    import_paths: [..] string;\n    array_add(*import_paths, .. options.import_path);\n    array_add(*import_paths, \"X:/demo/target/packages\");\n    array_add(*import_paths, \"X:/demo/modules\");\n    options.import_path = import_paths;\n    set_build_options(options, workspace);\n    compiler_begin_intercept(workspace);\n    add_build_file(\"X:/demo/src/main.jai\", workspace);\n    while true {\n        msg := compiler_wait_for_message();\n        if !msg continue;\n        if msg.workspace == workspace {\n            if msg.kind == {\n                case .ERROR;\n                case .COMPLETE;\n                    break;\n            }\n        }\n    }\n    compiler_end_intercept(workspace);\n}\n";

test "The generated metaprogram matches the byte-locked executable shape" {
    options: Compiler_Metaprogram_Options;
    options.workspace_name    = "Juice Build";
    options.executable_name   = "app";
    options.output_path       = "X:/demo/target";
    options.intermediate_path = "X:/demo/target";
    options.import_dirs       = string.["X:/demo/target/packages", "X:/demo/modules"];
    options.build_file        = "X:/demo/src/main.jai";
    expect(generate_compiler_metaprogram(options) == EXPECTED_METAPROGRAM);
}

test "The generated metaprogram slashes every quoted path" {
    options: Compiler_Metaprogram_Options;
    options.workspace_name    = "Juice Build";
    options.executable_name   = "app";
    options.output_path       = "X:\\demo\\target";
    options.intermediate_path = "X:\\demo\\target";
    options.import_dirs       = string.["X:\\demo\\target\\packages"];
    options.build_file        = "X:\\demo\\src\\main.jai";
    generated := generate_compiler_metaprogram(options);
    expect(find_index_from_left(generated, "\\") < 0);
    expect(find_index_from_left(generated, "\"X:/demo/target\"") >= 0);
    expect(find_index_from_left(generated, "\"X:/demo/src/main.jai\"") >= 0);
}

test "The generated executable metaprogram redirects the PDB when pdb_path is set" {
    options: Compiler_Metaprogram_Options;
    options.workspace_name    = "Juice Build";
    options.executable_name   = "app";
    options.output_path       = "X:/demo/target";
    options.intermediate_path = "X:/demo/target/build";
    options.pdb_path          = "X:\\demo\\target\\build\\app.pdb";
    options.import_dirs       = string.[];
    options.build_file        = "X:/demo/src/main.jai";
    generated := generate_compiler_metaprogram(options);
    #if OS == .WINDOWS {
        expect(find_index_from_left(generated, "    options.additional_linker_arguments = string.[\"/PDB:X:/demo/target/build/app.pdb\"];\n") >= 0);
    } else {
        expect(find_index_from_left(generated, "additional_linker_arguments") < 0);
    }
    // The no-output test shape never carries the linker redirect.
    options.no_output = true;
    generated = generate_compiler_metaprogram(options);
    expect(find_index_from_left(generated, "additional_linker_arguments") < 0);
}

// The no-output test shape (ticket 017, the 011 handover point): the
// output_type = .NO_OUTPUT line plus an unaligned intermediate_path line, no
// executable name/path lines — byte for byte the old juice test shape.
EXPECTED_METAPROGRAM_TEST_SHAPE :: "#import \"Basic\";\n#import \"Compiler\";\n\n#run {\n    set_build_options_dc(.{do_output = false});\n    workspace := compiler_create_workspace(\"Juice Test Program\");\n    if !workspace return;\n    options := get_build_options(workspace);\n    options.output_type = .NO_OUTPUT;\n    options.intermediate_path = \"X:/demo/target\";\n    import_paths: [..] string;\n    array_add(*import_paths, .. options.import_path);\n    array_add(*import_paths, \"X:/demo/modules\");\n    options.import_path = import_paths;\n    set_build_options(options, workspace);\n    compiler_begin_intercept(workspace);\n    add_build_file(\"X:/demo/src/main.jai\", workspace);\n    while true {\n        msg := compiler_wait_for_message();\n        if !msg continue;\n        if msg.workspace == workspace {\n            if msg.kind == {\n                case .ERROR;\n                case .COMPLETE;\n                    break;\n            }\n        }\n    }\n    compiler_end_intercept(workspace);\n}\n";

test "The generated metaprogram matches the byte-locked no-output test shape" {
    options: Compiler_Metaprogram_Options;
    options.workspace_name    = "Juice Test Program";
    options.no_output         = true;
    options.intermediate_path = "X:\\demo\\target";
    options.import_dirs       = string.["X:\\demo\\modules"];
    options.build_file        = "X:\\demo\\src\\main.jai";
    expect(generate_compiler_metaprogram(options) == EXPECTED_METAPROGRAM_TEST_SHAPE);
}

// ---------------------------------------------------------------------------
// b4: the whole-input revalidation gate.
// ---------------------------------------------------------------------------

test "Build revalidation: an unsafe package root blocks every compilation" {
    root := tprint("%1/missing-package-root", otter_root());
    plans := Juice.Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", otter_root())}, target_dir = package_target_dir(root), artifact_path = target_artifact_path(package_target_dir(root), "alpha")},
    ];
    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    reset_build_seam();
    expect(!build_prepared_workspace(*prepared, .[], test_artifact_is_running, test_artifact_handoff));
    expect(test_is_running_checked.count == 0);
    expect(test_handoff_calls == 0);
}

test "Build revalidation: an escaping artifact plan blocks compilation" {
    root := otter_root();
    plans := Juice.Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/../escape", root), artifact_path = tprint("%1/../escape/alpha.exe", root)},
    ];
    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    reset_build_seam();
    expect(!build_prepared_workspace(*prepared, .[], test_artifact_is_running, test_artifact_handoff));
    expect(test_is_running_checked.count == 0);
    expect(test_handoff_calls == 0);
}

test "Build revalidation: a missing target source blocks compilation" {
    root := otter_root();
    plans := Juice.Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/missing.jai", source_path = tprint("%1/src/missing.jai", root)}, target_dir = package_target_dir(root), artifact_path = target_artifact_path(package_target_dir(root), "alpha")},
    ];
    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    reset_build_seam();
    expect(!build_prepared_workspace(*prepared, .[], test_artifact_is_running, test_artifact_handoff));
    expect(test_is_running_checked.count == 0);
    expect(test_handoff_calls == 0);
}

// ---------------------------------------------------------------------------
// Orchestration: the seam faces of build_prepared_workspace.
// ---------------------------------------------------------------------------

test "Build without targets compiles nothing" {
    prepared: Juice.Prepared_Workspace;
    prepared.artifact_plans = Juice.Artifact_Plan.[];
    reset_build_seam();
    expect(build_prepared_workspace(*prepared, .[], test_artifact_is_running, test_artifact_handoff));
    expect(test_is_running_checked.count == 0);
    expect(test_handoff_calls == 0);
    expect(test_compile_at_calls == 0);
}

test "Build plugin preparation fails on invalid declarations before the zero-plan short circuit" {
    // Ticket 056: plugin preparation (declaration scan + resolver) runs
    // before the zero-plan early return, so a package with no targets still
    // fails loudly on a bad declaration — never silently builds nothing.
    reset_build_seam();

    // An unknown id (neither built-in nor workspace member) fails the
    // declaration-driven scan.
    unknown: Juice.Prepared_Workspace;
    unknown.discovery.root_dir = "C:/build-plugin-prep-unknown";
    unknown.discovery.has_package = true;
    unknown.discovery.root_package.name = "prep-root";
    unknown.discovery.root_package.plugins = Juice.Plugin_Declaration.[.{id = "mystery", version = "1"}];
    unknown.discovery.member_packages = Juice.Package.[.{name = "prep-root", dir = "C:/build-plugin-prep-unknown"}];
    unknown.artifact_plans = Juice.Artifact_Plan.[];
    expect(!build_prepared_workspace(*unknown, .[], test_artifact_is_running, test_artifact_handoff));
    expect(test_is_running_checked.count == 0);

    // A built-in declaration whose version differs from the plugin's own
    // version fails the resolver (the same check the test metaprogram runs
    // for member values).
    bad_version: Juice.Prepared_Workspace;
    bad_version.discovery.root_dir = "C:/build-plugin-prep-version";
    bad_version.discovery.has_package = true;
    bad_version.discovery.root_package.name = "prep-root";
    bad_version.discovery.root_package.plugins = Juice.Plugin_Declaration.[.{id = "load", version = "9.9.9"}];
    bad_version.discovery.member_packages = Juice.Package.[.{name = "prep-root", dir = "C:/build-plugin-prep-version"}];
    bad_version.artifact_plans = Juice.Artifact_Plan.[];
    expect(!build_prepared_workspace(*bad_version, .[], test_artifact_is_running, test_artifact_handoff));
    expect(test_is_running_checked.count == 0);
}

test "The built-in compile loop forwards each plan with its chosen entry" {
    root := otter_root();
    plans := Juice.Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = package_target_dir(root), artifact_path = target_artifact_path(package_target_dir(root), "alpha")},
        .{target = .{name = "beta",  main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = package_target_dir(root), artifact_path = target_artifact_path(package_target_dir(root), "beta")},
    ];
    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    cstage: Build_Compile_Stage;
    cstage.prepared = *prepared;
    entries: [..] string;
    array_add(*entries, "entry-alpha");
    array_add(*entries, "entry-beta");
    cstage.entries = entries;
    reset_build_seam();
    expect(build_compile_loop(*cstage, test_compile_artifact));
    expect(test_compile_count == 2);
    expect(test_compiled_driver_root == root);
    expect(test_compiled_entry == "entry-beta");
    expect(test_compiled_plan.target.name == "beta");
    expect(test_compiled_plan.artifact_path == path_slashes(target_artifact_path(package_target_dir(root), "beta")));
}

test "The built-in compile loop fails fast on a compile failure" {
    root := otter_root();
    plans := Juice.Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = package_target_dir(root), artifact_path = target_artifact_path(package_target_dir(root), "alpha")},
        .{target = .{name = "beta",  main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = package_target_dir(root), artifact_path = target_artifact_path(package_target_dir(root), "beta")},
    ];
    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    cstage: Build_Compile_Stage;
    cstage.prepared = *prepared;
    entries: [..] string;
    array_add(*entries, "entry-alpha");
    array_add(*entries, "entry-beta");
    cstage.entries = entries;
    reset_build_seam();
    test_compile_success = false;
    expect(!build_compile_loop(*cstage, test_compile_artifact));
    expect(test_compile_count == 1);
}

// ---------------------------------------------------------------------------
// LNK1104 face: the running-artifact decision logic (the production probe
// cannot be made to report "running" on demand — a real image lock needs a
// real running process, covered naturally by the stage 2 self-build — so
// the decision is driven through the recording seams).
// ---------------------------------------------------------------------------

test "Build hands a running artifact to the handoff before compiling" {
    root := otter_root();
    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    test_is_running_result = true;
    expect(build_prepared_workspace(*prepared, test_compile_at_table(), test_artifact_is_running, test_artifact_handoff));
    expect(test_handoff_calls == 1);
    expect(test_handoff_plan.artifact_path == path_slashes(plan.artifact_path));
    // The hand-off happens before any stage dispatch: the COMPILE at hook
    // never fires.
    expect(test_compile_at_calls == 0);
}

test "Build propagates a handoff failure" {
    root := otter_root();
    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    test_is_running_result = true;
    test_handoff_success = false;
    expect(!build_prepared_workspace(*prepared, test_compile_at_table(), test_artifact_is_running, test_artifact_handoff));
    expect(test_handoff_calls == 1);
    expect(test_compile_at_calls == 0);
}

test "Build compiles normally when no artifact is running" {
    root := otter_root();
    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    expect(build_prepared_workspace(*prepared, test_compile_at_table(), test_artifact_is_running, test_artifact_handoff));
    expect(test_handoff_calls == 0);
    expect(test_compile_at_calls == 1);
    expect(test_is_running_checked.count == 1);
    expect(test_is_running_checked[0] == path_slashes(plan.artifact_path));
    // The otter root's entry closure is test-free (src/module.jai's
    // self-tests are standard @test procedures, not test blocks), so the
    // built-in front compiles the original entry — no strip views.
    expect(test_compile_at_entries.count == 1);
    entry := test_compile_at_entries[0];
    expect(entry == path_slashes(tprint("%1/src/main.jai", root)));
}

test "A missing artifact is not running" {
    expect(!artifact_is_running(target_artifact_path(otter_target_dir(), "no-such-artifact")));
}

test "A present non-running artifact probes as not running" {
    root := otter_scratch("build-probe");
    delete_directory_full(root);
    defer delete_directory_full(root);
    make_directory_if_it_does_not_exist(root, recursive = true);
    probe_file := tprint("%1/demo.exe", root);
    expect(write_entire_file(probe_file, "not an image\n"));
    expect(!artifact_is_running(probe_file));
}

test "The handoff copy path stays inside the target directory" {
    root := otter_root();
    plan := build_seam_plan(root, "src/main.jai");
    expect(handoff_copy_path(plan) == path_slashes(target_artifact_path(package_target_dir(root), "app-build")));
}

test "A handoff copy failure reports and fails without spawning" {
    // The artifact to copy does not exist, so copy_file fails before any
    // spawn (the success path exits the process — the stage 2 self-build
    // covers it naturally).
    root := otter_scratch("build-handoff-fail");
    delete_directory_full(root);
    defer delete_directory_full(root);
    plan := build_seam_plan(root, "src/main.jai");
    expect(!running_artifact_handoff(plan));
}

// ---------------------------------------------------------------------------
// b8: compile_artifact_plan's seam faces (the real spawn is the E2E path;
// the fake spawn drives the metaprogram write, the failure branches and the
// artifact check deterministically).
// ---------------------------------------------------------------------------

test "Compile rejects a missing entry before spawning" {
    root := otter_scratch("build-compile-entry");
    delete_directory_full(root);
    defer delete_directory_full(root);
    plan := build_seam_plan(root, "src/missing.jai");
    reset_compile_seam();
    expect(!compile_artifact_plan(root, plan, path_slashes(plan.target.source_path), test_spawn_build_compiler));
    expect(test_spawn_calls == 0);
}

test "Compile writes the generated metaprogram, spawns jai and checks the artifact" {
    root := otter_scratch("build-compile-seam");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "main :: () {}\n"));
    plan := build_seam_plan(root, "src/main.jai");
    reset_compile_seam();
    test_spawn_artifact = plan.artifact_path;
    expect(compile_artifact_plan(root, plan, path_slashes(plan.target.source_path), test_spawn_build_compiler));
    expect(test_spawn_calls == 1);
    expect(test_spawn_metaprogram_path == path_slashes(target_session_driver_path(target_build_dir(package_target_dir(root)), tprint("build-app.jai"))));

    // The generated metaprogram lands on disk with the executable shape,
    // assembled from the plan's absolute paths, the shared import
    // directories and the Testing module view derivation (the same call the
    // production compile made — "" here, matching the absent module).
    content, ok := read_entire_file(test_spawn_metaprogram_path);
    expect(ok);
    expected := generate_compiler_metaprogram(.{
        workspace_name    = "Juice Build",
        executable_name   = "app",
        output_path       = package_target_dir(root),
        intermediate_path = target_build_dir(package_target_dir(root)),
        pdb_path          = tprint("%1/app.pdb", target_build_dir(package_target_dir(root))),
        import_dirs       = compiler_import_directories(packages_dir(root)),
        build_file        = path_slashes(plan.target.source_path),
        testing_view_dir  = juice_modules_dir(),
    });
    expect(content == expected);

    // The target directory was created before the spawn (the LNK1104 linker
    // face: jai's linker requires it).
    expect(path_exists_as_directory(package_target_dir(root)));
}

test "Compile reports a nonzero compiler exit" {
    root := otter_scratch("build-compile-fail");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "main :: () {}\n"));
    plan := build_seam_plan(root, "src/main.jai");
    reset_compile_seam();
    test_spawn_exit_code = 1;
    test_spawn_artifact = plan.artifact_path;
    expect(!compile_artifact_plan(root, plan, path_slashes(plan.target.source_path), test_spawn_build_compiler));
    expect(test_spawn_calls == 1);
}

test "Compile reports a missing artifact after a successful spawn" {
    root := otter_scratch("build-compile-no-artifact");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "main :: () {}\n"));
    plan := build_seam_plan(root, "src/main.jai");
    reset_compile_seam();
    expect(!compile_artifact_plan(root, plan, path_slashes(plan.target.source_path), test_spawn_build_compiler));
    expect(test_spawn_calls == 1);
}

// ---------------------------------------------------------------------------
// E2E child scenarios: the real otter exe on the build-* fixtures (the
// build-ok fixture's artifact run, the zero-plan short circuit, the failure
// path's exit code). run_otter_child_at seeds the bootstrap modules so the
// exe's manifest evaluator children resolve the Juice module face.
// ---------------------------------------------------------------------------

test "E2E: build-ok compiles the fixture and produces a runnable artifact" {
    fixture_root := path_slashes(tprint("%1/tests/data/build-ok", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, _ := run_otter_child_at(fixture_root, string.["build"]);
    expect(expect_exit("build-ok", result, 0, "build child"));
    expect(child_output_contains("build-ok", output, "[juice Build] Compiling Target 'build-ok' (src/main.jai) -> target/..."));
    expect(child_output_contains("build-ok", output, "[juice] Build completed successfully!"));

    artifact := target_artifact_path(package_target_dir(fixture_root), "build-ok");
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("build-ok artifact", run_result, 0, "build child"));
    expect(child_output_contains("build-ok artifact", run_output, "hello from build-ok"));
}

test "E2E: build-empty short-circuits on a zero plan" {
    fixture_root := path_slashes(tprint("%1/tests/data/build-empty", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, _ := run_otter_child_at(fixture_root, string.["build"]);
    expect(expect_exit("build-empty", result, 0, "build child"));
    expect(child_output_contains("build-empty", output, "[juice] No executable targets; nothing to build."));
    expect(child_output_contains("build-empty", output, "[juice] Build completed successfully!"));
    // The short circuit creates nothing under target/.
    expect(!file_exists(package_target_dir(fixture_root)));
}

test "E2E: a compile failure exits nonzero without an artifact" {
    fixture_root := path_slashes(tprint("%1/tests/data/build-bad", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, _ := run_otter_child_at(fixture_root, string.["build"]);
    expect(expect_exit("build-bad", result, 1, "build child"));
    expect(child_output_contains("build-bad", output, "[juice ERROR] Compilation failed for target 'build-bad'."));
    expect(!file_exists(target_artifact_path(package_target_dir(fixture_root), "build-bad")));
}
