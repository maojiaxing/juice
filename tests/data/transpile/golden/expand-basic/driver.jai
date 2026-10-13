#import "Basic";

#load "<abs>/target/transpile/997dcb6f5a40cb22/expand-basic/sample.jai";

#import "Testing";

#run {
    array_reset(*path_mapping);
    array_add(*path_mapping, .{ view = "<abs>/target/transpile/997dcb6f5a40cb22/expand-basic/sample.jai", original = "expand-basic/sample.jai" });
    run("addition", juice_test_1);
    run("expand-basic/sample.jai:7", juice_test_2);
    run("one line", juice_test_3);
    if finish() != 0 assert(false);
}
