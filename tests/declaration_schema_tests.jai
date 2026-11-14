#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";

// A real declaration evaluated by the installed CLI. A deliberately invalid
// conventional entry must remain unused when both product lists are empty.
declaration_schema_explicit_empty_disables_discovery :: () {
    root := tprint("%/target/schema-empty", get_working_directory());
    expect(make_directory_if_it_does_not_exist(tprint("%/src", root), recursive = true));
    expect(write_entire_file(tprint("%/package.jai", root), "#import \"Juice\";\nPACKAGE :: Package.{name = \"empty\", version = \"1\", modules = .[], executables = .[]};\n"));
    expect(write_entire_file(tprint("%/src/main.jai", root), "this is deliberately invalid Jai\n"));
    result, output, errors := run_otter_child_at(root, string.["build"]);
    expect(result.exit_code == 0);
    expect(!file_exists(tprint("%/target/empty.exe", root)));
} @test

// Removed runtime fields must fail in the actual declaration compiler.
declaration_schema_rejects_runtime_dir :: () {
    root := tprint("%/target/schema-old-dir", get_working_directory());
    expect(make_directory_if_it_does_not_exist(tprint("%/src", root), recursive = true));
    expect(write_entire_file(tprint("%/src/main.jai", root), "main :: () {}\n"));
    expect(write_entire_file(tprint("%/package.jai", root), "#import \"Juice\";\nPACKAGE :: Package.{name = \"old\", version = \"1\", dir = \"elsewhere\"};\n"));
    result, output, errors := run_otter_child_at(root, string.["build"]);
    expect(result.exit_code != 0);
    expect(contains(output, "dir") || contains(errors, "dir"));
    expect(contains(output, "not a member of Package") || contains(errors, "not a member of Package"));
    expect(contains(output, "docs/migrations/package-declarations.md") || contains(errors, "docs/migrations/package-declarations.md"));
} @test

// The real test command must not execute built-in test-block when plugins is explicit-empty.
declaration_schema_explicit_empty_plugins_disable_test_block :: () {
    root := tprint("%/target/schema-disabled-plugin", get_working_directory());
    expect(make_directory_if_it_does_not_exist(tprint("%/src", root), recursive = true));
    expect(write_entire_file(tprint("%/package.jai", root), "#import \"Juice\";\nPACKAGE :: Package.{name = \"disabled\", version = \"1\", modules = .[], executables = .[], plugins = .[]};\n"));
    expect(write_entire_file(tprint("%/src/disabled.jai", root), "test \"schema-plugin-must-not-run\" { print(\"PLUGIN_RAN\"); }\n"));
    result, output, errors := run_otter_child_at(root, string.["test"]);
    // With test-block disabled, this extension syntax is rejected by Jai.
    expect(result.exit_code != 0);
    expect(contains(errors, "Semicolon expected after expression") || contains(output, "Semicolon expected after expression"));
    expect(!contains(output, "PLUGIN_RAN"));

    // An ordinary Jai file remains usable and contributes no tests.
    expect(write_entire_file(tprint("%/src/disabled.jai", root), "schema_disabled_marker :: 42;\n"));
    plain_result, plain_output, plain_errors := run_otter_child_at(root, string.["test"]);
    expect(plain_result.exit_code == 0);
    expect(contains(plain_output, "[juice Test] No tests found."));
    expect(!contains(plain_output, "PLUGIN_RAN"));
} @test

// A partially initialized row is data, not the complete omitted-list marker.
declaration_schema_rejects_partial_dependency_default :: () {
    root := tprint("%/target/schema-partial-dependency", get_working_directory());
    expect(make_directory_if_it_does_not_exist(root, recursive = true));
    expect(write_entire_file(tprint("%/package.jai", root), "#import \"Juice\";\nPACKAGE :: Package.{name = \"partial_dep\", version = \"1\", modules = .[], executables = .[], dependencies = .[.{source = .{path = \"payload\"}}]};\n"));
    result, output, errors := run_otter_child_at(root, string.["build"]);
    expect(result.exit_code != 0);
    expect(contains(output, "Invalid dependency source") || contains(errors, "Invalid dependency source"));
} @test

