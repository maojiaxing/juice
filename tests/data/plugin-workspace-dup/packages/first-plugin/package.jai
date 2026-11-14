#import "Juice";

// A LIB member whose extra.jai is its only public module and carries the
// plugin anchor. The module name is declared; the file stem ("extra") never
// becomes an import name.
PACKAGE :: Package.{
    version = "0.1.0",
    modules = .[.{name = "first_plugin_module", entry = "extra.jai"}],
    name    = "first-plugin",

};
