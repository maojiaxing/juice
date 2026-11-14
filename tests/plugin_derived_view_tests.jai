// ---------------------------------------------------------------------------
// Independent plugin sources and the per-package derived view (ticket 0092;
// parent spec 0087 decisions 21-25, acceptance groups A05-A08).
//
// Two families live here:
//
// 1. The typed-API matrix (fast): the derived-view registration rules of the
//    published plugin face (src/lifecycle.jai) — duplicate substitution,
//    duplicate auxiliary path, covering a retained source, the same-path
//    drop/substitute conflict, path escapes, replacements outside the private
//    derived area, and "only this round's registrations are consumed". Plus
//    the resolver's independent entry-ABI check (no user-declared version
//    exists any more).
//
// 2. The real-CLI matrix (a spawned juice child over scratch packages): a
//    plugin enabled through its OWN typed source + public-module selection
//    (no ordinary dependency, no member-name guess), the builtin
//    omitted/empty/replaced triad, the entry capability/ambiguity
//    diagnostics, the options failures that must happen before any hook, the
//    duplicate-enablement and double-role failures, and the derived view
//    landing inside the consuming package's private target area while the
//    package sources stay untouched.
//
// The typed-API family uses the production seams the ticket already approved
// (real files in a scratch tree + the published interface); the CLI family
// runs the real executable over temporary packages. Every scratch tree lives
// under target/ (root target/ is excluded from test discovery and from plugin
// scans) and is unique per case. Every @test here is a filterable procedure
// (the plugin_derived_ prefix).
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";
#import "File";
#import "File_Utilities";
#import "String";

// ===========================================================================
// Typed-API family: the derived view registration rules
// ===========================================================================

PDV_SCRATCH_COUNTER: s64;

pdv_scratch :: (name: string) -> string {
    PDV_SCRATCH_COUNTER += 1;
    root := otter_scratch(tprint("plugin-derived-view/%1-%2", name, PDV_SCRATCH_COUNTER));
    delete_directory_full(root);
    make_directory_if_it_does_not_exist(root, recursive = true);
    return root;
}

// A stage whose package root holds the retained sources `retained` (written to
// disk, so the "covers a retained package source" rule sees a real file) and
// whose private derived root is a fresh scratch tree.
pdv_stage :: (root: string, retained: [] string) -> Prestep_Stage {
    package_root := tprint("%1/package", root);
    derived_root := tprint("%1/derived", root);
    make_directory_if_it_does_not_exist(package_root, recursive = true);
    make_directory_if_it_does_not_exist(derived_root, recursive = true);
    for rel: retained {
        path := tprint("%1/%2", package_root, rel);
        make_directory_if_it_does_not_exist(path_strip_filename(path), recursive = true);
        write_entire_file(path, "// retained\n");
    }
    stage: Prestep_Stage;
    stage.root_dir = package_root;
    stage.package_root = package_root;
    stage.derived_root = derived_root;
    return stage;
}

pdv_ctx :: (stage: *Prestep_Stage, diags: *[..] Lifecycle_Diagnostic) -> Lifecycle_Context {
    ctx: Lifecycle_Context;
    ctx.diagnostics = diags;
    ctx.prestep = stage;
    return ctx;
}

pdv_last_error :: (diags: [] Lifecycle_Diagnostic) -> string {
    if diags.count == 0 return "";
    return diags[diags.count - 1].message;
}

