// The dependency's test-bearing file: the test block is stripped from the
// closure view (the dependency-tests-neither-discovered-nor-executed face),
// so the Testing reference never reaches the test program.

extra_value :: () -> s32 {
    return 42;
}

test "dep self test" {
    fail("dependency test must never run");
}
