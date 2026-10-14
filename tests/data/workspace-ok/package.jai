#import "Juice";

PACKAGE :: Package.{
    name    = "ws_root",
    version = "0.1.0",
    type    = .BIN,
    workspace = .{
        members = string.["member_lib", "member_extra"],
    },
    dependencies = Dependency.[
        .{name = "member_lib", version = "0.1.0"},
        .{name = "member_extra", version = "0.1.0"},
    ],
};
