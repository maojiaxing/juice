#import "Testing";

COMMAND_REGISTRY :: Command.[
    DISCOVER_WORKSPACE_COMMAND,
    PREPARE_WORKSPACE_COMMAND,
    BUILD_COMMAND,
    RUN_COMMAND,
    CLEAN_COMMAND,
    TEST_COMMAND,
];

// ---------------------------------------------------------------------------
// 内联测试（票 0034 自旧 tests/ 迁移）：生产 registry 聚合与
// 命令声明/参数守卫。共享 helper 见 tests/test_support.jai。
// ---------------------------------------------------------------------------

test "Command-owned declarations in production registry" {
    expect(validate_registry(COMMAND_REGISTRY).success && COMMAND_REGISTRY.count == 6);
    expected := Command.[DISCOVER_WORKSPACE_COMMAND, PREPARE_WORKSPACE_COMMAND, BUILD_COMMAND, RUN_COMMAND, CLEAN_COMMAND, TEST_COMMAND];
    for declaration, i: expected {
        registered := COMMAND_REGISTRY[i];
        expect(registered.name == declaration.name && registered.description == declaration.description);
        expect(registered.usage == declaration.usage && registered.visible == declaration.visible);
        expect(registered.handler == declaration.handler);
        expect(registered.validate_arguments == declaration.validate_arguments);
        expect(registered.prerequisites.count == declaration.prerequisites.count);
        for prerequisite, j: declaration.prerequisites {
            expect(registered.prerequisites[j] == prerequisite);
        }
    }
    expect(!DISCOVER_WORKSPACE_COMMAND.visible && !PREPARE_WORKSPACE_COMMAND.visible);
    expect(BUILD_COMMAND.visible && RUN_COMMAND.visible && CLEAN_COMMAND.visible && TEST_COMMAND.visible);
    expect(RUN_COMMAND.prerequisites.count == 1 && RUN_COMMAND.prerequisites[0] == "build");
    expect(BUILD_COMMAND.prerequisites.count == 1 && BUILD_COMMAND.prerequisites[0] == "prepare-workspace");
    expect(PREPARE_WORKSPACE_COMMAND.prerequisites.count == 1 && PREPARE_WORKSPACE_COMMAND.prerequisites[0] == "discover-workspace");
    expect(DISCOVER_WORKSPACE_COMMAND.prerequisites.count == 0 && CLEAN_COMMAND.prerequisites.count == 0);
}

test "Command argument and preparation guards" {
    // Null driver makes an accidental operation after argument rejection visible.
    ctx: Command_Context;
    expect(!BUILD_COMMAND.handler(*ctx, string.["unexpected"]));
    expect(!RUN_COMMAND.handler(*ctx, string.["one", "two"]));
    expect(!CLEAN_COMMAND.handler(*ctx, string.["unexpected"]));
    expect(!DISCOVER_WORKSPACE_COMMAND.handler(*ctx, string.["unexpected"]));
    expect(!PREPARE_WORKSPACE_COMMAND.handler(*ctx, string.["unexpected"]));
    expect(!BUILD_COMMAND.handler(*ctx, string.[]));
    expect(!RUN_COMMAND.handler(*ctx, string.[]));
}
