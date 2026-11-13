// Plugin surface (ticket 024; extended by 056): the Juice_Plugin struct —
// one value declares every face a plugin contributes: identity (id +
// version — feeds the pipeline description and the cache keys), the
// transpile pipeline contribution (a nullable pointer; a non-null face joins
// the declaration-order pipeline and inherits the line-fidelity contract and
// the paired probe hooks), the lifecycle hooks, the lint rule face (ticket
// 041), the options pointer (the plugin instance, so the framework can apply
// schema rows through *void) and the options schema. Plus the
// get_juice_plugin acquisition contract, the Config_Option shape
// {default, apply, validate}, the Plugin_Config / Option_Row shared config
// types, the static registry of built-in plugins, the merge/dup-check
// surface (returns the registry) and the declaration-driven resolver
// resolve_plugin_configs (ticket 056).
//
// get_juice_plugin contract (spec §5.1, decided shape): a plugin module
// defines `get_juice_plugin :: () -> *Juice_Plugin`, annotated with the
// @juice_plugin tail note (the discovery anchor — ticket 025's lexical
// scan), returning a pointer to a plugin struct of its own: `using`
// inheritance of Juice_Plugin plus typed options members. The derived
// pointer is what makes typed options compile-time checked — configuration
// code assigns the typed members directly on the result; the framework
// consumes through the as_plugin explicit upcast (a cast from a non-using
// struct fails at compile time — the type gate). The built-ins below follow
// the same shape as any third-party plugin.
//
// The typed options member must NOT be named `options`: Juice_Plugin.options
// is the *void framework channel (the plugin instance pointer), and Jai
// rejects a derived struct member redeclaring a using-imported base member
// (spike-pinned). Plugins pick their own name (the fixtures use `config`);
// Config_Option.apply / validate cast the *void channel back to the derived
// type and write/read that typed member.
//
// Config_Option (the reference shape {name, default, validate}, extended by 056):
// default is a pointer to the plugin's own typed default value (module-held
// storage; the framework reads it, never writes). apply writes one string
// option row into the typed options through the *void channel — the plugin
// owns the key set, so an unknown key returns a non-empty error message.
// validate re-checks the assembled options after every row was applied
// ("" = pass, non-empty = rejection message, null = skip). The effective
// default is the options struct's declared member defaults — the plugin
// author keeps both consistent.
//
// Lint face (ticket 041, spec §5.1/§8.2): a nullable Lint_Plugin pointer on
// Juice_Plugin. The rule identity is its name — empty names are rejected
// and two rules sharing one name across plugins conflict at merge time (two
// observers sharing a name would silently double-report). The observer
// receives a collected test's typechecked header and its flattened
// subexpressions and returns findings; line/column are 1-based by contract
// (the plugin converts the compiler's 0-based AST positions while reading
// them). The host invoking the observers is the generated test metaprogram
// (ticket 042); this module only carries the face and the merge collection.
// The Compiler import below exists for the header/node types alone — plugin
// stays part of the juice_core #load closure, so the publication artifact
// set and its text contract are unchanged.
//
// Built-in registry: static by design (spec §5.2, research A§4.1). The
// built-ins ship with the tool and belong to the explicit bootstrap #load
// set, so auto-discovery buys nothing for them — the registry below is an
// explicit list wrapping the two built-in transpile plugins (tickets
// 022/023) as Juice_Plugin values in declaration order (#load first, then
// test-block — the default pipeline order). Third-party plugins join the
// same registration surface through the scan + registration codegen
// (ticket 025); merge_plugins consumes both.
//
// Merge/dup-check (spec §5.2): duplicate ids / version conflicts / at-hook
// mount conflicts / transpile name conflicts / lint name conflicts are all
// rejected with diagnostics and ok=false — the caller must refuse to
// continue. Since ticket 056 the merged product keeps the registry (every
// plugin value with all its faces) plus the merged lint list; the
// declaration-driven selection happens in resolve_plugin_configs below —
// merge knows no declarations. The pipeline and the hook table are
// resolver products; merge no longer pre-filters them. An empty registry
// resolves to the built-ins (the same convention as resolve_pipeline, so a
// view and its key always reflect the same pipeline).
//
// Resolver (ticket 056, spec §5.2 合并 vs 选择): resolve_plugin_configs
// filters the registry by the Package.plugins declaration order and yields
// the transpile pipeline, the lint observation order, the hook table (slot
// aligned: one options pointer per registration) and the diagnostics. The
// default-pipeline rule lives here too: no declared transpile face means the
// built-in [load, test-block] pipeline. Unknown ids / version mismatches /
// one package providing several plugins / option schema rejections all
// produce diagnostics with ok=false. Undeclared plugins never contribute
// hooks, lint or transpile.
//
// The command process holds built-in plugin values only (Phase-1 boundary):
// member plugin values live in the generated test metaprogram (and the
// Phase-2 host). The command-side adapter resolve_package_plugins
// (src/transpile_config.jai) therefore filters member declarations out
// before calling this resolver; member identity/version/options validation
// happens where the values exist.
//
// Merge semantics (pinned by this ticket): `at` mounts are exclusive — two
// at hooks on one stage would race for the stage's implementation, so the
// second is a registration error; before/after hooks may stack freely on
// one mount (registration order = execution order). The transpile face's
// pipeline identity is its name — two plugins contributing transpile faces
// with the same name conflict (otter's Transpile_Plugin carries no keyword
// claims; this is the keyword-claim conflict's otter equivalent). The
// lint face's rule identity is likewise its name — an empty name or a
// cross-plugin duplicate rejects (ticket 041).
//
// Load order note: this file's references to Transpile_Plugin /
// Transpile_Diagnostic (src/transpile_plugin.jai / src/transpile.jai) are
// forward references in the test program's lexical discovery order — Jai
// resolves whole-program declarations, so the struct fields and procedure
// bodies here compile regardless (the same cross-file default-reference
// family as workspace.jai's seams).
//
// This module is a bootstrap #load target and must stay test-free; its unit
// tests live in tests/plugin_tests.jai (0053 rule). main.jai stays untouched
// — the first production consumer of the merge surface is ticket 027.

