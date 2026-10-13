#import "Basic";
#import "File";
#import "Process";
#import "String";
#import "Testing";

// Fixture paths derive from juice_root() (defined in test_commands.jai): the
// test program executes at compile time, where the working directory is the
// entry file's directory (target/transpile).

// ---------------------------------------------------------------------------
// Tests for the Testing assertion module (modules/Testing.jai, ticket 0017).
// The in-process tests drive the module directly (abort semantics, counts,
// reset); the child scenarios run the real juice.exe `test` command on the
// fixture packages under tests/data/testing-child/ and capture stdout to
// verify the exact printed format: `[test] <name>` start lines,
// `path:line,col: message` failure lines, and the `N passed, M failed`
// summary. A failing package exits non-zero, which the parent verifies.
//
// Jai has no closures, so test bodies passed to run() touch globals instead
// of capturing locals (same visibility model as transpiled test blocks,
// which are top-level procedures).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// In-process tests over the module state
// ---------------------------------------------------------------------------

g_reached := false;
g_first_reached := false;
g_second_reached := false;
g_defer_ran := false;

// The tests below drive Testing's run()/finish() directly, which resets the
// global register. Each test drains leftover failures at its start into the
// accumulator so the final latch test can still fail the suite — otherwise a
// failure registered before a finish() call would be silently masked (in the
// old per-executable harness each process was isolated). The scenario's own
// counts are checked directly by the assertions instead.
testing_module_failures: s64 = 0;

test "expect and expect_eq pass and continue" {
    testing_module_failures += finish();
    g_reached = false;
    run("t-expect-pass", () -> () {
        expect(1 + 1 == 2);
        expect_eq("abc", "abc");
        expect_eq(2.5, 2.5);
        g_reached = true;
    });
    n := finish();
    expect(g_reached && n == 0);
}

test "failure aborts the current test, the suite continues" {
    testing_module_failures += finish();
    g_first_reached = false;
    g_second_reached = false;
    run("t-abort", () -> () {
        expect(3 > 4);
        g_first_reached = true;
    });
    run("t-next", () -> () {
        g_second_reached = true;
    });
    n := finish();
    expect(!g_first_reached && g_second_reached && n == 1);
}

test "fail always registers and aborts" {
    testing_module_failures += finish();
    g_reached = false;
    run("t-fail", () -> () {
        fail("always");
        g_reached = true;
    });
    n := finish();
    expect(!g_reached && n == 1);
}

test "defer runs when an assertion aborts the test" {
    testing_module_failures += finish();
    g_defer_ran = false;
    run("t-defer", () -> () {
        defer g_defer_ran = true;
        expect(1 == 2);
    });
    n := finish();
    expect(g_defer_ran);
}

test "bare return ends the test as passed" {
    testing_module_failures += finish();
    run("t-early", () -> () {
        x := 1;
        if x == 1 return;
        expect(false, "unreachable");
    });
    n := finish();
    expect(n == 0);
}

test "finish returns the failure count and resets state" {
    testing_module_failures += finish();
    run("t-failing", () -> () { expect(false, "will-fail"); });
    n := finish();
    expect(n == 1);
    run("t-passing", () -> () { expect(true); });
    n = finish();
    expect(n == 0);
}

// ---------------------------------------------------------------------------
// Child scenarios (juice test on the testing-child fixture packages, stdout
// captured by the parent)
// ---------------------------------------------------------------------------

testing_juice_exe :: () -> string {
    return tprint("%1/target/juice.exe", juice_root());
}

testing_child_run :: (scenario: string) -> Process_Result, string, string {
    juice := testing_juice_exe();
    fixture_abs := tprint("%1/tests/data/testing-child/%2", juice_root(), scenario);
    result, output, errors, _ := run_command(juice, "test", working_directory = fixture_abs, capture_and_return_output = true);
    return result, output, errors;
}

testing_expect_exit :: (name: string, result: Process_Result, want: s32) -> bool {
    if result.type == .EXITED && result.exit_code == want return true;
    print("[child %1] exit result %2/%3, want %4\n", name, result.type, result.exit_code, want);
    return false;
}

// Normalize CRLF to LF so expected blocks compare regardless of the child
// process's native line endings.
testing_normalize_crlf :: (s: string) -> string {
    has_cr := false;
    for ch: s {
        if ch == #char "\r" {
            has_cr = true;
            break;
        }
    }
    if !has_cr return s;
    builder: String_Builder;
    cursor := 0;
    i := 0;
    while i < s.count {
        if s[i] == #char "\r" {
            print_to_builder(*builder, "%", slice(s, cursor, i - cursor));
            print_to_builder(*builder, "\n");
            if i + 1 < s.count && s[i+1] == #char "\n" i += 1;
            cursor = i + 1;
        }
        i += 1;
    }
    if cursor < s.count print_to_builder(*builder, "%", slice(s, cursor, s.count - cursor));
    return builder_to_string(*builder);
}

