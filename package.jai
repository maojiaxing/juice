#import "Juice";

// Otter (the juice rewrite) stage 0: the repository root is a BIN package
// with the same shape juice itself declares, so old juice can build and
// test this package with zero special-casing (spec section 10, stage 0).
PACKAGE :: Package.{
    version = "0.1.0",
    name    = "juice",

    executables = .[
        .{name = "juice", entry = "src/main.jai"},
    ],
    // The real third-party plugin members: workspace.members makes each
    // package discoverable, and Package.plugins declares it as a plugin
    // (ticket 056's design revision) — declaration = available + activated +
    // configured + ordered. The member plugin id is the member package name;
    // the dependency list never activates plugins. juice-plugin-jaix is the
    // Phase 2 member (ticket 061): a declared jaix with no config option is
    // the defined no-op pre-step, so the root's own builds run no jaix work
    // while the declaration keeps the member wiring exercised.
    workspace = .{
        members = string.["packages/juice-plugin-lint", "packages/juice-plugin-jaix"],
    },
    plugins = Plugin_Declaration.[
        .{builtin = "load"},
        .{builtin = "test-block"},
        .{id = "juice-plugin-lint", source = .{kind = .PATH, path = "packages/juice-plugin-lint"}},
        .{id = "juice-plugin-jaix", source = .{kind = .PATH, path = "packages/juice-plugin-jaix"}},
    ],
};
