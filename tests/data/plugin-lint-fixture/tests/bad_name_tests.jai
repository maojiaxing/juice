// Fixture test source (ticket 042): the test program the E2E metaprogram
// compiles. BadNameTest trips the fixture plugin's lint rule (one WARNING
// anchored at this declaration), test_good_name stays clean, and the
// imported module's own @test is out of the package view set — imported
// modules are neither collected nor linted. All three facts are pinned by
// the E2E child output.
#import "Basic";
#import "Testing";
#import "imported_tests";

BadNameTest :: () {
    expect(1 + 1 == 2);
} @test

test_good_name :: () {
    expect(true);
} @test
