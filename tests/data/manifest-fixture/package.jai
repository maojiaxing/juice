#import "Juice";

// E2E manifest fixture for the evaluator protocol (ticket 007): declares
// every protocol record kind so the real-jai-child round trip can be
// asserted field by field. The expected protocol text lives in
// tests/manifest_tests.jai's FULL_PROTOCOL constant — keep the two in sync.
PACKAGE :: Package.{
    name         = "manifest-fixture",
    version      = "1.2.3",
    type         = .BIN,
    description  = "Evaluator protocol E2E fixture.",
    build_script = "build.py",

    plugins = .[
        .{ id = "load",       version = "1" },
        .{ id = "test-block", version = "2" },
    ],

    targets     = Target.[
        .{ name = "app", main_file = "src/main.jai" },
    ],

    dependencies = Dependency.[
        .{ name = "dep_a", version = "0.1", source = "",          package = "" },
        .{ name = "dep_b", version = "0.2", source = "../sibling", package = "renamed" },
    ],

    workspace   = .{ members = string.["packages/a", "packages/b"], exclude = string.["packages/skip"] },
};
