#import "Juice";

// Cross-package probe-precedence fixture (ticket 043, extended by the 040
// review fixes; declaration-driven since ticket 056): alpha-first is declared
// first and contributes the surviving "alpha-first" hit; zeta-extra's
// extra.jai (probe rank 3) is declared second; packages/extra's module.jai
// (rank 1, deriving the package directory name) is declared third. Both
// zeta-extra and extra derive the module name "extra"; the lower probe rank
// wins regardless of declaration order and the loser is dropped with a
// diagnostic. The winning hit must land at the third package's position,
// after alpha-first's surviving hit (declaration order, then intra-package
// scan order) — never hoisting into the dropped hit's slot. Each declared
// member provides exactly one plugin (the v1 one-plugin-per-package rule).
PACKAGE :: Package.{
    name    = "plugin_ws_rank",
    version = "0.1.0",
    type    = .BIN,
    workspace = .{
        members = string.["packages/alpha-first", "packages/zeta-extra", "packages/extra"],
    },
    plugins = .[
        .{id = "alpha-first", version = "0.1.0"},
        .{id = "zeta-extra", version = "0.1.0"},
        .{id = "extra", version = "0.1.0"},
    ],
};
