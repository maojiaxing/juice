#import "Juice";

// A LIB member whose root module.jai carries one plugin anchor; the module is
// declared explicitly, so the anchor's file name never becomes an import name.
PACKAGE :: Package.{
    version = "0.1.0",
    modules = .[.{name = "alpha_first_plugin", entry = "module.jai"}],
    name    = "alpha-first",

};
