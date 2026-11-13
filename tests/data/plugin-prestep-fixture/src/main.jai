#import "Basic";

// The original entry (ticket 060 fixture): the member PRESTEP plugin's host
// substitutes this file with .prestep/main.jai, so the build artifact must
// print the replacement's line, not this one.
main :: () {
    print("original entry\n");
}