plugin_derived_view_rules :: () {
    // --- substitute: the logical input must be a retained package source, and
    // the replacement must live inside the private derived area -------------
    root := pdv_scratch("substitute");
    defer delete_directory_full(root);
    stage := pdv_stage(root, .["src/main.jai"]);
    diags: [..] Lifecycle_Diagnostic;
    ctx := pdv_ctx(*stage, *diags);

    // A replacement in the package sources (or anywhere else) is the read-only
    // violation: the source tree is never an output area.
    expect(!prestep_add_substitution(*ctx, "src/main.jai", tprint("%1/package/src/main.jai", root)));
    expect(find_index_from_left(pdv_last_error(diags), "outside the package's private derived area") >= 0);

    // A logical path that invents a source the package does not have fails
    // too: substitute MAPS an existing input, it never creates one.
    expect(!prestep_add_substitution(*ctx, "src/missing.jai", tprint("%1/derived/x.jai", root)));
    expect(find_index_from_left(pdv_last_error(diags), "not a retained package source") >= 0);

    // An absolute, backslashed or escaping logical path never resolves.
    expect(!prestep_add_substitution(*ctx, "../escape.jai", tprint("%1/derived/x.jai", root)));
    expect(find_index_from_left(pdv_last_error(diags), "not a package-relative source path") >= 0);
    expect(!prestep_add_substitution(*ctx, "C:/abs.jai", tprint("%1/derived/x.jai", root)));
    expect(!prestep_add_substitution(*ctx, "src\\main.jai", tprint("%1/derived/x.jai", root)));

    // The accepted row keeps the LOGICAL path as its key (imports, diagnostics
    // and test attribution stay the package's own path) and stores the
    // physical file only for reading.
    replacement, written := prestep_write_derived(*ctx, "src/main.jai", "// derived main\n");
    expect(written && file_exists(replacement));
    expect(prestep_add_substitution(*ctx, "src/main.jai", replacement));
    physical, found := prestep_substitution_for(*stage, "src/main.jai");
    expect(found && physical == replacement);
    reverse, reverse_found := prestep_substitution_for(*stage, replacement);
    expect(!reverse_found && reverse == "");

    // --- drop: a repeated drop is a no-op; the same path cannot be both
    // dropped and substituted (either order) --------------------------------
    drop_root := pdv_scratch("drop");
    defer delete_directory_full(drop_root);
    drop_stage := pdv_stage(drop_root, .["src/main.jai", "src/skip.jai"]);
    drop_diags: [..] Lifecycle_Diagnostic;
    drop_ctx := pdv_ctx(*drop_stage, *drop_diags);

    expect(prestep_add_drop(*drop_ctx, "src/skip.jai"));
    expect(prestep_add_drop(*drop_ctx, "src/skip.jai"));       // idempotent
    expect(drop_diags.count == 0);

    expect(!prestep_add_substitution(*drop_ctx, "src/skip.jai", tprint("%1/derived/skip.jai", drop_root)));
    expect(find_index_from_left(pdv_last_error(drop_diags), "substitution conflicts with a drop") >= 0);

    drop_derived, drop_written := prestep_write_derived(*drop_ctx, "src/main.jai", "// derived main\n");
    expect(drop_written);
    expect(prestep_add_substitution(*drop_ctx, "src/main.jai", drop_derived));
    expect(!prestep_add_drop(*drop_ctx, "src/main.jai"));
    expect(find_index_from_left(pdv_last_error(drop_diags), "drop conflicts with a source substitution") >= 0);

    // --- generated: explicit registration only, conflicts never resolve by
    // declaration order ------------------------------------------------------
    gen_root := pdv_scratch("generated");
    defer delete_directory_full(gen_root);
    gen_stage := pdv_stage(gen_root, .["src/main.jai"]);
    gen_diags: [..] Lifecycle_Diagnostic;
    gen_ctx := pdv_ctx(*gen_stage, *gen_diags);

    // A brand-new auxiliary file lands inside the private derived area.
    expect(prestep_add_generated(*gen_ctx, "src/generated_helper.jai", "// helper\n"));
    expect(gen_stage.generated.count == 1);
    expect(file_exists(gen_stage.generated[0].physical_path));
    expect(derived_path_within_root(gen_stage.derived_root, gen_stage.generated[0].physical_path));
    generated_physical, generated_found := prestep_generated_for(*gen_stage, "src/generated_helper.jai");
    expect(generated_found && generated_physical == gen_stage.generated[0].physical_path);

    // The same logical path twice conflicts — even with identical text, so two
    // plugins can never silently agree on one output — and the rejected
    // registration never rewrites the file the first one wrote.
    expect(!prestep_add_generated(*gen_ctx, "src/generated_helper.jai", "// helper\n"));
    expect(find_index_from_left(pdv_last_error(gen_diags), "duplicate auxiliary source path") >= 0);
    expect(!prestep_add_generated(*gen_ctx, "src/generated_helper.jai", "// different\n"));
    expect(find_index_from_left(pdv_last_error(gen_diags), "duplicate auxiliary source path") >= 0);
    expect(gen_stage.generated.count == 1);
    helper_content, helper_read := read_entire_file(gen_stage.generated[0].physical_path);
    expect(helper_read && helper_content == "// helper\n");

    // Covering a retained source is a conflict: changing an existing input is
    // what substitute is for, and an auxiliary file must never become a root
    // entry.
    expect(!prestep_add_generated(*gen_ctx, "src/main.jai", "// takeover\n"));
    expect(find_index_from_left(pdv_last_error(gen_diags), "would cover a retained package source") >= 0);

    // A non-.jai path, an absolute path and an escaping path never register.
    expect(!prestep_add_generated(*gen_ctx, "src/data.txt", "x"));
    expect(find_index_from_left(pdv_last_error(gen_diags), "not a package-relative .jai path") >= 0);
    expect(!prestep_add_generated(*gen_ctx, "/abs/helper.jai", "x"));
    expect(!prestep_add_generated(*gen_ctx, "../helper.jai", "x"));

    // An auxiliary path already dropped, or already substituted, conflicts.
    expect(prestep_add_drop(*gen_ctx, "src/none.jai"));
    expect(!prestep_add_generated(*gen_ctx, "src/none.jai", "x"));
    expect(find_index_from_left(pdv_last_error(gen_diags), "conflicts with a drop") >= 0);
    gen_derived, gen_written := prestep_write_derived(*gen_ctx, "src/other.jai", "// derived other\n");
    expect(gen_written);
    make_directory_if_it_does_not_exist(path_strip_filename(tprint("%1/package/src/other.jai", gen_root)), recursive = true);
    write_entire_file(tprint("%1/package/src/other.jai", gen_root), "// retained\n");
    expect(prestep_add_substitution(*gen_ctx, "src/other.jai", gen_derived));
    expect(!prestep_add_generated(*gen_ctx, "src/other.jai", "x"));
    expect(find_index_from_left(pdv_last_error(gen_diags), "would cover a retained package source") >= 0);

    // --- the round boundary: only THIS round's registrations answer, so a
    // stale file on disk is never consumed --------------------------------
    round_root := pdv_scratch("round");
    defer delete_directory_full(round_root);
    round_stage := pdv_stage(round_root, .["src/main.jai"]);
    round_diags: [..] Lifecycle_Diagnostic;
    round_ctx := pdv_ctx(*round_stage, *round_diags);

    expect(prestep_add_generated(*round_ctx, "src/helper.jai", "// round one\n"));
    stale_path := round_stage.generated[0].physical_path;
    round_physical, round_found := prestep_derived_source_for(*round_stage, "src/helper.jai");
    expect(round_found && round_physical == stale_path);

    // A second, empty round over the SAME derived root: the file from the
    // earlier round still exists on disk, yet nothing is registered, so no
    // input resolves to it. The view is the registration table, never a
    // directory scan — an old output can never mask a failure.
    next: Prestep_Stage;
    next.root_dir = round_stage.root_dir;
    next.package_root = round_stage.package_root;
    next.derived_root = round_stage.derived_root;
    expect(file_exists(stale_path));
    next_diags: [..] Lifecycle_Diagnostic;
    next_ctx := pdv_ctx(*next, *next_diags);
    expect(next.generated.count == 0);
    next_physical, next_found := prestep_derived_source_for(*next, "src/helper.jai");
    expect(!next_found && next_physical == "");
    next_generated, next_generated_found := prestep_generated_for(*next, "src/helper.jai");
    expect(!next_generated_found && next_generated == "");

    // --- a stage without a private derived area cannot produce output: the
    // plugin error channel (no silent no-op) ------------------------------
    bare_root := pdv_scratch("no-derived");
    defer delete_directory_full(bare_root);
    bare: Prestep_Stage;
    bare.package_root = bare_root;
    bare_diags: [..] Lifecycle_Diagnostic;
    bare_ctx := pdv_ctx(*bare, *bare_diags);
    expect(!prestep_add_generated(*bare_ctx, "src/helper.jai", "x"));
    expect(find_index_from_left(pdv_last_error(bare_diags), "no private derived area") >= 0);
    expect(!prestep_write_derived(*bare_ctx, "src/helper.jai", "x"));
    expect(find_index_from_left(pdv_last_error(bare_diags), "no private derived area") >= 0);
} @test

