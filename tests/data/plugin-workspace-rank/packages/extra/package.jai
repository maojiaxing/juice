#import "Juice";

// A LIB member named "extra" whose root module.jai carries a plugin anchor
// (probe rank 1 — the package directory name is the derived module name).
PACKAGE :: Package.{
    name    = "extra",
    version = "0.1.0",
    type    = .LIB,
};
