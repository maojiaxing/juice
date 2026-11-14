#import "Juice";

// The t11 dependency-strip fixture (ticket 028): the root package depends
// on a local library whose closure contains a test block — the dependency
// strip front (the shared prepare_dependency_strip_views, ticket 027)
// rewrites the shim to the entry strip view, so the dependency's tests are
// neither discovered nor executed (spec US 18).

PACKAGE :: Package.{
    executables = .[.{name = "test_dep_root", entry = "src/main.jai"}],
    version = "0.1.0",
    name    = "test-dep-root",

    dependencies = Dependency.[
        .{name = "test_dep", source = .{kind = .PATH, path = "../test-dep-lib"}},
    ],
};
