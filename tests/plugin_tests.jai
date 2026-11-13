// ---------------------------------------------------------------------------
// Plugin surface tests (ticket 024): the Juice_Plugin struct, the
// get_juice_plugin acquisition contract (derived struct + using inheritance
// + typed options members + the as_plugin upcast), the Config_Option shape,
// the static built-in registry and the merge/dup-check surface — proven
// with synthetic plugin values mixed with the two real built-ins. Pinned
// behavior: the registry's declaration order, the empty-registry default
// (the built-ins, consistent with resolve_pipeline), the rejection matrix
// (duplicate id / version conflict / empty id / at-mount conflict /
// transpile name conflict — all diagnostics, ok=false), the legal set
// (before/after stacking, face-less plugins, declaration order feeding the
// pipeline and the hook table) and the direct feed of the merged product
// into the executor (transpile_source / run_mounted_hooks, no second
// conversion). Ticket 041 adds the lint face: the finding shape (1-based
// line/column, default WARNING level), the callable observer carried
// through the merge product, registration-order collection into
// lint_plugins, empty-name and cross-plugin duplicate-name rejection, and
// lint-less plugins contributing nothing. Ticket 056 extends the matrix:
// Juice_Plugin.options, the Config_Option.apply channel, merge returning the
// registry (not a pre-filtered pipeline) and the declaration-driven resolver
// resolve_plugin_configs — face defaults, declaration order, undeclared
// plugins never running, unknown id / version mismatch / one-package-multi-
// plugin / duplicate declaration / option apply+validate+duplicate-key
// rejections, and the hook-table slot alignment.
//
// Key constraint (same as the other sibling test files): src modules are
// bootstrap #load targets / entry closure members — test blocks would be
// illegal inside them, so this module stays test-free and its tests live
// here (tests/), per the test organization rule: referenced by no #load,
// collected into the test program by Test discovery's full-package scan.
// This file contains only test blocks and their helper declarations; zero
// production code coupling. Good-test standard: only external behavior is
// pinned (given plugin value set -> merged product / diagnostics / rejected
// continuation); the merge internals are never asserted.
// ---------------------------------------------------------------------------

#import "Basic";
#import "Compiler";
#import "Testing";
#import "String";

// ===========================================================================
// The synthetic plugins
// ===========================================================================

// The fake derived plugin: base inheritance + a typed options member — the
// get_juice_plugin contract shape (configuration code assigns the typed
// member directly; the framework consumes the base through as_plugin). The
// typed member cannot be named `options` (Juice_Plugin.options is the *void
// framework channel and Jai rejects the redeclaration — spike-pinned), so
// the fixtures use `config`.
Plug_Fake_Options :: struct {
    label:       string = "";
    trace:       *[..] string = null;
    trace_label: string = "";
}

Plug_Fake_Plugin :: struct {
    using base: Juice_Plugin;
    config: Plug_Fake_Options;
}

// A fake transpile face claiming nothing (a never-claiming hook keeps it
// safe under dispatch). Heap storage: the Juice_Plugin.transpile pointer
// must reference stable storage.
plug_noop_transpile :: (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool {
    return false;
}

plug_tp :: (name: string) -> *Transpile_Plugin {
    tp := New(Transpile_Plugin);
    tp.name = name;
    tp.version = "9.9.9";
    tp.modes = .{strip = true, expand = true};
    tp.has_anchor = null;
    tp.load_edges = null;
    tp.transpile = plug_noop_transpile;
    return tp;
}

// A fake plugin with an id, a version and (when tp_name is non-empty) a
// transpile face. Callers upcast with as_plugin for the merge entry. The
// options channel points at the instance (the get_juice_plugin contract).
plug_fake :: (id: string, version: string, tp_name: string) -> *Plug_Fake_Plugin {
    plugin := New(Plug_Fake_Plugin);
    plugin.id = id;
    plugin.version = version;
    plugin.options = cast(*void) plugin;
    if tp_name.count > 0 plugin.transpile = plug_tp(tp_name);
    return plugin;
}

// The recording hook (the lifecycle_tests rec_hook family): it records its
// configured label into the shared trace — the state slot the real dispatch
// hands over is the plugin's options pointer (the resolver's slot_options /
// the framework contract), so the hook casts it back to the derived plugin
// and reads the typed config.
plug_rec_hook :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    p := cast(*Plug_Fake_Plugin) state;
    if p != null && p.config.trace != null array_add(p.config.trace, p.config.trace_label);
    return true;
}

