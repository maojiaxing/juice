#import "Basic";

// The load-bearing "Juice" module face, imported as a namespace (how_to
// 040's Math :: #import "Math" form). A bare #import would link the module's
// declarations (Package, Target, ...) into the application scope of every
// program that loads this file — and old juice's test program compiles the
// whole package in one application scope, where src/module.jai already
// declares the same names as otter's own definition source. The two copies
// would clash with a redeclaration error (verified by spike); the qualified
// form keeps the module's links inside its own namespace.
//
// The module name "Juice" stays load-bearing: this import resolves through
// the import directories to otter's own published directory module
// (target/modules/Juice/module.jai, spec section 9.4). Consumers write
// Juice.Package, Juice.Target, etc.
//
// This file must be #loaded before every consumer (main.jai's #load list;
// in the test program the full-package scan's lexical order already puts
// it first among src files).
Juice :: #import "Juice";
