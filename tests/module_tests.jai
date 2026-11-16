#import "Basic";
#import "Testing";

// These are declaration vocabulary tests, not Testing's behavior suite.
// Test discovery loads src/module.jai into the application scope.

test "Face: omitted and explicit empty Package values remain distinct" {
    omitted: Package;
    empty: Package = .{name = "", version = "", description = "", modules = .[], executables = .[], dependencies = .[], plugins = .[], workspace = .{}, default_run = ""};
    expect(omitted.name != empty.name);
    expect(omitted.version != empty.version);
    expect(omitted.description != empty.description);
    expect(omitted.default_run != empty.default_run);
    expect(omitted.modules.count != empty.modules.count);
    expect(omitted.executables.count != empty.executables.count);
    expect(omitted.dependencies.count != empty.dependencies.count);
    expect(omitted.plugins.count != empty.plugins.count);
    expect(omitted.workspace.members[0] != empty.workspace.members[0]);
}

test "Face: Source selects PATH GIT or WORKSPACE explicitly" {
    source: Source;
    expect(source.kind == .UNSPECIFIED);
    source = .{kind = .PATH, path = "../library"};
    expect(source.kind == .PATH && source.path == "../library");
    source = .{kind = .GIT, git = .{url = "repo", rev = "commit"}};
    expect(source.kind == .GIT && source.git.url == "repo" && source.git.rev == "commit");
    source = .{kind = .WORKSPACE};
    expect(source.kind == .WORKSPACE);
}

test "Face: Dependency uses a source and flat module selections" {
    dependency: Dependency = .{name = "reference", source = .{kind = .PATH, path = "../provider"}, modules = .[.{path = "library", name = "Api", alias = "Local"}]};
    expect(dependency.name == "reference");
    expect(dependency.source.kind == .PATH && dependency.source.path == "../provider");
    expect(dependency.modules.count == 1);
    expect(dependency.modules[0].path == "library" && dependency.modules[0].name == "Api" && dependency.modules[0].alias == "Local");
}

test "Face: a full literal declaration round-trips" {
    package: Package = .{
        name = "face-fixture", version = "0.9.0", description = "A full declaration.",
        modules = .[.{name = "Api", entry = "src/module.jai"}],
        executables = .[.{name = "app", entry = "src/main.jai"}], default_run = "app",
        plugins = .[.{builtin = "load"}, .{builtin = "test-block"}],
        dependencies = .[.{name = "dep_a", source = .{kind = .PATH, path = "../a"}}, .{name = "dep_b", source = .{kind = .WORKSPACE}, modules = .[.{path = "packages/b", name = "B", alias = "Bee"}]}],
        workspace = .{members = .["packages/a", "packages/b"], exclude = .["packages/skip"], default_members = .["packages/a"]},
    };
    expect(package.name == "face-fixture");
    expect(package.version == "0.9.0");
    expect(package.description == "A full declaration.");
    expect(package.modules.count == 1);
    expect(package.modules[0].name == "Api");
    expect(package.modules[0].entry == "src/module.jai");
    expect(package.executables.count == 1);
    expect(package.executables[0].name == "app");
    expect(package.executables[0].entry == "src/main.jai");
    expect(package.default_run == "app");
    expect(package.plugins.count == 2);
    expect(package.plugins[0].builtin == "load");
    expect(package.plugins[1].builtin == "test-block");
    expect(package.plugins[0].options.count == 0);
    expect(package.dependencies.count == 2);
    expect(package.dependencies[0].name == "dep_a");
    expect(package.dependencies[1].name == "dep_b");
    expect(package.dependencies[1].modules[0].alias == "Bee");
    expect(package.workspace.members.count == 2);
    expect(package.workspace.members[0] == "packages/a");
    expect(package.workspace.members[1] == "packages/b");
    expect(package.workspace.exclude.count == 1 && package.workspace.exclude[0] == "packages/skip");
    expect(package.workspace.default_members.count == 1 && package.workspace.default_members[0] == "packages/a");
}

test "Face: built-in plugin id constants" {
    expect(TRANSPILE_PLUGIN_LOAD_ID == "load");
    expect(TRANSPILE_PLUGIN_TEST_BLOCK_ID == "test-block");
}

test "Face: plugin declaration options are typed rows" {
    declaration: Plugin_Declaration = .{builtin = "load", options = .[.{key = "k", value = "v"}]};
    expect(declaration.options.count == 1);
    expect(declaration.options[0].key == "k");
    expect(declaration.options[0].value == "v");
}