plug_hook :: (stage: Lifecycle_Stage, position: Hook_Position) -> Lifecycle_Hook {
    return .{stage = stage, position = position, hook = plug_rec_hook};
}

// The fake options row applier (the Config_Option.apply shape): the options
// pointer is the plugin itself; the plugin owns the key set, so an unknown
// key returns a non-empty error message.
plug_apply_label :: (options: *void, key: string, value: string) -> string {
    p := cast(*Plug_Fake_Plugin) options;
    if key == "label" {
        p.config.label = value;
        return "";
    }
    return tprint("unknown option '%'", key);
}

// The fake options validator (the Config_Option.validate shape): the
// options pointer is the plugin itself, read via a using downcast back to
// the derived struct.
plug_validate_label :: (options: *void) -> string {
    p := cast(*Plug_Fake_Plugin) options;
    for c: p.config.label {
        if c == #char " " return "label must not contain spaces";
    }
    return "";
}

// Module-held default value for the fake schema (Config_Option.default is a
// pointer the framework may read for reporting — never a stack temporary).
PLUG_FAKE_DEFAULT_LABEL: string = "";

// Attach the fake label schema (apply + validate) to a fake plugin — the
// schema is assembled inside a procedure body (top-level call-bearing
// initializers are illegal in Jai).
plug_with_label_schema :: (plugin: *Plug_Fake_Plugin) -> *Plug_Fake_Plugin {
    array_add(*plugin.options_schema, config_option("label", *PLUG_FAKE_DEFAULT_LABEL, plug_apply_label, plug_validate_label));
    return plugin;
}

// The fake lint observer: one finding with the default level. The
// header/subexpression arguments are the collection-time inputs (null/empty
// in these tests — the callable face shape is what they pin).
plug_lint_inspect :: (header: *Code_Procedure_Header, subexpressions: [] *Code_Node) -> [..] Lint_Finding {
    findings: [..] Lint_Finding;
    array_add(*findings, .{line = 3, column = 7, message = "lint observed"});
    return findings;
}

// A fake plugin carrying a lint face (heap storage: Juice_Plugin.lint must
// reference stable storage). The rule name/version are the merge identities.
plug_lint_plugin :: (id: string, lint_name: string, lint_version: string) -> *Plug_Fake_Plugin {
    plugin := plug_fake(id, "1.0.0", "");
    lint := New(Lint_Plugin);
    lint.name = lint_name;
    lint.version = lint_version;
    lint.inspect_test_header = plug_lint_inspect;
    plugin.lint = lint;
    return plugin;
}

// ===========================================================================
// Unit tests over the plugin surface and the merge
// ===========================================================================

test "Plugin: the derived struct's typed options are compile-time checked at the call site" {
    plugin := New(Plug_Fake_Plugin);
    plugin.id = "typed-demo";
    plugin.version = "1.2.3";
    // The typed member assignment is the compile-time check: a wrong field
    // name or type on this line fails the build.
    plugin.config.label = "typed";
    plugin.options = cast(*void) plugin;
    base := as_plugin(plugin);
    expect(base.id == "typed-demo");
    expect(base.version == "1.2.3");
    expect(plugin.config.label == "typed");
    // The framework channel points at the plugin instance (the contract
    // Config_Option.apply / validate and the hook state slots rely on).
    expect(base.options != null && cast(*Plug_Fake_Plugin) base.options == plugin);
}

test "Plugin: config_option wraps a typed default, the apply row and the validate hook" {
    option := config_option("label", *PLUG_FAKE_DEFAULT_LABEL, plug_apply_label, plug_validate_label);
    expect(option.name == "label");
    expect((cast(*string) option.default).* == "");

    // The apply callback writes the string row into the assembled typed
    // options through the *void channel; an unknown key is its error.
    plugin := New(Plug_Fake_Plugin);
    plugin.options = cast(*void) plugin;
    expect(plugin.options_schema.count == 0);
    expect(option.apply(plugin.options, "label", "clean") == "");
    expect(plugin.config.label == "clean");
    expect(option.apply(plugin.options, "mystery", "x") == "unknown option 'mystery'");

    // The validate callback reads the assembled typed options: "" = pass,
    // non-empty = rejection message.
    plugin.config.label = "clean";
    expect(plug_validate_label(cast(*void) plugin) == "");
    plugin.config.label = "bad label";
    expect(plug_validate_label(cast(*void) plugin) == "label must not contain spaces");
}

