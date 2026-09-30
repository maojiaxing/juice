#import "Basic";
#import "Hash_Table";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
#import "System";
#import "Juice";

#load "../src/xdg.jai";
#load "../src/path_safety.jai";
#load "../src/manifest.jai";
#load "../src/workspace.jai";
#load "../src/target.jai";
#load "../src/dependency.jai";
#load "../src/builder.jai";
#load "../src/commands/command.jai";
#load "../src/commands/prepare.jai";
#load "../src/commands/build.jai";
#load "../src/commands/run.jai";
#load "../src/commands/clean.jai";
#load "../src/commands/registry.jai";
#load "../src/dispatcher.jai";
#load "test_commands.jai";
#load "test_workspace.jai";

test_a_calls: s64 = 0;
test_b_calls: s64 = 0;
test_c_calls: s64 = 0;
test_d_calls: s64 = 0;
test_fail_calls: s64 = 0;

reset_dispatch_counters :: () {
    test_a_calls = 0;
    test_b_calls = 0;
    test_c_calls = 0;
    test_d_calls = 0;
    test_fail_calls = 0;
}

test_handler_a :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_a_calls += 1;
    return true;
}

test_handler_b :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_b_calls += 1;
    return true;
}

test_handler_c :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_c_calls += 1;
    return true;
}

test_handler_d :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_d_calls += 1;
    return true;
}

test_handler_fail :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_fail_calls += 1;
    return false;
}

strict_arguments_are_invalid :: (arguments: [] string) -> bool {
    return false;
}

TEST_REGISTRY_SIMPLE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], visible = true, handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.[], visible = true, handler = test_handler_b},
];

TEST_REGISTRY_DUPLICATE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], visible = true, handler = test_handler_a},
    .{name = "a", description = "Command A Duplicate", usage = "test a", prerequisites = string.[], visible = true, handler = test_handler_b},
];

TEST_REGISTRY_MISSING_PREREQ :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.["nonexistent"], visible = true, handler = test_handler_a},
];

TEST_REGISTRY_INTERNAL :: Command.[
    .{name = "internal", description = "Internal Command", usage = "test internal", prerequisites = string.[], visible = false, handler = test_handler_a},
    .{name = "public", description = "Public Command", usage = "test public", prerequisites = string.["internal"], visible = true, handler = test_handler_b},
];

TEST_REGISTRY_CYCLE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.["b"], visible = true, handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.["a"], visible = true, handler = test_handler_b},
];

TEST_REGISTRY_DIAMOND :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], visible = true, handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.["a"], visible = true, handler = test_handler_b},
    .{name = "c", description = "Command C", usage = "test c", prerequisites = string.["a"], visible = true, handler = test_handler_c},
    .{name = "d", description = "Command D", usage = "test d", prerequisites = string.["b", "c"], visible = true, handler = test_handler_d},
];

TEST_REGISTRY_FAILURE :: Command.[
    .{name = "failing", description = "Failing Command", usage = "test failing", prerequisites = string.[], visible = true, handler = test_handler_fail},
    .{name = "target", description = "Target Command", usage = "test target", prerequisites = string.["failing"], visible = true, handler = test_handler_b},
];

TEST_REGISTRY_ARGUMENTS :: Command.[
    .{name = "sideeffect", description = "Side Effect Command", usage = "test sideeffect", prerequisites = string.[], visible = true, handler = test_handler_a},
    .{name = "strict", description = "Strict Command", usage = "test strict", prerequisites = string.["sideeffect"], visible = true, validate_arguments = strict_arguments_are_invalid, handler = test_handler_b},
];

run_test :: (name: string, test_proc: () -> bool) -> bool {
    result := test_proc();
    if result print("[PASS] %\n", name);
    else print("[FAIL] %\n", name);
    return result;
}

test_production_registry_is_valid :: () -> bool {
    return validate_registry(COMMAND_REGISTRY).success;
}

test_duplicate_command_detection :: () -> bool {
    result := validate_registry(TEST_REGISTRY_DUPLICATE);
    return !result.success && result.error == .DUPLICATE_COMMAND_NAME;
}

test_missing_prerequisite_detection :: () -> bool {
    result := validate_registry(TEST_REGISTRY_MISSING_PREREQ);
    return !result.success && result.error == .MISSING_PREREQUISITE;
}

test_unknown_command_rejected :: () -> bool {
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_SIMPLE, "missing", *ctx, string.[]);
    return !result.success && result.error == .UNKNOWN_COMMAND;
}

test_internal_command_rejected :: () -> bool {
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_INTERNAL, "internal", *ctx, string.[]);
    return !result.success && result.error == .INTERNAL_COMMAND_INVOKED;
}

test_internal_command_runs_as_prerequisite :: () -> bool {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_INTERNAL, "public", *ctx, string.[]);
    return result.success && test_a_calls == 1 && test_b_calls == 1;
}

test_cycle_rejected_before_execution :: () -> bool {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_CYCLE, "a", *ctx, string.[]);
    return !result.success && result.error == .CYCLE_DETECTED && test_a_calls == 0 && test_b_calls == 0;
}

test_diamond_executes_each_command_once :: () -> bool {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_DIAMOND, "d", *ctx, string.[]);
    return result.success && test_a_calls == 1 && test_b_calls == 1 && test_c_calls == 1 && test_d_calls == 1;
}

