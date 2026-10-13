#import "Basic";
#import "File";
#import "Process";
#import "String";
#import "Juice";
#import "Testing";

// 共享声明（juice_root 等 helper、recording fake 与记录全局）位于
// src/test_support.jai（组织决议 0027），测试程序程序级共享。

test "Command-owned declarations in production registry" {
    expect(validate_registry(COMMAND_REGISTRY).success && COMMAND_REGISTRY.count == 6);
    expected := Command.[DISCOVER_WORKSPACE_COMMAND, PREPARE_WORKSPACE_COMMAND, BUILD_COMMAND, RUN_COMMAND, CLEAN_COMMAND, TEST_COMMAND];
    for declaration, i: expected {
        registered := COMMAND_REGISTRY[i];
        expect(registered.name == declaration.name && registered.description == declaration.description);
        expect(registered.usage == declaration.usage && registered.visible == declaration.visible);
        expect(registered.handler == declaration.handler);
        expect(registered.validate_arguments == declaration.validate_arguments);
        expect(registered.prerequisites.count == declaration.prerequisites.count);
        for prerequisite, j: declaration.prerequisites {
            expect(registered.prerequisites[j] == prerequisite);
        }
    }
    expect(!DISCOVER_WORKSPACE_COMMAND.visible && !PREPARE_WORKSPACE_COMMAND.visible);
    expect(BUILD_COMMAND.visible && RUN_COMMAND.visible && CLEAN_COMMAND.visible && TEST_COMMAND.visible);
    expect(RUN_COMMAND.prerequisites.count == 1 && RUN_COMMAND.prerequisites[0] == "build");
    expect(BUILD_COMMAND.prerequisites.count == 1 && BUILD_COMMAND.prerequisites[0] == "prepare-workspace");
    expect(PREPARE_WORKSPACE_COMMAND.prerequisites.count == 1 && PREPARE_WORKSPACE_COMMAND.prerequisites[0] == "discover-workspace");
    expect(DISCOVER_WORKSPACE_COMMAND.prerequisites.count == 0 && CLEAN_COMMAND.prerequisites.count == 0);
}

test "Command argument and preparation guards" {
    // Null driver makes an accidental operation after argument rejection visible.
    ctx: Command_Context;
    expect(!BUILD_COMMAND.handler(*ctx, string.["unexpected"]));
    expect(!RUN_COMMAND.handler(*ctx, string.["one", "two"]));
    expect(!CLEAN_COMMAND.handler(*ctx, string.["unexpected"]));
    expect(!DISCOVER_WORKSPACE_COMMAND.handler(*ctx, string.["unexpected"]));
    expect(!PREPARE_WORKSPACE_COMMAND.handler(*ctx, string.["unexpected"]));
    expect(!BUILD_COMMAND.handler(*ctx, string.[]));
    expect(!RUN_COMMAND.handler(*ctx, string.[]));
}

// test_launch_artifact 与记录全局见 src/test_support.jai。

