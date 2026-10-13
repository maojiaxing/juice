#import "Hash_Table";
#import "Testing";

Dispatch_Error :: enum {
    NONE;
    UNKNOWN_COMMAND;
    INTERNAL_COMMAND_INVOKED;
    DUPLICATE_COMMAND_NAME;
    MISSING_PREREQUISITE;
    INVALID_COMMAND;
    INVALID_ARGUMENTS;
    CYCLE_DETECTED;
    PREREQUISITE_FAILED;
    HANDLER_FAILED;
}

Dispatch_Result :: struct {
    success: bool;
    error:   Dispatch_Error;
    command: string;
}

Dispatch_State :: enum {
    UNVISITED;
    VISITING;
    COMPLETED;
}

find_command :: (registry: [] Command, name: string, visible_only := false) -> *Command, bool {
    for * cmd: registry {
        if cmd.name == name {
            if visible_only && !cmd.visible return null, false;
            return cmd, true;
        }
    }
    return null, false;
}

validate_registry :: (registry: [] Command) -> Dispatch_Result {
    for cmd, i: registry {
        if cmd.name == "" || cmd.handler == null || cmd.validate_arguments == null {
            print("[juice ERROR] Invalid command declaration: '%'\n", cmd.name);
            return .{error = .INVALID_COMMAND, command = cmd.name};
        }
        for other, j: registry {
            if i == j continue;
            if cmd.name == other.name {
                print("[juice ERROR] Duplicate command name in registry: '%'\n", cmd.name);
                return .{error = .DUPLICATE_COMMAND_NAME, command = cmd.name};
            }
        }
    }
    for cmd: registry {
        for prerequisite: cmd.prerequisites {
            _, found := find_command(registry, prerequisite);
            if !found {
                print("[juice ERROR] Command '%' has unknown prerequisite: '%'\n", cmd.name, prerequisite);
                return .{error = .MISSING_PREREQUISITE, command = cmd.name};
            }
        }
    }
    return .{success = true};
}

// Build and validate the complete selected graph before invoking any handler.
// Prerequisites always receive empty arguments; only the requested command
// receives the user's arguments.
plan_command :: (
    registry: [] Command,
    cmd: *Command,
    arguments: [] string,
    states: *Table(string, Dispatch_State),
    ordered: *[..] Command
) -> Dispatch_Result {
    state, exists := table_find(states, cmd.name);
    if exists {
        if state == .VISITING {
            print("[juice ERROR] Cycle detected involving command: '%'\n", cmd.name);
            return .{error = .CYCLE_DETECTED, command = cmd.name};
        }
        if state == .COMPLETED return .{success = true};
    }
    if !command_arguments_are_valid(cmd.*, arguments) {
        return .{error = .INVALID_ARGUMENTS, command = cmd.name};
    }
    table_set(states, cmd.name, .VISITING);
    for prerequisite: cmd.prerequisites {
        prerequisite_cmd, found := find_command(registry, prerequisite);
        if !found return .{error = .MISSING_PREREQUISITE, command = cmd.name};
        result := plan_command(registry, prerequisite_cmd, string.[], states, ordered);
        if !result.success return result;
    }
    table_set(states, cmd.name, .COMPLETED);
    array_add(ordered, cmd.*);
    return .{success = true};
}

dispatch_command :: (registry: [] Command, command_name: string, ctx: *Command_Context, arguments: [] string) -> Dispatch_Result {
    validation := validate_registry(registry);
    if !validation.success return validation;

    cmd, found := find_command(registry, command_name);
    if !found {
        print("[juice ERROR] Unknown command: '%'\n", command_name);
        print_usage(registry);
        return .{error = .UNKNOWN_COMMAND, command = command_name};
    }
    if !cmd.visible {
        print("[juice ERROR] Internal command cannot be invoked directly: '%'\n", command_name);
        return .{error = .INTERNAL_COMMAND_INVOKED, command = command_name};
    }

    states: Table(string, Dispatch_State);
    defer deinit(*states);
    ordered: [..] Command;
    defer array_free(ordered);
    planning := plan_command(registry, cmd, arguments, *states, *ordered);
    if !planning.success return planning;

    for command: ordered {
        command_arguments := ifx command.name == command_name then arguments else string.[];
        if !command.handler(ctx, command_arguments) {
            error := ifx command.name == command_name then Dispatch_Error.HANDLER_FAILED else Dispatch_Error.PREREQUISITE_FAILED;
            print("[juice ERROR] Command '%' failed while executing '%'.\n", command.name, command_name);
            return .{error = error, command = command.name};
        }
    }
    return .{success = true};
}

