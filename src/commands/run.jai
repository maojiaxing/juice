#import "Basic";
#import "File_Utilities";
#import "Process";

// The run command (spec section 4.3/4.6, the old juice commands/run.jai
// semantics): the thin prerequisite client of build — the dispatcher plans
// build before run (the only prerequisite edge) and a build failure stops
// run with PREREQUISITE_FAILED. The handler then prepares the workspace
// (idempotent: build's prerequisite run already drove the phase machine to
// PREPARED, so the prepared state is returned untouched), selects the
// artifact plan and launches it; the artifact inherits the process cwd (the
// package root — juice never chdirs) and its output and exit code pass
// through.
//
// The Package face is consumed through the namespaced Juice binding
// (src/juice_module.jai), as in the workspace/target layers.

RUN_COMMAND :: Command.{
    name          = "run",
    description   = "Build and run an executable target",
    usage         = "juice run [target]",
    prerequisites = string.["build"],
    handler       = run_command_handler,
    validate_arguments = run_arguments_are_valid,
};

run_arguments_are_valid :: (arguments: [] string) -> bool {
    return arguments.count <= 1;
}

run_command_handler :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if !command_arguments_are_valid(RUN_COMMAND, arguments) return false;
    prepared := ensure_workspace_prepared(ctx.root_dir, ctx.cache_dir, *ctx.workspace);
    if prepared == null return false;
    target_name := ifx arguments.count == 1 then arguments[0] else "";
    return run_prepared_workspace(prepared, target_name);
}

// Selection is deliberately case-sensitive: target declaration uniqueness is
// case-insensitive, while the command-line spelling is exact.
select_artifact_plan :: (plans: [] Juice.Artifact_Plan, package_name: string, requested_target: string) -> Juice.Artifact_Plan, bool {
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

run_artifact_plan :: (plan: Juice.Artifact_Plan, package_root: string) -> bool {
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

// The launch seam keeps the old juice shape (#type (plan, package_root) ->
// bool with production default run_artifact_plan) — the at_EXECUTE mount
// point (spec section 6.3).
run_prepared_workspace :: (
    prepared: *Juice.Prepared_Workspace,
    requested_target: string,
    launch: #type (plan: Juice.Artifact_Plan, package_root: string) -> bool = run_artifact_plan
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
