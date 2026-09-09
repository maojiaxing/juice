run_command_handler :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if arguments.count > 1 {
        print("[juice ERROR] Usage: juice run [target]\n");
        return false;
    }
    if !ctx.workspace_prepared {
        print("[juice ERROR] Command 'run' requires workspace preparation.\n");
        return false;
    }
    target_name := ifx arguments.count == 1 then arguments[0] else "";
    return run_prepared_workspace(*ctx.prepared, target_name);
}