print_usage :: (registry: [] Command) {
    print("Usage: juice [command] [args]\n\n");
    print("Available commands:\n");
    for cmd: registry {
        if !cmd.visible continue;
        print("  %-12  %\n", cmd.name, cmd.description);
    }
}

// ---------------------------------------------------------------------------
// 内联测试（票 0034 迁移自 tests/test_dispatcher.jai）：registry 校验、查
// 找、循环检测、菱形去重、参数预检与失败传播（含 manifest 严格协议与
// target 大小写选择两块的归属按映射表整文件迁入）。共享 helper（记录
// handler、TEST_REGISTRY_* 常量与 reset_dispatch_counters）见
// src/test_support.jai。
// ---------------------------------------------------------------------------

test "Production registry validation" {
    expect(validate_registry(COMMAND_REGISTRY).success);
}

test "Duplicate command detection" {
    result := validate_registry(TEST_REGISTRY_DUPLICATE);
    expect(!result.success && result.error == .DUPLICATE_COMMAND_NAME);
}

test "Missing prerequisite detection" {
    result := validate_registry(TEST_REGISTRY_MISSING_PREREQ);
    expect(!result.success && result.error == .MISSING_PREREQUISITE);
}

test "Unknown command rejected" {
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_SIMPLE, "missing", *ctx, string.[]);
    expect(!result.success && result.error == .UNKNOWN_COMMAND);
}

test "Internal command rejected for direct invocation" {
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_INTERNAL, "internal", *ctx, string.[]);
    expect(!result.success && result.error == .INTERNAL_COMMAND_INVOKED);
}

test "Internal command runs as prerequisite" {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_INTERNAL, "public", *ctx, string.[]);
    expect(result.success && test_a_calls == 1 && test_b_calls == 1);
}

test "Cycle rejected before execution" {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_CYCLE, "a", *ctx, string.[]);
    expect(!result.success && result.error == .CYCLE_DETECTED && test_a_calls == 0 && test_b_calls == 0);
}

test "Diamond executes each command once" {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_DIAMOND, "d", *ctx, string.[]);
    expect(result.success && test_a_calls == 1 && test_b_calls == 1 && test_c_calls == 1 && test_d_calls == 1);
}

test "Invalid arguments rejected before prerequisites" {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_ARGUMENTS, "strict", *ctx, string.["unexpected"]);
    expect(!result.success && result.error == .INVALID_ARGUMENTS && test_a_calls == 0 && test_b_calls == 0);
}

test "Prerequisite failure propagates" {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_FAILURE, "target", *ctx, string.[]);
    expect(!result.success && result.error == .PREREQUISITE_FAILED && test_fail_calls == 1 && test_b_calls == 0);
}

test "Handler failure reported" {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_FAILURE, "failing", *ctx, string.[]);
    expect(!result.success && result.error == .HANDLER_FAILED && result.command == "failing" && test_fail_calls == 1);
}

test "Strict manifest protocol" {
    valid := parse_manifest_data_strict("NAME=demo\nVERSION=1\nTYPE=1\nTARGET=app|src/main.jai\n");
    expect(valid.success && valid.package.targets.count == 1);
    expect(valid.package.targets[0].name == "app");

    unknown := parse_manifest_data_strict("NAME=demo\nVERSION=1\nNOPE=x\n");
    expect(!unknown.success);
    malformed := parse_manifest_data_strict("TARGET=app|src/main.jai|result\n");
    expect(!malformed.success);
}

test "Case-sensitive target selection" {
    plans := Artifact_Plan.[
        .{target = .{name = "alpha"}, target_dir = "root/target", artifact_path = "root/target/alpha.exe"},
        .{target = .{name = "demo"}, target_dir = "root/target", artifact_path = "root/target/demo.exe"},
    ];
    selected, found := select_artifact_plan(plans, "demo", "");
    expect(found && selected.target.name == "demo");
    selected, found = select_artifact_plan(plans, "demo", "alpha");
    expect(found && selected.target.name == "alpha");
    _, found = select_artifact_plan(plans, "demo", "Alpha");
    expect(!found);
}
