// Testing-face child scenario fixture (ticket 016, published single-face
// shape since ticket 036): the mapped scenario. One failing body calls the
// bare names of the published Testing face — the generated driver injects
// a path_mapping entry that rewrites this file's absolute path to the
// package-relative "src/scenarios.jai", so the failure line reports the
// mapped coordinates.

mapped_fail :: () {
    expect(2 + 2 == 5);
}
