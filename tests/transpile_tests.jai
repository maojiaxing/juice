// ---------------------------------------------------------------------------
// Transpiler tests (45 blocks, migrated from the old tests/; back in tests/
// per the 2026-10-14 test organization rule).
//
// Key constraint (a known-risk landing): src/transpile.jai and
// src/transpile_cache.jai are build.jai's #load targets / entry closure
// members — test blocks would be illegal inside a metaprogram compile-time
// text inclusion, so those two files must stay test-free. The transpiler
// test blocks therefore cannot be inlined and live in tests/ (this file)
// per the test organization rule: referenced by no #load (outside the entry
// closure, outside the release product), collected into the test program by
// Test discovery's full-package scan (same mechanism as
// tests/test_support.jai). This file contains only test blocks; zero
// production code coupling.
// ---------------------------------------------------------------------------

// Shared declarations (the GOLDEN_CASES/NEGATIVE_CASES constants, the
// golden/negative harness, the expand_ctx/strip_ctx and other helpers, and
// the compile-and-run matrix helpers) live in tests/test_support.jai,
// program-level shared in the test program.

#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// Unit tests over the pure function
// ---------------------------------------------------------------------------

test "Expand: named test header and entry" {
    result := transpile_source("test \"addition\" {\n    expect(2, 2);\n}\n", expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.tests.count == 1);
    expect(result.tests[0].name == "addition" && result.tests[0].number == 1 && result.tests[0].line == 1);
    expect(result.view == "juice_test_1 :: () -> () {\n    expect(2, 2);\n} @test\n");
}

test "Expand: anonymous test name is path:line" {
    result := transpile_source("test {\n}\n", expand_ctx());
    expect(result.tests.count == 1);
    expect(result.tests[0].name == "src/foo.jai:1");
    expect(result.view == "juice_test_1 :: () -> () {\n} @test\n");
}

test "Expand: @test sits before trailing comments" {
    result := transpile_source("test \"x\" {\n} // c\n", expand_ctx());
    expect(result.view == "juice_test_1 :: () -> () {\n} @test // c\n");
}

test "Expand: numbering continues across tests" {
    result := transpile_source("test \"a\" { }\ntest \"b\" { }\n", expand_ctx(next = 7));
    expect(result.tests.count == 2);
    expect(result.tests[0].number == 7 && result.tests[1].number == 8);
    expect(result.view == "juice_test_7 :: () -> () { } @test\njuice_test_8 :: () -> () { } @test\n");
}

test "Expand: in-package #load stripped" {
    result := transpile_source("#load \"helper.jai\";\n", expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.view == "// juice: load stripped: #load \"helper.jai\";\n");
}

test "Expand: multi-line #load gets (cont) placeholder" {
    result := transpile_source("#load\n\"multi.jai\";\n", expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.view == "// juice: load stripped: #load\n// juice: load stripped (cont)\n");
}

test "Expand: stripped #load keeps indentation" {
    result := transpile_source("    #load \"helper.jai\";\n", expand_ctx());
    expect(result.view == "    // juice: load stripped: #load \"helper.jai\";\n");
}

test "Expand: #load inside a test body is stripped" {
    result := transpile_source("test \"a\" {\n    #load \"helper.jai\";\n}\n", expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.view == "juice_test_1 :: () -> () {\n    // juice: load stripped: #load \"helper.jai\";\n} @test\n");
}

test "Expand: out-of-package and non-literal #load verbatim" {
    source := "#load \"../../outside.jai\";\n#load CONST_NAME;\n#load \"other\" + \".jai\";\n#import \"Basic\";\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.view == source);
}

test "Expand: test-free file is identical" {
    source := "#import \"Basic\";\n\nmain :: () {\n    print(\"hello\\n\");\n}\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 0 && result.tests.count == 0);
    expect(result.view == source);
}

test "Expand: one-line blocks and one-line multi tests" {
    source := "test \"fast\" { assert(true); }\n\ntest \"a\" { } test \"b\" { }\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 0 && result.tests.count == 3);
    expected := "juice_test_1 :: () -> () { assert(true); } @test\n\njuice_test_2 :: () -> () { } @test juice_test_3 :: () -> () { } @test\n";
    expect(result.view == expected);
}

