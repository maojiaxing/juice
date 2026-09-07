prepare_workspace_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if arguments.count != 0 {
        print("[juice ERROR] Internal command 'prepare-workspace' does not accept arguments.\n");
        return false;
    }

    if ctx.workspace_prepared return true;

    print("[juice 🍹] Squeezing build dependencies in %1 ...\n", ctx.driver.root_dir);

    root_package, ok := load_package_manifest(ctx.driver, ctx.driver.root_dir);
    if !ok {
        print("[juice ERROR] Could not load 'package.jai' in directory: %1\n", ctx.driver.root_dir);
        return false;
    }

    ctx.root_package = root_package;
    print("[juice] Package '%1' (v%2) loaded.\n", ctx.root_package.name, ctx.root_package.version);

    array_reset_keeping_memory(*ctx.driver.member_paths);
    array_add(*ctx.driver.member_paths, ctx.driver.root_dir);
    for relative_path : ctx.root_package.workspace.members {
        member_path := tprint("%1/%2", ctx.driver.root_dir, relative_path);
        array_add(*ctx.driver.member_paths, member_path);
    }

    if !resolve_and_fetch_dependencies(ctx.driver, ctx.root_package) {
        print("[juice ERROR] Dependency resolution failed.\n");
        return false;
    }

    ctx.workspace_prepared = true;
    return true;
}
