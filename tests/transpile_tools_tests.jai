// ---------------------------------------------------------------------------
// Transpile tool face + built-in #load plugin tests (ticket 022): the string
// literal helpers (decode/escape/quote), the #load target resolution and
// lookup, the line-content helpers, the strip edit builders, and the
// built-in #load plugin — the default pipeline's first member (EXPAND
// placeholders, STRIP target rewrites, the load_edges edge source and the
// diagnostics). The built-in registry now resolves an empty registration to
// the #load plugin; the test-block plugin joins with ticket 023.
//
// Key constraint (same as the other sibling test files): src modules are
// bootstrap #load targets / entry closure members — test blocks would be
// illegal inside them, so they stay test-free and their tests live here
// (tests/), per the test organization rule: referenced by no #load,
// collected into the test program by Test discovery's full-package scan.
// This file contains only test blocks and their helper declarations; zero
// production code coupling. Good-test standard: only external behavior is
// pinned (given source + pipeline -> view text / entries / diagnostics).
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";
#import "String";

// ===========================================================================
// Helpers
// ===========================================================================

// Local matching-close scan for the strip-builder tests (find_matching_close
// joins src/transpile.jai with ticket 023's test-block plugin).
find_close :: (s: string, tokens: [] Token, open_index: s64) -> s64, bool {
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

count_lines :: (s: string) -> s64 {
    n := 1;
    for ch: s if ch == #char "\n" n += 1;
    return n;
}

// A context with an empty registration: the runner resolves it to the
// default pipeline (the #load plugin alone).
expand_ctx :: () -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = .EXPAND;
    ctx.path = "src/foo.jai";
    return ctx;
}

strip_ctx :: (targets: [] Load_Target) -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = "src/foo.jai";
    ctx.load_targets = targets;
    return ctx;
}

