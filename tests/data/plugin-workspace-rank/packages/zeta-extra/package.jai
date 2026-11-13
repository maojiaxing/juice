#import "Juice";

// A LIB member whose extra.jai carries one plugin anchor (probe rank 3).
// Declared second; its "extra" hit loses the cross-package probe-rank
// arbitration to packages/extra's module.jai and is dropped (the v1
// one-plugin-per-package rule keeps this package at one anchor).
PACKAGE :: Package.{
    name    = "zeta-extra",
    version = "0.1.0",
    type    = .LIB,
};
