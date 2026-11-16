#import "Juice";

// A LIB member whose extra.jai is its only public module — the same file name
// as first-plugin's, declared under a different module name.
PACKAGE :: Package.{
    version = "0.1.0",
    modules = .[.{name = "second_plugin_module", entry = "extra.jai"}],
    name    = "second-plugin",

};
