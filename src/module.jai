#import "Basic";

// The package declaration compatibility face (spec section 2.1). This file
// is the single definition source for the published "Juice" module (spec
// section 9.1): field shapes stay declaration-compatible with the reference
// implementation's module face (its Juice.jai declaration block,
// lines 97-118), except for the 2026-10-21 design revision: the pre-step
// marker and transpile fields are removed and `Package.plugins` is the
// single plugin declaration/configuration/ordering surface (breaking
// change; spec 2.1).
// Extension fields arrive only after the self-hosting switch (spec section
// 2.3).
//
// The package section also carries the internal structure face
// (Effective_Target / Artifact_Plan / Workspace_Discovery /
// Prepared_Workspace, ticket 032): otter's implementation modules consume
// these through the namespaced Juice binding (src/juice_module.jai), so the
// published directory module must carry them — both the self-built
// executable and the self-hosted test program compile against the published
// face. Shapes mirror the old juice module face declaration for
// declaration; the published directory module is the only face in use
// (the bootstrap seed window is retired).
//
// The namespaced binding resolves against otter's published directory
// module (spec section 9.4): the self-built executable, the manifest
// evaluator children (they receive the modules directory on their import
// path) and the self-hosted test programs all compile against the published
// face. Tests exercise this file's declarations directly through Test
// discovery's full-package scan (tests/module_tests.jai — it never
// #imports "Juice").
//
// The Testing API surface (ticket 016) lives at the end of this file in its
// definition-source declaration shape — see the section comment there.
//
// Publication section contract (ticket 030, spec section 9.1): the publish
// step (src/publication.jai) cuts the published module artifacts out of
// this file at two marker comments, and those marker lines are the
// single-source contract. `// [PUBLICATION-SECTION package]` (right below)
// starts the Juice directory module's content; `// [PUBLICATION-SECTION
// testing]` (before the Testing banner) starts Testing.jai's — the banner
// is part of the testing section (the published module carries it as
// provenance documentation). A missing, duplicated, misordered or renamed
// marker fails the publication loudly — keep the marker lines verbatim.
// [PUBLICATION-SECTION package]

// UNSPECIFIED means the role is derived from convention during target
// resolution: src/main.jai (or declared targets) means BIN; an import entry
// means LIB; anything else stays BIN.
Package_Type :: enum {
    LIB;
    BIN;
    UNSPECIFIED;
}

// Raw target declaration as written by package.jai.
Target :: struct {
    name:      string;
    main_file: string;
}

// A target after defaults and filesystem validation have been applied.
Effective_Target :: struct {
    name:        string;
    main_file:   string;
    source_path: string;
}

// The complete output contract consumed by Build and Run. target_dir is the
// package's unified target/ directory root; the artifact lands directly
// inside it (no profile sublayers).
Artifact_Plan :: struct {
    target:        Effective_Target;
    target_dir:    string;
    artifact_path: string;
}

Dependency :: struct {
    name:    string;
    version: string = "";
    source:  string = "";
    package: string = "";
}

Workspace_Config :: struct {
    members: [] string;
    exclude: [] string;
}

// One option row of a plugin declaration. The value is a string; the plugin's
// options schema owns parsing and validation (Config_Option.apply, added by
// the pre-step plugin effort). Options cross the manifest protocol as
// PLUGIN_OPTION records with %XX encoding.
Plugin_Option :: struct {
    key:   string;
    value: string;
}

// One plugin declaration: the plugin identity (id + version — feeds the
// pipeline/hook description and the cache key) plus the options rows.
// Declaration order = pipeline order = hook registration order = lint
// observation order. An empty Package.plugins list means the default
// pipeline and no hooks/lint. Member plugins use the member package name as
// their id; the built-in ids are TRANSPILE_PLUGIN_LOAD_ID /
// TRANSPILE_PLUGIN_TEST_BLOCK_ID.
Plugin_Declaration :: struct {
    id:      string;
    version: string;
    options: [] Plugin_Option;
}

// The v1 built-in transpile plugin ids: the reserved built-in declaration
// ids. Member plugin ids are package names and must not collide with these.
TRANSPILE_PLUGIN_LOAD_ID       :: "load";
TRANSPILE_PLUGIN_TEST_BLOCK_ID :: "test-block";

Package :: struct {
    name:         string;
    version:      string;
    type:         Package_Type = .UNSPECIFIED;
    description:  string = "";

    targets:      [] Target;

    dependencies: [] Dependency;
    workspace:    Workspace_Config;
    build_script: string = "";

    // Plugin declarations: the single activation/configuration/ordering
    // surface (2026-10-21 design revision). An empty list means the default
    // transpile pipeline and no hooks/lint.
    plugins:      [] Plugin_Declaration;

    // Set by the manifest loader; it is not declared in package.jai.
    dir:          string = "";
}

// Discovery retains the evaluated declarations, including the root first.
// Dependencies consume this snapshot rather than executing member manifests
// again.
Workspace_Discovery :: struct {
    root_dir:        string;
    has_package:     bool;
    root_package:    Package;
    member_packages: [] Package;
}

// State shared by command handlers after discovery, resolution, and (if
// necessary) dependency preparation have completed.
Prepared_Workspace :: struct {
    discovery:             Workspace_Discovery;
    artifact_plans:        [] Artifact_Plan;
    // The package role after UNSPECIFIED has been resolved by convention.
    package_type:          Package_Type;
    dependencies_prepared: bool;
}

