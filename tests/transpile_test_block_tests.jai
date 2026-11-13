// ---------------------------------------------------------------------------
// Built-in test-block plugin tests (ticket 023): the default pipeline's
// second member — the EXPAND rewrite (`juice_test_N` procedure + @test note
// + Test_Entry bookkeeping), the STRIP placeholder (the whole block;
// interior tokens never dispatched), the has_anchor probe feeding the
// closure-viewing decision, the anchor machinery (find_matching_close /
// is_test_anchor) and the diagnostics. The default pipeline now resolves an
// empty registration to both built-ins (#load first, test-block second).
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

// ===========================================================================
// Helpers
// ===========================================================================

// An EXPAND-mode context with an empty registration (the runner resolves it
// to the default pipeline = both built-ins) and the given file-start test
// number.
tblock_expand_ctx :: (next: s64 = 1) -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = .EXPAND;
    ctx.path = "src/foo.jai";
    ctx.next_test_number = next;
    return ctx;
}

// A STRIP-mode context with an empty registration and the given #load
// rewrite table.
tblock_strip_ctx :: (targets: [] Load_Target) -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = "src/foo.jai";
    ctx.load_targets = targets;
    return ctx;
}

tblock_lines :: (s: string) -> s64 {
    n := 1;
    for ch: s if ch == #char "\n" n += 1;
    return n;
}

// ===========================================================================
// EXPAND: the header rewrite, the @test note and the Test_Entry manifest
// ===========================================================================

test "Test block EXPAND: named header, entry and @test note" {
    result := transpile_source("test \"addition\" {\n    expect(2, 2);\n}\n", tblock_expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.tests.count == 1);
    expect(result.tests[0].name == "addition" && result.tests[0].number == 1 && result.tests[0].line == 1);
    expect(result.view == "juice_test_1 :: () -> () {\n    expect(2, 2);\n} @test\n");
}

test "Test block EXPAND: anonymous test name is path:line" {
    result := transpile_source("test {\n}\n", tblock_expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.tests.count == 1);
    expect(result.tests[0].name == "src/foo.jai:1" && result.tests[0].number == 1);
    expect(result.view == "juice_test_1 :: () -> () {\n} @test\n");
}

test "Test block EXPAND: @test sits before trailing comments" {
    result := transpile_source("test \"x\" {\n} // c\n", tblock_expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.view == "juice_test_1 :: () -> () {\n} @test // c\n");
}

test "Test block EXPAND: numbering continues across tests" {
    result := transpile_source("test \"a\" { }\ntest \"b\" { }\n", tblock_expand_ctx(next = 7));
    expect(result.diagnostics.count == 0);
    expect(result.tests.count == 2);
    expect(result.tests[0].number == 7 && result.tests[1].number == 8);
    expect(result.view == "juice_test_7 :: () -> () { } @test\njuice_test_8 :: () -> () { } @test\n");
}

test "Test block EXPAND: one-line blocks and chained blocks" {
    source := "test \"fast\" { assert(true); }\n\ntest \"a\" { } test \"b\" { }\n";
    result := transpile_source(source, tblock_expand_ctx());
    expect(result.diagnostics.count == 0 && result.tests.count == 3);
    expected := "juice_test_1 :: () -> () { assert(true); } @test\n\njuice_test_2 :: () -> () { } @test juice_test_3 :: () -> () { } @test\n";
    expect(result.view == expected);
}

test "Test block EXPAND: #load inside the body is stripped" {
    // The claim enters the body without consuming it: the later #load
    // plugin still reaches the load statement inside the block.
    result := transpile_source("test \"a\" {\n    #load \"helper.jai\";\n}\n", tblock_expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.view == "juice_test_1 :: () -> () {\n    // juice: load stripped: #load \"helper.jai\";\n} @test\n");
}

test "Test block EXPAND: immunity to strings, comments and calls" {
    source := "test :: () -> void { print(\"not a test\\n\"); }\n";
    source = tprint("%1%2", source, "x := \"test \\\"fake\\\" { }\";\n// test \"commented\" { }\n/* test \"blocked\" { } */\n");
    source = tprint("%1%2", source, "if ready test { work(); }\ntest(x);\ny := test;\n");
    result := transpile_source(source, tblock_expand_ctx());
    expect(result.diagnostics.count == 0 && result.tests.count == 0);
    expect(result.view == source);
}

test "Test block EXPAND: brace matching skips strings and comments" {
    source := "test \"braces\" {\n    s := \"{ } not braces\"; // } { \n    /* { } */\n}\n";
    result := transpile_source(source, tblock_expand_ctx());
    expect(result.diagnostics.count == 0);
    expected := "juice_test_1 :: () -> () {\n    s := \"{ } not braces\"; // } { \n    /* { } */\n} @test\n";
    expect(result.view == expected);
}

test "Test block EXPAND: named entry reuses the decoded token" {
    result := transpile_source("test \"a\\tb\" { }\n", tblock_expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.tests.count == 1);
    expect(result.tests[0].name == "a\tb");
}

