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
    for relative_path: retained {
        path := tprint("%1/%2", package_root, relative_path);
        make_directory_if_it_does_not_exist(path_strip_filename(path), recursive = true);
        write_entire_file(path, "// retained\n");
    }
    stage: Prestep_Stage;
    stage.root_dir = package_root;
    stage.package_root = package_root;
    stage.derived_root = derived_root;
    stage.target_root = tprint("%1/target", root);
    // The typed suite pins the THIRD-PARTY contract (the generated plugin host's
    // posture): every physical output stays inside the package's private target
    // areas. Juice's own in-process hooks leave the flag false.
    stage.enforce_private_output = true;
    return stage;
}

pdv_ctx :: (stage: *Prestep_Stage, diagnostics: *[..] Lifecycle_Diagnostic) -> Lifecycle_Context {
    lifecycle_context: Lifecycle_Context;
    lifecycle_context.diagnostics = diagnostics;
    lifecycle_context.prestep = stage;
    return lifecycle_context;
}

pdv_last_error :: (diagnostics: [] Lifecycle_Diagnostic) -> string {
    if diagnostics.count == 0 return "";
    return diagnostics[diagnostics.count - 1].message;
}

plugin_derived_view_rules :: () {
    // --- substitute: the logical input must be a retained package source, and
    // the replacement must live inside the private derived area -------------
    root := pdv_scratch("substitute");
    defer delete_directory_full(root);
    stage := pdv_stage(root, .["src/main.jai"]);
    diagnostics: [..] Lifecycle_Diagnostic;
    lifecycle_context := pdv_ctx(*stage, *diagnostics);

    // A replacement in the package sources (or anywhere else) is the read-only
    // violation: the source tree is never an output area.
    expect(!prestep_add_substitution(*lifecycle_context, "src/main.jai", tprint("%1/package/src/main.jai", root)));
    expect(find_index_from_left(pdv_last_error(diagnostics), "outside the package's private derived area") >= 0);

    // A logical path that invents a source the package does not have fails
    // too: substitute MAPS an existing input, it never creates one.
    expect(!prestep_add_substitution(*lifecycle_context, "src/missing.jai", tprint("%1/derived/x.jai", root)));
    expect(find_index_from_left(pdv_last_error(diagnostics), "not a retained package source") >= 0);

    // An absolute, backslashed or escaping logical path never resolves.
    expect(!prestep_add_substitution(*lifecycle_context, "../escape.jai", tprint("%1/derived/x.jai", root)));
    expect(find_index_from_left(pdv_last_error(diagnostics), "not a package-relative source path") >= 0);
    expect(!prestep_add_substitution(*lifecycle_context, "C:/abs.jai", tprint("%1/derived/x.jai", root)));
    expect(!prestep_add_substitution(*lifecycle_context, "src\\main.jai", tprint("%1/derived/x.jai", root)));

    // The accepted row keeps the LOGICAL path as its key (imports, diagnostics
    // and test attribution stay the package's own path) and stores the
    // physical file only for reading.
    replacement, written := prestep_write_derived(*lifecycle_context, "src/main.jai", "// derived main\n");
    expect(written && file_exists(replacement));
    expect(prestep_add_substitution(*lifecycle_context, "src/main.jai", replacement));
    physical, found := prestep_substitution_for(*stage, "src/main.jai");
    expect(found && physical == replacement);
    reverse, reverse_found := prestep_substitution_for(*stage, replacement);
    expect(!reverse_found && reverse == "");

    // --- drop: a repeated drop is a no-op; the same path cannot be both
    // dropped and substituted (either order) --------------------------------
    drop_root := pdv_scratch("drop");
    defer delete_directory_full(drop_root);
    drop_stage := pdv_stage(drop_root, .["src/main.jai", "src/skip.jai"]);
    drop_diagnostics: [..] Lifecycle_Diagnostic;
    drop_context := pdv_ctx(*drop_stage, *drop_diagnostics);

    expect(prestep_add_drop(*drop_context, "src/skip.jai"));
    expect(prestep_add_drop(*drop_context, "src/skip.jai"));       // idempotent
    expect(drop_diagnostics.count == 0);

    expect(!prestep_add_substitution(*drop_context, "src/skip.jai", tprint("%1/derived/skip.jai", drop_root)));
    expect(find_index_from_left(pdv_last_error(drop_diagnostics), "substitution conflicts with a drop") >= 0);

    drop_derived, drop_written := prestep_write_derived(*drop_context, "src/main.jai", "// derived main\n");
    expect(drop_written);
    expect(prestep_add_substitution(*drop_context, "src/main.jai", drop_derived));
    expect(!prestep_add_drop(*drop_context, "src/main.jai"));
    expect(find_index_from_left(pdv_last_error(drop_diagnostics), "drop conflicts with a source substitution") >= 0);

    // --- generated: explicit registration only, conflicts never resolve by
    // declaration order ------------------------------------------------------
    generated_root := pdv_scratch("generated");
    defer delete_directory_full(generated_root);
    generated_stage := pdv_stage(generated_root, .["src/main.jai"]);
    generated_diagnostics: [..] Lifecycle_Diagnostic;
    generated_context := pdv_ctx(*generated_stage, *generated_diagnostics);

    // A brand-new auxiliary file lands inside the private derived area.
    expect(prestep_add_generated(*generated_context, "src/generated_helper.jai", "// helper\n"));
    expect(generated_stage.generated.count == 1);
    expect(file_exists(generated_stage.generated[0].physical_path));
    expect(derived_path_within_root(generated_stage.derived_root, generated_stage.generated[0].physical_path));
    generated_physical, generated_found := prestep_generated_for(*generated_stage, "src/generated_helper.jai");
    expect(generated_found && generated_physical == generated_stage.generated[0].physical_path);

    // The same logical path twice conflicts — even with identical text, so two
    // plugins can never silently agree on one output — and the rejected
    // registration never rewrites the file the first one wrote.
    expect(!prestep_add_generated(*generated_context, "src/generated_helper.jai", "// helper\n"));
    expect(find_index_from_left(pdv_last_error(generated_diagnostics), "duplicate auxiliary source path") >= 0);
    expect(!prestep_add_generated(*generated_context, "src/generated_helper.jai", "// different\n"));
    expect(find_index_from_left(pdv_last_error(generated_diagnostics), "duplicate auxiliary source path") >= 0);
    expect(generated_stage.generated.count == 1);
    helper_content, helper_read := read_entire_file(generated_stage.generated[0].physical_path);
    expect(helper_read && helper_content == "// helper\n");

    // Covering a retained source is a conflict: changing an existing input is
    // what substitute is for, and an auxiliary file must never become a root
    // entry.
    expect(!prestep_add_generated(*generated_context, "src/main.jai", "// takeover\n"));
    expect(find_index_from_left(pdv_last_error(generated_diagnostics), "would cover a retained package source") >= 0);

    // A non-.jai path, an absolute path and an escaping path never register.
    expect(!prestep_add_generated(*generated_context, "src/data.txt", "x"));
    expect(find_index_from_left(pdv_last_error(generated_diagnostics), "not a package-relative .jai path") >= 0);
    expect(!prestep_add_generated(*generated_context, "/abs/helper.jai", "x"));
    expect(!prestep_add_generated(*generated_context, "../helper.jai", "x"));

    // An auxiliary path already dropped, or already substituted, conflicts.
    expect(prestep_add_drop(*generated_context, "src/none.jai"));
    expect(!prestep_add_generated(*generated_context, "src/none.jai", "x"));
    expect(find_index_from_left(pdv_last_error(generated_diagnostics), "conflicts with a drop") >= 0);
    generated_source_path, generated_written := prestep_write_derived(*generated_context, "src/other.jai", "// derived other\n");
    expect(generated_written);
    make_directory_if_it_does_not_exist(path_strip_filename(tprint("%1/package/src/other.jai", generated_root)), recursive = true);
    write_entire_file(tprint("%1/package/src/other.jai", generated_root), "// retained\n");
    expect(prestep_add_substitution(*generated_context, "src/other.jai", generated_source_path));
    expect(!prestep_add_generated(*generated_context, "src/other.jai", "x"));
    expect(find_index_from_left(pdv_last_error(generated_diagnostics), "would cover a retained package source") >= 0);

    // --- the round boundary: only THIS round's registrations answer, so a
    // stale file on disk is never consumed --------------------------------
    round_root := pdv_scratch("round");
    defer delete_directory_full(round_root);
    round_stage := pdv_stage(round_root, .["src/main.jai"]);
    round_diagnostics: [..] Lifecycle_Diagnostic;
    round_context := pdv_ctx(*round_stage, *round_diagnostics);

    expect(prestep_add_generated(*round_context, "src/helper.jai", "// round one\n"));
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
    next_diagnostics: [..] Lifecycle_Diagnostic;
    next_context := pdv_ctx(*next, *next_diagnostics);
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
    bare_diagnostics: [..] Lifecycle_Diagnostic;
    bare_context := pdv_ctx(*bare, *bare_diagnostics);
    expect(!prestep_add_generated(*bare_context, "src/helper.jai", "x"));
    expect(find_index_from_left(pdv_last_error(bare_diagnostics), "no private derived area") >= 0);
    expect(!prestep_write_derived(*bare_context, "src/helper.jai", "x"));
    expect(find_index_from_left(pdv_last_error(bare_diagnostics), "no private derived area") >= 0);
} @test

