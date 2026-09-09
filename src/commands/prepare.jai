discover_workspace_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if arguments.count != 0 {
        print("[juice ERROR] Internal command 'discover-workspace' does not accept arguments.\n");
        return false;
    }
    if ctx.workspace_discovered return true;

    discovery, ok := discover_workspace(ctx.driver);
    if !ok || !discovery.has_package {
        if ok print("[juice ERROR] No package.jai found in current directory.\n");
        return false;
    }
    ctx.discovery = discovery;
    ctx.workspace_discovered = true;
    print("[juice] Package '%' (v%) discovered.\n", discovery.root_package.name, discovery.root_package.version);
    return true;
}

prepare_workspace_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if arguments.count != 0 {
        print("[juice ERROR] Internal command 'prepare-workspace' does not accept arguments.\n");
        return false;
    }
    if ctx.workspace_prepared return true;
    if !ctx.workspace_discovered {
        print("[juice ERROR] Workspace discovery is required before preparation.\n");
        return false;
    }

    plans_result := resolve_artifact_plans(ctx.discovery.root_package);
    if !plans_result.success {
        print("[juice ERROR] %\n", plans_result.error_message);
        return false;
    }

    ctx.prepared.discovery = ctx.discovery;
    ctx.prepared.artifact_plans = plans_result.plans;

    // No targets means a successful no-op build and no dependency side effect.
    if ctx.prepared.artifact_plans.count > 0 {
        print("[juice] Preparing workspace dependencies...\n");
        if !resolve_and_fetch_dependencies(ctx.driver, ctx.discovery.member_paths) {
            print("[juice ERROR] Dependency resolution failed.\n");
            return false;
        }
        ctx.prepared.dependencies_prepared = true;
    }

    ctx.workspace_prepared = true;
    return true;
}
