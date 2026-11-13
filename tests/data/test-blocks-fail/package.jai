#import "Juice";

// The 1c failure fixture (ticket 028): the failing test block's assertion
// aborts the test body only, the suite reports the mapped package-relative
// coordinate (the driver-injected path mapping rewrote the view path), and
// the finish()/assert gate turns the failure count into a compile error
// (old juice execution semantics, spec section 7.2).

PACKAGE :: Package.{
    name    = "test-blocks-fail",
    version = "0.1.0",
    type    = .BIN,
};
