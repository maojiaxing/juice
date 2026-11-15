#import "Basic";
#import "Testing";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";

// ---------------------------------------------------------------------------
// Final-review regressions (issue 0098, spec 0087 decisions 11-12/14-15/20).
// Each case runs the real executable over a temporary project with its own
// isolated XDG roots and, where Git is involved, a real local repository. The
// shared fixture helpers live in tests/dependency_resolution_tests.jai.
//
// These cases pin package-scoped import ownership (a member's dependency names
// and own modules are not visible to a sibling member), the initiating-consumer
// resolution context (two consumers sharing one provider keep independent
// transitive Git selections) and Git provenance across a provider's internal
// PATH edges.
// ---------------------------------------------------------------------------

fr_write_package :: (dir: string, name: string, body: string) -> bool {
    return dr_write_file(dir, "package.jai", dr_package_source(name, body));
}

fr_write_program :: (dir: string, name: string, body: string, source: string) -> bool {
    if !fr_write_package(dir, name, body) return false;
    return dr_write_file(dr_path(dir, "src"), "main.jai", source);
}

fr_pure_workspace_root :: (root: string) -> bool {
    return dr_write_file(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{workspace = .{members = .[\"members/*\"]}};\n");
}

// A local PATH dependency body fragment for a provider directory.
fr_path_dependency :: (reference_name: string, provider_dir: string, alias: string) -> string {
    return copy_string(tprint("    dependencies = Dependency.[\n        .{name = \"%1\", source = .{kind = .PATH, path = %2}, modules = .[.{alias = \"%3\"}]},\n    ],\n", reference_name, quote_jai_string(provider_dir), alias));
}

// ---------------------------------------------------------------------------
// S03: a dependency import name belongs to the package that declared it. A
// sibling member that never declared it cannot import it, with or without the
// declaring member in the same batch.
// ---------------------------------------------------------------------------
final_review_member_imports_are_package_scoped :: () {
    scratch := dr_scratch("fr-member-visibility");
    dr_isolate(scratch);
    defer dr_restore_env();
    secret_one := dr_path(scratch, "secret_one");
    expect(dr_write_module_provider(secret_one, "secret_one", "Secret_Value :: 11;\n"));
    root := dr_path(scratch, "workspace");
    expect(fr_pure_workspace_root(root));
    alpha := dr_path(root, "members/alpha");
    expect(fr_write_program(alpha, "alpha", fr_path_dependency("secret_one", secret_one, "Secret"), "#import \"Basic\";\n#import \"Secret\";\n\nmain :: () { print(\"ALPHA_SECRET=%\\n\", Secret_Value); }\n"));
    beta := dr_path(root, "members/beta");
    expect(fr_write_program(beta, "beta", "    executables = .[.{name = \"beta\", entry = \"src/main.jai\"}],\n", "#import \"Basic\";\n#import \"Secret\";\n\nmain :: () { print(\"BETA_SECRET=%\\n\", Secret_Value); }\n"));

    // The declaring member resolves its own dependency.
    alpha_run, alpha_output, alpha_errors := dr_run(alpha, string.["run"]);
    expect(expect_exit("member-own-dependency", alpha_run, 0));
    expect(contains(alpha_output, "ALPHA_SECRET=11"));
    // The import shim lives in the declaring package's private zone, never in
    // a directory its siblings search.
    expect(file_exists(tprint("%1/Secret.jai", dependency_imports_dir(alpha))));
    expect(!file_exists(tprint("%1/Secret.jai", dependency_imports_dir(root))));

    // The sibling member never sees the name -- alone or in the same batch.
    beta_result, beta_output, beta_errors := dr_run(beta, string.["build"]);
    expect(beta_result.exit_code != 0);
    beta_combined := tprint("%\n%", beta_output, beta_errors);
    expect(contains(beta_combined, "Secret"));

    batch_result, batch_output, batch_errors := dr_run(root, string.["build", "--workspace"]);
    expect(batch_result.exit_code != 0);
    batch_combined := tprint("%\n%", batch_output, batch_errors);
    expect(contains(batch_combined, "Secret"));
    // The declaring member completed before the failing member stops the batch.
    expect(contains(batch_combined, "build: completed members/alpha"));
} @test

// A member's own modules are that member's import names only. The workspace
// root package's modules never become a member's import names.
final_review_root_modules_are_not_member_imports :: () {
    scratch := dr_scratch("fr-root-visibility");
    dr_isolate(scratch);
    defer dr_restore_env();
    root := dr_path(scratch, "workspace");
    expect(dr_write_file(root, "package.jai", "#import \"Juice\";\nPACKAGE :: Package.{name = \"root\", version = \"1\", modules = .[{name = \"RootApi\", entry = \"src/root_api.jai\"}], workspace = .{members = .[\"members/*\"]}};\n"));
    expect(dr_write_file(dr_path(root, "src"), "root_api.jai", "Root_Value :: 5;\n"));
    member := dr_path(root, "members/alpha");
    expect(fr_write_program(member, "alpha", "    executables = .[.{name = \"alpha\", entry = \"src/main.jai\"}],\n", "#import \"Basic\";\n#import \"RootApi\";\n\nmain :: () { print(\"MEMBER_ROOT=%\\n\", Root_Value); }\n"));

    result, output, errors := dr_run(member, string.["build"]);
    expect(result.exit_code != 0);
    combined := tprint("%\n%", output, errors);
    expect(contains(combined, "RootApi"));
} @test

// Two members may give different providers the same local alias: the alias is
// package-scoped, not a batch-wide namespace.
final_review_members_may_share_an_alias :: () {
    scratch := dr_scratch("fr-shared-alias");
    dr_isolate(scratch);
    defer dr_restore_env();
    provider_one := dr_path(scratch, "provider_one");
    expect(dr_write_module_provider(provider_one, "provider_one", "Data_Value :: 1;\n"));
    provider_two := dr_path(scratch, "provider_two");
    expect(dr_write_module_provider(provider_two, "provider_two", "Data_Value :: 2;\n"));
    root := dr_path(scratch, "workspace");
    expect(fr_pure_workspace_root(root));
    alpha := dr_path(root, "members/alpha");
    expect(fr_write_program(alpha, "alpha", fr_path_dependency("provider_one", provider_one, "Data"), "#import \"Basic\";\n#import \"Data\";\n\nmain :: () { print(\"ALPHA_DATA=%\\n\", Data_Value); }\n"));
    beta := dr_path(root, "members/beta");
    expect(fr_write_program(beta, "beta", fr_path_dependency("provider_two", provider_two, "Data"), "#import \"Basic\";\n#import \"Data\";\n\nmain :: () { print(\"BETA_DATA=%\\n\", Data_Value); }\n"));

    batch_result, batch_output, batch_errors := dr_run(root, string.["build", "--workspace"]);
    expect(expect_exit("members-share-alias", batch_result, 0));

    alpha_run, alpha_output, alpha_errors := dr_run(alpha, string.["run"]);
    expect(expect_exit("alpha-alias-value", alpha_run, 0));
    expect(contains(alpha_output, "ALPHA_DATA=1"));
    beta_run, beta_output, beta_errors := dr_run(beta, string.["run"]);
    expect(expect_exit("beta-alias-value", beta_run, 0));
    expect(contains(beta_output, "BETA_DATA=2"));
} @test

// ---------------------------------------------------------------------------
// S08: a provider package validates its own module identities and import names
// exactly like a consumer: two different modules cannot share one import name,
// one actual module cannot be selected twice, and a dependency import name may
// not shadow the provider's own export.
// ---------------------------------------------------------------------------
final_review_provider_import_name_collision :: () {
    scratch := dr_scratch("fr-provider-alias");
    dr_isolate(scratch);
    defer dr_restore_env();
    one := dr_path(scratch, "one");
    expect(dr_write_module_provider(one, "one", "Data_Value :: 1;\n"));
    two := dr_path(scratch, "two");
    expect(dr_write_module_provider(two, "two", "Data_Value :: 2;\n"));
    middle := dr_path(scratch, "middle");
    middle_body := copy_string(tprint("    dependencies = Dependency.[\n        .{name = \"one\", source = .{kind = .PATH, path = %1}, modules = .[.{alias = \"Data\"}]},\n        .{name = \"two\", source = .{kind = .PATH, path = %2}, modules = .[.{alias = \"Data\"}]},\n    ],\n", quote_jai_string(one), quote_jai_string(two)));
    expect(fr_write_package(middle, "middle", middle_body));
    expect(dr_write_file(middle, "module.jai", "#import \"Data\";\nMiddle_Value :: () -> s64 { return Data_Value; }\n"));
    app := dr_path(scratch, "app");
    app_body := tprint("%1    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n", fr_path_dependency("middle", middle, "Middle"));
    expect(fr_write_program(app, "app", app_body, "#import \"Basic\";\n#import \"Middle\";\n\nmain :: () { print(\"MIDDLE=%\\n\", Middle_Value()); }\n"));

    result, output, errors := dr_run(app, string.["build"]);
    expect(result.exit_code != 0);
    combined := tprint("%\n%", output, errors);
    expect(contains(combined, "declared twice") || contains(combined, "two different modules"));
} @test

final_review_provider_duplicate_module_selection :: () {
    scratch := dr_scratch("fr-provider-duplicate");
    dr_isolate(scratch);
    defer dr_restore_env();
    one := dr_path(scratch, "one");
    expect(dr_write_module_provider(one, "one", "Data_Value :: 1;\n"));
    middle := dr_path(scratch, "middle");
    middle_body := copy_string(tprint("    dependencies = Dependency.[\n        .{name = \"first\", source = .{kind = .PATH, path = %1}, modules = .[.{alias = \"Data\"}]},\n        .{name = \"second\", source = .{kind = .PATH, path = %1}, modules = .[.{alias = \"Other\"}]},\n    ],\n", quote_jai_string(one)));
    expect(fr_write_package(middle, "middle", middle_body));
    expect(dr_write_file(middle, "module.jai", "#import \"Data\";\nMiddle_Value :: () -> s64 { return Data_Value; }\n"));
    app := dr_path(scratch, "app");
    app_body := tprint("%1    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n", fr_path_dependency("middle", middle, "Middle"));
    expect(fr_write_program(app, "app", app_body, "#import \"Basic\";\n#import \"Middle\";\n\nmain :: () { print(\"MIDDLE=%\\n\", Middle_Value()); }\n"));

    result, output, errors := dr_run(app, string.["build"]);
    expect(result.exit_code != 0);
    combined := tprint("%\n%", output, errors);
    expect(contains(combined, "selected more than once"));
} @test

// ---------------------------------------------------------------------------
// S16a: a local PATH source is anchored at the declaring package and may point
// outside the consumer root's parent directory. No consumer-parent ceiling.
// ---------------------------------------------------------------------------
final_review_local_path_is_not_parent_bounded :: () {
    scratch := dr_scratch("fr-local-path");
    dr_isolate(scratch);
    defer dr_restore_env();
    library := dr_path(scratch, "libs/core");
    expect(dr_write_module_provider(library, "core", "Core_Value :: 34;\n"));
    app := dr_path(scratch, "apps/cli");
    app_body := tprint("%1    executables = .[.{name = \"cli\", entry = \"src/main.jai\"}],\n", fr_path_dependency("core", library, "Core"));
    expect(fr_write_program(app, "cli", app_body, "#import \"Basic\";\n#import \"Core\";\n\nmain :: () { print(\"CLI_CORE=%\\n\", Core_Value); }\n"));

    result, output, errors := dr_run(app, string.["run"]);
    expect(expect_exit("local-path-sibling", result, 0));
    expect(contains(output, "CLI_CORE=34"));
} @test

// ---------------------------------------------------------------------------
// S05: a provider inside a Git checkout keeps its repository/commit provenance
// across internal PATH edges, so a multi-package checkout resolves inside the
// checkout instead of falling back to a consumer-local boundary.
// ---------------------------------------------------------------------------
final_review_git_internal_path_chain :: () {
    scratch := dr_scratch("fr-git-chain");
    dr_isolate(scratch);
    defer dr_restore_env();
    repository := dr_path(scratch, "provider-repo");
    expect(dr_git_init(repository));
    // pkg_c exports 7; pkg_b depends on pkg_c by an internal PATH edge; pkg_a
    // depends on pkg_b the same way and returns the chained value.
    expect(dr_write_module_provider(dr_path(repository, "pkg_c"), "pkg_c", "C_Value :: 7;\n"));
    expect(fr_write_package(dr_path(repository, "pkg_b"), "pkg_b", fr_path_dependency("pkg_c", "../pkg_c", "C")));
    expect(dr_write_file(dr_path(repository, "pkg_b"), "module.jai", "#import \"C\";\nB_Value :: () -> s64 { return C_Value; }\n"));
    expect(fr_write_package(dr_path(repository, "pkg_a"), "pkg_a", fr_path_dependency("pkg_b", "../pkg_b", "B")));
    expect(dr_write_file(dr_path(repository, "pkg_a"), "module.jai", "#import \"B\";\nA_Value :: () -> s64 { return B_Value() + 1; }\n"));
    commit := copy_string(dr_git_commit_all(repository, "chain"));
    expect(commit.count == 40);

    app := dr_path(scratch, "app");
    body := copy_string(tprint("    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"chain\", source = .{kind = .GIT, git = .{url = %1}}, modules = .[.{path = \"pkg_a\", name = \"pkg_a\", alias = \"A\"}]},\n    ],\n", quote_jai_string(repository)));
    expect(fr_write_program(app, "app", body, "#import \"Basic\";\n#import \"A\";\n\nmain :: () { print(\"CHAIN=%\\n\", A_Value()); }\n"));

    result, output, errors := dr_run(app, string.["run"]);
    expect(expect_exit("git-internal-chain", result, 0));
    expect(contains(output, "CHAIN=8"));
} @test

// ---------------------------------------------------------------------------
// S04: two consuming members that share one local provider keep independent
// transitive Git selections. Updating one member's graph never rewrites the
// other member's ordinary build.
// ---------------------------------------------------------------------------
final_review_consumer_contexts_are_independent :: () {
    scratch := dr_scratch("fr-consumer-context");
    dr_isolate(scratch);
    defer dr_restore_env();
    crypto := dr_path(scratch, "crypto-repo");
    expect(dr_git_init(crypto));
    expect(dr_write_module_provider(crypto, "crypto", "Crypto_Value :: 1;\n"));
    first_commit := copy_string(dr_git_commit_all(crypto, "crypto first"));
    expect(first_commit.count == 40);
    http := dr_path(scratch, "http");
    http_body := copy_string(tprint("    dependencies = Dependency.[\n        .{name = \"crypto\", source = .{kind = .GIT, git = .{url = %1, branch = \"main\"}}, modules = .[.{alias = \"Crypto\"}]},\n    ],\n", quote_jai_string(crypto)));
    expect(fr_write_package(http, "http", http_body));
    expect(dr_write_file(http, "module.jai", "#import \"Crypto\";\nHttp_Value :: () -> s64 { return Crypto_Value; }\n"));

    root := dr_path(scratch, "workspace");
    expect(fr_pure_workspace_root(root));
    alpha := dr_path(root, "members/alpha");
    alpha_body := tprint("%1    executables = .[.{name = \"alpha\", entry = \"src/main.jai\"}],\n", fr_path_dependency("http", http, "HttpLib"));
    expect(fr_write_program(alpha, "alpha", alpha_body, "#import \"Basic\";\n#import \"HttpLib\";\n\nmain :: () { print(\"ALPHA=%\\n\", Http_Value()); }\n"));
    beta := dr_path(root, "members/beta");
    beta_body := tprint("%1    executables = .[.{name = \"beta\", entry = \"src/main.jai\"}],\n", fr_path_dependency("http", http, "HttpLib"));
    expect(fr_write_program(beta, "beta", beta_body, "#import \"Basic\";\n#import \"HttpLib\";\n\nmain :: () { print(\"BETA=%\\n\", Http_Value()); }\n"));

    alpha_first, alpha_first_output, alpha_first_errors := dr_run(alpha, string.["run"]);
    expect(expect_exit("alpha-first", alpha_first, 0));
    expect(contains(alpha_first_output, "ALPHA=1"));
    beta_first, beta_first_output, beta_first_errors := dr_run(beta, string.["run"]);
    expect(expect_exit("beta-first", beta_first, 0));
    expect(contains(beta_first_output, "BETA=1"));

    // The provider's transitive source moves; only alpha updates.
    expect(dr_write_module_provider(crypto, "crypto", "Crypto_Value :: 2;\n"));
    second_commit := copy_string(dr_git_commit_all(crypto, "crypto second"));
    expect(second_commit.count == 40 && second_commit != first_commit);
    alpha_update, alpha_update_output, alpha_update_errors := dr_run(alpha, string.["update"]);
    expect(expect_exit("alpha-update", alpha_update, 0));

    alpha_second, alpha_second_output, alpha_second_errors := dr_run(alpha, string.["run"]);
    expect(expect_exit("alpha-second", alpha_second, 0));
    expect(contains(alpha_second_output, "ALPHA=2"));

    // beta never updated, so its ordinary build keeps its own selection.
    beta_second, beta_second_output, beta_second_errors := dr_run(beta, string.["run"]);
    expect(expect_exit("beta-second", beta_second, 0));
    expect(contains(beta_second_output, "BETA=1"));
    expect(!contains(beta_second_output, "BETA=2"));
} @test

// ---------------------------------------------------------------------------
// S13: every enabled external plugin is validated through its real module
// value — entry uniqueness across the selected module's #load closure, entry
// ABI and options — regardless of whether the entry mentions hooks. The review
// probes 16-24 (plugin-verification.md) recorded the pre-fix behavior: ABI 999
// and unknown options without hooks built successfully, and a #load-only entry
// with its single real plugin value was rejected as capability-missing.
// ---------------------------------------------------------------------------

FR_PLUGIN_HEADER :: #string FR_END
#import "Basic";
#import "juice_core";

FR_Plugin_Options :: struct {
    label: string = "default";
}

FR_Plugin :: struct {
    using base: Juice_Plugin;
    config: FR_Plugin_Options;
}

get_juice_plugin :: () -> *FR_Plugin {
    plugin := New(FR_Plugin);
    plugin.id = "fr_plugin";
    plugin.version = "1.0.0";
FR_END

// A valid plugin that contributes no hooks at all.
fr_plugin_no_hooks_source :: () -> string {
    return tprint("%1    plugin.options = cast(*void) plugin;\n    return plugin;\n} @juice_plugin\n", FR_PLUGIN_HEADER);
}

// Same shape, but compiled value claims a foreign entry ABI.
fr_plugin_bad_abi_source :: () -> string {
    return tprint("%1    plugin.options = cast(*void) plugin;\n    plugin.abi_version = 999;\n    return plugin;\n} @juice_plugin\n", FR_PLUGIN_HEADER);
}

fr_write_plugin_provider :: (provider: string, module_source: string) -> bool {
    if !fr_write_package(provider, "fr_plugin_provider", "    modules = .[.{name = \"plugin_module\", entry = \"plugin.jai\"}],\n") return false;
    return dr_write_file(provider, "plugin.jai", module_source);
}

fr_write_plugin_consumer :: (app: string, provider: string, options_field: string) -> bool {
    plugins := copy_string(tprint("    plugins = Plugin_Declaration.[.{id = \"fr_plugin\", source = .{kind = .PATH, path = %1}, module = .{name = \"plugin_module\"}%2}],\n", quote_jai_string(provider), options_field));
    return fr_write_program(app, "plugin_app", tprint("%1    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n", plugins), "#import \"Basic\";\n\nmain :: () { print(\"PLUGIN_APP_OK\\n\"); }\n");
}

final_review_no_hook_plugin_is_validated :: () {
    scratch := dr_scratch("fr-plugin-valid");
    dr_isolate(scratch);
    defer dr_restore_env();
    provider := dr_path(scratch, "provider");
    expect(fr_write_plugin_provider(provider, fr_plugin_no_hooks_source()));
    app := dr_path(scratch, "app");
    expect(fr_write_plugin_consumer(app, provider, ""));

    result, output, errors := dr_run(app, string.["run"]);
    if result.exit_code != 0 print("[fr] valid-no-hook child:\n%\n%\n", output, errors);
    expect(expect_exit("valid-no-hook-plugin", result, 0));
    expect(contains(output, "PLUGIN_APP_OK"));

    // The same plugin module with a foreign ABI must fail before anything runs.
    expect(dr_write_file(provider, "plugin.jai", fr_plugin_bad_abi_source()));
    bad_result, bad_output, bad_errors := dr_run(app, string.["build"]);
    expect(bad_result.exit_code != 0);
    bad_combined := tprint("%\n%", bad_output, bad_errors);
    expect(contains(bad_combined, "ABI") || contains(bad_combined, "incompatible"));
} @test

final_review_no_hook_plugin_rejects_unknown_options :: () {
    scratch := dr_scratch("fr-plugin-options");
    dr_isolate(scratch);
    defer dr_restore_env();
    provider := dr_path(scratch, "provider");
    expect(fr_write_plugin_provider(provider, fr_plugin_no_hooks_source()));
    app := dr_path(scratch, "app");
    expect(fr_write_plugin_consumer(app, provider, ", options = .[{key = \"bogus\", value = \"1\"}]"));

    result, output, errors := dr_run(app, string.["build"]);
    expect(result.exit_code != 0);
    combined := tprint("%\n%", output, errors);
    expect(contains(combined, "bogus") || contains(combined, "unknown"));
} @test

final_review_plugin_entry_through_load_closure :: () {
    scratch := dr_scratch("fr-plugin-closure");
    dr_isolate(scratch);
    defer dr_restore_env();
    provider := dr_path(scratch, "provider");
    // The selected module entry only #loads its implementation, which carries
    // the module's single get_juice_plugin value.
    expect(fr_write_plugin_provider(provider, "#load \"implementation.jai\";\n"));
    expect(dr_write_file(provider, "implementation.jai", fr_plugin_no_hooks_source()));
    app := dr_path(scratch, "app");
    expect(fr_write_plugin_consumer(app, provider, ""));

    result, output, errors := dr_run(app, string.["run"]);
    if result.exit_code != 0 print("[fr] load-closure child:\n%\n%\n", output, errors);
    expect(expect_exit("plugin-entry-through-load", result, 0));
    expect(contains(output, "PLUGIN_APP_OK"));
} @test
