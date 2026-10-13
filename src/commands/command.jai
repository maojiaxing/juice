Command_Handler :: #type (ctx: *Command_Context, arguments: [] string) -> bool;
Command_Argument_Validator :: #type (arguments: [] string) -> bool;

Command_Context :: struct {
    // The two process-wide paths (票 0038：Build_Driver 拆解后仅存此二值；
    // packages_dir 等派生路径由各自持有者推导)：package root（启动时的
    // 工作目录）与 juice 缓存目录（XDG cache home 下）。
    root_dir:  string;
    cache_dir: string;
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
