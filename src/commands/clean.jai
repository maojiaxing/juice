#import "Basic";
#import "File_Utilities";
#import "Juice";

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

    if discovery.has_package {
        for member: discovery.member_packages {
            array_add(*paths, tprint("%1/result", member.dir));
        }
        array_add(*paths, tprint("%1/.packages", discovery.root_dir));
    } else {
        array_add(*paths, tprint("%1/result", driver.root_dir));
        array_add(*paths, tprint("%1/.packages", driver.root_dir));
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
