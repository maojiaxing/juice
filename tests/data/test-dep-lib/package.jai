#import "Juice";

PACKAGE :: Package.{
    name = "test_dep",
    version = "0.1.0",
    modules = .[.{name = "test_dep", entry = "module.jai"}],
    executables = .[],
};
