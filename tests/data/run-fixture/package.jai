#import "Juice";

// E2E run fixture (ticket 013): a BIN package with a single implicit target
// (named after the package), so `juice run` drives the build prerequisite
// chain and launches the artifact by default selection.
PACKAGE :: Package.{
    name    = "run-fixture",
    version = "0.1.0",
    type    = .BIN,
};
