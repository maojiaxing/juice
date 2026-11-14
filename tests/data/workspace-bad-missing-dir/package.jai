#import "Juice";

PACKAGE :: Package.{
    version = "0.1.0",
    name    = "bad_missing_dir",

    workspace = .{
        members = string.["ghost_member"],
    },
};
