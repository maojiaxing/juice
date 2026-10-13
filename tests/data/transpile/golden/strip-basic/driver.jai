#import "Basic";

#load "<abs>/target/transpile/7bf4e510393d7e64/src/main.jai";

#import "Testing";

#run {
    array_reset(*path_mapping);
    array_add(*path_mapping, .{ view = "<abs>/target/transpile/7bf4e510393d7e64/src/main.jai", original = "src/main.jai" });
    if finish() != 0 assert(false);
}