test "Immunity: test in strings, comments and calls" {
    source := "test :: () -> void { print(\"not a test\\n\"); }\n";
    source = tprint("%1%2", source, "x := \"test \\\"fake\\\" { }\";\n// test \"commented\" { }\n/* test \"blocked\" { } */\n");
    source = tprint("%1%2", source, "if ready test { work(); }\ntest(x);\ny := test;\n");
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 0 && result.tests.count == 0);
    expect(result.view == source);
}

test "Immunity: brace matching skips strings and comments" {
    source := "test \"braces\" {\n    s := \"{ } not braces\"; // } { \n    /* { } */\n}\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 0);
    expected := "juice_test_1 :: () -> () {\n    s := \"{ } not braces\"; // } { \n    /* { } */\n} @test\n";
    expect(result.view == expected);
}

test "Strip: test block becomes comment placeholder" {
    source := "test \"addition\" {\n    expect(2, 2);\n}\n";
    result := transpile_source(source, strip_ctx(targets = Load_Target.[]));
    expect(result.diagnostics.count == 0);
    expected := "// juice: test stripped: test \"addition\" {\n    // juice: test stripped\n// juice: test stripped\n";
    expect(result.view == expected);
}

test "Strip: one-line block keeps original text" {
    source := "test \"one\" { body(); }\n";
    result := transpile_source(source, strip_ctx(targets = Load_Target.[]));
    expected := "// juice: test stripped: test \"one\" { body(); }\n";
    expect(result.view == expected);
}

test "Strip: one-line multiple blocks share the line" {
    source := "test \"a\" { } test \"b\" { }\n";
    result := transpile_source(source, strip_ctx(targets = Load_Target.[]));
    expect(result.diagnostics.count == 0);
    expected := "// juice: test stripped: test \"a\" { } // juice: test stripped: test \"b\" { }\n";
    expect(result.view == expected);
}

test "Strip: placeholder keeps indentation" {
    source := "    test \"x\" {\n        body();\n    }\n";
    result := transpile_source(source, strip_ctx(targets = Load_Target.[]));
    expected := "    // juice: test stripped: test \"x\" {\n        // juice: test stripped\n    // juice: test stripped\n";
    expect(result.view == expected);
}

test "Strip: loads inside a stripped block vanish" {
    source := "test \"a\" {\n    #load \"helper.jai\";\n}\n";
    result := transpile_source(source, strip_ctx(targets = Load_Target.[]));
    expect(result.diagnostics.count == 0);
    expected := "// juice: test stripped: test \"a\" {\n    // juice: test stripped\n// juice: test stripped\n";
    expect(result.view == expected);
}

test "Strip: in-package #load rewritten to view path" {
    targets := Load_Target.[.{from = "src/helper.jai", to = "C:/pkg/target/transpile/hash1/src/helper.jai"}];
    result := transpile_source("#load \"helper.jai\";\n", strip_ctx(targets = targets));
    expect(result.diagnostics.count == 0);
    expect(result.view == "#load \"C:/pkg/target/transpile/hash1/src/helper.jai\";\n");
}

test "Strip: rewritten path is escaped" {
    targets := Load_Target.[.{from = "src/h.jai", to = "C:\\Users\\a\"b.jai"}];
    result := transpile_source("#load \"h.jai\";\n", strip_ctx(targets = targets));
    expect(result.view == "#load \"C:\\\\Users\\\\a\\\"b.jai\";\n");
}

test "Strip: test-free file is identical" {
    source := "#import \"Basic\";\n\nmain :: () {}\n";
    result := transpile_source(source, strip_ctx(targets = Load_Target.[]));
    expect(result.view == source);
}

test "Diagnostic: test inside a procedure body" {
    source := "foo :: () {\n    test \"inner\" { }\n}\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 1);
    d := result.diagnostics[0];
    expect(d.line == 2 && d.column == 5);
    expect(d.message == "test block 仅允许文件顶层");
    expect(result.view == source);
}

