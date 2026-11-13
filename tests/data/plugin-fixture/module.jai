// Fixture plugin package entry (ticket 025 E2E): convention 1 — the root
// module.jai, whose #import name is the package directory name
// ("plugin-fixture"). This plugin contributes a transpile face (a claiming
// plugin rewriting the IDENT "fixture_mark" into "FIXTURE_SEEN") and one
// before-TRANSPILE lifecycle hook recording an INFO diagnostic.
//
// The fixture imports the plugin face by name (#import "juice_core") — the
// published library face (target/modules, landed by ensure_published_modules).
// The registration file's #import and this module must share that ONE
// name-imported module (a #load duplicate in two scopes would create
// incompatible duplicate types — spike-pinned). This file is compiled only
// by the E2E driver child through the registration file; it lives under
// tests/data/, which test discovery exempts from the root package's test
// program.
#import "Basic";
#import "juice_core";

Fixture_Options :: struct {
    label: string = "default";
}

Fixture_Plugin :: struct {
    using base: Juice_Plugin;
    config: Fixture_Options;
}

// The hook: records through the context's diagnostic sink (the explicit ctx
// channel — the state slot stays unused so no fixture type crosses the
// module boundary).
fixture_before_transpile :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    array_add(ctx.diagnostics, .{level = .INFO, message = "fixture-before-transpile"});
    return true;
}

// The transpile face: claims IDENT tokens named "fixture_mark" and rewrites
// them (a one-line token-bounded edit — the line-fidelity contract).
fixture_transpile :: (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool {
    tok := scan.tokens[scan.index];
    if tok.kind != .IDENT || token_text(scan.source, tok) != "fixture_mark" return false;
    array_add(scan.edits, .{start = tok.start, end = tok.end, text = "FIXTURE_SEEN"});
    scan.prev_text = "FIXTURE_SEEN";
    scan.have_prev = true;
    scan.index += 1;
    return true;
}

get_juice_plugin :: () -> *Fixture_Plugin {
    plugin := New(Fixture_Plugin);
    plugin.id = "plugin-fixture";
    plugin.version = "1.0.0";
    plugin.options = cast(*void) plugin;
    plugin.transpile = New(Transpile_Plugin);
    plugin.transpile.name = "fixture-mark";
    plugin.transpile.version = "1.0.0";
    plugin.transpile.modes = .{strip = true, expand = true};
    plugin.transpile.has_anchor = null;
    plugin.transpile.load_edges = null;
    plugin.transpile.transpile = fixture_transpile;
    array_add(*plugin.hooks, .{stage = .TRANSPILE, position = .before, hook = fixture_before_transpile});
    return plugin;
} @juice_plugin
