#import "Basic";

// `juice update` (spec 0087 decisions 19 and 20): refresh the dependency
// resolution graph of the selected packages only — no compilation, no test
// execution and no build hook (decision 23: 更新不因解析插件来源而执行构建 hook).
//
// Offline is rejected before anything is resolved (decision 14: update 与
// offline 冲突): an update always contacts its Git sources, so a conflict is a
// usage error rather than an offline resolution attempt.
//
// The selected packages' complete direct/transitive graphs are resolved as one
// operation: a failure leaves the previous records untouched and fails the
// command (decision 15), and a member that resolved earlier is not rolled back.

UPDATE_COMMAND :: Command.{
    name          = "update",
    description   = "Refresh dependency resolution selections without compiling",
    usage         = "juice update",
    flag_help     = "  Selection: --workspace | -p/--package <name> | --package-path <dir>",
    prerequisites = string.[],
    handler       = update_command,
    validate_arguments = update_arguments_are_valid,
};

update_arguments_are_valid :: (arguments: [] string) -> bool {
    return command_selection_arguments_are_valid(arguments, 0, false);
}

update_command :: (command_context: *Command_Context, arguments: [] string) -> bool {
    flags, flags_ok := parse_command_flags(arguments, 0, false);
    if !flags_ok {
        print_command_usage(UPDATE_COMMAND);
        return false;
    }
    if flags.offline {
        print("[juice ERROR] update cannot run offline: an update always contacts the Git sources.\n");
        return false;
    }
    // The update resolves every selected package's graph, whether or not the
    // package declares a program.
    selection, selected := select_command_packages(command_context, flags, .UPDATE);
    if !selected return false;
    batch: Package_Batch;
    batch.operation = "update";
    batch.total = selection.packages.count;
    for selected_package, index: selection.packages {
        _, prepared_ok := prepare_command_package(command_context, selected_package);
        if !prepared_ok {
            package_batch_fail(*batch, *selection, index);
            package_batch_report_failure(*batch);
            return false;
        }
        array_add(*batch.completed, selected_package.relative_path);
    }
    print("[juice] Dependency resolution graph updated.\n");
    return true;
}