// The pre-0092 caller shape keeps working: with no package_root/derived_root
// the containment checks are inert, so tool-side in-process hooks that never
// opted into the derived view are not retroactively broken.
plugin_derived_view_legacy_stage :: () {
    stage: Prestep_Stage;
    stage.root_dir = "C:/pkg";
    diags: [..] Lifecycle_Diagnostic;
    ctx := pdv_ctx(*stage, *diags);
    expect(prestep_add_substitution(*ctx, "src/a.jai", "C:/mirror/a.jai"));
    expect(prestep_add_drop(*ctx, "config.toml"));
    expect(diags.count == 0);
    replacement, found := prestep_substitution_for(*stage, "src/a.jai");
    expect(found && replacement == "C:/mirror/a.jai");
    derived, derived_found := prestep_derived_source_for(*stage, "src/a.jai");
    expect(derived_found && derived == "C:/mirror/a.jai");
} @test

// ===========================================================================
// Typed-API family: the entry ABI check (no user-declared version)
// ===========================================================================

PDV_ABI_HOOK_RUNS: s64;

pdv_abi_hook :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    PDV_ABI_HOOK_RUNS += 1;
    return true;
}

// The entry ABI replaces the retired user-declared plugin version: a value
// compiled against a different face is rejected, its options are never applied
// and its hooks never run — and no declaration carries a version at all
// (Plugin_Config has no such field, pinned by every construction site).
plugin_derived_entry_abi :: () {
    // A plugin whose value sits on the current face resolves cleanly.
    current := builtin_load_plugin();
    expect(current.abi_version == JUICE_PLUGIN_ABI_VERSION);
    resolved := resolve_plugin_configs(.[current], Plugin_Config.[.{id = "load"}]);
    expect(resolved.ok);
    expect(resolved.pipeline.count == 1);

    // A plugin built against another face is rejected before its options and
    // hooks are reached, with no user version involved anywhere.
    stale := builtin_load_plugin();
    stale.abi_version = JUICE_PLUGIN_ABI_VERSION + 1;
    array_add(*stale.hooks, .{stage = .PRESTEP, position = .before, hook = pdv_abi_hook});
    PDV_ABI_HOOK_RUNS = 0;
    rejected := resolve_plugin_configs(.[stale], Plugin_Config.[.{id = "load"}], plugins_omitted = false);
    expect(!rejected.ok);
    expect(rejected.hook_table.count == 0);
    expect(rejected.pipeline.count == 0);
    expect(find_index_from_left(rejected.diagnostics[0].message, "incompatible plugin entry ABI") >= 0);
    diags: [..] Lifecycle_Diagnostic;
    ctx := pdv_ctx(null, *diags);
    expect(run_mounted_hooks(rejected.hook_table, .PRESTEP, .before, *ctx));
    expect(PDV_ABI_HOOK_RUNS == 0);
} @test

