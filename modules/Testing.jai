// Juice's first-party assertion module for test blocks. User test code
// imports it with `#import "Testing"`. Depends on Basic only; neutral toward
// the execution model (runtime runner / compile-time driver).
//
// Semantics:
// - A failing assertion registers the failure globally and aborts the current
//   test body immediately (a backticked `return in the macro is inserted into
//   the caller; Zig "try expect" semantics). The rest of the suite keeps
//   running, and defers in the test body fire normally.
// - Each failure is printed immediately as `path:line,col: message` (no
//   `Error:` prefix, so editors can jump to the location); each test start is
//   printed as `[test] <report name>`; finish() prints the summary
//   `N passed, M failed` and returns the failure count.
// - path_mapping is the driver-injected "view absolute path <-> original
//   package-relative path" rewrite table. Exact match rewrites the printed
//   path; the default empty array passes paths through untouched, keeping the
//   module independent of the driver.

#import "Basic";

#scope_export

// One rewrite pair: `view` is the absolute path of a view (the path
// #caller_location reports); `original` is the package-relative source path
// printed in its place.
Path_Pair :: struct {
    view:     string;
    original: string;
}

// Mutable global the driver fills in before running the test list.
// Default empty array = passthrough.
path_mapping : [..] Path_Pair;

#scope_file

// --- Internal registration state. Module-level globals are shared
// program-wide by every file that #imports the module. ---

current_test_name: string;
current_test_failed := false;
passed_count: s32 = 0;
failure_count: s32 = 0;

mapped_path :: (view: string) -> string {
    for pair: path_mapping {
        if pair.view == view return pair.original;
    }
    return view;
}

report_failure :: (loc: Source_Code_Location, message: string) {
    current_test_failed = true;
    failure_count += 1;
    print("%:%:%: %\n", mapped_path(loc.fully_pathed_filename), loc.line_number, loc.character_number, message);
}

#scope_export

// expect(cond) with an optional printf-style message, mirroring Basic.assert's
// shape.
expect :: (condition: bool, message := "", args: .. Any, loc := #caller_location) #expand {
    if !condition {
        if message == "" {
            report_failure(loc, "expect failed");
        } else {
            report_failure(loc, tprint(message, ..args));
        }
        `return;
    }
}

// expect_eq(expected, actual) with the $T same-type constraint checked at
// compile time; T must support != and print.
expect_eq :: (expected: $T, actual: T, message := "", loc := #caller_location) #expand {
    if expected != actual {
        if message == "" {
            report_failure(loc, tprint("expect_eq failed: expected %, got %", expected, actual));
        } else {
            report_failure(loc, tprint(message));
        }
        `return;
    }
}

// Unconditionally register a failure and abort the current test.
fail :: (message: string, loc := #caller_location) #expand {
    report_failure(loc, message);
    `return;
}

// Runs one test. run maintains the "current test name" context: it prints the
// `[test] <name>` start line and counts the test as passed unless a failure
// was registered while it ran.
run :: (name: string, proc: () -> ()) {
    current_test_name = name;
    current_test_failed = false;
    print("[test] %\n", name);
    proc();
    if !current_test_failed passed_count += 1;
    current_test_name = "";
}

// Prints the summary and returns the failure count; the driver turns a
// non-zero result into a compile error. Counters reset so a fresh suite can
// start afterward.
finish :: () -> s32 {
    print("% passed, % failed\n", passed_count, failure_count);
    result := failure_count;
    passed_count = 0;
    failure_count = 0;
    current_test_failed = false;
    current_test_name = "";
    return result;
}

// ---------------------------------------------------------------------------
// Self tests for this module, inlined as test blocks like
// user tests. The test program generator special-cases
// this file: its EXPAND view replaces `#import "Testing"` as the assertion
// module source (test discovery still excludes modules/), so the blocks below
// execute in the repository's own `juice test` run while user packages keep
// their unchanged import semantics.
//
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
//
// Shared declarations (the g_* record globals, testing_module_failures and
// the child scenario helpers) live in tests/test_support.jai — the helpers
// the Testing self-tests need do not live at this file's top level (release
// module discipline); they are program-level shared in the test program.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// In-process tests over the module state
// ---------------------------------------------------------------------------

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
// captured by the parent). The child scenario helpers (juice_exe,
// testing_child_run, expect_exit, normalize_crlf, output_matches,
// fixture_line_col) live in tests/test_support.jai (the Testing module
// self-test support segment).
// ---------------------------------------------------------------------------

test "child: pass scenario output and exit code" {
    result, output, _ := testing_child_run("pass");
    expect(expect_exit("pass", result, 0));

    // The anonymous test reports as src/scenarios.jai:<line of its `test`
    // token> (generated by the transpiler).
    anon_line, _ := fixture_line_col(tprint("%1/tests/data/testing-child/pass/src/scenarios.jai", juice_root()), "test {");
    expect(anon_line != 0);
    expected := tprint("[test] addition\n[test] equality\n[test] src/scenarios.jai:%1\n3 passed, 0 failed\n", anon_line);
    expect(output_matches("pass", output, string.[expected]));
}

test "child: fail scenario output and exit code" {
    result, output, _ := testing_child_run("fail");
    expect(expect_exit("fail", result, 1));

    path := "src/scenarios.jai";
    fixture_file := tprint("%1/tests/data/testing-child/fail/src/scenarios.jai", juice_root());
    l1, c1 := fixture_line_col(fixture_file, "expect(false);");
    l2, c2 := fixture_line_col(fixture_file, "expect_eq(3, 5);");
    l3, c3 := fixture_line_col(fixture_file, "fail(\"boom\")");
    l4, c4 := fixture_line_col(fixture_file, "expect(false, \"got % and %\", 7, 9)");
    l5, c5 := fixture_line_col(fixture_file, "expect_eq(3, 5, \"custom mismatch\")");
    expect(l1 != 0 && l2 != 0 && l3 != 0 && l4 != 0 && l5 != 0);
    expected := tprint(
        "[test] aborts\n%1:%2:%3: expect failed\n[test] eq-fails\n%1:%4:%5: expect_eq failed: expected 3, got 5\n[test] named-failure\n%1:%6:%7: boom\n[test] prints-message\n%1:%8:%9: got 7 and 9\n[test] custom-eq\n%1:%10:%11: custom mismatch\n0 passed, 5 failed\n",
        path, l1, c1, l2, c2, l3, c3, l4, c4, l5, c5);
    expect(output_matches("fail", output, string.[expected]));
    // The aborted test's body never continued past the failing assertion.
    expect(output_matches("fail", output, string.["reached"], want = false));
}

test "child: mapped scenario rewrites the failure path" {
    result, output, _ := testing_child_run("mapped");
    expect(expect_exit("mapped", result, 1));

    l, c := fixture_line_col(tprint("%1/tests/data/testing-child/mapped/src/scenarios.jai", juice_root()), "expect(2 + 2 == 5)");
    expect(l != 0);
    // The failure line reports the original package-relative coordinates:
    // the driver-injected mapping table rewrote the view path.
    expect(output_matches("mapped", output, string.[tprint("[test] mapped-fail\nsrc/scenarios.jai:%1:%2: expect failed\n0 passed, 1 failed\n", l, c)]));
    expect(output_matches("mapped", output, string.["target/transpile"], want = false));
}

// Latch for the suite-level failure gate: the in-process tests above drain
// the global register via finish() (Testing module semantics), so any
// failure they drained — or left by an earlier test — is re-checked here
// and trips the driver's finish()/assert gate instead of being masked.
test "Testing module register stays clean between tests" {
    expect(testing_module_failures == 0);
}
