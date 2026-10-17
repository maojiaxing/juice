#import "Juice";

PACKAGE :: Package.{
    name    = "pipeline-unknown",
    version = "0.1.0",
    type    = .BIN,
    transpile = .{
        plugins = .[
            .{ id = "mystery-plugin", version = "1.0.0" },
        ],
    },
};
