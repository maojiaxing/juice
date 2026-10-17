// The juice test block file (the mixed-package surface): juice's own test
// mechanism handles it — the jaix pre-step leaves it out of the mirror (jaix
// cannot parse test blocks without its test block plugin, which the marker
// config excludes), and `juice test` discovers it from the original. The
// double() tests below execute the try/catch lowering: the test program
// compiles calc.jai's mirror view (the lowered code), and program-level
// scope makes the procs visible here without a #load (juice test compiles
// every discovered file into one program; the EXPAND views strip in-package
// #loads).
#import "Testing";

add :: (a: s32, b: s32) -> s32 {
    return a + b;
}

test "demo addition" {
    expect_eq(add(2, 3), 5);
}

test "demo double success" {
    err, value := double(10);
    expect(err == .NONE);
    expect_eq(value, 20);
}

test "demo double negative" {
    err, value := double(-6);
    expect(err == .NEGATIVE);
    expect_eq(value, 0);
}
