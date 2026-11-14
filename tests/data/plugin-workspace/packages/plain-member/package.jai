#import "Juice";

// A LIB member without plugin anchors that is NOT declared in the root's
// Package.plugins: the declaration-driven scan never touches it (the v1
// scan surface is the declaration list, not the member list).
PACKAGE :: Package.{
    version = "0.1.0",
    modules = .[.{name = "plain_member", entry = "module.jai"}],
    name    = "plain-member",

};
