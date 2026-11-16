#import "Juice";

// E2E run fixture (ticket 013): a BIN package with a single implicit target
// (named after the package), so `juice run` drives the build prerequisite
// chain and launches the artifact by default selection.
PACKAGE :: Package.{
    executables = .[.{name = "run_fixture", entry = "src/main.jai"}],
    version = "0.1.0",
    name    = "run-fixture",

};
