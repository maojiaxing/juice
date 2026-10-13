#import "Basic";

#load "<abs>/target/transpile/f483c96e502c0cb6/loads/sample.jai";

#import "Testing";

#run {
    array_reset(*path_mapping);
    array_add(*path_mapping, .{ view = "<abs>/target/transpile/f483c96e502c0cb6/loads/sample.jai", original = "loads/sample.jai" });
    run("uses helpers", juice_test_1);
    if finish() != 0 assert(false);
}