test "Plugin: the built-in registry wraps the two built-ins in declaration order" {
    registry := builtin_plugins();
    expect(registry.count == 2);
    expect(registry[0].id == "load" && registry[1].id == "test-block");
    expect(registry[0].version == "1.0.0" && registry[1].version == "1.0.0");
    expect(registry[0].transpile != null && registry[1].transpile != null);
    expect(registry[0].transpile.name == "load" && registry[1].transpile.name == "test-block");
    // The wrapped faces are the real built-ins: the #load plugin contributes
    // edges and no anchor; the test-block plugin anchors and contributes no
    // edges.
    expect(registry[0].transpile.load_edges != null);
    expect(registry[0].transpile.has_anchor == null);
    expect(registry[1].transpile.has_anchor != null);
    expect(registry[1].transpile.load_edges == null);
    // The built-ins carry no hooks and no options schema.
    expect(registry[0].hooks.count == 0 && registry[1].hooks.count == 0);
    expect(registry[0].options_schema.count == 0 && registry[1].options_schema.count == 0);
}

test "Merge: an empty registry merges the built-ins and resolves to the default pipeline" {
    empty: [..] *Juice_Plugin;
    merged := merge_plugins(empty);
    expect(merged.ok);
    expect(merged.diagnostics.count == 0);
    expect(merged.registry.count == 2);
    expect(merged.registry[0].id == "load" && merged.registry[1].id == "test-block");

    // The resolver is the pipeline landing point: an empty declaration list
    // resolves to the default [load, test-block] pipeline.
    resolved := resolve_plugin_configs(merged.registry, Plugin_Config.[]);
    expect(resolved.ok);
    expect(resolved.diagnostics.count == 0);
    expect(resolved.pipeline.count == 2);
    expect(resolved.pipeline[0].name == "load" && resolved.pipeline[1].name == "test-block");
    expect(resolved.hook_table.count == 0);
    expect(resolved.lint_plugins.count == 0);

    // The explicit built-in registry merges to the same registry — empty ==
    // built-ins, one convention (consistent with resolve_pipeline).
    builtin_merged := merge_plugins(builtin_plugins());
    expect(builtin_merged.ok);
    expect(builtin_merged.registry.count == 2);
    expect(builtin_merged.registry[0].id == "load" && builtin_merged.registry[1].id == "test-block");
}

test "Merge/Resolve: declaration order feeds the pipeline and the hook table" {
    a := plug_fake("a", "1.0.0", "face-a");
    b := plug_fake("b", "2.0.0", "face-b");
    array_add(*a.hooks, plug_hook(.TRANSPILE, .before));
    array_add(*b.hooks, plug_hook(.COMPILE, .after));

    plugins: [..] *Juice_Plugin;
    array_add(*plugins, as_plugin(a));
    array_add(*plugins, as_plugin(b));
    merged := merge_plugins(plugins);
    expect(merged.ok);
    expect(merged.diagnostics.count == 0);
    // Merge keeps the merge order; selection is the resolver's job.
    expect(merged.registry.count == 2);
    expect(merged.registry[0].id == "a" && merged.registry[1].id == "b");

    // The declared order b, a reaches the pipeline reversed and the hook
    // table in declaration order (registration order = execution order).
    resolved := resolve_plugin_configs(merged.registry, Plugin_Config.[
        .{id = "b", version = "2.0.0"},
        .{id = "a", version = "1.0.0"},
    ]);
    expect(resolved.ok);
    expect(resolved.pipeline.count == 2);
    expect(resolved.pipeline[0].name == "face-b" && resolved.pipeline[1].name == "face-a");
    expect(resolved.hook_table.count == 2);
    expect(resolved.hook_table[0].hooks.count == 1);
    expect(resolved.hook_table[0].hooks[0].stage == .COMPILE && resolved.hook_table[0].hooks[0].position == .after);
    expect(resolved.hook_table[1].hooks[0].stage == .TRANSPILE && resolved.hook_table[1].hooks[0].position == .before);
    // Slot alignment: one options pointer per registration, pointing at the
    // declared plugin instance.
    expect(resolved.slot_options.count == 2);
    expect(resolved.slot_options[0] == cast(*void) b && resolved.slot_options[1] == cast(*void) a);
}

