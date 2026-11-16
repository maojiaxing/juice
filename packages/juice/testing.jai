#import "Basic";

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