test "Diagnostic: test inside a struct body" {
    source := "Data :: struct {\n    x: int;\n    test { }\n}\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 1);
    d := result.diagnostics[0];
    expect(d.line == 3 && d.column == 5 && d.message == "test block 仅允许文件顶层");
}

test "Diagnostic: multi-line test head" {
    named := transpile_source("test\n    \"name\" {\n}\n", expand_ctx());
    anonymous := transpile_source("test\n{\n}\n", expand_ctx());
    expect(named.diagnostics.count == 1 && anonymous.diagnostics.count == 1);
    expect(named.diagnostics[0].line == 1 && named.diagnostics[0].column == 1);
    expect(named.diagnostics[0].message == "test 头必须位于同一行");
    expect(anonymous.diagnostics[0].message == "test 头必须位于同一行");
}

test "Diagnostic: #load sharing a line" {
    before := transpile_source("x := 1; #load \"a.jai\";\n", expand_ctx());
    after := transpile_source("#load \"a.jai\"; x := 1;\n", expand_ctx());
    expect(before.diagnostics.count == 1 && after.diagnostics.count == 1);
    expect(before.diagnostics[0].line == 1 && before.diagnostics[0].column == 9);
    expect(before.diagnostics[0].message == "#load 必须独占其行");
    expect(after.diagnostics[0].column == 1);
}

test "Diagnostic: statement after a stripped }" {
    source := "test \"x\" { body(); } after();\n";
    result := transpile_source(source, strip_ctx(targets = Load_Target.[]));
    expect(result.diagnostics.count == 1);
    d := result.diagnostics[0];
    expect(d.line == 1 && d.column == 22 && d.message == "test block 闭括号后不得有其他语句");
}

test "Diagnostic: unterminated test block" {
    source := "test \"forever\" {\n    expect(1, 1);\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 1);
    d := result.diagnostics[0];
    expect(d.line == 1 && d.column == 1 && d.message == "test block 缺少闭合 }");
}

test "Diagnostic: missing view target in strip mode" {
    result := transpile_source("#load \"helper.jai\";\n", strip_ctx(targets = Load_Target.[]));
    expect(result.diagnostics.count == 1);
    expect(result.diagnostics[0].message == "in-package #load 缺少视图目标");
}

test "Line fidelity: view line counts match the source" {
    inputs := string.[
        "test \"a\" {\n    body();\n}\n",
        "test \"x\" { body(); }\n\ntest \"y\" {\n}\n",
        "#load \"h.jai\";\ntest \"a\" { }\n",
    ];
    for input: inputs {
        expand := transpile_source(input, expand_ctx());
        strip := transpile_source(input, strip_ctx(targets = Load_Target.[.{from = "src/h.jai", to = "v"}]));
        expect(expand.diagnostics.count == 0 && strip.diagnostics.count == 0);
        expect(count_lines(expand.view) == count_lines(input));
        expect(count_lines(strip.view) == count_lines(input));
    }
}

test "Line endings: CRLF normalized to LF" {
    result := transpile_source("test \"x\" {\r\n}\r\n", expand_ctx());
    expect(result.view == "juice_test_1 :: () -> () {\n} @test\n");
}

test "Named test reuses the decoded source token" {
    result := transpile_source("test \"a\\tb\" { }\n", expand_ctx());
    expect(result.tests.count == 1);
    expect(result.tests[0].name == "a\tb");
}

test "if test {} is not an anchor" {
    source := "if test { work(); }\n";
    result := transpile_source(source, expand_ctx());
    expect(result.view == source && result.tests.count == 0);
}

test "String decode keeps unknown escapes" {
    expect(decode_jai_string("C:\\Users") == "C:\\Users");
}

test "String decode and quote roundtrip" {
    decoded := decode_jai_string("a\\nb\\\"c\\\\d");
    expect(decoded == "a\nb\"c\\d");
    expect(quote_jai_string(decoded) == "\"a\\nb\\\"c\\\\d\"");
}

test "String escaping" {
    expect(escape_jai_string("C:\\a\"b") == "C:\\\\a\\\"b");
}

