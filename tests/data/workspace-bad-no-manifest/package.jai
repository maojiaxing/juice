#import "Juice";

PACKAGE :: Package.{
    version = "0.1.0",
    name    = "bad_no_manifest",

    workspace = .{
        members = string.["plain_member"],
    },
};