// region: claims a statement-position `region {` header and enters the body
// without consuming it — the runner keeps dispatching the later #load
// plugin inside the body (the test-block plugin's EXPAND claim plays the
// same role from ticket 023 onward).
region_transpile :: (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool {
    tok := scan.tokens[scan.index];
    if tok.kind != .IDENT || token_text(scan.source, tok) != "region" return false;
    if !is_statement_position(scan.have_prev, scan.prev_text) return false;
    if scan.index + 1 >= scan.tokens.count || token_text(scan.source, scan.tokens[scan.index + 1]) != "{" return false;
    scan.index += 2;
    scan.depth += 1;
    scan.prev_text = "{";
    scan.have_prev = true;
    return true;
}

region_plugin :: () -> Transpile_Plugin {
    plugin: Transpile_Plugin;
    plugin.name = "region";
    plugin.version = "1.0.0";
    plugin.modes = .{strip = true, expand = true};
    plugin.has_anchor = null;
    plugin.load_edges = null;
    plugin.transpile = region_transpile;
    return plugin;
}

// ---------------------------------------------------------------------------
// String literal helpers
// ---------------------------------------------------------------------------

test "Tool: string decode handles known escapes" {
    expect(decode_jai_string("a\\nb\\\"c\\\\d") == "a\nb\"c\\d");
    expect(decode_jai_string("\\x41") == "A");
    expect(decode_jai_string("a\\tb") == "a\tb");
}

test "Tool: string decode keeps unknown escapes" {
    expect(decode_jai_string("C:\\Users") == "C:\\Users");
    expect(decode_jai_string("\\q") == "\\q");
}

test "Tool: string escape and quote" {
    expect(escape_jai_string("C:\\a\"b") == "C:\\\\a\\\"b");
    expect(quote_jai_string("a\nb\"c\\d") == "\"a\\nb\\\"c\\\\d\"");
}

// ---------------------------------------------------------------------------
// #load target resolution
// ---------------------------------------------------------------------------

test "Tool: load target resolution matrix" {
    resolved, ok := resolve_load_target("src/foo.jai", "bar.jai");
    expect(ok && resolved == "src/bar.jai");
    resolved, ok = resolve_load_target("src/foo.jai", "../x.jai");
    expect(ok && resolved == "x.jai");
    _, ok = resolve_load_target("src/foo.jai", "../../x.jai");
    expect(!ok);
    _, ok = resolve_load_target("src/foo.jai", "C:/x.jai");
    expect(!ok);
    _, ok = resolve_load_target("src/foo.jai", "/x.jai");
    expect(!ok);
    resolved, ok = resolve_load_target("foo.jai", "bar.jai");
    expect(ok && resolved == "bar.jai");
    resolved, ok = resolve_load_target("src/foo.jai", "sub\\x.jai");
    expect(ok && resolved == "src/sub/x.jai");
    _, ok = resolve_load_target("src/foo.jai", "");
    expect(!ok);
}

test "Tool: load target lookup" {
    targets := Load_Target.[.{from = "src/a.jai", to = "view-a"}, .{from = "src/b.jai", to = "view-b"}];
    to, found := find_load_target(targets, "src/b.jai");
    expect(found && to == "view-b");
    _, found = find_load_target(targets, "src/c.jai");
    expect(!found);
}

// ---------------------------------------------------------------------------
// Strip edit builders (strip_block_edit joins ticket 023's test-block plugin)
// ---------------------------------------------------------------------------

test "Tool: strip builder single-line block" {
    source := "test \"x\" { body(); }\n";
    tokens := lex_source(source);
    close_index, closed := find_close(source, tokens, 2);
    expect(closed);
    edit := strip_block_edit(source, compute_line_starts(source), tokens[0], tokens[close_index]);
    expect(edit.text == "// juice: test stripped: test \"x\" { body(); }");
}

test "Tool: strip builder multi-line block keeps indentation" {
    source := "    test \"x\" {\n        body();\n    }\n";
    tokens := lex_source(source);
    close_index, closed := find_close(source, tokens, 2);
    expect(closed);
    edit := strip_block_edit(source, compute_line_starts(source), tokens[0], tokens[close_index]);
    expected := "// juice: test stripped: test \"x\" {\n        // juice: test stripped\n    // juice: test stripped";
    expect(edit.text == expected);
}

test "Tool: strip builder chained blocks share the line" {
    source := "test \"a\" { } test \"b\" { }\n";
    tokens := lex_source(source);
    close1, _ := find_close(source, tokens, 2);
    close2, _ := find_close(source, tokens, 6);
    edits: [..] Edit;
    array_add(*edits, strip_block_edit(source, compute_line_starts(source), tokens[0], tokens[close1]));
    array_add(*edits, strip_block_edit(source, compute_line_starts(source), tokens[4], tokens[close2]));
    expect(apply_edits(source, edits) == "// juice: test stripped: test \"a\" { } // juice: test stripped: test \"b\" { }\n");
}

test "Tool: line-content helpers" {
    s := "  abc\n";
    starts := compute_line_starts(s);
    expect(starts.count == 2 && starts[0] == 0 && starts[1] == 6);
    expect(line_content_end(s, starts, 0) == 5);
    expect(line_content_end(s, starts, 1) == 6);
    expect(first_non_whitespace(s, 0, 5) == 2);
    expect(first_non_whitespace(" \t x", 0, 4) == 3);
}

// ---------------------------------------------------------------------------
// The built-in #load plugin: EXPAND mode
// ---------------------------------------------------------------------------

test "Load EXPAND: in-package #load becomes placeholder" {
    result := transpile_source("#load \"helper.jai\";\n", expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.tests.count == 0);
    expect(result.view == "// juice: load stripped: #load \"helper.jai\";\n");
}

test "Load EXPAND: multi-line #load gets (cont) placeholder" {
    result := transpile_source("#load\n\"multi.jai\";\n", expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.view == "// juice: load stripped: #load\n// juice: load stripped (cont)\n");
}

test "Load EXPAND: placeholder keeps indentation" {
    result := transpile_source("    #load \"helper.jai\";\n", expand_ctx());
    expect(result.view == "    // juice: load stripped: #load \"helper.jai\";\n");
}

test "Load EXPAND: out-of-package and non-literal #load verbatim" {
    source := "#load \"../../outside.jai\";\n#load CONST_NAME;\n#load \"other\" + \".jai\";\n#import \"Basic\";\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.view == source);
}

test "Load: test-free file is identical in both modes" {
    source := "#import \"Basic\";\n\nmain :: () {\n    print(\"hello\\n\");\n}\n";
    expanded := transpile_source(source, expand_ctx());
    expect(expanded.diagnostics.count == 0 && expanded.tests.count == 0);
    expect(expanded.view == source);
    stripped := transpile_source(source, strip_ctx(Load_Target.[]));
    expect(stripped.diagnostics.count == 0);
    expect(stripped.view == source);
}

// ---------------------------------------------------------------------------
// The built-in #load plugin: STRIP mode
// ---------------------------------------------------------------------------

test "Load STRIP: target rewritten to view path" {
    targets := Load_Target.[.{from = "src/helper.jai", to = "C:/pkg/target/transpile/hash1/src/helper.jai"}];
    result := transpile_source("#load \"helper.jai\";\n", strip_ctx(targets));
    expect(result.diagnostics.count == 0);
    expect(result.view == "#load \"C:/pkg/target/transpile/hash1/src/helper.jai\";\n");
}

test "Load STRIP: rewritten path is escaped" {
    targets := Load_Target.[.{from = "src/h.jai", to = "C:\\Users\\a\"b.jai"}];
    result := transpile_source("#load \"h.jai\";\n", strip_ctx(targets));
    expect(result.diagnostics.count == 0);
    expect(result.view == "#load \"C:\\\\Users\\\\a\\\"b.jai\";\n");
}

test "Load STRIP: missing view target diagnostic" {
    result := transpile_source("#load \"helper.jai\";\n", strip_ctx(Load_Target.[]));
    expect(result.diagnostics.count == 1);
    expect(result.diagnostics[0].line == 1 && result.diagnostics[0].column == 1);
    expect(result.diagnostics[0].message == "in-package #load 缺少视图目标");
    expect(result.view == "#load \"helper.jai\";\n");
}

test "Load STRIP: multi-line shapes" {
    targets := Load_Target.[.{from = "src/multi.jai", to = "C:/v/src/multi.jai"}];
    // A target string spanning lines is rejected...
    multiline_target := transpile_source("#load \"a\nb\";\n", strip_ctx(targets));
    expect(multiline_target.diagnostics.count == 1);
    expect(multiline_target.diagnostics[0].line == 1 && multiline_target.diagnostics[0].column == 7);
    expect(multiline_target.diagnostics[0].message == "#load 目标字符串不可跨行");
    expect(multiline_target.view == "#load \"a\nb\";\n");
    // ...while a statement spanning lines with a single-line target rewrites.
    multiline_stmt := transpile_source("#load\n\"multi.jai\";\n", strip_ctx(targets));
    expect(multiline_stmt.diagnostics.count == 0);
    expect(multiline_stmt.view == "#load\n\"C:/v/src/multi.jai\";\n");
}

// ---------------------------------------------------------------------------
// The built-in #load plugin: shared diagnostics
// ---------------------------------------------------------------------------

test "Load: statement sharing a line is rejected" {
    before := transpile_source("x := 1; #load \"a.jai\";\n", expand_ctx());
    after := transpile_source("#load \"a.jai\"; x := 1;\n", expand_ctx());
    expect(before.diagnostics.count == 1 && after.diagnostics.count == 1);
    expect(before.diagnostics[0].line == 1 && before.diagnostics[0].column == 9);
    expect(before.diagnostics[0].message == "#load 必须独占其行");
    expect(after.diagnostics[0].column == 1);
    expect(before.view == "x := 1; #load \"a.jai\";\n");
    expect(after.view == "#load \"a.jai\"; x := 1;\n");
}

test "Load: #load inside a claimed region is stripped" {
    ctx: Transpile_Context;
    ctx.mode = .EXPAND;
    ctx.path = "src/a.jai";
    array_add(*ctx.plugins, region_plugin());
    array_add(*ctx.plugins, load_plugin());
    result := transpile_source("region {\n    #load \"helper.jai\";\n}\n", ctx);
    expect(result.diagnostics.count == 0);
    expect(result.view == "region {\n    // juice: load stripped: #load \"helper.jai\";\n}\n");
}

// ---------------------------------------------------------------------------
// The built-in #load plugin: probe and fidelity
// ---------------------------------------------------------------------------

test "Load edges: literal in-package targets resolved in statement order" {
    source := "#load \"sub/x.jai\";\n#load \"C:/abs.jai\";\n#load CONST;\n#import \"Basic\";\n#load \"..\\up.jai\";\n";
    edges := pipeline_load_edges(resolve_pipeline(Transpile_Plugin.[]), source, "src/foo.jai");
    expect(edges.count == 2 && edges[0] == "src/sub/x.jai" && edges[1] == "up.jai");
    // Escaped targets decode before resolution (backslashes normalize).
    escaped := pipeline_load_edges(resolve_pipeline(Transpile_Plugin.[]), "#load \"sub\\\\x.jai\";\n", "src/foo.jai");
    expect(escaped.count == 1 && escaped[0] == "src/sub/x.jai");
}

test "Load: line fidelity holds across the matrix" {
    targets := Load_Target.[.{from = "src/h.jai", to = "v"}, .{from = "src/multi.jai", to = "v"}];
    inputs := string.[
        "#load \"h.jai\";\ntest \"a\" { }\n",
        "#load\n\"multi.jai\";\n",
        "    #load \"h.jai\";\n",
    ];
    for input: inputs {
        expand := transpile_source(input, expand_ctx());
        strip := transpile_source(input, strip_ctx(targets));
        expect(expand.diagnostics.count == 0 && strip.diagnostics.count == 0);
        expect(count_lines(expand.view) == count_lines(input));
        expect(count_lines(strip.view) == count_lines(input));
    }
}

test "Load: CRLF source normalizes in the view" {
    result := transpile_source("#load \"h.jai\";\r\n", expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.view == "// juice: load stripped: #load \"h.jai\";\n");
}