test "Run launches the selected prepared artifact" {
    plans := Artifact_Plan.[
        .{target = .{name = "alpha"}, target_dir = "root/target", artifact_path = "root/target/alpha.exe"},
        .{target = .{name = "demo"}, target_dir = "root/target", artifact_path = "root/target/demo.exe"},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = "root";
    prepared.discovery.root_package.name = "demo";
    prepared.artifact_plans = plans;
    test_launch_count = 0;
    test_launch_success = true;

    expect(run_prepared_workspace(*prepared, "", test_launch_artifact));
    expect(test_launch_count == 1 && test_launched_plan.artifact_path == plans[1].artifact_path);
    expect(test_launched_root == "root" && test_launched_plan.target_dir == plans[1].target_dir);
    expect(run_prepared_workspace(*prepared, "alpha", test_launch_artifact));
    expect(test_launch_count == 2 && test_launched_plan.artifact_path == plans[0].artifact_path);
}

test "Run defaults to the only target" {
    plans := Artifact_Plan.[.{target = .{name = "only"}, artifact_path = "root/target/only.exe"}];
    prepared: Prepared_Workspace;
    prepared.discovery.root_package.name = "different-package-name";
    prepared.artifact_plans = plans;
    test_launch_count = 0;
    test_launch_success = true;
    expect(run_prepared_workspace(*prepared, "", test_launch_artifact));
    expect(test_launch_count == 1 && test_launched_plan.artifact_path == plans[0].artifact_path);
}

test "Invalid Run selection never launches" {
    plans := Artifact_Plan.[.{target = .{name = "alpha"}}, .{target = .{name = "beta"}}];
    prepared: Prepared_Workspace;
    prepared.discovery.root_package.name = "demo";
    prepared.artifact_plans = plans;
    test_launch_count = 0;
    test_launch_success = true;
    expect(!run_prepared_workspace(*prepared, "", test_launch_artifact));
    expect(!run_prepared_workspace(*prepared, "missing", test_launch_artifact));
    expect(!run_prepared_workspace(*prepared, "Alpha", test_launch_artifact));
    prepared.artifact_plans = Artifact_Plan.[];
    expect(!run_prepared_workspace(*prepared, "", test_launch_artifact));
    expect(test_launch_count == 0);
}

test "Run propagates launch failure" {
    plans := Artifact_Plan.[.{target = .{name = "demo"}}];
    prepared: Prepared_Workspace;
    prepared.artifact_plans = plans;
    test_launch_count = 0;
    test_launch_success = false;
    expect(!run_prepared_workspace(*prepared, "", test_launch_artifact));
    expect(test_launch_count == 1);
}

// test_clean_* 记录全局与 reset_clean_test 等 helper 见 src/test_support.jai。

test "Clean validates workspace scope before deletion" {
    driver: Build_Driver;
    driver.root_dir = "unused-driver-root";
    discovery: Workspace_Discovery;
    discovery.has_package = true;
    discovery.root_dir = "root";
    discovery.member_packages = Package.[.{name = "root", dir = "root"}, .{name = "member", dir = "root/member"}];
    reset_clean_test(2);
    expect(clean_discovered_workspace(*driver, discovery, test_validate_clean_path, test_delete_clean_path));
    expect(!test_clean_deleted_too_early && test_clean_deleted.count == 2);
    expect(test_clean_deleted[0] == "root/target" && test_clean_deleted[1] == "root/member/target");
}

test "Clean without a manifest uses the current root" {
    driver: Build_Driver;
    driver.root_dir = "root";
    discovery: Workspace_Discovery;
    reset_clean_test(1);
    expect(clean_discovered_workspace(*driver, discovery, test_validate_clean_path, test_delete_clean_path));
    expect(!test_clean_deleted_too_early && test_clean_deleted.count == 1);
    expect(test_clean_deleted[0] == "root/target");
}

test "Unsafe Clean path prevents every deletion" {
    driver: Build_Driver;
    discovery: Workspace_Discovery;
    discovery.has_package = true;
    discovery.root_dir = "root";
    discovery.member_packages = Package.[.{name = "root", dir = "root"}, .{name = "member", dir = "root/member"}];
    reset_clean_test(2);
    test_clean_invalid_path = "root/member/target";
    expect(!clean_discovered_workspace(*driver, discovery, test_validate_clean_path, test_delete_clean_path));
    expect(test_clean_validated.count == 2 && test_clean_deleted.count == 0);
}

test "Clean continues after a deletion fails" {
    driver: Build_Driver;
    discovery: Workspace_Discovery;
    discovery.has_package = true;
    discovery.root_dir = "root";
    discovery.member_packages = Package.[.{name = "root", dir = "root"}, .{name = "member", dir = "root/member"}];
    reset_clean_test(2);
    test_clean_failed_delete = "root/target";
    expect(!clean_discovered_workspace(*driver, discovery, test_validate_clean_path, test_delete_clean_path));
    expect(!test_clean_deleted_too_early && test_clean_deleted.count == 2);
    expect(test_clean_deleted[0] == "root/target" && test_clean_deleted[1] == "root/member/target");
}

// test_compile_* 记录全局与 test_compile_artifact 见 src/test_support.jai。

// Fake build transpile step 与 build seam helper 见 src/test_support.jai。

test "Build without targets compiles nothing" {
    driver: Build_Driver;
    prepared: Prepared_Workspace;
    prepared.artifact_plans = Artifact_Plan.[];
    test_compile_count = 0;
    expect(build_prepared_workspace(*driver, *prepared, fake_build_transpile, test_compile_artifact) && test_compile_count == 0);
}

test "Unsafe package root blocks every compilation" {
    driver: Build_Driver;
    root := tprint("%1/missing-package-root", juice_root());
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", juice_root())}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/alpha.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    test_build_transpile_calls = 0;
    expect(!build_prepared_workspace(*driver, *prepared, fake_build_transpile, test_compile_artifact));
    expect(test_compile_count == 0 && test_build_transpile_calls == 0);
}

test "Escaping artifact plan blocks compilation" {
    driver: Build_Driver;
    root := juice_root();
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/../escape", root), artifact_path = tprint("%1/../escape/alpha.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    expect(!build_prepared_workspace(*driver, *prepared, fake_build_transpile, test_compile_artifact) && test_compile_count == 0);
}

test "Build forwards each prepared plan to compilation" {
    driver: Build_Driver;
    driver.root_dir = "driver-root";
    root := juice_root();
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/alpha.exe", root)},
        .{target = .{name = "beta",  main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/beta.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    test_compile_success = true;
    test_build_transpile_calls = 0;
    expect(build_prepared_workspace(*driver, *prepared, fake_build_transpile, test_compile_artifact));
    expect(test_compile_count == 2);
    expect(test_compiled_driver_root == "driver-root");
    expect(test_compiled_entry == plans[0].target.source_path);
    // The plan's source file has no test blocks: the transpile step never ran.
    expect(test_build_transpile_calls == 0);
    expect(test_compiled_plan.target.name == "beta" && test_compiled_plan.artifact_path == tprint("%1/target/beta.exe", root));
}

// The final gate before the compiler: a plan with an empty target name must
// never reach compile_artifact_plan (which would pass "-exe ''" through).
test "Build rejects a plan with an empty target name" {
    driver: Build_Driver;
    root := juice_root();
    plans := Artifact_Plan.[
        .{target = .{name = "", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    expect(!build_prepared_workspace(*driver, *prepared, fake_build_transpile, test_compile_artifact) && test_compile_count == 0);
}

test "Build fails fast on a compile failure" {
    driver: Build_Driver;
    root := juice_root();
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/alpha.exe", root)},
        .{target = .{name = "beta",  main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/beta.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    test_compile_success = false;
    expect(!build_prepared_workspace(*driver, *prepared, fake_build_transpile, test_compile_artifact));
    expect(test_compile_count == 1);
}

// ---------------------------------------------------------------------------
// Build transpile front (ticket 0021): the seam tests drive the production
// orchestration with recording fakes over real temp fixture files. The probe
// (production) reads and lexes the closure; the injectable transpile step is
// skipped entirely for test-free closures (zero transpile, zero cache) and
// runs once per closure file in dependency order otherwise.
// ---------------------------------------------------------------------------

// build_seam_write 见 src/test_support.jai。

// Test-free closure: the transpile step is never called, the compile seam
// receives the original entry, and no transpile tree is created.
test "Build front: a test-free closure skips the transpile step" {
    root := tprint("%1/target/build-seam-clean", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"helper.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/helper.jai", "helper :: () -> s32 { return 1; }\n"));

    driver: Build_Driver;
    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    expect(build_prepared_workspace(*driver, *prepared, fake_build_transpile, fake_build_compile));
    expect(test_build_transpile_calls == 0);
    expect(test_build_compile_calls == 1);
    expect(test_build_compiled_entries[0] == to_forward_slashes(plan.target.source_path));
    // Zero cache: nothing under the transpile tree was created.
    expect(!file_exists(tprint("%1/target/transpile", root)));
}

// Closure with test blocks: every closure file is viewed all-or-nothing
// (dependency order, so the load rewrite embeds the child's view path), the
// entry becomes the entry file's view, and files outside the closure are
// never transpiled.
test "Build front: a test closure is viewed all-or-nothing with load rewrites" {
    root := tprint("%1/target/build-seam-view", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"math.jai\";\n\nmain :: () { print(\"hi\\n\"); }\n"));
    expect(build_seam_write(root, "src/math.jai", "add :: (a: s32, b: s32) -> s32 { return a + b; }\n\ntest \"addition\" {\n}\n"));
    expect(build_seam_write(root, "src/unloaded.jai", "test \"never viewed\" {\n}\n"));

    driver: Build_Driver;
    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    expect(build_prepared_workspace(*driver, *prepared, fake_build_transpile, fake_build_compile));

    // Transpile ran once per closure file, children first (Merkle chain):
    // math.jai before main.jai; unloaded.jai stays untouched.
    expect(test_build_transpile_calls == 2);
    expect(test_build_transpiled_files.count == 2);
    expect(test_build_transpiled_files[0] == "src/math.jai" && test_build_transpiled_files[1] == "src/main.jai");

    // The entry's load rewrite points at the child's fake view path.
    math_view := tprint("%1/target/transpile/%2/src/math.jai", root, build_fake_key("src/math.jai"));
    expect(test_build_transpiled_rewrites.count == 1);
    expect(test_build_transpiled_rewrites[0] == tprint("src/math.jai -> %1", math_view));

    // The fake views were written content-addressed; the compile seam
    // received the entry file's fake view exactly once.
    expect(test_build_compile_calls == 1);
    entry_view := tprint("%1/target/transpile/%2/src/main.jai", root, build_fake_key("src/main.jai"));
    expect(test_build_compiled_entries[0] == entry_view);
    main_view, ok := read_entire_file(entry_view);
    expect(ok && main_view == "// fake build view of src/main.jai\n");
    expect(file_exists(math_view));
}

// Transpile diagnostics fail the build before the compile seam, with the
// original file coordinates.
test "Build front: transpile diagnostics fail before compiling" {
    root := tprint("%1/target/build-seam-diag", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "test \"nested in proc\" { }\n\nproc :: () {\n    test \"bad\" { }\n}\n"));

    driver: Build_Driver;
    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    test_build_fake_diagnostic = "test block 仅允许文件顶层";
    expect(!build_prepared_workspace(*driver, *prepared, fake_build_transpile, fake_build_compile));
    expect(test_build_compile_calls == 0);
}

// A cycle in the literal in-package #load graph of a viewed closure cannot
// be rewritten and fails with the dedicated diagnostic (issue 0008).
test "Build front: a load cycle cannot be rewritten" {
    root := tprint("%1/target/build-seam-cycle", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"a.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/a.jai", "#load \"main.jai\";\n\ntest \"cycle\" { }\n"));

    driver: Build_Driver;
    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    expect(!build_prepared_workspace(*driver, *prepared, fake_build_transpile, fake_build_compile));
    expect(test_build_compile_calls == 0);
}

// ---------------------------------------------------------------------------
// Production probe: closure shape over real fixture files (no fakes).
// ---------------------------------------------------------------------------

// The closure is the entry's literal in-package #load reachability: nested
// literal targets are followed, non-literal and out-of-package targets are
// not. Files come back in DFS preorder, loads in statement order.
test "Build probe: only literal in-package loads form the closure" {
    root := tprint("%1/target/build-probe-package", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"a.jai\";\n#load \"sub/b.jai\";\n#load CONST_NAME;\n#load \"../../outside.jai\";\n"));
    expect(build_seam_write(root, "src/a.jai", "x :: 1;\n"));
    expect(build_seam_write(root, "src/sub/b.jai", "y :: 2;\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    closure, ok := probe_build_closure(*prepared, plan);
    expect(ok && closure.count == 3);
    expect(closure[0].file.rel_path == "src/main.jai");
    expect(closure[1].file.rel_path == "src/a.jai" && closure[2].file.rel_path == "src/sub/b.jai");
    expect(closure[0].loads.count == 2);
    expect(closure[0].loads[0] == "src/a.jai" && closure[0].loads[1] == "src/sub/b.jai");
    for file: closure {
        expect(!file.has_tests);
    }
}

test "Build probe: test blocks are detected, pass-through shapes are not" {
    root := tprint("%1/target/build-probe-tests", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    // A top-level anchor, a nested anchor (rejected with a diagnostic when
    // viewed), and a non-statement `test` token that passes through.
    expect(build_seam_write(root, "src/has.jai", "test \"top\" { }\n"));
    expect(build_seam_write(root, "src/nested.jai", "proc :: () {\n    test \"bad\" { }\n}\n"));
    expect(build_seam_write(root, "src/pass.jai", "if test { }\n\ntest := 5;\n"));

    plan := build_seam_plan(root, "src/has.jai");
    prepared := build_seam_prepared(root, plan);
    closure, ok := probe_build_closure(*prepared, plan);
    expect(ok && closure.count == 1 && closure[0].has_tests);

    plan2 := build_seam_plan(root, "src/nested.jai");
    closure2, ok2 := probe_build_closure(*prepared, plan2);
    expect(ok2 && closure2.count == 1 && closure2[0].has_tests);

    plan3 := build_seam_plan(root, "src/pass.jai");
    closure3, ok3 := probe_build_closure(*prepared, plan3);
    expect(ok3 && closure3.count == 1 && !closure3[0].has_tests);
}

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
// out-of-package statements stay verbatim (issue 0008 resolution 4).
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
// E2E child scenarios: real juice.exe on fixture packages. Child 场景 helper
// （juice_exe、run_juice_child、expect_child_exit、child_output_contains）
// 见 src/test_support.jai。
// ---------------------------------------------------------------------------

// A BIN package with embedded tests builds through strip views: tests are
// stripped, the in-package load is rewritten to the child's view, the views
// match the pure transpile contract byte for byte, and the artifact keeps
// its semantics (prints the same greeting as the original program).
test "E2E: embedded-tests package builds through strip views" {
    fixture_root := tprint("%1/tests/data/test-package", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));

    result, output, _ := run_juice_child("test-package", "build");
    expect(expect_child_exit("build", result, 0));
    expect(child_output_contains("build", output, "[juice Build] Compiling Target 'test-package' (src/main.jai) -> target/..."));

    // The artifact exists and behaves like the original program.
    artifact := tprint("%1/target/test-package.exe", fixture_root);
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_child_exit("artifact", run_result, 0));
    expect(child_output_contains("artifact", run_output, "hello from test-package"));

    // Both closure files have strip views at their pure-contract paths.
    transpile_dir := tprint("%1/target/transpile", fixture_root);
    math_source, ok := read_entire_file(tprint("%1/src/math.jai", fixture_root));
    expect(ok);
    math_key := transpile_view_key("src/math.jai", math_source, .STRIP, Load_Target.[], JUICE_VERSION);
    math_view := transpile_view_path(transpile_dir, math_key, "src/math.jai");
    expect(path_exists_as_regular_file(math_view));
    math_result := transpile_source(math_source, .{mode = .STRIP, path = "src/math.jai"});
    math_view_text, ok2 := read_entire_file(math_view);
    expect(ok2 && math_view_text == math_result.view);

    main_source, ok3 := read_entire_file(tprint("%1/src/main.jai", fixture_root));
    expect(ok3);
    main_key := transpile_view_key("src/main.jai", main_source, .STRIP, Load_Target.[.{from = "src/math.jai", to = math_view}], JUICE_VERSION);
    main_view := transpile_view_path(transpile_dir, main_key, "src/main.jai");
    expect(path_exists_as_regular_file(main_view));
    main_result := transpile_source(main_source, .{mode = .STRIP, path = "src/main.jai", load_targets = Load_Target.[.{from = "src/math.jai", to = math_view}]});
    main_view_text, ok4 := read_entire_file(main_view);
    expect(ok4 && main_view_text == main_result.view);
    // Tests were stripped and the load rewritten to the child view.
    expect(find_index_from_left(main_view_text, "// juice: test stripped") >= 0);
    expect(find_index_from_left(main_view_text, math_view) >= 0);
}

// A test-free package builds without any transpile: no views, no cache
// tree, the artifact comes straight from the original entry.
test "E2E: test-free package builds with zero transpile" {
    fixture_root := tprint("%1/tests/data/build-empty", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));

    result, output, _ := run_juice_child("build-empty", "build");
    expect(expect_child_exit("build-empty", result, 0));
    expect(file_exists(tprint("%1/target/build-empty.exe", fixture_root)));
    expect(!file_exists(tprint("%1/target/transpile", fixture_root)));
}

// run inherits the strip semantics through its build prerequisite: the
// embedded-tests package builds via views and the artifact launches.
test "E2E: run inherits strip semantics through build" {
    fixture_root := tprint("%1/tests/data/test-package", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));

    result, output, _ := run_juice_child("test-package", "run");
    expect(expect_child_exit("run", result, 0));
    expect(child_output_contains("run", output, "[juice Run] Launching"));
    expect(child_output_contains("run", output, "hello from test-package"));
}
