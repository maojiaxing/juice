#import "Juice";

// A LIB member whose plugin anchor lives in extra.jai — the same file stem as
// packages/extra's entry file, which no longer matters: the declaration selects
// this package's zeta_plugin module by name.
PACKAGE :: Package.{
    version = "0.1.0",
    modules = .[.{name = "zeta_plugin", entry = "extra.jai"}],
    name    = "zeta-extra",

};
