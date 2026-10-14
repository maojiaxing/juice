#import "Juice";

PACKAGE :: Package.{
    name    = "bad_invalid_manifest",
    version = "0.1.0",
    type    = .BIN,
    workspace = .{
        members = string.["broken_member"],
    },
};
