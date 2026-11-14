#import "Juice";

// A LIB member named "alpha-first" whose root module.jai carries one plugin
// anchor (probe rank 1 — the package directory name is the derived module
// name). Declared first: its surviving hit pins the declaration-order
// position the later "extra" winner must follow.
PACKAGE :: Package.{
    version = "0.1.0",
    modules = .[.{name = "alpha_first", entry = "module.jai"}],
    name    = "alpha-first",

};