#import "Basic";
#import "Compiler";

// ---------------------------------------------------------------------------
// Options schema
// ---------------------------------------------------------------------------

// One options schema entry (the reference shape {name, default, validate},
// extended with the ticket 056 apply row). default = a pointer to the
// plugin's typed default value (module-held storage; the framework reads it
// for reporting, never writes). apply = write one string option row into the
// typed options through the *void channel; the plugin owns the key set, so
// an unknown key returns a non-empty error message ("" = applied). validate
// = the post-assembly check after every row was applied: the options pointer
// is the plugin itself, read via a using downcast back to the derived
// struct; "" = pass, non-empty = rejection message, null = skip.
Config_Option :: struct {
    name:     string;
    default:  *void;
    apply:    (options: *void, key: string, value: string) -> string;
    validate: (options: *void) -> string;
}

// Typed construction: default accepts any type's pointer (compile-time
// polymorphism erased into *void — the heterogeneous options-type boundary).
config_option :: (name: string, default: *$T,
                  apply: (options: *void, key: string, value: string) -> string,
                  validate: (options: *void) -> string) -> Config_Option {
    return .{ name = name, default = cast(*void) default, apply = apply, validate = validate };
}

// ---------------------------------------------------------------------------
// Shared plugin configuration types (host and static paths)
// ---------------------------------------------------------------------------

// One declared option row: the string key/value pair Package.plugins carries
// (the manifest protocol's PLUGIN_OPTION record decoded). The plugin face's
// own copy of the row shape — the host driver embeds Plugin_Config values
// as constants and must not depend on the Juice module face.
Option_Row :: struct {
    key:   string;
    value: string;
}

// One declared plugin configuration: id + version + option rows, in
// declaration order when held in an array. The static command path and the
// generated plugin host share this type; resolve_plugin_configs consumes it.
// (Package.plugins is the manifest face's own declaration shape; the command
// converts declarations to this shared shape at the resolver boundary.)
Plugin_Config :: struct {
    id:      string;
    version: string;
    options: [] Option_Row;
}

// ---------------------------------------------------------------------------
// Lint face
// ---------------------------------------------------------------------------

