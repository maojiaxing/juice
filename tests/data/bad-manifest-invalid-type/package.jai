#import "Juice";

// Retired public fields must be rejected by the real declaration compiler.
// Keep the value well-typed so the diagnostic identifies the removed member.
PACKAGE :: Package.{
    name    = "bad_type",
    version = "0.1.0",
    type    = 7,
};
