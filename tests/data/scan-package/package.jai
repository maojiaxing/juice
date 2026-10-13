#import "Juice";

PACKAGE :: Package.{
    name    = "scan-package",
    version = "0.1.0",
    type    = .BIN,
    workspace = .{
        members = string.["member-a"],
        exclude = string.[],
    },
    dependencies = Dependency.[
        .{name = "member-a", version = "0.1.0"},
    ],
};
