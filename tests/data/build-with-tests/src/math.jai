add :: (a: s64, b: s64) -> s64 {
    return a + b;
}

test "addition" {
    assert(add(2, 3) == 5);
}
