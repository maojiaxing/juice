#import "Basic";
#import "Testing";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";

// ---------------------------------------------------------------------------
// Git resolution acceptance (spec 0087 decisions 13-15; ticket 0091 acceptance
// groups A09/A10/A11/A12). Every case builds a real local Git repository and runs
// the real juice executable with its own isolated XDG content-cache and state
// roots. The fixture helpers live in tests/dependency_resolution_tests.jai and are
// shared program-wide.
// ---------------------------------------------------------------------------

// A provider package whose single export carries Git_Value, so a case can prove
// which commit's content was actually compiled.
dr_git_provider_value :: (repository: string, value: int) -> bool {
    if !dr_write_file(repository, "package.jai", dr_package_source("gitlib", "")) return false;
    return dr_write_file(repository, "module.jai", tprint("Git_Value :: %;\n", value));
}

// A consumer app that imports the provider's single export under the given import
// name and prints the provider's value.
dr_write_git_app :: (app: string, url: string, import_name: string, selector: string) -> bool {
    body := copy_string(tprint("    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"gitlib\", source = .{kind = .GIT, git = .{url = \"%1\"%2}}, modules = .[.{alias = \"%3\"}]},\n    ],\n", url, selector, import_name));
    source := copy_string(tprint("#import \"Basic\";\n#import \"%1\";\n\nmain :: () { print(\"value=%%\\n\", Git_Value); }\n", import_name));
    return dr_write_app(app, body, source);
}

// The same consumer, selecting a provider package located inside the repository
// (a multi-package Git source).
dr_write_git_app_module :: (app: string, url: string, import_name: string, package_path: string) -> bool {
    body := copy_string(tprint("    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"gitlib\", source = .{kind = .GIT, git = .{url = \"%1\"}}, modules = .[.{path = \"%2\", alias = \"%3\"}]},\n    ],\n", url, package_path, import_name));
    source := copy_string(tprint("#import \"Basic\";\n#import \"%1\";\n\nmain :: () { print(\"value=%%\\n\", Git_Value); }\n", import_name));
    return dr_write_app(app, body, source);
}

// A40: an ordinary build reuses the recorded commit; a moved branch is not
// followed; reference name, alias and module changes keep the commit; an explicit
// update refreshes the complete graph and refuses to run offline.
dependency_resolution_git_reuse_and_update :: () {
    scratch := dr_scratch("git-reuse");
    dr_isolate(scratch);
    defer dr_restore_env();
    repository := dr_path(scratch, "repo");
    expect(dr_git_init(repository));
    expect(dr_git_provider_value(repository, 100));
    first_commit := copy_string(dr_git_commit_all(repository, "first"));
    expect(first_commit.count == 40);

    app := dr_path(scratch, "app");
    expect(dr_write_git_app(app, repository, "Lib", ", branch = \"main\""));
    expect(dr_build_app(app) == 0);
    exit_code, run_output := dr_run_app(app);
    print("[dbg] exit=% output=[%]\n", exit_code, run_output);
    expect(exit_code == 0 && contains(run_output, "value=100"));
    expect(contains(dr_state_text(scratch), first_commit));

    // The branch moves; an ordinary build keeps the recorded commit and its
    // content instead of following the new tip.
    expect(dr_git_provider_value(repository, 200));
    second_commit := copy_string(dr_git_commit_all(repository, "second"));
    expect(second_commit.count == 40 && second_commit != first_commit);
    expect(dr_build_app(app) == 0);
    exit_code, run_output = dr_run_app(app);
    expect(exit_code == 0 && contains(run_output, "value=100"));
    state := dr_state_text(scratch);
    expect(contains(state, first_commit) && !contains(state, second_commit));

    // A changed import name/alias does not re-resolve.
    expect(dr_write_git_app(app, repository, "Renamed", ", branch = \"main\""));
    expect(dr_build_app(app) == 0);
    exit_code, run_output = dr_run_app(app);
    expect(exit_code == 0 && contains(run_output, "value=100"));

    // An explicit update refreshes the graph, and the new content compiles.
    update_result, update_output, update_errors := dr_run(app, string.["update"]);
    expect(expect_exit("update", update_result, 0, "dependency resolution"));
    expect(contains(dr_state_text(scratch), second_commit));
    expect(dr_build_app(app) == 0);
    exit_code, run_output = dr_run_app(app);
    expect(exit_code == 0 && contains(run_output, "value=200"));

    // update and offline are mutually exclusive.
    offline_update, offline_output, offline_errors := dr_run(app, string.["update", "--offline"]);
    expect(offline_update.exit_code != 0);
    offline_combined := tprint("%\n%", offline_output, offline_errors);
    expect(contains(offline_combined, "update cannot run offline"));
} @test

