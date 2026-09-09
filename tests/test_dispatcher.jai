#import "Basic";
#import "Hash_Table";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
#import "System";
#import "Juice";

#load "../src/xdg.jai";
#load "../src/path_safety.jai";
#load "../src/manifest.jai";
#load "../src/workspace.jai";
#load "../src/target.jai";
#load "../src/dependency.jai";
#load "../src/builder.jai";
#load "../src/commands/command.jai";
#load "../src/commands/prepare.jai";
#load "../src/commands/build.jai";
#load "../src/commands/run.jai";
#load "../src/commands/clean.jai";
#load "../src/commands/registry.jai";
#load "../src/dispatcher.jai";

// Test handlers are independent of the production registry.
test_handler_a :: (ctx: *Command_Context, arguments: [] string) -> bool {
    return true;
}

test_handler_b :: (ctx: *Command_Context, arguments: [] string) -> bool {
    return true;
}

test_handler_c :: (ctx: *Command_Context, arguments: [] string) -> bool {
    return true;
}

test_handler_fail :: (ctx: *Command_Context, arguments: [] string) -> bool {
    return false;
}

TEST_REGISTRY_SIMPLE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], visible = true, handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.[], visible = true, handler = test_handler_b},
];

TEST_REGISTRY_DUPLICATE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], visible = true, handler = test_handler_a},
    .{name = "a", description = "Command A Duplicate", usage = "test a", prerequisites = string.[], visible = true, handler = test_handler_b},
];

TEST_REGISTRY_MISSING_PREREQ :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.["nonexistent"], visible = true, handler = test_handler_a},
];

TEST_REGISTRY_INTERNAL :: Command.[
    .{name = "internal", description = "Internal Command", usage = "test internal", prerequisites = string.[], visible = false, handler = test_handler_a},
    .{name = "public", description = "Public Command", usage = "test public", prerequisites = string.["internal"], visible = true, handler = test_handler_b},
];

validate_registry_test :: (registry: [] Command) -> bool {
    for cmd, i: registry {
        for other, j: registry {
            if i == j continue;
            if cmd.name == other.name return false;
        }
    }
    for cmd: registry {
        for prereq_name: cmd.prerequisites {
            found := false;
            for other: registry {
                if other.name == prereq_name {
                    found = true;
                    break;
                }
            }
            if !found return false;
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

run_test :: (name: string, test_proc: () -> bool) -> bool {
    result := test_proc();
    if result print("[PASS] %\n", name);
    else print("[FAIL] %\n", name);
    return result;
}

test_simple_registry :: () -> bool {
    return validate_registry_test(TEST_REGISTRY_SIMPLE);
}

test_duplicate_detection :: () -> bool {
    return !validate_registry_test(TEST_REGISTRY_DUPLICATE);
}

test_missing_prerequisite :: () -> bool {
    return !validate_registry_test(TEST_REGISTRY_MISSING_PREREQ);
}

test_visible_command_lookup :: () -> bool {
    cmd, found := find_command_test(TEST_REGISTRY_INTERNAL, "public", visible_only = true);
    if !found || cmd.name != "public" return false;
    internal_cmd, internal_found := find_command_test(TEST_REGISTRY_INTERNAL, "internal", visible_only = true);
    return !internal_found && internal_cmd == null;
}

test_internal_command_available :: () -> bool {
    cmd, found := find_command_test(TEST_REGISTRY_INTERNAL, "internal", visible_only = false);
    return found && cmd.name == "internal";
}

test_manifest_protocol :: () -> bool {
    valid := parse_manifest_data_strict("NAME=demo\nVERSION=1\nTYPE=1\nTARGET=app|src/main.jai\n");
    if !valid.success || valid.package.targets.count != 1 return false;
    if valid.package.targets[0].name != "app" return false;

    unknown := parse_manifest_data_strict("NAME=demo\nVERSION=1\nNOPE=x\n");
    if unknown.success return false;
    malformed := parse_manifest_data_strict("TARGET=app|src/main.jai|result\n");
    return !malformed.success;
}

test_selection :: () -> bool {
    plans := Artifact_Plan.[
        .{target = .{name = "alpha"}, result_dir = "root/result", artifact_path = "root/result/alpha.exe"},
        .{target = .{name = "demo"}, result_dir = "root/result", artifact_path = "root/result/demo.exe"},
    ];
    selected, found := select_artifact_plan(plans, "demo", "");
    if !found || selected.target.name != "demo" return false;
    selected, found = select_artifact_plan(plans, "demo", "alpha");
    if !found || selected.target.name != "alpha" return false;
    _, found = select_artifact_plan(plans, "demo", "Alpha");
    return !found;
}

main :: () {
    all_ok := true;
    all_ok = run_test("Simple registry validation", test_simple_registry) && all_ok;
    all_ok = run_test("Duplicate command detection", test_duplicate_detection) && all_ok;
    all_ok = run_test("Missing prerequisite detection", test_missing_prerequisite) && all_ok;
    all_ok = run_test("Visible command lookup", test_visible_command_lookup) && all_ok;
    all_ok = run_test("Internal command availability", test_internal_command_available) && all_ok;
    all_ok = run_test("Strict manifest protocol", test_manifest_protocol) && all_ok;
    all_ok = run_test("Case-sensitive target selection", test_selection) && all_ok;
    if !all_ok exit(1);
}
