#import "Juice";

// A LIB member declaring a dependency on another member by name (with a
// source relative to the member's own root when it runs as its own root);
// from the root side the declared name links the member directly.
PACKAGE :: Package.{
    version = "0.1.0",
    name    = "member_extra",

    dependencies = Dependency.[
        .{name = "member_lib", source = .{kind = .PATH, path = "../member_lib"}},
    ],
};
