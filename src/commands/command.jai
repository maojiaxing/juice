Command_Handler :: #type (ctx: *Command_Context, arguments: [] string) -> bool;
Command_Argument_Validator :: #type (arguments: [] string) -> bool;

Command_Context :: struct {
    // The two process-wide paths (the only survivors of the Build_Driver
    // teardown; derived paths like packages_dir are derived by their own
    // owners): the package root (the working directory at startup) and the
    // juice cache directory (under the XDG cache home).
    root_dir:  string;
    cache_dir: string;
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
