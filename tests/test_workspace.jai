test_discovery_attempts: s64 = 0;
test_fake_discovery_ok: bool = false;
test_fake_discovery: Workspace_Discovery;

test_fake_discover :: (driver: *Build_Driver) -> Workspace_Discovery, bool {
    test_discovery_attempts += 1;
    return test_fake_discovery, test_fake_discovery_ok;
}

test_plan_resolution_success: bool = false;
test_resolved_plans: [] Artifact_Plan;
test_dependency_attempts: s64 = 0;
test_dependency_ok: bool = false;
test_dependency_snapshot: [] Package;

test_fake_resolve :: (pkg: Package) -> Artifact_Plan_Result {
    if !test_plan_resolution_success return .{success = false, error_message = copy_string("resolution failure")};
    return .{success = true, plans = test_resolved_plans};
}

test_fake_prepare_dependencies :: (driver: *Build_Driver, member_packages: [] Package) -> bool {
    test_dependency_attempts += 1;
    test_dependency_snapshot = member_packages;
    return test_dependency_ok;
}

reset_preparation_test :: () {
    test_discovery_attempts = 0;
    test_fake_discovery_ok = false;
    test_fake_discovery = .{};
    test_plan_resolution_success = false;
    test_resolved_plans = Artifact_Plan.[];
    test_dependency_attempts = 0;
    test_dependency_ok = false;
    test_dependency_snapshot = Package.[];
}

test_discovery_publishes_state_once :: () -> bool {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    driver: Build_Driver;
    state: Workspace_State;
    if !ensure_workspace_discovered(*driver, *state, test_fake_discover) return false;
    if state.phase != .DISCOVERED || test_discovery_attempts != 1 return false;
    if !ensure_workspace_discovered(*driver, *state, test_fake_discover) return false;
    return state.phase == .DISCOVERED && test_discovery_attempts == 1;
}

test_discovery_without_package_stays_empty :: () -> bool {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = false;
    driver: Build_Driver;
    state: Workspace_State;
    if ensure_workspace_discovered(*driver, *state, test_fake_discover) return false;
    return state.phase == .EMPTY && test_discovery_attempts == 1;
}

test_preparation_without_targets_skips_dependencies :: () -> bool {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    test_plan_resolution_success = true;
    test_resolved_plans = Artifact_Plan.[];
    driver: Build_Driver;
    state: Workspace_State;
    if !ensure_workspace_discovered(*driver, *state, test_fake_discover) return false;
    if !prepare_workspace(*driver, *state, test_fake_resolve, test_fake_prepare_dependencies) return false;
    if state.phase != .PREPARED || test_dependency_attempts != 0 return false;
    prepared := get_prepared_workspace(*state);
    return prepared != null && !prepared.dependencies_prepared && prepared.artifact_plans.count == 0;
}

test_preparation_with_targets_prepares_dependencies :: () -> bool {
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
    if !ensure_workspace_discovered(*driver, *state, test_fake_discover) return false;
    if !prepare_workspace(*driver, *state, test_fake_resolve, test_fake_prepare_dependencies) return false;
    if state.phase != .PREPARED || test_dependency_attempts != 1 return false;
    if test_dependency_snapshot.count != 2 || test_dependency_snapshot[1].name != "member" return false;
    prepared := get_prepared_workspace(*state);
    return prepared != null && prepared.dependencies_prepared;
}

test_resolution_failure_publishes_nothing :: () -> bool {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    test_plan_resolution_success = false;
    driver: Build_Driver;
    state: Workspace_State;
    if !ensure_workspace_discovered(*driver, *state, test_fake_discover) return false;
    if prepare_workspace(*driver, *state, test_fake_resolve, test_fake_prepare_dependencies) return false;
    if state.phase != .DISCOVERED || get_prepared_workspace(*state) != null return false;
    test_plan_resolution_success = true;
    test_resolved_plans = Artifact_Plan.[];
    return prepare_workspace(*driver, *state, test_fake_resolve, test_fake_prepare_dependencies) && state.phase == .PREPARED;
}

test_dependency_failure_publishes_nothing :: () -> bool {
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
    if !ensure_workspace_discovered(*driver, *state, test_fake_discover) return false;
    if prepare_workspace(*driver, *state, test_fake_resolve, test_fake_prepare_dependencies) return false;
    return state.phase == .DISCOVERED && test_dependency_attempts == 1 && get_prepared_workspace(*state) == null;
}

test_preparation_requires_discovery :: () -> bool {
    reset_preparation_test();
    driver: Build_Driver;
    state: Workspace_State;
    if prepare_workspace(*driver, *state, test_fake_resolve, test_fake_prepare_dependencies) return false;
    return state.phase == .EMPTY && test_dependency_attempts == 0;
}

test_fetched_dependency_names: [..] string;
test_fetch_result: bool = false;

test_fake_fetch :: (driver: *Build_Driver, dep: Dependency) -> bool {
    array_add(*test_fetched_dependency_names, copy_string(dep.name));
    return test_fetch_result;
}

test_member_dependencies_are_not_fetched :: () -> bool {
    array_reset(*test_fetched_dependency_names);
    test_fetch_result = true;
    packages := Package.[
        .{name = "root", dependencies = Dependency.[.{name = "member-lib"}, .{name = "external"}]},
        .{name = "member-lib", dependencies = Dependency.[.{name = "external2"}]},
    ];
    if !fetch_workspace_dependencies(null, packages, test_fake_fetch) return false;
    return test_fetched_dependency_names.count == 2
        && test_fetched_dependency_names[0] == "external"
        && test_fetched_dependency_names[1] == "external2";
}

test_fetch_failure_propagates :: () -> bool {
    array_reset(*test_fetched_dependency_names);
    test_fetch_result = false;
    packages := Package.[.{name = "root", dependencies = Dependency.[.{name = "external"}]}];
    if fetch_workspace_dependencies(null, packages, test_fake_fetch) return false;
    return test_fetched_dependency_names.count == 1;
}
