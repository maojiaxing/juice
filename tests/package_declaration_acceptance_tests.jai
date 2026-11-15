#import "Basic";
#import "Testing";
#import "File";
#import "File_Utilities";
#import "String";

#if OS == .WINDOWS {
    #import "Windows";
} else {
    #import "POSIX";
}

// ---------------------------------------------------------------------------
// Final acceptance coverage for spec 0087 (ticket 0096).
//
// The 0095 migration guide is the source of the uncovered list; its own
// examples did not run these behaviours. Each case here is a real CLI
// acceptance case: a temporary package tree, the real executable, a real local
// Git repository where relevant, and its own isolated XDG content-cache and
// state roots. No internal object is built in place of the user's declaration.
//
// Groups added here: A02 (a same-named workspace member never replaces a Git
// source), A03 (different sources and different revisions of the same package
// name coexist under explicit aliases), A11 (a moved project root is a new
// resolution context while a changed cwd is not; a relative XDG value warns and
// falls back), A12 (a Git provider's own workspace references stay inside its
// checkout), A13 (an invalid but unselected member blocks the operation) and
// A15 (a link-free entry requirement, Windows case identity, and the
// cross-category name rule).
//
// The fixture helpers `dr_*` live in tests/dependency_resolution_tests.jai and
// are shared program-wide (the same reuse tests/dependency_resolution_git_tests.jai
// already relies on). `tprint` allocates in the temporary allocator, so any
// fixture text assembled with it is copied before a path is built from it.
// ---------------------------------------------------------------------------

// A Git provider package that exports one named constant. The package name is
// the caller's choice so a case can give two sources the same package name.
acceptance_write_git_package :: (directory: string, package_name: string, module_source: string) -> bool {
    if !dr_write_file(directory, "package.jai", dr_package_source(package_name, "")) return false;
    return dr_write_file(directory, "module.jai", module_source);
}

// A consumer whose only dependency is a Git provider selected by `selector`
// (for example `, branch = "main"` or `, rev = "<40 hex>"`) and imported as
// `Lib`. The provider's single export is `Git_Value`.
acceptance_write_git_consumer :: (app: string, url: string, selector: string) -> bool {
    body := copy_string(tprint("    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"libdep\", source = .{kind = .GIT, git = .{url = \"%1\"%2}}, modules = .[.{alias = \"Lib\"}]},\n    ],\n", url, selector));
    source := "#import \"Basic\";\n#import \"Lib\";\n\nmain :: () {\n    print(\"git=%\\n\", Git_Value);\n}\n";
    return dr_write_app(app, body, source);
}

// The same consumer with a WORKSPACE source selecting `member_path` (a
// workspace-root-relative member directory) under the same import name, so the
// two doors can be compared against the same same-named provider.
acceptance_write_workspace_consumer :: (app: string, member_path: string) -> bool {
    body := copy_string(tprint("    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"libdep\", source = .{kind = .WORKSPACE}, modules = .[.{path = \"%1\", alias = \"Lib\"}]},\n    ],\n", member_path));
    source := "#import \"Basic\";\n#import \"Lib\";\n\nmain :: () {\n    print(\"member=%\\n\", Git_Value);\n}\n";
    return dr_write_app(app, body, source);
}

// ===========================================================================
// A02: a same-named workspace member never replaces a Git source
// ===========================================================================

