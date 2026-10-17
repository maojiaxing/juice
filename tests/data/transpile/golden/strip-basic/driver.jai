#import "Basic";

#load "<abs>/target/transpile/280cf4f6d2ad61a8/src/main.jai";

#import "Testing";

#run {
    array_reset(*path_mapping);
    array_add(*path_mapping, .{ view = "<abs>/target/transpile/280cf4f6d2ad61a8/src/main.jai", original = "src/main.jai" });
    if finish() != 0 assert(false);
}
