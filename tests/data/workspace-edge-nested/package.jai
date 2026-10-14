#import "Juice";

PACKAGE :: Package.{
    name    = "edge_nested",
    version = "0.1.0",
    type    = .BIN,
    workspace = .{
        members = string.["member_lib"],
    },
};
