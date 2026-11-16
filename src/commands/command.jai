
COMMAND_REGISTRY :: Command.[
    BUILD_COMMAND,
    RUN_COMMAND,
    CLEAN_COMMAND,
    TEST_COMMAND,
    UPDATE_COMMAND,
    VERSION_COMMAND,
    HELP_COMMAND,
];

// The argument contract and the per-command usage rendering. Package/workspace
// selection flags (--workspace, -p/--package, --package-path) and --offline are
// parsed by the shared parser in src/commands/selection.jai (ticket 0093), so
// every command accepts exactly the same selection surface.
Command_Handler :: #type (ctx: *Command_Context, arguments: [] string) -> bool;
Command_Argument_Validator :: #type (arguments: [] string) -> bool;

Command_Context :: struct {
    // The two process-wide paths (the only survivors of the Build_Driver
    // teardown; derived paths like packages_dir are derived by their own
    // owners): the package root (the working directory at startup) and the
    // juice cache directory (under the XDG cache home). The workspace phase
    // machine (EMPTY -> DISCOVERED -> PREPARED, src/workspace.jai) rides
    // along for the command handlers; it zero-initializes to EMPTY and is
    // filled by discovery (ticket 008).
    root_dir:  string;
    cache_dir: string;
    // The typed dependency roots (spec 0087 decision 15): shared Git content
    // and the per-consumer resolution state, resolved once at startup from the
    // XDG contract. The workspace state carries the same values into the
    // dependency preparation seam.
    content_cache_dir: string;
    state_dir:         string;
    workspace: Workspace_State;
}

Command :: struct {
    name:               string;
    description:        string;
    usage:              string;
    // The selection/option surface of the command, rendered under the usage
    // line by `juice help <command>` and by the invalid-argument diagnostic.
    // Empty for commands that take no options (clean, version, help).
    flag_help:          string = "";
    prerequisites:      [] string;
    handler:            Command_Handler;
    validate_arguments: Command_Argument_Validator = command_accepts_no_arguments;
}

// The one usage rendering: the usage line, then the command's flag surface when
// it declares one. Both the help command and the argument guards print through
// here, so a documented option cannot drift from the accepted one.
print_command_usage :: (command: Command) {
    print("%\n", command.usage);
    if command.flag_help != "" print("%\n", command.flag_help);
}

command_accepts_no_arguments :: (arguments: [] string) -> bool {
    return arguments.count == 0;
}

command_arguments_are_valid :: (command: Command, arguments: [] string) -> bool {
    if command.validate_arguments(arguments) return true;
    print("[juice ERROR] Usage: ");
    print_command_usage(command);
    return false;
}
