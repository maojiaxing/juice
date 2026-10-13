#import "Basic";

#load "<abs>/target/transpile/edd4dba4a8bd02ba/test-free/sample.jai";

#import "Testing";

#run {
    array_reset(*path_mapping);
    array_add(*path_mapping, .{ view = "<abs>/target/transpile/edd4dba4a8bd02ba/test-free/sample.jai", original = "test-free/sample.jai" });
    if finish() != 0 assert(false);
}
