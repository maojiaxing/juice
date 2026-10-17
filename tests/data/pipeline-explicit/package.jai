#import "Juice";

PACKAGE :: Package.{
    name    = "pipeline-explicit",
    version = "0.1.0",
    type    = .BIN,
    transpile = .{
        plugins = .[
            .{ id = "load",       version = "1.0.0" },
            .{ id = "test-block", version = "1.0.0" },
        ],
    },
};
