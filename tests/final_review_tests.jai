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
    plugin.id = FR_PLUGIN_ID;
    plugin.version = "1.0.0";
FR_END

// One plugin module source. The plugin VALUE's id must equal the enabled
// declaration's id (the host matches them), so the id is a fixture parameter.
fr_plugin_source :: (plugin_id: string, extra := "") -> string {
    return tprint("FR_PLUGIN_ID :: %1;\n%2    plugin.options = cast(*void) plugin;\n%3    return plugin;\n} @juice_plugin\n", quote_jai_string(plugin_id), FR_PLUGIN_HEADER, extra);
}

// A valid plugin that contributes no hooks at all.
fr_plugin_no_hooks_source :: (plugin_id := "fr_plugin") -> string {
    return fr_plugin_source(plugin_id);
}

// Same shape, but the compiled value claims a foreign entry ABI.
fr_plugin_bad_abi_source :: (plugin_id := "fr_plugin") -> string {
    return fr_plugin_source(plugin_id, "    plugin.abi_version = 999;\n");
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

// ---------------------------------------------------------------------------
// S12: a plugin enablement owns a private import name. The review probes 13-15
// recorded the pre-fix behavior: an ordinary dependency aliased `Tool` returned
// 7, enabling a plugin whose id was `Tool` changed the app to 99, and enabling
// that plugin alone made `#import "Tool"` succeed. A plugin id must never
// overwrite a business alias, and enabling a plugin must add no ordinary import
// name.
// ---------------------------------------------------------------------------

fr_write_value_provider :: (provider: string, name: string, value: s64) -> bool {
    return dr_write_module_provider(provider, name, tprint("Get_Value :: () -> s64 { return %; }\n", value));
}

// A plugin module that ALSO exports `Get_Value` returning 99. The review
// probes needed this: the pre-fix shim was named after the declaration id and
// re-exported the provider module, so `#import "Tool"` reached 99 whether the
// plugin overwrote a business alias or stood alone.
fr_write_value_plugin :: (provider: string, plugin_id: string) -> bool {
    source := tprint("Get_Value :: () -> s64 { return 99; }\n%1", fr_plugin_source(plugin_id));
    if !fr_write_package(provider, "fr_plugin_provider", "    modules = .[.{name = \"plugin_module\", entry = \"plugin.jai\"}],\n") return false;
    return dr_write_file(provider, "plugin.jai", source);
}

final_review_plugin_id_cannot_overwrite_business_alias :: () {
    scratch := dr_scratch("fr-plugin-alias");
    dr_isolate(scratch);
    defer dr_restore_env();
    business := dr_path(scratch, "business");
    expect(fr_write_value_provider(business, "business", 7));
    plugin_provider := dr_path(scratch, "plugin_provider");
    expect(fr_write_value_plugin(plugin_provider, "Tool"));

    // Control: the ordinary alias resolves to the business provider (7).
    app_body := tprint("%1    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n", fr_path_dependency("business", business, "Tool"));
    expect(fr_write_program(dr_path(scratch, "app"), "plugin_app", app_body, "#import \"Basic\";\n#import \"Tool\";\n\nmain :: () { print(\"API=%\\n\", Get_Value()); }\n"));
    app := dr_path(scratch, "app");
    control, control_output, control_errors := dr_run(app, string.["run"]);
    if control.exit_code != 0 print("[fr] alias control:'+chr(92)+'n%'+chr(92)+'n%'+chr(92)+'n", control_output, control_errors);
    expect(expect_exit("plugin-alias-control", control, 0));
    expect(contains(control_output, "API=7"));

    // Enabling a plugin whose DECLARATION ID is `Tool` must not touch it.
    plugins := copy_string(tprint("    plugins = Plugin_Declaration.[.{id = \"Tool\", source = .{kind = .PATH, path = %1}, module = .{name = \"plugin_module\"}}],\n", quote_jai_string(plugin_provider)));
    with_plugin := tprint("%1%2    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n", fr_path_dependency("business", business, "Tool"), plugins);
    expect(fr_write_program(app, "plugin_app", with_plugin, "#import \"Basic\";\n#import \"Tool\";\n\nmain :: () { print(\"API=%\\n\", Get_Value()); }\n"));
    collision, collision_output, collision_errors := dr_run(app, string.["run"]);
    if collision.exit_code != 0 print("[fr] collision:'+chr(92)+'n%'+chr(92)+'n%'+chr(92)+'n", collision_output, collision_errors);
    expect(expect_exit("plugin-alias-collision", collision, 0));
    expect(contains(collision_output, "API=7"));
    expect(!contains(collision_output, "API=99"));
} @test

final_review_plugin_alone_exposes_no_ordinary_import :: () {
    scratch := dr_scratch("fr-plugin-exposure");
    dr_isolate(scratch);
    defer dr_restore_env();
    plugin_provider := dr_path(scratch, "plugin_provider");
    expect(fr_write_value_plugin(plugin_provider, "Tool"));
    app := dr_path(scratch, "app");
    // No ordinary dependency at all: only the plugin enablement names `Tool`.
    plugins := copy_string(tprint("    plugins = Plugin_Declaration.[.{id = \"Tool\", source = .{kind = .PATH, path = %1}, module = .{name = \"plugin_module\"}}],\n", quote_jai_string(plugin_provider)));
    expect(fr_write_program(app, "plugin_app", tprint("%1    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n", plugins), "#import \"Basic\";\n#import \"Tool\";\n\nmain :: () { print(\"API=%\\n\", Get_Value()); }\n"));

    result, output, errors := dr_run(app, string.["build"]);
    expect(result.exit_code != 0);
    combined := tprint("%\n%", output, errors);
    expect(contains(combined, "Tool"));
    // Nothing was compiled by accident; the enablement itself is valid.
    expect(!file_exists(tprint("%1/Tool.jai", dependency_imports_dir(app))));
    expect(!file_exists(tprint("%1/Tool.jai", packages_dir(app))));
} @test

// ---------------------------------------------------------------------------
// S09: the generated test program belongs to the package being tested. Review
// probes 03/04/09 recorded the pre-fix behavior: a member's test program ran
// with the WORKSPACE ROOT's plugin configs and diagnostic paths, so the member
// declaration was silently ignored and the member's own lint never ran.
//
// The fixture plugin below carries one lint rule and one option row. Its
// validator ACCEPTS marker "member" and REJECTS marker "root", so a run that
// resolved the root's declaration fails loudly; its lint rule reports an ERROR
// naming the test, so a run that skipped the member's lint cannot exit nonzero
// with that message.
// ---------------------------------------------------------------------------

S09_PLUGIN_SOURCE :: #string S09_END
#import "Basic";
#import "Compiler";
#import "juice_core";

S09_Plugin :: struct {
    using base: Juice_Plugin;
    marker: string;
}

S09_DEFAULT_MARKER: string = "";

s09_apply_option :: (options: *void, key: string, value: string) -> string {
    plugin := cast(*S09_Plugin) options;
    if key == "marker" {
        plugin.marker = value;
        return "";
    }
    return tprint("unknown option '%'", key);
}

s09_validate_options :: (options: *void) -> string {
    plugin := cast(*S09_Plugin) options;
    if plugin.marker == "root" return "S09 root config used";
    return "";
}

s09_inspect :: (header: *Code_Procedure_Header, subexpressions: [] *Code_Node) -> [..] Lint_Finding {
    findings: [..] Lint_Finding;
    if header.name != "BadTestOne" return findings;
    array_add(*findings, .{
        line    = cast(s64) header.l0,
        column  = cast(s64) header.c0,
        message = tprint("S09 member lint ran: %", header.name),
        level   = .ERROR,
    });
    return findings;
}

get_juice_plugin :: () -> *S09_Plugin {
    plugin := New(S09_Plugin);
    plugin.id = "s09_lint";
    plugin.version = "1.0.0";
    plugin.options = cast(*void) plugin;
    lint := New(Lint_Plugin);
    lint.name = "s09_lint_rule";
    lint.version = "1.0.0";
    lint.inspect_test_header = s09_inspect;
    plugin.lint = lint;
    array_add(*plugin.options_schema, config_option("marker", *S09_DEFAULT_MARKER, s09_apply_option, s09_validate_options));
    return plugin;
} @juice_plugin
S09_END

// One S09 workspace: a provider package, a root that optionally declares the
// plugin with a marker, and one member that declares it with marker "member".
// An empty root marker leaves the root with no plugin declaration at all, so a
// case can isolate "the member's lint never ran" from "the wrong configs were
// resolved".
s09_write_workspace :: (scratch: string, root_marker := "root") -> (string, string) {
    provider := dr_path(scratch, "provider");
    if !fr_write_package(provider, "s09_provider", "    modules = .[.{name = \"plugin\", entry = \"plugin.jai\"}],\n") return "", "";
    if !dr_write_file(provider, "plugin.jai", S09_PLUGIN_SOURCE) return "", "";
    root := dr_path(scratch, "workspace");
    root_plugins := "";
    if root_marker != "" {
        root_plugins = copy_string(tprint("    plugins = Plugin_Declaration.[.{id = \"s09_lint\", source = .{kind = .PATH, path = %1}, module = .{name = \"plugin\"}, options = Plugin_Option.[.{key = \"marker\", value = %2}]}],\n", quote_jai_string(provider), quote_jai_string(root_marker)));
    }
    if !fr_write_package(root, "s09_root", tprint("    workspace = .{members = .[\"members/*\"]},\n%1", root_plugins)) return "", "";
    return root, provider;
}

s09_member_plugins :: (provider: string) -> string {
    return copy_string(tprint("    modules = .[.{name = \"member_module\", entry = \"module.jai\"}],\n    plugins = Plugin_Declaration.[.{id = \"s09_lint\", source = .{kind = .PATH, path = %1}, module = .{name = \"plugin\"}, options = Plugin_Option.[.{key = \"marker\", value = \"member\"}]}],\n", quote_jai_string(provider)));
}

// The member's own declaration is the one in force: marker "member" passes its
// validator while the root's marker "root" would be rejected, so a test run
// that exits 0 proves the configs came from the package being tested.
final_review_member_test_uses_member_config :: () {
    scratch := dr_scratch("fr-member-config");
    dr_isolate(scratch);
    defer dr_restore_env();
    root, provider := s09_write_workspace(scratch);
    expect(root != "");
    member := dr_path(root, "members/alpha");
    expect(fr_write_package(member, "alpha", s09_member_plugins(provider)));
    expect(dr_write_file(member, "module.jai", "alpha_value :: () -> s64 { return 3; }\n"));
    expect(dr_write_file(dr_path(member, "tests"), "alpha_tests.jai", "alpha_good_name :: () {\n    expect(alpha_value() == 3);\n} @test\n"));

    result, output, errors := dr_run(member, string.["test"]);
    combined := tprint("%\n%", output, errors);
    if result.exit_code != 0 print("[fr] member-config child:\n%\n", combined);
    expect(expect_exit("member-config", result, 0));
    // The member's config was applied, never the root's.
    expect(!contains(combined, "S09 root config used"));
    expect(contains(combined, "1 passed, 0 failed"));
} @test

// The member's lint rule actually runs, and it reports against the MEMBER's own
// coordinate: `tests/beta_tests.jai`, not the workspace-relative
// `members/beta/tests/beta_tests.jai`. The root declares no plugin at all, so
// the case cannot be satisfied by resolving the root's declarations: only the
// member's own enablement can put this rule on the run.
final_review_member_lint_runs_with_member_paths :: () {
    scratch := dr_scratch("fr-member-lint");
    dr_isolate(scratch);
    defer dr_restore_env();
    root, provider := s09_write_workspace(scratch, "");
    expect(root != "");
    member := dr_path(root, "members/beta");
    expect(fr_write_package(member, "beta", s09_member_plugins(provider)));
    expect(dr_write_file(member, "module.jai", "beta_value :: () -> s64 { return 4; }\n"));
    expect(dr_write_file(dr_path(member, "tests"), "beta_tests.jai", "BadTestOne :: () {\n    expect(beta_value() == 4);\n} @test\n"));

    result, output, errors := dr_run(member, string.["test"]);
    combined := tprint("%\n%", output, errors);
    if result.exit_code == 0 print("[fr] member-lint child:\n%\n", combined);
    // Probe 09: pre-fix the member's lint never ran, so the run exited 0.
    expect(result.exit_code != 0);
    expect(contains(combined, "S09 member lint ran: BadTestOne"));
    // Diagnostic ownership: the finding is reported at the member's own path.
    expect(contains(combined, "tests/beta_tests.jai"));
    expect(!contains(combined, "members/beta/tests/beta_tests.jai"));
} @test

// ---------------------------------------------------------------------------
// S06/S07: a plugin Git source is a resolution like any other. Its record lands
// in the same state transaction as the package's dependency selections, and it
// lands only after the package's plugin checks passed. The review trajectories:
//   A) a plugins-only Git reference re-resolved on every build, offline failed
//      even right after a successful build, and `update` skipped plugin sources
//      entirely;
//   B) build/update published the new commit before a plugin error, so a
//      failing plugin silently replaced a working record.
// ---------------------------------------------------------------------------

// One plugin provider committed to a local repository. The plugin carries no
// hooks so the build stays a pure resolution question.
S06_PLUGIN_MODULE_SOURCE :: #string S06_END
#import "Basic";
#import "juice_core";

S06_Plugin :: struct {
    using base: Juice_Plugin;
}

get_juice_plugin :: () -> *S06_Plugin {
    plugin := New(S06_Plugin);
    plugin.id = "s06_plugin";
    plugin.version = "1.0.0";
    plugin.options = cast(*void) plugin;
    return plugin;
} @juice_plugin
S06_END

s06_write_plugin_repo :: (repo: string, module_source: string) -> string {
    if !dr_git_init(repo) return "";
    if !dr_write_file(repo, "package.jai", "#import \"Juice\";\n\nPACKAGE :: Package.{\n    version = \"1\",\n    name    = \"s06-plugin\",\n    modules = .[.{name = \"plugin_module\", entry = \"plugin.jai\"}],\n};\n") return "";
    if !dr_write_file(repo, "plugin.jai", module_source) return "";
    return copy_string(dr_git_commit_all(repo, "s06 plugin provider"));
}

s06_write_app :: (app: string, repo: string) -> bool {
    plugins := copy_string(tprint("    plugins = Plugin_Declaration.[.{id = \"s06_plugin\", source = .{kind = .GIT, git = .{url = %1}}, module = .{name = \"plugin_module\"}}],\n", quote_jai_string(repo)));
    return fr_write_program(app, "s06_app", plugins, "#import \"Basic\";\n\nmain :: () { print(\"S06_OK\\n\"); }\n");
}

// The resolution state file belonging to one consumer root, read through the
// production state root (the case isolates XDG_STATE_HOME through dr_isolate).
s06_read_state :: (consumer_root: string) -> (string, bool) {
    environment: Resolution_Environment;
    environment.state_root = get_juice_resolution_state_root().path;
    text, ok := read_entire_file(resolution_state_file(environment, consumer_root));
    return text, ok;
}

// Trajectory A, first half: the plugin's commit is recorded, so a later build
// with the remote moved on keeps the recorded commit, and an offline build
// succeeds without contacting anything.
final_review_plugin_git_source_is_recorded :: () {
    scratch := dr_scratch("fr-plugin-git-record");
    dr_isolate(scratch);
    defer dr_restore_env();
    repo := dr_path(scratch, "repo");
    first := s06_write_plugin_repo(repo, S06_PLUGIN_MODULE_SOURCE);
    expect(first.count == 40);
    app := dr_path(scratch, "app");
    expect(s06_write_app(app, repo));

    built, built_output, built_errors := dr_run(app, string.["build"]);
    if built.exit_code != 0 print("[fr] plugin-git first build:\n%\n", tprint("%\n%", built_output, built_errors));
    expect(expect_exit("plugin-git-first", built, 0));

    state_text, state_ok := s06_read_state(app);
    expect(state_ok);
    expect(contains(state_text, first));
    // The record is the plugin ROLE record: its declaring key ends with the
    // plugin package-path field, so a dependency of the same URL is a different
    // record and cannot satisfy this lookup.
    expect(contains(state_text, ":plugin"));

    // The remote moves on; the recorded build must still resolve the record.
    second := s06_write_plugin_repo(repo, tprint("%1\nS06_Extra :: 1;\n", S06_PLUGIN_MODULE_SOURCE));
    expect(second != "" && second != first);
    recorded, recorded_output, recorded_errors := dr_run(app, string.["build"]);
    if recorded.exit_code != 0 print("[fr] plugin-git recorded build:\n%\n", tprint("%\n%", recorded_output, recorded_errors));
    expect(expect_exit("plugin-git-recorded", recorded, 0));
    after_text, after_ok := s06_read_state(app);
    expect(after_ok);
    expect(contains(after_text, first));
    expect(!contains(after_text, second));

    // Offline: the record alone answers the resolution.
    offline, offline_output, offline_errors := dr_run(app, string.["build", "--offline"]);
    if offline.exit_code != 0 print("[fr] plugin-git offline:\n%\n", tprint("%\n%", offline_output, offline_errors));
    expect(expect_exit("plugin-git-offline", offline, 0));

    // update refreshes the plugin graph (the remote commit) and runs no hook.
    // The artifact is removed first, so "the update compiled nothing" is a real
    // observation rather than a file the earlier builds left behind.
    artifact := target_artifact_path(package_target_dir(app), "s06_app");
    expect(file_delete(artifact));
    updated, updated_output, updated_errors := dr_run(app, string.["update"]);
    updated_text := tprint("%\n%", updated_output, updated_errors);
    if updated.exit_code != 0 print("[fr] plugin-git update:\n%\n", updated_text);
    expect(expect_exit("plugin-git-update", updated, 0));
    update_text, update_ok := s06_read_state(app);
    expect(update_ok);
    expect(contains(update_text, second));
    // No build hook ran and no program compiled: the artifact stayed absent.
    expect(!file_exists(artifact));
} @test

// Trajectory B: a broken plugin must not replace a working record. The first
// build records the good plugin; the plugin module is then replaced by one with
// no entry at all (a role/entry failure the scan catches) and the second build
// must fail while the state still names the good commit.
final_review_plugin_failure_keeps_previous_state :: () {
    scratch := dr_scratch("fr-plugin-git-rollback");
    dr_isolate(scratch);
    defer dr_restore_env();
    repo := dr_path(scratch, "repo");
    good := s06_write_plugin_repo(repo, S06_PLUGIN_MODULE_SOURCE);
    expect(good.count == 40);
    app := dr_path(scratch, "app");
    expect(s06_write_app(app, repo));

    built, built_output, built_errors := dr_run(app, string.["build"]);
    if built.exit_code != 0 print("[fr] rollback first build:\n%\n", tprint("%\n%", built_output, built_errors));
    expect(expect_exit("plugin-git-rollback-first", built, 0));

    // A new commit whose plugin module has no plugin entry at all.
    broken := s06_write_plugin_repo(repo, "#import \"Basic\";\n\nNot_A_Plugin :: 1;\n");
    expect(broken != "" && broken != good);

    failed, failed_output, failed_errors := dr_run(app, string.["update"]);
    failed_text := tprint("%\n%", failed_output, failed_errors);
    expect(failed.exit_code != 0);
    expect(contains(failed_text, "Plugin capability missing"));
    // The failing update published nothing: the previous record still names the
    // good commit, and the broken one appears nowhere.
    state_text, state_ok := s06_read_state(app);
    expect(state_ok);
    expect(contains(state_text, good));
    expect(!contains(state_text, broken));
} @test

// ---------------------------------------------------------------------------
// S14: declaration names are validated once, with one grammar, and compared with
// one ASCII-insensitive key. The review trajectories: a dependency referenced as
// `"bad name"` built successfully, a plugin id `"../escaped"` was accepted, a
// program declared `Tool` did not answer `run tool`, and a schema key `config`
// rejected the declaration row `CONFIG`.
// ---------------------------------------------------------------------------
final_review_dependency_name_grammar_is_enforced :: () {
    scratch := dr_scratch("fr-name-grammar");
    dr_isolate(scratch);
    defer dr_restore_env();
    provider := dr_path(scratch, "provider");
    expect(dr_write_module_provider(provider, "provider", "Provider_Value :: 1;\n"));
    app := dr_path(scratch, "app");
    body := tprint("    dependencies = Dependency.[.{name = \"bad name\", source = .{kind = .PATH, path = %1}, modules = .[.{alias = \"Bad\"}]}],\n    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n", quote_jai_string(provider));
    expect(fr_write_program(app, "app", body, "#import \"Basic\";\n\nmain :: () { print(\"NOPE\\n\"); }\n"));

    result, output, errors := dr_run(app, string.["build"]);
    combined := tprint("%\n%", output, errors);
    // Probe: pre-fix this build succeeded with the name accepted verbatim.
    expect(result.exit_code != 0);
    expect(contains(combined, "Invalid dependency name"));

    // A plugin id outside the identifier grammar is rejected at declaration time.
    plugin_body := "    plugins = Plugin_Declaration.[.{id = \"../escaped\", source = .{kind = .PATH, path = \"vendor/p\"}, module = .{name = \"p\"}}],\n    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n";
    expect(fr_write_program(dr_path(scratch, "app2"), "app2", plugin_body, "#import \"Basic\";\n\nmain :: () { print(\"NOPE\\n\"); }\n"));
    plugin_result, plugin_output, plugin_errors := dr_run(dr_path(scratch, "app2"), string.["build"]);
    plugin_combined := tprint("%\n%", plugin_output, plugin_errors);
    expect(plugin_result.exit_code != 0);
    expect(contains(plugin_combined, "Invalid plugin id"));
} @test

// A declared program name answers the same request in any ASCII case, while the
// declaration keeps its own spelling in the artifact and the diagnostics.
final_review_program_name_match_is_ascii_insensitive :: () {
    scratch := dr_scratch("fr-program-case");
    dr_isolate(scratch);
    defer dr_restore_env();
    app := dr_path(scratch, "app");
    expect(fr_write_program(app, "app", "    executables = .[.{name = \"Tool\", entry = \"src/main.jai\"}],\n", "#import \"Basic\";\n\nmain :: () { print(\"TOOL_RAN\\n\"); }\n"));

    built, built_output, built_errors := dr_run(app, string.["build"]);
    if built.exit_code != 0 print("[fr] program-case build:\n%\n", tprint("%\n%", built_output, built_errors));
    expect(expect_exit("program-case-build", built, 0));

    lower, lower_output, lower_errors := dr_run(app, string.["run", "tool"]);
    if lower.exit_code != 0 print("[fr] program-case run tool:\n%\n", tprint("%\n%", lower_output, lower_errors));
    expect(expect_exit("program-case-run-lower", lower, 0));
    expect(contains(lower_output, "TOOL_RAN"));

    // The declaration spelling still names the artifact.
    expect(file_exists(target_artifact_path(package_target_dir(app), "Tool")));
} @test

// ---------------------------------------------------------------------------
// S15: the typed XDG roots are a contract, not a hint. A root that cannot be
// created or written is a failure the command reports, and every cache consumer
// — the manifest evaluator's temp files included — uses the verified typed root
// rather than a legacy base-home helper that would reinterpret an invalid
// XDG_CACHE_HOME as a cwd-relative path.
// ---------------------------------------------------------------------------

// A no-Git build under an XDG_CACHE_HOME that is an existing REGULAR FILE. The
// typed root cannot be created there, so the entry must refuse instead of
// running on an unusable root.
final_review_unusable_cache_root_fails_the_command :: () {
    scratch := dr_scratch("fr-xdg-cache");
    dr_isolate(scratch);
    defer dr_restore_env();
    blocked := dr_path(scratch, "blocked-cache");
    expect(write_entire_file(blocked, "regular file"));
    dr_set_process_env("XDG_CACHE_HOME", blocked);

    app := dr_path(scratch, "app");
    expect(fr_write_program(app, "app", "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n", "#import \"Basic\";\n\nmain :: () { print(\"XDG_OK\\n\"); }\n"));
    result, output, errors := dr_run(app, string.["build"]);
    combined := tprint("%\n%", output, errors);
    if result.exit_code == 0 print("[fr] xdg-cache child:\n%\n", combined);
    // Pre-fix: the failure flag was ignored and the build reported success.
    expect(result.exit_code != 0);
    expect(contains(combined, "content cache root"));
    expect(!contains(combined, "Build completed successfully"));
    // The path really is still a regular file: nothing was created behind it.
    blocked_content, read_ok := read_entire_file(blocked);
    expect(read_ok && blocked_content == "regular file");
} @test

// The same for XDG_STATE_HOME. The dependency-free build never writes state, so
// only the entry check can catch it — which is exactly the review point.
final_review_unusable_state_root_fails_the_command :: () {
    scratch := dr_scratch("fr-xdg-state");
    dr_isolate(scratch);
    defer dr_restore_env();
    blocked := dr_path(scratch, "blocked-state");
    expect(write_entire_file(blocked, "regular file"));
    dr_set_process_env("XDG_STATE_HOME", blocked);

    app := dr_path(scratch, "app");
    expect(fr_write_program(app, "app", "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n", "#import \"Basic\";\n\nmain :: () { print(\"XDG_OK\\n\"); }\n"));
    result, output, errors := dr_run(app, string.["build"]);
    combined := tprint("%\n%", output, errors);
    if result.exit_code == 0 print("[fr] xdg-state child:\n%\n", combined);
    expect(result.exit_code != 0);
    expect(contains(combined, "resolution state root"));
    expect(!contains(combined, "Build completed successfully"));
} @test

// The evaluator cache follows the VERIFIED typed root: with a valid custom
// XDG_CACHE_HOME the manifest evaluator's generated source and data land under
// that root's juice directory, and nothing lands in a cwd-relative `juice/`.
final_review_evaluator_cache_uses_typed_root :: () {
    scratch := dr_scratch("fr-xdg-evaluator");
    dr_isolate(scratch);
    defer dr_restore_env();
    app := dr_path(scratch, "app");
    expect(fr_write_program(app, "app", "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n", "#import \"Basic\";\n\nmain :: () { print(\"XDG_OK\\n\"); }\n"));

    built, built_output, built_errors := dr_run(app, string.["build"]);
    if built.exit_code != 0 print("[fr] xdg-evaluator child:\n%\n", tprint("%\n%", built_output, built_errors));
    expect(expect_exit("xdg-evaluator", built, 0));

    // The evaluator wrote under the typed root this case isolated.
    typed_root := tprint("%1/juice", dr_path(scratch, "xdg-cache"));
    expect(is_directory(typed_root));
    evaluator_files: [..] string;
    collect :: (info: *File_Visit_Info, out: *[..] string) {
        if !contains(info.short_name, "manifest_data_") return;
        array_add(out, copy_string(info.full_name));
    }
    visit_files(typed_root, true, *evaluator_files, collect, visit_directories = false);
    expect(evaluator_files.count > 0);
    // And no legacy cwd-relative cache appeared beside the package.
    expect(!is_directory(dr_path(app, "juice")));
} @test

// ---------------------------------------------------------------------------
// S06 tail: a plugin provider is a package like any other, so the plugin module
// may `#import` a dependency its OWN declaration selects. The consumer never
// repeats that declaration (decision 21: reuse the provider's graph), yet the
// plugin must compile. Review trajectory B: the provider legally declared
// `Helper`, the plugin module imported it, and the host could not find it.
// ---------------------------------------------------------------------------

// The plugin module imports `Helper`, a module the PROVIDER declares as its own
// dependency; the consumer declares no dependency at all.
S06_PROVIDER_PLUGIN_SOURCE :: #string S06_P_END
#import "Basic";
#import "Helper";
#import "juice_core";

S06_Provider_Plugin :: struct {
    using base: Juice_Plugin;
}

get_juice_plugin :: () -> *S06_Provider_Plugin {
    plugin := New(S06_Provider_Plugin);
    plugin.id = "s06_provider_plugin";
    plugin.version = "1.0.0";
    plugin.options = cast(*void) plugin;
    // The imported value is part of the plugin's own state, so a host that
    // cannot resolve `Helper` fails to compile instead of silently ignoring it.
    plugin.version = tprint("1.0.0+%", HELPER_VALUE);
    return plugin;
} @juice_plugin
S06_P_END

final_review_plugin_provider_dependencies_resolve :: () {
    scratch := dr_scratch("fr-plugin-provider-deps");
    dr_isolate(scratch);
    defer dr_restore_env();
    helper := dr_path(scratch, "helper");
    expect(dr_write_module_provider(helper, "helper", "HELPER_VALUE :: \"7\";\n"));
    repo := dr_path(scratch, "repo");
    expect(dr_git_init(repo));
    // The provider: one public plugin module plus its OWN dependency on Helper.
    provider_body := tprint("    modules = .[.{name = \"plugin_module\", entry = \"plugin.jai\"}],\n    dependencies = Dependency.[.{name = \"helper\", source = .{kind = .PATH, path = %1}, modules = .[.{alias = \"Helper\"}]}],\n", quote_jai_string(helper));
    expect(fr_write_package(repo, "s06-provider", provider_body));
    expect(dr_write_file(repo, "plugin.jai", S06_PROVIDER_PLUGIN_SOURCE));
    commit_hash := copy_string(dr_git_commit_all(repo, "provider with a dependency"));
    expect(commit_hash.count == 40);

    app := dr_path(scratch, "app");
    plugins := copy_string(tprint("    plugins = Plugin_Declaration.[.{id = \"s06_provider_plugin\", source = .{kind = .GIT, git = .{url = %1}}, module = .{name = \"plugin_module\"}}],\n", quote_jai_string(repo)));
    expect(fr_write_program(app, "s06_app", plugins, "#import \"Basic\";\n\nmain :: () { print(\"S06_PROVIDER_OK\\n\"); }\n"));

    built, built_output, built_errors := dr_run(app, string.["build"]);
    combined := tprint("%\n%", built_output, built_errors);
    if built.exit_code != 0 print("[fr] plugin-provider-deps child:\n%\n", combined);
    // Pre-fix: `Undeclared identifier 'HELPER_VALUE'` (or an unresolvable
    // `#import "Helper"`) because the provider's graph was never resolved.
    expect(expect_exit("plugin-provider-deps", built, 0));
    expect(!contains(combined, "Helper"));

    // The provider's graph is recorded by the same transaction, and update
    // refreshes it without running any hook.
    artifact := target_artifact_path(package_target_dir(app), "s06_app");
    expect(file_delete(artifact));
    updated, updated_output, updated_errors := dr_run(app, string.["update"]);
    updated_text := tprint("%\n%", updated_output, updated_errors);
    if updated.exit_code != 0 print("[fr] plugin-provider-deps update:\n%\n", updated_text);
    expect(expect_exit("plugin-provider-deps-update", updated, 0));
    expect(!file_exists(artifact));

    // Nothing was written into the provider's Git checkout: every derived
    // import name lives in the consumer's private area.
    status_result, status := dr_git(string.["-C", repo, "status", "--porcelain"]);
    expect(status_result.exit_code == 0);
    expect(status == "");
} @test

// ---------------------------------------------------------------------------
// S11: the derived-output contract is a contract, not a string prefix.
// Review probes: `<derived>/../../../../outside.jai` satisfied a literal prefix
// test, a second registration of the same original (identical replacement) was
// accepted and the winner depended on order, and a failed cleanup of the stale
// derived area only warned while the run went on to consume stale files.
// ---------------------------------------------------------------------------

// The most recent lifecycle diagnostic message (the contract API records one
// ERROR per rejected registration).
fr_last_error :: (diags: [] Lifecycle_Diagnostic) -> string {
    if diags.count == 0 return "";
    return diags[diags.count - 1].message;
}

// The plugin-visible registration API rejects a replacement that only LOOKS
// contained: dot segments are resolved before the comparison, so an escape is
// an escape even when the path string starts with the derived root.
final_review_substitution_rejects_dot_segment_escape :: () {
    scratch := dr_scratch("fr-derived-escape");
    defer delete_directory_full(scratch);
    root := dr_path(scratch, "pkg");
    expect(dr_write_file(dr_path(root, "src"), "main.jai", "main :: () {}\n"));
    expect(dr_write_file(dr_path(root, "src"), "helper.jai", "Helper :: 1;\n"));
    derived := dr_path(root, "target/plugins/derived/pkg");
    expect(make_directory_if_it_does_not_exist(derived, recursive = true));

    stage: Prestep_Stage;
    stage.package_root = root;
    stage.derived_root = derived;
    stage.enforce_private_output = true;
    diags: [..] Lifecycle_Diagnostic;
    ctx: Lifecycle_Context;
    ctx.diagnostics = *diags;
    ctx.prestep = *stage;

    // The pre-fix escape: the literal string starts with the derived root.
    outside := tprint("%1/../../../../outside.jai", derived);
    expect(starts_with(outside, derived));
    expect(!prestep_add_substitution(*ctx, "src/helper.jai", outside));
    expect(find_index_from_left(fr_last_error(diags), "outside the package's private derived area") >= 0);

    // An inner dot segment that resolves back OUTSIDE is the same violation.
    array_reset(*diags);
    inner_escape := tprint("%1/sub/../../../../outside.jai", derived);
    expect(!prestep_add_substitution(*ctx, "src/helper.jai", inner_escape));

    // A dot segment that resolves INSIDE stays legal: the check is canonical,
    // not a blanket ban on "..".
    array_reset(*diags);
    inside := tprint("%1/sub/../kept.jai", derived);
    expect(make_directory_if_it_does_not_exist(tprint("%1/sub", derived), recursive = true));
    expect(write_entire_file(tprint("%1/kept.jai", derived), "// kept\n"));
    expect(prestep_add_substitution(*ctx, "src/helper.jai", inside));
} @test

// One logical input, two registrations: rejected even when both name the same
// replacement, so no plugin can rely on registration order to win.
final_review_duplicate_substitution_is_rejected :: () {
    scratch := dr_scratch("fr-derived-duplicate");
    defer delete_directory_full(scratch);
    root := dr_path(scratch, "pkg");
    expect(dr_write_file(dr_path(root, "src"), "helper.jai", "Helper :: 1;\n"));
    derived := dr_path(root, "target/plugins/derived/pkg");
    expect(make_directory_if_it_does_not_exist(derived, recursive = true));
    replacement := tprint("%1/src/helper.jai", derived);
    expect(make_directory_if_it_does_not_exist(tprint("%1/src", derived), recursive = true));
    expect(write_entire_file(replacement, "Helper :: 2;\n"));

    stage: Prestep_Stage;
    stage.package_root = root;
    stage.derived_root = derived;
    stage.enforce_private_output = true;
    diags: [..] Lifecycle_Diagnostic;
    ctx: Lifecycle_Context;
    ctx.diagnostics = *diags;
    ctx.prestep = *stage;

    expect(prestep_add_substitution(*ctx, "src/helper.jai", replacement));
    expect(!prestep_add_substitution(*ctx, "src/helper.jai", replacement));
    expect(find_index_from_left(fr_last_error(diags), "duplicate source substitution") >= 0);
    expect(stage.substitutions.count == 1);
} @test

// A confirmed report of a physical file that lives outside the derived area is
// rejected — the host's own registration channel gets the same canonical check
// as the in-process one.
final_review_generated_rejects_foreign_physical_path :: () {
    scratch := dr_scratch("fr-derived-generated");
    defer delete_directory_full(scratch);
    root := dr_path(scratch, "pkg");
    expect(dr_write_file(dr_path(root, "src"), "main.jai", "main :: () {}\n"));
    derived := dr_path(root, "target/plugins/derived/pkg");
    expect(make_directory_if_it_does_not_exist(derived, recursive = true));
    foreign := dr_path(scratch, "outside.jai");
    expect(write_entire_file(foreign, "Foreign :: 1;\n"));

    stage: Prestep_Stage;
    stage.package_root = root;
    stage.derived_root = derived;
    stage.enforce_private_output = true;
    diags: [..] Lifecycle_Diagnostic;
    ctx: Lifecycle_Context;
    ctx.diagnostics = *diags;
    ctx.prestep = *stage;

    expect(!prestep_register_generated(*ctx, "src/generated.jai", foreign));
    expect(find_index_from_left(fr_last_error(diags), "outside the package's private derived area") >= 0);
    // The dot-segment spelling of the same escape is rejected too.
    array_reset(*diags);
    escape := tprint("%1/../../outside.jai", derived);
    expect(!prestep_register_generated(*ctx, "src/generated.jai", escape));
} @test

// A stale private derived area that cannot be cleared stops the package instead
// of warning: the run would otherwise consume files from a directory the plugin
// layer no longer owns (decision 24: 创建、清理、写入或注册失败中止当前包).
final_review_stale_derived_area_failure_is_fatal :: () {
    scratch := dr_scratch("fr-derived-cleanup");
    defer delete_directory_full(scratch);
    root := dr_path(scratch, "pkg");
    expect(dr_write_file(dr_path(root, "src"), "main.jai", "main :: () {}\n"));
    derived := dr_path(root, "target/plugins/derived/pkg");
    expect(make_directory_if_it_does_not_exist(derived, recursive = true));
    // The cleanup seam reports failure (a real undeletable directory needs a
    // platform lock, so the decision logic is what this case pins).
    refuse :: (path: string) -> bool {
        return false;
    }
    stage: Prestep_Stage;
    package_view: Prepared_Package_Plugins;
    package_view.package_root = root;
    package_view.derived_root = derived;
    expect(!prepare_package_derived_view(*package_view, *stage, refuse));
    // The same view with a working cleanup proceeds and hands the stage its roots.
    stage_ok: Prestep_Stage;
    expect(prepare_package_derived_view(*package_view, *stage_ok, delete_directory_full));
    expect(stage_ok.derived_root == derived && stage_ok.package_root == root);
} @test

// ---------------------------------------------------------------------------
// S10: one logical input graph. The pre-step's substitute/generated channels act
// on the whole `#load` closure of the run, not only on the build entry, and the
// logical paths stay the identity used for relative loads and for loading edges.
// Review probes: a hook registered `generated("src/helper.jai", ...)` for a file
// the retained main `#load`s and the compile never saw it; a substitution of a
// nested helper was ignored; a substitution of the entry moved its relative
// load base.
// ---------------------------------------------------------------------------

// PRESTEP plugin: substitutes one nested helper, generates another, and refuses
// anything the options do not name. The two option rows keep the fixture honest —
// the hook only ever touches the paths it was told to.
S10_PLUGIN_SOURCE :: #string S10_END
#import "Basic";
#import "juice_core";

S10_Plugin :: struct {
    using base: Juice_Plugin;
    replace: string;
    generate: string;
}

S10_DEFAULT_REPLACE: string = "";
S10_DEFAULT_GENERATE: string = "";

// The replacement keeps the LOGICAL name its caller already uses: substitute
// replaces a file's text, it never renames the input. The value changes, which is
// what the assertion observes.
S10_REPLACED_HELPER :: "Value_From_Deep :: () -> s64 {\n    return 42;\n}\n";
S10_GENERATED_HELPER :: "#import \"Basic\";\n\nGenerated_Helper :: () -> s64 {\n    return 7;\n}\n";

s10_apply :: (options: *void, key: string, value: string) -> string {
    plugin := cast(*S10_Plugin) options;
    if key == "replace" {
        plugin.replace = value;
        return "";
    }
    if key == "generate" {
        plugin.generate = value;
        return "";
    }
    return tprint("unknown option '%'", key);
}

s10_hook :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    plugin := cast(*S10_Plugin) state;
    if plugin.replace != "" {
        physical, written := prestep_write_derived(ctx, plugin.replace, S10_REPLACED_HELPER);
        if !written return false;
        if !prestep_add_substitution(ctx, plugin.replace, physical) return false;
    }
    if plugin.generate != "" {
        if !prestep_add_generated(ctx, plugin.generate, S10_GENERATED_HELPER) return false;
    }
    return true;
}

