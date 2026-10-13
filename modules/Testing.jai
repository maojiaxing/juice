// Juice's first-party assertion module for test blocks (issues/0005,
// spec 0013 Implementation Decisions 9). User test code imports it with
// `#import "Testing"`. Depends on Basic only; neutral toward the execution
// model (runtime runner / compile-time driver).
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

// Mutable global the driver fills in before running the test list
// (spec 0013 ID 8). Default empty array = passthrough.
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
// shape (issues/0005 resolution 2).
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
// compile time; T must support != and print (issues/0005 resolution 3).
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
