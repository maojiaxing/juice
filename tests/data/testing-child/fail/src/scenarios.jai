#import "Basic";
#import "Testing";

test "aborts" {
    expect(false);
    print("reached\n");
}

test "eq-fails" {
    expect_eq(3, 5);
}

test "named-failure" {
    fail("boom");
}

test "prints-message" {
    expect(false, "got % and %", 7, 9);
}

test "custom-eq" {
    expect_eq(3, 5, "custom mismatch");
}
