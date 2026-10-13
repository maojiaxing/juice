#import "Basic";
#import "Testing";

add :: (a: s64, b: s64) -> s64 {
    return a + b;
}

test "broken math" {
    expect_eq(add(2, 3), 99);
}
