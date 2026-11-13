#import "Juice";

// E2E failure fixture (ticket 017, package manifest for the ticket 018 exe
// runs): the failing @test program in src/failing.jai drives the suite
// continuation and the aggregated exit code through the real command.
PACKAGE :: Package.{
    name    = "test-fail",
    version = "0.1.0",
    type    = .BIN,
};
