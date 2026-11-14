#import "Juice";

PACKAGE :: Package.{
    version = "0.1.0",
    name    = "bad_duplicate",

    workspace = .{
        members = string.["member_lib", "member_lib/."],
    },
};