declaration_schema_rejects_partial_plugin_default :: () {
    root := tprint("%/target/schema-partial-plugin", get_working_directory());
    expect(make_directory_if_it_does_not_exist(root, recursive = true));
    expect(write_entire_file(tprint("%/package.jai", root), "#import \"Juice\";\nPACKAGE :: Package.{name = \"partial_plugin\", version = \"1\", modules = .[], executables = .[], plugins = .[.{source = .{path = \"payload\"}}]};\n"));
    result, output, errors := run_otter_child_at(root, string.["build"]);
    expect(result.exit_code != 0);
    expect(contains(output, "External plugin requires an explicit source") || contains(errors, "External plugin requires an explicit source"));
} @test

declaration_schema_rejects_empty_builtin_plugin_id :: () {
    root := tprint("%/target/schema-empty-plugin-id", get_working_directory());
    expect(make_directory_if_it_does_not_exist(root, recursive = true));
    expect(write_entire_file(tprint("%/package.jai", root), "#import \"Juice\";\nPACKAGE :: Package.{name = \"empty_id\", version = \"1\", modules = .[], executables = .[], plugins = .[.{id = \"\", builtin = \"load\"}]};\n"));
    result, output, errors := run_otter_child_at(root, string.["build"]);
    expect(result.exit_code != 0);
    expect(contains(output, "Plugin id cannot be empty") || contains(errors, "Plugin id cannot be empty"));
} @test

// Omitted lists discover the conventional module and executable independently.
declaration_schema_omitted_products_discover_both :: () {
    root := otter_scratch("schema-omitted-products");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(tprint("%/src", root), recursive = true));
    expect(write_entire_file(tprint("%/package.jai", root), "#import \"Juice\";\nPACKAGE :: Package.{name = \"discovered\", version = \"1\"};\n"));
    expect(write_entire_file(tprint("%/module.jai", root), "schema_value :: 17;\n"));
    expect(write_entire_file(tprint("%/src/main.jai", root), "#import \"Basic\";\nmain :: () { print(\"SCHEMA_DISCOVERED\\n\"); }\n"));
    result, output, errors := run_otter_child_at(root, string.["build"]);
    expect(expect_exit("schema-omitted-products", result, 0, "schema build"));
    package, loaded := load_package_manifest(tprint("%/target/manifest", root), root, plugin_face_modules_dir());
    expect(loaded);
    expect(package.modules_omitted && package.executables_omitted);
    products := resolve_effective_targets(package);
    expect(products.success);
    expect(products.modules.count == 1 && products.targets.count == 1);
    expect_eq("module.jai", products.modules[0].main_file);
    expect_eq("src/main.jai", products.targets[0].main_file);
    artifact := target_artifact_path(package_target_dir(root), "discovered");
    expect(file_exists(artifact));
    run_result, run_output, run_errors, _ := run_command(artifact, working_directory = root, capture_and_return_output = true);
    expect(run_result.exit_code == 0);
    expect(contains(run_output, "SCHEMA_DISCOVERED"));
} @test

// Multiple programs coexist with modules; a single nameless module uses the package name.
declaration_schema_module_and_multiple_programs :: () {
    root := otter_scratch("schema-multiple-products");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(tprint("%/src", root), recursive = true));
    expect(write_entire_file(tprint("%/package.jai", root), "#import \"Juice\";\nPACKAGE :: Package.{name = \"mixed\", version = \"1\", modules = .[.{entry = \"src/library.jai\"}], executables = .[.{name = \"alpha\", entry = \"src/alpha.jai\"}, .{name = \"beta\", entry = \"src/beta.jai\"}], default_run = \"beta\"};\n"));
    expect(write_entire_file(tprint("%/src/library.jai", root), "schema_value :: 23;\n"));
    expect(write_entire_file(tprint("%/src/alpha.jai", root), "#import \"Basic\";\nmain :: () { print(\"SCHEMA_ALPHA\\n\"); }\n"));
    expect(write_entire_file(tprint("%/src/beta.jai", root), "#import \"Basic\";\nmain :: () { print(\"SCHEMA_BETA\\n\"); }\n"));
    result, output, errors := run_otter_child_at(root, string.["build"]);
    expect(expect_exit("schema-multiple-products", result, 0, "schema build"));
    package, loaded := load_package_manifest(tprint("%/target/manifest", root), root, plugin_face_modules_dir());
    expect(loaded);
    expect(!package.modules_omitted && !package.executables_omitted);
    expect_eq("beta", package.default_run);
    products := resolve_effective_targets(package);
    expect(products.success);
    expect(products.modules.count == 1 && products.targets.count == 2);
    expect_eq("mixed", products.modules[0].name);
    for name: string.["alpha", "beta"] {
        artifact := target_artifact_path(package_target_dir(root), name);
        expect(file_exists(artifact));
        run_result, run_output, run_errors, _ := run_command(artifact, working_directory = root, capture_and_return_output = true);
        expect(run_result.exit_code == 0);
        marker := ifx name == "alpha" then "SCHEMA_ALPHA" else "SCHEMA_BETA";
        expect(contains(run_output, marker));
    }
    expect(!file_exists(target_artifact_path(package_target_dir(root), "mixed")));
} @test

