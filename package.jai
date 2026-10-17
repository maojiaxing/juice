#import "Juice";

// Juice bootstrap: the repository itself is a BIN package whose target is
// its own entry, so `juice test` runs at the repository root (test consumes
// the prepared workspace through the workspace preparation call).
PACKAGE :: Package.{
    name    = "juice",
    version = "0.1.0",
    type    = .BIN,
    targets = Target.[
        .{name = "juice", main_file = "src/main.jai"},
    ],
};
