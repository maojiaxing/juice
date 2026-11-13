#import "Basic";

// The second fixture file: the global numbering continues across files
// (juice_test_3/juice_test_4 — ticket 023's caller-side contract, wired by
// ticket 028's t3).

add :: (a: s32, b: s32) -> s32 {
    return a + b;
}

test "addition" {
    expect_eq(add(2, 3), 5);
}

test "addition with negatives" {
    expect_eq(add(-2, -3), -5);
}
