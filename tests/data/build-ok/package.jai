#import "Juice";

// E2E build fixture (ticket 011): a BIN package that compiles straight from
// the original source (no test blocks — the strip front is 1c) and produces
// a runnable artifact.
PACKAGE :: Package.{
    name    = "build-ok",
    version = "0.1.0",
    type    = .BIN,
};
