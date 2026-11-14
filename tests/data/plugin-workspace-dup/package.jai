#import "Juice";

// Cross-package duplicate module-name fixture (ticket 043; declaration-driven
// since ticket 056): both declared members carry an extra.jai, so both derive
// the #import module name "extra" (the file stem). Equal probe ranks resolve
// by accumulation order — the earlier declaration wins — and the loser is
// dropped with a non-fatal diagnostic.
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
