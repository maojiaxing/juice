#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

// Workspace rules use normalized package-relative directories. A star matches
// within one path component; recursive and other glob syntax is unsupported.
workspace_relative_path_is_valid :: (path: string) -> bool {
    normalized := normalize_package_relative_path(path);
    if !normalized.success return false;
    for character: normalized.path {
        if character == #char "?" || character == #char "[" || character == #char "]" || character == #char "{" || character == #char "}" return false;
    }
    return find_index_from_left(normalized.path, "**") < 0;
}

workspace_component_matches :: (pattern: string, name: string) -> bool {
    pattern_index := 0;
    name_index := 0;
    star_index := -1;
    retry_index := 0;
    while name_index < name.count {
        if pattern_index < pattern.count && pattern[pattern_index] == #char "*" {
            star_index = pattern_index;
            pattern_index += 1;
            retry_index = name_index;
        } else if pattern_index < pattern.count && paths_equal(slice(pattern, pattern_index, 1), slice(name, name_index, 1)) {
            pattern_index += 1;
            name_index += 1;
        } else if star_index >= 0 {
            retry_index += 1;
            name_index = retry_index;
            pattern_index = star_index + 1;
        } else return false;
    }
    while pattern_index < pattern.count && pattern[pattern_index] == #char "*" pattern_index += 1;
    return pattern_index == pattern.count;
}

workspace_rule_excludes :: (rule: string, relative_path: string) -> bool {
    if rule == "." return true;
    pattern_parts := split(rule, "/");
    path_parts := split(relative_path, "/");
    if pattern_parts.count > path_parts.count return false;
    for part, index: pattern_parts {
        if !workspace_component_matches(part, path_parts[index]) return false;
    }
    return true;
}

expand_workspace_member :: (root_dir: string, rule: string) -> [] string, bool {
    paths: [..] string;
    array_add(*paths, copy_string(root_dir));
    normalized := normalize_package_relative_path(rule);
    if !workspace_relative_path_is_valid(rule) {
        print("[juice ERROR] Invalid workspace member path: %\n", rule);
        return .[], false;
    }
    if normalized.path != "." {
        for component: split(normalized.path, "/") {
            expanded: [..] string;
            for parent: paths {
                if find_index_from_left(component, "*") < 0 {
                    array_add(*expanded, copy_string(tprint("%/%", parent, component)));
                    continue;
                }
                if !path_chain_is_link_free(parent) {
                    print("[juice ERROR] Workspace member traverses a link: %\n", rule);
                    return .[], false;
                }
                Matches :: struct { pattern: string; paths: *[..] string; }
                matches: Matches = .{component, *expanded};
                collect :: (info: *File_Visit_Info, matches: *Matches) {
                    if info.is_directory && workspace_component_matches(matches.pattern, info.short_name) array_add(matches.paths, copy_string(info.full_name));
                }
                if path_exists_as_directory(parent) _ := visit_files(parent, false, *matches, collect, visit_files = false, visit_directories = true, visit_symlinks = true, follow_directory_symlinks = false);
            }
            paths = expanded;
        }
    }
    if paths.count == 0 {
        print("[juice ERROR] Workspace member pattern has no matching directories: %\n", rule);
        return .[], false;
    }
    for path: paths {
        entry := inspect_path_entry(path);
        if !entry.exists || !entry.is_directory {
            print("[juice ERROR] Workspace member is not a safe real directory: %\n", rule);
            return .[], false;
        }
    }
    return paths, true;
}

workspace_parent_directory :: (directory: string) -> string {
    if path_is_filesystem_root(directory) return "";
    parent := path_slashes(path_strip_filename(directory));
    while parent.count > 1 && ends_with(parent, "/") parent.count -= 1;
    #if OS == .WINDOWS {
        if parent.count == 2 && parent[1] == #char ":" parent = tprint("%/", parent);
    }
    if paths_equal(parent, directory) return "";
    return parent;
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

