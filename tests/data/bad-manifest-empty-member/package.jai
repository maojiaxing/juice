#import "Juice";

// E2E protocol-error fixture (ticket 014): an empty member path — the
// evaluator child prints the empty MEMBER record (data line 8) and the
// parent's strict parser rejects it (byte-locked by manifest_tests.jai's
// bad-manifest E2E section).
PACKAGE :: Package.{
    version = "0.1.0",
    name    = "bad_empty_member",
    workspace = .{ members = string.[""] },
};
