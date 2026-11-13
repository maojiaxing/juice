HELP_COMMAND :: Command.{
    name          = "help",
    description   = "Show command help",
    usage         = "juice help [command]",
    prerequisites = string.[],
    handler       = help_command,
    validate_arguments = help_arguments_are_valid,
};

help_arguments_are_valid :: (arguments: [] string) -> bool {
    return arguments.count <= 1;
}

// `juice help` renders the registry overview (the shared print_usage block
// the dispatcher's unknown-command path also uses); `juice help <command>`
// prints that command's usage line. Zero prerequisites, zero side effects —
// the command runs without a workspace and ignores the context.
help_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if !command_arguments_are_valid(HELP_COMMAND, arguments) return false;
    if arguments.count == 0 {
        print_usage(COMMAND_REGISTRY);
        return true;
    }
    cmd, found := find_command(COMMAND_REGISTRY, arguments[0]);
    if !found {
        print("[juice ERROR] Unknown command: '%'\n", arguments[0]);
        return false;
    }
    print("%\n", cmd.usage);
    return true;
}
