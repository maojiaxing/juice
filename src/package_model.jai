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
    root_package: Normalized_Package;
    member_packages: [] Normalized_Package;
}
Prepared_Workspace :: struct {
    discovery: Workspace_Discovery;
    artifact_plans: [] Artifact_Plan;
    dependencies_prepared: bool;
}
