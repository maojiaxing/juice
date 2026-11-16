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
    // The two plugin packages live under plugins/ (they are juice's own
    // integrations, not third-party members); workspace.members makes each
    // package discoverable and Package.plugins declares it as a plugin
    // (ticket 056's design revision) — declaration = available + activated +
    // configured + ordered. Membership never activates a plugin, and the
    // directory name carries no meaning: it is classification only.
    //
    // The plugin id comes from the declaration below and is NOT derived from
    // the member package name. The two happen to share a spelling here, but
    // tests/plugin_scan_tests.jai and tests/final_review_tests.jai both rely on
    // id and package name being able to differ, so never introduce that
    // derivation.
    //
    // juice-plugin-jaix is the Phase 2 member (ticket 061): a declared jaix
    // with no config option is the defined no-op pre-step, so the root's own
    // builds run no jaix work while the declaration keeps the member wiring
    // exercised.
    workspace = .{
        members = string.["plugins/juice-plugin-lint", "plugins/juice-plugin-jaix"],
    },
    plugins = Plugin_Declaration.[
        .{builtin = "load"},
        .{builtin = "test-block"},
        .{id = "juice-plugin-lint", source = .{kind = .PATH, path = "plugins/juice-plugin-lint"}},
        .{id = "juice-plugin-jaix", source = .{kind = .PATH, path = "plugins/juice-plugin-jaix"}},
    ],
};
