#import "Juice";

// E2E run failure fixture (ticket 013): the artifact exits nonzero, pinning
// the run command's exit-code passthrough (juice maps any failing artifact
// exit to command failure).
PACKAGE :: Package.{
    executables = .[.{name = "run_fail", entry = "src/main.jai"}],
    version = "0.1.0",
    name    = "run-fail",

};
