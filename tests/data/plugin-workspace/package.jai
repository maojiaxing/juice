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
    version = "0.1.0",
    name    = "plugin_ws_root",

    workspace = .{
        members = string.["packages/alpha-plugin", "packages/plain-member", "packages/zeta-plugin"],
    },
    dependencies = Dependency.[
        .{name = "external-lib", source = .{kind = .WORKSPACE}, modules = .[.{path = "packages/external-lib"}]},
    ],
    plugins = .[
        .{id = "zeta-plugin", source = .{kind = .PATH, path = "packages/zeta-plugin"}},
        .{id = "alpha-plugin", source = .{kind = .PATH, path = "packages/alpha-plugin"}},
    ],
};
