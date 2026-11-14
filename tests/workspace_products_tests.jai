#import "Basic";
#import "Testing";
#import "File_Utilities";

workspace_products_overlap_cli :: () {
    root := otter_scratch("workspace-products-overlap");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", #string END
#import "Juice";
PACKAGE :: Package.{name = "root", version = "1", modules = .[], executables = .[],
    workspace = .{members = .[".", "members/*", "members/a/../a"], exclude = .["."]}};
END
    ));
    expect(build_seam_write(root, "members/a/package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"member\", version = \"1\", modules = .[], executables = .[]};\n"));
    result, output, errors := run_otter_child_at(root, .["clean"]);
    expect(expect_exit("workspace-overlap", result, 0));
    expect(output_matches("workspace-overlap", tprint("%\n%", output, errors), .["Workspace cleaned."]));
    discovery, discovered := discover_workspace(root, otter_scratch("workspace-products-cache"), plugin_face_modules_dir());
    expect(discovered && discovery.member_packages.count == 1);
    expect(discovery.member_packages[0].name == "root");
} @test

workspace_products_nested_boundary :: () {
    root := otter_scratch("workspace-products-nested");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"outer\", version = \"1\", workspace = .{members = .[\"nested/member\"]}};\n"));
    expect(build_seam_write(root, "nested/package.jai", "#import \"Juice\";\nPACKAGE :: Package.{workspace = .{members = .[\"member\"]}};\n"));
    expect(build_seam_write(root, "nested/member/package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"inner\", version = \"1\"};\n"));
    expect(build_seam_write(root, "target/keep.txt", "keep"));
    result, output, errors := run_otter_child_at(root, .["clean"]);
    expect(expect_exit("nested-boundary", result, 1));
    expect(output_matches("nested-boundary", tprint("%\n%", output, errors), .["Nested workspace boundary", "nested"]));
    expect(file_exists(tprint("%/target/keep.txt", root)));
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"outer\", version = \"1\", workspace = .{members = .[\"nested/member\"], exclude = .[\"nested\"]}};\n"));
    accepted, _, _ := run_otter_child_at(root, .["clean"]);
    expect(expect_exit("excluded-nested-boundary", accepted, 0));
} @test

workspace_products_nearest_declaration_cli :: () {
    root := otter_scratch("workspace-products-nearest");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"nearest\", version = \"1\", modules = .[], executables = .[], plugins = .[]};\n"));
    expect(build_seam_write(root, "src/deep/keep.txt", "keep"));
    result, output, errors := run_otter_child_at(tprint("%/src/deep", root), .["build"]);
    expect(expect_exit("nearest-from-subdirectory", result, 0));
    expect(output_matches("nearest-from-subdirectory", tprint("%\n%", output, errors), .["Package 'nearest'"]));

    expect(build_seam_write(root, "src/package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"invalid\"};\n"));
    invalid, invalid_output, invalid_errors := run_otter_child_at(tprint("%/src/deep", root), .["build"]);
    expect(expect_exit("nearest-invalid-stops", invalid, 1));
    expect(output_matches("nearest-invalid-stops", tprint("%\n%", invalid_output, invalid_errors), .["package.jai", "invalid"]));
    expect(find_index_from_left(invalid_output, "Package 'nearest'") < 0);
} @test

workspace_products_child_scan_boundary_cli :: () {
    root := otter_scratch("workspace-products-scan");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"parent\", version = \"1\", modules = .[], executables = .[]};\n"));
    expect(build_seam_write(root, "parent_test.jai", "#import \"Testing\";\nparent_boundary_test :: () { expect(true); } @test\n"));
    expect(build_seam_write(root, "unregistered/package.jai", "invalid child declaration must not be evaluated\n"));
    expect(build_seam_write(root, "unregistered/child_test.jai", "#import \"Testing\";\nchild_must_not_run :: () { expect(false); } @test\n"));
    expect(build_seam_write(root, "nested/package.jai", "#import \"Juice\";\nPACKAGE :: Package.{workspace = .{}};\n"));
    expect(build_seam_write(root, "nested/broken.jai", "This child source must never be compiled.\n"));
    result, output, errors := run_otter_child_at(root, .["test"]);
    expect(expect_exit("child-scan-boundary", result, 0));
    expect(output_matches("child-scan-boundary", tprint("%\n%", output, errors), .["parent_boundary_test", "1 passed, 0 failed"]));
    expect(find_index_from_left(output, "child_must_not_run") < 0);
} @test

