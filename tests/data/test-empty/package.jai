#import "Juice";

// E2E test fixture (ticket 019): the zero-file package — only the manifest,
// no .jai source files at all, so the test file collection returns nothing
// and the command short-circuits with "No tests found" before any test
// program is generated (the command-layer t4 semantics, spec section 7.3).
// The static tree carries no src/ and no target/ — the E2E scenario removes
// the session target/ after each run so the fixture stays clean.
PACKAGE :: Package.{
    name    = "test-empty",
    version = "0.1.0",
    type    = .BIN,
};
