#import "Basic";
#import "Testing";
#import "File_Utilities";

// ---------------------------------------------------------------------------
// Command selection tests (spec 0087 decisions 17-20/23/27, ticket 0093).
// Every case drives the real executable over a temporary package tree, so the
// observable contract is the CLI's: which packages ran, which programs were
// compiled, what the batch report says and which exit code came back.
//
// The fixtures are written at run time (build_seam_write) so each case owns its
// declaration text; none of them is checked in, so a change here cannot leak
// into another suite.
// ---------------------------------------------------------------------------

cs_package :: (root: string, directory: string) -> string {
    return tprint("%1/%2", root, directory);
}

cs_last_component :: (path: string) -> string {
    index := path.count - 1;
    while index >= 0 && path[index] != #char "/" index -= 1;
    return slice(path, index + 1, path.count - index - 1);
}

// One explicit program named `program_name`; it prints its own name so the
// launch is observable.
cs_write_program_member :: (root: string, directory: string, program_name: string) -> bool {
    member := cs_package(root, directory);
    if !build_seam_write(member, "package.jai", tprint("#import \"Juice\";\nPACKAGE :: Package.{name = \"%1\", version = \"1\", executables = .[.{name = \"%1\", entry = \"src/main.jai\"}]};\n", program_name)) return false;
    return build_seam_write(member, "src/main.jai", tprint("#import \"Basic\";\nmain :: () { print(\"%1 says hello\"); }\n", program_name));
}

// A test-only member: no public module and no program (decision 19 — test never
// requires a public product). An empty test name writes only the declaration, so
// the member has no test source at all (the zero-test case).
cs_write_test_member :: (root: string, directory: string, test_name: string, test_passes: bool, body := "") -> bool {
    member := cs_package(root, directory);
    declaration := tprint("#import \"Juice\";\nPACKAGE :: Package.{name = \"%1\", version = \"1\", modules = .[], executables = .[]};\n", cs_last_component(directory));
    if !build_seam_write(member, "package.jai", declaration) return false;
    if body != "" return build_seam_write(member, "member_test.jai", body);
    if test_name == "" return true;
    source := tprint("#import \"Testing\";\n\n%1 :: () {\n    expect(%2);\n} @test\n", test_name, ifx test_passes then "true" else "false");
    return build_seam_write(member, "member_test.jai", source);
}

cs_artifact_exists :: (root: string, directory: string, program_name: string) -> bool {
    return file_exists(target_artifact_path(package_target_dir(cs_package(root, directory)), program_name));
}

cs_clear_member_targets :: (root: string) {
    for member: string.["members/alpha", "members/beta", "members/gamma"] delete_directory_full(package_target_dir(cs_package(root, member)));
}

