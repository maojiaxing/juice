#import "Juice";

// Module-selection fixture (ticket 043's probe-rank matrix, migrated to
// independent sources by ticket 0092): the three declared members put their
// plugin anchors in differently NAMED files, and the middle one shares its
// file stem with the third — under the retired model the file stem WAS the
// #import name, so the stem collision had to be arbitrated by probe rank.
// A declaration now selects its module explicitly and the registration imports
// the declaration id, so all three enablements coexist at their declaration
// positions and the entry file names never arbitrate anything.
//
// packages/extra declares TWO public modules: the `ambiguous_extra` case below
// omits the module name and must be rejected (the provider exposes several),
// which is the replacement rule for the retired probe precedence.
PACKAGE :: Package.{
    version = "0.1.0",
    name    = "plugin_ws_rank",

    workspace = .{
        members = string.["packages/alpha-first", "packages/zeta-extra", "packages/extra"],
    },
    plugins = .[
        .{id = "alpha-first", source = .{kind = .PATH, path = "packages/alpha-first"}, module = .{name = "alpha_first_plugin"}},
        .{id = "zeta-extra", source = .{kind = .PATH, path = "packages/zeta-extra"}, module = .{name = "zeta_plugin"}},
        .{id = "extra", source = .{kind = .PATH, path = "packages/extra"}, module = .{name = "extra_plugin"}},
    ],
};
