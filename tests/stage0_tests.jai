#import "Testing";

// Stage 0: this file proves the zero-special-casing invariant — old juice
// discovers and executes this test block on the otter root without any
// knowledge of otter. The assertion body is trivial on purpose; the test
// passing at all is the check.
test "stage 0: test discovery and execution on the otter root" {
    expect(1 + 1 == 2);
}