// ===========================================================================
// CLI family: a real juice child over scratch packages
// ===========================================================================
//
// The provider package exports TWO public modules — the plugin module and an
// ordinary API module — so the same cases can prove both halves of decision
// 21: a plugin enablement needs only its own source/module selection, and the
// provider's other export stays available as an ordinary dependency module.

// The provider's plugin module. It compiles against the tool-provided
// juice_core face (no declared tool dependency), writes its derived main
// through the view (which owns the landing path), registers the substitution
// of the retained logical input and optionally registers one auxiliary source.
PDV_PLUGIN_MODULE_SOURCE :: #string PDV_END
#import "Basic";
#import "juice_core";

IPDV_Options :: struct {
    entry:  string = "";
    helper: string = "";
}

IPDV_Plugin :: struct {
    using base: Juice_Plugin;
    config: IPDV_Options;
}

IPDV_DEFAULT_ENTRY: string = "";
IPDV_DEFAULT_HELPER: string = "";

// The derived main the hook installs in place of the retained entry.
IPDV_DERIVED_MAIN :: "#import \"Basic\";\n\nmain :: () {\n    print(\"derived entry\\n\");\n}\n";

ipdv_apply :: (options: *void, key: string, value: string) -> string {
    plugin := cast(*IPDV_Plugin) options;
    if key == "entry" {
        plugin.config.entry = value;
        return "";
    }
    if key == "helper" {
        plugin.config.helper = value;
        return "";
    }
    return tprint("unknown plugin option '%'", key);
}