test "Merge: a duplicate id with the same version rejects" {
    a := plug_fake("dup", "1.0.0", "face-a");
    b := plug_fake("dup", "1.0.0", "face-b");
    merged := merge_plugins(.[as_plugin(a), as_plugin(b)]);
    expect(!merged.ok);
    expect(merged.diagnostics.count == 1);
    expect(merged.diagnostics[0].message == "duplicate plugin registration: dup");
    // Registration-time diagnostics carry no source anchor.
    expect(merged.diagnostics[0].line == 0 && merged.diagnostics[0].column == 0);
}

test "Merge: a duplicate id with a different version rejects as a version conflict" {
    a := plug_fake("dup", "1.0.0", "face-a");
    b := plug_fake("dup", "2.0.0", "face-b");
    merged := merge_plugins(.[as_plugin(a), as_plugin(b)]);
    expect(!merged.ok);
    expect(merged.diagnostics.count == 1);
    expect(merged.diagnostics[0].message == "plugin version conflict: dup (1.0.0 vs 2.0.0)");
}

test "Merge: an empty plugin id rejects" {
    merged := merge_plugins(.[as_plugin(plug_fake("", "1.0.0", ""))]);
    expect(!merged.ok);
    expect(merged.diagnostics.count == 1);
    expect(merged.diagnostics[0].message == "plugin id must not be empty");
}

test "Merge: at mounts are exclusive per stage" {
    a := plug_fake("a", "1.0.0", "");
    b := plug_fake("b", "1.0.0", "");
    array_add(*a.hooks, plug_hook(.TRANSPILE, .at));
    array_add(*b.hooks, plug_hook(.TRANSPILE, .at));
    merged := merge_plugins(.[as_plugin(a), as_plugin(b)]);
    expect(!merged.ok);
    expect(merged.diagnostics.count == 1);
    expect(merged.diagnostics[0].message == "at hook mount conflict on stage TRANSPILE: a and b");
}

test "Merge: one plugin stacking two at hooks on one stage conflicts too" {
    a := plug_fake("a", "1.0.0", "");
    array_add(*a.hooks, plug_hook(.COMPILE, .at));
    array_add(*a.hooks, plug_hook(.COMPILE, .at));
    merged := merge_plugins(.[as_plugin(a)]);
    expect(!merged.ok);
    expect(merged.diagnostics.count == 1);
    expect(merged.diagnostics[0].message == "at hook mount conflict on stage COMPILE: a and a");
}

test "Merge: before/after hooks stack freely on one mount" {
    a := plug_fake("a", "1.0.0", "");
    b := plug_fake("b", "1.0.0", "");
    array_add(*a.hooks, plug_hook(.TRANSPILE, .before));
    array_add(*b.hooks, plug_hook(.TRANSPILE, .before));
    merged := merge_plugins(.[as_plugin(a), as_plugin(b)]);
    expect(merged.ok);
    expect(merged.diagnostics.count == 0);
    // Both contributions register on one mount, declaration order preserved
    // (the resolver is the hook-table landing point).
    resolved := resolve_plugin_configs(merged.registry, Plugin_Config.[
        plug_config("a", "1.0.0"),
        plug_config("b", "1.0.0"),
    ]);
    expect(resolved.ok);
    expect(resolved.hook_table.count == 2);
    expect(resolved.slot_options.count == 2);
}

test "Merge: transpile name conflicts reject" {
    a := plug_fake("a", "1.0.0", "same-face");
    b := plug_fake("b", "1.0.0", "same-face");
    merged := merge_plugins(.[as_plugin(a), as_plugin(b)]);
    expect(!merged.ok);
    expect(merged.diagnostics.count == 1);
    expect(merged.diagnostics[0].message == "transpile plugin name conflict: same-face (a vs b)");
}