// Nearest-declaration lookup (spec 0087 decision 17): from the starting
// directory upward, the first directory holding a package.jai is the root a
// command operates on. The found declaration stays authoritative even when
// its contents are invalid - callers must report that failure instead of
// continuing to an outer package, so this returns the directory only, never
// a validity verdict. Returns "" when no ancestor declares a package, which
// leaves the caller on its original root (the manifest-less clean case).
locate_declaration_root :: (start_dir: string) -> string {
    if start_dir == "" return "";
    current, ok := normalize_existing_path(start_dir);
    if !ok return "";
    while current != "" {
        if inspect_path_entry(tprint("%/package.jai", current)).exists return current;
        if path_is_filesystem_root(current) return "";
        current = workspace_parent_directory(current);
    }
    return "";
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
discover_workspace :: (root_dir: string, cache_dir: string, modules_dir: string = "") -> Workspace_Discovery, bool {
    discovery: Workspace_Discovery;
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
    if root_package.has_package array_add(*members, copy_string(root_abs));
    packages: [..] Normalized_Package;
    if root_package.has_package array_add(*packages, root_package);

    excluded_rules: [..] string;
    for rule: root_package.workspace.exclude {
        if !workspace_relative_path_is_valid(rule) {
            print("[juice ERROR] Invalid workspace exclude path: %\n", rule);
            return discovery, false;
        }
        array_add(*excluded_rules, normalize_package_relative_path(rule).path);
    }
    candidates: [..] string;
    for rule: root_package.workspace.members {
        expanded, expanded_ok := expand_workspace_member(root_abs, rule);
        if !expanded_ok return discovery, false;
        for candidate: expanded {
            normalized, normalized_ok := normalize_existing_path(candidate);
            if !normalized_ok return discovery, false;
            if paths_equal(root_abs, normalized) && root_package.has_package continue;
            relative := ".";
            if !paths_equal(root_abs, normalized) relative = slice(normalized, root_abs.count + 1, normalized.count - root_abs.count - 1);
            excluded := false;
            for rule: excluded_rules if workspace_rule_excludes(rule, relative) excluded = true;
            if excluded continue;
            if !workspace_path_already_seen(candidates, normalized) array_add(*candidates, normalized);
        }
    }
    for member_abs: candidates {
        if !path_exists_as_directory(member_abs) || !path_chain_is_link_free(member_abs) || !path_is_within(root_abs, member_abs) {
            print("[juice ERROR] Workspace member is not a safe real directory: %\n", member_abs);
            return discovery, false;
        }
        if !file_exists(tprint("%/package.jai", member_abs)) {
            print("[juice ERROR] Workspace member lacks package.jai: %\n", member_abs);
            return discovery, false;
        }
        member_package, member_ok := load_package_manifest(cache_dir, member_abs, modules_dir);
        if !member_ok {
            print("[juice ERROR] Workspace member manifest is invalid: %\n", member_abs);
            return discovery, false;
        }
        if member_package.has_workspace && !paths_equal(root_abs, member_abs) {
            print("[juice ERROR] Nested workspace boundary: % (workspace.members).\n", member_abs);
            return discovery, false;
        }
        ancestor := workspace_parent_directory(member_abs);
        while ancestor != "" && path_is_within(root_abs, ancestor) && !paths_equal(root_abs, ancestor) {
            if inspect_path_entry(tprint("%/package.jai", ancestor)).exists {
                ancestor_package, ancestor_ok := load_package_manifest(cache_dir, ancestor, modules_dir);
                if !ancestor_ok return discovery, false;
                if ancestor_package.has_workspace {
                    print("[juice ERROR] Nested workspace boundary: % contains member % (workspace.members).\n", ancestor, member_abs);
                    return discovery, false;
                }
            }
            ancestor = workspace_parent_directory(ancestor);
        }
        if !member_package.has_package {
            print("[juice ERROR] Workspace member has no package: %\n", member_abs);
            return discovery, false;
        }
        array_add(*members, copy_string(member_abs));
        array_add(*packages, member_package);
    }

    discovery.root_dir = copy_string(root_abs);
    discovery.has_declaration = true;
    discovery.has_workspace = root_package.has_workspace;
    discovery.has_package = root_package.has_package;
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
    // The directory the command was invoked from (the nearest-declaration
    // lookup starts here, and the package selection's location default reads
    // it). Discovery keeps it so preparation can select packages without
    // consulting process-global state.
    invocation_dir: string;
    // The command's validated package selection (ticket 0093). Preparation
    // publishes it to the dependency resolution seam, so only the selected
    // packages' graphs are resolved. A zero value keeps the location default.
    selection: Package_Selection;
    // The explicit dependency resolution environment (content cache root,
    // state root and mode). The command layer fills it before preparation; it
    // is never derived from a global "current project".
    environment: Resolution_Environment;
}

ensure_workspace_discovered :: (
    root_dir: string,
    cache_dir: string,
    state: *Workspace_State,
    discover: #type (root_dir: string, cache_dir: string, modules_dir: string) -> (Workspace_Discovery, bool) = discover_workspace
) -> bool {
    if state.phase != .EMPTY return true;
    declaration_root := locate_declaration_root(root_dir);
    discovery, ok := discover(ifx declaration_root != "" then declaration_root else root_dir, cache_dir, "");
    if !ok || (!discovery.has_package && !discovery.has_workspace) {
        if ok print("[juice ERROR] No package.jai found in current directory.\n");
        return false;
    }
    state.discovery = discovery;
    state.phase = .DISCOVERED;
    state.invocation_dir = root_dir;
    if discovery.has_package {
        print("[juice] Package '%' (v%) discovered.\n", discovery.root_package.name, discovery.root_package.version);
    } else {
        print("[juice] Workspace '%' discovered.\n", discovery.root_dir);
    }
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
    resolve: #type (pkg: Normalized_Package) -> Artifact_Plan_Result = resolve_artifact_plans,
    prepare_dependencies: #type (request: Dependency_Preparation_Request) -> bool = resolve_dependencies_for_workspace,
    force_dependencies := false
) -> bool {
    if state.phase == .PREPARED return true;
    if state.phase != .DISCOVERED || (!state.discovery.has_package && !state.discovery.has_workspace) {
        print("[juice ERROR] Workspace discovery is required before preparation.\n");
        return false;
    }
    plans_result := resolve(state.discovery.root_package);
    if !plans_result.success {
        print("[juice ERROR] %\n", plans_result.error_message);
        return false;
    }
    prepared := Prepared_Workspace.{};
    prepared.discovery = state.discovery;
    prepared.environment = state.environment;
    prepared.artifact_plans = plans_result.plans;
    if prepared.artifact_plans.count > 0 || force_dependencies {
        print("[juice] Preparing workspace dependencies...\n");
        request := Dependency_Preparation_Request.{
            discovery      = state.discovery,
            invocation_dir = ifx state.invocation_dir != "" then state.invocation_dir else root_dir,
            cache_dir      = cache_dir,
            environment    = state.environment,
            selection      = state.selection,
        };
        if !prepare_dependencies(request) {
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
    discover: #type (root_dir: string, cache_dir: string, modules_dir: string) -> (Workspace_Discovery, bool) = discover_workspace,
    resolve: #type (pkg: Normalized_Package) -> Artifact_Plan_Result = resolve_artifact_plans,
    prepare_dependencies: #type (request: Dependency_Preparation_Request) -> bool = resolve_dependencies_for_workspace,
    force_dependencies := false
) -> *Prepared_Workspace {
    if state.phase == .PREPARED return *state.prepared;
    if !ensure_workspace_discovered(root_dir, cache_dir, state, discover) return null;
    if !prepare_workspace(root_dir, cache_dir, state, resolve, prepare_dependencies, force_dependencies) return null;
    return *state.prepared;
}

// Package selection (spec 0087 decisions 17 and 18): the one validated result
// every command consumes. It separates the workspace member set from the
// packages a command operates on, and fails before any command work when the
// request is contradictory, unknown or empty.

selection_failure :: (message: string) -> Package_Selection {
    return .{error = copy_string(message)};
}

// Workspace-relative directory of an absolute directory, "." for the root
// itself, "" when the directory is outside the root.
workspace_relative_directory :: (root_dir: string, directory: string) -> string {
    normalized_root, root_ok := normalize_existing_path(root_dir);
    if !root_ok return "";
    normalized_directory, directory_ok := normalize_existing_path(directory);
    if !directory_ok return "";
    if paths_equal(normalized_root, normalized_directory) return ".";
    if !path_is_within(normalized_root, normalized_directory) return "";
    return slice(normalized_directory, normalized_root.count + 1, normalized_directory.count - normalized_root.count - 1);
}

find_selected_package :: (packages: [] Normalized_Package, directory: string) -> *Normalized_Package {
    for *package: packages {
        if paths_equal(package.dir, directory) return package;
    }
    return null;
}

// Deepest member containing the working directory, or null when the directory
// is the workspace root itself or lies outside every member (a root-owned
// scratch directory keeps the root rules).
nearest_member_for_directory :: (discovery: Workspace_Discovery, cwd: string) -> *Normalized_Package {
    deepest: *Normalized_Package = null;
    for *package: discovery.member_packages {
        if !path_is_within(package.dir, cwd) continue;
        if deepest == null || package.dir.count > deepest.dir.count deepest = package;
    }
    return deepest;
}

append_selected_package :: (packages: *[..] Normalized_Package, paths: *[..] string, package: *Normalized_Package, paths_root: string) {
    if find_selected_package(packages.*, package.dir) != null return;
    array_add(packages, package.*);
    array_add(paths, copy_string(workspace_relative_directory(paths_root, package.dir)));
}

sort_selection_by_path :: (selection: *Package_Selection) {
    for i: 1..selection.packages.count-1 {
        if i >= selection.packages.count break;
        package_key := selection.packages[i];
        path_key := selection.paths[i];
        j := i - 1;
        while j >= 0 && compare(selection.paths[j], path_key) > 0 {
            selection.packages[j+1] = selection.packages[j];
            selection.paths[j+1] = selection.paths[j];
            j -= 1;
        }
        selection.packages[j+1] = package_key;
        selection.paths[j+1] = path_key;
    }
}

// Default selection at the workspace root. An explicit default_members list
// replaces the location default; the empty list means the root call has no
// default selection at all (decision 17).
select_root_defaults :: (discovery: Workspace_Discovery, packages: *[..] Normalized_Package, paths: *[..] string) -> Package_Selection {
    if discovery.has_workspace {
        if discovery.root_package.workspace.default_members_omitted {
            if discovery.has_package {
                append_selected_package(packages, paths, *discovery.root_package, discovery.root_dir);
                return .{success = true};
            }
            for *package: discovery.member_packages append_selected_package(packages, paths, package, discovery.root_dir);
            return .{success = true};
        }
        if discovery.root_package.workspace.default_members.count == 0 {
            return selection_failure("The workspace default member list is empty; no package was selected.");
        }
        for rule: discovery.root_package.workspace.default_members {
            normalized := normalize_package_relative_path(rule);
            if !normalized.success || !workspace_relative_path_is_valid(rule) || find_index_from_left(rule, "*") >= 0 {
                return selection_failure(tprint("Invalid default member directory: %", rule));
            }
            matched: *Normalized_Package = null;
            for *package: discovery.member_packages {
                if !paths_equal(workspace_relative_directory(discovery.root_dir, package.dir), normalized.path) continue;
                matched = package;
                break;
            }
            if matched == null return selection_failure(tprint("Default member is not a workspace member: %", rule));
            append_selected_package(packages, paths, matched, discovery.root_dir);
        }
        return .{success = true};
    }
    if !discovery.has_package return selection_failure("No package or workspace is available for selection.");
    append_selected_package(packages, paths, *discovery.root_package, discovery.root_dir);
    return .{success = true};
}

select_workspace_packages :: (discovery: Workspace_Discovery, cwd: string, request: Package_Selection_Request) -> Package_Selection {
    if request.all_members && (request.names.count > 0 || request.paths.count > 0) {
        return selection_failure("--workspace cannot be combined with --package or --package-path.");
    }
    packages: [..] Normalized_Package;
    paths: [..] string;

    if request.all_members {
        if !discovery.has_workspace || discovery.member_packages.count == 0 {
            return selection_failure("--workspace requires a workspace with at least one member package.");
        }
        for *package: discovery.member_packages append_selected_package(*packages, *paths, package, discovery.root_dir);
    } else if request.names.count > 0 || request.paths.count > 0 {
        for name: request.names {
            if !package_name_is_valid(name) return selection_failure(tprint("Invalid package name: %", name));
            matched: *Normalized_Package = null;
            matches := 0;
            for *package: discovery.member_packages {
                if !ascii_names_equal(package.name, name) continue;
                matched = package;
                matches += 1;
            }
            if matches == 0 return selection_failure(tprint("Unknown package name: %", name));
            if matches > 1 return selection_failure(tprint("Package name is ambiguous; select it by path: %", name));
            append_selected_package(*packages, *paths, matched, discovery.root_dir);
        }
        for path: request.paths {
            normalized := normalize_package_relative_path(path);
            if !normalized.success return selection_failure(tprint("Invalid package path: %", path));
            matched: *Normalized_Package = null;
            for *package: discovery.member_packages {
                if !paths_equal(workspace_relative_directory(discovery.root_dir, package.dir), normalized.path) continue;
                matched = package;
                break;
            }
            if matched == null return selection_failure(tprint("Package path is not a workspace member: %", path));
            append_selected_package(*packages, *paths, matched, discovery.root_dir);
        }
    } else {
        // Location defaults: inside a member only that member, at the root the
        // workspace's default members.
        nearest := nearest_member_for_directory(discovery, cwd);
        if nearest != null && !paths_equal(nearest.dir, discovery.root_dir) {
            append_selected_package(*packages, *paths, nearest, discovery.root_dir);
        } else {
            defaults := select_root_defaults(discovery, *packages, *paths);
            if !defaults.success return defaults;
        }
    }

    if packages.count == 0 return selection_failure("No package was selected.");
    selection := Package_Selection.{success = true, packages = packages, paths = paths};
    sort_selection_by_path(*selection);
    return selection;
}

// Cardinality gate for commands whose operation takes exactly one package
// (run). Filtering out packages without executables would guess the intent.
selection_selects_one_package :: (selection: Package_Selection) -> bool {
    return selection.success && selection.packages.count == 1;
}