test_invalid_arguments_rejected_before_prerequisites :: () -> bool {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_ARGUMENTS, "strict", *ctx, string.["unexpected"]);
    return !result.success && result.error == .INVALID_ARGUMENTS && test_a_calls == 0 && test_b_calls == 0;
}

test_prerequisite_failure_propagates :: () -> bool {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_FAILURE, "target", *ctx, string.[]);
    return !result.success && result.error == .PREREQUISITE_FAILED && test_fail_calls == 1 && test_b_calls == 0;
}

test_handler_failure_reported :: () -> bool {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_FAILURE, "failing", *ctx, string.[]);
    return !result.success && result.error == .HANDLER_FAILED && result.command == "failing" && test_fail_calls == 1;
}

test_manifest_protocol :: () -> bool {
    valid := parse_manifest_data_strict("NAME=demo\nVERSION=1\nTYPE=1\nTARGET=app|src/main.jai\n");
    if !valid.success || valid.package.targets.count != 1 return false;
    if valid.package.targets[0].name != "app" return false;

    unknown := parse_manifest_data_strict("NAME=demo\nVERSION=1\nNOPE=x\n");
    if unknown.success return false;
    malformed := parse_manifest_data_strict("TARGET=app|src/main.jai|result\n");
    return !malformed.success;
}

test_selection :: () -> bool {
    plans := Artifact_Plan.[
        .{target = .{name = "alpha"}, result_dir = "root/result", artifact_path = "root/result/alpha.exe"},
        .{target = .{name = "demo"}, result_dir = "root/result", artifact_path = "root/result/demo.exe"},
    ];
    selected, found := select_artifact_plan(plans, "demo", "");
    if !found || selected.target.name != "demo" return false;
    selected, found = select_artifact_plan(plans, "demo", "alpha");
    if !found || selected.target.name != "alpha" return false;
    _, found = select_artifact_plan(plans, "demo", "Alpha");
    return !found;
}

main :: () {
    all_ok := true;
    all_ok = run_test("Production registry validation", test_production_registry_is_valid) && all_ok;
    all_ok = run_test("Duplicate command detection", test_duplicate_command_detection) && all_ok;
    all_ok = run_test("Missing prerequisite detection", test_missing_prerequisite_detection) && all_ok;
    all_ok = run_test("Unknown command rejected", test_unknown_command_rejected) && all_ok;
    all_ok = run_test("Internal command rejected for direct invocation", test_internal_command_rejected) && all_ok;
    all_ok = run_test("Internal command runs as prerequisite", test_internal_command_runs_as_prerequisite) && all_ok;
    all_ok = run_test("Cycle rejected before execution", test_cycle_rejected_before_execution) && all_ok;
    all_ok = run_test("Diamond executes each command once", test_diamond_executes_each_command_once) && all_ok;
    all_ok = run_test("Invalid arguments rejected before prerequisites", test_invalid_arguments_rejected_before_prerequisites) && all_ok;
    all_ok = run_test("Prerequisite failure propagates", test_prerequisite_failure_propagates) && all_ok;
    all_ok = run_test("Handler failure reported", test_handler_failure_reported) && all_ok;
    all_ok = run_test("Strict manifest protocol", test_manifest_protocol) && all_ok;
    all_ok = run_test("Case-sensitive target selection", test_selection) && all_ok;
    all_ok = run_test("Command-owned declarations in production registry", test_command_declarations) && all_ok;
    all_ok = run_test("Command argument and preparation guards", test_command_argument_guards) && all_ok;
    all_ok = run_test("Run launches the selected prepared artifact", test_run_selects_prepared_artifact) && all_ok;
    all_ok = run_test("Run defaults to the only target", test_run_single_target) && all_ok;
    all_ok = run_test("Invalid Run selection never launches", test_run_invalid_selection_never_launches) && all_ok;
    all_ok = run_test("Run propagates launch failure", test_run_propagates_launch_failure) && all_ok;
    all_ok = run_test("Clean validates workspace scope before deletion", test_clean_workspace_scope) && all_ok;
    all_ok = run_test("Clean without a manifest uses the current root", test_clean_without_manifest) && all_ok;
    all_ok = run_test("Unsafe Clean path prevents every deletion", test_clean_invalid_path_prevents_all_deletions) && all_ok;
    all_ok = run_test("Clean continues after a deletion fails", test_clean_continues_after_delete_failure) && all_ok;
    all_ok = run_test("Discovery publishes workspace state once", test_discovery_publishes_state_once) && all_ok;
    all_ok = run_test("Discovery without a package stays empty", test_discovery_without_package_stays_empty) && all_ok;
    all_ok = run_test("Preparation without targets skips dependencies", test_preparation_without_targets_skips_dependencies) && all_ok;
    all_ok = run_test("Preparation with targets prepares dependencies", test_preparation_with_targets_prepares_dependencies) && all_ok;
    all_ok = run_test("Resolution failure publishes no prepared workspace", test_resolution_failure_publishes_nothing) && all_ok;
    all_ok = run_test("Dependency failure publishes no prepared workspace", test_dependency_failure_publishes_nothing) && all_ok;
    all_ok = run_test("Preparation requires discovery", test_preparation_requires_discovery) && all_ok;
    all_ok = run_test("Workspace member dependencies are not fetched", test_member_dependencies_are_not_fetched) && all_ok;
    all_ok = run_test("Dependency fetch failure propagates", test_fetch_failure_propagates) && all_ok;
    if !all_ok exit(1);
}
