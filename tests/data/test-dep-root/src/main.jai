#import "Basic";
#import "test_dep";

// The root package consumes the dependency through the import shim (the
// dependency's declarations enter the application scope via the shim's
// #load). The root's own test block runs through the EXPAND view; the
// dependency's test block must never appear in this test program.

use_dep :: () -> s32 {
    return dep_value();
}

test "dep usage" {
    expect_eq(use_dep(), 42);
}
