// ---------------------------------------------------------------------------
// Transpile pipeline framework tests (ticket 020): the plugin interface and
// runner mechanics, proven with synthetic recording plugins — declaration
// order, the claim contract (a claim covers exactly the tokens it consumes;
// unconsumed regions keep dispatching), mode applicability, probe
// aggregation with nullable-skip, cross-file state continuation through the
// plugin_state slots, and the runner's line-fidelity rejection. The built-in
// #load plugin landed with ticket 022 and the test-block plugin with ticket
// 023, so the empty-registry pin here documents the 023 shape: an empty
// registration resolves to the default pipeline (both built-ins, #load
// first).
//
// Key constraint (same as the other sibling test files): src modules are
// bootstrap #load targets / entry closure members — test blocks would be
// illegal inside them, so this module stays test-free and its tests live
// here (tests/), per the test organization rule: referenced by no #load,
// collected into the test program by Test discovery's full-package scan.
// This file contains only test blocks and their helper declarations; zero
// production code coupling. Good-test standard: only external behavior is
// pinned (given source + plugin set -> view text / entries / diagnostics);
// the dispatch trace itself is never asserted.
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";
#import "String";

// ===========================================================================
// The synthetic plugins (recording adapters)
// ===========================================================================
//
// synth: claims a statement-position `synth_anchor ;` — rewrites the anchor
// to `synth_stripped` (a 1-line, token-bounded edit), a test entry joins
// the list numbered from the plugin's state slot (the cross-file numbering
// channel), and the state counter advances. An anchor not followed by `;`
// is a diagnostic (not claimed). STRIP-only: in EXPAND mode the runner
// never dispatches it. Probe hooks: has_anchor sees statement-position
// anchors; load_edges contributes the raw target of `#synth_load "x.jai";`
// statements.

synth_has_anchor :: (source: string, path: string) -> bool {
    s := normalize_view_line_endings(source);
    tokens := lex_source(s);
    have_prev := false;
    prev_text := "";
    for tok: tokens {
        text := token_text(s, tok);
        if tok.kind == .IDENT && text == "synth_anchor" && is_statement_position(have_prev, prev_text) return true;
        prev_text = text;
        have_prev = true;
    }
    return false;
}

synth_load_edges :: (source: string, path: string) -> [..] string {
    s := normalize_view_line_endings(source);
    tokens := lex_source(s);
    edges: [..] string;
    i := 0;
    while i < tokens.count {
        tok := tokens[i];
        if tok.kind == .DIRECTIVE && token_text(s, tok) == "#synth_load" && i + 2 < tokens.count
            && tokens[i+1].kind == .STRING && token_text(s, tokens[i+2]) == ";" {
            target := tokens[i+1];
            // The recording adapter records the literal's raw content (no
            // escape decoding — the fixtures control the input; the real
            // string helpers join with ticket 022).
            array_add(*edges, slice(s, target.start + 1, target.end - target.start - 2));
            i += 3;
            continue;
        }
        i += 1;
    }
    return edges;
}

synth_transpile :: (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool {
    tok := scan.tokens[scan.index];
    if tok.kind != .IDENT || token_text(scan.source, tok) != "synth_anchor" return false;
    if !is_statement_position(scan.have_prev, scan.prev_text) return false;
    if scan.index + 1 >= scan.tokens.count || token_text(scan.source, scan.tokens[scan.index + 1]) != ";" {
        array_add(scan.diagnostics, .{line = tok.line, column = tok.column, message = "synth 锚点缺少 ;"});
        // Not claimed: the statement stays verbatim.
        return false;
    }
    // The cross-file state channel: the plugin's slot in ctx.plugin_state
    // (aligned with the pipeline order) persists across transpile_source
    // calls — the counter continues across files.
    counter := cast(*s64) state;
    counter.* += 1;
    array_add(scan.edits, .{start = tok.start, end = tok.end, text = "synth_stripped"});
    array_add(scan.tests, .{name = tprint("synth:%1:%2", ctx.path, tok.line), number = counter.*, line = tok.line});
    scan.index += 2;
    scan.prev_text = ";";
    scan.have_prev = true;
    return true;
}

synth_plugin :: () -> Transpile_Plugin {
    plugin: Transpile_Plugin;
    plugin.name = "synth";
    plugin.version = "1.0.0";
    plugin.modes = .{strip = true, expand = false};
    plugin.has_anchor = synth_has_anchor;
    plugin.load_edges = synth_load_edges;
    plugin.transpile = synth_transpile;
    return plugin;
}

// A context whose pipeline is the synthetic plugin alone (slot 0 = the
// caller's counter).
synth_ctx :: (mode: Transpile_Mode, path: string, counter: *s64) -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = mode;
    ctx.path = path;
    ctx.next_test_number = 1;
    array_add(*ctx.plugins, synth_plugin());
    array_add(*ctx.plugin_state, counter);
    return ctx;
}