// ===========================================================================
// STRIP: the whole-block placeholder; interior tokens never dispatched
// ===========================================================================

test "Test block STRIP: block becomes comment placeholder" {
    source := "test \"addition\" {\n    expect(2, 2);\n}\n";
    result := transpile_source(source, tblock_strip_ctx(Load_Target.[]));
    expect(result.diagnostics.count == 0);
    expect(result.tests.count == 0);
    expected := "// juice: test stripped: test \"addition\" {\n    // juice: test stripped\n// juice: test stripped\n";
    expect(result.view == expected);
}

test "Test block STRIP: one-line block keeps the original text" {
    result := transpile_source("test \"one\" { body(); }\n", tblock_strip_ctx(Load_Target.[]));
    expect(result.diagnostics.count == 0);
    expect(result.view == "// juice: test stripped: test \"one\" { body(); }\n");
}

test "Test block STRIP: chained blocks share the line" {
    result := transpile_source("test \"a\" { } test \"b\" { }\n", tblock_strip_ctx(Load_Target.[]));
    expect(result.diagnostics.count == 0);
    expect(result.view == "// juice: test stripped: test \"a\" { } // juice: test stripped: test \"b\" { }\n");
}

test "Test block STRIP: placeholder keeps indentation" {
    source := "    test \"x\" {\n        body();\n    }\n";
    result := transpile_source(source, tblock_strip_ctx(Load_Target.[]));
    expect(result.diagnostics.count == 0);
    expected := "    // juice: test stripped: test \"x\" {\n        // juice: test stripped\n    // juice: test stripped\n";
    expect(result.view == expected);
}

test "Test block STRIP: loads inside the block vanish" {
    // The claim consumes the block through its closing brace: the #load
    // inside the placeholder is never dispatched (no view-target diagnostic,
    // no rewrite).
    source := "test \"a\" {\n    #load \"helper.jai\";\n}\n";
    result := transpile_source(source, tblock_strip_ctx(Load_Target.[]));
    expect(result.diagnostics.count == 0);
    expected := "// juice: test stripped: test \"a\" {\n    // juice: test stripped\n// juice: test stripped\n";
    expect(result.view == expected);
}

// ===========================================================================
// Diagnostics
// ===========================================================================

test "Test block diagnostics: nested block is rejected" {
    source := "foo :: () {\n    test \"inner\" { }\n}\n";
    result := transpile_source(source, tblock_expand_ctx());
    expect(result.diagnostics.count == 1);
    d := result.diagnostics[0];
    expect(d.line == 2 && d.column == 5);
    expect(d.message == "test block 仅允许文件顶层");
    expect(result.view == source);
}

test "Test block diagnostics: multi-line head is rejected" {
    named := transpile_source("test\n    \"name\" {\n}\n", tblock_expand_ctx());
    anonymous := transpile_source("test\n{\n}\n", tblock_expand_ctx());
    expect(named.diagnostics.count == 1 && anonymous.diagnostics.count == 1);
    expect(named.diagnostics[0].line == 1 && named.diagnostics[0].column == 1);
    expect(named.diagnostics[0].message == "test 头必须位于同一行");
    expect(anonymous.diagnostics[0].message == "test 头必须位于同一行");
}

test "Test block diagnostics: statement after a stripped close" {
    source := "test \"x\" { body(); } after();\n";
    result := transpile_source(source, tblock_strip_ctx(Load_Target.[]));
    expect(result.diagnostics.count == 1);
    d := result.diagnostics[0];
    expect(d.line == 1 && d.column == 22 && d.message == "test block 闭括号后不得有其他语句");
    expect(result.view == source);
}

test "Test block diagnostics: unterminated block stops the scan" {
    result := transpile_source("test \"forever\" {\n    expect(1, 1);\n", tblock_expand_ctx());
    expect(result.diagnostics.count == 1);
    expect(result.diagnostics[0].line == 1 && result.diagnostics[0].column == 1);
    expect(result.diagnostics[0].message == "test block 缺少闭合 }");
    expect(result.view == "test \"forever\" {\n    expect(1, 1);\n");
    // Nothing after the unterminated block is processed: the #load is never
    // dispatched, so no placeholder edit and no view-target diagnostic.
    stripped := transpile_source("test \"x\" {\n#load \"h.jai\";\n", tblock_strip_ctx(Load_Target.[]));
    expect(stripped.diagnostics.count == 1);
    expect(stripped.diagnostics[0].message == "test block 缺少闭合 }");
    expect(stripped.view == "test \"x\" {\n#load \"h.jai\";\n");
}

// ===========================================================================
// Line fidelity, line endings, the probe and the numbering channel
// ===========================================================================

