#import "Juice";

PACKAGE :: Package.{
    name    = "build-with-tests",
    version = "1",
    type    = .BIN,
    targets = Target.[
        .{name = "build-with-tests", main_file = "src/main.jai"},
    ],
};
