#import "Juice";

// E2E run fixture (ticket 0093): two declared programs, no default_run. Only
// the selected program may be compiled, so the second program's source is
// deliberately unparsable: `juice run good` succeeds only if run never compiles
// a program it was not asked for.
PACKAGE :: Package.{
    name    = "run-select",
    version = "0.1.0",
    executables = .[
        .{name = "good", entry = "src/good.jai"},
        .{name = "broken", entry = "src/broken.jai"},
    ],
};
