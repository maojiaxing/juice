#import "Juice";

// E2E protocol-error fixture (ticket 014): the type enum is cast to a value
// outside the legal 0/1/2 set — the evaluator child faithfully prints
// TYPE=7 (data line 3) and the parent's strict parser rejects it: the
// parent never trusts the child's data, even from a declaration that
// compiles (byte-locked by manifest_tests.jai's bad-manifest E2E section).
PACKAGE :: Package.{
    name    = "bad_type",
    version = "0.1.0",
    type    = cast(Package_Type) 7,
};
