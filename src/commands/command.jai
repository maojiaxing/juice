Command_Handler :: #type (ctx: *Command_Context, arguments: [] string) -> bool;
Command_Argument_Validator :: #type (arguments: [] string) -> bool;

Command_Context :: struct {
    driver:    *Build_Driver;
    workspace: Workspace_State;
}

Command :: struct {
    name:               string;
    description:        string;
    usage:              string;
    prerequisites:      [] string;
    visible:            bool = true;
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