// ---------------------------------------------------------------------------
// Slice 1: every command shares the selection. A pure workspace root omits the
// package identity entirely, so the location default is the whole member set.
// ---------------------------------------------------------------------------
command_selection_pure_workspace_default :: () {
    root := otter_scratch("command-selection-pure-workspace");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{workspace = .{members = .[\"members/*\"]}};\n"));
    expect(cs_write_program_member(root, "members/alpha", "alpha"));
    expect(cs_write_program_member(root, "members/beta", "beta"));

    result, output, errors := run_otter_child_at(root, .["build"]);
    combined := tprint("%\n%", output, errors);
    expect(expect_exit("pure-workspace-build", result, 0));
    // build compiles programs; it never launches them.
    expect(output_matches("pure-workspace-build", combined, .["says hello"], want = false));
    expect(output_matches("pure-workspace-build", combined, .["[juice Build] Compiling Target 'alpha'", "[juice Build] Compiling Target 'beta'"]));
    expect(cs_artifact_exists(root, "members/alpha", "alpha"));
    expect(cs_artifact_exists(root, "members/beta", "beta"));
} @test

// ---------------------------------------------------------------------------
// The explicit flag surface: -p/--package name, --package-path directory and
// --workspace, with the location default separating the root package from the
// member set.
// ---------------------------------------------------------------------------
command_selection_flags_cli :: () {
    root := otter_scratch("command-selection-flags");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"root\", version = \"1\", modules = .[], executables = .[], workspace = .{members = .[\"members/*\"]}};\n"));
    expect(cs_write_program_member(root, "members/alpha", "alpha"));
    expect(cs_write_program_member(root, "members/beta", "beta"));

    // At the root with an omitted default_members list only the root package is
    // selected; it declares no program, so build states exactly what it checked.
    result, output, errors := run_otter_child_at(root, .["build"]);
    combined := tprint("%\n%", output, errors);
    expect(expect_exit("root-default", result, 0));
    expect(output_matches("root-default", combined, .["Package '.' has no executable program", "not type-checked"]));
    expect(output_matches("root-default", combined, .["Compiling Target"], want = false));
    expect(!cs_artifact_exists(root, "members/alpha", "alpha"));

    // --workspace selects every member including the root package.
    result, output, errors = run_otter_child_at(root, .["build", "--workspace"]);
    combined = tprint("%\n%", output, errors);
    expect(expect_exit("workspace-flag", result, 0));
    expect(output_matches("workspace-flag", combined, .["[juice Build] Compiling Target 'alpha'", "[juice Build] Compiling Target 'beta'"]));
    expect(cs_artifact_exists(root, "members/alpha", "alpha") && cs_artifact_exists(root, "members/beta", "beta"));

    // A named selection replaces the default set: only beta is built.
    cs_clear_member_targets(root);
    result, output, errors = run_otter_child_at(root, .["build", "-p", "beta"]);
    combined = tprint("%\n%", output, errors);
    expect(expect_exit("named-selection", result, 0));
    expect(output_matches("named-selection", combined, .["Compiling Target 'beta'"]));
    expect(output_matches("named-selection", combined, .["Compiling Target 'alpha'"], want = false));
    expect(cs_artifact_exists(root, "members/beta", "beta") && !cs_artifact_exists(root, "members/alpha", "alpha"));

    // The workspace-relative path spelling selects the same package.
    cs_clear_member_targets(root);
    result, output, errors = run_otter_child_at(root, .["build", "--package-path", "members/alpha"]);
    combined = tprint("%\n%", output, errors);
    expect(expect_exit("path-selection", result, 0));
    expect(output_matches("path-selection", combined, .["Compiling Target 'alpha'"]));
    expect(output_matches("path-selection", combined, .["Compiling Target 'beta'"], want = false));
    expect(cs_artifact_exists(root, "members/alpha", "alpha") && !cs_artifact_exists(root, "members/beta", "beta"));

    // From inside a member the location default is that member alone.
    cs_clear_member_targets(root);
    result, output, errors = run_otter_child_at(cs_package(root, "members/beta/src"), .["build"]);
    combined = tprint("%\n%", output, errors);
    expect(expect_exit("member-default", result, 0));
    expect(output_matches("member-default", combined, .["Compiling Target 'beta'"]));
    expect(output_matches("member-default", combined, .["Compiling Target 'alpha'"], want = false));
} @test

