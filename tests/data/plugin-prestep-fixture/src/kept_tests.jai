#import "Testing";

// The kept test (ticket 060 fixture): the only test that may run when the
// member plugin's host drops src/dropped_tests.jai.
test "plugin prestep kept test" {
    expect(true);
}