// [PUBLICATION-SECTION testing]

// ---------------------------------------------------------------------------
// Testing API surface (ticket 016, spec section 9.5): the definition-source
// declaration shape of the published "Testing" module — expect/expect_eq/
// fail/run/finish/path_mapping, API-compatible with old juice's Testing.jai
// (the published face is what test programs consume since ticket 035).
//
// The public names carry the Testing_ prefix because this file enters every
// test program's application scope through Test discovery's full-package
// scan, while the test driver imports the published Testing face — bare
// run/finish/expect/... declarations here would collide with that face. The
// shape is pinned by the spike at
// AppData/Local/Temp/otter-testing-shape-spike/ (the bare candidate fails
// with "Two overloaded definitions of the same procedure can't have
// identical argument lists"); the prefix keeps the definition-source face
// distinct from the imported published face.
//
// The internals stay bare under #scope_file, mirroring the published
// module's structure: the publication step (ticket 030,
// src/publication.jai) strips the Testing_ prefixes from this section and
// emits it as target/modules/Testing.jai — no other transformation (the
// spike's publish smoke compiled the converted module with a bare import).
//
// The published face is the only consumption path (ticket 035): test
// drivers import the published module and drive the bare names. These
// prefixed declarations remain the definition source's internal face — the
// publication transform's input and the face the src self-tests and
// module_tests' definition-source scenarios exercise. (Ticket 003's
// source-face driver loading is retired.)
//
// Semantics (old juice Testing.jai contract): a failing assertion registers
// the failure globally and aborts the current test body immediately (the
// backticked `return is inserted into the caller); the suite keeps running
// and defers fire normally. Each failure prints as `path:line,col: message`
// and each test start as `[test] <name>`; finish() prints
// `N passed, M failed` and returns the failure count. path_mapping is the
// driver-injected "view absolute path <-> original package-relative path"
// rewrite table; the default empty array passes paths through untouched.
// ---------------------------------------------------------------------------

// One rewrite pair: `view` is the absolute path of a view (the path
// #caller_location reports); `original` is the package-relative source path
// printed in its place.
Testing_Path_Pair :: struct {
    view:     string;
    original: string;
}

// Mutable global the driver fills in before running the test list.
// Default empty array = passthrough.
Testing_path_mapping : [..] Testing_Path_Pair;

// expect(cond) with an optional printf-style message, mirroring Basic.assert's
// shape.
Testing_expect :: (condition: bool, message := "", args: .. Any, loc := #caller_location) #expand {
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
Testing_expect_eq :: (expected: $T, actual: T, message := "", loc := #caller_location) #expand {
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
Testing_fail :: (message: string, loc := #caller_location) #expand {
    report_failure(loc, message);
    `return;
}

// Runs one test. run prints the `[test] <name>` start line and counts the
// test as passed unless a failure was registered while it ran.
Testing_run :: (name: string, proc: () -> ()) {
    current_test_failed = false;
    print("[test] %\n", name);
    proc();
    if !current_test_failed passed_count += 1;
}

// Prints the summary and returns the failure count; the driver turns a
// non-zero result into a compile error. Counters reset so a fresh suite can
// start afterward.
Testing_finish :: () -> s32 {
    print("% passed, % failed\n", passed_count, failure_count);
    result := failure_count;
    passed_count = 0;
    failure_count = 0;
    current_test_failed = false;
    return result;
}

#scope_file;

// --- Internal registration state. File-private (the published module keeps
// the same bare names under #scope_file); the #expand macros above resolve
// these names at their definition site, so callers in other files never see
// them. Module-level globals are shared program-wide by every file that
// loads this file. ---

current_test_failed := false;
passed_count: s32 = 0;
failure_count: s32 = 0;

mapped_path :: (view: string) -> string {
    for pair: Testing_path_mapping {
        if pair.view == view return pair.original;
    }
    return view;
}

report_failure :: (loc: Source_Code_Location, message: string) {
    current_test_failed = true;
    failure_count += 1;
    print("%:%:%: %\n", mapped_path(loc.fully_pathed_filename), loc.line_number, loc.character_number, message);
}

#scope_export;

// [PUBLICATION-CUT testing-self-tests]
// The published Testing.jai ends before this marker: the self-test procedures
// and their state below are juice's own suite surface, not part of the
// consumer face. Keeping them out of the published module is what lets the
// published face compile as standard Jai without colliding with a consumer's
// own @test procedure names. The definition source keeps the tests in place.

// ---------------------------------------------------------------------------
// Self-test state: the @test procedures below drive the module through these
// program-level globals — Jai has no closures, so the run() bodies reach
// globals. They stay beside the definition source's tests (the published
// Testing.jai cuts at the marker above, so the consumer face stays test-free
// and self-contained).
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
// (src/publication.jai) retains this segment and strips the Testing_ prefixes,
// so the published Testing.jai carries the same procedures against the bare
// names. The drain discipline is unchanged: every procedure starts by
// draining the module register into the shared accumulator, so a test that
// aborts mid-way cannot mask its leftovers — the closing latch drains once
// more and asserts the accumulator.
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
