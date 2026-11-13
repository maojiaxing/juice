#import "Juice";

// Cross-package duplicate module-name fixture (ticket 043; declaration-driven
// since ticket 056): both declared members carry an extra.jai, so both derive
// the #import module name "extra" (the file stem). Equal probe ranks resolve
// by accumulation order — the earlier declaration wins — and the loser is
// dropped with a non-fatal diagnostic.
PACKAGE :: Package.{
    name    = "plugin_ws_dup",
    version = "0.1.0",
    type    = .BIN,
    workspace = .{
        members = string.["packages/first-plugin", "packages/second-plugin"],
    },
    plugins = .[
        .{id = "first-plugin", version = "0.1.0"},
        .{id = "second-plugin", version = "0.1.0"},
    ],
};