workspace_products_selection_rules :: () {
    root := otter_scratch("workspace-products-selection");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"root\", version = \"1\", workspace = .{members = .[\"members/*\"]}};\n"));
    expect(build_seam_write(root, "members/alpha/package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"alpha\", version = \"1\"};\n"));
    expect(build_seam_write(root, "members/beta/package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"beta\", version = \"1\"};\n"));
    expect(build_seam_write(root, "members/beta/src/deep/keep.txt", "keep"));
    cache := otter_scratch("workspace-products-selection-cache");
    discovery, discovered := discover_workspace(root, cache, plugin_face_modules_dir());
    expect(discovered && discovery.member_packages.count == 3);

    // Inside a member, the location default is that member alone.
    inside := select_workspace_packages(discovery, tprint("%/members/beta/src/deep", root), .{});
    expect(inside.success && inside.packages.count == 1 && inside.packages[0].name == "beta");

    // At the root, the omitted default_members list selects the root package.
    at_root := select_workspace_packages(discovery, root, .{});
    expect(at_root.success && at_root.packages.count == 1 && at_root.packages[0].name == "root");

    all := select_workspace_packages(discovery, root, .{all_members = true});
    expect(all.success && all.packages.count == 3 && all.paths[0] == ".");
    expect(all.packages[1].name == "alpha" && all.packages[2].name == "beta");

    by_name := select_workspace_packages(discovery, root, .{names = .["beta"]});
    expect(by_name.success && by_name.packages.count == 1 && by_name.paths[0] == "members/beta");
    by_path := select_workspace_packages(discovery, root, .{paths = .["members/alpha", "members/beta/../beta"]});
    expect(by_path.success && by_path.packages.count == 2);
    expect(by_path.paths[0] == "members/alpha" && by_path.paths[1] == "members/beta");
    mixed := select_workspace_packages(discovery, root, .{names = .["alpha"], paths = .["members/alpha"]});
    expect(mixed.success && mixed.packages.count == 1);

    conflict := select_workspace_packages(discovery, root, .{all_members = true, names = .["alpha"]});
    expect(!conflict.success && find_index_from_left(conflict.error, "--workspace") >= 0);
    unknown := select_workspace_packages(discovery, root, .{names = .["missing"]});
    expect(!unknown.success && find_index_from_left(unknown.error, "Unknown package name") >= 0);
    foreign := select_workspace_packages(discovery, root, .{paths = .["elsewhere"]});
    expect(!foreign.success);
    expect(selection_selects_one_package(by_name) && !selection_selects_one_package(all));

    // An explicit empty default_members list means the root call has no default.
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"root\", version = \"1\", workspace = .{members = .[\"members/*\"], default_members = .[]}};\n"));
    empty_discovery, empty_ok := discover_workspace(root, cache, plugin_face_modules_dir());
    expect(empty_ok);
    none := select_workspace_packages(empty_discovery, root, .{});
    expect(!none.success && find_index_from_left(none.error, "no package was selected") >= 0);

    // An explicit default_members list replaces the location default.
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"root\", version = \"1\", workspace = .{members = .[\"members/*\"], default_members = .[\"members/alpha\"]}};\n"));
    explicit_discovery, explicit_ok := discover_workspace(root, cache, plugin_face_modules_dir());
    expect(explicit_ok);
    explicit := select_workspace_packages(explicit_discovery, root, .{});
    expect(explicit.success && explicit.packages.count == 1 && explicit.packages[0].name == "alpha");
} @test

