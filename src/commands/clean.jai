clean_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if arguments.count != 0 {
        print("[juice ERROR] Usage: juice clean\n");
        return false;
    }

    discovery, ok := discover_workspace_for_clean(ctx.driver);
    if !ok {
        print("[juice ERROR] Clean discovery failed; no files were deleted.\n");
        return false;
    }
    return clean_discovered_workspace(ctx.driver, discovery);
}