// A11: content and state are separate. Deleting content keeps the recorded
// selection; offline it fails instead of picking another commit; online it
// restores exactly the recorded commit.
dependency_resolution_git_content_restore :: () {
    scratch := dr_scratch("git-restore");
    dr_isolate(scratch);
    defer dr_restore_env();
    repository := dr_path(scratch, "repo");
    expect(dr_git_init(repository));
    expect(dr_git_provider_value(repository, 100));
    first_commit := copy_string(dr_git_commit_all(repository, "first"));
    app := dr_path(scratch, "app");
    expect(dr_write_git_app(app, repository, "Lib", ", branch = \"main\""));
    expect(dr_build_app(app) == 0);

    // Move the branch, then delete every content checkout (state stays).
    expect(dr_git_provider_value(repository, 300));
    second_commit := copy_string(dr_git_commit_all(repository, "second"));
    expect(dr_delete_wait(dr_path(scratch, "xdg-cache/juice/content")));
    expect(!is_directory(dr_path(scratch, "xdg-cache/juice/content")));
    expect(contains(dr_state_text(scratch), first_commit));

    // Offline cannot restore missing content.
    offline_result, offline_output, offline_errors := dr_run(app, string.["build", "--offline"]);
    expect(offline_result.exit_code != 0);
    offline_combined := tprint("%\n%", offline_output, offline_errors);
    expect(contains(offline_combined, "Offline resolution needs cached content"));

    // Online restores the recorded commit only, never the moved branch tip.
    expect(dr_build_app(app) == 0);
    exit_code, run_output := dr_run_app(app);
    expect(exit_code == 0 && contains(run_output, "value=100"));
    expect(dr_content_has_commit(scratch, first_commit));
    expect(!dr_content_has_commit(scratch, second_commit));
} @test

