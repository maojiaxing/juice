#import "Basic";


// UNSPECIFIED means the role is derived from convention during target
// resolution: src/main.jai (or declared targets) means BIN; an import entry
// means LIB; anything else stays BIN.
Package_Type :: enum {
    LIB;
    BIN;
    UNSPECIFIED;
}

// Raw target declaration as written by package.jai.
Target :: struct {
    name:       string;
    main_file:  string;
}

// A target after defaults and filesystem validation have been applied.
Effective_Target :: struct {
    name:       string;
    main_file:  string;
    source_path: string;
}

// The complete output contract consumed by Build and Run.
// target_dir is the package's unified target/ directory root; the artifact
// lands directly inside it (no profile sublayers).
Artifact_Plan :: struct {
    target:      Effective_Target;
    target_dir:  string;
    artifact_path: string;
}

Dependency :: struct {
    name:    string;
    version: string = "";
    source:  string = "";
    package: string = "";
}

Workspace_Config :: struct {
    members: [] string;
    exclude: [] string;
}

// Optional jaix pre-step marker. config is the package-relative path to the
// jaix configuration; an empty config means the pre-step is not enabled.
// exe overrides the jaix executable; an empty exe means a PATH lookup of
// "jaix". Both default to empty, so packages that never declare the marker
// are unaffected.
Jaix_Prestep :: struct {
    config: string;
    exe:    string = "";
}

// One option row of a transpile plugin declaration (spec 0060 decision 6).
// v1: both built-in plugins' option sets are empty — no legal rows exist,
// and the manifest validation gate rejects any declaration carrying rows.
// The typed slot is in place so future option surfaces land here as typed
// members; options never cross the manifest protocol (id+version only — the
// jaix "options don't cross the process boundary" stance).
Transpile_Plugin_Option :: struct {
    key:   string;
    value: string;
}

// One transpile pipeline plugin declaration (spec 0060 decision 6): the
// plugin identity (id + version — feeds the pipeline description and the
// cache key) plus the typed options slot. Declaration order = pipeline
// order. The built-in plugin ids are the v1 legal declaration set
// (TRANSPILE_PLUGIN_LOAD_ID / TRANSPILE_PLUGIN_TEST_BLOCK_ID).
Transpile_Plugin_Declaration :: struct {
    id:      string;
    version: string;
    options: [] Transpile_Plugin_Option;
}

// The package's transpile pipeline declaration. An empty plugins list means
// the default pipeline (the two built-in plugins in their default order) —
// undeclared packages keep today's behavior exactly. Slice fields so
// package.jai authors can write `.{ plugins = .[ .{...}, .{...} ] }`
// (fixed-array literals decay to slices at assignment, the Package struct's
// house style).
Transpile_Pipeline_Declaration :: struct {
    plugins: [] Transpile_Plugin_Declaration;
}

// The v1 built-in transpile plugin ids: the legal declaration ids. The
// built-in registry in src/transpile_plugin.jai uses the same literals as
// plugin names (bootstrap load order keeps the two files from sharing
// declarations; the src/transpile_config.jai inline tests lock them in
// sync).
TRANSPILE_PLUGIN_LOAD_ID       :: "load";
TRANSPILE_PLUGIN_TEST_BLOCK_ID :: "test-block";

Package :: struct {
    name:         string;
    version:      string;
    type:         Package_Type = .UNSPECIFIED;
    description:  string = "";

    targets:      [] Target;

    dependencies: [] Dependency;
    workspace:    Workspace_Config;
    build_script: string = "";

    // jaix pre-step marker; an empty config disables the pre-step.
    jaix:         Jaix_Prestep;

    // transpile pipeline declaration (spec 0060 decision 6); an empty
    // plugins list means the default pipeline.
    transpile:    Transpile_Pipeline_Declaration;

    // Set by the manifest loader; it is not declared in package.jai.
    dir:          string = "";
}

// Discovery retains the evaluated declarations, including the root first.
// Dependencies consume this snapshot rather than executing member manifests again.
Workspace_Discovery :: struct {
    root_dir:        string;
    has_package:     bool;
    root_package:    Package;
    member_packages: [] Package;
}

// State shared by command handlers after discovery, resolution, and (if
// necessary) dependency preparation have completed.
Prepared_Workspace :: struct {
    discovery:     Workspace_Discovery;
    artifact_plans: [] Artifact_Plan;
    // The package role after UNSPECIFIED has been resolved by convention.
    package_type:  Package_Type;
    dependencies_prepared: bool;
}
