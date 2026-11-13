#import "Juice";

// E2E run failure fixture (ticket 013): the artifact exits nonzero, pinning
// the run command's exit-code passthrough (juice maps any failing artifact
// exit to command failure).
PACKAGE :: Package.{
    name    = "run-fail",
    version = "0.1.0",
    type    = .BIN,
};
