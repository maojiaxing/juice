#import "Juice";

// E2E test fixture (ticket 017, package manifest for the ticket 018 exe
// runs): a BIN package whose only sources are the hand-written @test files
// in src/ — no targets, so the test program is the only product.
PACKAGE :: Package.{
    name    = "test-fixture",
    version = "0.1.0",
    type    = .BIN,
};
