test_command_declarations :: () -> bool {
    if !validate_registry(COMMAND_REGISTRY).success || COMMAND_REGISTRY.count != 5 return false;
    expected := Command.[DISCOVER_WORKSPACE_COMMAND, PREPARE_WORKSPACE_COMMAND, BUILD_COMMAND, RUN_COMMAND, CLEAN_COMMAND];
    for declaration, i: expected {
        registered := COMMAND_REGISTRY[i];
        if registered.name != declaration.name || registered.description != declaration.description return false;
        if registered.usage != declaration.usage || registered.visible != declaration.visible return false;
        if registered.handler != declaration.handler return false;
        if registered.validate_arguments != declaration.validate_arguments return false;
        if registered.prerequisites.count != declaration.prerequisites.count return false;
        for prerequisite, j: declaration.prerequisites {
            if registered.prerequisites[j] != prerequisite return false;
        }
    }
    if DISCOVER_WORKSPACE_COMMAND.visible || PREPARE_WORKSPACE_COMMAND.visible return false;
    if !BUILD_COMMAND.visible || !RUN_COMMAND.visible || !CLEAN_COMMAND.visible return false;
    if RUN_COMMAND.prerequisites.count != 1 || RUN_COMMAND.prerequisites[0] != "build" return false;
    if BUILD_COMMAND.prerequisites.count != 1 || BUILD_COMMAND.prerequisites[0] != "prepare-workspace" return false;
    if PREPARE_WORKSPACE_COMMAND.prerequisites.count != 1 || PREPARE_WORKSPACE_COMMAND.prerequisites[0] != "discover-workspace" return false;
    return DISCOVER_WORKSPACE_COMMAND.prerequisites.count == 0 && CLEAN_COMMAND.prerequisites.count == 0;
}

test_command_argument_guards :: () -> bool {
    // Null driver makes an accidental operation after argument rejection visible.
    ctx: Command_Context;
    if BUILD_COMMAND.handler(*ctx, string.["unexpected"]) return false;
    if RUN_COMMAND.handler(*ctx, string.["one", "two"]) return false;
    if CLEAN_COMMAND.handler(*ctx, string.["unexpected"]) return false;
    if DISCOVER_WORKSPACE_COMMAND.handler(*ctx, string.["unexpected"]) return false;
    if PREPARE_WORKSPACE_COMMAND.handler(*ctx, string.["unexpected"]) return false;
    if BUILD_COMMAND.handler(*ctx, string.[]) return false;
    return !RUN_COMMAND.handler(*ctx, string.[]);
}

test_launch_count: s64;
test_launched_plan: Artifact_Plan;
test_launched_root: string;
test_launch_success: bool;

test_launch_artifact :: (plan: Artifact_Plan, package_root: string) -> bool {
    test_launch_count += 1;
    test_launched_plan = plan;
    test_launched_root = package_root;
    return test_launch_success;
}

