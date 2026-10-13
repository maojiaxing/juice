#import "Basic";
#import "Testing";

lib_add :: (a: s64, b: s64) -> s64 {
    return a + b;
}

test "lib arithmetic" {
    expect_eq(lib_add(2, 3), 5);
}

test "lib strings" {
    expect_eq("juice", "juice");
}

test {
    expect(true);
}