// A09: the offline matrix. A record with complete content works; without a record
// only a full commit id whose content is already present may establish one;
// floating and short selectors are rejected; absent content is rejected.
dependency_resolution_offline_matrix :: () {
    scratch := dr_scratch("offline");
    dr_isolate(scratch);
    defer dr_restore_env();
    repository := dr_path(scratch, "repo");
    expect(dr_git_init(repository));
    expect(dr_git_provider_value(repository, 100));
    first_commit := copy_string(dr_git_commit_all(repository, "first"));

    // No record: a floating branch is rejected offline.
    app := dr_path(scratch, "app");
    expect(dr_write_git_app(app, repository, "Lib", ", branch = \"main\""));
    floating_result, floating_output, floating_errors := dr_run(app, string.["build", "--offline"]);
    expect(floating_result.exit_code != 0);
    floating_combined := tprint("%\n%", floating_output, floating_errors);
    expect(contains(floating_combined, "no recorded selection"));

    // A short revision does not establish a record offline.
    short_app := dr_path(scratch, "short-app");
    expect(dr_write_git_app(short_app, repository, "Lib", ", rev = \"abcdef1\""));
    short_result, short_output, short_errors := dr_run(short_app, string.["build", "--offline"]);
    expect(short_result.exit_code != 0);

    // Establish content online, then a full commit id without a record works
    // offline because its content is already present.
    expect(dr_build_app(app) == 0);
    pinned_app := dr_path(scratch, "pinned-app");
    expect(dr_write_git_app(pinned_app, repository, "Lib", copy_string(tprint(", rev = \"%1\"", first_commit))));
    pinned_result, pinned_output, pinned_errors := dr_run(pinned_app, string.["build", "--offline"]);
    expect(expect_exit("pinned offline", pinned_result, 0, "dependency resolution"));
    pinned_exit, pinned_run := dr_run_app(pinned_app);
    expect(pinned_exit == 0 && contains(pinned_run, "value=100"));

    // A record plus complete content reuses offline.
    offline_result, offline_output, offline_errors := dr_run(app, string.["build", "--offline"]);
    expect(expect_exit("offline reuse", offline_result, 0, "dependency resolution"));

    // A full commit id whose content is absent cannot be established offline.
    unknown_commit := "0123456789abcdef0123456789abcdef01234567";
    unknown_app := dr_path(scratch, "unknown-app");
    expect(dr_write_git_app(unknown_app, repository, "Lib", copy_string(tprint(", rev = \"%1\"", unknown_commit))));
    unknown_result, unknown_output, unknown_errors := dr_run(unknown_app, string.["build", "--offline"]);
    expect(unknown_result.exit_code != 0);
    unknown_combined := tprint("%\n%", unknown_output, unknown_errors);
    expect(contains(unknown_combined, "no recorded selection") || contains(unknown_combined, "Offline resolution needs cached content"));
} @test

// A10: two consumer projects share content but never share selections; a member
// update does not move a sibling member.
dependency_resolution_context_isolation :: () {
    scratch := dr_scratch("isolation");
    dr_isolate(scratch);
    defer dr_restore_env();
    repository := dr_path(scratch, "repo");
    expect(dr_git_init(repository));
    expect(dr_git_provider_value(repository, 100));
    first_commit := copy_string(dr_git_commit_all(repository, "first"));

    app_one := dr_path(scratch, "app-one");
    app_two := dr_path(scratch, "app-two");
    expect(dr_write_git_app(app_one, repository, "Lib", ", branch = \"main\""));
    expect(dr_write_git_app(app_two, repository, "Lib", ", branch = \"main\""));
    expect(dr_build_app(app_one) == 0);
    expect(dr_build_app(app_two) == 0);

    // The branch moves and only the first project updates.
    expect(dr_git_provider_value(repository, 200));
    second_commit := copy_string(dr_git_commit_all(repository, "second"));
    update_result, update_output, update_errors := dr_update_app(app_one);
    expect(expect_exit("update app one", update_result, 0, "dependency resolution"));
    expect(dr_build_app(app_one) == 0);
    first_exit, first_run := dr_run_app(app_one);
    expect(first_exit == 0 && contains(first_run, "value=200"));

    // The second project still compiles its own recorded commit.
    expect(dr_build_app(app_two) == 0);
    second_exit, second_run := dr_run_app(app_two);
    expect(second_exit == 0 && contains(second_run, "value=100"));
    both := dr_state_text(scratch);
    expect(contains(both, second_commit) && contains(both, first_commit));

    // Two workspace members select independently as well.
    workspace := dr_path(scratch, "ws");
    member_one := dr_path(workspace, "member-one");
    member_two := dr_path(workspace, "member-two");
    expect(dr_write_file(workspace, "package.jai", "#import \"Juice\";\n\nPACKAGE :: Package.{\n    version = \"0.1.0\",\n    name    = \"ws_root\",\n\n    workspace = .{\n        members = string.[\"member-one\", \"member-two\"],\n    },\n};\n"));
    expect(dr_write_git_app(member_one, repository, "Lib", ", branch = \"main\""));
    expect(dr_write_git_app(member_two, repository, "Lib", ", branch = \"main\""));
    expect(dr_build_app(member_one) == 0);
    expect(dr_build_app(member_two) == 0);
    expect(dr_git_provider_value(repository, 300));
    third_commit := copy_string(dr_git_commit_all(repository, "third"));
    member_update, member_output, member_errors := dr_update_app(member_one);
    expect(expect_exit("member update", member_update, 0, "dependency resolution"));
    expect(dr_build_app(member_one) == 0);
    member_exit, member_run := dr_run_app(member_one);
    expect(member_exit == 0 && contains(member_run, "value=300"));
    expect(dr_build_app(member_two) == 0);
    sibling_exit, sibling_run := dr_run_app(member_two);
    // member-two first resolved when the branch tip was the second commit, so its
    // own record is that commit: it keeps compiling value=200 and never follows
    // member-one's update to the third commit (value=300).
    expect(sibling_exit == 0 && contains(sibling_run, "value=200"));
    member_two_state := dr_state_text(scratch);
    expect(contains(member_two_state, second_commit) && contains(member_two_state, third_commit));
} @test

