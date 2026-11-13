// Testing-face child scenario fixture (ticket 016, published single-face
// shape since ticket 036): the pass scenario. The bodies call the bare
// names of the published Testing face — the same shape an old-juice-style
// user package writes (`#import "Testing"` plus bare assertions). The
// generated driver imports the published face and runs this list.

addition :: () {
    expect(1 + 1 == 2);
}

equality :: () {
    expect_eq("abc", "abc");
}
