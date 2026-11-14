#import "Juice";

// The dependency declaration face: the root references both members through
// declared DEP records (members are linked only by declared name, never by
// directory presence), and every member's own dependency declarations load
// with its manifest into the discovery snapshot.
PACKAGE :: Package.{
    version = "0.1.0",
    name    = "ws_root",

    workspace = .{
        members = string.["member_lib", "member_extra"],
    },
    dependencies = Dependency.[
        .{name = "member_lib", source = .{kind = .WORKSPACE}, modules = .[.{path = "member_lib"}]},
        .{name = "member_extra", source = .{kind = .WORKSPACE}, modules = .[.{path = "member_extra"}]},
    ],
};
