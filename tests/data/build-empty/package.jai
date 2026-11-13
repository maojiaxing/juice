#import "Juice";

// E2E zero-plan fixture (ticket 011): no declared targets and no
// src/main.jai — the package role derives to BIN with zero plans, so the
// build short-circuits before creating anything under target/.
PACKAGE :: Package.{
    name    = "build-empty",
    version = "0.1.0",
};
