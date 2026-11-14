#import "Juice";

PACKAGE :: Package.{
    version = "0.1.0",
    name    = "bad_escape",

    workspace = .{
        members = string.["../outside"],
    },
};
