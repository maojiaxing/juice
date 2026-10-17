// jaix pre-step demo package: the jaix marker enables the pre-step — juice
// build jaix-transpiles the whole package into target/jaix/ (mirroring the
// package layout) and compiles the mirror entry view, so the try/catch
// extension syntax below builds through. config = package-relative path to
// the jaix configuration; exe stays empty = the "jaix" PATH lookup.
PACKAGE :: Package.{
    name    = "jaix-demo",
    version = "0.1.0",
    type    = .BIN,
    jaix    = .{ config = "jaix.config.jai" },
};