test_run_selects_prepared_artifact :: () -> bool {
    plans := Artifact_Plan.[
        .{target = .{name = "alpha"}, result_dir = "root/result", artifact_path = "root/result/alpha.exe"},
        .{target = .{name = "demo"}, result_dir = "root/result", artifact_path = "root/result/demo.exe"},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = "root";
    prepared.discovery.root_package.name = "demo";
    prepared.artifact_plans = plans;
    test_launch_count = 0;
    test_launch_success = true;

    if !run_prepared_workspace(*prepared, "", test_launch_artifact) return false;
    if test_launch_count != 1 || test_launched_plan.artifact_path != plans[1].artifact_path return false;
    if test_launched_root != "root" || test_launched_plan.result_dir != plans[1].result_dir return false;
    if !run_prepared_workspace(*prepared, "alpha", test_launch_artifact) return false;
    return test_launch_count == 2 && test_launched_plan.artifact_path == plans[0].artifact_path;
}

test_run_single_target :: () -> bool {
    plans := Artifact_Plan.[.{target = .{name = "only"}, artifact_path = "root/result/only.exe"}];
    prepared: Prepared_Workspace;
    prepared.discovery.root_package.name = "different-package-name";
    prepared.artifact_plans = plans;
    test_launch_count = 0;
    test_launch_success = true;
    if !run_prepared_workspace(*prepared, "", test_launch_artifact) return false;
    return test_launch_count == 1 && test_launched_plan.artifact_path == plans[0].artifact_path;
}

test_run_invalid_selection_never_launches :: () -> bool {
    plans := Artifact_Plan.[.{target = .{name = "alpha"}}, .{target = .{name = "beta"}}];
    prepared: Prepared_Workspace;
    prepared.discovery.root_package.name = "demo";
    prepared.artifact_plans = plans;
    test_launch_count = 0;
    test_launch_success = true;
    if run_prepared_workspace(*prepared, "", test_launch_artifact) return false;
    if run_prepared_workspace(*prepared, "missing", test_launch_artifact) return false;
    if run_prepared_workspace(*prepared, "Alpha", test_launch_artifact) return false;
    prepared.artifact_plans = Artifact_Plan.[];
    if run_prepared_workspace(*prepared, "", test_launch_artifact) return false;
    return test_launch_count == 0;
}

test_run_propagates_launch_failure :: () -> bool {
    plans := Artifact_Plan.[.{target = .{name = "demo"}}];
    prepared: Prepared_Workspace;
    prepared.artifact_plans = plans;
    test_launch_count = 0;
    test_launch_success = false;
    if run_prepared_workspace(*prepared, "", test_launch_artifact) return false;
    return test_launch_count == 1;
}

test_clean_validated: [..] string;
test_clean_deleted: [..] string;
test_clean_invalid_path: string;
test_clean_failed_delete: string;
test_clean_expected_validations: s64;
test_clean_deleted_too_early: bool;

reset_clean_test :: (expected_validations: s64) {
    array_reset(*test_clean_validated);
    array_reset(*test_clean_deleted);
    test_clean_invalid_path = "";
    test_clean_failed_delete = "";
    test_clean_expected_validations = expected_validations;
    test_clean_deleted_too_early = false;
}

test_validate_clean_path :: (path: string) -> bool {
    array_add(*test_clean_validated, path);
    return path != test_clean_invalid_path;
}

test_delete_clean_path :: (path: string) -> bool {
    if test_clean_validated.count != test_clean_expected_validations test_clean_deleted_too_early = true;
    array_add(*test_clean_deleted, path);
    return path != test_clean_failed_delete;
}

test_clean_workspace_scope :: () -> bool {
    driver: Build_Driver;
    driver.root_dir = "unused-driver-root";
    discovery: Workspace_Discovery;
    discovery.has_package = true;
    discovery.root_dir = "root";
    discovery.member_packages = Package.[.{name = "root", dir = "root"}, .{name = "member", dir = "root/member"}];
    reset_clean_test(3);
    if !clean_discovered_workspace(*driver, discovery, test_validate_clean_path, test_delete_clean_path) return false;
    if test_clean_deleted_too_early || test_clean_deleted.count != 3 return false;
    if test_clean_deleted[0] != "root/result" || test_clean_deleted[1] != "root/member/result" return false;
    return test_clean_deleted[2] == "root/.packages";
}

test_clean_without_manifest :: () -> bool {
    driver: Build_Driver;
    driver.root_dir = "root";
    discovery: Workspace_Discovery;
    reset_clean_test(2);
    if !clean_discovered_workspace(*driver, discovery, test_validate_clean_path, test_delete_clean_path) return false;
    if test_clean_deleted_too_early || test_clean_deleted.count != 2 return false;
    return test_clean_deleted[0] == "root/result" && test_clean_deleted[1] == "root/.packages";
}

test_clean_invalid_path_prevents_all_deletions :: () -> bool {
    driver: Build_Driver;
    discovery: Workspace_Discovery;
    discovery.has_package = true;
    discovery.root_dir = "root";
    discovery.member_packages = Package.[.{name = "root", dir = "root"}, .{name = "member", dir = "root/member"}];
    reset_clean_test(3);
    test_clean_invalid_path = "root/.packages";
    if clean_discovered_workspace(*driver, discovery, test_validate_clean_path, test_delete_clean_path) return false;
    return test_clean_validated.count == 3 && test_clean_deleted.count == 0;
}

test_clean_continues_after_delete_failure :: () -> bool {
    driver: Build_Driver;
    discovery: Workspace_Discovery;
    discovery.has_package = true;
    discovery.root_dir = "root";
    discovery.member_packages = Package.[.{name = "root", dir = "root"}, .{name = "member", dir = "root/member"}];
    reset_clean_test(3);
    test_clean_failed_delete = "root/result";
    if clean_discovered_workspace(*driver, discovery, test_validate_clean_path, test_delete_clean_path) return false;
    if test_clean_deleted_too_early || test_clean_deleted.count != 3 return false;
    return test_clean_deleted[1] == "root/member/result" && test_clean_deleted[2] == "root/.packages";
}

test_compile_count: s64;
test_compiled_plan: Artifact_Plan;
test_compiled_driver_root: string;
test_compile_success: bool;

test_compile_artifact :: (driver: *Build_Driver, plan: Artifact_Plan) -> bool {
    test_compile_count += 1;
    test_compiled_plan = plan;
    test_compiled_driver_root = driver.root_dir;
    return test_compile_success;
}

test_build_without_targets_compiles_nothing :: () -> bool {
    driver: Build_Driver;
    prepared: Prepared_Workspace;
    prepared.artifact_plans = Artifact_Plan.[];
    test_compile_count = 0;
    return build_prepared_workspace(*driver, *prepared, test_compile_artifact) && test_compile_count == 0;
}

test_build_revalidation_gate_blocks_unsafe_root :: () -> bool {
    driver: Build_Driver;
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = "test_commands.jai"}, result_dir = "./result", artifact_path = "./result/alpha.exe"},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = "missing-package-root";
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    return !build_prepared_workspace(*driver, *prepared, test_compile_artifact) && test_compile_count == 0;
}

