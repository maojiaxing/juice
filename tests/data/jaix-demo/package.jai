#import "Juice";

// jaix pre-step demo package (ticket 058; member form since ticket 061): the
// declaration activates the `juice-plugin-jaix` member — juice build
// jaix-transpiles the whole package into target/jaix/ (mirroring the package
// layout) and compiles the mirror entry view, so the try/catch extension
// syntax below builds through. The config option is the package-relative
// path of the jaix configuration; the optional exe option stays empty, so the
// plugin probes PATH for "jaix" (the E2E injects the sibling jaix-cli build).
//
// The member package is not part of this static fixture tree (it lives at
// packages/juice-plugin-jaix in the repository): the E2E copies the fixture
// into a scratch workspace and copies the real member tree beside it under
// packages/. The workspace.members path is root-relative, never a path into a
// juice checkout (the distribution contract).
PACKAGE :: Package.{
    version = "0.1.0",
    name    = "jaix-demo",

    executables = .[
        .{name = "jaix_demo", entry = "src/main.jai"},
    ],
    workspace = .{
        members = string.["packages/juice-plugin-jaix"],
    },
    plugins = Plugin_Declaration.[
        .{builtin = "load"},
        .{builtin = "test-block"},
        .{id = "juice-plugin-jaix", source = .{kind = .PATH, path = "packages/juice-plugin-jaix"},
            options = Plugin_Option.[
                .{key = "config", value = "jaix.config.jai"},
            ],
        },
    ],
};
