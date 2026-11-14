#import "Juice";

PACKAGE :: Package.{
    name = "shim_pkg",
    version = "0.1.0",
    modules = .[.{name = "shim_pkg", entry = "src/module.jai"}],
    executables = .[],
};
