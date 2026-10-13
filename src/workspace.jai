#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import "Juice";
#import "Testing";

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
    prepared.package_type = plans_result.package_type;
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

// Command-side guard over the prepared workspace (票 0037): prints the
// command-specific preparation error and returns null on failure; callers
// treat null as the command's own failure. get_prepared_workspace stays the
// raw state accessor for tests.
require_prepared_workspace :: (name: string, state: *Workspace_State) -> *Prepared_Workspace {
    prepared := get_prepared_workspace(state);
    if prepared == null {
        print("[juice ERROR] Command '%' requires workspace preparation.\n", name);
    }
    return prepared;
}

// ---------------------------------------------------------------------------
// 内联测试（票 0034 自旧 tests/ 迁移）：workspace 状态机、
// 依赖快照消费与 import shim。共享 helper（discovery/resolution/dependency
// 记录 fake 与记录全局、shim_content_for）见 tests/test_support.jai。
// ---------------------------------------------------------------------------

test "Discovery publishes workspace state once" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    driver: Build_Driver;
    state: Workspace_State;
    expect(ensure_workspace_discovered(*driver, *state, test_fake_discover));
    expect(state.phase == .DISCOVERED && test_discovery_attempts == 1);
    expect(ensure_workspace_discovered(*driver, *state, test_fake_discover));
    expect(state.phase == .DISCOVERED && test_discovery_attempts == 1);
}

test "Discovery without a package stays empty" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = false;
    driver: Build_Driver;
    state: Workspace_State;
    expect(!ensure_workspace_discovered(*driver, *state, test_fake_discover));
    expect(state.phase == .EMPTY && test_discovery_attempts == 1);
}

test "Preparation without targets skips dependencies" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    test_plan_resolution_success = true;
    test_resolved_plans = Artifact_Plan.[];
    driver: Build_Driver;
    state: Workspace_State;
    expect(ensure_workspace_discovered(*driver, *state, test_fake_discover));
    expect(prepare_workspace(*driver, *state, test_fake_resolve, test_fake_prepare_dependencies));
    expect(state.phase == .PREPARED && test_dependency_attempts == 0);
    prepared := get_prepared_workspace(*state);
    expect(prepared != null && !prepared.dependencies_prepared && prepared.artifact_plans.count == 0);
}

test "Preparation with targets prepares dependencies" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    test_fake_discovery.member_packages = Package.[.{name = "root", dir = "root"}, .{name = "member", dir = "root/member"}];
    test_plan_resolution_success = true;
    test_resolved_plans = Artifact_Plan.[.{target = .{name = "demo"}}];
    test_dependency_ok = true;
    driver: Build_Driver;
    state: Workspace_State;
    expect(ensure_workspace_discovered(*driver, *state, test_fake_discover));
    expect(prepare_workspace(*driver, *state, test_fake_resolve, test_fake_prepare_dependencies));
    expect(state.phase == .PREPARED && test_dependency_attempts == 1);
    expect(test_dependency_snapshot.count == 2 && test_dependency_snapshot[1].name == "member");
    prepared := get_prepared_workspace(*state);
    expect(prepared != null && prepared.dependencies_prepared);
}

test "Resolution failure publishes no prepared workspace" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    test_plan_resolution_success = false;
    driver: Build_Driver;
    state: Workspace_State;
    expect(ensure_workspace_discovered(*driver, *state, test_fake_discover));
    expect(!prepare_workspace(*driver, *state, test_fake_resolve, test_fake_prepare_dependencies));
    expect(state.phase == .DISCOVERED && get_prepared_workspace(*state) == null);
    test_plan_resolution_success = true;
    test_resolved_plans = Artifact_Plan.[];
    expect(prepare_workspace(*driver, *state, test_fake_resolve, test_fake_prepare_dependencies) && state.phase == .PREPARED);
}

test "Dependency failure publishes no prepared workspace" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    test_plan_resolution_success = true;
    test_resolved_plans = Artifact_Plan.[.{target = .{name = "demo"}}];
    test_dependency_ok = false;
    driver: Build_Driver;
    state: Workspace_State;
    expect(ensure_workspace_discovered(*driver, *state, test_fake_discover));
    expect(!prepare_workspace(*driver, *state, test_fake_resolve, test_fake_prepare_dependencies));
    expect(state.phase == .DISCOVERED && test_dependency_attempts == 1 && get_prepared_workspace(*state) == null);
}

test "Preparation requires discovery" {
    reset_preparation_test();
    driver: Build_Driver;
    state: Workspace_State;
    expect(!prepare_workspace(*driver, *state, test_fake_resolve, test_fake_prepare_dependencies));
    expect(state.phase == .EMPTY && test_dependency_attempts == 0);
}

// Command-side guard（票 0037）：空状态打印共享报错并返回 null，已 prepared
// 状态原样交出结果——报错文案与旧的三处逐字守卫一致。
test "Prepared workspace guard fails on an empty state" {
    state: Workspace_State;
    expect(require_prepared_workspace("build", *state) == null);
}

