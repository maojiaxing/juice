#import "Juice";

// E2E protocol-error fixture (ticket 014): an empty exclude path — the
// evaluator child prints the empty EXCLUDE record (data line 6) and the
// parent's strict parser rejects it (byte-locked by manifest_tests.jai's
// bad-manifest E2E section).
PACKAGE :: Package.{
    name    = "bad_empty_exclude",
    version = "0.1.0",
    workspace = .{ exclude = string.[""] },
};
