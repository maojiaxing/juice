#import "Juice";

// E2E breaking-change fixture (ticket 055): the `jaix` field was removed
// from the published Package face on 2026-10-21 (Package.plugins replaced
// it). The evaluator child fails to compile this manifest against the
// published face — the test locks the hard cut's failure path (byte-locked
// by manifest_tests.jai's bad-manifest E2E section).
PACKAGE :: Package.{
    name    = "bad_jaix",
    version = "0.1.0",
    jaix    = .{ exe = "jaix" },
};
