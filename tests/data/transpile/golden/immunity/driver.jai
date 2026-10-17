#import "Basic";

#load "<abs>/target/transpile/4e6141a20ef3a569/immunity/sample.jai";

#import "Testing";

#run {
    array_reset(*path_mapping);
    array_add(*path_mapping, .{ view = "<abs>/target/transpile/4e6141a20ef3a569/immunity/sample.jai", original = "immunity/sample.jai" });
    run("real", juice_test_1);
    if finish() != 0 assert(false);
}