// A11: a corrupt state file is an error, not an absent record.
dependency_resolution_corrupt_state_fails :: () {
    scratch := dr_scratch("corrupt-state");
    dr_isolate(scratch);
    defer dr_restore_env();
    repository := dr_path(scratch, "repo");
    expect(dr_git_init(repository));
    expect(dr_git_provider_value(repository, 100));
    expect(dr_git_commit_all(repository, "first").count == 40);

    app := dr_path(scratch, "app");
    expect(dr_write_git_app(app, repository, "Lib", ", branch = \"main\""));
    expect(dr_build_app(app) == 0);

    contexts := dr_path(scratch, "xdg-state/juice/contexts");
    state_files := file_list(contexts, recursive = true);
    corrupted := 0;
    for name: state_files {
        if !ends_with(name, "resolution.state") continue;
        expect(write_entire_file(name, "not a resolution state\n"));
        corrupted += 1;
    }
    expect(corrupted > 0);
    corrupt_result, corrupt_output, corrupt_errors := dr_run(app, string.["build"]);
    expect(corrupt_result.exit_code != 0);
    corrupt_combined := tprint("%\n%", corrupt_output, corrupt_errors);
    expect(contains(corrupt_combined, "corrupt"));
} @test

// A10/A11: a failed resolution keeps the previous selections and fails the
// operation; a compile failure after a successful resolution keeps the new one.
dependency_resolution_failure_preserves_old_state :: () {
    scratch := dr_scratch("failure-state");
    dr_isolate(scratch);
    defer dr_restore_env();
    repository := dr_path(scratch, "repo");
    expect(dr_git_init(repository));
    expect(dr_git_provider_value(repository, 100));
    first_commit := copy_string(dr_git_commit_all(repository, "first"));

    app := dr_path(scratch, "app");
    expect(dr_write_git_app(app, repository, "Lib", ", branch = \"main\""));
    expect(dr_build_app(app) == 0);
    expect(contains(dr_state_text(scratch), first_commit));

    // A resolution failure (unknown export) fails the build and keeps the record.
    broken := dr_path(scratch, "broken-app");
    expect(dr_write_git_app(broken, repository, "Lib", ", branch = \"main\""));
    broken_body := copy_string(tprint("    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"gitlib\", source = .{kind = .GIT, git = .{url = \"%1\", branch = \"main\"}}, modules = .[.{name = \"Missing\"}]},\n    ],\n", repository));
    expect(dr_write_file(broken, "package.jai", dr_package_source("app", broken_body)));
    broken_result, broken_output, broken_errors := dr_run(broken, string.["build"]);
    expect(broken_result.exit_code != 0);
    broken_combined := tprint("%\n%", broken_output, broken_errors);
    expect(contains(broken_combined, "does not export"));
    expect(contains(dr_state_text(scratch), first_commit));

    // The original consumer still builds its old selection.
    expect(dr_build_app(app) == 0);

    // Update advances the record; a broken source then fails to compile while the
    // new selection stays recorded (a compile failure does not roll back).
    expect(dr_git_provider_value(repository, 200));
    second_commit := copy_string(dr_git_commit_all(repository, "second"));
    update_result, update_output, update_errors := dr_run(app, string.["update"]);
    expect(expect_exit("update", update_result, 0, "dependency resolution"));
    expect(contains(dr_state_text(scratch), second_commit));
    expect(dr_write_file(app, "src/main.jai", "#import \"Basic\";\n\nmain :: () { this is not Jai }\n"));
    compile_result, compile_output, compile_errors := dr_run(app, string.["build"]);
    expect(compile_result.exit_code != 0);
    expect(contains(dr_state_text(scratch), second_commit));
} @test

