#import "Basic";

answer :: () -> s64 {
    return 42;
}

juice_test_1 :: () -> () {
    expect_eq(answer(), 42);
} @test

juice_test_2 :: () -> () {
    expect(1 < 2);
} @test