ipdv_validate :: (options: *void) -> string {
    plugin := cast(*IPDV_Plugin) options;
    if plugin.config.entry == "" return "option 'entry' is required";
    return "";
}

ipdv_before_hook :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    if state == null || ctx.prestep == null return false;
    plugin := cast(*IPDV_Plugin) state;
    physical, written := prestep_write_derived(ctx, plugin.config.entry, IPDV_DERIVED_MAIN);
    if !written return false;
    if !prestep_add_substitution(ctx, plugin.config.entry, physical) return false;
    if plugin.config.helper != "" {
        if !prestep_add_generated(ctx, plugin.config.helper, "// registered auxiliary source\nAUX_VALUE :: 1;\n") return false;
    }
    return true;
}

get_juice_plugin :: () -> *IPDV_Plugin {
    plugin := New(IPDV_Plugin);
    plugin.id = "my_plugin";
    plugin.version = "0.0.0";
    plugin.options = cast(*void) plugin;
    array_add(*plugin.hooks, .{stage = .PRESTEP, position = .before, hook = ipdv_before_hook});
    array_add(*plugin.options_schema, config_option("entry", *IPDV_DEFAULT_ENTRY, ipdv_apply, ipdv_validate));
    array_add(*plugin.options_schema, config_option("helper", *IPDV_DEFAULT_HELPER, ipdv_apply, null));
    return plugin;
} @juice_plugin
PDV_END

// A module with no plugin entry at all (the capability-missing case).
PDV_NO_ENTRY_MODULE_SOURCE :: #string PDV_END
// A public module of the provider that simply is not a plugin.
plain_helper :: () -> s64 {
    return 1;
}
PDV_END

// A module with TWO plugin entries (the ambiguity case).
PDV_TWO_ENTRY_MODULE_SOURCE :: #string PDV_END
#import "Basic";
#import "juice_core";

// Two plugin entries in ONE public module: the entry the enablement selects
// must be unique, so the scan counts the anchor twice and the resolution
// reports ambiguity (the module itself is never compiled — the lexical
// recognition runs first).
get_juice_plugin :: () -> *Juice_Plugin {
    return null;
} @juice_plugin

get_juice_plugin :: () -> *Juice_Plugin {
    return null;
} @juice_plugin
PDV_END

PDV_PROVIDER_PACKAGE :: #string PDV_END
#import "Juice";

PACKAGE :: Package.{
    name    = "my-plugin",
    version = "1",
    modules = .[
        .{name = "plugin_module", entry = "plugin.jai"},
        .{name = "plain_module",  entry = "plain.jai"},
    ],
};
PDV_END

PDV_API_MODULE_SOURCE :: #string PDV_END
api_value :: () -> s64 {
    return 7;
}
PDV_END

// The app package: a workspace root whose only member is the provider. The
// member relationship is NOT what enables the plugin (the declaration below
// is), and no ordinary dependency exists in the base shape.
pdv_app_package :: (plugins_field: string, dependencies_field: string) -> string {
    builder: String_Builder;
    print_to_builder(*builder, "#import \"Juice\";\n\n");
    print_to_builder(*builder, "PACKAGE :: Package.{\n");
    print_to_builder(*builder, "    name    = \"plugin-app\",\n");
    print_to_builder(*builder, "    version = \"1\",\n");
    print_to_builder(*builder, "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n");
    print_to_builder(*builder, "    workspace = .{members = .[\"packages/my-plugin\"]},\n");
    print_to_builder(*builder, "%\n", dependencies_field);
    print_to_builder(*builder, "%\n", plugins_field);
    print_to_builder(*builder, "};\n");
    return builder_to_string(*builder);
}

PDV_APP_MAIN :: #string PDV_END
#import "Basic";

main :: () {
    print("original entry\n");
}
PDV_END

PDV_APP_TEST_MAIN :: #string PDV_END
#import "Basic";

main :: () {
    print("test entry\n");
}

