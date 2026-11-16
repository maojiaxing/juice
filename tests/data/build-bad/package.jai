#import "Juice";

// E2E failure-path fixture (ticket 011): the entry has a compile error, so
// the spawned jai fails and the build exits nonzero without an artifact.
PACKAGE :: Package.{
    executables = .[.{name = "build_bad", entry = "src/main.jai"}],
    version = "0.1.0",
    name    = "build-bad",

};