test "Prepared workspace guard hands back the prepared result" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    test_plan_resolution_success = true;
    test_resolved_plans = Artifact_Plan.[];
    driver: Build_Driver;
    state: Workspace_State;
    expect(ensure_workspace_discovered(*driver, *state, test_fake_discover));
    expect(prepare_workspace(*driver, *state, test_fake_resolve, test_fake_prepare_dependencies));
    prepared := require_prepared_workspace("test", *state);
    expect(prepared != null && !prepared.dependencies_prepared && prepared.artifact_plans.count == 0);
}

// test_fake_fetch/test_fake_link_member 与记录全局见 tests/test_support.jai。

test "Workspace member dependencies are linked not fetched" {
    array_reset(*test_fetched_dependency_names);
    array_reset(*test_linked_member_names);
    test_fetch_result = true;
    test_link_result = true;
    packages := Package.[
        .{name = "root", dependencies = Dependency.[.{name = "member-lib"}, .{name = "external"}]},
        .{name = "member-lib", dependencies = Dependency.[.{name = "external2"}]},
    ];
    expect(fetch_workspace_dependencies(null, packages, test_fake_fetch, test_fake_link_member));
    expect(test_fetched_dependency_names.count == 2);
    expect(test_fetched_dependency_names[0] == "external" && test_fetched_dependency_names[1] == "external2");
    expect(test_linked_member_names.count == 1 && test_linked_member_names[0] == "member-lib");
}

test "Member link failure propagates" {
    array_reset(*test_fetched_dependency_names);
    array_reset(*test_linked_member_names);
    test_fetch_result = true;
    test_link_result = false;
    packages := Package.[
        .{name = "root", dependencies = Dependency.[.{name = "member-lib"}, .{name = "external"}]},
        .{name = "member-lib"},
    ];
    expect(!fetch_workspace_dependencies(null, packages, test_fake_fetch, test_fake_link_member));
    expect(test_linked_member_names.count == 1 && test_fetched_dependency_names.count == 0);
}

test "Dependency fetch failure propagates" {
    array_reset(*test_fetched_dependency_names);
    array_reset(*test_linked_member_names);
    test_fetch_result = false;
    test_link_result = true;
    packages := Package.[.{name = "root", dependencies = Dependency.[.{name = "external"}]}];
    expect(!fetch_workspace_dependencies(null, packages, test_fake_fetch, test_fake_link_member));
    expect(test_fetched_dependency_names.count == 1);
}

// Consumers resolve "#import <name>" through a generated shim in the
// dependency directory; the shim loads the dependency's real entry by path,
// so any source directory name and any of the three layouts work
// （shim_content_for 见 tests/test_support.jai）。

test "Import shim generated for a src/module.jai entry" {
    packages_dir := tprint("%1/tests/data/shim-fixture/packages-src", juice_root());
    delete_directory_full(packages_dir);
    make_directory_if_it_does_not_exist(packages_dir, recursive = true);
    defer delete_directory_full(packages_dir);
    expect(ensure_import_shim(packages_dir, "shim-pkg", tprint("%1/tests/data/shim-fixture/shim-pkg", juice_root())));
    content, ok := shim_content_for(packages_dir, "shim-pkg");
    expect(ok);
    expect(contains(content, "#load ") && contains(content, "src/module.jai\";"));
}

test "Import shim generated for a single-file layout" {
    packages_dir := tprint("%1/tests/data/shim-fixture/packages-file", juice_root());
    delete_directory_full(packages_dir);
    make_directory_if_it_does_not_exist(packages_dir, recursive = true);
    defer delete_directory_full(packages_dir);
    expect(ensure_import_shim(packages_dir, "file-pkg", tprint("%1/tests/data/shim-fixture/file-pkg", juice_root())));
    content, ok := shim_content_for(packages_dir, "file-pkg");
    expect(ok);
    expect(contains(content, "#load ") && contains(content, "file-pkg.jai\";"));
}

test "Import shim generated for a root module.jai entry" {
    packages_dir := tprint("%1/tests/data/shim-fixture/packages-root", juice_root());
    delete_directory_full(packages_dir);
    make_directory_if_it_does_not_exist(packages_dir, recursive = true);
    defer delete_directory_full(packages_dir);
    expect(ensure_import_shim(packages_dir, "root-pkg", tprint("%1/tests/data/shim-fixture/root-pkg", juice_root())));
    content, ok := shim_content_for(packages_dir, "root-pkg");
    expect(ok);
    expect(contains(content, "#load ") && contains(content, "module.jai\";"));
}

test "Import shim skipped without any layout" {
    packages_dir := tprint("%1/tests/data/shim-fixture/packages-none", juice_root());
    delete_directory_full(packages_dir);
    make_directory_if_it_does_not_exist(packages_dir, recursive = true);
    defer delete_directory_full(packages_dir);
    expect(ensure_import_shim(packages_dir, "empty-pkg", tprint("%1/tests/data/shim-fixture/empty-pkg", juice_root())));
    _, shim_written := shim_content_for(packages_dir, "empty-pkg");
    expect(!shim_written);
}
