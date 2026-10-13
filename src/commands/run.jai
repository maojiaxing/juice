#import "Basic";
#import "File";
#import "Process";
#import "Juice";
#import "Testing";

RUN_COMMAND :: Command.{
    name          = "run",
    description   = "Build and run an executable target",
    usage         = "juice run [target]",
    prerequisites = string.["build"],
    visible       = true,
    handler       = run_command_handler,
    validate_arguments = run_arguments_are_valid,
};

run_arguments_are_valid :: (arguments: [] string) -> bool {
    return arguments.count <= 1;
}

run_command_handler :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if !command_arguments_are_valid(RUN_COMMAND, arguments) return false;
    prepared := require_prepared_workspace("run", *ctx.workspace);
    if prepared == null return false;
    target_name := ifx arguments.count == 1 then arguments[0] else "";
    return run_prepared_workspace(prepared, target_name);
}

// Selection is deliberately case-sensitive: target declaration uniqueness is
// case-insensitive, while the command-line spelling is exact.
select_artifact_plan :: (plans: [] Artifact_Plan, package_name: string, requested_target: string) -> Artifact_Plan, bool {
    if plans.count == 0 return .{}, false;

    if requested_target != "" {
        for plan: plans {
            if plan.target.name == requested_target return plan, true;
        }
        return .{}, false;
    }

    if plans.count == 1 return plans[0], true;
    for plan: plans {
        if plan.target.name == package_name return plan, true;
    }
    return .{}, false;
}

run_artifact_plan :: (plan: Artifact_Plan, package_root: string) -> bool {
    if !revalidate_artifact_plan(plan, package_root) {
        print("[juice ERROR] Refusing unsafe artifact path: %\n", plan.artifact_path);
        return false;
    }
    if !file_exists(plan.artifact_path) {
        print("[juice ERROR] Could not find executable to run: %\n", plan.artifact_path);
        return false;
    }

    print("[juice Run] Launching % ...\n\n", plan.artifact_path);
    result := run_command(plan.artifact_path);
    return result.exit_code == 0;
}

run_prepared_workspace :: (
    prepared: *Prepared_Workspace,
    requested_target: string,
    launch: #type (plan: Artifact_Plan, package_root: string) -> bool = run_artifact_plan
) -> bool {
    plan, found := select_artifact_plan(prepared.artifact_plans, prepared.discovery.root_package.name, requested_target);
    if !found {
        if prepared.artifact_plans.count == 0 {
            print("[juice ERROR] Package has no executable target to run.\n");
        } else if requested_target == "" {
            print("[juice ERROR] Multiple targets exist; select one explicitly or define a target named '%'.\n", prepared.discovery.root_package.name);
        } else {
            print("[juice ERROR] Unknown binary target: %\n", requested_target);
        }
        return false;
    }
    return launch(plan, prepared.discovery.root_dir);
}

// ---------------------------------------------------------------------------
// 内联测试（票 0034 自旧 tests/ 迁移）：Run 目标选择与 launch
// seam；E2E child 场景验证 run 经由 build 前置继承剥离语义。共享 helper
// （test_launch_* 记录全局、run_juice_child 等 child 场景 helper）见
// tests/test_support.jai。
// ---------------------------------------------------------------------------

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

// run inherits the strip semantics through its build prerequisite: the
// embedded-tests package builds via views and the artifact launches.
test "E2E: run inherits strip semantics through build" {
    fixture_root := tprint("%1/tests/data/test-package", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));

    result, output, _ := run_juice_child("test-package", "run");
    expect(expect_exit("run", result, 0, "build child"));
    expect(child_output_contains("run", output, "[juice Run] Launching"));
    expect(child_output_contains("run", output, "hello from test-package"));
}