// Finding levels — the host maps them onto the compiler_report three-sink
// (WARNING / ERROR / INFO). WARNING is the zero member and the default: a
// zero-initialized or forgotten level stays advisory and never changes the
// exit code. ERROR must be spelled explicitly (the review fix made the enum
// zero-safe; the order changed pre-release before any face shipped).
Lint_Level :: enum {
    WARNING;
    ERROR;
    INFO;
}

// One finding: 1-based line and column by contract (the plugin converts
// from the compiler's 0-based AST positions while reading the header /
// subexpression locations; the host does not convert again), plus the
// message and the level.
Lint_Finding :: struct {
    line:    s64;
    column:  s64;
    message: string;
    level:   Lint_Level = .WARNING;
}

// One lint rule face: the rule identity (name is the merged identity —
// merge_plugins rejects empty names and cross-plugin duplicates; version is
// reporting metadata) and the observer. The host calls inspect_test_header
// once per collected test procedure with the procedure's typechecked header
// and its flattened subexpressions, at the same collection point as test
// discovery (ticket 042).
Lint_Plugin :: struct {
    name:                string;
    version:             string;
    inspect_test_header: #type (header: *Code_Procedure_Header, subexpressions: [] *Code_Node) -> [..] Lint_Finding;
}

// ---------------------------------------------------------------------------
// Juice_Plugin
// ---------------------------------------------------------------------------

// The unified plugin declaration face (spec §5.1, all fields). Plugin
// structs inherit it with `using` and add typed options members (the
// get_juice_plugin contract above).
Juice_Plugin :: struct {
    id:             string;                    // identity: feeds the pipeline
                                               // description and the cache
                                               // keys
    version:        string;
    transpile:      *Transpile_Plugin = null;  // transpile pipeline face
                                               // (nullable; a non-null face
                                               // joins the declaration-order
                                               // pipeline and inherits the
                                               // line-fidelity contract and
                                               // the paired probe hooks)
    lint:           *Lint_Plugin = null;       // lint rule face (nullable; a
                                               // non-null face joins the
                                               // merged lint rule list and
                                               // its name feeds the
                                               // cross-plugin dup-check)
    hooks:          [..] Lifecycle_Hook;       // lifecycle mounting face (§6)
    options:        *void = null;              // the plugin instance / options
                                               // pointer (design revision
                                               // 2026-10-21): a derived
                                               // plugin points it at itself
                                               // in get_juice_plugin; the
                                               // framework applies schema
                                               // rows through this channel
                                               // and hooks receive it via
                                               // their plugin_state slot
    options_schema: [..] Config_Option;        // options schema
                                               // {default, apply, validate}
}

// ---------------------------------------------------------------------------
// get_juice_plugin contract
// ---------------------------------------------------------------------------

// The discovery tail note (ticket 025's lexical anchor): a plugin module
// annotates its get_juice_plugin declaration with this exact note text; the
// plugin scan recognizes it (the juice is_test_anchor technique).
JUICE_PLUGIN_NOTE :: "@juice_plugin";

// The framework's upcast: derived plugin struct pointer -> *Juice_Plugin.
// The using upcast needs an explicit cast (spike-pinned); a non-using
// struct fails to compile at this cast — the type gate. The derived pointer
// itself is what configuration code assigns typed options on; the framework
// consumes the base face through this.
as_plugin :: (p: *$T) -> *Juice_Plugin {
    return cast(*Juice_Plugin) p;
}

// ---------------------------------------------------------------------------
// Built-in registry (static by design)
// ---------------------------------------------------------------------------

// The two built-in transpile plugins wrapped as Juice_Plugin values, in
// declaration order (#load first, then test-block — the default pipeline
// order). An explicit list, not auto-discovery: the built-ins ship with the
// tool and belong to the explicit bootstrap #load set, so discovery buys
// nothing for them (spec §5.2, research A§4.1). The registry is the
// built-in face of the registration surface merge_plugins consumes; an
// empty registry resolves here.
builtin_plugins :: () -> [..] *Juice_Plugin {
    plugins: [..] *Juice_Plugin;
    array_add(*plugins, builtin_load_plugin());
    array_add(*plugins, builtin_test_block_plugin());
    return plugins;
}

