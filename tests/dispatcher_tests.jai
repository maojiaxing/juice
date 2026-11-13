#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// Dispatcher tests: registry validation (declaration legality, duplicate
// names, unknown prerequisites), the production registry contract, and the
// DFS planning/execution matrix (cycle, diamond dedup, argument handling,
// failure propagation). The recording handlers and the test registries
// live in test_support.jai.
// ---------------------------------------------------------------------------

test "Registry: the production registry validates" {
    expect(validate_registry(COMMAND_REGISTRY).success);
    expect(COMMAND_REGISTRY.count == 6);
}

test "Registry: the production declarations match the spec shape" {
    expected := Command.[BUILD_COMMAND, RUN_COMMAND, CLEAN_COMMAND, TEST_COMMAND, VERSION_COMMAND, HELP_COMMAND];
    for declaration, i: expected {
        registered := COMMAND_REGISTRY[i];
        expect(registered.name == declaration.name && registered.description == declaration.description);
        expect(registered.usage == declaration.usage);
        expect(registered.handler == declaration.handler);
        expect(registered.validate_arguments == declaration.validate_arguments);
        expect(registered.prerequisites.count == declaration.prerequisites.count);
        for prerequisite, j: declaration.prerequisites {
            expect(registered.prerequisites[j] == prerequisite);
        }
    }
    // The only prerequisite relation: run depends on build (spec section 4.3).
    expect(RUN_COMMAND.prerequisites.count == 1 && RUN_COMMAND.prerequisites[0] == "build");
    expect(BUILD_COMMAND.prerequisites.count == 0 && CLEAN_COMMAND.prerequisites.count == 0 && TEST_COMMAND.prerequisites.count == 0);
    expect(VERSION_COMMAND.prerequisites.count == 0 && HELP_COMMAND.prerequisites.count == 0);
}

test "Registry: a nameless declaration is rejected" {
    result := validate_registry(TEST_REGISTRY_INVALID_NAME);
    expect(!result.success && result.error == .INVALID_COMMAND);
}

test "Registry: a null handler is rejected" {
    result := validate_registry(TEST_REGISTRY_INVALID_HANDLER);
    expect(!result.success && result.error == .INVALID_COMMAND);
}

test "Registry: a duplicate command name is rejected" {
    result := validate_registry(TEST_REGISTRY_DUPLICATE);
    expect(!result.success && result.error == .DUPLICATE_COMMAND_NAME);
}

test "Registry: an unknown prerequisite is rejected" {
    result := validate_registry(TEST_REGISTRY_MISSING_PREREQ);
    expect(!result.success && result.error == .MISSING_PREREQUISITE);
}

test "Dispatch: an unknown command is rejected" {
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_SIMPLE, "missing", *ctx, string.[]);
    expect(!result.success && result.error == .UNKNOWN_COMMAND);
}

test "Dispatch: a cycle is rejected before any handler runs" {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_CYCLE, "a", *ctx, string.[]);
    expect(!result.success && result.error == .CYCLE_DETECTED && test_a_calls == 0 && test_b_calls == 0);
}

test "Dispatch: a diamond executes each command exactly once" {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_DIAMOND, "d", *ctx, string.[]);
    expect(result.success && test_a_calls == 1 && test_b_calls == 1 && test_c_calls == 1 && test_d_calls == 1);
}

test "Dispatch: invalid arguments are rejected before prerequisites" {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_ARGUMENTS, "strict", *ctx, string.["unexpected"]);
    expect(!result.success && result.error == .INVALID_ARGUMENTS && test_a_calls == 0 && test_b_calls == 0);
}

test "Dispatch: a prerequisite failure propagates" {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_FAILURE, "target", *ctx, string.[]);
    expect(!result.success && result.error == .PREREQUISITE_FAILED && test_fail_calls == 1 && test_b_calls == 0);
}

test "Dispatch: a handler failure is reported" {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_FAILURE, "failing", *ctx, string.[]);
    expect(!result.success && result.error == .HANDLER_FAILED && result.command == "failing" && test_fail_calls == 1);
}

test "Dispatch: only the requested command receives user arguments" {
    reset_dispatch_counters();
    ctx: Command_Context;
    result := dispatch_command(TEST_REGISTRY_DIAMOND, "d", *ctx, string.["one", "two"]);
    expect(result.success && test_a_calls == 1 && test_b_calls == 1 && test_c_calls == 1 && test_d_calls == 1);
    expect(test_a_arguments.count == 0 && test_b_arguments.count == 0 && test_c_arguments.count == 0);
    expect(test_d_arguments.count == 2 && test_d_arguments[0] == "one" && test_d_arguments[1] == "two");
}
