// Fixture plugin anchor (scan-only; the root module.jai derives the module
// name "alpha-first" from the package directory name). It gives the
// first-declared package a surviving hit that must stay ahead of the later
// package's lower-rank "extra" winner — the declaration-order position pin
// (040 review fix).
get_juice_plugin :: () -> *X { return null; } @juice_plugin
