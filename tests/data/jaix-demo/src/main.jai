// The entry: a literal in-package #load chain into calc.jai (the chain
// resolves inside the target/jaix/ mirror after the pre-step — the same
// package-relative structure, zero rewrites). No extension syntax here, so
// the mirror view is byte-identical to this file.
#import "Basic";

#load "calc.jai";

main :: () {
    e1, v1 := double(20);
    e2, v2 := double(-6);
    print("double(20): % %\n", e1, v1);
    print("double(-6): % %\n", e2, v2);
}
