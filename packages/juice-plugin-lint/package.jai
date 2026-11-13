#import "Juice";

// Real third-party plugin member (ticket 044, parent 040 decisions 1/2/10):
// the repository's first packages/ member. Directory name = Package.name =
// module name — the root module.jai entry convention (its #import name is
// the package directory name, spec section 3).
//
// LIB with no targets and no dependencies (ticket 050, parent 048 decisions
// 9/10): the package is a plain, copyable source member. `juice_core` is the
// tool-provided module face — the installed executable resolves it from its
// adjacent modules/ directory on every compile subprocess's import path — so
// the package declares no dependency for it and carries no path into a juice
// checkout. In the root workspace the member is made discoverable by
// workspace.members and activated by the root's Package.plugins declaration
// (ticket 056 — declaration = activation; dependencies never activate
// plugins); run alone, the member root is its own package (no plugin
// declarations) and resolves the face from the tool that runs it.
PACKAGE :: Package.{
    name    = "juice-plugin-lint",
    version = "0.1.0",
    type    = .LIB,
};
