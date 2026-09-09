#import "Hash_Table";

// Command dispatcher: validates registry, resolves prerequisites, and executes commands

Dispatch_Error :: enum {
    NONE;
    UNKNOWN_COMMAND;
    INTERNAL_COMMAND_INVOKED;
    DUPLICATE_COMMAND_NAME;
    MISSING_PREREQUISITE;
    CYCLE_DETECTED;
    PREREQUISITE_FAILED;
    HANDLER_FAILED;
}

Dispatch_State :: enum {
    UNVISITED;
    VISITING;
    COMPLETED;
}

Execution_Record :: struct {
    state:   Dispatch_State;
    success: bool;
}

validate_registry :: () -> bool {
    // Check for duplicate names
    for cmd, i: COMMAND_REGISTRY {
        for other, j: COMMAND_REGISTRY {
            if i == j continue;
            if cmd.name == other.name {
                print("[juice ERROR] Duplicate command name in registry: '%'\n", cmd.name);
                return false;
            }
        }
    }

    // Check for missing prerequisites
    for cmd: COMMAND_REGISTRY {
        for prereq_name: cmd.prerequisites {
            found := false;
            for other: COMMAND_REGISTRY {
                if other.name == prereq_name {
                    found = true;
                    break;
                }
            }
            if !found {
                print("[juice ERROR] Command '%' has unknown prerequisite: '%'\n", cmd.name, prereq_name);
                return false;
            }
        }
    }

    return true;
}

find_command :: (name: string, visible_only := false) -> *Command, bool {
    for * cmd: COMMAND_REGISTRY {
        if cmd.name == name {
            if visible_only && !cmd.visible return null, false;
            return cmd, true;
        }
    }
    return null, false;
}

execute_with_prerequisites :: (
    cmd: *Command,
    ctx: *Command_Context,
    arguments: [] string,
    execution_map: *Table(string, Execution_Record)
) -> bool {
    record, exists := table_find(execution_map, cmd.name);

    if exists {
        if record.state == .VISITING {
            print("[juice ERROR] Cycle detected involving command: '%'\n", cmd.name);
            return false;
        }
        if record.state == .COMPLETED {
            return record.success;
        }
    }

    // Mark as visiting
    table_set(execution_map, cmd.name, .{state = .VISITING, success = false});

    // Execute prerequisites first
    for prereq_name: cmd.prerequisites {
        prereq_cmd, found := find_command(prereq_name);
        if !found {
            print("[juice ERROR] Prerequisite not found: '%'\n", prereq_name);
            return false;
        }

        if !execute_with_prerequisites(prereq_cmd, ctx, string.[], execution_map) {
            print("[juice ERROR] Prerequisite '%' failed for command '%'\n", prereq_name, cmd.name);
            table_set(execution_map, cmd.name, .{state = .COMPLETED, success = false});
            return false;
        }
    }

    // Execute this command
    success := cmd.handler(ctx, arguments);
    table_set(execution_map, cmd.name, .{state = .COMPLETED, success = success});

    return success;
}

dispatch_command :: (command_name: string, ctx: *Command_Context, arguments: [] string) -> bool {
    if !validate_registry() {
        return false;
    }

    cmd, found := find_command(command_name, visible_only = true);
    if !found {
        print("[juice ERROR] Unknown command: '%'\n", command_name);
        print_usage();
        return false;
    }

    execution_map: Table(string, Execution_Record);
    defer deinit(*execution_map);

    return execute_with_prerequisites(cmd, ctx, arguments, *execution_map);
}

print_usage :: () {
    print("Usage: juice [command] [args]\n\n");
    print("Available commands:\n");
    for cmd: COMMAND_REGISTRY {
        if !cmd.visible continue;
        print("  %-12  %\n", cmd.name, cmd.description);
    }
}
