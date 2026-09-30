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
    packages: [..] Package;
    array_add(*packages, root_package);

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
        array_add(*packages, member_package);
    }

    discovery.root_dir = copy_string(root_abs);
    discovery.has_package = true;
    discovery.root_package = root_package;
    discovery.member_packages = packages;
    return discovery, true;
}

Workspace_Phase :: enum {
    EMPTY;
    DISCOVERED;
    PREPARED;
}

Workspace_State :: struct {
    phase:     Workspace_Phase;
    discovery: Workspace_Discovery;
    prepared:  Prepared_Workspace;
}

ensure_workspace_discovered :: (
    driver: *Build_Driver,
    state: *Workspace_State,
    discover: #type (driver: *Build_Driver) -> (Workspace_Discovery, bool) = discover_workspace
) -> bool {
    if state.phase != .EMPTY return true;
    discovery, ok := discover(driver);
    if !ok || !discovery.has_package {
        if ok print("[juice ERROR] No package.jai found in current directory.\n");
        return false;
    }
    state.discovery = discovery;
    state.phase = .DISCOVERED;
    print("[juice] Package '%' (v%) discovered.\n", discovery.root_package.name, discovery.root_package.version);
    return true;
}

// Publish a prepared result only after every required step succeeds. A failed
// attempt leaves discovery reusable and exposes no partial prepared workspace.
prepare_workspace :: (
    driver: *Build_Driver,
    state: *Workspace_State,
    resolve: #type (pkg: Package) -> Artifact_Plan_Result = resolve_artifact_plans,
    prepare_dependencies: #type (driver: *Build_Driver, member_packages: [] Package) -> (bool) = resolve_and_fetch_dependencies
) -> bool {
    if state.phase == .PREPARED return true;
    if state.phase != .DISCOVERED || !state.discovery.has_package {
        print("[juice ERROR] Workspace discovery is required before preparation.\n");
        return false;
    }
    plans_result := resolve(state.discovery.root_package);
    if !plans_result.success {
        print("[juice ERROR] %\n", plans_result.error_message);
        return false;
    }
    prepared: Prepared_Workspace;
    prepared.discovery = state.discovery;
    prepared.artifact_plans = plans_result.plans;
    if prepared.artifact_plans.count > 0 {
        print("[juice] Preparing workspace dependencies...\n");
        if !prepare_dependencies(driver, state.discovery.member_packages) {
            print("[juice ERROR] Dependency resolution failed.\n");
            return false;
        }
        prepared.dependencies_prepared = true;
    }
    state.prepared = prepared;
    state.phase = .PREPARED;
    return true;
}

get_prepared_workspace :: (state: *Workspace_State) -> *Prepared_Workspace {
    if state.phase != .PREPARED return null;
    return *state.prepared;
}