// A12: a Git provider's own sources stay inside its checkout: an in-checkout
// sibling package works, an escaped path fails, and the shared checkout is never
// modified.
dependency_resolution_git_checkout_boundary :: () {
    scratch := dr_scratch("git-boundary");
    dr_isolate(scratch);
    defer dr_restore_env();
    repository := dr_path(scratch, "repository");
    expect(dr_git_init(repository));

    sibling := dr_path(dr_path(repository, "libs"), "sibling");
    expect(dr_write_module_provider(sibling, "sibling", "Sibling_Value :: 21;\n"));
    provider := dr_path(repository, "provider");
    expect(dr_write_file(provider, "package.jai", dr_package_source("provider", "    dependencies = Dependency.[\n        .{name = \"sibling\", source = .{kind = .PATH, path = \"../libs/sibling\"}, modules = .[.{alias = \"Sibling\"}]},\n    ],\n")));
    expect(dr_write_file(provider, "module.jai", "#import \"Sibling\";\n\nGit_Value :: Sibling_Value + 1;\n"));
    commit := copy_string(dr_git_commit_all(repository, "provider with sibling"));
    expect(commit.count == 40);

    app := dr_path(scratch, "app");
    expect(dr_write_git_app_module(app, repository, "Prov", "provider"));
    expect(dr_build_app(app) == 0);
    exit_code, run_output := dr_run_app(app);
    expect(exit_code == 0 && contains(run_output, "value=22"));

    // The shared checkout is untouched and no consumer view landed inside it.
    status_result, status_output := dr_git(string.["-C", repository, "status", "--porcelain"]);
    expect(status_result.exit_code == 0 && trim(status_output) == "");
    expect(dr_content_has_commit(scratch, commit));
    for directory: dr_content_directories(scratch) {
        if get_filename(directory) != commit continue;
        expect(!is_directory(dr_path(directory, "target")));
        expect(!is_directory(dr_path(directory, "deps")));
    }

    // A path that escapes the checkout is rejected.
    expect(dr_write_file(provider, "package.jai", dr_package_source("provider", "    dependencies = Dependency.[\n        .{name = \"escape\", source = .{kind = .PATH, path = \"../../outside\"}, modules = .[.{}]},\n    ],\n")));
    expect(dr_write_file(provider, "module.jai", "#import \"Sibling\";\n\nGit_Value :: Sibling_Value + 1;\n"));
    escape_commit := copy_string(dr_git_commit_all(repository, "escaping path"));
    expect(escape_commit.count == 40);
    escape_app := dr_path(scratch, "escape-app");
    expect(dr_write_git_app_module(escape_app, repository, "Prov", "provider"));
    escape_result, escape_output, escape_errors := dr_run(escape_app, string.["build"]);
    expect(escape_result.exit_code != 0);
    escape_combined := tprint("%\n%", escape_output, escape_errors);
    if !contains(escape_combined, "escapes its Git checkout") print("[checkout-boundary] unexpected escape rejection:\n%\n", escape_combined);
    expect(contains(escape_combined, "escapes its Git checkout"));
} @test
