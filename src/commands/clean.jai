clean_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if arguments.count != 0 {
        print("[juice ERROR] Usage: juice clean\n");
        return false;
    }

    clean_workspace(ctx.driver);
    return true;
}