test "Load target resolution" {
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

// ---------------------------------------------------------------------------
// Content-addressed cache pure functions
// ---------------------------------------------------------------------------

// The key is a deterministic 16-hex-char hash; every component (relative
// path, source content, mode, version, pipeline description) participates
// in it.
test "Cache key is deterministic and component-sensitive" {
    key := transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION);
    expect(key == transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION));
    expect(key.count == 16);
    for ch: key {
        expect(is_hex_digit(ch));
    }
    expect(key != transpile_view_key("src/b.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION));
    expect(key != transpile_view_key("src/a.jai", "x := 2;\n", .EXPAND, Load_Target.[], JUICE_VERSION));
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .STRIP, Load_Target.[], JUICE_VERSION));
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], "1"));
    // A different pipeline description changes the key.
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION, .[test_block_plugin()]));
    // The omitted version defaults to the juice version constant; the
    // omitted (or empty) pipeline defaults to the default pipeline
    // description.
    expect(transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[]) == key);
    expect(transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION, default_transpile_pipeline()) == key);
    expect(transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION, Transpile_Plugin.[]) == key);
}

// Merkle chain: in build mode the load rewrite
// targets embed the target views' hash directories, so a parent's key changes
// whenever a loaded view's key changes — and stays deterministically
// computable in dependency order.
test "Cache key forms a Merkle chain in build mode" {
    child := transpile_view_key("src/b.jai", "b := 1;\n", .STRIP, Load_Target.[], "1");
    child_other := transpile_view_key("src/b.jai", "b := 2;\n", .STRIP, Load_Target.[], "1");

    targets: [..] Load_Target;
    array_add(*targets, .{from = "src/b.jai", to = tprint("C:/pkg/target/transpile/%1/src/b.jai", child)});
    parent := transpile_view_key("src/a.jai", "#load \"b.jai\";\n", .STRIP, targets, "1");

    // The rewrite table participates in the key...
    expect(parent != transpile_view_key("src/a.jai", "#load \"b.jai\";\n", .STRIP, Load_Target.[], "1"));
    // ...and carries the child key, so the parent key tracks the child.
    targets_other: [..] Load_Target;
    array_add(*targets_other, .{from = "src/b.jai", to = tprint("C:/pkg/target/transpile/%1/src/b.jai", child_other)});
    expect(parent != transpile_view_key("src/a.jai", "#load \"b.jai\";\n", .STRIP, targets_other, "1"));
    // From-side changes rewrite the same way and must change the key too.
    targets_from: [..] Load_Target;
    array_add(*targets_from, .{from = "src/c.jai", to = tprint("C:/pkg/target/transpile/%1/src/b.jai", child)});
    expect(parent != transpile_view_key("src/a.jai", "#load \"b.jai\";\n", .STRIP, targets_from, "1"));
}

// Collision-avoiding path shape: <transpile_dir>/<hash>/<rel>
// mirrors the package-relative structure inside the hash directory, so
// "src/a/x.jai" and "src/a_x.jai" stay distinct where a flattened layout
// would collide.
test "Cache view path mirrors the relative structure" {
    dir := "C:/pkg/target/transpile";
    expect(transpile_hash_dir(dir, "abcd1234") == "C:/pkg/target/transpile/abcd1234");
    expect(transpile_view_path(dir, "abcd1234", "src/a/x.jai") == "C:/pkg/target/transpile/abcd1234/src/a/x.jai");
    expect(transpile_view_path(dir, "abcd1234", "src/a_x.jai") != transpile_view_path(dir, "abcd1234", "src/a/x.jai"));
    // The rel path is mirrored, not flattened into the hash directory name.
    expect(transpile_view_path(dir, "abcd1234", "src/a/x.jai") != transpile_hash_dir(dir, "abcd1234_src_a_x.jai"));
    // Backslash inputs are normalized to forward slashes.
    expect(transpile_view_path("C:\\pkg\\target\\transpile", "abcd1234", "src/a.jai") == "C:/pkg/target/transpile/abcd1234/src/a.jai");
}