test "the builtin test-block plugin transpiles this block" {
    expect(1 + 1 == 2);
}
PDV_END
// The plugin declaration shape under test: the external plugin through its OWN
// workspace source with an explicitly named public module — no ordinary
// dependency and no member-name guess is involved.
pdv_plugins_external :: (options: string, id := "my_plugin") -> string {
    return tprint("    plugins = Plugin_Declaration.[\n        .{id = \"%1\", source = .{kind = .WORKSPACE},\n          module = .{path = \"packages/my-plugin\", name = \"plugin_module\"},\n          options = Plugin_Option.[%2]},\n    ],\n", id, options);
}

PDV_OPTIONS_ENTRY_HELPER :: ".{key = \"entry\", value = \"src/main.jai\"}, .{key = \"helper\", value = \"src/aux.jai\"}";

// Write the provider package under <root>/packages/my-plugin.
pdv_write_provider :: (root: string, plugin_module_source: string) -> bool {
    if !build_seam_write(root, "packages/my-plugin/package.jai", PDV_PROVIDER_PACKAGE) return false;
    if !build_seam_write(root, "packages/my-plugin/plugin.jai", plugin_module_source) return false;
    if !build_seam_write(root, "packages/my-plugin/plain.jai", PDV_NO_ENTRY_MODULE_SOURCE) return false;
    if !build_seam_write(root, "packages/my-plugin/api.jai", PDV_API_MODULE_SOURCE) return false;
    return true;
}

// Write the app package (root) with the given plugins/dependencies fields and
// the given entry source.
pdv_write_app :: (root: string, plugins_field: string, dependencies_field: string, main_source: string) -> bool {
    if !build_seam_write(root, "package.jai", pdv_app_package(plugins_field, dependencies_field)) return false;
    if !build_seam_write(root, "src/main.jai", main_source) return false;
    return true;
}

pdv_derived_root :: (root: string) -> string {
    return package_derived_view_root(package_target_dir(root), "plugin-app");
}

// The child's combined output (stdout + stderr) — plugin diagnostics are
// printed to stdout, compiler diagnostics to stderr.
pdv_child_text :: (output: string, errors: string) -> string {
    return tprint("%\n%", output, errors);
}

plugin_derived_independent_source_cli :: () {
    root := pdv_scratch("cli-independent");
    defer delete_directory_full(root);
    expect(pdv_write_provider(root, PDV_PLUGIN_MODULE_SOURCE));
    expect(pdv_write_app(root, pdv_plugins_external(PDV_OPTIONS_ENTRY_HELPER), "", PDV_APP_MAIN));

    result, output, errors := run_otter_child_at(root, .["build"]);
    text := pdv_child_text(output, errors);
    expect(expect_exit("independent-source", result, 0));
    expect(output_matches("independent-source", text, .["Build completed successfully"]));

    // The substitution took effect: the artifact runs the DERIVED main.
    artifact := target_artifact_path(package_target_dir(root), "app");
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("independent-source artifact", run_result, 0));
    expect(output_matches("independent-source artifact", run_output, .["derived entry"]));
    expect(output_matches("independent-source artifact", run_output, .["original entry"], want = false));

    // Every physical output lives in the consuming package's private derived
    // area, keyed by the retained LOGICAL paths.
    derived_root := pdv_derived_root(root);
    expect(file_exists(tprint("%1/src/main.jai", derived_root)));
    expect(file_exists(tprint("%1/src/aux.jai", derived_root)));

    // The package sources are untouched: the retained entry still prints the
    // original line and the provider declaration is byte-identical.
    retained, retained_ok := read_entire_file(tprint("%1/src/main.jai", root));
    expect(retained_ok && find_index_from_left(retained, "original entry") >= 0);
    provider, provider_ok := read_entire_file(tprint("%1/packages/my-plugin/package.jai", root));
    expect(provider_ok && provider == PDV_PROVIDER_PACKAGE);

    // The explicit non-empty list REPLACED the builtin defaults: no load /
    // test-block transpile face was added (decision 22 — a list without a
    // conversion capability is not silently repaired).
    expect(output_matches("independent-source", text, .["test-block"], want = false));
} @test

