#load "extra.jai";

// The dependency entry: a test-bearing closure (extra.jai carries the test
// block), so the strip front views the whole closure and rewrites the
// consumer's shim to this file's strip view.

dep_value :: () -> s32 {
    return extra_value();
}