// The pre-0092 caller shape keeps working: with no package_root/derived_root
// the containment checks are inert, so tool-side in-process hooks that never
// opted into the derived view are not retroactively broken.
plugin_derived_view_legacy_stage :: () {
    stage: Prestep_Stage;
    stage.root_dir = "C:/pkg";
    diagnostics: [..] Lifecycle_Diagnostic;
    lifecycle_context := pdv_ctx(*stage, *diagnostics);
    expect(prestep_add_substitution(*lifecycle_context, "src/a.jai", "C:/mirror/a.jai"));
    expect(prestep_add_drop(*lifecycle_context, "config.toml"));
    expect(diagnostics.count == 0);
    replacement, found := prestep_substitution_for(*stage, "src/a.jai");
    expect(found && replacement == "C:/mirror/a.jai");
    derived, derived_found := prestep_derived_source_for(*stage, "src/a.jai");
    expect(derived_found && derived == "C:/mirror/a.jai");
} @test

// ===========================================================================
// Typed-API family: the entry ABI check (no user-declared version)
// ===========================================================================

PDV_ABI_HOOK_RUNS: s64;

pdv_abi_hook :: (lifecycle_context: *Lifecycle_Context, state: *void) -> bool {
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
    diagnostics: [..] Lifecycle_Diagnostic;
    lifecycle_context := pdv_ctx(null, *diagnostics);
    expect(run_mounted_hooks(rejected.hook_table, .PRESTEP, .before, *lifecycle_context));
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

ipdv_before_hook :: (lifecycle_context: *Lifecycle_Context, state: *void) -> bool {
    if state == null || lifecycle_context.prestep == null return false;
    plugin := cast(*IPDV_Plugin) state;
    physical, written := prestep_write_derived(lifecycle_context, plugin.config.entry, IPDV_DERIVED_MAIN);
    if !written return false;
    if !prestep_add_substitution(lifecycle_context, plugin.config.entry, physical) return false;
    if plugin.config.helper != "" {
        if !prestep_add_generated(lifecycle_context, plugin.config.helper, "// registered auxiliary source\nAUX_VALUE :: 1;\n") return false;
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

PDV_APP_TEST_MAIN_HEAD :: #string PDV_END
#import "Basic";

main :: () {
    print("test entry\n");
}
PDV_END

// The block header is composed at run time rather than written literally in
// this file: a raw #string block is not opaque to the test-block transpiler
// (pre-existing behavior, reproducible on the integration build), so a
// literal header here would be rewritten in this file's own view and the
// fixture would stop carrying the source it claims to.
pdv_app_test_main :: () -> string {
    return tprint("%1\ntest \"the builtin test-block plugin transpiles this block\" {\n    print(\"builtin test block ran\\n\");\n}\n", PDV_APP_TEST_MAIN_HEAD);
}
// The plugin declaration shape under test: the external plugin through its OWN
// workspace source with an explicitly named public module — no ordinary
// dependency and no member-name guess is involved.
pdv_plugins_external :: (options: string, id := "my_plugin") -> string {
    return tprint("    plugins = Plugin_Declaration.[\n        .{id = \"%1\", source = .{kind = .WORKSPACE},\n          module = .{path = \"packages/my-plugin\", name = \"plugin_module\"},\n          options = Plugin_Option.[%2]},\n    ],\n", id, options);
}

PDV_OPTIONS_ENTRY_HELPER :: ".{key = \"entry\", value = \"src/main.jai\"}, .{key = \"helper\", value = \"src/aux.jai\"}";

// The provider modules every provider shape in this file carries: the plugin
// module itself, a module without a plugin entry, and the API module the
// dependency-role case imports. Each shape still writes its own declaration (and
// any extra module) itself, so a case reads as the declaration it is about.
pdv_write_provider_modules :: (root: string, plugin_module_source: string) -> bool {
    if !build_seam_write(root, "packages/my-plugin/plugin.jai", plugin_module_source) return false;
    if !build_seam_write(root, "packages/my-plugin/plain.jai", PDV_NO_ENTRY_MODULE_SOURCE) return false;
    return build_seam_write(root, "packages/my-plugin/api.jai", PDV_API_MODULE_SOURCE);
}

// Write the provider package under <root>/packages/my-plugin.
pdv_write_provider :: (root: string, plugin_module_source: string) -> bool {
    if !build_seam_write(root, "packages/my-plugin/package.jai", PDV_PROVIDER_PACKAGE) return false;
    return pdv_write_provider_modules(root, plugin_module_source);
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

// Exit expectation that keeps the child's combined output in the failure
// report: a wrong exit code from a spawned CLI run is only diagnosable with
// what the child printed.
pdv_expect_child :: (name: string, result: Process_Result, want: s32, text: string) -> bool {
    if expect_exit(name, result, want) return true;
    print("[child %1] output:\n%2\n", name, text);
    return false;
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

// ===========================================================================
// CLI family: duplicate enablement and the ordinary-dependency role
// ===========================================================================

// A hook-less plugin module: it carries exactly one entry, contributes no
// faces and no options, so the cases that only need "this provider exports a
// plugin module AND a plain module" stay fast (no PRESTEP host spawn).
PDV_NOOP_PLUGIN_SOURCE :: #string PDV_END
#import "Basic";
#import "juice_core";

Noop_Plugin :: struct {
    using base: Juice_Plugin;
}

get_juice_plugin :: () -> *Noop_Plugin {
    plugin := New(Noop_Plugin);
    plugin.id = "noop_plugin";
    plugin.version = "0.0.0";
    plugin.options = cast(*void) plugin;
    return plugin;
} @juice_plugin
PDV_END

PDV_PROVIDER_PACKAGE_WITH_NOOP :: #string PDV_END
#import "Juice";

PACKAGE :: Package.{
    name    = "my-plugin",
    version = "1",
    modules = .[
        .{name = "plugin_module",      entry = "plugin.jai"},
        .{name = "noop_plugin_module", entry = "noop_plugin.jai"},
        .{name = "plain_module",       entry = "plain.jai"},
    ],
};
PDV_END

pdv_write_provider_with_noop :: (root: string) -> bool {
    if !build_seam_write(root, "packages/my-plugin/package.jai", PDV_PROVIDER_PACKAGE_WITH_NOOP) return false;
    if !build_seam_write(root, "packages/my-plugin/noop_plugin.jai", PDV_NOOP_PLUGIN_SOURCE) return false;
    return pdv_write_provider_modules(root, PDV_PLUGIN_MODULE_SOURCE);
}

// One dependency entry selecting a module of the provider.
pdv_dependency :: (name: string, module_name: string, alias := "", entry_module := "") -> string {
    alias_field := ifx alias == "" then "" else tprint(", alias = \"%\"", alias);
    path := ifx entry_module == "" then "packages/my-plugin" else entry_module;
    return tprint("    dependencies = Dependency.[.{name = \"%1\", source = .{kind = .WORKSPACE}, modules = .[.{path = \"%2\", name = \"%3\"%4}]}],\n", name, path, module_name, alias_field);
}

plugin_derived_duplicate_enablement_cli :: () {
    // The same ACTUAL plugin twice: different ids, same source and module. The
    // identity is the resolved source + provider directory + export, so a
    // different name cannot buy a second instance (decision 21).
    twice_root := pdv_scratch("cli-twice");
    defer delete_directory_full(twice_root);
    expect(pdv_write_provider(twice_root, PDV_PLUGIN_MODULE_SOURCE));
    duplicate_plugins := tprint("    plugins = Plugin_Declaration.[\n        .{id = \"my_plugin\", source = .{kind = .WORKSPACE}, module = .{path = \"packages/my-plugin\", name = \"plugin_module\"}, options = Plugin_Option.[%1]},\n        .{id = \"my_plugin_copy\", source = .{kind = .WORKSPACE}, module = .{path = \"packages/my-plugin\", name = \"plugin_module\"}, options = Plugin_Option.[%1]},\n    ],\n", PDV_OPTIONS_ENTRY_HELPER);
    expect(pdv_write_app(twice_root, duplicate_plugins, "", PDV_APP_MAIN));
    twice_result, twice_output, twice_errors := run_otter_child_at(twice_root, .["build"]);
    twice_text := pdv_child_text(twice_output, twice_errors);
    expect(expect_exit("twice", twice_result, 1));
    expect(output_matches("twice", twice_text, .["the same plugin is enabled twice"]));
    expect(!file_exists(tprint("%1/src/main.jai", pdv_derived_root(twice_root))));
} @test

plugin_derived_ordinary_dependency_roles_cli :: () {
    // The plugin module ALSO selected as an ordinary dependency module is one
    // actual module with two roles: rejected (decision 21). A different export
    // of the same provider is the legal way to use the provider's API.
    double_root := pdv_scratch("cli-double-role");
    defer delete_directory_full(double_root);
    expect(pdv_write_provider(double_root, PDV_PLUGIN_MODULE_SOURCE));
    expect(pdv_write_app(double_root, pdv_plugins_external(PDV_OPTIONS_ENTRY_HELPER), pdv_dependency("plugin-lib", "plugin_module", "plugin_lib"), PDV_APP_MAIN));
    double_result, double_output, double_errors := run_otter_child_at(double_root, .["build"]);
    double_text := pdv_child_text(double_output, double_errors);
    expect(expect_exit("double-role", double_result, 1));
    expect(output_matches("double-role", double_text, .["already selected by the ordinary dependency"]));
    expect(!file_exists(tprint("%1/src/main.jai", pdv_derived_root(double_root))));

    // The provider's OTHER public module as an ordinary dependency while its
    // plugin module is enabled: both work, in one build.
    api_root := pdv_scratch("cli-api-beside-plugin");
    defer delete_directory_full(api_root);
    expect(pdv_write_provider_with_noop(api_root));
    noop_plugins := "    plugins = Plugin_Declaration.[.{id = \"noop_plugin\", source = .{kind = .WORKSPACE}, module = .{path = \"packages/my-plugin\", name = \"noop_plugin_module\"}}],\n";
    api_main := #string PDV_END
#import "Basic";
#import "api";

main :: () {
    print("api value %\n", plain_helper());
}
PDV_END
    expect(pdv_write_app(api_root, noop_plugins, pdv_dependency("api-lib", "plain_module", "api"), api_main));
    api_result, api_output, api_errors := run_otter_child_at(api_root, .["build"]);
    api_text := pdv_child_text(api_output, api_errors);
    expect(expect_exit("api-beside-plugin", api_result, 0));
    expect(output_matches("api-beside-plugin", api_text, .["Build completed successfully"]));
    artifact := target_artifact_path(package_target_dir(api_root), "app");
    expect(file_exists(artifact));
    api_run, api_run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("api-beside-plugin artifact", api_run, 0));
    expect(output_matches("api-beside-plugin artifact", api_run_output, .["api value 1"]));
} @test

// ===========================================================================
// CLI family: the builtin triad (omitted / explicit empty / replaced)
// ===========================================================================

plugin_derived_builtin_triad_cli :: () {
    // Omitted: the builtin [load, test-block] pipeline runs, so the source's
    // test block is transpiled and executed.
    omitted_root := pdv_scratch("cli-builtin-omitted");
    defer delete_directory_full(omitted_root);
    expect(pdv_write_provider(omitted_root, PDV_PLUGIN_MODULE_SOURCE));
    expect(pdv_write_app(omitted_root, "", "", pdv_app_test_main()));
    omitted_result, omitted_output, omitted_errors := run_otter_child_at(omitted_root, .["build"]);
    omitted_text := pdv_child_text(omitted_output, omitted_errors);
    expect(pdv_expect_child("builtin-omitted", omitted_result, 0, omitted_text));
    expect(output_matches("builtin-omitted", omitted_text, .["Build completed successfully"]));

    // Explicit empty: NO plugin runs, builtins included — the same source no
    // longer compiles, because nothing rewrites the test block. This is the
    // declared consequence of an explicit empty list, not a regression.
    empty_root := pdv_scratch("cli-builtin-empty");
    defer delete_directory_full(empty_root);
    expect(pdv_write_provider(empty_root, PDV_PLUGIN_MODULE_SOURCE));
    expect(pdv_write_app(empty_root, "    plugins = Plugin_Declaration.[],\n", "", pdv_app_test_main()));
    empty_discovery, empty_discovered := discover_workspace(empty_root, pdv_scratch("cli-builtin-empty-cache"), plugin_face_modules_dir());
    expect(empty_discovered && empty_discovery.has_package);
    expect(empty_discovery.root_package.plugins.count == 0);
    expect(!empty_discovery.root_package.plugins_omitted);
    empty_result, empty_output, empty_errors := run_otter_child_at(empty_root, .["build"]);
    empty_text := pdv_child_text(empty_output, empty_errors);
    // No plugin ran at all: no registration file, no derived area, no host.
    expect(!file_exists(workspace_plugin_registration_path(package_target_dir(empty_root))));
    expect(!is_directory(pdv_derived_root(empty_root)));

    // The non-empty direction (a list without a conversion face) is pinned at
    // the resolver seam instead (plugin_derived_builtin_triad_resolver): the
    // CLI build path normalizes test blocks for BUILD independently of the
    // pipeline, so it cannot observe the difference.
} @test

// The explicit-empty triad at the resolver level (decision 22): an explicit
// empty list contributes no transpile face AND asks for no default, while an
// omitted list resolves to the builtin [load, test-block] pipeline. This is
// the precise statement the CLI case observes indirectly.
plugin_derived_builtin_triad_resolver :: () {
    empty := resolve_package_plugins(Plugin_Reference.[], plugins_omitted = false);
    expect(empty.ok);
    expect(empty.pipeline.count == 0);

    omitted := resolve_package_plugins(Plugin_Reference.[], plugins_omitted = true);
    expect(omitted.ok);
    expect(omitted.pipeline.count == 2);
    expect(omitted.pipeline[0].name == "load" && omitted.pipeline[1].name == "test-block");

    // A non-empty list without a conversion face is left alone: the defaults
    // are never supplemented.
    explicit := resolve_package_plugins(Plugin_Reference.[.{id = "load", builtin = true}], plugins_omitted = false);
    expect(explicit.ok);
    expect(explicit.pipeline.count == 1 && explicit.pipeline[0].name == "load");
} @test

// ===========================================================================
// CLI family: update never runs a build hook (decision 23)
// ===========================================================================

plugin_derived_update_runs_no_hook_cli :: () {
    root := pdv_scratch("cli-update");
    defer delete_directory_full(root);
    expect(pdv_write_provider(root, PDV_PLUGIN_MODULE_SOURCE));
    expect(pdv_write_app(root, pdv_plugins_external(PDV_OPTIONS_ENTRY_HELPER), "", PDV_APP_MAIN));

    result, output, errors := run_otter_child_at(root, .["update"]);
    text := pdv_child_text(output, errors);
    expect(expect_exit("update", result, 0));
    // Refreshing the resolution graph resolves the declared plugin sources but
    // never dispatches PRESTEP: no host, no derived output.
    expect(!file_exists(tprint("%1/src/main.jai", pdv_derived_root(root))));
    expect(!file_exists(plugin_host_path(package_target_dir(root))));
    expect(output_matches("update", text, .["derived entry"], want = false));
} @test

// ===========================================================================
// Typed-API family: one package operation prepares a package exactly once
// ===========================================================================

// The command-layer single-prepare interface: resolving the same package twice
// returns the SAME context (no second scan, no second registration, no second
// derived area), which is what keeps a build front, a second program and a
// re-entered prerequisite phase from enabling a package's plugins twice.
plugin_derived_prepare_once :: () {
    root := pdv_scratch("prepare-once");
    defer delete_directory_full(root);
    expect(pdv_write_provider(root, PDV_PLUGIN_MODULE_SOURCE));
    expect(pdv_write_app(root, pdv_plugins_external(PDV_OPTIONS_ENTRY_HELPER), "", PDV_APP_MAIN));

    discovery, discovered := discover_workspace(root, pdv_scratch("prepare-once-cache"), plugin_face_modules_dir());
    expect(discovered && discovery.has_package);
    prepared: Prepared_Workspace;
    prepared.discovery = discovery;

    preparation: Plugin_Preparation;
    first := plugin_prepare_once_for(*preparation, *prepared, discovery.root_package);
    expect(first.ok);
    expect(first.prepare_count == 1);
    expect(first.sources.count == 1);
    expect(first.sources[0].module_export == "plugin_module");
    expect(first.sources[0].package_dir == path_slashes(tprint("%1/packages/my-plugin", root)));
    expect(first.registration_path != "" && file_exists(first.registration_path));
    expect(first.derived_root == package_derived_view_root(package_target_dir(root), "plugin-app"));

    // The same package again: the same context, still prepared once.
    second := plugin_prepare_once_for(*preparation, *prepared, discovery.root_package);
    expect(second == first);
    expect(second.prepare_count == 1);
    expect(preparation.packages.count == 1);

    // A DIFFERENT package gets its own context and its own private derived
    // area — per-package isolation, never a shared view.
    member := discovery.member_packages[1];
    other := plugin_prepare_once_for(*preparation, *prepared, member);
    expect(preparation.packages.count == 2);
    expect(other.derived_root != first.derived_root);
    expect(other.package_dir == path_slashes(member.dir));
} @test

// ===========================================================================
// CLI family: the builtin triad observed through the TEST command
// ===========================================================================
//
// The build path normalizes test blocks for BUILD independently of the pipeline,
// so an omitted / empty / non-empty `plugins` field cannot be told apart through
// `juice build` alone (the build-only triad lives above). The TEST command
// transpiles WITH the resolved pipeline, so a test block is the observable: it
// compiles and runs only when a conversion face is really in the pipeline.

// A consuming package with an OPTIONAL single workspace member. The triad cases
// need the no-member shape (a declared member directory that does not exist is a
// discovery error, not a plugin question) and the isolation case needs exactly
// one real member.
pdv_write_app_shaped :: (root: string, plugins_field: string, member_directory: string, main_source: string) -> bool {
    workspace_field := ifx member_directory == "" then "" else tprint("    workspace = .{members = .[\"%\"]},\n", member_directory);
    manifest := tprint("#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"plugin-app\",\n    version = \"1\",\n    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n%1%2};\n", workspace_field, plugins_field);
    if !build_seam_write(root, "package.jai", manifest) return false;
    if !build_seam_write(root, "src/main.jai", main_source) return false;
    return true;
}

plugin_derived_builtin_triad_test_cli :: () {
    // Omitted: the builtin [load, test-block] pipeline converts the block and
    // the test runs.
    omitted_root := pdv_scratch("cli-triad-test-omitted");
    defer delete_directory_full(omitted_root);
    expect(pdv_write_app_shaped(omitted_root, "", "", pdv_app_test_main()));
    omitted_result, omitted_output, omitted_errors := run_otter_child_at(omitted_root, .["test"]);
    omitted_text := pdv_child_text(omitted_output, omitted_errors);
    expect(expect_exit("triad-test-omitted", omitted_result, 0));
    expect(output_matches("triad-test-omitted", omitted_text, .[
        "builtin test block ran",
        "1 passed, 0 failed",
    ]));

    // Explicit empty: nothing converts the block, so the same source no longer
    // compiles. The command fails at the compile with the compiler's own
    // diagnostic — the declared consequence of an empty list — and no
    // registration lands.
    empty_root := pdv_scratch("cli-triad-test-empty");
    defer delete_directory_full(empty_root);
    expect(pdv_write_app_shaped(empty_root, "    plugins = Plugin_Declaration.[],\n", "", pdv_app_test_main()));
    empty_result, empty_output, empty_errors := run_otter_child_at(empty_root, .["test"]);
    empty_text := pdv_child_text(empty_output, empty_errors);
    if empty_result.exit_code != 1 {
        manifest_debug, manifest_debug_ok := read_entire_file(tprint("%1/package.jai", empty_root));
        print("[triad-test-empty] exit %, output:\n%\n", empty_result.exit_code, empty_text);
        if manifest_debug_ok print("[triad-test-empty] manifest:\n%\n", manifest_debug);
        for dir: dr_subdirectories(tprint("%1/target/transpile", empty_root)) {
            view_text, view_ok := read_entire_file(tprint("%1/src/main.jai", dir));
            if view_ok print("[triad-test-empty] view %:\n%\n", dir, view_text);
        }
        _evaluation_source, evaluation_data := manifest_temp_file_names(get_juice_content_cache_root().path, empty_root);
        evaluation_text, evaluation_ok := read_entire_file(evaluation_data);
        if evaluation_ok print("[triad-test-empty] manifest data %:\n%\n", evaluation_data, evaluation_text);
    }
    expect(expect_exit("triad-test-empty", empty_result, 1));
    expect(output_matches("triad-test-empty", empty_text, .["[juice ERROR] Test compilation failed."]));
    expect(output_matches("triad-test-empty", empty_text, .["Semicolon expected after expression."]));
    expect(output_matches("triad-test-empty", empty_text, .["1 passed, 0 failed"], want = false));
    expect(!file_exists(workspace_plugin_registration_path(package_target_dir(empty_root))));

    // Explicit non-empty naming the conversion face: the same block compiles and
    // runs. A non-empty list enables exactly what it names.
    named_root := pdv_scratch("cli-triad-test-named");
    defer delete_directory_full(named_root);
    expect(pdv_write_app_shaped(named_root, "    plugins = Plugin_Declaration.[.{builtin = \"test-block\"}],\n", "", pdv_app_test_main()));
    named_result, named_output, named_errors := run_otter_child_at(named_root, .["test"]);
    named_text := pdv_child_text(named_output, named_errors);
    expect(expect_exit("triad-test-named", named_result, 0));
    expect(output_matches("triad-test-named", named_text, .[
        "builtin test block ran",
        "1 passed, 0 failed",
    ]));

    // Explicit non-empty WITHOUT a conversion face (a real external plugin): the
    // defaults are never supplemented, so the block fails exactly like the empty
    // list — yet the declaration was honored: the plugin was enabled, its module
    // compiled and its registration landed. "Enabled" is not a synonym for
    // "adds a conversion capability".
    external_root := pdv_scratch("cli-triad-test-external");
    defer delete_directory_full(external_root);
    expect(pdv_write_provider_with_noop(external_root));
    noop_plugins := "    plugins = Plugin_Declaration.[.{id = \"noop_plugin\", source = .{kind = .WORKSPACE}, module = .{path = \"packages/my-plugin\", name = \"noop_plugin_module\"}}],\n";
    expect(pdv_write_app_shaped(external_root, noop_plugins, "packages/my-plugin", pdv_app_test_main()));
    external_result, external_output, external_errors := run_otter_child_at(external_root, .["test"]);
    external_text := pdv_child_text(external_output, external_errors);
    if external_result.exit_code != 1 print("[triad-test-external] exit %, output:\n%\n", external_result.exit_code, external_text);
    expect(expect_exit("triad-test-external", external_result, 1));
    expect(output_matches("triad-test-external", external_text, .["[juice ERROR] Test compilation failed."]));
    // No plugin error: the enablement itself resolved and registered.
    expect(output_matches("triad-test-external", external_text, .["Plugin capability missing"], want = false));
    expect(output_matches("triad-test-external", external_text, .["Could not prepare the workspace's plugin declarations"], want = false));
    registration := workspace_plugin_registration_path(package_target_dir(external_root));
    expect(file_exists(registration));
    // The registration imports the plugin's PRIVATE name, never the bare
    // declaration id: enabling a plugin adds no ordinary import name
    // (decision 21, issue 0098 S12).
    expect(file_contains(registration, "JUICE_PLUGIN_0 :: #import \"noop_plugin__plugin_"));
    expect(file_contains(registration, "JUICE_PLUGIN_0 :: #import \"noop_plugin\";") == false);
} @test

// ===========================================================================
// CLI family: an unselected member's own plugin declaration stays inert
// ===========================================================================

plugin_derived_unselected_member_isolation_cli :: () {
    root := pdv_scratch("cli-member-isolation");
    defer delete_directory_full(root);
    // The root declares the EMPTY list (nothing of its own runs), and the member
    // declares its own plugin whose source directory does not exist: if the
    // root's operation resolved member declarations, this build would fail.
    expect(pdv_write_app_shaped(root, "    plugins = Plugin_Declaration.[],\n", "packages/plugin-member", PDV_APP_MAIN));
    expect(build_seam_write(root, "packages/plugin-member/package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    version = \"1\",\n    name    = \"plugin-member\",\n    modules = .[.{name = \"member_module\", entry = \"module.jai\"}],\n    plugins = Plugin_Declaration.[\n        .{id = \"member_plugin\", source = .{kind = .PATH, path = \"vendor/my-plugin\"}, module = .{name = \"plugin_module\"}},\n    ],\n};\n"));
    expect(build_seam_write(root, "packages/plugin-member/module.jai", "member_value :: () -> s64 {\n    return 1;\n}\n"));

    result, output, errors := run_otter_child_at(root, .["build"]);
    text := pdv_child_text(output, errors);
    expect(expect_exit("member-isolation", result, 0));
    expect(output_matches("member-isolation", text, .["Build completed successfully"]));
    expect(output_matches("member-isolation", text, .["member_plugin"], want = false));

    // Nothing of the member's plugin ran: no scan, no registration, no host, no
    // private derived view, and no member import shim. The isolation is that
    // strong — the unselected package is not even fetched.
    expect(!is_directory(target_plugins_dir(package_target_dir(root))));
    expect(!file_exists(workspace_plugin_registration_path(package_target_dir(root))));
    expect(!file_exists(plugin_registration_path(package_target_dir(root), "plugin-member")));
    expect(!file_exists(plugin_host_path(package_target_dir(root))));
    expect(!is_directory(package_derived_view_root(package_target_dir(root), "plugin-member")));
    expect(!file_exists(tprint("%1/plugin-member.jai", packages_dir(root))));
    // The root's own artifact still exists: the operation was not silently
    // skipped.
    expect(file_exists(target_artifact_path(package_target_dir(root), "app")));
} @test

// ===========================================================================
// CLI family: a Git plugin source, and the shared checkout stays read-only
// ===========================================================================

// A standalone consuming package (no workspace, no member): the Git and sibling
// PATH cases need the plugin declaration to be the only plugin input.
pdv_write_standalone_app :: (root: string, plugins_field: string, main_source: string) -> bool {
    return pdv_write_app_shaped(root, plugins_field, "", main_source);
}

plugin_derived_git_source_read_only_cli :: () {
    scratch := dr_scratch("plugin-git-source");
    dr_isolate(scratch);
    defer dr_restore_env();
    provider_repository := dr_path(scratch, "provider_repository");
    expect(dr_git_init(provider_repository));
    // The provider package at the repository root: one public plugin module whose
    // PRESTEP hook writes its derived main through the view.
    expect(dr_write_file(provider_repository, "package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    version = \"1\",\n    name    = \"git-plugin\",\n    modules = .[.{name = \"plugin_module\", entry = \"plugin.jai\"}],\n};\n"));
    expect(dr_write_file(provider_repository, "plugin.jai", PDV_PLUGIN_MODULE_SOURCE));
    commit := copy_string(dr_git_commit_all(provider_repository, "plugin provider"));
    expect(commit.count == 40);

    app := dr_path(scratch, "app");
    git_plugins := copy_string(tprint("    plugins = Plugin_Declaration.[\n        .{id = \"my_plugin\", source = .{kind = .GIT, git = .{url = \"%1\"}}, module = .{name = \"plugin_module\"}, options = Plugin_Option.[%2]},\n    ],\n", provider_repository, PDV_OPTIONS_ENTRY_HELPER));
    expect(pdv_write_standalone_app(app, git_plugins, PDV_APP_MAIN));

    result, output, errors := run_otter_child_at(app, .["build"]);
    text := pdv_child_text(output, errors);
    expect(expect_exit("git-source", result, 0));
    expect(output_matches("git-source", text, .["Build completed successfully"]));
    // The Git-sourced plugin ran: its substitution produced the derived entry.
    expect(file_exists(tprint("%1/src/main.jai", pdv_derived_root(app))));
    artifact := target_artifact_path(package_target_dir(app), "app");
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("git-source artifact", run_result, 0));
    expect(output_matches("git-source artifact", run_output, .["derived entry"]));

    // The shared checkout is a real Git working tree under the content cache. The
    // plugin read its module from there and wrote every output into the consuming
    // package's private area, so the checkout is still pristine: not one tracked
    // or untracked change.
    environment: Resolution_Environment;
    environment.content_cache_root = get_juice_content_cache_root().path;
    checkout := git_content_checkout_directory(environment, path_slashes(provider_repository), commit);
    expect(is_directory(checkout));
    expect(file_exists(tprint("%1/plugin.jai", checkout)));
    status_result, status := dr_git(string.["-C", checkout, "status", "--porcelain"]);
    expect(status_result.exit_code == 0);
    expect(status == "");

    // A module path that escapes the checkout is rejected (spec 0087 decision 12:
    // 越出检出根直接报错). The GIT source resolves; the selection does not.
    escape_plugins := copy_string(tprint("    plugins = Plugin_Declaration.[\n        .{id = \"my_plugin\", source = .{kind = .GIT, git = .{url = \"%1\"}}, module = .{path = \"../..\", name = \"plugin_module\"}},\n    ],\n", provider_repository));
    expect(pdv_write_standalone_app(app, escape_plugins, PDV_APP_MAIN));
    escape_result, escape_output, escape_errors := run_otter_child_at(app, .["build"]);
    escape_text := pdv_child_text(escape_output, escape_errors);
    expect(expect_exit("git-escape", escape_result, 1));
    expect(output_matches("git-escape", escape_text, .["module path escapes its source root: ../.."]));
    expect(output_matches("git-escape", escape_text, .["Could not prepare the workspace's plugin declarations"]));
    // The source repository itself was never written to either.
    repository_status_result, repository_status := dr_git(string.["-C", provider_repository, "status", "--porcelain"]);
    expect(repository_status_result.exit_code == 0);
    expect(repository_status == "");
} @test

// ===========================================================================
// CLI family: a local sibling PATH source, and its source-root boundary
// ===========================================================================
//
// Spec 0081 decision 3 / decision 45: a local path source is resolved relative
// to the declaring package and MAY point at a sibling directory outside the
// workspace, with no member requirement. The sibling range is therefore a
// capability, not a restriction — what IS bounded is the module path: it must
// stay inside the resolved source root (decision 12/45). Both halves run here on
// a real sibling package outside the consuming workspace root.

plugin_derived_sibling_path_source_cli :: () {
    root := pdv_scratch("cli-sibling-path");
    defer delete_directory_full(root);
    // The provider lives OUTSIDE the consuming package's workspace root.
    provider := tprint("%1/sibling-plugin", path_strip_filename(root));
    delete_directory_full(provider);
    defer delete_directory_full(provider);
    expect(build_seam_write(provider, "package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    version = \"1\",\n    name    = \"sibling-plugin\",\n    modules = .[.{name = \"plugin_module\", entry = \"plugin.jai\"}],\n};\n"));
    expect(build_seam_write(provider, "plugin.jai", PDV_PLUGIN_MODULE_SOURCE));

    // The app: no workspace, no member, no ordinary dependency — only its own
    // PATH source pointing at the sibling directory.
    sibling_plugins := copy_string(tprint("    plugins = Plugin_Declaration.[\n        .{id = \"my_plugin\", source = .{kind = .PATH, path = \"../sibling-plugin\"}, module = .{name = \"plugin_module\"}, options = Plugin_Option.[%1]},\n    ],\n", PDV_OPTIONS_ENTRY_HELPER));
    expect(pdv_write_standalone_app(root, sibling_plugins, PDV_APP_MAIN));

    result, output, errors := run_otter_child_at(root, .["build"]);
    text := pdv_child_text(output, errors);
    expect(expect_exit("sibling-path", result, 0));
    expect(output_matches("sibling-path", text, .["Build completed successfully"]));
    artifact := target_artifact_path(package_target_dir(root), "app");
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("sibling-path artifact", run_result, 0));
    expect(output_matches("sibling-path artifact", run_output, .["derived entry"]));
    // The sibling SOURCE tree stays read-only: only the consuming package's
    // private derived area received output.
    provider_source, provider_ok := read_entire_file(tprint("%1/plugin.jai", provider));
    expect(provider_ok && provider_source == PDV_PLUGIN_MODULE_SOURCE);
    expect(file_exists(tprint("%1/src/main.jai", pdv_derived_root(root))));

    // The module path is the bounded half: it must stay inside the resolved
    // source root, so a selection that climbs out is rejected before any hook.
    escape_plugins := copy_string(tprint("    plugins = Plugin_Declaration.[\n        .{id = \"my_plugin\", source = .{kind = .PATH, path = \"../sibling-plugin\"}, module = .{path = \"..\", name = \"plugin_module\"}},\n    ],\n"));
    expect(pdv_write_standalone_app(root, escape_plugins, PDV_APP_MAIN));
    escape_result, escape_output, escape_errors := run_otter_child_at(root, .["build"]);
    escape_text := pdv_child_text(escape_output, escape_errors);
    expect(expect_exit("sibling-escape", escape_result, 1));
    expect(output_matches("sibling-escape", escape_text, .["module path escapes its source root: .."]));
} @test