// The consumer belongs to a workspace that also contains a package with the
// provider's package name. Which door the declaration chose decides which
// content is compiled: the Git source keeps its repository content even though
// a same-named member exists, and the WORKSPACE source reaches the member. The
// source is a declaration fact, not a name lookup (story 24, decision 9).
acceptance_a02_member_does_not_override_git_source :: () {
    scratch := dr_scratch("a02-same-name-member");
    dr_isolate(scratch);
    defer dr_restore_env();

    repository := dr_path(scratch, "repo");
    expect(dr_git_init(repository));
    expect(acceptance_write_git_package(repository, "gitlib", "Git_Value :: 100;\n"));
    expect(dr_git_commit_all(repository, "provider").count == 40);

    workspace := dr_path(scratch, "ws");
    expect(dr_write_file(workspace, "package.jai", "#import \"Juice\";\n\nPACKAGE :: Package.{\n    workspace = .{\n        members = string.[\"packages/lib\", \"app\"],\n    },\n};\n"));
    // The member declares the SAME package name as the Git provider above.
    expect(dr_write_module_provider(dr_path(dr_path(workspace, "packages"), "lib"), "gitlib", "Git_Value :: 999;\n"));

    app := dr_path(workspace, "app");
    expect(acceptance_write_git_consumer(app, repository, ", branch = \"main\""));
    expect(dr_build_app(app) == 0);
    exit_code, run_output := dr_run_app(app);
    expect(exit_code == 0 && contains(run_output, "git=100"));

    // The same consumer, switching only the source kind, reaches the member.
    // Both providers are real and legal: only the declaration decides.
    expect(acceptance_write_workspace_consumer(app, "packages/lib"));
    expect(dr_build_app(app) == 0);
    exit_code, run_output = dr_run_app(app);
    expect(exit_code == 0 && contains(run_output, "member=999"));
} @test

// ===========================================================================
// A03: same package name from different sources / revisions
// ===========================================================================

// Two independent Git repositories both declare a package called `dupe`. Each
// exports a different symbol, so both can be imported together under explicit
// aliases: the package name is not the identity, the source is (story 34,
// decisions 9 and 11).
acceptance_a03_same_name_sources_coexist :: () {
    scratch := dr_scratch("a03-two-sources");
    dr_isolate(scratch);
    defer dr_restore_env();

    first_repository := dr_path(scratch, "first-repo");
    second_repository := dr_path(scratch, "second-repo");
    expect(dr_git_init(first_repository));
    expect(dr_git_init(second_repository));
    expect(acceptance_write_git_package(first_repository, "dupe", "From_First :: 10;\n"));
    expect(acceptance_write_git_package(second_repository, "dupe", "From_Second :: 20;\n"));
    expect(dr_git_commit_all(first_repository, "first source").count == 40);
    expect(dr_git_commit_all(second_repository, "second source").count == 40);

    app := dr_path(scratch, "app");
    body := copy_string(tprint("    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"first\", source = .{kind = .GIT, git = .{url = \"%1\"}}, modules = .[.{alias = \"First\"}]},\n        .{name = \"second\", source = .{kind = .GIT, git = .{url = \"%2\"}}, modules = .[.{alias = \"Second\"}]},\n    ],\n", first_repository, second_repository));
    source := "#import \"Basic\";\n#import \"First\";\n#import \"Second\";\n\nmain :: () {\n    print(\"sum=%\\n\", From_First + From_Second);\n}\n";
    expect(dr_write_app(app, body, source));

    expect(dr_build_app(app) == 0);
    exit_code, run_output := dr_run_app(app);
    expect(exit_code == 0 && contains(run_output, "sum=30"));
} @test

// Two revisions of ONE repository are different identities as well: the pinned
// revision and the floating branch coexist under distinct aliases and each
// compiles its own content (decision 11's identity includes the resolved
// commit).
acceptance_a03_same_name_revisions_coexist :: () {
    scratch := dr_scratch("a03-two-revisions");
    dr_isolate(scratch);
    defer dr_restore_env();

    repository := dr_path(scratch, "repo");
    expect(dr_git_init(repository));
    expect(acceptance_write_git_package(repository, "dupe", "Old_Value :: 10;\n"));
    older := copy_string(dr_git_commit_all(repository, "older"));
    expect(older.count == 40);
    expect(acceptance_write_git_package(repository, "dupe", "New_Value :: 20;\n"));
    expect(dr_git_commit_all(repository, "newer").count == 40);

    app := dr_path(scratch, "app");
    body := copy_string(tprint("    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"pinned\", source = .{kind = .GIT, git = .{url = \"%1\", rev = \"%2\"}}, modules = .[.{alias = \"Old\"}]},\n        .{name = \"floating\", source = .{kind = .GIT, git = .{url = \"%1\", branch = \"main\"}}, modules = .[.{alias = \"New\"}]},\n    ],\n", repository, older));
    source := "#import \"Basic\";\n#import \"Old\";\n#import \"New\";\n\nmain :: () {\n    print(\"sum=%\\n\", Old_Value + New_Value);\n}\n";
    expect(dr_write_app(app, body, source));

    expect(dr_build_app(app) == 0);
    exit_code, run_output := dr_run_app(app);
    expect(exit_code == 0 && contains(run_output, "sum=30"));
} @test

