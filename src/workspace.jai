#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import "Juice";

workspace_relative_path_is_valid :: (path: string) -> bool {
    if path == "" || path_is_absolute_portable(path) return false;
    if path_has_escape_component(path) return false;
    return true;
}

workspace_member_path :: (root_dir: string, relative_path: string) -> string {
    return to_forward_slashes(tprint("%1/%2", root_dir, path_slashes(relative_path)));
}

workspace_path_already_seen :: (paths: [] string, candidate: string) -> bool {
    for path: paths {
        if paths_equal(path, candidate) return true;
    }
    return false;
}

// Discovery loads only manifests and validates member roots. It deliberately
// does not fetch dependencies; preparation is a separate command prerequisite.
discover_workspace :: (driver: *Build_Driver) -> Workspace_Discovery, bool {
    discovery: Workspace_Discovery;
    root_spelling_entry := inspect_path_entry(driver.root_dir);
    if !root_spelling_entry.exists || !root_spelling_entry.is_directory || root_spelling_entry.is_symlink || root_spelling_entry.is_junction {
        print("[juice ERROR] Workspace root is not a safe real directory: %\n", driver.root_dir);
        return discovery, false;
    }
    root_abs, root_ok := normalize_existing_path(driver.root_dir);
    if !root_ok {
        print("[juice ERROR] Current directory could not be normalized.\n");
        return discovery, false;
    }
    root_entry := inspect_path_entry(root_abs);
    if !root_entry.exists || !root_entry.is_directory || root_entry.is_symlink || root_entry.is_junction {
        print("[juice ERROR] Workspace root is not a safe real directory: %\n", root_abs);
        return discovery, false;
    }

    manifest_path := tprint("%1/package.jai", root_abs);
    if !file_exists(manifest_path) {
        return .{root_dir = root_abs, has_package = false}, true;
    }

    root_package, package_ok := load_package_manifest(driver, root_abs);
    if !package_ok {
        print("[juice ERROR] Existing package.jai is invalid.\n");
        return discovery, false;
    }

    members: [..] string;
    array_add(*members, copy_string(root_abs));

    for relative_path: root_package.workspace.members {
        if !workspace_relative_path_is_valid(relative_path) {
            print("[juice ERROR] Invalid workspace member path: %\n", relative_path);
            return discovery, false;
        }

        member_abs_spelling := workspace_member_path(root_abs, relative_path);
        member_abs, member_abs_ok := normalize_existing_path(member_abs_spelling);
        if !member_abs_ok {
            print("[juice ERROR] Workspace member directory does not exist: %\n", relative_path);
            return discovery, false;
        }
        member_entry := inspect_path_entry(member_abs);
        if !member_entry.exists || !member_entry.is_directory || member_entry.is_symlink || member_entry.is_junction {
            print("[juice ERROR] Workspace member is not a safe real directory: %\n", relative_path);
            return discovery, false;
        }
        if !path_is_within(root_abs, member_abs) {
            print("[juice ERROR] Workspace member escapes package root: %\n", relative_path);
            return discovery, false;
        }
        if workspace_path_already_seen(members, member_abs) {
            print("[juice ERROR] Duplicate workspace member path: %\n", relative_path);
            return discovery, false;
        }
        if !file_exists(tprint("%1/package.jai", member_abs)) {
            print("[juice ERROR] Workspace member lacks package.jai: %\n", member_abs);
            return discovery, false;
        }
        member_package, member_ok := load_package_manifest(driver, member_abs);
        if !member_ok {
            print("[juice ERROR] Workspace member manifest is invalid: %\n", member_abs);
            return discovery, false;
        }
        array_add(*members, copy_string(member_abs));
    }

    discovery.root_dir = copy_string(root_abs);
    discovery.has_package = true;
    discovery.root_package = root_package;
    discovery.member_paths = members;
    return discovery, true;
}

// Clean needs discovery but not preparation. The bool distinguishes an absent
// manifest (valid fallback) from an existing manifest that failed validation.
discover_workspace_for_clean :: (driver: *Build_Driver) -> Workspace_Discovery, bool {
    discovery, ok := discover_workspace(driver);
    return discovery, ok;
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

clean_discovered_workspace :: (driver: *Build_Driver, discovery: Workspace_Discovery) -> bool {
    paths: [..] string;
    paths.allocator = temp;

    if discovery.has_package {
        for member_path: discovery.member_paths {
            array_add(*paths, tprint("%1/result", member_path));
        }
        array_add(*paths, tprint("%1/.packages", discovery.root_dir));
    } else {
        array_add(*paths, tprint("%1/result", driver.root_dir));
        array_add(*paths, tprint("%1/.packages", driver.root_dir));
    }

    // Validate every deletion target before deleting any of them.
    for path: paths {
        if !clean_path_is_safe(path) return false;
    }

    print("[juice Clean] Cleaning output directories...\n");
    all_ok := true;
    for path: paths {
        if !delete_directory_full(path) {
            print("[juice ERROR] Could not delete: %\n", path);
            all_ok = false;
        }
    }
    if all_ok print("[juice Clean] Workspace cleaned.\n");
    return all_ok;
}
