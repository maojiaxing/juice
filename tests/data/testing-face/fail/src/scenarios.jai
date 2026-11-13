// Testing-face child scenario fixture (ticket 016, published single-face
// shape since ticket 036): the fail scenario. Five failing bodies — abort
// semantics, expect_eq mismatch, the unconditional fail, a formatted
// message and the custom expect_eq message. The bodies call the bare names
// of the published Testing face; the parent computes the expected failure
// coordinates from these lines.

aborts :: () {
    expect(false);
}

eq_fails :: () {
    expect_eq(3, 5);
}

named_failure :: () {
    fail("boom");
}

prints_message :: () {
    expect(false, "got % and %", 7, 9);
}

custom_eq :: () {
    expect_eq(3, 5, "custom mismatch");
}
