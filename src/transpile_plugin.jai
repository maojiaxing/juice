// Registry-driven transpile pipeline (spec 0060 decisions 2/3/4/7/8, ticket
// 0061): the plugin interface, the two built-in plugins (test-block handling
// and #load handling — the two branches the old transpile_source scan loop
// hardcoded), the pipeline runner (the scan loop itself, dispatching to the
// registered plugins in declaration order) and the probe aggregation
// (closure decisions ask the pipeline instead of hardcoding the transforms).
// Zero observable behavior change: the default static registry reproduces
// the old branch order exactly, and the existing transpile tests keep
// proving that byte for byte.
//
// This module is a bootstrap build.jai #load target and must stay test-free;
// its unit tests live in tests/transpile_plugin_tests.jai (0053 rule). The
// shared infrastructure it builds on (lexer, edits, line-fidelity helpers,
// the Transpile_Context / Test_Entry / Transpile_Result contract) stays in
// src/transpile.jai, loaded right before this file in build.jai and main.jai.

#import "Basic";
#import "String";

// ---------------------------------------------------------------------------
// Plugin interface
// ---------------------------------------------------------------------------

// A plugin's mode applicability: which transpile modes its transpile hook
// handles (the test-block plugin behaves completely differently per mode;
// the #load plugin shares its recognition across modes). Probe hooks are
// mode-independent.
Transpile_Plugin_Modes :: struct {
    strip:  bool;
    expand: bool;
}

plugin_mode_applies :: (plugin: Transpile_Plugin, mode: Transpile_Mode) -> bool {
    if mode == .STRIP return plugin.modes.strip;
    return plugin.modes.expand;
}

// The runner's per-dispatch state handed to each transpile hook: the scan
// position (token index), the brace depth and the statement-position
// bookkeeping, and the three output sinks (edits / test entries /
// diagnostics). A claiming hook owns the cursor and bookkeeping for its
// region; an unclaimed token keeps the runner's default tracking.
Transpile_Scan :: struct {
    source:      string;   // line-ending-normalized source
    tokens:      [] Token;
    line_starts: [] s64;
    index:       s64;      // scan position (token index)
    depth:       s64;      // brace depth at the scan position
    have_prev:   bool;     // statement-position tracking (is_statement_position)
    prev_text:   string;
    edits:       *[..] Edit;
    tests:       *[..] Test_Entry;
    diagnostics: *[..] Transpile_Diagnostic;
}

// One registered pipeline plugin. Identity (name + version) is part of the
// pipeline description (it feeds the cache key's pipeline component, 0062);
// the probe hooks are paired with the transpile hook:
// - has_anchor: does the transpile hook act on anything in this source?
//   Feeds the closure viewing decision (ADR 0004 decision 1) via
//   pipeline_has_anchors. Required.
// - load_edges: the load edges this source contributes to the closure DFS,
//   via pipeline_load_edges. Optional (null = no edges).
// - transpile: dispatched by the runner at every scan position (in
//   declaration order, gated by mode applicability). A claiming hook owns
//   the cursor, the depth/statement-position bookkeeping and the three
//   sinks for its region; a non-claiming hook leaves the position
//   untouched and the token passes through.
// Cross-file state flows through Transpile_Context extension fields: each
// plugin reads its plugin_state slot (aligned with the pipeline order) and
// casts it to its own state type; the caller owns the slot's storage, which
// persists across transpile_source calls (the same channel family as
// next_test_number's numbering continuation).
Transpile_Plugin :: struct {
    name:       string;
    version:    string;
    modes:      Transpile_Plugin_Modes;
    has_anchor: #type (source: string, path: string) -> bool;
    load_edges: #type (source: string, path: string) -> [..] string;
    transpile:  #type (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool;
}

// ---------------------------------------------------------------------------
// Built-in plugin: #load handling (the old hardcoded #load branch)
// ---------------------------------------------------------------------------

