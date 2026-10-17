#import "Basic";
#import "Testing";

#load "math.jai";

main :: () {
    print("hello from pipeline-explicit\n");
}

add :: (a: s32, b: s32) -> s32 {
    return a + b;
}

test "explicit pipeline addition" {
    expect_eq(add(2, 3), 5);
}