// ===========================================================================
// A11: content vs state — the resolution context is the project root
// ===========================================================================

// The same project at a new root is a new resolution context: it resolves the
// current selector instead of inheriting the old root's recorded commit. A
// changed cwd inside the recorded project keeps the record (decision 14,
// story 56).
acceptance_a11_moved_root_is_new_context :: () {
    scratch := dr_scratch("a11-moved-root");
    dr_isolate(scratch);
    defer dr_restore_env();

    repository := dr_path(scratch, "repo");
    expect(dr_git_init(repository));
    expect(dr_git_provider_value(repository, 100));
    first_commit := copy_string(dr_git_commit_all(repository, "first"));
    expect(first_commit.count == 40);

    original := dr_path(scratch, "original/app");
    expect(dr_write_git_app(original, repository, "Lib", ", branch = \"main\""));
    expect(dr_build_app(original) == 0);
    moved_exit, moved_output := dr_run_app(original);
    expect(moved_exit == 0 && contains(moved_output, "value=100"));
    expect(contains(dr_state_text(scratch), first_commit));

    // The branch moves after the record exists.
    expect(dr_git_provider_value(repository, 200));
    second_commit := copy_string(dr_git_commit_all(repository, "second"));
    expect(second_commit.count == 40 && second_commit != first_commit);

    // The project is recreated at a new root from its own declaration and
    // sources (a moved checkout carries no generated target/ state). A new root
    // is a new context: it resolves the current branch tip rather than reusing
    // the old root's record.
    moved := dr_path(scratch, "moved/app");
    declaration, declaration_ok := read_entire_file(dr_path(original, "package.jai"));
    source, source_ok := read_entire_file(dr_path(dr_path(original, "src"), "main.jai"));
    expect(declaration_ok && source_ok);
    expect(build_seam_write(moved, "package.jai", declaration));
    expect(build_seam_write(dr_path(moved, "src"), "main.jai", source));
    expect(!is_directory(dr_path(moved, "target")));
    expect(dr_build_app(moved) == 0);
    moved_exit, moved_output = dr_run_app(moved);
    if !(moved_exit == 0 && contains(moved_output, "value=200")) {
        print("[a11-moved-root] moved artifact exit=% output=[%]\n", moved_exit, moved_output);
    }
    expect(moved_exit == 0 && contains(moved_output, "value=200"));

    // The original root still compiles its own recorded commit.
    expect(dr_build_app(original) == 0);
    original_exit, original_output := dr_run_app(original);
    expect(original_exit == 0 && contains(original_output, "value=100"));

    // A changed cwd inside the same project does not re-resolve: invoking from
    // a source subdirectory keeps the record of the package root found upward.
    subdirectory_result, subdirectory_output, subdirectory_errors := dr_run(dr_path(original, "src"), string.["build"]);
    expect(expect_exit("a11-subdirectory-build", subdirectory_result, 0));
    expect(output_matches("a11-subdirectory-build", tprint("%\n%", subdirectory_output, subdirectory_errors), .["Compiling Target 'app'"]));
    subdirectory_exit, subdirectory_run := dr_run_app(original);
    expect(subdirectory_exit == 0 && contains(subdirectory_run, "value=100"));
} @test

