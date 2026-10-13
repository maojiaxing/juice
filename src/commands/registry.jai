#import "Testing";

COMMAND_REGISTRY :: Command.[
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
    expect(validate_registry(COMMAND_REGISTRY).success && COMMAND_REGISTRY.count == 4);
    expected := Command.[BUILD_COMMAND, RUN_COMMAND, CLEAN_COMMAND, TEST_COMMAND];
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
    expect(RUN_COMMAND.prerequisites.count == 1 && RUN_COMMAND.prerequisites[0] == "build");
    expect(BUILD_COMMAND.prerequisites.count == 0 && CLEAN_COMMAND.prerequisites.count == 0 && TEST_COMMAND.prerequisites.count == 0);
}

test "Command argument guards" {
    // Null driver makes an accidental operation after argument rejection visible.
    ctx: Command_Context;
    expect(!BUILD_COMMAND.handler(*ctx, string.["unexpected"]));
    expect(!RUN_COMMAND.handler(*ctx, string.["one", "two"]));
    expect(!CLEAN_COMMAND.handler(*ctx, string.["unexpected"]));
    expect(!TEST_COMMAND.handler(*ctx, string.["one", "two"]));
}
