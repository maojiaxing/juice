#import "Basic";

juice_test_1 :: () -> () {
    expect(2, 2);
} @test

juice_test_2 :: () -> () {
    x := 1;
    defer cleanup();
} @test // trailing comment

juice_test_3 :: () -> () { body(); } @test
