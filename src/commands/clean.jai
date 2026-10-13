#import "Basic";
#import "File_Utilities";
#import "Juice";
#import "Testing";

CLEAN_COMMAND :: Command.{
    name          = "clean",
    description   = "Remove Juice outputs and local dependency links",
    usage         = "juice clean",
    prerequisites = string.[],
    visible       = true,
    handler       = clean_command,
};

clean_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if !command_arguments_are_valid(CLEAN_COMMAND, arguments) return false;

    discovery, ok := discover_workspace(ctx.driver);
    if !ok {
        print("[juice ERROR] Clean discovery failed; no files were deleted.\n");
        return false;
    }
    return clean_discovered_workspace(ctx.driver, discovery);
}

clean_path_is_safe :: (path: string) -> bool {
    entry := inspect_path_entry(path);
    if !entry.exists return true;
    if entry.is_symlink || entry.is_junction {
        print("[juice ERROR] Refusing to delete symlink/junction: %\n", path);
        return false;
    }
    return entry.is_directory;
}

clean_discovered_workspace :: (
    driver: *Build_Driver,
    discovery: Workspace_Discovery,
    validate_path: #type (path: string) -> bool = clean_path_is_safe,
    delete_path: #type (path: string) -> bool = delete_directory_full
) -> bool {
    paths: [..] string;
    paths.allocator = temp;

    // Clean deletes the whole target/ directory of the root package and every
    // validated workspace member. Legacy result/ and .packages directories are
    // no longer managed and are never touched.
    if discovery.has_package {
        for member: discovery.member_packages {
            array_add(*paths, tprint("%1/target", member.dir));
        }
    } else {
        array_add(*paths, tprint("%1/target", driver.root_dir));
    }

    // Validate every deletion target before deleting any of them.
    for path: paths {
        if !validate_path(path) return false;
    }

    print("[juice Clean] Cleaning output directories...\n");
    all_ok := true;
    for path: paths {
        if !delete_path(path) {
            print("[juice ERROR] Could not delete: %\n", path);
            all_ok = false;
        }
    }
    if all_ok print("[juice Clean] Workspace cleaned.\n");
    return all_ok;
}

// ---------------------------------------------------------------------------
// 内联测试（票 0034 自旧 tests/ 迁移）：Clean 的范围校验与
// 先验证后删除的编排。共享 helper（test_clean_* 记录全局与
// reset_clean_test）见 tests/test_support.jai。
// ---------------------------------------------------------------------------

test "Clean validates workspace scope before deletion" {
    driver: Build_Driver;
    driver.root_dir = "unused-driver-root";
    discovery: Workspace_Discovery;
    discovery.has_package = true;
    discovery.root_dir = "root";
    discovery.member_packages = Package.[.{name = "root", dir = "root"}, .{name = "member", dir = "root/member"}];
    reset_clean_test(2);
    expect(clean_discovered_workspace(*driver, discovery, test_validate_clean_path, test_delete_clean_path));
    expect(!test_clean_deleted_too_early && test_clean_deleted.count == 2);
    expect(test_clean_deleted[0] == "root/target" && test_clean_deleted[1] == "root/member/target");
}

test "Clean without a manifest uses the current root" {
    driver: Build_Driver;
    driver.root_dir = "root";
    discovery: Workspace_Discovery;
    reset_clean_test(1);
    expect(clean_discovered_workspace(*driver, discovery, test_validate_clean_path, test_delete_clean_path));
    expect(!test_clean_deleted_too_early && test_clean_deleted.count == 1);
    expect(test_clean_deleted[0] == "root/target");
}

test "Unsafe Clean path prevents every deletion" {
    driver: Build_Driver;
    discovery: Workspace_Discovery;
    discovery.has_package = true;
    discovery.root_dir = "root";
    discovery.member_packages = Package.[.{name = "root", dir = "root"}, .{name = "member", dir = "root/member"}];
    reset_clean_test(2);
    test_clean_invalid_path = "root/member/target";
    expect(!clean_discovered_workspace(*driver, discovery, test_validate_clean_path, test_delete_clean_path));
    expect(test_clean_validated.count == 2 && test_clean_deleted.count == 0);
}

test "Clean continues after a deletion fails" {
    driver: Build_Driver;
    discovery: Workspace_Discovery;
    discovery.has_package = true;
    discovery.root_dir = "root";
    discovery.member_packages = Package.[.{name = "root", dir = "root"}, .{name = "member", dir = "root/member"}];
    reset_clean_test(2);
    test_clean_failed_delete = "root/target";
    expect(!clean_discovered_workspace(*driver, discovery, test_validate_clean_path, test_delete_clean_path));
    expect(!test_clean_deleted_too_early && test_clean_deleted.count == 2);
    expect(test_clean_deleted[0] == "root/target" && test_clean_deleted[1] == "root/member/target");
}