// A member keeps its nearest declaration as the current package, but explicit
// selections and declaration validation use its containing workspace.
command_selection_member_workspace_cli :: () {
    root := otter_scratch("command-selection-member-workspace");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{workspace = .{members = .[\"members/*\"]}};\n"));
    expect(cs_write_program_member(root, "members/alpha", "alpha"));
    expect(cs_write_program_member(root, "members/beta", "beta"));

    working_directory := cs_package(root, "members/alpha/src");
    result, output, errors := run_otter_child_at(working_directory, .["build", "--package-path", "members/beta"]);
    combined := tprint("%\n%", output, errors);
    expect(expect_exit("member-selects-sibling", result, 0));
    expect(output_matches("member-selects-sibling", combined, .["Compiling Target 'beta'"]));
    expect(!cs_artifact_exists(root, "members/alpha", "alpha"));
    expect(cs_artifact_exists(root, "members/beta", "beta"));

    expect(build_seam_write(cs_package(root, "members/beta"), "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"beta\"};\n"));
    result, output, errors = run_otter_child_at(working_directory, .["build"]);
    expect(expect_exit("member-invalid-sibling", result, 1));
    expect(!cs_artifact_exists(root, "members/alpha", "alpha"));
} @test

// Declaration validity does not depend on whether defaults are selected.
command_selection_workspace_declaration_preflight_cli :: () {
    root := otter_scratch("command-selection-declaration-preflight");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(cs_write_program_member(root, "members/alpha", "alpha"));
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{workspace = .{members = .[\"members/alpha\"], default_members = .[\"missing\"]}};\n"));
    result, output, errors := run_otter_child_at(root, .["build", "-p", "alpha"]);
    expect(expect_exit("explicit-selection-invalid-default", result, 1));
    expect(!cs_artifact_exists(root, "members/alpha", "alpha"));
} @test

command_selection_workspace_root_exclude_cli :: () {
    root := otter_scratch("command-selection-root-exclude");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(cs_write_program_member(root, "members/alpha", "alpha"));
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"root\", version = \"1\", modules = .[], executables = .[], workspace = .{members = .[\"members/alpha\"], exclude = .[\".\"]}};\n"));
    result, output, errors := run_otter_child_at(root, .["build"]);
    expect(expect_exit("cannot-exclude-root-package", result, 1));

    // Explicit empty defaults remain valid, and an explicit selection can
    // replace that empty default set.
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{workspace = .{members = .[\"members/alpha\"], default_members = .[]}};\n"));
    result, output, errors = run_otter_child_at(root, .["build", "-p", "alpha"]);
    expect(expect_exit("explicit-selection-empty-default", result, 0));
    expect(cs_artifact_exists(root, "members/alpha", "alpha"));
} @test

// ---------------------------------------------------------------------------
// Selection failures stop before any command work (decision 18/70): no program
// is compiled and no artifact appears.
// ---------------------------------------------------------------------------
command_selection_rejections_cli :: () {
    root := otter_scratch("command-selection-rejections");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"root\", version = \"1\", modules = .[], executables = .[], workspace = .{members = .[\"members/*\"]}};\n"));
    expect(cs_write_program_member(root, "members/alpha", "alpha"));

    result, output, errors := run_otter_child_at(root, .["build", "-p", "missing"]);
    combined := tprint("%\n%", output, errors);
    expect(expect_exit("unknown-name", result, 1));
    expect(output_matches("unknown-name", combined, .["Unknown package name: missing"]));

    result, output, errors = run_otter_child_at(root, .["build", "--workspace", "-p", "alpha"]);
    combined = tprint("%\n%", output, errors);
    expect(expect_exit("conflicting-selection", result, 1));
    expect(output_matches("conflicting-selection", combined, .["--workspace cannot be combined with --package or --package-path"]));

    result, output, errors = run_otter_child_at(root, .["build", "--package-path", "elsewhere"]);
    combined = tprint("%\n%", output, errors);
    expect(expect_exit("foreign-path", result, 1));
    expect(output_matches("foreign-path", combined, .["Package path is not a workspace member: elsewhere"]));

    // A malformed option is rejected at plan time, before the handler runs, with
    // the command's usage and its documented selection surface.
    result, output, errors = run_otter_child_at(root, .["build", "--frobnicate"]);
    combined = tprint("%\n%", output, errors);
    expect(expect_exit("unknown-option", result, 1));
    expect(output_matches("unknown-option", combined, .["[juice ERROR] Usage: juice build", "Selection: --workspace"]));

    // Not one of the failures above compiled anything.
    expect(!cs_artifact_exists(root, "members/alpha", "alpha"));
} @test

