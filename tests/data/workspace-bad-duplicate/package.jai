#import "Juice";

PACKAGE :: Package.{
    name    = "bad_duplicate",
    version = "0.1.0",
    type    = .BIN,
    workspace = .{
        members = string.["member_lib", "member_lib/."],
    },
};
