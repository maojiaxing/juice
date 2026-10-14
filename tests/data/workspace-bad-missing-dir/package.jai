#import "Juice";

PACKAGE :: Package.{
    name    = "bad_missing_dir",
    version = "0.1.0",
    type    = .BIN,
    workspace = .{
        members = string.["ghost_member"],
    },
};
