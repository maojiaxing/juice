BUILD_COMMAND :: Command.{
    name          = "build",
    description   = "Build all targets in the root package",
    usage         = "juice build",
    prerequisites = string.["prepare-workspace"],
    visible       = true,
    handler       = build_command,
};

build_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if !command_arguments_are_valid(BUILD_COMMAND, arguments) return false;
    prepared := get_prepared_workspace(*ctx.workspace);
    if prepared == null {
        print("[juice ERROR] Command 'build' requires workspace preparation.\n");
        return false;
    }
    if !build_prepared_workspace(ctx.driver, prepared) return false;
    print("[juice] Build completed successfully!\n");
    return true;
}