test "Test block: line fidelity holds across the matrix" {
    inputs := string.[
        "test \"a\" {\n    body();\n}\n",
        "test \"x\" { body(); }\n\ntest \"y\" {\n}\n",
        "#load \"h.jai\";\ntest \"a\" { }\n",
        "test \"l\" {\n    #load \"h.jai\";\n}\n",
    ];
    targets := Load_Target.[.{from = "src/h.jai", to = "v"}];
    for input: inputs {
        expand := transpile_source(input, tblock_expand_ctx());
        strip := transpile_source(input, tblock_strip_ctx(targets));
        expect(expand.diagnostics.count == 0 && strip.diagnostics.count == 0);
        expect(tblock_lines(expand.view) == tblock_lines(input));
        expect(tblock_lines(strip.view) == tblock_lines(input));
    }
}

test "Test block: CRLF source normalizes in the view" {
    result := transpile_source("test \"x\" {\r\n}\r\n", tblock_expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.view == "juice_test_1 :: () -> () {\n} @test\n");
}

test "Test block: has_anchor feeds the closure decision" {
    // The default pipeline (both built-ins) reports an anchor for a
    // top-level statement-position test block...
    pipeline := resolve_pipeline(Transpile_Plugin.[]);
    expect(pipeline_has_anchors(pipeline, "test \"a\" { }\n", "src/a.jai"));
    expect(pipeline_has_anchors(pipeline, "test { }\n", "src/a.jai"));
    // ...and for a nested one (the transpile hook rejects it with a
    // diagnostic, so the closure still needs viewing).
    expect(pipeline_has_anchors(pipeline, "foo :: () {\n    test \"a\" { }\n}\n", "src/a.jai"));
    // Non-statement anchors and test-free sources do not count.
    expect(!pipeline_has_anchors(pipeline, "if test { work(); }\n", "src/a.jai"));
    expect(!pipeline_has_anchors(pipeline, "x := 1;\n", "src/a.jai"));
    // The #load plugin alone has no anchor of its own.
    load_only: [..] Transpile_Plugin;
    array_add(*load_only, load_plugin());
    expect(!pipeline_has_anchors(load_only, "test \"a\" { }\n", "src/a.jai"));
}

test "Test block: numbering continues across files via next_test_number" {
    // The caller's channel: next_test_number seeds each file's first test,
    // and the caller advances it between files (global numbering, base 1).
    ctx := tblock_expand_ctx();
    first := transpile_source("test \"a\" { }\ntest \"b\" { }\n", ctx);
    expect(first.tests.count == 2);
    expect(first.tests[0].number == 1 && first.tests[1].number == 2);

    ctx.next_test_number = 3;
    ctx.path = "src/bar.jai";
    second := transpile_source("test \"c\" { }\n", ctx);
    expect(second.tests.count == 1);
    expect(second.tests[0].number == 3 && second.tests[0].line == 1);
}

test "Anchor machinery: matching close and anchor shapes" {
    source := "test \"braces\" {\n    s := \"{ } not braces\"; // } { \n    /* { } */\n}\n";
    tokens := lex_source(source);
    expect(is_test_anchor(source, tokens, 0));
    // The lexer consumed strings and comments: the matching-close scan sees
    // only real braces.
    close_index, closed := find_matching_close(source, tokens, 2);
    expect(closed);
    expect(token_text(source, tokens[close_index]) == "}");
    // Shape matrix: named and anonymous anchors; a bare `test` in `if test
    // {` has the anchor shape (the statement-position gate rejects it at the
    // hook level); `test(x)` does not.
    s2 := "test \"a\" { } test { } if test { } test(x);\n";
    tokens2 := lex_source(s2);
    expect(is_test_anchor(s2, tokens2, 0));
    expect(is_test_anchor(s2, tokens2, 4));
    expect(is_test_anchor(s2, tokens2, 8));
    expect(!is_test_anchor(s2, tokens2, 11));
    // Unterminated block: no matching close.
    _, closed2 := find_matching_close("test \"x\" {", lex_source("test \"x\" {"), 2);
    expect(!closed2);
}

// ===========================================================================
// Statement position after directives (ticket 030)
// ===========================================================================

test "Test block after a bare directive is claimed in STRIP and EXPAND" {
    // A directive occupies a whole statement: the token after it is a
    // statement start, so a test block right after a bare directive (the
    // published Testing module shape, src/module.jai's self-test segment
    // neighbor) must be claimed — the directive text itself must not block
    // the statement-position gate.
    source := "#scope_export\n\ntest \"after-directive\" {\n    x := 1;\n}\n";
    expect(test_block_has_anchor(source, "src/foo.jai"));

    stripped := transpile_source(source, tblock_strip_ctx(Load_Target.[]));
    expect(stripped.diagnostics.count == 0);
    expect(stripped.view == "#scope_export\n\n// juice: test stripped: test \"after-directive\" {\n    // juice: test stripped\n// juice: test stripped\n");

    expanded := transpile_source(source, tblock_expand_ctx());
    expect(expanded.diagnostics.count == 0);
    expect(expanded.tests.count == 1);
    expect(expanded.tests[0].name == "after-directive" && expanded.tests[0].number == 1);
    expect(expanded.view == "#scope_export\n\njuice_test_1 :: () -> () {\n    x := 1;\n} @test\n");
}
