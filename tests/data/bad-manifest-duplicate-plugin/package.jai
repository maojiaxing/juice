#import "Juice";

// E2E protocol-error fixture (ticket 014; 2026-10-21 declaration rename):
// the declared plugin list repeats an id — the evaluator child prints both
// records and the parent's strict parser rejects the duplicate at data line
// 15 (the parser's line numbers count the data file's record order, not the
// manifest's; byte-locked by manifest_tests.jai's bad-manifest E2E section).
PACKAGE :: Package.{
    version = "0.1.0",
    name    = "bad_dup_plugin",
    plugins = .[
        .{builtin = "load" },
        .{builtin = "load" },
    ],
};