test "Merge: a transpile name colliding with a built-in rejects" {
    custom := plug_fake("custom", "1.0.0", "load");
    plugins: [..] *Juice_Plugin;
    for p: builtin_plugins() array_add(*plugins, p);
    array_add(*plugins, as_plugin(custom));
    merged := merge_plugins(plugins);
    expect(!merged.ok);
    expect(merged.diagnostics.count == 1);
    expect(merged.diagnostics[0].message == "transpile plugin name conflict: load (load vs custom)");
}

test "Merge: a plugin contributing no faces is legal" {
    merged := merge_plugins(.[as_plugin(plug_fake("observer-only", "1.0.0", ""))]);
    expect(merged.ok);
    expect(merged.diagnostics.count == 0);
    expect(merged.registry.count == 1);
    // Declared but face-less: contributes nothing to any product channel; no
    // declared transpile face means the default pipeline.
    resolved := resolve_plugin_configs(merged.registry, Plugin_Config.[.{id = "observer-only", version = "1.0.0"}]);
    expect(resolved.ok);
    expect(resolved.pipeline.count == 2);
    expect(resolved.pipeline[0].name == "load" && resolved.pipeline[1].name == "test-block");
    expect(resolved.hook_table.count == 0);
    expect(resolved.lint_plugins.count == 0);
}

test "Merge: multiple violations accumulate" {
    bad := plug_fake("bad", "1.0.0", "face-x");    // name conflict with other
    other := plug_fake("other", "1.0.0", "face-x"); // name conflict
    array_add(*other.hooks, plug_hook(.TRANSPILE, .at));
    third := plug_fake("third", "1.0.0", "face-y");
    array_add(*third.hooks, plug_hook(.TRANSPILE, .at));  // at conflict with other
    merged := merge_plugins(.[as_plugin(bad), as_plugin(other), as_plugin(third)]);
    expect(!merged.ok);
    expect(merged.diagnostics.count == 2);
    // Accumulation order = plugin order, per-plugin check order (id, transpile, at).
    expect(merged.diagnostics[0].message == "transpile plugin name conflict: face-x (bad vs other)");
    expect(merged.diagnostics[1].message == "at hook mount conflict on stage TRANSPILE: other and third");
}

test "Merge/Resolve: the resolved product feeds the executor directly" {
    // Transpile side: the resolved default pipeline runs the real #load
    // plugin (EXPAND placeholder) — resolved.pipeline goes into
    // Transpile_Context.plugins with no second conversion.
    merged := merge_plugins(builtin_plugins());
    resolved := resolve_plugin_configs(merged.registry, Plugin_Config.[]);
    expect(resolved.ok);
    ctx: Transpile_Context;
    ctx.mode = .EXPAND;
    ctx.path = "src/a.jai";
    ctx.next_test_number = 1;
    ctx.plugins = resolved.pipeline;
    result := transpile_source("#load \"helper.jai\";\n", ctx);
    expect(result.diagnostics.count == 0);
    expect(result.view == "// juice: load stripped: #load \"helper.jai\";\n");

    // Hook side: the resolved hook table fires the recording hook through
    // the slot protocol — resolved.hook_table goes into run_mounted_hooks
    // as-is, and resolved.slot_options fills the host's plugin_state with
    // the plugin options pointers.
    trace: [..] string;
    hooked := plug_fake("hooked", "1.0.0", "");
    hooked.config.trace = *trace;
    hooked.config.trace_label = "fired";
    array_add(*hooked.hooks, plug_hook(.TRANSPILE, .before));
    // The recording hook reads its slot through plugin_state; the resolver's
    // slot_options is the aligned host input.
    hooked_resolved := resolve_plugin_configs(.[as_plugin(hooked)], Plugin_Config.[.{id = "hooked", version = "1.0.0"}]);
    expect(hooked_resolved.ok);
    expect(hooked_resolved.hook_table.count == 1);
    diags: [..] Lifecycle_Diagnostic;
    lctx: Lifecycle_Context;
    lctx.stage = .TRANSPILE;
    lctx.diagnostics = *diags;
    for slot: hooked_resolved.slot_options array_add(*lctx.plugin_state, slot);
    expect(run_mounted_hooks(hooked_resolved.hook_table, .TRANSPILE, .before, *lctx));
    expect(trace.count == 1 && trace[0] == "fired");
}

