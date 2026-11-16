#import "Juice";

// The fixture's member plugin package (ticket 060): a plain LIB workspace
// member with zero tool dependencies — juice_core is provided by the tool
// (the executable's adjacent modules directory), never declared as a DEP.
PACKAGE :: Package.{
    version = "0.1.0",
    modules = .[.{name = "prestep_plugin", entry = "module.jai"}],
    name    = "prestep-plugin",

};
