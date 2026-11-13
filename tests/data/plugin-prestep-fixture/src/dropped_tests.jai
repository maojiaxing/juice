#import "Testing";

// The dropped test (ticket 060 fixture): the member PRESTEP plugin's `drop`
// option removes this file from the test program before TRANSPILE, so the
// failing body must never execute (and the file must never compile).
test "plugin prestep dropped test" {
    expect(false, "the dropped test must never run");
}
