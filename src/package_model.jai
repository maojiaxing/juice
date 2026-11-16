// Runtime-only declarations. This file is not part of the published Juice module.
Declared_Product :: struct {
    name: string;
    entry: string;
    name_present: bool = true;
}
Source_Reference :: struct {
    kind: Juice.Source_Kind;
    path: string;
    url: string;
    branch: string;
    tag: string;
    rev: string;
}
Module_Reference :: struct {
    path: string = ".";
    name: string;
    alias: string;
}
Dependency_Reference :: struct {
    name: string;
    source: Source_Reference;
    modules: [] Module_Reference;
    modules_omitted: bool = true;
}
Plugin_Reference :: struct {
    id: string;
    builtin: bool;
    source: Source_Reference;
    module: Module_Reference;
    options: [] Juice.Plugin_Option;
}
Workspace_Declaration :: struct {
    members: [] string;
    exclude: [] string;
    default_members: [] string;
    default_members_omitted: bool = true;
}
Declaration_Field :: struct {
    path: string;
    value: string;
    protocol_line: int;
}
Normalized_Package :: struct {
    name: string;
    version: string;
    description: string;
    dir: string;
    has_package: bool = true;
    has_workspace: bool;
    modules: [] Declared_Product;
    executables: [] Declared_Product;
    modules_omitted: bool = true;
    executables_omitted: bool = true;
    dependencies: [] Dependency_Reference;
    plugins: [] Plugin_Reference;
    plugins_omitted: bool = true;
    workspace: Workspace_Declaration;
    default_run: string;
    fields: [] Declaration_Field;
}
Effective_Target :: struct {
    name: string;
    main_file: string;
    source_path: string;
}
Artifact_Plan :: struct {
    target: Effective_Target;
    target_dir: string;
    artifact_path: string;
}
Workspace_Discovery :: struct {
    root_dir: string;
    has_declaration: bool;
    has_workspace: bool;
    has_package: bool;
    packages: [] Normalized_Package;
    packages_root: string;
    selected_packages: [] Normalized_Package;
    selection_error: string;
    root_package: Normalized_Package;
    member_packages: [] Normalized_Package;
}
Prepared_Workspace :: struct {
    discovery: Workspace_Discovery;
    artifact_plans: [] Artifact_Plan;
    dependencies_prepared: bool;
    // The resolution environment the preparation ran with (ticket 0092: the
    // plugin source resolution reuses the dependency resolution environment, so
    // a plugin Git source and a dependency Git source behave identically). The
    // command layer fills it before preparation; plugins never derive it from a
    // process-global value.
    environment: Resolution_Environment;
    // Publication is deferred out of the resolution itself (spec 0087
    // decision 15): the resolution computes the selections and shims, but the
    // command commits them only after every applicable validation — the
    // package's declarations, its plugin role/identity checks and the member
    // plugin values' ABI/options — has passed. A failure before the commit
    // leaves the previous resolution state untouched, so a broken new
    // selection never replaces a working record.
    pending_selections: [..] Resolved_Selection;
    pending_consumer_root: string;
    pending_environment: Resolution_Environment;
    pending_publication: bool;
}

// Command selection request (spec 0087 decision 18). The mutual exclusion of
// --workspace against -p/--package and --package-path is structural: one
// flag selects all members, the two lists select by package name and by
// workspace-relative directory.
Package_Selection_Request :: struct {
    all_members: bool;
    names: [] string;
    paths: [] string;
}

// The validated result the command layer consumes: the selected packages in
// stable workspace-relative directory order, with their workspace-relative
// directories parallel to the package list. Failure carries one diagnostic;
// no partial selection is published.
Package_Selection :: struct {
    success: bool;
    packages: [] Normalized_Package;
    paths: [] string;
    error: string;
}