test_build_revalidation_gate_blocks_escaping_plan :: () -> bool {
    driver: Build_Driver;
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = "test_commands.jai"}, result_dir = "../escape", artifact_path = "../escape/alpha.exe"},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = ".";
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    return !build_prepared_workspace(*driver, *prepared, test_compile_artifact) && test_compile_count == 0;
}

test_build_compiles_each_prepared_plan :: () -> bool {
    driver: Build_Driver;
    driver.root_dir = "driver-root";
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = "test_commands.jai"}, result_dir = "./result", artifact_path = "./result/alpha.exe"},
        .{target = .{name = "beta",  main_file = "src/main.jai", source_path = "test_commands.jai"}, result_dir = "./result", artifact_path = "./result/beta.exe"},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = ".";
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    test_compile_success = true;
    if !build_prepared_workspace(*driver, *prepared, test_compile_artifact) return false;
    if test_compile_count != 2 return false;
    if test_compiled_driver_root != "driver-root" return false;
    return test_compiled_plan.target.name == "beta" && test_compiled_plan.artifact_path == "./result/beta.exe";
}

test_build_fails_fast_on_compile_failure :: () -> bool {
    driver: Build_Driver;
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = "test_commands.jai"}, result_dir = "./result", artifact_path = "./result/alpha.exe"},
        .{target = .{name = "beta",  main_file = "src/main.jai", source_path = "test_commands.jai"}, result_dir = "./result", artifact_path = "./result/beta.exe"},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = ".";
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    test_compile_success = false;
    if build_prepared_workspace(*driver, *prepared, test_compile_artifact) return false;
    return test_compile_count == 1;
}
