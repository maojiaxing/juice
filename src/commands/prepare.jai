DISCOVER_WORKSPACE_COMMAND :: Command.{
    name          = "discover-workspace",
    description   = "Internal: Discover and validate workspace members",
    usage         = "juice discover-workspace",
    prerequisites = string.[],
    visible       = false,
    handler       = discover_workspace_command,
};

PREPARE_WORKSPACE_COMMAND :: Command.{
    name          = "prepare-workspace",
    description   = "Internal: Resolve package targets and dependencies",
    usage         = "juice prepare-workspace",
    prerequisites = string.["discover-workspace"],
    visible       = false,
    handler       = prepare_workspace_command,
};

discover_workspace_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if !command_arguments_are_valid(DISCOVER_WORKSPACE_COMMAND, arguments) return false;
    return ensure_workspace_discovered(ctx.driver, *ctx.workspace);
}

prepare_workspace_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if !command_arguments_are_valid(PREPARE_WORKSPACE_COMMAND, arguments) return false;
    return prepare_workspace(ctx.driver, *ctx.workspace);
}