// A relative XDG value is a warning and a fallback to the platform default, not
// a silent cwd-relative root and not a failure. The platform default root is
// redirected into the case's own tree so the machine's real roots are untouched
// (decision 15, story 57).
acceptance_a11_xdg_relative_falls_back :: () {
    scratch := dr_scratch("a11-xdg-fallback");
    dr_isolate(scratch);
    defer dr_restore_env();

    // The platform default root's own variable, saved and restored: the case
    // must not write into the user's real cache or state directory.
    #if OS == .WINDOWS {
        default_variable := "LOCALAPPDATA";
        cache_root := dr_path(dr_path(scratch, "platform"), "juice/cache");
        state_root := dr_path(dr_path(scratch, "platform"), "juice/state");
    } else {
        default_variable := "HOME";
        cache_root := dr_path(dr_path(scratch, "platform"), ".cache/juice");
        state_root := dr_path(dr_path(scratch, "platform"), ".local/state/juice");
    }
    saved_default := copy_string(get_env(default_variable));
    saved_default_present := saved_default != "";
    defer {
        if saved_default_present {
            dr_set_process_env(default_variable, saved_default);
        } else {
            dr_unset_process_env(default_variable);
        }
    }
    dr_set_process_env(default_variable, dr_path(scratch, "platform"));

    // Both typed roots get a relative value: the contract warns and falls back.
    dr_set_process_env("XDG_CACHE_HOME", "relative-cache");
    dr_set_process_env("XDG_STATE_HOME", "relative-state");

    app := dr_path(scratch, "app");
    expect(dr_write_file(app, "package.jai", dr_package_source("app", "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n")));
    expect(build_seam_write(dr_path(app, "src"), "main.jai", "#import \"Basic\";\n\nmain :: () {\n    print(\"fallback\\n\");\n}\n"));

    result, output, errors := dr_run(app, string.["build"]);
    combined := tprint("%\n%", output, errors);
    expect(expect_exit("a11-xdg-relative", result, 0));
    expect(output_matches("a11-xdg-relative", combined, .[
        "[juice WARNING] XDG_CACHE_HOME is not an absolute path; using the platform default content cache.",
        "[juice WARNING] XDG_STATE_HOME is not an absolute path; using the platform default resolution state.",
        "Compiling Target 'app'",
    ]));
    // The fallback root is the platform default under the redirected variable,
    // never a cwd-relative directory.
    expect(is_directory(cache_root));
    expect(is_directory(state_root));
    expect(!is_directory(dr_path(app, "relative-cache")));
    expect(!is_directory(dr_path(app, "relative-state")));
} @test

// ===========================================================================
// A12: a Git provider's own workspace references stay inside its checkout
// ===========================================================================

// A provider checked out from Git may itself belong to a workspace inside the
// repository. Its WORKSPACE source resolves against that checkout's workspace,
// never against the consuming project's members, even when the consumer has a
// member with the same name (decision 12, story 39).
acceptance_a12_git_provider_workspace_boundary :: () {
    scratch := dr_scratch("a12-provider-workspace");
    dr_isolate(scratch);
    defer dr_restore_env();

    // The provider repository: a workspace with a shared member and a provider
    // member that selects the shared member by a WORKSPACE source.
    repository := dr_path(scratch, "repo");
    expect(dr_git_init(repository));
    expect(dr_write_file(repository, "package.jai", "#import \"Juice\";\n\nPACKAGE :: Package.{\n    workspace = .{\n        members = string.[\"packages/shared\", \"packages/provider\"],\n    },\n};\n"));
    expect(dr_write_file(dr_path(dr_path(repository, "packages"), "shared"), "package.jai", dr_package_source("shared", "")));
    expect(dr_write_file(dr_path(dr_path(repository, "packages"), "shared"), "module.jai", "Shared_Value :: 5;\n"));
    provider := dr_path(dr_path(repository, "packages"), "provider");
    expect(dr_write_file(provider, "package.jai", dr_package_source("provider", "    dependencies = Dependency.[\n        .{name = \"shared\", source = .{kind = .WORKSPACE}, modules = .[.{path = \"packages/shared\", alias = \"Shared\"}]},\n    ],\n")));
    expect(dr_write_file(provider, "module.jai", "#import \"Shared\";\n\nProvider_Value :: Shared_Value * 2;\n"));
    expect(dr_git_commit_all(repository, "provider workspace").count == 40);

    // The consumer workspace has a member with the SAME name and a different
    // value, so borrowing the consumer's members would be observable.
    workspace := dr_path(scratch, "ws");
    expect(dr_write_file(workspace, "package.jai", "#import \"Juice\";\n\nPACKAGE :: Package.{\n    workspace = .{\n        members = string.[\"members/shared\", \"app\"],\n    },\n};\n"));
    expect(dr_write_module_provider(dr_path(dr_path(workspace, "members"), "shared"), "shared", "Shared_Value :: 500;\n"));

    app := dr_path(workspace, "app");
    body := copy_string(tprint("    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"provider\", source = .{kind = .GIT, git = .{url = \"%1\"}}, modules = .[.{path = \"packages/provider\", alias = \"Prov\"}]},\n    ],\n", repository));
    provider_source := "#import \"Basic\";\n#import \"Prov\";\n\nmain :: () {\n    print(\"value=%\\n\", Provider_Value);\n}\n";
    expect(dr_write_app(app, body, provider_source));
    expect(dr_build_app(app) == 0);
    exit_code, run_output := dr_run_app(app);
    expect(exit_code == 0 && contains(run_output, "value=10"));

    // A WORKSPACE selection that names a consumer-only member is not a member of
    // the provider's own checkout, so it fails instead of reaching outwards.
    expect(dr_write_file(provider, "package.jai", dr_package_source("provider", "    dependencies = Dependency.[\n        .{name = \"shared\", source = .{kind = .WORKSPACE}, modules = .[.{path = \"members/shared\", alias = \"Shared\"}]},\n    ],\n")));
    expect(dr_git_commit_all(repository, "consumer member reference").count == 40);
    escaping := dr_path(scratch, "escaping-app");
    expect(dr_write_app(escaping, body, provider_source));
    escape_result, escape_output, escape_errors := dr_run(escaping, string.["build"]);
    escape_combined := tprint("%\n%", escape_output, escape_errors);
    expect(escape_result.exit_code != 0);
    expect(contains(escape_combined, "not a workspace member") || contains(escape_combined, "WORKSPACE path escapes") || contains(escape_combined, "workspace"));
} @test

