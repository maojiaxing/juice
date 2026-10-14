#import "Juice";

PACKAGE :: Package.{
    name    = "bad_no_manifest",
    version = "0.1.0",
    type    = .BIN,
    workspace = .{
        members = string.["plain_member"],
    },
};
