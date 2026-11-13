#import "Basic";

// The host-side replacement for src/main.jai (ticket 060 fixture). The dot
// directory keeps it out of the test file collection (dot entries are
// excluded at any depth) and out of plugin scans — the hook points the
// substitution at this absolute path.
main :: () {
    print("prestep replacement entry\n");
}
