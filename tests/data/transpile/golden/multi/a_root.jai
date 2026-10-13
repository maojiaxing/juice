#import "Basic";

answer :: () -> s64 {
    return 42;
}

test "root answer" {
    expect_eq(answer(), 42);
}

test {
    expect(1 < 2);
}
