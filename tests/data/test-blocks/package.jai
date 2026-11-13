#import "Juice";

// The 1c test-block fixture (ticket 028): the full-chain E2E package —
// test blocks EXPAND into juice_test_N + @test views, the note enumeration
// discovers them exactly like hand-written @test procedures (spec section
// 7.1, US 14), and the generated runner executes them at compile time. The
// test bodies assert through the published Testing face's bare names (the
// generated driver imports it — ticket 035's single register).

PACKAGE :: Package.{
    name    = "test-blocks",
    version = "0.1.0",
    type    = .BIN,
};
