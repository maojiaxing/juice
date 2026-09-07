build_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if arguments.count != 0 {
        print("[juice ERROR] Usage: juice build\n");
        return false;
    }

    if !ctx.workspace_prepared {
        print("[juice ERROR] Command 'build' requires workspace preparation.\n");
        return false;
    }

    if !build_all_targets(ctx.driver, *ctx.root_package) return false;

    print("[juice 🍹] Build completed successfully!\n");
    return true;
}