workspace_products_strict_products :: () {
    root := otter_scratch("workspace-products-strict");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(tprint("%/src", root), recursive = true));
    expect(build_seam_write(root, "src/alpha.jai", "#import \"Basic\";\nmain :: () { print(\"A\\n\"); }\n"));
    expect(build_seam_write(root, "src/beta.jai", "#import \"Basic\";\nmain :: () { print(\"B\\n\"); }\n"));

    // A nameless item is only legal when it is the sole product.
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"strict\", version = \"1\", executables = .[.{entry = \"src/alpha.jai\"}, .{name = \"beta\", entry = \"src/beta.jai\"}]};\n"));
    unnamed, unnamed_output, unnamed_errors := run_otter_child_at(root, .["build"]);
    expect(expect_exit("strict-unnamed-item", unnamed, 1));
    expect(output_matches("strict-unnamed-item", tprint("%\n%", unnamed_output, unnamed_errors), .["must declare name"]));

    // Duplicate entries are rejected instead of silently collapsing.
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"strict\", version = \"1\", executables = .[.{name = \"alpha\", entry = \"src/alpha.jai\"}, .{name = \"beta\", entry = \"src/./alpha.jai\"}]};\n"));
    duplicate, duplicate_output, duplicate_errors := run_otter_child_at(root, .["build"]);
    expect(expect_exit("strict-duplicate-entry", duplicate, 1));
    expect(output_matches("strict-duplicate-entry", tprint("%\n%", duplicate_output, duplicate_errors), .["Duplicate product entry"]));

    // default_run must name a declared executable, not be guessed.
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"strict\", version = \"1\", executables = .[.{name = \"alpha\", entry = \"src/alpha.jai\"}], default_run = \"beta\"};\n"));
    bad_default, bad_output, bad_errors := run_otter_child_at(root, .["build"]);
    expect(expect_exit("strict-invalid-default-run", bad_default, 1));
    expect(output_matches("strict-invalid-default-run", tprint("%\n%", bad_output, bad_errors), .["default_run"]));

    // Both automatic module candidates existing is an ambiguity, not a pick.
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"strict\", version = \"1\", executables = .[]};\n"));
    expect(build_seam_write(root, "module.jai", "strict_root :: 1;\n"));
    expect(build_seam_write(root, "src/module.jai", "strict_src :: 2;\n"));
    ambiguous, ambiguous_output, ambiguous_errors := run_otter_child_at(root, .["build"]);
    expect(expect_exit("strict-ambiguous-modules", ambiguous, 1));
    expect(output_matches("strict-ambiguous-modules", tprint("%\n%", ambiguous_output, ambiguous_errors), .["module.jai", "src/module.jai"]));
} @test

workspace_products_independent_and_same_name :: () {
    root := otter_scratch("workspace-products-independent");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"host\", version = \"1\", workspace = .{members = .[\"members/*\"], exclude = .[\"members/private\"]}};\n"));
    expect(build_seam_write(root, "members/one/package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"twin\", version = \"1\"};\n"));
    expect(build_seam_write(root, "members/two/package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"twin\", version = \"1\"};\n"));
    expect(build_seam_write(root, "members/private/package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"standalone\", version = \"1\"};\n"));
    expect(make_directory_if_it_does_not_exist(tprint("%/members/private/src", root), recursive = true));
    expect(build_seam_write(root, "members/private/src/main.jai", "#import \"Basic\";\nmain :: () { print(\"INDEPENDENT\"); }\n"));

    cache := otter_scratch("workspace-products-independent-cache");
    discovery, discovered := discover_workspace(root, cache, plugin_face_modules_dir());
    expect(discovered);
    // The excluded package is not a member, so same-name members stay the only
    // name candidates and the ambiguity is reported rather than resolved.
    expect(discovery.member_packages.count == 3);
    ambiguous := select_workspace_packages(discovery, root, .{names = .["twin"]});
    expect(!ambiguous.success && find_index_from_left(ambiguous.error, "ambiguous") >= 0);
    by_path := select_workspace_packages(discovery, root, .{paths = .["members/two"]});
    expect(by_path.success && by_path.packages.count == 1 && by_path.paths[0] == "members/two");

    // An excluded (or otherwise unregistered) package still runs on its own.
    result, output, errors := run_otter_child_at(tprint("%/members/private", root), .["build"]);
    expect(expect_exit("independent-excluded-package", result, 0));
    expect(output_matches("independent-excluded-package", tprint("%\n%", output, errors), .["Package 'standalone'"]));
    artifact := target_artifact_path(package_target_dir(tprint("%/members/private", root)), "standalone");
    expect(file_exists(artifact));

    // Cleaning the workspace does not reach into the excluded package.
    clean_root, _, _ := run_otter_child_at(root, .["clean"]);
    expect(expect_exit("independent-clean-root", clean_root, 0));
    expect(file_exists(artifact));
} @test
