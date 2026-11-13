#import "Juice";

// The jaix pre-step plugin member package (ticket 061, parent effort
// jaix-plugin-map Phase 2): the real workspace member the root declares as
// `juice-plugin-jaix`. Directory name = Package.name = module name — the
// root module.jai entry convention (its #import name is the package
// directory name, spec section 3).
//
// LIB with no targets and no dependencies (the distribution contract, spec
// §3.3/§11.11): the package is a plain, copyable source member. `juice_core`
// is the tool-provided module face — the installed executable resolves it
// from its adjacent modules/ directory on every compile subprocess's import
// path — so the package declares no dependency for it and carries no path
// into a juice checkout. In the root workspace the member is made
// discoverable by workspace.members and activated by the root's
// Package.plugins declaration (declaration = activation; dependencies never
// activate plugins); run alone, the member root is its own package (no
// plugin declarations) and resolves the face from the tool that runs it.
PACKAGE :: Package.{
    name    = "juice-plugin-jaix",
    version = "0.1.0",
    type    = .LIB,
};