test "Resolver: the built-in registry drives the real default pipeline end to end" {
    merged := merge_plugins(builtin_plugins());
    resolved := resolve_plugin_configs(merged.registry, Plugin_Config.[]);
    ctx: Transpile_Context;
    ctx.mode = .EXPAND;
    ctx.path = "src/a.jai";
    ctx.next_test_number = 1;
    ctx.plugins = resolved.pipeline;
    result := transpile_source("test \"hello\" { }\n", ctx);
    expect(result.diagnostics.count == 0);
    expect(result.tests.count == 1);
    expect(result.tests[0].name == "hello" && result.tests[0].number == 1 && result.tests[0].line == 1);
    expect(result.view == "juice_test_1 :: () -> () { } @test\n");
}

// ===========================================================================
// Lint face (ticket 041)
// ===========================================================================

test "Plugin: the lint face pins the finding shape and the callable observer" {
    // The face is a nullable member: a plugin without a lint rule has none.
    plain := plug_fake("plain", "1.0.0", "");
    expect(plain.lint == null);

    // The finding: 1-based line/column by contract; the level defaults to
    // WARNING (advisory), the enum's other two levels are expressible.
    finding: Lint_Finding = .{line = 4, column = 9, message = "advisory"};
    expect(finding.line == 4 && finding.column == 9);
    expect(finding.level == .WARNING);
    // Zero-safe default (review fix): the zero value of the level enum is
    // WARNING, so a forgotten or zero-initialized level can never become a
    // build-blocking ERROR.
    expect(cast(Lint_Level) 0 == .WARNING);
    info_finding: Lint_Finding = .{line = 1, column = 1, message = "note", level = .INFO};
    error_finding: Lint_Finding = .{line = 1, column = 1, message = "bad", level = .ERROR};
    expect(info_finding.level == .INFO && error_finding.level == .ERROR);

    // The observer is callable through the face with the collect-time
    // argument shape (a typechecked header + the flattened subexpressions).
    no_subexpressions: [] *Code_Node;
    findings := plug_lint_inspect(null, no_subexpressions);
    expect(findings.count == 1);
    expect(findings[0].message == "lint observed");
    expect(findings[0].level == .WARNING);
}

test "Merge: lint faces are collected in registration order" {
    a := plug_lint_plugin("a", "rule-a", "1.0.0");
    b := plug_fake("b", "1.0.0", "");  // no lint face: contributes nothing
    c := plug_lint_plugin("c", "rule-c", "2.0.0");
    merged := merge_plugins(.[as_plugin(a), as_plugin(b), as_plugin(c)]);
    expect(merged.ok);
    expect(merged.diagnostics.count == 0);
    expect(merged.lint_plugins.count == 2);
    expect(merged.lint_plugins[0].name == "rule-a" && merged.lint_plugins[0].version == "1.0.0");
    expect(merged.lint_plugins[1].name == "rule-c" && merged.lint_plugins[1].version == "2.0.0");
    // The copied face carries the observer: calling it through the merged
    // product runs the rule.
    no_subexpressions: [] *Code_Node;
    findings := merged.lint_plugins[0].inspect_test_header(null, no_subexpressions);
    expect(findings.count == 1 && findings[0].message == "lint observed");
}

test "Merge: a plugin without a lint face contributes no lint rule" {
    merged := merge_plugins(.[as_plugin(plug_fake("no-lint", "1.0.0", ""))]);
    expect(merged.ok);
    expect(merged.diagnostics.count == 0);
    expect(merged.lint_plugins.count == 0);

    // The built-in registry carries no lint faces either.
    builtin_merged := merge_plugins(builtin_plugins());
    expect(builtin_merged.ok);
    expect(builtin_merged.lint_plugins.count == 0);
}

test "Merge: an empty lint rule name rejects" {
    merged := merge_plugins(.[as_plugin(plug_lint_plugin("a", "", "1.0.0"))]);
    expect(!merged.ok);
    expect(merged.diagnostics.count == 1);
    expect(merged.diagnostics[0].message == "lint plugin name must not be empty");
    // Registration-time diagnostics carry no source anchor.
    expect(merged.diagnostics[0].line == 0 && merged.diagnostics[0].column == 0);
    // The merged product is filled regardless (the jaix shape): only
    // ok=false blocks the caller.
    expect(merged.lint_plugins.count == 1);
}

