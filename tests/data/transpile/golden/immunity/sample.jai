test :: () -> void { print("not a test\n"); }
test_string := "test \"fake\" { }";
// test "commented" { }
/* test "blocked" { } */
if ready test { work(); }
test(x);
y := test;

test "real" { body(); }
