#import "Juice";

// Member PRESTEP plugin fixture (ticket 060): the root declares one workspace
// member plugin (id = the member package name) whose value contributes a
// PRESTEP `before` hook and an options schema. The command-level prepare
// scans the member, writes target/plugins/registration.jai and spawns the
// generated PRESTEP-only host — the member value exists only in that child.
//
// The options drive the hook so the E2E observes real host effects:
// - entry/replacement: substitute src/main.jai with the shipped view file
//   .prestep/main.jai (a dot directory: outside every test/plugin scan);
// - drop: remove the failing test source from the test program;
// - message: an INFO diagnostic carrying "|" and "%", pinning the record
//   escaping round-trip through the host file.
// The two failing/kept test blocks live in src/kept_tests.jai and
// src/dropped_tests.jai; only the dropped one may disappear.
PACKAGE :: Package.{
    name    = "plugin-prestep-fixture",
    version = "0.1.0",
    type    = .BIN,
    targets = Target.[
        .{name = "plugin-prestep-fixture", main_file = "src/main.jai"},
    ],
    workspace = .{
        members = string.["packages/prestep-plugin"],
    },
    plugins = Plugin_Declaration.[
        .{
            id      = "prestep-plugin",
            version = "0.1.0",
            options = Plugin_Option.[
                .{key = "entry",       value = "src/main.jai"},
                .{key = "replacement", value = ".prestep/main.jai"},
                .{key = "drop",        value = "src/dropped_tests.jai"},
                .{key = "message",     value = "prestep|50% done"},
            ],
        },
    ],
};
