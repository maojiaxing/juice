// Fixture plugin package entry (ticket 029 E2E): the bad-side package.
// This plugin's id collides with extra.jai's (duplicate registration — the
// merge must reject loudly) and its transpile face rewrites the IDENT
// "bad_mark" into a TWO-line text — an edit violating the line-fidelity
// contract (1 line in = 1 line out), which the runner must reject loudly
// at transpile time. Both rejections are the "bad plugin package" faces.
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

Bad_Options :: struct {
    label: string = "default";
}

Bad_Plugin :: struct {
    using base: Juice_Plugin;
    config: Bad_Options;
}

// The transpile face: claims IDENT tokens named "bad_mark" and rewrites
// them into two lines. The runner's line-fidelity gate must drop the edit
// and report a diagnostic — a bad plugin fails loudly instead of silently
// drifting line numbers.
bad_transpile :: (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool {
    tok := scan.tokens[scan.index];
    if tok.kind != .IDENT || token_text(scan.source, tok) != "bad_mark" return false;
    array_add(scan.edits, .{start = tok.start, end = tok.end, text = "BAD\nSEEN"});
    scan.prev_text = "bad_mark";
    scan.have_prev = true;
    scan.index += 1;
    return true;
}

get_juice_plugin :: () -> *Bad_Plugin {
    plugin := New(Bad_Plugin);
    plugin.id = "bad-shared";
    plugin.version = "1.0.0";
    plugin.options = cast(*void) plugin;
    plugin.transpile = New(Transpile_Plugin);
    plugin.transpile.name = "bad-mark";
    plugin.transpile.version = "1.0.0";
    plugin.transpile.modes = .{strip = true, expand = true};
    plugin.transpile.has_anchor = null;
    plugin.transpile.load_edges = null;
    plugin.transpile.transpile = bad_transpile;
    return plugin;
} @juice_plugin
