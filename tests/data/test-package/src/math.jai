#import "Basic";
#import "Testing";

add :: (a: s64, b: s64) -> s64 {
    return a + b;
}

test "addition" {
    expect_eq(add(2, 3), 5);
}

test "addition with negatives" {
    expect_eq(add(-2, -3), -5);
}
