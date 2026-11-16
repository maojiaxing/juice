#import "Juice";

// A LIB member whose root module.jai carries a plugin anchor.
PACKAGE :: Package.{
    version = "0.1.0",
    modules = .[.{name = "zeta_plugin", entry = "module.jai"}],
    name    = "zeta-plugin",

};