// claim-a / claim-b: both recognize the same `shared ;` statement and
// rewrite the token differently. Whichever plugin the runner dispatches
// first claims it — declaration order decides the output.
claim_a_transpile :: (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool {
    tok := scan.tokens[scan.index];
    if tok.kind != .IDENT || token_text(scan.source, tok) != "shared" return false;
    if scan.index + 1 >= scan.tokens.count || token_text(scan.source, scan.tokens[scan.index + 1]) != ";" return false;
    array_add(scan.edits, .{start = tok.start, end = tok.end, text = "claimed_by_a"});
    scan.index += 2;
    scan.prev_text = ";";
    scan.have_prev = true;
    return true;
}

claim_b_transpile :: (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool {
    tok := scan.tokens[scan.index];
    if tok.kind != .IDENT || token_text(scan.source, tok) != "shared" return false;
    if scan.index + 1 >= scan.tokens.count || token_text(scan.source, scan.tokens[scan.index + 1]) != ";" return false;
    array_add(scan.edits, .{start = tok.start, end = tok.end, text = "claimed_by_b"});
    scan.index += 2;
    scan.prev_text = ";";
    scan.have_prev = true;
    return true;
}

claim_a_plugin :: () -> Transpile_Plugin {
    plugin: Transpile_Plugin;
    plugin.name = "claim-a";
    plugin.version = "1.0.0";
    plugin.modes = .{strip = true, expand = true};
    plugin.has_anchor = null;
    plugin.load_edges = null;
    plugin.transpile = claim_a_transpile;
    return plugin;
}

claim_b_plugin :: () -> Transpile_Plugin {
    plugin: Transpile_Plugin;
    plugin.name = "claim-b";
    plugin.version = "1.0.0";
    plugin.modes = .{strip = true, expand = true};
    plugin.has_anchor = null;
    plugin.load_edges = null;
    plugin.transpile = claim_b_transpile;
    return plugin;
}

// enter: claims a statement-position `enter {` header, rewrites the token
// and enters the body without consuming it (cursor at the brace's
// successor, depth + 1) — the runner keeps dispatching later plugins on the
// unconsumed tokens inside the body.
enter_transpile :: (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool {
    tok := scan.tokens[scan.index];
    if tok.kind != .IDENT || token_text(scan.source, tok) != "enter" return false;
    if !is_statement_position(scan.have_prev, scan.prev_text) return false;
    if scan.index + 1 >= scan.tokens.count || token_text(scan.source, scan.tokens[scan.index + 1]) != "{" return false;
    array_add(scan.edits, .{start = tok.start, end = tok.end, text = "entered"});
    scan.index += 2;
    scan.depth += 1;
    scan.prev_text = "{";
    scan.have_prev = true;
    return true;
}

enter_plugin :: () -> Transpile_Plugin {
    plugin: Transpile_Plugin;
    plugin.name = "enter";
    plugin.version = "1.0.0";
    plugin.modes = .{strip = true, expand = true};
    plugin.has_anchor = null;
    plugin.load_edges = null;
    plugin.transpile = enter_transpile;
    return plugin;
}

// The swallow fake's own matching-close scan (the shared find_matching_close
// joins src/transpile.jai with ticket 023's test-block plugin).
test_find_close :: (s: string, tokens: [] Token, open_index: s64) -> s64, bool {
    depth := 0;
    j := open_index;
    while j < tokens.count {
        text := token_text(s, tokens[j]);
        if tokens[j].kind == .PUNCT && text == "{" {
            depth += 1;
        } else if tokens[j].kind == .PUNCT && text == "}" {
            depth -= 1;
            if depth == 0 return j, true;
        }
        j += 1;
    }
    return 0, false;
}

// swallow: claims a statement-position `swallow { ... }` region through its
// closing brace and replaces the whole single-line block with an equal-line
// comment — tokens inside the consumed region are never dispatched again.
swallow_transpile :: (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool {
    tok := scan.tokens[scan.index];
    if tok.kind != .IDENT || token_text(scan.source, tok) != "swallow" return false;
    if !is_statement_position(scan.have_prev, scan.prev_text) return false;
    if scan.index + 1 >= scan.tokens.count || token_text(scan.source, scan.tokens[scan.index + 1]) != "{" return false;
    close_index, closed := test_find_close(scan.source, scan.tokens, scan.index + 1);
    if !closed return false;
    close := scan.tokens[close_index];
    array_add(scan.edits, .{start = tok.start, end = close.end, text = "// swallowed"});
    scan.index = close_index + 1;
    scan.prev_text = "}";
    scan.have_prev = true;
    return true;
}

swallow_plugin :: () -> Transpile_Plugin {
    plugin: Transpile_Plugin;
    plugin.name = "swallow";
    plugin.version = "1.0.0";
    plugin.modes = .{strip = true, expand = true};
    plugin.has_anchor = null;
    plugin.load_edges = null;
    plugin.transpile = swallow_transpile;
    return plugin;
}

// extra_edges: a probe-only plugin contributing the raw target of
// `#extra_load "x.jai";` statements (a never-claiming transpile hook keeps
// it safe under dispatch).
extra_load_edges :: (source: string, path: string) -> [..] string {
    s := normalize_view_line_endings(source);
    tokens := lex_source(s);
    edges: [..] string;
    i := 0;
    while i < tokens.count {
        tok := tokens[i];
        if tok.kind == .DIRECTIVE && token_text(s, tok) == "#extra_load" && i + 2 < tokens.count
            && tokens[i+1].kind == .STRING && token_text(s, tokens[i+2]) == ";" {
            target := tokens[i+1];
            array_add(*edges, slice(s, target.start + 1, target.end - target.start - 2));
            i += 3;
            continue;
        }
        i += 1;
    }
    return edges;
}

extra_edges_transpile :: (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool {
    return false;
}

extra_edges_plugin :: () -> Transpile_Plugin {
    plugin: Transpile_Plugin;
    plugin.name = "extra-edges";
    plugin.version = "1.0.0";
    plugin.modes = .{strip = true, expand = true};
    plugin.has_anchor = null;
    plugin.load_edges = extra_load_edges;
    plugin.transpile = extra_edges_transpile;
    return plugin;
}

// ===========================================================================
// The violating fixtures: two plugins whose edits break the line-fidelity
// hard constraint — one replaces a 1-line region with 2-line text
// (equal-line expansion fails), the other starts its edit in the middle of
// a token. The runner must drop the edit and report a diagnostic; the view
// keeps the source verbatim.
// ===========================================================================

violate_line_transpile :: (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool {
    tok := scan.tokens[scan.index];
    if tok.kind != .IDENT || token_text(scan.source, tok) != "violate_line" return false;
    if scan.index + 1 >= scan.tokens.count || token_text(scan.source, scan.tokens[scan.index + 1]) != ";" return false;
    array_add(scan.edits, .{start = tok.start, end = tok.end, text = "a\nb"});
    scan.index += 2;
    scan.prev_text = ";";
    scan.have_prev = true;
    return true;
}

violate_line_plugin :: () -> Transpile_Plugin {
    plugin: Transpile_Plugin;
    plugin.name = "violate-line";
    plugin.version = "1.0.0";
    plugin.modes = .{strip = true, expand = true};
    plugin.has_anchor = null;
    plugin.load_edges = null;
    plugin.transpile = violate_line_transpile;
    return plugin;
}

violate_bounds_transpile :: (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool {
    tok := scan.tokens[scan.index];
    if tok.kind != .IDENT || token_text(scan.source, tok) != "violate_bounds" return false;
    if scan.index + 1 >= scan.tokens.count || token_text(scan.source, scan.tokens[scan.index + 1]) != ";" return false;
    // Starts mid-token: 1 line -> 1 line, but not token-bounded.
    array_add(scan.edits, .{start = tok.start + 1, end = tok.end, text = "x"});
    scan.index += 2;
    scan.prev_text = ";";
    scan.have_prev = true;
    return true;
}

violate_bounds_plugin :: () -> Transpile_Plugin {
    plugin: Transpile_Plugin;
    plugin.name = "violate-bounds";
    plugin.version = "1.0.0";
    plugin.modes = .{strip = true, expand = true};
    plugin.has_anchor = null;
    plugin.load_edges = null;
    plugin.transpile = violate_bounds_transpile;
    return plugin;
}

// ---------------------------------------------------------------------------
// Unit tests over the pipeline mechanism
// ---------------------------------------------------------------------------

test "Pipeline: an empty registry means the default pipeline (023 shape)" {
    // The single resolution point: an empty registry resolves to the default
    // pipeline (the #load plugin and the test-block plugin, in declaration
    // order), a non-empty registry passes through.
    resolved := resolve_pipeline(Transpile_Plugin.[]);
    expect(resolved.count == 2 && resolved[0].name == "load" && resolved[1].name == "test-block");
    pipeline: [..] Transpile_Plugin;
    array_add(*pipeline, synth_plugin());
    resolved = resolve_pipeline(pipeline);
    expect(resolved.count == 1 && resolved[0].name == "synth");

    // With no registered plugins the runner runs the default pipeline: the
    // synth anchor passes through (the synth plugin is not registered), the
    // test block is stripped by the built-in test-block plugin in STRIP mode
    // and nothing is diagnosed.
    result := transpile_source("synth_anchor;\ntest \"a\" { }\n", .{mode = .STRIP, path = "src/a.jai"});
    expect(result.diagnostics.count == 0);
    expect(result.tests.count == 0);
    expect(result.view == "synth_anchor;\n// juice: test stripped: test \"a\" { }\n");
}

test "Pipeline: declaration order decides which plugin claims a shared token" {
    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = "src/a.jai";
    a_first: [..] Transpile_Plugin;
    array_add(*a_first, claim_a_plugin());
    array_add(*a_first, claim_b_plugin());
    ctx.plugins = a_first;
    result := transpile_source("shared;\n", ctx);
    expect(result.diagnostics.count == 0);
    expect(result.view == "claimed_by_a;\n");

    b_first: [..] Transpile_Plugin;
    array_add(*b_first, claim_b_plugin());
    array_add(*b_first, claim_a_plugin());
    ctx.plugins = b_first;
    result = transpile_source("shared;\n", ctx);
    expect(result.view == "claimed_by_b;\n");
}

test "Pipeline: an unclaimed position keeps dispatching to later plugins" {
    // Each plugin claims only its own token shape; the runner re-dispatches
    // every unconsumed position from the pipeline head, so the two claims
    // combine regardless of declaration order.
    counter: s64 = 0;
    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = "src/a.jai";
    array_add(*ctx.plugins, claim_a_plugin());
    array_add(*ctx.plugins, synth_plugin());
    array_add(*ctx.plugin_state, null);
    array_add(*ctx.plugin_state, *counter);
    result := transpile_source("shared;\nsynth_anchor;\n", ctx);
    expect(result.diagnostics.count == 0);
    expect(result.tests.count == 1);
    expect(result.view == "claimed_by_a;\nsynth_stripped;\n");
    expect(counter == 1);
}

test "Pipeline: a header claim enters the body without consuming it" {
    counter: s64 = 0;
    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = "src/a.jai";
    array_add(*ctx.plugins, enter_plugin());
    array_add(*ctx.plugins, synth_plugin());
    array_add(*ctx.plugin_state, null);
    array_add(*ctx.plugin_state, *counter);
    result := transpile_source("enter {\n    synth_anchor;\n}\n", ctx);
    // The enter plugin claimed only the header; the synth anchor inside the
    // body was still dispatched to later plugins.
    expect(result.diagnostics.count == 0);
    expect(result.tests.count == 1);
    expect(result.view == "entered {\n    synth_stripped;\n}\n");
    expect(counter == 1);
}

test "Pipeline: a block claim consumes the whole region" {
    counter: s64 = 0;
    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = "src/a.jai";
    array_add(*ctx.plugins, swallow_plugin());
    array_add(*ctx.plugins, synth_plugin());
    array_add(*ctx.plugin_state, null);
    array_add(*ctx.plugin_state, *counter);
    result := transpile_source("swallow { synth_anchor; }\n", ctx);
    // The swallow plugin consumed the block through its closing brace: the
    // synth anchor inside the placeholder is never dispatched.
    expect(result.diagnostics.count == 0);
    expect(result.tests.count == 0);
    expect(result.view == "// swallowed\n");
    expect(counter == 0);
}

test "Pipeline: mode applicability gates the dispatch" {
    source := "synth_anchor;\n";
    expand_counter: s64 = 0;
    expanded := transpile_source(source, synth_ctx(.EXPAND, "src/a.jai", *expand_counter));
    // The synth plugin declares STRIP-only: in EXPAND mode it is never
    // dispatched — the anchor passes through untouched.
    expect(expanded.diagnostics.count == 0);
    expect(expanded.tests.count == 0);
    expect(expanded.view == source);
    expect(expand_counter == 0);

    strip_counter: s64 = 0;
    stripped := transpile_source(source, synth_ctx(.STRIP, "src/a.jai", *strip_counter));
    expect(stripped.diagnostics.count == 0);
    expect(stripped.tests.count == 1);
    expect(stripped.tests[0].name == "synth:src/a.jai:1" && stripped.tests[0].number == 1 && stripped.tests[0].line == 1);
    expect(stripped.view == "synth_stripped;\n");
    expect(strip_counter == 1);
}

test "Pipeline: cross-file state continues across calls" {
    counter: s64 = 0;
    ctx := synth_ctx(.STRIP, "src/a.jai", *counter);
    first := transpile_source("synth_anchor;\nsynth_anchor;\n", ctx);
    expect(first.diagnostics.count == 0);
    expect(first.tests.count == 2);
    expect(first.tests[0].number == 1 && first.tests[1].number == 2);
    expect(first.view == "synth_stripped;\nsynth_stripped;\n");

    // The same pipeline and state slot, a different file: the numbering
    // continues across transpile_source calls.
    ctx.path = "src/b.jai";
    second := transpile_source("synth_anchor;\n", ctx);
    expect(second.tests.count == 1);
    expect(second.tests[0].number == 3);
    expect(second.tests[0].name == "synth:src/b.jai:1");
    expect(counter == 3);
}

test "Pipeline: the diagnostic channel records a malformed anchor" {
    counter: s64 = 0;
    result := transpile_source("synth_anchor x;\n", synth_ctx(.STRIP, "src/a.jai", *counter));
    expect(result.diagnostics.count == 1);
    expect(result.diagnostics[0].line == 1 && result.diagnostics[0].column == 1);
    expect(result.diagnostics[0].message == "synth 锚点缺少 ;");
    expect(result.view == "synth_anchor x;\n");
    expect(counter == 0);
}

test "Probe: has_anchor aggregation skips null hooks" {
    expect(!pipeline_has_anchors(Transpile_Plugin.[], "synth_anchor;\n", "src/a.jai"));
    synth_pipeline: [..] Transpile_Plugin;
    array_add(*synth_pipeline, synth_plugin());
    expect(pipeline_has_anchors(synth_pipeline, "synth_anchor;\n", "src/a.jai"));
    expect(!pipeline_has_anchors(synth_pipeline, "x := 1;\n", "src/a.jai"));
    // A plugin without an anchor hook contributes nothing (nullable skip).
    expect(!pipeline_has_anchors(.[claim_a_plugin()], "synth_anchor;\n", "src/a.jai"));
}

test "Probe: load_edges aggregation combines plugins in pipeline order" {
    source := "#extra_load \"c.jai\";\n#synth_load \"b.jai\";\n";
    synth_first: [..] Transpile_Plugin;
    array_add(*synth_first, synth_plugin());
    array_add(*synth_first, extra_edges_plugin());
    edges := pipeline_load_edges(synth_first, source, "src/foo.jai");
    // Pipeline order, not source order: the synth plugin's edge comes first
    // even though its directive sits on the later line.
    expect(edges.count == 2 && edges[0] == "b.jai" && edges[1] == "c.jai");

    extra_first: [..] Transpile_Plugin;
    array_add(*extra_first, extra_edges_plugin());
    array_add(*extra_first, synth_plugin());
    reversed := pipeline_load_edges(extra_first, source, "src/foo.jai");
    expect(reversed.count == 2 && reversed[0] == "c.jai" && reversed[1] == "b.jai");

    // Pipelines without load_edges hooks contribute no edges (nullable skip).
    expect(pipeline_load_edges(.[claim_a_plugin()], source, "src/foo.jai").count == 0);
    expect(pipeline_load_edges(Transpile_Plugin.[], source, "src/foo.jai").count == 0);
}

test "Runner rejects non-equal-line plugin edits" {
    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = "src/a.jai";
    array_add(*ctx.plugins, violate_line_plugin());
    result := transpile_source("violate_line;\n", ctx);
    expect(result.diagnostics.count == 1);
    expect(result.diagnostics[0].line == 1 && result.diagnostics[0].column == 1);
    expect(result.diagnostics[0].message == "编辑违反行号保真：等行数展开失败");
    expect(result.view == "violate_line;\n");
}

test "Runner rejects token-unbounded plugin edits" {
    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = "src/a.jai";
    array_add(*ctx.plugins, violate_bounds_plugin());
    result := transpile_source("violate_bounds;\n", ctx);
    expect(result.diagnostics.count == 1);
    expect(result.diagnostics[0].message == "编辑未以 token 为界");
    expect(result.view == "violate_bounds;\n");
}
