#import "Basic";

// The failure fixture (ticket 017): the failing assertion registers the
// failure and aborts the failing test body only — the suite continues (the
// sorted order runs test_after first), finish() aggregates the failure
// count, and the injected `if finish() != 0 assert(false);` turns
// it into a compile error (old juice execution semantics, spec section
// 7.2). The failure line prints the package-relative coordinate through the
// embedded path mapping.

test_after :: () {
    expect(true);
} @test

test_boom :: () {
    fail("boom");
} @test