// The built-in #load plugin (ticket 022) as a Juice_Plugin. The id is the
// manifest declaration id (single source — module.jai), so the registry and
// the package.jai pipeline declarations speak the same identity.
builtin_load_plugin :: () -> *Juice_Plugin {
    plugin := New(Juice_Plugin);
    plugin.id = TRANSPILE_PLUGIN_LOAD_ID;
    plugin.version = "1.0.0";
    plugin.transpile = New(Transpile_Plugin);
    plugin.transpile.* = load_plugin();
    // The framework channel points at the plugin instance (the same contract
    // every derived plugin follows); the built-in carries no schema today.
    plugin.options = cast(*void) plugin;
    return plugin;
}

// The built-in test-block plugin (ticket 023) as a Juice_Plugin.
builtin_test_block_plugin :: () -> *Juice_Plugin {
    plugin := New(Juice_Plugin);
    plugin.id = TRANSPILE_PLUGIN_TEST_BLOCK_ID;
    plugin.version = "1.0.0";
    plugin.transpile = New(Transpile_Plugin);
    plugin.transpile.* = test_block_plugin();
    plugin.options = cast(*void) plugin;
    return plugin;
}

// ---------------------------------------------------------------------------
// Merge and dup-check
// ---------------------------------------------------------------------------

// The merged product (the registry the resolver selects from):
// - registry: every merged plugin value with all its faces, merge order
//   (registration order). This is the resolver's input — merge keeps the
//   faces intact instead of pre-filtering a pipeline (ticket 056);
// - lint_plugins: the lint rule faces in merge order (one value per
//   non-null Juice_Plugin.lint) — the merge-wide view; the host observes
//   the resolver's declaration-filtered list, not this one;
// - diagnostics: registration-time diagnostics (all rejections; line and
//   column stay 0 — the merge sees only plugin values, no source anchor);
// - ok: zero diagnostics. ok=false means the product is unusable and the
//   caller must refuse to continue.
Merged_Plugins :: struct {
    registry:     [..] *Juice_Plugin;
    lint_plugins: [..] Lint_Plugin;
    diagnostics:  [..] Transpile_Diagnostic;
    ok:           bool;
}

// Registration-time diagnostic accumulation (no source anchor — line and
// column 0, the reference merge_diag shape).
merge_diag :: (diags: *[..] Transpile_Diagnostic, message: string) {
    array_add(diags, .{line = 0, column = 0, message = message});
}

