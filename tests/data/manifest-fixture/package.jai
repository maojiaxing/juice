#import "Juice";

// E2E manifest fixture for the evaluator protocol (ticket 007): declares
// every protocol record kind so the real-jai-child round trip can be
// asserted field by field. The expected protocol text lives in
// tests/manifest_tests.jai's FULL_PROTOCOL constant — keep the two in sync.
PACKAGE :: Package.{
    name         = "manifest-fixture",
    version      = "1.2.3",
    description  = "Evaluator protocol E2E fixture.",
    default_run = "app",

    modules = .[
        .{name = "Api", entry = "src/module.jai"},
    ],
    executables = .[
        .{name = "app", entry = "src/main.jai"},
    ],
    plugins = .[
        .{builtin = "load"},
        .{builtin = "test-block"},
        .{id = "external-lint", source = .{kind = .PATH, path = "../lint-plugin"}, module = .{path = "src", name = "Lint", alias = "LintAlias"}, options = .[.{key = "mode", value = "strict"}]},
    ],
    dependencies = Dependency.[
        .{name = "dep_a", source = .{kind = .PATH, path = "../a"}, modules = .[.{path = "lib", name = "Api", alias = "LocalApi"}]},
        .{name = "dep_b", source = .{kind = .GIT, git = .{url = "https://example.test/dep-b.git", tag = "v1"}}},
        .{name = "dep_member", source = .{kind = .WORKSPACE}, modules = .[.{path = "packages/b", name = "Bee", alias = "BeeAlias"}]},
    ],
    workspace = .{members = string.["packages/a", "packages/b"], exclude = string.["packages/skip"], default_members = string.["packages/a"]},};
