#import "Juice";

PACKAGE :: Package.{
    name    = "edge_self",
    version = "0.1.0",
    type    = .BIN,
    workspace = .{
        members = string.["."],
    },
};
