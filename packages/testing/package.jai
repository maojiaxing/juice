#import "Juice";

PACKAGE: Package : .{
    name = "testing",
    version = "0.1.0",
    modules = .[.{name = "Testing", entry = "src/module.jai"}],
    executables = .[],
    plugins = .[],
};