// ===========================================================================
// A13: an unselected invalid member still blocks the operation
// ===========================================================================

// Discovery validates every member declaration before any command work, so a
// broken member fails a command that selected a different package, and no
// artifact is produced for the healthy one (decision 20, story 65).
acceptance_a13_unselected_invalid_member_blocks :: () {
    scratch := dr_scratch("a13-invalid-member");
    dr_isolate(scratch);
    defer dr_restore_env();

    workspace := dr_path(scratch, "ws");
    expect(dr_write_file(workspace, "package.jai", "#import \"Juice\";\n\nPACKAGE :: Package.{\n    workspace = .{\n        members = string.[\"good\", \"broken\"],\n    },\n};\n"));
    good := dr_path(workspace, "good");
    expect(dr_write_file(good, "package.jai", dr_package_source("good", "    executables = .[.{name = \"good\", entry = \"src/main.jai\"}],\n")));
    expect(build_seam_write(dr_path(good, "src"), "main.jai", "#import \"Basic\";\n\nmain :: () {\n    print(\"good\\n\");\n}\n"));
    // The unselected member carries a retired field, which the Jai compiler
    // rejects while the declaration is evaluated.
    broken := dr_path(workspace, "broken");
    expect(dr_write_file(broken, "package.jai", "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"broken\",\n    version = \"0.1.0\",\n    type    = .BIN,\n};\n"));
    expect(build_seam_write(dr_path(broken, "src"), "main.jai", "#import \"Basic\";\n\nmain :: () {\n    print(\"broken\\n\");\n}\n"));

    // Selecting only the healthy package still fails: the member set is
    // validated as a whole before the selection runs.
    result, output, errors := dr_run(workspace, string.["build", "-p", "good"]);
    combined := tprint("%\n%", output, errors);
    expect(result.exit_code != 0);
    expect(contains(combined, "'type' is not a member of Package"));
    expect(contains(combined, "broken"));
    expect(!file_exists(target_artifact_path(package_target_dir(good), "good")));

    // The same is true for run and test: no partial command work happens.
    run_result, run_output, run_errors := dr_run(workspace, string.["run", "-p", "good"]);
    expect(run_result.exit_code != 0);
    expect(contains(tprint("%\n%", run_output, run_errors), "'type' is not a member of Package"));
    test_result, test_output, test_errors := dr_run(workspace, string.["test", "-p", "good"]);
    expect(test_result.exit_code != 0);
    expect(contains(tprint("%\n%", test_output, test_errors), "'type' is not a member of Package"));
} @test

