#import "Juice";

// A LIB member whose root module.jai carries a plugin anchor.
PACKAGE :: Package.{
    version = "0.1.0",
    modules = .[.{name = "alpha_plugin", entry = "module.jai"}],
    name    = "alpha-plugin",

};