// The merge/dup-check entry: plugin pointers -> merged registry. Rules
// (spec §5.2, decided):
// - an empty id is rejected; a duplicate id is a duplicate registration
//   (same version) or a version conflict (different versions);
// - transpile name conflicts: two plugins contributing a transpile face
//   with the same name reject (the name is the pipeline identity — the
//   keyword-claim conflict's otter equivalent);
// - lint name conflicts: an empty lint rule name or two plugins
//   contributing lint faces with the same name reject (the name is the
//   rule identity — two observers sharing it would silently double-report);
// - at mounts are exclusive per stage (two at hooks on one stage would
//   race for the stage's implementation); before/after mounts stack freely;
// - all violations accumulate as diagnostics and ok=false; the caller must
//   refuse to continue. The merged product is filled regardless (the
//   reference shape).
// An empty registry merges the built-in registry — the default-pipeline
// convention in one place (consistent with resolve_pipeline).
merge_plugins :: (plugins: [] *Juice_Plugin) -> Merged_Plugins {
    out: Merged_Plugins;
    diags: [..] Transpile_Diagnostic;

    input: [] *Juice_Plugin = plugins;
    if input.count == 0 input = builtin_plugins();

    seen_ids:        [..] string;
    seen_versions:   [..] string;
    seen_tp_names:   [..] string;
    seen_tp_owner:   [..] string;
    seen_lint_names: [..] string;
    seen_lint_owner: [..] string;
    seen_at_stages:  [..] Lifecycle_Stage;
    seen_at_owner:   [..] string;

    for p: input {
        // Identity: the empty id is illegal; duplicate ids are duplicates
        // (same version) or version conflicts.
        if p.id.count == 0 {
            merge_diag(*diags, "plugin id must not be empty");
        } else {
            dup := -1;
            for i: 0..seen_ids.count - 1 {
                if seen_ids[i] == p.id { dup = i; break; }
            }
            if dup >= 0 {
                if seen_versions[dup] == p.version {
                    merge_diag(*diags, tprint("duplicate plugin registration: %", p.id));
                } else {
                    merge_diag(*diags, tprint("plugin version conflict: % (% vs %)", p.id, seen_versions[dup], p.version));
                }
            }
        }
        array_add(*seen_ids, p.id);
        array_add(*seen_versions, p.version);

        // Transpile face: the pipeline claims names. A plugin without a
        // transpile face contributes nothing to the pipeline.
        if p.transpile != null {
            name := p.transpile.name;
            owner := "";
            for i: 0..seen_tp_names.count - 1 {
                if seen_tp_names[i] == name { owner = seen_tp_owner[i]; break; }
            }
            if owner.count > 0 {
                merge_diag(*diags, tprint("transpile plugin name conflict: % (% vs %)", name, owner, p.id));
            } else {
                array_add(*seen_tp_names, name);
                array_add(*seen_tp_owner, p.id);
            }
        }

        // Lint face: the rule names are the merged identity. An empty name
        // is illegal; a duplicate name across plugins conflicts (two rules
        // sharing a name would silently double-report). A plugin without a
        // lint face contributes nothing to the lint list.
        if p.lint != null {
            name := p.lint.name;
            if name.count == 0 {
                merge_diag(*diags, "lint plugin name must not be empty");
            } else {
                owner := "";
                for i: 0..seen_lint_names.count - 1 {
                    if seen_lint_names[i] == name { owner = seen_lint_owner[i]; break; }
                }
                if owner.count > 0 {
                    merge_diag(*diags, tprint("lint plugin name conflict: % (% vs %)", name, owner, p.id));
                } else {
                    array_add(*seen_lint_names, name);
                    array_add(*seen_lint_owner, p.id);
                }
            }
            array_add(*out.lint_plugins, p.lint.*);
        }

        // Hook face: at mounts are exclusive per stage.
        for h: p.hooks {
            if h.position == .at {
                owner := "";
                for i: 0..seen_at_stages.count - 1 {
                    if seen_at_stages[i] == h.stage { owner = seen_at_owner[i]; break; }
                }
                if owner.count > 0 {
                    merge_diag(*diags, tprint("at hook mount conflict on stage %: % and %", stage_name(h.stage), owner, p.id));
                } else {
                    array_add(*seen_at_stages, h.stage);
                    array_add(*seen_at_owner, p.id);
                }
            }
        }

        // The value keeps every face in the registry (the resolver selects).
        array_add(*out.registry, p);
    }

    out.diagnostics = diags;
    out.ok = diags.count == 0;
    return out;
}

// ---------------------------------------------------------------------------
// Declaration-driven resolution (ticket 056)
// ---------------------------------------------------------------------------

// The resolver product — the single landing point for the pipeline, the
// hook table and the options application (spec §5.2 合并 vs 选择):
// - pipeline: the declared transpile faces in declaration order; no
//   declared transpile face at all = the default [load, test-block] pipeline
//   (so an undeclared package keeps today's behavior and a declared lint-only
//   plugin does not disable transpiling);
// - lint_plugins: the declared lint faces in declaration order (the host's
//   observation order — undeclared rules never run);
// - hook_table: the declared hooks in declaration order, slot-aligned
//   (register_hooks skips empty contributions, so registration i is the i-th
//   non-empty declared hook contribution);
// - slot_options: one options pointer per hook_table registration, aligned —
//   the host fills Lifecycle_Context.plugin_state from it (the hook reads its
//   plugin's typed options through its state slot);
// - diagnostics: registration-style diagnostics, line/column 0;
// - ok: zero diagnostics. ok=false means the product is unusable.
Resolved_Plugins :: struct {
    pipeline:     [..] Transpile_Plugin;
    lint_plugins: [..] Lint_Plugin;
    hook_table:   [..] Hook_Registration;
    slot_options: [..] *void;
    diagnostics:  [..] Transpile_Diagnostic;
    ok:           bool;
}

