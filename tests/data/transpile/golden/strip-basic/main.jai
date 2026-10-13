#import "Basic";
#load "helper.jai";
#load "../../outside.jai";

test "addition" {
    expect(2, 2);
}

test "one line" { body(); }

test "a" { } test "b" { }

main :: () {}
