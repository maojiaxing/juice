#import "Basic";

// The second fixture file: test_alpha lives here (after tests_a.jai in scan
// order but first in name order), plus test_gamma with a parameterized-note
// near miss that must not be collected (the note filter is exact/prefix
// only — spec section 7.1 point 2).

test_alpha :: () {
    expect(true);
} @test

test_gamma :: () {
    expect_eq(3, 1 + 2);
} @test

// "testy" is a substring match, not the exact convention — never collected.
testy_probe :: () {
    fail("must never run");
} @testy
