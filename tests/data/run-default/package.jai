#import "Juice";

// E2E run fixture (ticket 0093): two valid programs and a declared default_run,
// so `juice run` without a program name selects the declared default instead of
// falling back to the first program or the package name.
PACKAGE :: Package.{
    name        = "run-default",
    version     = "0.1.0",
    default_run = "two",
    executables = .[
        .{name = "one", entry = "src/one.jai"},
        .{name = "two", entry = "src/two.jai"},
    ],
};
