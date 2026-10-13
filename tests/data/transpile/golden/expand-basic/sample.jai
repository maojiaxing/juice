#import "Basic";

test "addition" {
    expect(2, 2);
}

test {
    x := 1;
    defer cleanup();
} // trailing comment

test "one line" { body(); }
