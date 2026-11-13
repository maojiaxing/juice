#import "Basic";

// Test fixture (ticket 017, numbering face extended by ticket 019): a
// hand-written @test program — the trailing note is the discovery source
// (spec section 7.1), the bodies assert through the published Testing
// face's bare names (the generated driver imports it — ticket 035's single
// register). The file/name order deliberately differs
// (tests_b.jai declares test_alpha) so the sorted run order is visible in
// the output; juice_test_10 is declared before juice_test_2 so the
// numeric-aware name sort (spec section 7.1 point 2) is what pins the run
// order — plain lexicographic order would run them the other way around.

test_beta :: () {
    expect(2 + 2 == 4);
} @test

// The numbering face (ticket 019): hand-written juice_test_N names enter the
// same discovery stream (1c's EXPAND output carries the same shape), and the
// deterministic order compares the numeric parts as numbers — juice_test_2
// sorts before juice_test_10 despite the declaration order.
juice_test_10 :: () {
    expect(true);
} @test

juice_test_2 :: () {
    expect_eq(20, 4 * 5);
} @test

// A non-collected procedure keeps the count honest: if discovery leaked
// procedures without the @test note into the run list, the count would move.
not_a_test_helper :: () -> s64 {
    return 7;
}
