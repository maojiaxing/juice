#import "Basic";

#load "<abs>/target/transpile/d690f0db31cf3337/one-line/sample.jai";

#import "Testing";

#run {
    array_reset(*path_mapping);
    array_add(*path_mapping, .{ view = "<abs>/target/transpile/d690f0db31cf3337/one-line/sample.jai", original = "one-line/sample.jai" });
    run("fast", juice_test_1);
    run("a", juice_test_2);
    run("b", juice_test_3);
    if finish() != 0 assert(false);
}
