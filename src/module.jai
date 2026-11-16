#import "Basic";

// The declaration vocabulary and the Testing face both moved to
// packages/juice/ (publication source directories, not packages). These two
// loads keep their bare names in juice's own compilation unit: src/manifest.jai
// evaluates a Package value directly, and the self-tests below drive the
// Testing_ prefixed face this file defines.
//
// This file keeps its name deliberately: "src/module.jai" is a package entry
// probe path in the spec section 5.2 convention (src/plugin_scan.jai,
// src/dependency.jai), so renaming it would change what that probe finds.
#load "../packages/juice/module.jai";
#load "../packages/juice/testing.jai";

// ---------------------------------------------------------------------------
// Self-tests for the Testing face.
//
// The @test procedures below drive the module through program-level globals —
// Jai has no closures, so the run() bodies reach globals. The tests live here,
// not in packages/juice/testing.jai, so the published consumer face stays
// test-free and self-contained.
// ---------------------------------------------------------------------------

self_testing_failures: s64 = 0;
g_self_reached := false;
g_self_first_reached := false;
g_self_second_reached := false;
g_self_defer_ran := false;

// ---------------------------------------------------------------------------
// Self tests for the Testing face, standard Jai @test procedures (juice's own
// suite no longer uses the test-block syntax or the former global
// juice_test_N numbering; each procedure name is the stable slug of its
// original test display name). The publication transform
// (src/publication.jai) strips the Testing_ prefixes from
// packages/juice/testing.jai, which never carried these procedures, so the
// published Testing.jai stays test-free. The drain discipline is unchanged:
// every procedure starts by draining the module register into the shared
// accumulator, so a test that aborts mid-way cannot mask its leftovers — the
// closing latch drains once more and asserts the accumulator.
// ---------------------------------------------------------------------------

testing_face_expect_and_expect_eq_pass_and_continue :: () -> () {
    self_testing_failures += Testing_finish();
    g_self_reached = false;
    Testing_run("t-expect-pass", () -> () {
        Testing_expect(1 + 1 == 2);
        Testing_expect_eq("abc", "abc");
        Testing_expect_eq(2.5, 2.5);
        g_self_reached = true;
    });
    n := Testing_finish();
    Testing_expect(g_self_reached && n == 0);
} @test

testing_face_failure_aborts_the_current_test_the_suite_continues :: () -> () {
    self_testing_failures += Testing_finish();
    g_self_first_reached = false;
    g_self_second_reached = false;
    Testing_run("t-abort", () -> () {
        Testing_expect(3 > 4);
        g_self_first_reached = true;
    });
    Testing_run("t-next", () -> () {
        g_self_second_reached = true;
    });
    n := Testing_finish();
    Testing_expect(!g_self_first_reached && g_self_second_reached && n == 1);
} @test

testing_face_fail_always_registers_and_aborts :: () -> () {
    self_testing_failures += Testing_finish();
    g_self_reached = false;
    Testing_run("t-fail", () -> () {
        Testing_fail("always");
        g_self_reached = true;
    });
    n := Testing_finish();
    Testing_expect(!g_self_reached && n == 1);
} @test

testing_face_defer_runs_when_an_assertion_aborts_the_test :: () -> () {
    self_testing_failures += Testing_finish();
    g_self_defer_ran = false;
    Testing_run("t-defer", () -> () {
        defer g_self_defer_ran = true;
        Testing_expect(1 == 2);
    });
    n := Testing_finish();
    Testing_expect(g_self_defer_ran && n == 1);
} @test

testing_face_bare_return_ends_the_test_as_passed :: () -> () {
    self_testing_failures += Testing_finish();
    Testing_run("t-early", () -> () {
        x := 1;
        if x == 1 return;
        Testing_expect(false, "unreachable");
    });
    n := Testing_finish();
    Testing_expect(n == 0);
} @test

testing_face_finish_returns_the_failure_count_and_resets_state :: () -> () {
    self_testing_failures += Testing_finish();
    Testing_run("t-failing", () -> () { Testing_expect(false, "will-fail"); });
    n := Testing_finish();
    Testing_run("t-passing", () -> () { Testing_expect(true); });
    n2 := Testing_finish();
    Testing_expect(n == 1 && n2 == 0);
} @test

testing_face_registers_stay_clean_between_self_tests :: () -> () {
    self_testing_failures += Testing_finish();
    Testing_expect(self_testing_failures == 0);
} @test
