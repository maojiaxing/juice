#import "Basic";

// A failed assertion records one failure and returns from the current test
// body. The caller's defers still run, and run() can start the next test.
// This standard Jai entry is both the source module and the published bytes.

Path_Pair :: struct {
    view: string;
    original: string;
}

// The runner may rewrite absolute view paths to package-relative sources.
// An empty table leaves paths unchanged; line and column are never rewritten.
path_mapping: [..] Path_Pair;

// Keep the existing printf-style heterogeneous arguments at this boundary.
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

fail :: (message: string, loc := #caller_location) #expand {
    report_failure(loc, message);
    `return;
}

run :: (name: string, proc: () -> ()) {
    current_test_failed = false;
    print("[test] %\n", name);
    proc();
    if !current_test_failed passed_count += 1;
}

// Return the failure count and clear the suite counters. The runner decides
// how a nonzero result affects its process exit status. Mapping is caller-owned.
finish :: () -> s32 {
    print("% passed, % failed\n", passed_count, failure_count);
    result := failure_count;
    passed_count = 0;
    failure_count = 0;
    current_test_failed = false;
    return result;
}

#scope_file;

// Macro expansion resolves these names at the definition site. All importers
// of this module share the same state, without exporting it to application code.
current_test_failed := false;
passed_count: s32 = 0;
failure_count: s32 = 0;

mapped_path :: (view: string) -> string {
    for pair: path_mapping {
        if pair.view == view return pair.original;
    }
    return view;
}

report_failure :: (location: Source_Code_Location, message: string) {
    current_test_failed = true;
    failure_count += 1;
    print("%:%:%: %\n", mapped_path(location.fully_pathed_filename), location.line_number, location.character_number, message);
}

#scope_export;
