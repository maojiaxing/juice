#import "Juice";

PACKAGE :: Package.{
    version = "0.1.0",
    name    = "bad_invalid_manifest",

    workspace = .{
        members = string.["broken_member"],
    },
};