// Resolve the registry against the declared configs (declaration order =
// pipeline order = lint observation order = hook registration order):
// - unknown id (no registry entry), a declared id matching several registry
//   values (one package must provide exactly one plugin — the v1 rule), a
//   repeated declaration id, a version mismatch and any option rejection are
//   diagnostics with ok=false;
// - options: every row goes through the matching schema entry's apply
//   (unknown key = rejection), then every schema entry's validate runs; a
//   duplicate row key is rejected up front;
// - only declared plugins contribute faces. An empty config list resolves to
//   the default pipeline with no hooks and no lint;
// - the product is still filled when diagnostics exist (the reference
//   shape — only ok=false blocks the caller); an ambiguous or
//   version-mismatched plugin contributes no faces.
resolve_plugin_configs :: (registry: [] *Juice_Plugin, configs: [] Plugin_Config) -> Resolved_Plugins {
    out: Resolved_Plugins;
    diags: [..] Transpile_Diagnostic;
    declared_transpile := false;

    seen_config_ids: [..] string;
    for config: configs {
        // One declaration per id: a repeated id would silently register the
        // same package twice (the v1 one-package-one-plugin rule's
        // declaration face).
        duplicate_declaration := false;
        for id: seen_config_ids {
            if id == config.id duplicate_declaration = true;
        }
        array_add(*seen_config_ids, config.id);
        if duplicate_declaration {
            merge_diag(*diags, tprint("duplicate plugin declaration: %", config.id));
            continue;
        }

        // Locate the registry value. Zero matches = unknown id; several
        // matches = one package providing multiple plugins (merge rejects
        // duplicate registrations already; this is the resolver's defensive
        // face for a raw registry).
        matches := 0;
        plugin: *Juice_Plugin = null;
        for p: registry {
            if p.id != config.id continue;
            matches += 1;
            if plugin == null plugin = p;
        }
        if matches == 0 {
            merge_diag(*diags, tprint("unknown plugin id: %", config.id));
            continue;
        }
        if matches > 1 {
            merge_diag(*diags, tprint("plugin package provides multiple plugins: %", config.id));
            continue;
        }
        if config.version != plugin.version {
            merge_diag(*diags, tprint("plugin version mismatch: % (declared %, plugin %)", config.id, config.version, plugin.version));
            continue;
        }

        // Options: rows first (schema lookup by name; the plugin's apply owns
        // the key set and reports unknown keys), then every schema entry's
        // validate over the assembled typed options.
        seen_option_keys: [..] string;
        for row: config.options {
            row_duplicate := false;
            for key: seen_option_keys {
                if key == row.key row_duplicate = true;
            }
            if row_duplicate {
                merge_diag(*diags, tprint("duplicate plugin option key: % (%)", config.id, row.key));
                continue;
            }
            array_add(*seen_option_keys, row.key);

            schema_found := false;
            for option: plugin.options_schema {
                if option.name != row.key continue;
                schema_found = true;
                message := "";
                if option.apply != null message = option.apply(plugin.options, row.key, row.value);
                if message != "" merge_diag(*diags, tprint("invalid plugin option: % (%)", config.id, message));
                break;
            }
            if !schema_found merge_diag(*diags, tprint("unknown plugin option: % (%)", config.id, row.key));
        }
        for option: plugin.options_schema {
            if option.validate == null continue;
            message := option.validate(plugin.options);
            if message != "" merge_diag(*diags, tprint("invalid plugin options: % (%)", config.id, message));
        }

        // The declared faces join the products in declaration order.
        if plugin.transpile != null {
            array_add(*out.pipeline, plugin.transpile.*);
            declared_transpile = true;
        }
        if plugin.lint != null {
            array_add(*out.lint_plugins, plugin.lint.*);
        }
        if plugin.hooks.count > 0 {
            register_hooks(*out.hook_table, plugin.hooks);
            array_add(*out.slot_options, plugin.options);
        }
    }

    // No declared transpile face at all: the default pipeline. This keeps an
    // undeclared package on today's behavior (and lets a declaration that
    // only activates a lint plugin keep transpiling).
    if !declared_transpile {
        array_add(*out.pipeline, load_plugin());
        array_add(*out.pipeline, test_block_plugin());
    }

    out.diagnostics = diags;
    out.ok = diags.count == 0;
    return out;
}