testing_output_matches :: (name: string, output: string, needles: [] string, want := true) -> bool {
    normalized := testing_normalize_crlf(output);
    for needle: needles {
        found := find_index_from_left(normalized, needle) >= 0;
        if found != want {
            print("[child %1] output %2 '%3'\n", name, ifx found then "unexpectedly contains" else "missing", needle);
            print("  output was:\n%\n", output);
            return false;
        }
    }
    return true;
}

// 1-based line and character column of the first occurrence of `needle` in
// `file`; 0,0 if the source cannot be read or the needle is missing. Used to
// build the expected failure lines without hardcoding line numbers.
testing_line_col :: (file: string, needle: string) -> (line: s64, col: s64) {
    source, ok := read_entire_file(file);
    if !ok return 0, 0;
    index := find_index_from_left(source, needle);
    if index < 0 return 0, 0;
    line := 1;
    line_start := 0;
    for i: 0..index-1 {
        if source[i] == #char "\n" {
            line += 1;
            line_start = i + 1;
        }
    }
    return line, index - line_start + 1;
}

test "child: pass scenario output and exit code" {
    result, output, _ := testing_child_run("pass");
    expect(testing_expect_exit("pass", result, 0));

    // The anonymous test reports as src/scenarios.jai:<line of its `test`
    // token> (generated by the transpiler, issues/0004).
    anon_line, _ := testing_line_col(tprint("%1/tests/data/testing-child/pass/src/scenarios.jai", juice_root()), "test {");
    expect(anon_line != 0);
    expected := tprint("[test] addition\n[test] equality\n[test] src/scenarios.jai:%1\n3 passed, 0 failed\n", anon_line);
    expect(testing_output_matches("pass", output, string.[expected]));
}

test "child: fail scenario output and exit code" {
    result, output, _ := testing_child_run("fail");
    expect(testing_expect_exit("fail", result, 1));

    path := "src/scenarios.jai";
    fixture_file := tprint("%1/tests/data/testing-child/fail/src/scenarios.jai", juice_root());
    l1, c1 := testing_line_col(fixture_file, "expect(false);");
    l2, c2 := testing_line_col(fixture_file, "expect_eq(3, 5);");
    l3, c3 := testing_line_col(fixture_file, "fail(\"boom\")");
    l4, c4 := testing_line_col(fixture_file, "expect(false, \"got % and %\", 7, 9)");
    l5, c5 := testing_line_col(fixture_file, "expect_eq(3, 5, \"custom mismatch\")");
    expect(l1 != 0 && l2 != 0 && l3 != 0 && l4 != 0 && l5 != 0);
    expected := tprint(
        "[test] aborts\n%1:%2:%3: expect failed\n[test] eq-fails\n%1:%4:%5: expect_eq failed: expected 3, got 5\n[test] named-failure\n%1:%6:%7: boom\n[test] prints-message\n%1:%8:%9: got 7 and 9\n[test] custom-eq\n%1:%10:%11: custom mismatch\n0 passed, 5 failed\n",
        path, l1, c1, l2, c2, l3, c3, l4, c4, l5, c5);
    expect(testing_output_matches("fail", output, string.[expected]));
    // The aborted test's body never continued past the failing assertion.
    expect(testing_output_matches("fail", output, string.["reached"], want = false));
}

test "child: mapped scenario rewrites the failure path" {
    result, output, _ := testing_child_run("mapped");
    expect(testing_expect_exit("mapped", result, 1));

    l, c := testing_line_col(tprint("%1/tests/data/testing-child/mapped/src/scenarios.jai", juice_root()), "expect(2 + 2 == 5)");
    expect(l != 0);
    // The failure line reports the original package-relative coordinates:
    // the driver-injected mapping table rewrote the view path.
    expect(testing_output_matches("mapped", output, string.[tprint("[test] mapped-fail\nsrc/scenarios.jai:%1:%2: expect failed\n0 passed, 1 failed\n", l, c)]));
    expect(testing_output_matches("mapped", output, string.["target/transpile"], want = false));
}

// Latch for the suite-level failure gate: the in-process tests above drain
// the global register via finish() (Testing module semantics), so any
// failure they drained — or left by an earlier test — is re-checked here
// and trips the driver's finish()/assert gate instead of being masked.
test "Testing module register stays clean between tests" {
    expect(testing_module_failures == 0);
}
