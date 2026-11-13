#import "Juice";

// A LIB member without plugin anchors that is NOT declared in the root's
// Package.plugins: the declaration-driven scan never touches it (the v1
// scan surface is the declaration list, not the member list).
PACKAGE :: Package.{
    name    = "plain-member",
    version = "0.1.0",
    type    = .LIB,
};