test "Merge: duplicate lint rule names conflict across plugins" {
    a := plug_lint_plugin("a", "same-rule", "1.0.0");
    b := plug_lint_plugin("b", "same-rule", "1.0.0");
    merged := merge_plugins(.[as_plugin(a), as_plugin(b)]);
    expect(!merged.ok);
    expect(merged.diagnostics.count == 1);
    expect(merged.diagnostics[0].message == "lint plugin name conflict: same-rule (a vs b)");
    // Both faces still land in the list in registration order; the product
    // is unusable only through ok=false.
    expect(merged.lint_plugins.count == 2);
    expect(merged.lint_plugins[0].name == "same-rule" && merged.lint_plugins[1].name == "same-rule");
}

// ===========================================================================
// Declaration-driven resolver (ticket 056)
// ===========================================================================

// A config without option rows.
plug_config :: (id: string, version: string) -> Plugin_Config {
    return .{id = id, version = version};
}

// A config with option rows.
plug_config_with_rows :: (id: string, version: string, rows: [] Option_Row) -> Plugin_Config {
    return .{id = id, version = version, options = rows};
}

test "Resolver: face default — no declared transpile face yields [load, test-block]" {
    // An empty declaration list and a lint-only declaration both resolve to
    // the built-in default pipeline (an activated lint plugin must not
    // disable transpiling; undeclared packages keep today's behavior).
    empty := resolve_plugin_configs(builtin_plugins(), Plugin_Config.[]);
    expect(empty.ok);
    expect(empty.pipeline.count == 2);
    expect(empty.pipeline[0].name == "load" && empty.pipeline[1].name == "test-block");

    lint_only := plug_lint_plugin("lint-only", "rule", "1.0.0");
    resolved := resolve_plugin_configs(.[as_plugin(lint_only)], Plugin_Config.[plug_config("lint-only", "1.0.0")]);
    expect(resolved.ok);
    expect(resolved.pipeline.count == 2);
    expect(resolved.pipeline[0].name == "load" && resolved.pipeline[1].name == "test-block");
    expect(resolved.lint_plugins.count == 1 && resolved.lint_plugins[0].name == "rule");
    expect(resolved.hook_table.count == 0);
}

test "Resolver: declaration order drives the pipeline, hooks and lint; undeclared plugins never run" {
    used := plug_lint_plugin("used", "rule-used", "1.0.0");
    used.transpile = plug_tp("face-used");
    array_add(*used.hooks, plug_hook(.TRANSPILE, .before));

    unused := plug_lint_plugin("unused", "rule-unused", "1.0.0");
    unused.transpile = plug_tp("face-unused");
    array_add(*unused.hooks, plug_hook(.COMPILE, .at));

    registry: [..] *Juice_Plugin;
    array_add(*registry, as_plugin(used));
    array_add(*registry, as_plugin(unused));

    resolved := resolve_plugin_configs(registry, Plugin_Config.[plug_config("used", "1.0.0")]);
    expect(resolved.ok);
    // Only the declared plugin's faces exist: its pipeline face, its hooks
    // and its lint rule. The undeclared plugin never contributes.
    expect(resolved.pipeline.count == 1 && resolved.pipeline[0].name == "face-used");
    expect(resolved.hook_table.count == 1 && resolved.hook_table[0].hooks[0].stage == .TRANSPILE);
    expect(resolved.lint_plugins.count == 1 && resolved.lint_plugins[0].name == "rule-used");
    expect(resolved.slot_options.count == 1 && resolved.slot_options[0] == cast(*void) used);
}

test "Resolver: an unknown plugin id rejects" {
    resolved := resolve_plugin_configs(builtin_plugins(), Plugin_Config.[plug_config("mystery", "1")]);
    expect(!resolved.ok);
    expect(resolved.diagnostics.count == 1);
    expect(resolved.diagnostics[0].message == "unknown plugin id: mystery");
    expect(resolved.diagnostics[0].line == 0 && resolved.diagnostics[0].column == 0);
    // No declared transpile face: the unusable product still carries the
    // default pipeline (the caller must stop on ok=false).
    expect(resolved.pipeline.count == 2);
}