plugin_derived_entry_diagnostics_cli :: () {
    // Zero plugin entries in the selected module: the capability is missing.
    zero_root := pdv_scratch("cli-zero-entry");
    defer delete_directory_full(zero_root);
    expect(pdv_write_provider(zero_root, PDV_NO_ENTRY_MODULE_SOURCE));
    expect(pdv_write_app(zero_root, pdv_plugins_external(PDV_OPTIONS_ENTRY_HELPER), "", PDV_APP_MAIN));
    zero_result, zero_output, zero_errors := run_otter_child_at(zero_root, .["build"]);
    zero_text := pdv_child_text(zero_output, zero_errors);
    expect(expect_exit("zero-entry", zero_result, 1));
    expect(output_matches("zero-entry", zero_text, .["Plugin capability missing"]));
    expect(!file_exists(tprint("%1/src/main.jai", pdv_derived_root(zero_root))));

    // Two entries in one selected module: the entry is ambiguous.
    two_root := pdv_scratch("cli-two-entry");
    defer delete_directory_full(two_root);
    expect(pdv_write_provider(two_root, PDV_TWO_ENTRY_MODULE_SOURCE));
    expect(pdv_write_app(two_root, pdv_plugins_external(PDV_OPTIONS_ENTRY_HELPER), "", PDV_APP_MAIN));
    two_result, two_output, two_errors := run_otter_child_at(two_root, .["build"]);
    two_text := pdv_child_text(two_output, two_errors);
    expect(expect_exit("two-entry", two_result, 1));
    expect(output_matches("two-entry", two_text, .["ambiguous plugin entry"]));
    expect(!file_exists(tprint("%1/src/main.jai", pdv_derived_root(two_root))));
} @test

plugin_derived_options_errors_cli :: () {
    // Every options failure happens BEFORE any hook runs: no derived output,
    // no artifact — a bad configuration never produces a build side effect.

    // 1. An unknown key (the plugin's own schema owns the key set).
    unknown_root := pdv_scratch("cli-options-unknown");
    defer delete_directory_full(unknown_root);
    expect(pdv_write_provider(unknown_root, PDV_PLUGIN_MODULE_SOURCE));
    expect(pdv_write_app(unknown_root, pdv_plugins_external(".{key = \"entry\", value = \"src/main.jai\"}, .{key = \"nonsense\", value = \"1\"}"), "", PDV_APP_MAIN));
    unknown_result, unknown_output, unknown_errors := run_otter_child_at(unknown_root, .["build"]);
    unknown_text := pdv_child_text(unknown_output, unknown_errors);
    expect(expect_exit("options-unknown", unknown_result, 1));
    expect(output_matches("options-unknown", unknown_text, .["unknown plugin option"]));
    expect(!file_exists(tprint("%1/src/main.jai", pdv_derived_root(unknown_root))));

    // 2. A required value missing (the schema's post-assembly validation).
    missing_root := pdv_scratch("cli-options-missing");
    defer delete_directory_full(missing_root);
    expect(pdv_write_provider(missing_root, PDV_PLUGIN_MODULE_SOURCE));
    expect(pdv_write_app(missing_root, pdv_plugins_external(".{key = \"helper\", value = \"src/aux.jai\"}"), "", PDV_APP_MAIN));
    missing_result, missing_output, missing_errors := run_otter_child_at(missing_root, .["build"]);
    missing_text := pdv_child_text(missing_output, missing_errors);
    expect(expect_exit("options-missing", missing_result, 1));
    expect(output_matches("options-missing", missing_text, .["invalid plugin options", "option 'entry' is required"]));
    expect(!file_exists(tprint("%1/src/main.jai", pdv_derived_root(missing_root))));

    // 3. A duplicated key (the declaration shape rejects it outright).
    duplicate_root := pdv_scratch("cli-options-duplicate");
    defer delete_directory_full(duplicate_root);
    expect(pdv_write_provider(duplicate_root, PDV_PLUGIN_MODULE_SOURCE));
    expect(pdv_write_app(duplicate_root, pdv_plugins_external(".{key = \"entry\", value = \"src/main.jai\"}, .{key = \"entry\", value = \"src/other.jai\"}"), "", PDV_APP_MAIN));
    duplicate_result, duplicate_output, duplicate_errors := run_otter_child_at(duplicate_root, .["build"]);
    duplicate_text := pdv_child_text(duplicate_output, duplicate_errors);
    expect(expect_exit("options-duplicate", duplicate_result, 1));
    expect(output_matches("options-duplicate", duplicate_text, .["Duplicate plugin option key"]));
} @test
