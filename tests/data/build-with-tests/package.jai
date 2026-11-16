#import "Juice";

PACKAGE :: Package.{
    version = "1",
    name    = "build-with-tests",

    executables = .[
        .{name = "build_with_tests", entry = "src/main.jai"},
    ],
};