// ---------------------------------------------------------------------------
// Golden / negative harness (Case_Config, read_case_config,
// collect_case_files, golden_root, normalize_golden_abs, compare_or_update,
// case_context, run_golden_cases, run_negative_cases and wants_update live
// in tests/test_support.jai)
// ---------------------------------------------------------------------------

test "Golden baselines" {
    print("--- golden baselines ---\n");
    expect(run_golden_cases(wants_update()));
}

test "Negative cases" {
    print("--- negative cases ---\n");
    expect(run_negative_cases(wants_update()));
}

// ---------------------------------------------------------------------------
// Compile-and-run matrix (docs/transpiled-output-formatting.md §4.1):
// package-level fixtures under tests/data/transpile/run/, executed end to
// end via the real juice.exe `test` command; exit codes and the output
// contract are asserted (no full-output goldens). The run matrix helpers
// (juice_exe, run_juice_test, expect_exit, normalize_crlf, output_matches,
// fixture_line_col) live in tests/test_support.jai.
// ---------------------------------------------------------------------------

// LIB packages have no effective target; `juice test` still discovers and
// runs every test in the package.
test "Run: LIB package passes via juice test" {
    result, output, _ := run_juice_test("lib-package", fixture_base = "tests/data/transpile/run/");
    expect(expect_exit("lib", result, 0, "run"));
    expect(output_matches("lib", output, string.["[juice Test] Found 3 tests; compiling test program..."], tag = "run"));
    anon_line, _ := fixture_line_col(tprint("%1/tests/data/transpile/run/lib-package/module.jai", juice_root()), "test {");
    expect(anon_line != 0);
    expect(output_matches("lib", output, string.[
        tprint("[test] lib arithmetic\n[test] lib strings\n[test] module.jai:%1\n3 passed, 0 failed\n", anon_line),
    ], tag = "run"));
}

// Pattern filtering end to end: a hit runs exactly the matched tests, a
// zero-hit pattern succeeds with an explanation and skips the build.
test "Run: pattern hit filters the executed tests" {
    result, output, _ := run_juice_test("lib-package", "strings", fixture_base = "tests/data/transpile/run/");
    expect(expect_exit("pattern-hit", result, 0, "run"));
    expect(output_matches("pattern-hit", output, string.[
        "[juice Test] Found 1 tests; compiling test program...",
        "[test] lib strings\n1 passed, 0 failed\n",
    ], tag = "run"));
    expect(output_matches("pattern-hit", output, string.["[test] lib arithmetic"], want = false, tag = "run"));
}

test "Run: zero-hit pattern succeeds with an explanation" {
    result, output, _ := run_juice_test("lib-package", "zzz", fixture_base = "tests/data/transpile/run/");
    expect(expect_exit("pattern-zero", result, 0, "run"));
    expect(output_matches("pattern-zero", output, string.["[juice Test] No tests matched 'zzz'."], tag = "run"));
}

// Crash semantics: a bare assert inside a test crashes the
// compiler — non-zero exit, no clean per-test attribution line and no
// summary; the crash point stays attributable by the [test] start line, and
// the compiler's own assert noise surfaces on stderr.
test "Run: bare-assert crash is non-zero without clean attribution" {
    result, output, errors := run_juice_test("crash-package", fixture_base = "tests/data/transpile/run/");
    if result.type != .EXITED || result.exit_code == 0 {
        print("[run crash] exit result %1/%2, want non-zero\n", result.type, result.exit_code);
    }
    expect(result.type == .EXITED && result.exit_code != 0);
    expect(output_matches("crash", output, string.[
        "[test] crashy",
        "[juice ERROR] Test compilation failed.",
    ], tag = "run"));
    // No clean attribution: no mapped original-path failure line on stdout...
    expect(output_matches("crash", output, string.["src/main.jai:"], want = false, tag = "run"));
    // ...and no N passed / M failed summary.
    expect(output_matches("crash", output, string.[" passed, "], want = false, tag = "run"));
    expect(output_matches("crash", errors, string.["Assertion failed!"], tag = "run"));
}