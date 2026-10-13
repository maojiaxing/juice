#import "Juice";
#import "Testing";

// 共享声明（记录 handler、TEST_REGISTRY_* 常量与 reset_dispatch_counters）
// 位于 src/test_support.jai（组织决议 0027），测试程序程序级共享。

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
