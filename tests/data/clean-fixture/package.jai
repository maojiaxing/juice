#import "Juice";

// The clean E2E fixture: a root package with two workspace members. Clean
// discovers the workspace (never prepares it — no dependency or plan
// resolution) and removes every package's own target/ directory (spec
// section 3.5). The fixture never commits target/; test junk is
// manufactured at runtime.
PACKAGE :: Package.{
    name    = "clean_fixture",
    version = "0.1.0",
    type    = .BIN,
    workspace = .{
        members = string.["member_lib", "member_extra"],
    },
};
