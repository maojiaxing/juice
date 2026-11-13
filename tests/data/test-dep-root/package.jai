#import "Juice";

// The t11 dependency-strip fixture (ticket 028): the root package depends
// on a local library whose closure contains a test block — the dependency
// strip front (the shared prepare_dependency_strip_views, ticket 027)
// rewrites the shim to the entry strip view, so the dependency's tests are
// neither discovered nor executed (spec US 18).

PACKAGE :: Package.{
    name    = "test-dep-root",
    version = "0.1.0",
    type    = .BIN,
    dependencies = Dependency.[
        .{name = "test_dep", source = "../test-dep-lib"},
    ],
};
