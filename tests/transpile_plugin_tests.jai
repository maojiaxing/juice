// ---------------------------------------------------------------------------
// Transpile pipeline tests (spec 0060 Testing Decisions 接缝 3, tickets
// 0061/0062): the plugin interface and runner mechanics, proven with a
// synthetic third plugin — dispatch through the three output channels (edits
// / manifest entries / diagnostics), cross-file state continuation, mode
// applicability, probe aggregation, the runner's ADR 0005 rejection and the
// cache key's pipeline description component (name/version/order
// sensitivity) — without touching the two built-in plugins' locked outputs
// (those stay locked by tests/transpile_tests.jai).
//
// Key constraint (same as tests/transpile_tests.jai): src/transpile_plugin.jai
// is a build.jai #load target / entry closure member — test blocks would be
// illegal inside a metaprogram compile-time text inclusion, so the module
// must stay test-free and its tests live here (tests/), per the test
// organization rule: referenced by no #load, collected into the test program
// by Test discovery's full-package scan. This file contains only test blocks
// and their helper declarations; zero production code coupling.
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";

// ===========================================================================
// The synthetic third plugin (spec 0060 Testing Decisions 接缝 3): proves the
// pipeline mechanics — dispatch through the three output channels, cross-file
// state continuation, mode applicability, probe aggregation — without
// touching the two built-in plugins' locked outputs.
// ===========================================================================
//
// Anchor: a statement-position `synth_anchor` token. STRIP mode: the anchor
// is rewritten to `synth_stripped` (a 1-line, token-bounded edit), a
// manifest entry joins the test list and the plugin's state counter
// advances. EXPAND mode: not applicable — the runner never dispatches the
// plugin, the anchor passes through untouched. An anchor not followed by
// `;` is a diagnostic (not claimed).
// Probe hooks: has_anchor sees statement-position anchors; load_edges
// contributes the (unresolved) target of `#synth_load "x.jai";` statements.

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
            array_add(*edges, decode_jai_string(slice(s, target.start + 1, target.end - target.start - 2)));
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

// A context whose pipeline is the default registry plus the synthetic
// plugin (slot 2 = the caller's counter); the default registry's own slots
// stay null.
synth_ctx :: (mode: Transpile_Mode, path: string, counter: *s64) -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = mode;
    ctx.path = path;
    ctx.next_test_number = 1;
    ctx.plugins = default_transpile_pipeline();
    array_add(*ctx.plugins, synth_plugin());
    array_add(*ctx.plugin_state, null);
    array_add(*ctx.plugin_state, null);
    array_add(*ctx.plugin_state, counter);
    return ctx;
}

// ===========================================================================
// The violating fixtures: two plugins whose edits break the ADR 0005 hard
// constraint (spec 0060 decision 8) — one replaces a 1-line region with
// 2-line text (equal-line expansion fails), the other starts its edit in
// the middle of a token. The runner must drop the edit and report a
// diagnostic; the view keeps the source verbatim.
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

test "Pipeline: default registry order and identity" {
    pipeline := default_transpile_pipeline();
    expect(pipeline.count == 2);
    expect(pipeline[0].name == "load" && pipeline[0].version == "1.0.0");
    expect(pipeline[1].name == "test-block" && pipeline[1].version == "1.0.0");
    expect(pipeline[0].modes.strip && pipeline[0].modes.expand);
    expect(pipeline[1].modes.strip && pipeline[1].modes.expand);
    expect(pipeline[0].has_anchor == null && pipeline[1].load_edges == null);
}

test "Pipeline: an empty registry means the default pipeline" {
    result := transpile_source("test \"a\" { }\n", .{mode = .EXPAND, path = "src/a.jai", next_test_number = 1});
    expect(result.diagnostics.count == 0);
    expect(result.view == "juice_test_1 :: () -> () { } @test\n");
}