get_juice_plugin :: () -> *S10_Plugin {
    plugin := New(S10_Plugin);
    plugin.id = "s10_derived";
    plugin.version = "1.0.0";
    plugin.options = cast(*void) plugin;
    array_add(*plugin.hooks, .{stage = .PRESTEP, position = .before, hook = s10_hook});
    array_add(*plugin.options_schema, config_option("replace", *S10_DEFAULT_REPLACE, s10_apply, null));
    array_add(*plugin.options_schema, config_option("generate", *S10_DEFAULT_GENERATE, s10_apply, null));
    return plugin;
} @juice_plugin
S10_END

// One app shaped for the S10 cases: main `#load`s a retained helper, which in turn
// `#load`s a second helper. The substitutions/generations the plugin is told to
// make all land BELOW the entry, so an entry-only implementation sees none of
// them.
s10_write_app :: (app: string, replace_path: string, generate_path: string) -> bool {
    rows: [..] string;
    if replace_path != "" array_add(*rows, tprint(".{key = \"replace\", value = %1}", quote_jai_string(replace_path)));
    if generate_path != "" array_add(*rows, tprint(".{key = \"generate\", value = %1}", quote_jai_string(generate_path)));
    plugin_options := "";
    if rows.count > 0 {
        builder: String_Builder;
        for row, index: rows {
            if index > 0 print_to_builder(*builder, ", ");
            print_to_builder(*builder, "%", row);
        }
        plugin_options = tprint(", options = Plugin_Option.[%]", builder_to_string(*builder));
    }
    plugins := copy_string(tprint("    plugins = Plugin_Declaration.[.{builtin = \"load\"}, .{builtin = \"test-block\"}, .{id = \"s10_derived\", source = .{kind = .WORKSPACE}, module = .{path = \"packages/s10-plugin\", name = \"s10_plugin\"}%1}],\n", plugin_options));
    // The provider is a workspace member, so the WORKSPACE source kind resolves it
    // without a second declaration surface.
    if !fr_write_package(app, "s10_app", tprint("%1    workspace = .{members = .[\"packages/s10-plugin\"]},\n    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n", plugins)) return false;
    if !dr_write_file(dr_path(app, "src"), "main.jai", "#import \"Basic\";\n\n#load \"helper.jai\";\n\nmain :: () {\n    print(\"S10_VALUE=%\\n\", Value_From_Helper());\n}\n") return false;
    if !dr_write_file(dr_path(app, "src"), "helper.jai", "#import \"Basic\";\n\n#load \"deep.jai\";\n\nValue_From_Helper :: () -> s64 {\n    return Value_From_Deep() + 1;\n}\n") return false;
    return dr_write_file(dr_path(app, "src"), "deep.jai", "Value_From_Deep :: () -> s64 {\n    return 1;\n}\n");
}

