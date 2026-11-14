
COMMAND_REGISTRY :: Command.[
    BUILD_COMMAND,
    RUN_COMMAND,
    CLEAN_COMMAND,
    TEST_COMMAND,
    UPDATE_COMMAND,
    VERSION_COMMAND,
    HELP_COMMAND,
];

// The one resolution flag commands understand in this stage: --offline forces
// the OFFLINE resolution mode (spec 0087 decision 14). Package/workspace
// selection flags belong to ticket 0093. Any other flag-shaped argument is
// rejected so a typo cannot silently change resolution semantics.
// Argument validation for commands that take only resolution flags and an
// optional positional argument. The dispatcher validates before the handler,
// so the flag must be accepted here as well as stripped there.
resolution_flag_arguments_are_valid :: (arguments: [] string, max_positional: int) -> bool {
    positionals := 0;
    for argument: arguments {
        if argument == "--offline" continue;
        if starts_with(argument, "--") return false;
        positionals += 1;
    }
    return positionals <= max_positional;
}

build_arguments_are_valid :: (arguments: [] string) -> bool {
    return resolution_flag_arguments_are_valid(arguments, 0);
}

split_offline_flag :: (arguments: [] string) -> (mode: Resolution_Mode, remaining: [..] string, rejected: bool) {
    mode := Resolution_Mode.NORMAL;
    remaining: [..] string;
    for argument: arguments {
        if argument == "--offline" {
            mode = .OFFLINE;
            continue;
        }
        if starts_with(argument, "--") return mode, remaining, true;
        array_add(*remaining, argument);
    }
    return mode, remaining, false;
}

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
    prerequisites:      [] string;
    handler:            Command_Handler;
    validate_arguments: Command_Argument_Validator = command_accepts_no_arguments;
}

command_accepts_no_arguments :: (arguments: [] string) -> bool {
    return arguments.count == 0;
}

command_arguments_are_valid :: (command: Command, arguments: [] string) -> bool {
    if command.validate_arguments(arguments) return true;
    print("[juice ERROR] Usage: %\n", command.usage);
    return false;
}
