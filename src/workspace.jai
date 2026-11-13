#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

// The workspace layer: member validation at discovery and the
// EMPTY -> DISCOVERED -> PREPARED phase machine (spec section 4.5, old
// juice workspace.jai semantics). Discovery loads only manifests and
// validates member roots — it deliberately never fetches dependencies
// (preparation is a separate command prerequisite). Members are referenced
// only through declared DEP records: discovery loads every member's
// manifest (dependency declarations included) into the snapshot, and the
// dependency layer (ticket 009) links a member only when a package declares
// the DEP by name — an undeclared member directory is simply not a member.
//
// The Package face is consumed through the namespaced Juice binding
// (src/juice_module.jai); the load-bearing "Juice" module name constraint
// applies as in the manifest layer.

workspace_relative_path_is_valid :: (path: string) -> bool {
    if path == "" || path_is_absolute_portable(path) return false;
    if path_has_escape_component(path) return false;
    return true;
}

workspace_member_path :: (root_dir: string, relative_path: string) -> string {
    return path_slashes(tprint("%1/%2", root_dir, path_slashes(relative_path)));
}

workspace_path_already_seen :: (paths: [] string, candidate: string) -> bool {
    for path: paths {
        if paths_equal(path, candidate) return true;
    }
    return false;
}

// Discovery loads only manifests and validates member roots. It deliberately
// does not fetch dependencies; preparation is a separate command
// prerequisite. After the Build_Driver teardown, discovery takes only the
// two paths it owns.
//
// modules_dir is the seam-injected modules directory (ticket 007
// convention): the production default derives next to the running
// executable (path_safety.juice_modules_dir), the published modules
// directory otter lands every build — tests and the generated driver child
// inject that same published directory. The default kicks in for the
// two-argument production call shape.
discover_workspace :: (root_dir: string, cache_dir: string, modules_dir: string = "") -> Juice.Workspace_Discovery, bool {
    discovery: Juice.Workspace_Discovery;
    root_spelling_entry := inspect_path_entry(root_dir);
    if !root_spelling_entry.exists || !root_spelling_entry.is_directory || root_spelling_entry.is_symlink || root_spelling_entry.is_junction {
        print("[juice ERROR] Workspace root is not a safe real directory: %\n", root_dir);
        return discovery, false;
    }
    root_abs, root_ok := normalize_existing_path(root_dir);
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

    root_package, package_ok := load_package_manifest(cache_dir, root_abs, modules_dir);
    if !package_ok {
        print("[juice ERROR] Existing package.jai is invalid.\n");
        return discovery, false;
    }

    members: [..] string;
    array_add(*members, copy_string(root_abs));
    packages: [..] Juice.Package;
    array_add(*packages, root_package);

    // Only the root package's members list is iterated: a member's own
    // workspace.members declaration is silently ignored (pinned by the old
    // juice test_monorepo nested-member edge case).
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
        member_package, member_ok := load_package_manifest(cache_dir, member_abs, modules_dir);
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
    discovery: Juice.Workspace_Discovery;
    prepared:  Juice.Prepared_Workspace;
}

ensure_workspace_discovered :: (
    root_dir: string,
    cache_dir: string,
    state: *Workspace_State,
    discover: #type (root_dir: string, cache_dir: string, modules_dir: string) -> (Juice.Workspace_Discovery, bool) = discover_workspace
) -> bool {
    if state.phase != .EMPTY return true;
    discovery, ok := discover(root_dir, cache_dir, "");
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
// attempt leaves discovery reusable and exposes no partial prepared
// workspace. force_dependencies: Test must prepare dependencies even with no
// effective target (LIB) — its test program references dependencies through
// import shims; Build/Clean semantics are unchanged (0 plans still skip
// preparation).
//
// The resolve and prepare_dependencies seams keep the old juice shapes
// (#type (pkg: Package) -> Artifact_Plan_Result / #type (root_dir,
// cache_dir, member_packages: [] Package) -> bool) with their production
// defaults resolve_artifact_plans / resolve_and_fetch_dependencies
// (ticket 009's target.jai / dependency.jai — cross-file default references,
// the old juice workspace.jai:148 precedent; both #load after this file in
// main.jai).
prepare_workspace :: (
    root_dir: string,
    cache_dir: string,
    state: *Workspace_State,
    resolve: #type (pkg: Juice.Package) -> Artifact_Plan_Result = resolve_artifact_plans,
    prepare_dependencies: #type (root_dir: string, cache_dir: string, member_packages: [] Juice.Package) -> (bool) = resolve_and_fetch_dependencies,
    force_dependencies := false
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
    prepared: Juice.Prepared_Workspace;
    prepared.discovery = state.discovery;
    prepared.artifact_plans = plans_result.plans;
    prepared.package_type = plans_result.package_type;
    if prepared.artifact_plans.count > 0 || force_dependencies {
        print("[juice] Preparing workspace dependencies...\n");
        if !prepare_dependencies(root_dir, cache_dir, state.discovery.member_packages) {
            print("[juice ERROR] Dependency resolution failed.\n");
            return false;
        }
        prepared.dependencies_prepared = true;
    }
    state.prepared = prepared;
    state.phase = .PREPARED;
    return true;
}

get_prepared_workspace :: (state: *Workspace_State) -> *Juice.Prepared_Workspace {
    if state.phase != .PREPARED return null;
    return *state.prepared;
}

// Command-side preparation entry: one idempotent call chains the two phases
// — discovery then preparation — and hands back the prepared workspace
// (null = failure, already reported by the phase that failed). The phase
// machine makes repeats free: an already prepared state is returned
// untouched, so run's handler can call this after build's prerequisite run
// has prepared the state. The two phases stay injectable as internal seams
// for this module's own tests, mirroring prepare_workspace's production
// defaults. The command-specific guard is absorbed: the failure message
// names the concrete discovery/preparation error instead of a generic
// requirement.
ensure_workspace_prepared :: (
    root_dir: string,
    cache_dir: string,
    state: *Workspace_State,
    discover: #type (root_dir: string, cache_dir: string, modules_dir: string) -> (Juice.Workspace_Discovery, bool) = discover_workspace,
    resolve: #type (pkg: Juice.Package) -> Artifact_Plan_Result = resolve_artifact_plans,
    prepare_dependencies: #type (root_dir: string, cache_dir: string, member_packages: [] Juice.Package) -> (bool) = resolve_and_fetch_dependencies,
    force_dependencies := false
) -> *Juice.Prepared_Workspace {
    if state.phase == .PREPARED return *state.prepared;
    if !ensure_workspace_discovered(root_dir, cache_dir, state, discover) return null;
    if !prepare_workspace(root_dir, cache_dir, state, resolve, prepare_dependencies, force_dependencies) return null;
    return *state.prepared;
}
