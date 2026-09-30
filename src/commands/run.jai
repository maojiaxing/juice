#import "Basic";
#import "File";
#import "Process";
#import "Juice";

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
    prepared := get_prepared_workspace(*ctx.workspace);
    if prepared == null {
        print("[juice ERROR] Command 'run' requires workspace preparation.\n");
        return false;
    }
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

// Compatibility entry point. Command handlers use the prepared plan so
// Build and Run cannot disagree about output naming or directories.
run_executable :: (driver: *Build_Driver, pkg: Package, requested_target: string) -> bool {
    plans_result := resolve_artifact_plans(pkg);
    if !plans_result.success {
        print("[juice ERROR] %\n", plans_result.error_message);
        return false;
    }
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = pkg.dir;
    prepared.discovery.root_package = pkg;
    prepared.artifact_plans = plans_result.plans;
    return run_prepared_workspace(*prepared, requested_target);
}
