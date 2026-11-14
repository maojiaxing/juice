#import "Juice";

// A LIB member exporting TWO public modules: the plugin module (module.jai)
// and a plain helper (helper.jai). A declaration that omits the module name is
// ambiguous here; naming extra_plugin selects the plugin entry.
PACKAGE :: Package.{
    version = "0.1.0",
    modules = .[
        .{name = "extra_plugin", entry = "module.jai"},
        .{name = "extra_helper", entry = "helper.jai"},
    ],
    name    = "extra",

};