// ---------------------------------------------------------------------------
// run: one package, one program, only that program compiled (decision 19/73).
// ---------------------------------------------------------------------------
command_selection_run_cardinality_cli :: () {
    root := otter_scratch("command-selection-run-cardinality");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{workspace = .{members = .[\"members/*\"]}};\n"));
    expect(cs_write_program_member(root, "members/alpha", "alpha"));
    expect(cs_write_program_member(root, "members/beta", "beta"));

    // Two selected packages: run refuses before compiling or launching.
    result, output, errors := run_otter_child_at(root, .["run", "--workspace"]);
    combined := tprint("%\n%", output, errors);
    expect(expect_exit("run-two-packages", result, 1));
    expect(output_matches("run-two-packages", combined, .["run requires exactly one selected package", "members/alpha", "members/beta"]));
    expect(output_matches("run-two-packages", combined, .["Compiling Target", "Launching"], want = false));

    // One explicitly selected package runs its program.
    result, output, errors = run_otter_child_at(root, .["run", "-p", "beta"]);
    combined = tprint("%\n%", output, errors);
    expect(expect_exit("run-one-package", result, 0));
    expect(output_matches("run-one-package", combined, .["Compiling Target 'beta'", "beta says hello"]));
    expect(output_matches("run-one-package", combined, .["Compiling Target 'alpha'"], want = false));
} @test

// A real local Git provider proves preflight is not merely before compilation:
// invalid cardinality must not acquire content or publish any selection.
command_selection_run_preflight_no_fetch_cli :: () {
    scratch := dr_scratch("selection-preflight");
    dr_isolate(scratch);
    defer dr_restore_env();
    provider := dr_path(scratch, "provider");
    expect(dr_git_init(provider));
    expect(dr_write_module_provider(provider, "provider", "Provider_Value :: 7;\n"));
    commit := dr_git_commit_all(provider, "preflight provider");
    expect(commit != "");
    root := dr_path(scratch, "workspace");
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{workspace = .{members = .[\"members/*\"]}};\n"));
    expect(cs_write_program_member(root, "members/alpha", "alpha"));
    expect(cs_write_program_member(root, "members/beta", "beta"));
    declaration := tprint("#import \"Juice\";\nPACKAGE :: Package.{name = \"beta\", version = \"1\", dependencies = .[.{name = \"provider\", source = .{kind = .GIT, git = .{url = %1, branch = \"main\"}}}]};\n", quote_jai_string(provider));
    expect(build_seam_write(cs_package(root, "members/beta"), "package.jai", declaration));

    result, output, errors := run_otter_child_at(root, .["run", "--workspace"]);
    expect(expect_exit("run-cardinality-preflight", result, 1));
    expect(output_matches("run-cardinality-preflight", tprint("%\n%", output, errors), .["run requires exactly one selected package"]));
    expect(!dr_content_has_commit(scratch, commit));
    expect(dr_state_text(scratch) == "");
    expect(!cs_artifact_exists(root, "members/alpha", "alpha"));
} @test

command_selection_first_failure_no_later_fetch_cli :: () {
    scratch := dr_scratch("selection-first-failure");
    dr_isolate(scratch);
    defer dr_restore_env();
    provider := dr_path(scratch, "provider");
    expect(dr_git_init(provider));
    expect(dr_write_module_provider(provider, "provider", "Provider_Value :: 7;\n"));
    previous_commit := copy_string(dr_git_commit_all(provider, "earlier provider"));
    expect(previous_commit != "");
    expect(dr_write_module_provider(provider, "provider", "Provider_Value :: 9;\n"));
    commit := copy_string(dr_git_commit_all(provider, "later provider"));
    expect(commit != "" && commit != previous_commit);
    root := dr_path(scratch, "workspace");
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{workspace = .{members = .[\"members/*\"]}};\n"));
    expect(cs_write_program_member(root, "members/alpha", "alpha"));
    expect(cs_write_program_member(root, "members/beta", "beta"));
    expect(cs_write_program_member(root, "members/gamma", "gamma"));
    for member_name: string.["alpha", "beta"] {
        earlier_declaration := tprint("#import \"Juice\";\nPACKAGE :: Package.{name = \"%1\", version = \"1\", dependencies = .[.{name = \"provider\", source = .{kind = .GIT, git = .{url = %2, rev = %3}}}]};\n", member_name, quote_jai_string(provider), quote_jai_string(previous_commit));
        expect(build_seam_write(cs_package(root, tprint("members/%", member_name)), "package.jai", earlier_declaration));
    }
    expect(build_seam_write(cs_package(root, "members/beta"), "src/main.jai", "main :: () { this does not compile }\n"));
    declaration := tprint("#import \"Juice\";\nPACKAGE :: Package.{name = \"gamma\", version = \"1\", dependencies = .[.{name = \"provider\", source = .{kind = .GIT, git = .{url = %1, branch = \"main\"}}}]};\n", quote_jai_string(provider));
    expect(build_seam_write(cs_package(root, "members/gamma"), "package.jai", declaration));

    result, output, errors := run_otter_child_at(root, .["build", "--workspace"]);
    expect(expect_exit("batch-no-later-fetch", result, 1));
    expect(output_matches("batch-no-later-fetch", tprint("%\n%", output, errors), .["build: completed members/alpha", "build: failed members/beta", "build: not executed members/gamma"]));
    expect(cs_artifact_exists(root, "members/alpha", "alpha"));
    expect(!dr_content_has_commit(scratch, commit));
    expect(!contains(dr_state_text(scratch), commit));
    expect(contains(dr_state_text(scratch), previous_commit));
    // An earlier valid resolution is kept even though the next compilation
    // failed; the successful package remains buildable from its offline state.
    result, output, errors = run_otter_child_at(root, .["build", "-p", "alpha", "--offline"]);
    expect(expect_exit("completed-package-keeps-resolution", result, 0));
} @test

// ---------------------------------------------------------------------------
// test: zero products, zero tests and zero matches all succeed, the pattern is
// applied per package, and a real compile error is never hidden (decision 19).
// ---------------------------------------------------------------------------
command_selection_test_batch_cli :: () {
    root := otter_scratch("command-selection-test-batch");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{workspace = .{members = .[\"members/*\"]}};\n"));
    expect(cs_write_test_member(root, "members/alpha", "alpha_check", true));
    expect(cs_write_test_member(root, "members/beta", "beta_check", true));
    expect(cs_write_test_member(root, "members/empty", "", true));

    // Every selected package's tests run; the test-only member with no source
    // files still succeeds (zero tests is not a failure).
    result, output, errors := run_otter_child_at(root, .["test"]);
    combined := tprint("%\n%", output, errors);
    expect(expect_exit("test-batch", result, 0));
    expect(output_matches("test-batch", combined, .["[test] alpha_check", "[test] beta_check", "No tests found"]));
    expect(count_text_occurrences(combined, "1 passed, 0 failed") == 2);

    // The pattern is applied to every package; a package with no match reports
    // it and still succeeds.
    result, output, errors = run_otter_child_at(root, .["test", "alpha"]);
    combined = tprint("%\n%", output, errors);
    expect(expect_exit("test-pattern", result, 0));
    expect(output_matches("test-pattern", combined, .["[test] alpha_check", "No tests matched 'alpha'"]));
    expect(output_matches("test-pattern", combined, .["[test] beta_check"], want = false));

    // A compile error in a selected package's test source fails the batch; the
    // pattern never hides it.
    expect(cs_write_test_member(root, "members/broken", "broken_check", true, "#import \"Testing\";\n\nbroken_check :: () {\n    this does not compile\n} @test\n"));
    result, output, errors = run_otter_child_at(root, .["test", "alpha"]);
    combined = tprint("%\n%", output, errors);
    expect(expect_exit("test-compile-error", result, 1));
    expect(output_matches("test-compile-error", combined, .["members/broken"]));
} @test

// ---------------------------------------------------------------------------
// The first failure stops the batch and the report names the completed, failed
// and not-executed scope; an earlier success is never rolled back (decision 20).
// ---------------------------------------------------------------------------
command_selection_first_failure_cli :: () {
    root := otter_scratch("command-selection-first-failure");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{workspace = .{members = .[\"members/*\"]}};\n"));
    expect(cs_write_program_member(root, "members/alpha", "alpha"));
    expect(cs_write_program_member(root, "members/beta", "beta"));
    expect(cs_write_program_member(root, "members/gamma", "gamma"));
    // beta sorts between alpha and gamma and cannot compile.
    expect(build_seam_write(cs_package(root, "members/beta"), "src/main.jai", "#import \"Basic\";\nmain :: () { this is not Jai }\n"));

    result, output, errors := run_otter_child_at(root, .["build", "--workspace"]);
    combined := tprint("%\n%", output, errors);
    expect(expect_exit("first-failure", result, 1));
    expect(output_matches("first-failure", combined, .[
        "build: completed members/alpha",
        "build: failed members/beta",
        "build: not executed members/gamma",
    ]));
    // The completed package keeps its artifact; the not-executed one has none.
    expect(cs_artifact_exists(root, "members/alpha", "alpha"));
    expect(!cs_artifact_exists(root, "members/gamma", "gamma"));
} @test

// ---------------------------------------------------------------------------
// update: only the selected packages' graphs are refreshed, and an offline
// update is a usage error before any resolution (decision 14/19).
// ---------------------------------------------------------------------------
command_selection_update_scope_cli :: () {
    scratch := dr_scratch("command-selection-update");
    dr_delete_wait(scratch);
    defer dr_delete_wait(scratch);
    expect(make_directory_if_it_does_not_exist(scratch, recursive = true));
    dr_isolate(scratch);
    defer dr_restore_env();

    // A local Git provider: the only expensive source in the workspace.
    provider := dr_path(scratch, "provider");
    expect(dr_git_init(provider));
    expect(dr_write_module_provider(provider, "provider", "provider_value :: 7;\n"));
    commit := dr_git_commit_all(provider, "first");
    expect(commit != "");

    root := dr_path(scratch, "workspace");
    expect(make_directory_if_it_does_not_exist(root, recursive = true));
    declaration := tprint("#import \"Juice\";\nPACKAGE :: Package.{workspace = .{members = .[\"members/*\"]}};\n");
    expect(dr_write_file(root, "package.jai", declaration));
    plain_member := dr_path(root, "members/plain");
    expect(dr_write_file(plain_member, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"plain\", version = \"1\", modules = .[], executables = .[]};\n"));
    git_member := dr_path(root, "members/git-consumer");
    git_declaration := tprint("#import \"Juice\";\nPACKAGE :: Package.{name = \"git-consumer\", version = \"1\", modules = .[], executables = .[], dependencies = Dependency.[.{name = \"provider\", source = .{kind = .GIT, git = .{url = \"%1\", branch = \"main\"}}, modules = .[.{name = \"provider\", alias = \"provider_module\"}]}]};\n", provider);
    expect(dr_write_file(git_member, "package.jai", git_declaration));

    // Offline update is rejected before any declaration work.
    offline, offline_output, offline_errors := run_otter_child_at(root, string.["update", "--offline"]);
    expect(expect_exit("update-offline", offline, 1));
    expect(output_matches("update-offline", tprint("%\n%", offline_output, offline_errors), .["update cannot run offline"]));

    // Updating the plain member never resolves the Git source.
    plain, plain_output, plain_errors := run_otter_child_at(root, string.["update", "-p", "plain"]);
    expect(expect_exit("update-plain", plain, 0));
    expect(output_matches("update-plain", tprint("%\n%", plain_output, plain_errors), .["Dependency resolution graph updated."]));
    expect(!dr_content_has_commit(scratch, commit));

    // Updating the whole workspace does resolve it, once.
    all, all_output, all_errors := run_otter_child_at(root, string.["update", "--workspace"]);
    expect(expect_exit("update-all", all, 0));
    expect(output_matches("update-all", tprint("%\n%", all_output, all_errors), .["Dependency resolution graph updated."]));
    expect(dr_content_has_commit(scratch, commit));
    // update only refreshes the graph: nothing is compiled.
    expect(!file_exists(target_artifact_path(package_target_dir(git_member), "git-consumer")));
} @test