// Workspace-only metadata must not synthesize a package from conventional files.
declaration_schema_pure_workspace_has_no_root_package :: () {
    root := otter_scratch("schema-pure-workspace");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(tprint("%/src", root), recursive = true));
    expect(write_entire_file(tprint("%/package.jai", root), "#import \"Juice\";\nPACKAGE :: Package.{workspace = .{}};\n"));
    expect(write_entire_file(tprint("%/src/main.jai", root), "deliberately invalid conventional entry\n"));
    result, output, errors := run_otter_child_at(root, string.["build"]);
    expect(expect_exit("schema-pure-workspace", result, 0, "schema build"));
    discovery, discovered := discover_workspace(root, tprint("%/target/manifest", root), plugin_face_modules_dir());
    expect(discovered);
    expect(discovery.has_declaration && discovery.has_workspace);
    expect(!discovery.has_package && !discovery.root_package.has_package);
    expect(discovery.member_packages.count == 0);
    expect(discovery.root_package.plugins.count == 0);
    products := resolve_effective_targets(discovery.root_package);
    expect(products.success && products.modules.count == 0 && products.targets.count == 0);
    expect(!contains(output, "Package '"));
} @test

// A package and workspace share one declaration without losing the root package.
declaration_schema_package_and_workspace_coexist :: () {
    root := otter_scratch("schema-package-workspace");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(tprint("%/src", root), recursive = true));
    expect(make_directory_if_it_does_not_exist(tprint("%/member", root), recursive = true));
    expect(write_entire_file(tprint("%/package.jai", root), "#import \"Juice\";\nPACKAGE :: Package.{name = \"container\", version = \"1\", workspace = .{members = .[\"member\"], default_members = .[\".\"]}};\n"));
    expect(write_entire_file(tprint("%/member/package.jai", root), "#import \"Juice\";\nPACKAGE :: Package.{name = \"member\", version = \"1\", modules = .[], executables = .[]};\n"));
    expect(write_entire_file(tprint("%/src/main.jai", root), "main :: () {}\n"));
    result, output, errors := run_otter_child_at(root, string.["build"]);
    expect(expect_exit("schema-package-workspace", result, 0, "schema build"));
    discovery, discovered := discover_workspace(root, tprint("%/target/manifest", root), plugin_face_modules_dir());
    expect(discovered);
    expect(discovery.has_declaration && discovery.has_workspace && discovery.has_package);
    expect(discovery.member_packages.count == 2);
    expect_eq("container", discovery.member_packages[0].name);
    expect_eq("member", discovery.member_packages[1].name);
    expect(!discovery.root_package.workspace.default_members_omitted);
    expect(discovery.root_package.workspace.default_members.count == 1);
    expect_eq(".", discovery.root_package.workspace.default_members[0]);
    expect(file_exists(target_artifact_path(package_target_dir(root), "container")));
} @test

// Compile-time code can set one nested field without replacing the workspace.
declaration_schema_computed_workspace_preserves_explicit_defaults :: () {
    root := otter_scratch("schema-computed-workspace");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(root, recursive = true));
    expect(write_entire_file(tprint("%/package.jai", root), "#import \"Juice\";\nmake_package :: () -> Package {\n    package: Package = .{name = \"computed\", version = \"1\", modules = .[], executables = .[]};\n    package.workspace.default_members = .[];\n    return package;\n}\nPACKAGE :: #run make_package();\n"));
    result, output, errors := run_otter_child_at(root, string.["build"]);
    expect(expect_exit("schema-computed-workspace", result, 0, "schema build"));
    discovery, discovered := discover_workspace(root, tprint("%/target/manifest", root), plugin_face_modules_dir());
    expect(discovered);
    expect(discovery.has_workspace && discovery.has_package);
    expect(!discovery.root_package.workspace.default_members_omitted);
    expect(discovery.root_package.workspace.default_members.count == 0);
    expect(discovery.root_package.workspace.members.count == 0);
} @test
