#import "Basic";
#import "Hash_Table";

#load "../src/commands/command.jai";

// Mock Build_Driver for testing
Build_Driver :: struct {
    root_dir:     string;
    packages_dir: string;
    bin_dir:      string;
    cache_dir:    string;
    data_dir:     string;
    config_dir:   string;
    member_paths: [..] string;
}

// Mock Package for testing
Package_Type :: enum { BINARY; LIBRARY; }
Package :: struct {
    name:    string;
    version: string;
}

// Test handlers
test_handler_a :: (ctx: *Command_Context, arguments: [] string) -> bool {
    print("[TEST] Handler A executed\n");
    return true;
}

test_handler_b :: (ctx: *Command_Context, arguments: [] string) -> bool {
    print("[TEST] Handler B executed\n");
    return true;
}

test_handler_c :: (ctx: *Command_Context, arguments: [] string) -> bool {
    print("[TEST] Handler C executed\n");
    return true;
}

test_handler_fail :: (ctx: *Command_Context, arguments: [] string) -> bool {
    print("[TEST] Handler FAIL executed\n");
    return false;
}

// Test registry configurations
TEST_REGISTRY_SIMPLE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], visible = true, handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.[], visible = true, handler = test_handler_b},
];

TEST_REGISTRY_WITH_DEPS :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], visible = true, handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.["a"], visible = true, handler = test_handler_b},
    .{name = "c", description = "Command C", usage = "test c", prerequisites = string.["b"], visible = true, handler = test_handler_c},
];

TEST_REGISTRY_DIAMOND :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], visible = true, handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.["a"], visible = true, handler = test_handler_b},
    .{name = "c", description = "Command C", usage = "test c", prerequisites = string.["a"], visible = true, handler = test_handler_c},
    .{name = "d", description = "Command D", usage = "test d", prerequisites = string.["b", "c"], visible = true, handler = test_handler_a},
];

TEST_REGISTRY_DUPLICATE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], visible = true, handler = test_handler_a},
    .{name = "a", description = "Command A Duplicate", usage = "test a", prerequisites = string.[], visible = true, handler = test_handler_b},
];

TEST_REGISTRY_MISSING_PREREQ :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.["nonexistent"], visible = true, handler = test_handler_a},
];

TEST_REGISTRY_CYCLE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.["b"], visible = true, handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.["a"], visible = true, handler = test_handler_b},
];

TEST_REGISTRY_INTERNAL :: Command.[
    .{name = "internal", description = "Internal Command", usage = "test internal", prerequisites = string.[], visible = false, handler = test_handler_a},
    .{name = "public", description = "Public Command", usage = "test public", prerequisites = string.["internal"], visible = true, handler = test_handler_b},
];

TEST_REGISTRY_PREREQ_FAILS :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], visible = true, handler = test_handler_fail},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.["a"], visible = true, handler = test_handler_b},
];

// Validation test functions
validate_registry_test :: (registry: [] Command) -> bool {
    // Check for duplicate names
    for cmd, i: registry {
        for other, j: registry {
            if i == j continue;
            if cmd.name == other.name {
                print("[TEST ERROR] Duplicate command name: '%'\n", cmd.name);
                return false;
            }
        }
    }

    // Check for missing prerequisites
    for cmd: registry {
        for prereq_name: cmd.prerequisites {
            found := false;
            for other: registry {
                if other.name == prereq_name {
                    found = true;
                    break;
                }
            }
            if !found {
                print("[TEST ERROR] Command '%' has unknown prerequisite: '%'\n", cmd.name, prereq_name);
                return false;
            }
        }
    }

    return true;
}

find_command_test :: (registry: [] Command, name: string, visible_only := false) -> *Command, bool {
    for * cmd: registry {
        if cmd.name == name {
            if visible_only && !cmd.visible return null, false;
            return cmd, true;
        }
    }
    return null, false;
}

run_test :: (name: string, test_proc: () -> bool) {
    print("\n=== Test: % ===\n", name);
    result := test_proc();
    if result {
        print("[PASS] %\n", name);
    } else {
        print("[FAIL] %\n", name);
    }
}

test_simple_registry :: () -> bool {
    print("Testing simple registry validation...\n");
    return validate_registry_test(TEST_REGISTRY_SIMPLE);
}

test_duplicate_detection :: () -> bool {
    print("Testing duplicate command detection...\n");
    result := validate_registry_test(TEST_REGISTRY_DUPLICATE);
    return !result; // Should fail validation
}

test_missing_prerequisite :: () -> bool {
    print("Testing missing prerequisite detection...\n");
    result := validate_registry_test(TEST_REGISTRY_MISSING_PREREQ);
    return !result; // Should fail validation
}

test_visible_command_lookup :: () -> bool {
    print("Testing visible command lookup...\n");
    cmd, found := find_command_test(TEST_REGISTRY_INTERNAL, "public", visible_only = true);
    if !found || cmd.name != "public" {
        print("Failed to find visible command\n");
        return false;
    }

    internal_cmd, internal_found := find_command_test(TEST_REGISTRY_INTERNAL, "internal", visible_only = true);
    if internal_found {
        print("Internal command should not be visible\n");
        return false;
    }

    return true;
}

test_internal_command_available :: () -> bool {
    print("Testing internal command is available without visibility filter...\n");
    cmd, found := find_command_test(TEST_REGISTRY_INTERNAL, "internal", visible_only = false);
    return found && cmd.name == "internal";
}

main :: () {
    print("\n╔═══════════════════════════════════╗\n");
    print("║  Juice Dispatcher Test Suite     ║\n");
    print("╚═══════════════════════════════════╝\n");

    run_test("Simple registry validation", test_simple_registry);
    run_test("Duplicate command detection", test_duplicate_detection);
    run_test("Missing prerequisite detection", test_missing_prerequisite);
    run_test("Visible command lookup", test_visible_command_lookup);
    run_test("Internal command availability", test_internal_command_available);

    print("\n=== Test Suite Complete ===\n");
}
