#import "Basic";


Package_Type :: enum {
    LIB;
    BIN;
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
Artifact_Plan :: struct {
    target:      Effective_Target;
    result_dir:  string;
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

Package :: struct {
    name:         string;
    version:      string;
    type:         Package_Type = .BIN;
    description:  string = "";

    targets:      [] Target;
    root_file:    string = "modulejai";

    dependencies: [] Dependency;
    workspace:    Workspace_Config;
    build_script: string = "";

    // Set by the manifest loader; it is not declared in package.jai.
    dir:          string = "";
}

// Filesystem-independent discovery result. member_paths are validated absolute
// package directories, with the root directory first.
Workspace_Discovery :: struct {
    root_dir:     string;
    has_package:  bool;
    root_package: Package;
    member_paths: [] string;
}

// State shared by command handlers after discovery, resolution, and (if
// necessary) dependency preparation have completed.
Prepared_Workspace :: struct {
    discovery:     Workspace_Discovery;
    artifact_plans: [] Artifact_Plan;
    dependencies_prepared: bool;
}
