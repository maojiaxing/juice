#import "Basic";

// The failing test block: EXPAND renames it juice_test_1, the runner
// executes it through the note enumeration, and the failure prints
// src/math.jai:<line>:<col> through the path mapping (view path -> original
// package-relative path; the EXPAND pass preserves line numbers).

add :: (a: s32, b: s32) -> s32 {
    return a + b;
}

test "broken math" {
    expect_eq(add(2, 3), 99);
}