test "Pipeline: synthetic plugin dispatches all three channels" {
    counter: s64 = 0;
    result := transpile_source("synth_anchor;\nsynth_anchor x;\n", synth_ctx(.STRIP, "src/a.jai", *counter));
    // Edit channel: the claimed anchor is rewritten.
    expect(result.view == "synth_stripped;\nsynth_anchor x;\n");
    // Manifest channel: one entry, numbered from the plugin's state slot.
    expect(result.tests.count == 1);
    expect(result.tests[0].name == "synth:src/a.jai:1" && result.tests[0].number == 1 && result.tests[0].line == 1);
    // Diagnostic channel: the malformed second anchor.
    expect(result.diagnostics.count == 1);
    expect(result.diagnostics[0].line == 2 && result.diagnostics[0].column == 1);
    expect(result.diagnostics[0].message == "synth 锚点缺少 ;");
    expect(counter == 1);
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

test "Pipeline: mode applicability gates the dispatch" {
    source := "synth_anchor;\ntest \"t\" { }\n";
    expand_counter: s64 = 0;
    expanded := transpile_source(source, synth_ctx(.EXPAND, "src/a.jai", *expand_counter));
    // The synth plugin declares STRIP-only: in EXPAND mode it is never
    // dispatched — the anchor passes through, the built-in test plugin
    // still expands.
    expect(expanded.diagnostics.count == 0);
    expect(expanded.tests.count == 1);
    expect(expanded.tests[0].name == "t");
    expect(expanded.view == "synth_anchor;\njuice_test_1 :: () -> () { } @test\n");
    expect(expand_counter == 0);

    strip_counter: s64 = 0;
    stripped := transpile_source(source, synth_ctx(.STRIP, "src/a.jai", *strip_counter));
    // In STRIP mode the synth plugin claims its anchor and the built-in
    // test plugin strips the block, in declaration order.
    expect(stripped.diagnostics.count == 0);
    expect(stripped.tests.count == 1);
    expect(stripped.tests[0].name == "synth:src/a.jai:1");
    expect(stripped.view == "synth_stripped;\n// juice: test stripped: test \"t\" { }\n");
    expect(strip_counter == 1);
}

test "Pipeline: stripped test body is not dispatched to later plugins" {
    counter: s64 = 0;
    result := transpile_source("test \"a\" {\n    synth_anchor;\n}\n", synth_ctx(.STRIP, "src/a.jai", *counter));
    // The test plugin's STRIP claim consumes the whole block: the synth
    // anchor inside the placeholder is never dispatched.
    expect(result.diagnostics.count == 0);
    expect(result.tests.count == 0);
    expect(result.view == "// juice: test stripped: test \"a\" {\n    // juice: test stripped\n// juice: test stripped\n");
    expect(counter == 0);
}

test "Probe: has_anchor aggregation combines plugins" {
    default_pipeline := default_transpile_pipeline();
    synth_source := "synth_anchor;\n";
    test_source := "test \"a\" { }\n";
    // The default registry alone sees no anchor in the synth source...
    expect(!pipeline_has_anchors(default_pipeline, synth_source, ""));
    // ...the synthetic plugin's hook flips the aggregated decision...
    with_synth := default_transpile_pipeline();
    array_add(*with_synth, synth_plugin());
    expect(pipeline_has_anchors(with_synth, synth_source, ""));
    // ...and the built-ins keep their own anchors visible.
    expect(pipeline_has_anchors(default_pipeline, test_source, ""));
    expect(!pipeline_has_anchors(.[synth_plugin()], test_source, ""));
}

test "Probe: load_edges aggregation combines plugins" {
    source := "#load \"a.jai\";\n#synth_load \"b.jai\";\n";
    default_edges := pipeline_load_edges(default_transpile_pipeline(), source, "src/foo.jai");
    expect(default_edges.count == 1 && default_edges[0] == "src/a.jai");
    with_synth := default_transpile_pipeline();
    array_add(*with_synth, synth_plugin());
    edges := pipeline_load_edges(with_synth, source, "src/foo.jai");
    expect(edges.count == 2 && edges[0] == "src/a.jai" && edges[1] == "b.jai");
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

// ---------------------------------------------------------------------------
// Cache-key pipeline description (spec 0060 decision 5, ticket 0062): the
// view cache key embeds the ordered name+version sequence of the registry
// that produces the view, so a plugin rename, a version bump or a pipeline
// reorder each changes the key precisely — and an omitted pipeline means
// the default registry.
// ---------------------------------------------------------------------------

test "Cache key: pipeline description is component-sensitive" {
    base: [..] Transpile_Plugin;
    array_add(*base, load_plugin());
    array_add(*base, synth_plugin());
    key := transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION, base);
    expect(key == transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION, base));

    // Name change → key change (same version, same order, same input).
    renamed: [..] Transpile_Plugin;
    array_add(*renamed, load_plugin());
    renamed_synth := synth_plugin();
    renamed_synth.name = "synth-renamed";
    array_add(*renamed, renamed_synth);
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION, renamed));

    // Version change → key change.
    bumped: [..] Transpile_Plugin;
    array_add(*bumped, load_plugin());
    bumped_synth := synth_plugin();
    bumped_synth.version = "1.0.1";
    array_add(*bumped, bumped_synth);
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION, bumped));

    // Order change → key change.
    reversed: [..] Transpile_Plugin;
    array_add(*reversed, synth_plugin());
    array_add(*reversed, load_plugin());
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION, reversed));
}

test "Cache key: omitted pipeline means the default pipeline" {
    key := transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION);
    // The default registry's description joins the key when the pipeline is
    // omitted or empty...
    expect(key == transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION, default_transpile_pipeline()));
    expect(key == transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION, Transpile_Plugin.[]));
    // ...and the description is order-sensitive: the reordered default must
    // not collide with it.
    reversed: [..] Transpile_Plugin;
    array_add(*reversed, test_block_plugin());
    array_add(*reversed, load_plugin());
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION, reversed));
}
