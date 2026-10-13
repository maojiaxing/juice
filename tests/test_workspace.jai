#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import "Juice";
#import "Testing";

// 共享声明（discovery/resolution/dependency 记录 fake、记录全局与
// shim_content_for helper）位于 src/test_support.jai（组织决议 0027），
// 测试程序程序级共享。

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

// test_fake_fetch/test_fake_link_member 与记录全局见 src/test_support.jai。

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
// （shim_content_for 见 src/test_support.jai）。

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
