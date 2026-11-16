#import "Basic";

// The Juice package declaration vocabulary: the exact declarations a package
// author writes against in package.jai (`PACKAGE :: Package.{...}`).
//
// This is a publication source directory, not a package: it has no package.jai,
// is not a workspace member, and is never imported by name as a package. The
// publish step reads this file and emits it verbatim behind the standard import
// line as the installed "Juice" module. juice's own compilation unit reaches it
// through src/module.jai, which loads it for the bare declaration names
// (src/manifest.jai evaluates a Package value directly).
//
// Declaration input only. Runtime models live in src/package_model.jai.
// The control-character defaults are reserved implementation values; ordinary
// empty strings and empty lists remain explicit input.
Product :: struct {
    name: string = "\x01juice-omitted";
    entry: string = "\x01juice-omitted";
}
Source_Kind :: enum { UNSPECIFIED; PATH; GIT; WORKSPACE; }
Git_Source :: struct {
    url: string = "\x01juice-omitted";
    branch: string = "\x01juice-omitted";
    tag: string = "\x01juice-omitted";
    rev: string = "\x01juice-omitted";
}
Source :: struct {
    kind: Source_Kind;
    path: string = "\x01juice-omitted";
    git: Git_Source;
}
Module_Selection :: struct {
    path: string = "\x01juice-omitted";
    name: string = "\x01juice-omitted";
    alias: string = "\x01juice-omitted";
}
Dependency :: struct {
    name: string = "\x01juice-omitted";
    source: Source;
    modules: [] Module_Selection = .[.{}];
}
Workspace_Config :: struct {
    members: [] string = .["\x01juice-omitted"];
    exclude: [] string = .["\x01juice-omitted"];
    default_members: [] string = .["\x01juice-omitted"];
}
Plugin_Option :: struct {
    key: string;
    value: string;
}
Plugin_Declaration :: struct {
    id: string = "\x01juice-omitted";
    builtin: string = "\x01juice-omitted";
    source: Source;
    module: Module_Selection;
    options: [] Plugin_Option;
}
TRANSPILE_PLUGIN_LOAD_ID :: "load";
TRANSPILE_PLUGIN_TEST_BLOCK_ID :: "test-block";
Package :: struct {
    name: string = "\x01juice-omitted";
    version: string = "\x01juice-omitted";
    description: string = "\x01juice-omitted";
    modules: [] Product = .[.{}];
    executables: [] Product = .[.{}];
    dependencies: [] Dependency = .[.{}];
    plugins: [] Plugin_Declaration = .[.{}];
    workspace: Workspace_Config = .{members = .["\x01juice-workspace-omitted"]};
    default_run: string = "\x01juice-omitted";
}
