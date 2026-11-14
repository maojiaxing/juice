#import "Juice";

// E2E protocol-error fixture (ticket 014): an empty exclude path — the
// evaluator child prints the empty EXCLUDE record (data line 9) and the
// parent's strict parser rejects it (byte-locked by manifest_tests.jai's
// bad-manifest E2E section).
PACKAGE :: Package.{
    version = "0.1.0",
    name    = "bad_empty_exclude",
    workspace = .{ exclude = string.[""] },
};
