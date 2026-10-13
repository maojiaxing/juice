#import "Basic";
#import "Testing";

#load "math.jai";

main :: () {
    print("hello from test-package\n");
}

greet :: (name: string) -> string {
    return tprint("hello, %", name);
}

test "greeting" {
    expect_eq(greet("world"), "hello, world");
}

test {
    expect(1 < 2);
}
