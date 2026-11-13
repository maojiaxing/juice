#import "Basic";

// The greeting face plus two test blocks: a named block (the global
// numbering starts here — greet.jai is the first file in scan order) and
// an anonymous block (numbered juice_test_2 by the EXPAND pass; its report
// name is the generated procedure name — ticket 028 deviation).

greeting :: () -> string {
    return "hello";
}

test "greeting" {
    expect_eq(greeting(), "hello");
}

test {
    expect(true);
}