s10_write_provider :: (app: string) -> bool {
    provider := dr_path(app, "packages/s10-plugin");
    if !fr_write_package(provider, "s10_plugin_provider", "    modules = .[.{name = \"s10_plugin\", entry = \"plugin.jai\"}],\n") return false;
    return dr_write_file(provider, "plugin.jai", S10_PLUGIN_SOURCE);
}

// A generated helper that the retained main `#load`s and the package does not
// have: the compile input must come from the pre-step's registration.
final_review_generated_helper_joins_the_closure :: () {
    scratch := dr_scratch("fr-derived-generated-closure");
    dr_isolate(scratch);
    defer dr_restore_env();
    app := dr_path(scratch, "app");
    expect(s10_write_app(app, "", "src/gen_helper.jai"));
    expect(s10_write_provider(app));
    // The retained main loads the generated name instead of the shipped helper.
    expect(dr_write_file(dr_path(app, "src"), "main.jai", "#import \"Basic\";\n\n#load \"gen_helper.jai\";\n\nmain :: () {\n    print(\"S10_GEN=%\\n\", Generated_Helper());\n}\n"));

    built, built_output, built_errors := dr_run(app, string.["build"]);
    combined := tprint("%\n%", built_output, built_errors);
    if built.exit_code != 0 print("[fr] generated-closure child:\n%\n", combined);
    expect(expect_exit("generated-closure", built, 0));
    run_result, run_output, _, _ := run_command(target_artifact_path(package_target_dir(app), "app"), capture_and_return_output = true);
    expect(expect_exit("generated-closure-run", run_result, 0));
    expect(contains(run_output, "S10_GEN=7"));
} @test

// A substitution of a NESTED helper (two `#load` edges below the entry): the
// compile must read the derived text, and the logical path stays the helper's.
final_review_nested_substitution_reaches_the_compile :: () {
    scratch := dr_scratch("fr-derived-nested");
    dr_isolate(scratch);
    defer dr_restore_env();
    app := dr_path(scratch, "app");
    expect(s10_write_app(app, "src/deep.jai", ""));
    expect(s10_write_provider(app));

    built, built_output, built_errors := dr_run(app, string.["build"]);
    combined := tprint("%\n%", built_output, built_errors);
    if built.exit_code != 0 print("[fr] nested-substitution child:\n%\n", combined);
    expect(expect_exit("nested-substitution", built, 0));
    run_result, run_output, _, _ := run_command(target_artifact_path(package_target_dir(app), "app"), capture_and_return_output = true);
    expect(expect_exit("nested-substitution-run", run_result, 0));
    // 42 (the substituted deep helper) + 1, never the retained 1 + 1.
    expect(contains(run_output, "S10_VALUE=43"));
    expect(!contains(run_output, "S10_VALUE=2"));
} @test