// Both modes share the recognition; the behavior differs per mode:
// - EXPAND: in-package #load statements become equal-line comment
//   placeholders (load_strip_edit);
// - STRIP: the target string is rewritten to the view path looked up in
//   ctx.load_targets (the Merkle-chain rewrite table).
// No anchor of its own — a #load never triggers closure viewing on its own
// (has_anchor is null); the load_edges hook feeds the closure DFS.
load_plugin :: () -> Transpile_Plugin {
    plugin: Transpile_Plugin;
    plugin.name = "load";
    plugin.version = "1.0.0";
    plugin.modes = .{strip = true, expand = true};
    plugin.has_anchor = null;
    plugin.load_edges = load_plugin_edges;
    plugin.transpile = load_plugin_transpile;
    return plugin;
}

// Literal in-package #load targets of a source file, resolved against its
// package-relative path ("/" separated), in statement order. Non-literal
// targets (#load CONST) and out-of-package targets are absent by design:
// their files are never viewed or rewritten.
load_plugin_edges :: (source: string, path: string) -> [..] string {
    s := normalize_view_line_endings(source);
    tokens := lex_source(s);
    targets: [..] string;
    i := 0;
    while i < tokens.count {
        tok := tokens[i];
        if tok.kind == .DIRECTIVE && token_text(s, tok) == "#load" && i + 2 < tokens.count
            && tokens[i+1].kind == .STRING && token_text(s, tokens[i+2]) == ";" {
            target := tokens[i+1];
            value := decode_jai_string(slice(s, target.start + 1, target.end - target.start - 2));
            resolved, in_package := resolve_load_target(path, value);
            if in_package array_add(*targets, resolved);
            i += 3;
            continue;
        }
        i += 1;
    }
    return targets;
}

