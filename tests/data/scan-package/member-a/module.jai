#import "Basic";
#import "Testing";

member_helper :: () -> s64 {
    return 7;
}

// This dependency source's tests must never run in the root package's
// `juice test`; they run only when member-a is its own package root.
test "member test" {
    expect_eq(member_helper(), 7);
}
