#import "Juice";

// E2E plugin-preparation-error fixture (ticket 014; 2026-10-21 declaration
// rename, ticket 056 takeover): an unknown plugin id — the manifest protocol
// parses clean (semantic validation moved out of the loader), then the
// declaration-driven workspace scan rejects the id (not a built-in and not a
// workspace member) during plugin preparation; byte-locked by
// manifest_tests.jai's bad-manifest E2E section.
PACKAGE :: Package.{
    name    = "bad_plugin_id",
    version = "0.1.0",
    plugins = .[
        .{ id = "mystery", version = "1" },
    ],
};