// The #load plugin's transpile hook (the old hardcoded #load branch):
// literal #load statements — DIRECTIVE(#load) STRING ; — are claimed
// wherever the runner dispatches the plugin. That includes inside a test
// body in EXPAND mode: the test plugin's claim enters the body without
// consuming it (see the runner's region interaction contract).
load_plugin_transpile :: (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool {
    s := scan.source;
    tokens := scan.tokens;
    i := scan.index;
    tok := tokens[i];
    if tok.kind != .DIRECTIVE || token_text(s, tok) != "#load" || i + 2 >= tokens.count
        || tokens[i+1].kind != .STRING || token_text(s, tokens[i+2]) != ";" {
        return false;
    }
    target := tokens[i+1];
    semi := tokens[i+2];
    shared_before := i > 0 && tokens[i-1].end_line >= tok.line;
    shared_after := i + 3 < tokens.count && tokens[i+3].line == semi.line;
    if shared_before || shared_after {
        array_add(scan.diagnostics, .{line = tok.line, column = tok.column, message = "#load 必须独占其行"});
        // Not claimed: the statement stays verbatim.
        return false;
    }
    value := decode_jai_string(slice(s, target.start + 1, target.end - target.start - 2));
    resolved, in_package := resolve_load_target(ctx.path, value);
    if !in_package return false;
    if ctx.mode == .EXPAND {
        array_add(scan.edits, load_strip_edit(s, scan.line_starts, tok, semi));
    } else if target.end_line > target.line {
        array_add(scan.diagnostics, .{line = target.line, column = target.column, message = "#load 目标字符串不可跨行"});
    } else {
        rewrite_to, found := find_load_target(ctx.load_targets, resolved);
        if !found {
            array_add(scan.diagnostics, .{line = tok.line, column = tok.column, message = "in-package #load 缺少视图目标"});
        } else {
            array_add(scan.edits, .{start = target.start, end = target.end, text = quote_jai_string(rewrite_to)});
        }
    }
    scan.index = i + 3;
    scan.prev_text = ";";
    scan.have_prev = true;
    return true;
}

// ---------------------------------------------------------------------------
// Built-in plugin: test-block handling (the old hardcoded test anchor branch)
// ---------------------------------------------------------------------------

// Both modes have anchors; the behaviors are completely different:
// - STRIP: the whole block becomes an equal-line comment placeholder
//   (strip_block_edit);
// - EXPAND: the header is rewritten to `juice_test_N :: () -> () {`, an
//   @test tag lands after the closing brace and a Test_Entry joins the
//   manifest.
// load_edges is null: test blocks contribute no closure edges.
test_block_plugin :: () -> Transpile_Plugin {
    plugin: Transpile_Plugin;
    plugin.name = "test-block";
    plugin.version = "1.0.0";
    plugin.modes = .{strip = true, expand = true};
    plugin.has_anchor = test_block_has_anchor;
    plugin.load_edges = null;
    plugin.transpile = test_block_transpile;
    return plugin;
}

// Whether the source contains any test block the transpiler acts on in
// either mode: a `test` anchor in statement position at file top level, or
// one at brace depth > 0 (rejected with a diagnostic there). Anchors in
// non-statement positions (e.g. `if test {`) pass through untouched and do
// not count. The build front probes closures with this (aggregated over the
// pipeline) to decide whether viewing is needed (ADR 0004 decision 1).
test_block_has_anchor :: (source: string, path: string) -> bool {
    s := normalize_view_line_endings(source);
    tokens := lex_source(s);
    depth := 0;
    have_prev := false;
    prev_text := "";
    i := 0;
    while i < tokens.count {
        tok := tokens[i];
        text := token_text(s, tok);
        if tok.kind == .IDENT && text == "test" && is_test_anchor(s, tokens, i) {
            if depth > 0 || is_statement_position(have_prev, prev_text) return true;
        }
        if tok.kind == .PUNCT && text == "{" {
            depth += 1;
        } else if tok.kind == .PUNCT && text == "}" {
            if depth > 0 depth -= 1;
        }
        prev_text = text;
        have_prev = true;
        i += 1;
    }
    return false;
}

// The test-block plugin's transpile hook (the old hardcoded test anchor
// branch): recognizes `test` + string + `{` / `test` + `{` anchors, rejects
// illegal shapes with diagnostics (nested blocks, non-statement positions
// pass through untouched, multi-line heads, trailing statements after a
// stripped close — the ADR 0005 enforcement precedent) and claims:
// - STRIP: an equal-line comment placeholder covering the whole block
//   (strip_block_edit). The cursor jumps past the closing brace, so tokens
//   inside the placeholder are never dispatched again — loads inside
//   stripped test bodies vanish with the placeholder;
// - EXPAND: the header rewrite + the @test tag + the Test_Entry manifest
//   record. The cursor enters the body (depth + 1) without consuming it, so
//   later dispatches still reach the loads inside it (the region
//   interaction contract, see the runner).
test_block_transpile :: (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool {
    s := scan.source;
    tokens := scan.tokens;
    i := scan.index;
    tok := tokens[i];
    if tok.kind != .IDENT || token_text(s, tok) != "test" return false;

    named := false;
    brace_index := -1;
    if i + 2 < tokens.count && tokens[i+1].kind == .STRING && token_text(s, tokens[i+2]) == "{" {
        named = true;
        brace_index = i + 2;
    } else if i + 1 < tokens.count && token_text(s, tokens[i+1]) == "{" {
        brace_index = i + 1;
    }
    if brace_index < 0 return false;

    brace := tokens[brace_index];
    name_tok := tokens[i+1];
    single_line := brace.line == tok.line;
    if named {
        single_line = single_line && name_tok.line == tok.line && name_tok.end_line == tok.line;
    }
    if scan.depth > 0 {
        array_add(scan.diagnostics, .{line = tok.line, column = tok.column, message = "test block 仅允许文件顶层"});
        // Not claimed: the block stays verbatim.
        return false;
    }
    if !is_statement_position(scan.have_prev, scan.prev_text) {
        // Not a statement start: e.g. `if test { ... }`. Pass through.
        return false;
    }
    if !single_line {
        array_add(scan.diagnostics, .{line = tok.line, column = tok.column, message = "test 头必须位于同一行"});
        // Not claimed: the block stays verbatim.
        return false;
    }
    close_index, closed := find_matching_close(s, tokens, brace_index);
    if !closed {
        array_add(scan.diagnostics, .{line = tok.line, column = tok.column, message = "test block 缺少闭合 }"});
        // Stop the scan entirely (the old break semantics): nothing after
        // an unterminated block is processed.
        scan.index = tokens.count;
        return true;
    }
    close := tokens[close_index];
    if ctx.mode == .STRIP {
        // Any other token after the closing brace on the same line would be
        // swallowed by the placeholder comment. A chained test anchor is
        // fine: each block gets its own placeholder and they share the line.
        trailing := close_index + 1 < tokens.count && tokens[close_index + 1].line == close.line;
        if trailing && !is_test_anchor(s, tokens, close_index + 1) {
            next := tokens[close_index + 1];
            array_add(scan.diagnostics, .{line = next.line, column = next.column, message = "test block 闭括号后不得有其他语句"});
            // Not claimed: the block stays verbatim.
            return false;
        }
        array_add(scan.edits, strip_block_edit(s, scan.line_starts, tok, close));
        scan.index = close_index + 1;
        scan.prev_text = "}";
        scan.have_prev = true;
        return true;
    }
    number := ctx.next_test_number + scan.tests.count;
    entry: Test_Entry;
    entry.number = number;
    entry.line = tok.line;
    if named {
        entry.name = decode_jai_string(slice(s, name_tok.start + 1, name_tok.end - name_tok.start - 2));
    } else {
        entry.name = tprint("%1:%2", ctx.path, tok.line);
    }
    array_add(scan.tests, entry);
    array_add(scan.edits, .{start = tok.start, end = brace.end, text = tprint("juice_test_%1 :: () -> () {", number)});
    array_add(scan.edits, .{start = close.end, end = close.end, text = " @test"});
    // Scan the body (loads inside it still need stripping); the closing
    // brace is consumed by the "@test" edit.
    scan.index = brace_index + 1;
    scan.depth += 1;
    scan.prev_text = "{";
    scan.have_prev = true;
    return true;
}

// ---------------------------------------------------------------------------
// Probe aggregation
// ---------------------------------------------------------------------------

// The closure viewing decision asks the pipeline (spec 0060 decision 4):
// any plugin's has_anchor hook reporting an anchor views the closure (ADR
// 0004 decision 1). Plugins without the hook contribute nothing; a
// pipeline-wide "no anchor" keeps the test-free closure's zero-transpile
// short circuit unchanged.
pipeline_has_anchors :: (pipeline: [] Transpile_Plugin, source: string, path: string) -> bool {
    for plugin: pipeline {
        if plugin.has_anchor == null continue;
        if plugin.has_anchor(source, path) return true;
    }
    return false;
}

// The closure DFS edge source asks the pipeline: every plugin's optional
// load_edges hook contributes its edges in pipeline order (the #load
// plugin's literal in-package targets today).
pipeline_load_edges :: (pipeline: [] Transpile_Plugin, source: string, path: string) -> [..] string {
    edges: [..] string;
    for plugin: pipeline {
        if plugin.load_edges == null continue;
        for edge: plugin.load_edges(source, path) array_add(*edges, edge);
    }
    return edges;
}

// ---------------------------------------------------------------------------
// Pipeline runner
// ---------------------------------------------------------------------------

// The default static registry: the two built-in plugins in the old
// hardcoded branch order (#load first, test anchors second). Declaration
// order = dispatch order.
default_transpile_pipeline :: () -> [..] Transpile_Plugin {
    pipeline: [..] Transpile_Plugin;
    array_add(*pipeline, load_plugin());
    array_add(*pipeline, test_block_plugin());
    return pipeline;
}

// 1-based line and column of a byte offset (binary search over the line
// start offsets from compute_line_starts).
offset_location :: (starts: [] s64, offset: s64) -> s64, s64 {
    lo := 0;
    hi := starts.count - 1;
    while lo < hi {
        mid := (lo + hi + 1) / 2;
        if starts[mid] <= offset {
            lo = mid;
        } else {
            hi = mid - 1;
        }
    }
    return lo + 1, offset - starts[lo] + 1;
}

// Number of lines covered by a byte range (a zero-width range covers the
// one line it sits on).
line_count_of :: (s: string, start: s64, end: s64) -> s64 {
    n := 1;
    for i: start..end-1 {
        if s[i] == #char "\n" n += 1;
    }
    return n;
}

// ADR 0005's token-boundedness: an edit point sits on a token boundary —
// its start and end are each either a token start or a token end
// (zero-width insertions like the @test tag sit on a single boundary).
edit_token_bounded :: (tokens: [] Token, edit: Edit) -> bool {
    start_ok := false;
    end_ok := false;
    for tok: tokens {
        if tok.start == edit.start || tok.end == edit.start start_ok = true;
        if tok.start == edit.end || tok.end == edit.end end_ok = true;
    }
    return start_ok && end_ok;
}

// ADR 0005 hard constraint, enforced by the runner for every plugin (spec
// 0060 decision 8): each edit must expand 1 source line into exactly 1 view
// line (the multi-line test head rejection generalized) and must be bounded
// by token boundaries. Violating edits are dropped and reported as
// diagnostics — bad plugins fail loudly at transpile time instead of
// silently breaking line fidelity. The built-in plugins never violate the
// constraint, so existing behavior is unchanged.
enforce_line_fidelity :: (s: string, starts: [] s64, tokens: [] Token, edits: [] Edit, diagnostics: *[..] Transpile_Diagnostic) -> [..] Edit {
    kept: [..] Edit;
    for edit: edits {
        line, column := offset_location(starts, edit.start);
        if line_count_of(s, edit.start, edit.end) != line_count_of(edit.text, 0, edit.text.count) {
            array_add(diagnostics, .{line = line, column = column, message = "编辑违反行号保真：等行数展开失败"});
        } else if !edit_token_bounded(tokens, edit) {
            array_add(diagnostics, .{line = line, column = column, message = "编辑未以 token 为界"});
        } else {
            array_add(*kept, edit);
        }
    }
    return kept;
}

// The single transpile entry (spec 0060 decision 3): the scan loop that
// used to hardcode the two branches is now the pipeline runner — the depth
// + statement-position + edit-collection skeleton is unchanged, the
// branches are replaced by plugin dispatch from the context's registry (an
// empty registry means the default pipeline, so every existing caller keeps
// its behavior unchanged).
//
// Region interaction contract (explicit at the runner layer): a plugin
// claim covers exactly the tokens it consumes. The test plugin's EXPAND
// claim replaces the header and enters the block body without consuming it
// (cursor at the brace's successor, depth + 1) — the runner keeps
// dispatching every applicable plugin inside the claimed region, so #load
// statements inside test bodies are still stripped by the #load plugin
// (locked by tests/transpile_tests.jai:73-77). Its STRIP claim consumes the
// whole block through the closing brace, so tokens inside the placeholder
// are never dispatched — loads inside stripped test bodies vanish with the
// placeholder (transpile_tests.jai:148-154). The same contract governs any
// future plugin: what a plugin does not consume stays dispatchable.
transpile_source :: (source: string, ctx: Transpile_Context) -> Transpile_Result {
    s := normalize_view_line_endings(source);
    tokens := lex_source(s);
    starts := compute_line_starts(s);

    edits: [..] Edit;
    tests: [..] Test_Entry;
    diagnostics: [..] Transpile_Diagnostic;

    pipeline := ctx.plugins;
    if pipeline.count == 0 pipeline = default_transpile_pipeline();

    scan: Transpile_Scan;
    scan.source = s;
    scan.tokens = tokens;
    scan.line_starts = starts;
    scan.edits = *edits;
    scan.tests = *tests;
    scan.diagnostics = *diagnostics;
    scan.index = 0;
    scan.depth = 0;
    scan.have_prev = false;
    scan.prev_text = "";

    while scan.index < tokens.count {
        claimed := false;
        for plugin, i: pipeline {
            if !plugin_mode_applies(plugin, ctx.mode) continue;
            state: *void = null;
            if i < ctx.plugin_state.count state = ctx.plugin_state[i];
            if plugin.transpile(*scan, *ctx, state) {
                claimed = true;
                break;
            }
        }
        if claimed continue;

        // No plugin claimed the position: the token passes through with the
        // runner's default bookkeeping.
        tok := tokens[scan.index];
        text := token_text(s, tok);
        if tok.kind == .PUNCT && text == "{" {
            scan.depth += 1;
        } else if tok.kind == .PUNCT && text == "}" {
            if scan.depth > 0 scan.depth -= 1;
        }
        scan.prev_text = text;
        scan.have_prev = true;
        scan.index += 1;
    }

    // ADR 0005 hard constraint, enforced for every plugin's edits before
    // they are applied (spec 0060 decision 8).
    edits = enforce_line_fidelity(s, starts, tokens, edits, *diagnostics);

    result: Transpile_Result;
    result.view = apply_edits(s, edits);
    result.tests = tests;
    result.diagnostics = diagnostics;
    return result;
}
