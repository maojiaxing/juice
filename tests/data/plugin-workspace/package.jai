#import "Juice";

// Workspace-level plugin scan fixture (ticket 043; declaration-driven since
// ticket 056): the root activates members strictly through Package.plugins
// declarations, in declaration order. zeta-plugin is declared first, then
// alpha-plugin; plain-member is a member that is NOT declared (it carries no
// plugin anchor and must never be scanned); external-lib is an ordinary
// dependency that names no member (dependencies never activate plugins).
// The workspace.members order and the package directory order both put
// alpha-plugin first — the scan order follows the declarations instead.
PACKAGE :: Package.{
    name    = "plugin_ws_root",
    version = "0.1.0",
    type    = .BIN,
    workspace = .{
        members = string.["packages/alpha-plugin", "packages/plain-member", "packages/zeta-plugin"],
    },
    dependencies = Dependency.[
        .{name = "external-lib", version = "9.9.9"},
    ],
    plugins = .[
        .{id = "zeta-plugin", version = "0.1.0"},
        .{id = "alpha-plugin", version = "0.1.0"},
    ],
};