// ===========================================================================
// A15: entry links, Windows case identity, cross-category names
// ===========================================================================

// A product entry must be a regular link-free file: an entry that enters
// through a directory link is rejected by the real command (decision 8).
acceptance_a15_entry_through_link_is_rejected :: () {
    scratch := dr_scratch("a15-entry-link");
    dr_isolate(scratch);
    defer dr_restore_env();

    package_directory := dr_path(scratch, "linked");
    expect(dr_write_file(package_directory, "package.jai", dr_package_source("linked", "    executables = .[.{name = \"linked\", entry = \"via_link/main.jai\"}],\n")));
    expect(build_seam_write(dr_path(package_directory, "real"), "main.jai", "#import \"Basic\";\n\nmain :: () {\n    print(\"linked\\n\");\n}\n"));

    #if OS == .WINDOWS {
        link_ok := make_test_link(tprint("%1/via_link", package_directory), tprint("%1/real", package_directory), true, true);
        if !link_ok {
            print("SKIP: directory junction creation unavailable on this machine\n");
            return;
        }
    } else {
        link_ok := run_command("ln", "-s", tprint("%1/real", package_directory), tprint("%1/via_link", package_directory)).exit_code == 0;
        if !link_ok {
            print("SKIP: symbolic link creation unavailable\n");
            return;
        }
    }

    result, output, errors := dr_run(package_directory, string.["build"]);
    combined := tprint("%\n%", output, errors);
    expect(result.exit_code != 0);
    expect(contains(combined, "Product entry is not a regular link-free file: via_link/main.jai"));
    expect(!file_exists(target_artifact_path(package_target_dir(package_directory), "linked")));
} @test

// Windows aliases the same file through another case spelling; the physical
// identity is what the tool compares, so a differently-cased entry path names
// the same regular file and builds. On a case-sensitive filesystem the same
// spelling is a different (absent) file, so this half is Windows-only and is
// reported as unverified there (decision 8, story 105).
acceptance_a15_case_identity_and_cross_category_names :: () {
    scratch := dr_scratch("a15-case-identity");
    dr_isolate(scratch);
    defer dr_restore_env();

    // One package declaring a module and an executable with the SAME name: the
    // two name spaces are separate (decision 6, story 14).
    package_directory := dr_path(scratch, "cased");
    expect(dr_write_file(package_directory, "package.jai", dr_package_source("cased", "    modules = .[.{name = \"tool\", entry = \"tool.jai\"}],\n    executables = .[.{name = \"tool\", entry = \"SRC/main.jai\"}],\n")));
    expect(dr_write_file(package_directory, "tool.jai", "Tool_Value :: 3;\n"));
    expect(build_seam_write(dr_path(package_directory, "src"), "main.jai", "#import \"Basic\";\n#import \"tool\";\n\nmain :: () {\n    print(\"tool=%\\n\", Tool_Value);\n}\n"));

    result, output, errors := dr_run(package_directory, string.["build"]);
    combined := tprint("%\n%", output, errors);
    #if OS == .WINDOWS {
        expect(expect_exit("a15-case-identity", result, 0));
        expect(output_matches("a15-case-identity", combined, .["Compiling Target 'tool'"]));
        expect(file_exists(target_artifact_path(package_target_dir(package_directory), "tool")));
        artifact_result, artifact_output, _, _ := run_command(target_artifact_path(package_target_dir(package_directory), "tool"), capture_and_return_output = true);
        expect(expect_exit("a15-case-identity-artifact", artifact_result, 0));
        expect(contains(artifact_output, "tool=3"));
    } else {
        // A case-sensitive filesystem treats SRC/main.jai as a different file
        // that does not exist: the entry must be rejected, not guessed.
        expect(result.exit_code != 0);
        expect(contains(combined, "Product entry"));
    }
} @test
