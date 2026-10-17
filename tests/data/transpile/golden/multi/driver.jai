#import "Basic";

#load "<abs>/target/transpile/50c0784e37f8e5ca/multi/a_root.jai";
#load "<abs>/target/transpile/a9dc94e936fda937/multi/b_root.jai";
#load "<abs>/target/transpile/464be42ced433e3a/multi/sub/c.jai";

#import "Testing";

#run {
    array_reset(*path_mapping);
    array_add(*path_mapping, .{ view = "<abs>/target/transpile/50c0784e37f8e5ca/multi/a_root.jai", original = "multi/a_root.jai" });
    array_add(*path_mapping, .{ view = "<abs>/target/transpile/a9dc94e936fda937/multi/b_root.jai", original = "multi/b_root.jai" });
    array_add(*path_mapping, .{ view = "<abs>/target/transpile/464be42ced433e3a/multi/sub/c.jai", original = "multi/sub/c.jai" });
    run("root answer", juice_test_1);
    run("multi/a_root.jai:11", juice_test_2);
    run("file b after a", juice_test_3);
    run("deep directory test", juice_test_4);
    if finish() != 0 assert(false);
}
