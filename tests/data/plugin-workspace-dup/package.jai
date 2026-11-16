#import "Juice";

// Cross-package same-file-name fixture (ticket 043; independent sources since
// ticket 0092): both declared members carry an extra.jai and both declare it
// as their public module, so the two providers have the SAME entry file name.
// The retired model derived the #import name from the file stem and arbitrated
// the collision by probe rank; a declaration now names its own module and the
// registration imports the DECLARATION's id, so the shared file name never
// collides and both plugins stay enabled at their declaration position.
PACKAGE :: Package.{
    version = "0.1.0",
    name    = "plugin_ws_dup",

    workspace = .{
        members = string.["packages/first-plugin", "packages/second-plugin"],
    },
    plugins = .[
        .{id = "first-plugin", source = .{kind = .PATH, path = "packages/first-plugin"}},
        .{id = "second-plugin", source = .{kind = .PATH, path = "packages/second-plugin"}},
    ],
};
