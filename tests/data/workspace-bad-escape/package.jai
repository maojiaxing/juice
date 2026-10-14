#import "Juice";

PACKAGE :: Package.{
    name    = "bad_escape",
    version = "0.1.0",
    type    = .BIN,
    workspace = .{
        members = string.["../outside"],
    },
};
