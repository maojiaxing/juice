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