test "Resolver: a version mismatch rejects" {
    resolved := resolve_plugin_configs(builtin_plugins(), Plugin_Config.[plug_config("load", "9.9.9")]);
    expect(!resolved.ok);
    expect(resolved.diagnostics.count == 1);
    expect(resolved.diagnostics[0].message == "plugin version mismatch: load (declared 9.9.9, plugin 1.0.0)");
    expect(resolved.pipeline.count == 2);
}

test "Resolver: one package providing several plugins rejects (the v1 rule)" {
    // Two registry values claiming one id (a raw, unmerged registry — merge
    // itself would have rejected the duplicate registration).
    first := plug_fake("dup", "1.0.0", "face-a");
    second := plug_fake("dup", "1.0.0", "face-b");
    resolved := resolve_plugin_configs(.[as_plugin(first), as_plugin(second)], Plugin_Config.[plug_config("dup", "1.0.0")]);
    expect(!resolved.ok);
    expect(resolved.diagnostics.count == 1);
    expect(resolved.diagnostics[0].message == "plugin package provides multiple plugins: dup");
    // The ambiguous plugin contributes no faces.
    expect(resolved.pipeline.count == 2);
}

test "Resolver: a repeated declaration id rejects" {
    plugin := plug_fake("once", "1.0.0", "face-once");
    resolved := resolve_plugin_configs(.[as_plugin(plugin)], Plugin_Config.[
        plug_config("once", "1.0.0"),
        plug_config("once", "1.0.0"),
    ]);
    expect(!resolved.ok);
    expect(resolved.diagnostics.count == 1);
    expect(resolved.diagnostics[0].message == "duplicate plugin declaration: once");
}

test "Resolver: option rows apply through the schema, then validate runs" {
    plugin := plug_with_label_schema(plug_fake("opt", "1.0.0", ""));
    registry: [..] *Juice_Plugin;
    array_add(*registry, as_plugin(plugin));

    // A valid row lands in the typed options field (the apply channel).
    resolved := resolve_plugin_configs(registry, Plugin_Config.[plug_config_with_rows("opt", "1.0.0", Option_Row.[
        .{key = "label", value = "clean"},
    ])]);
    expect(resolved.ok);
    expect(plugin.config.label == "clean");

    // validate runs after all rows: the space rejection surfaces as a
    // diagnostic (the row was still applied).
    resolved = resolve_plugin_configs(registry, Plugin_Config.[plug_config_with_rows("opt", "1.0.0", Option_Row.[
        .{key = "label", value = "bad label"},
    ])]);
    expect(!resolved.ok);
    expect(resolved.diagnostics.count == 1);
    expect(resolved.diagnostics[0].message == "invalid plugin options: opt (label must not contain spaces)");

    // An unknown key never reaches apply: the resolver reports it against
    // the plugin's schema. Reset the typed value first so the validate pass
    // stays clean and the unknown-key report is the only diagnostic.
    plugin.config.label = "clean";
    resolved = resolve_plugin_configs(registry, Plugin_Config.[plug_config_with_rows("opt", "1.0.0", Option_Row.[
        .{key = "mystery", value = "x"},
    ])]);
    expect(!resolved.ok);
    expect(resolved.diagnostics.count == 1);
    expect(resolved.diagnostics[0].message == "unknown plugin option: opt (mystery)");

    // Duplicate keys in one declaration reject up front.
    plugin.config.label = "clean";
    resolved = resolve_plugin_configs(registry, Plugin_Config.[plug_config_with_rows("opt", "1.0.0", Option_Row.[
        .{key = "label", value = "a"},
        .{key = "label", value = "b"},
    ])]);
    expect(!resolved.ok);
    expect(resolved.diagnostics.count == 1);
    expect(resolved.diagnostics[0].message == "duplicate plugin option key: opt (label)");
}

test "Resolver: a plugin without a schema rejects option rows" {
    plugin := plug_fake("bare", "1.0.0", "");
    resolved := resolve_plugin_configs(.[as_plugin(plugin)], Plugin_Config.[plug_config_with_rows("bare", "1.0.0", Option_Row.[
        .{key = "anything", value = "x"},
    ])]);
    expect(!resolved.ok);
    expect(resolved.diagnostics.count == 1);
    expect(resolved.diagnostics[0].message == "unknown plugin option: bare (anything)");
}
