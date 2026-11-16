// ---------------------------------------------------------------------------
// Publication contracts: Juice keeps its declaration face, Testing publishes
// packages/testing/src/module.jai byte for byte, and juice_core names its
// module-relative closure copies. The fake-source matrix pins validation and
// byte fidelity, while real-source checks pin the test-free member entry.
// Real jai children import the artifacts without rewriting or stripping them
// and exercise the bare API, failure output and path_mapping contract.
// ---------------------------------------------------------------------------
#import "Basic";
#import "Testing";
#import "File_Utilities";
#import "Process";
#import "String";

// ===========================================================================
// Helpers
// ===========================================================================

// Splits the actual artifact text and compares it line for line against
// the expected lines (the trailing "\n" terminator is not a line). Returns
// the 1-based index of the first differing line (0 = line-count mismatch)
// and ok.
expect_text_lines :: (actual: string, expected: [] string) -> (line: s64, ok: bool) {
    lines := split(actual, "\n");
    if lines.count > 0 && lines[lines.count - 1] == "" lines.count -= 1;
    if lines.count != expected.count return 0, false;
    for i: 0..lines.count - 1 {
        if lines[i] != expected[i] return i + 1, false;
    }
    return 0, true;
}

// The E2E smoke driver: imports the published Juice directory module
// (namespaced — the 007 deviation 1 shape, since juice_core re-declares
// the id constants), the published Testing module (bare names) and the
// generated juice_core, then drives both faces and pins the printed
// behavior (the 016 spike s4 shape). The path_mapping rewrite maps the
// driver's own path, so the intentional failure line reports through the
// mapping (the published module's rewrite contract).
publication_smoke_driver_code :: (driver_path: string) -> string {
    builder: String_Builder;
    append(*builder, "#import \"Basic\";\n");
    append(*builder, "Juice :: #import \"Juice\";\n");
    append(*builder, "#import \"Testing\";\n");
    append(*builder, "#import \"juice_core\";\n\n");
    append(*builder, "#run { main(); }\n\n");
    append(*builder, "main :: () {\n");
    append(*builder, "    pkg: Juice.Package;\n");
    append(*builder, "    pkg.name = \"pub-smoke\";\n");
    append(*builder, "    pkg.executables = .[.{name = \"app\", entry = \"src/main.jai\"}];\n");
    append(*builder, "    print(\"package=%1\\n\", pkg.name);\n");
    append(*builder, "    plugins := builtin_plugins();\n");
    append(*builder, "    print(\"builtins=%\\n\", plugins.count);\n");
    append(*builder, "    array_add(*path_mapping, .{view = \"");
    append(*builder, path_slashes(driver_path));
    append(*builder, "\", original = \"driver.jai\"});\n");
    append(*builder, "    expect(pkg.executables.count == 1 && pkg.executables[0].name == \"app\");\n");
    append(*builder, "    run(\"pub-smoke\", () -> () {\n");
    append(*builder, "        expect(true);\n");
    append(*builder, "        expect_eq(\"a\", \"a\");\n");
    append(*builder, "    });\n");
    append(*builder, "    n := finish();\n");
    append(*builder, "    print(\"failures=%\\n\", n);\n");
    append(*builder, "    run(\"pub-smoke-fail\", () -> () {\n");
    append(*builder, "        expect(false);\n");
    append(*builder, "    });\n");
    append(*builder, "    n = finish();\n");
    append(*builder, "    print(\"failures=%\\n\", n);\n");
    append(*builder, "}\n");
    return builder_to_string(*builder);
}

// ===========================================================================
// Fake-source matrix
// ===========================================================================

DECLARATION_SOURCE :: "#import \"Basic\";\n\n// The declaration vocabulary.\nProduct :: struct {\n    name: string;\n}\n";
TESTING_SOURCE :: "#import \"Basic\";\n\n// The Testing face.\nexpect :: (condition: bool) {}\n";

test "Juice face: the declaration source publishes whole behind the standard import" {
    published, ok := publish_juice_module(DECLARATION_SOURCE);
    expect(ok);
    // Exactly one import line: the source own copy is dropped, not doubled.
    // (A second occurrence would show up as an import line inside the body.)
    expect(starts_with(published, "#import \"Basic\";\n\n"));
    body := slice(published, 18, published.count - 18);
    expect(!contains(body, "#import"));
    expect(contains(published, "Product :: struct {"));
    expect(!contains(published, "PUBLICATION-SECTION"));
    // An empty source is a loud failure, not an empty module.
    _, empty_ok := publish_juice_module("");
    expect(!empty_ok);
}

test "Testing face: the member source publishes byte for byte" {
    published, ok := publish_testing_module(TESTING_SOURCE);
    expect(ok);
    expect(published == TESTING_SOURCE);
}

test "Testing face: empty, whitespace and import-only sources fail loudly" {
    sources := string.[
        "",
        "\n",
        "\r\n",
        "\r",
        " \t\r\n\t ",
        " \r \t\r ",
        "#import \"Basic\";",
        "#import \"Basic\";\n",
        "#import \"Basic\";\r\n",
        "#import \"Basic\";\r\n#import \"Basic\";\r\n",
        " \t#import \"Basic\";\n\t \n",
        "\r\n\t#import \"Basic\";\r\n \t\r\n",
    ];
    for source: sources {
        text, ok := publish_testing_module(source);
        expect(!ok && text == "", "an empty publication must fail without output");
    }
}

test "Testing face: a source with no import line is published as-is" {
    source := "run :: (name: string, procedure: () -> ()) { procedure(); }\n";
    published, ok := publish_testing_module(source);
    expect(ok);
    expect(published == source, "publication must not prepend a Basic import");
}

test "Publish Juice module: byte shape" {
    text, ok := publish_juice_module(DECLARATION_SOURCE);
    expect(ok);
    expect(text == "#import \"Basic\";\n\n// The declaration vocabulary.\nProduct :: struct {\n    name: string;\n}\n");
    // The failure channel carries the empty text.
    text, ok = publish_juice_module("");
    expect(!ok && text == "");
}

test "Publish Testing module: preserve imports, comments, spacing and line endings" {
    sources := string.[
        "#import \"Basic\";\nexpect :: (condition: bool) {}\n",
        "\n\n#import \"Basic\";\n\n// source comment\nexpect :: (condition: bool) {}\n\n",
        "#import \"Basic\";\r\n\r\n// source comment\r\nexpect :: (condition: bool) {}\r\n\r\n",
        "#import \"Basic\";\r\n\texpect :: (condition: bool) {}",
        "#import \"String\";\nvalue :: \"原始文本\";",
    ];
    for source: sources {
        text, ok := publish_testing_module(source);
        expect(ok);
        expect(text == source, "publication must not normalize source bytes");
    }
}

test "Publish juice_core: verbatim constants and the module-relative closure list" {
    source := "TRANSPILE_PLUGIN_LOAD_ID       :: \"load\";\nTRANSPILE_PLUGIN_TEST_BLOCK_ID :: \"test-block\";\n";
    text, ok := publish_juice_core(source);
    expect(ok);
    // Ticket 049: the closure is #loaded by module-relative paths under the
    // plugin face landing directory; the generated module quotes no
    // build-machine path at all (the relocation contract).
    expected := string.[
        "// juice_core generated module (ticket 030 publication): the",
        "// plugin-facing module face, #load-ing the plugin face closure by",
        "// module-relative paths under juice_internal/plugin_face/ (verbatim",
        "// copies published beside this file — #load inside a name-imported",
        "// module resolves against the containing file's directory, so the",
        "// modules tree relocates unchanged; ticket 049). The built-in id",
        "// constants are the definition source's own declaration lines (single",
        "// source); the source file itself is not #loaded — its testing",
        "// section carries self-test blocks. Regenerated by the publish step",
        "// every build — never edit.",
        "TRANSPILE_PLUGIN_LOAD_ID       :: \"load\";",
        "TRANSPILE_PLUGIN_TEST_BLOCK_ID :: \"test-block\";",
        "#load \"juice_internal/plugin_face/transpile.jai\";",
        "#load \"juice_internal/plugin_face/transpile_plugin.jai\";",
        "#load \"juice_internal/plugin_face/lifecycle.jai\";",
        "#load \"juice_internal/plugin_face/plugin.jai\";",
    ];
    line, lines_ok := expect_text_lines(text, expected);
    expect(lines_ok, "published juice_core line % differs", line);
    expect(find_index_from_left(text, "C:") < 0);
    expect(find_index_from_left(text, "/src/") < 0);
    // A missing constant declaration is a loud failure (the closure would
    // not compile without it); a near-miss name is not the declaration.
    _, ok = publish_juice_core("TRANSPILE_PLUGIN_LOAD_ID :: \"load\";\n");
    expect(!ok);
    _, ok = publish_juice_core("TRANSPILE_PLUGIN_LOAD_IDX :: \"load\";\nTRANSPILE_PLUGIN_TEST_BLOCK_ID :: \"test-block\";\n");
    expect(!ok);
}

test "Landing paths: the target/modules artifacts and the internal source artifact" {
    expect(juice_module_dir("C:\\p\\target") == "C:/p/target/modules/Juice");
    expect(juice_module_path("C:\\p\\target") == "C:/p/target/modules/Juice/module.jai");
    expect(testing_module_path("C:\\p\\target") == "C:/p/target/modules/Testing.jai");
    expect(juice_core_module_path("C:\\p\\target") == "C:/p/target/modules/juice_core.jai");
    // The fourth publication's helpers take the modules directory itself
    // (the consumption side only knows juice_modules_dir() — ticket 037).
    expect(juice_internal_dir("C:\\p\\target\\modules") == "C:/p/target/modules/juice_internal");
    expect(test_discovery_module_path("C:\\p\\target\\modules") == "C:/p/target/modules/juice_internal/test_discovery.jai");
    // Ticket 049: the plugin face closure copies share the internal
    // namespace, and the relative directory the generated #load lines quote
    // is the same constant pair the landing helpers derive from.
    expect(juice_plugin_face_relative_dir() == "juice_internal/plugin_face");
    expect(juice_plugin_face_dir("C:\\p\\target\\modules") == "C:/p/target/modules/juice_internal/plugin_face");
    expect(juice_plugin_face_file_path("C:\\p\\target\\modules", "plugin.jai") == "C:/p/target/modules/juice_internal/plugin_face/plugin.jai");
}

// ===========================================================================
// Real-source byte pins
// ===========================================================================

// The published Juice module, line for line: packages/juice/module.jai
// verbatim behind the Basic import. Any change to that file must update this
// pin — publication drift fails loudly here.
EXPECTED_JUICE_MODULE_LINES :: string.[
    "#import \"Basic\";",
    "",
    "// The Juice package declaration vocabulary: the exact declarations a package",
    "// author writes against in package.jai (`PACKAGE :: Package.{...}`).",
    "//",
    "// This is a publication source directory, not a package: it has no package.jai,",
    "// is not a workspace member, and is never imported by name as a package. The",
    "// publish step reads this file and emits it verbatim behind the standard import",
    "// line as the installed \"Juice\" module. juice's own compilation unit reaches it",
    "// through src/module.jai, which loads it for the bare declaration names",
    "// (src/manifest.jai evaluates a Package value directly).",
    "//",
    "// Declaration input only. Runtime models live in src/package_model.jai.",
    "// The control-character defaults are reserved implementation values; ordinary",
    "// empty strings and empty lists remain explicit input.",
    "Product :: struct {",
    "    name: string = \"\\x01juice-omitted\";",
    "    entry: string = \"\\x01juice-omitted\";",
    "}",
    "Source_Kind :: enum { UNSPECIFIED; PATH; GIT; WORKSPACE; }",
    "Git_Source :: struct {",
    "    url: string = \"\\x01juice-omitted\";",
    "    branch: string = \"\\x01juice-omitted\";",
    "    tag: string = \"\\x01juice-omitted\";",
    "    rev: string = \"\\x01juice-omitted\";",
    "}",
    "Source :: struct {",
    "    kind: Source_Kind;",
    "    path: string = \"\\x01juice-omitted\";",
    "    git: Git_Source;",
    "}",
    "Module_Selection :: struct {",
    "    path: string = \"\\x01juice-omitted\";",
    "    name: string = \"\\x01juice-omitted\";",
    "    alias: string = \"\\x01juice-omitted\";",
    "}",
    "Dependency :: struct {",
    "    name: string = \"\\x01juice-omitted\";",
    "    source: Source;",
    "    modules: [] Module_Selection = .[.{}];",
    "}",
    "Workspace_Config :: struct {",
    "    members: [] string = .[\"\\x01juice-omitted\"];",
    "    exclude: [] string = .[\"\\x01juice-omitted\"];",
    "    default_members: [] string = .[\"\\x01juice-omitted\"];",
    "}",
    "Plugin_Option :: struct {",
    "    key: string;",
    "    value: string;",
    "}",
    "Plugin_Declaration :: struct {",
    "    id: string = \"\\x01juice-omitted\";",
    "    builtin: string = \"\\x01juice-omitted\";",
    "    source: Source;",
    "    module: Module_Selection;",
    "    options: [] Plugin_Option;",
    "}",
    "TRANSPILE_PLUGIN_LOAD_ID :: \"load\";",
    "TRANSPILE_PLUGIN_TEST_BLOCK_ID :: \"test-block\";",
    "Package :: struct {",
    "    name: string = \"\\x01juice-omitted\";",
    "    version: string = \"\\x01juice-omitted\";",
    "    description: string = \"\\x01juice-omitted\";",
    "    modules: [] Product = .[.{}];",
    "    executables: [] Product = .[.{}];",
    "    dependencies: [] Dependency = .[.{}];",
    "    plugins: [] Plugin_Declaration = .[.{}];",
    "    workspace: Workspace_Config = .{members = .[\"\\x01juice-workspace-omitted\"]};",
    "    default_run: string = \"\\x01juice-omitted\";",
    "}",
];

test "Real source: Juice module publication byte pin" {
    source, ok := read_entire_file(tprint("%1/packages/juice/module.jai", otter_root()));
    expect(ok);
    text, pub_ok := publish_juice_module(source);
    expect(pub_ok);
    line, lines_ok := expect_text_lines(text, EXPECTED_JUICE_MODULE_LINES);
    expect(lines_ok, "published Juice module line % differs", line);
}

test "Real source: Testing publication and landed artifact are byte-identical" {
    source, source_ok := read_entire_file(tprint("%1/packages/testing/src/module.jai", otter_root()));
    expect(source_ok);
    text, published_ok := publish_testing_module(source);
    expect(published_ok);
    expect(text == source, "Testing publication must return the exact member entry");

    expect(ensure_published_modules());
    published_path := testing_module_path(otter_target_dir());
    published, read_ok := read_entire_file(published_path);
    expect(read_ok, "Testing publication must land at %", published_path);
    expect(published == source, "the landed Testing module must preserve every source byte");
}

test "Real source: juice_core publication byte pin" {
    source, ok := read_entire_file(tprint("%1/packages/juice/module.jai", otter_root()));
    expect(ok);
    text, pub_ok := publish_juice_core(source);
    expect(pub_ok);
    expected := string.[
        "// juice_core generated module (ticket 030 publication): the",
        "// plugin-facing module face, #load-ing the plugin face closure by",
        "// module-relative paths under juice_internal/plugin_face/ (verbatim",
        "// copies published beside this file — #load inside a name-imported",
        "// module resolves against the containing file's directory, so the",
        "// modules tree relocates unchanged; ticket 049). The built-in id",
        "// constants are the definition source's own declaration lines (single",
        "// source); the source file itself is not #loaded — its testing",
        "// section carries self-test blocks. Regenerated by the publish step",
        "// every build — never edit.",
        "TRANSPILE_PLUGIN_LOAD_ID :: \"load\";",
        "TRANSPILE_PLUGIN_TEST_BLOCK_ID :: \"test-block\";",
        "#load \"juice_internal/plugin_face/transpile.jai\";",
        "#load \"juice_internal/plugin_face/transpile_plugin.jai\";",
        "#load \"juice_internal/plugin_face/lifecycle.jai\";",
        "#load \"juice_internal/plugin_face/plugin.jai\";",
    ];
    line, lines_ok := expect_text_lines(text, expected);
    expect(lines_ok, "published juice_core line % differs", line);
    // No build-machine path may reach the published face (048 US 33): the
    // retired absolute-src form (048 decision 14) must never come back.
    expect(find_index_from_left(text, path_slashes(otter_root())) < 0);
    expect(find_index_from_left(text, "/src/") < 0);
}

test "Real source: the discovery source publication is byte-identical" {
    // The fourth publication (ticket 037, 006 decision 4/5): the verbatim
    // copy of src/test_discovery.jai under <modules>/juice_internal/. There
    // is no transform, so byte equality is the single-source proof — the
    // test-side publication helper must produce the same artifact the
    // build metaprogram publishes.
    expect(ensure_published_modules());
    modules_dir := target_modules_dir(otter_target_dir());
    published_path := test_discovery_module_path(modules_dir);
    source, source_ok := read_entire_file(path_slashes(tprint("%1/src/test_discovery.jai", otter_root())));
    published, published_ok := read_entire_file(published_path);
    expect(source_ok);
    expect(published_ok, "the discovery source publication must land at %", published_path);
    expect(published == source, "the discovery source publication must be the verbatim source");
}

test "Real source: the plugin face closure copies are byte-identical" {
    // Ticket 049: the four closure files are published verbatim under
    // <modules>/juice_internal/plugin_face/; byte equality is the
    // single-source proof (the copy path has no transform). The published
    // juice_core's relative #load lines must name exactly those landed
    // files (048 US 27/34).
    expect(ensure_published_modules());
    target_dir := otter_target_dir();
    modules_dir := path_slashes(tprint("%1/modules", target_dir));
    core_text, core_ok := read_entire_file(juice_core_module_path(target_dir));
    expect(core_ok);
    for file: JUICE_CORE_LOAD_FILES {
        source, source_ok := read_entire_file(path_slashes(tprint("%1/src/%2", otter_root(), file)));
        face_path := juice_plugin_face_file_path(modules_dir, file);
        published, published_ok := read_entire_file(face_path);
        expect(source_ok, "the plugin face source must be readable: %", file);
        expect(published_ok, "the plugin face copy must land at %", face_path);
        expect(published == source, "the plugin face copy must be the verbatim source: %", file);
        expect(find_index_from_left(core_text, tprint("#load \"%1/%2\";", juice_plugin_face_relative_dir(), file)) >= 0,
            "the published juice_core must #load the landed copy: %", file);
    }
    // The published module quotes no build-machine path.
    expect(find_index_from_left(core_text, path_slashes(otter_root())) < 0);
    expect(find_index_from_left(core_text, "/src/") < 0);
}

test "Publish: the Testing member manifest is not needed for bootstrap" {
    manifest_path := path_slashes(tprint("%1/packages/testing/package.jai", otter_root()));
    backup_path := path_slashes(otter_recovery_path("publication-testing-package.jai"));
    expect(park_source_file(manifest_path, backup_path));
    defer expect(restore_source_file(manifest_path, backup_path));
    expect(ensure_published_modules(), "publication must read the member entry without evaluating its manifest");
    source, source_ok := read_entire_file(tprint("%1/packages/testing/src/module.jai", otter_root()));
    published, published_ok := read_entire_file(testing_module_path(otter_target_dir()));
    expect(source_ok && published_ok);
    expect(published == source);
}

test "Publish: a missing or empty Testing entry cannot replace the installed set" {
    expect(ensure_published_modules());
    modules_directory := target_modules_dir(otter_target_dir());
    artifact_paths := install_artifact_paths(modules_directory);
    original_artifacts: [..] string;
    for artifact: artifact_paths {
        content, read_ok := read_entire_file(artifact.absolute_path);
        expect(read_ok);
        array_add(*original_artifacts, content);
    }
    original_marker, marker_read_ok := read_entire_file(install_manifest_path(modules_directory));
    expect(marker_read_ok);

    testing_path := path_slashes(tprint("%1/packages/testing/src/module.jai", otter_root()));
    backup_path := path_slashes(otter_recovery_path("publication-testing-member.jai"));
    expect(park_source_file(testing_path, backup_path));
    defer {
        expect(restore_source_file(testing_path, backup_path));
        expect(ensure_published_modules());
    }
    expect(!ensure_published_modules(), "a missing member entry must fail publication");
    for source: string.["", " \t\r\n", "#import \"Basic\";\r\n\t "] {
        expect(write_entire_file(testing_path, source));
        expect(!ensure_published_modules(), "an empty member entry must fail publication");
    }
    for artifact, index: artifact_paths {
        content, read_ok := read_entire_file(artifact.absolute_path);
        expect(read_ok && content == original_artifacts[index],
               "failed publication must not replace %", artifact.relative_path);
    }
    marker, marker_ok := read_entire_file(install_manifest_path(modules_directory));
    expect(marker_ok && marker == original_marker, "failed publication must not replace the installation marker");
}

test "Publish: a missing plugin face closure source fails the test-side publication" {
    // Park src/lifecycle.jai for the duration of the test: the test-side
    // publisher reads every source before writing, so a missing closure
    // source fails it loudly (false) with no partial artifact set. The park
    // is crash-safe (ticket 053 F2): the source is copied to a target/
    // backup and verified on disk before the original is removed, so a test
    // process killed mid-run leaves the only copy recoverable. The defer
    // restores from the backup, asserts the restore and republishes for the
    // following tests.
    closure_path := path_slashes(tprint("%1/src/lifecycle.jai", otter_root()));
    backup_path := path_slashes(otter_recovery_path("publication-plugin-face-lifecycle.jai"));
    expect(park_source_file(closure_path, backup_path));
    defer {
        expect(restore_source_file(closure_path, backup_path));
        expect(ensure_published_modules());
    }
    expect(!ensure_published_modules());
}

// ===========================================================================
// E2E: the published artifacts under bare imports
// ===========================================================================

test "E2E: published modules compile and run under bare imports" {
    declaration, declaration_ok := read_entire_file(tprint("%1/packages/juice/module.jai", otter_root()));
    expect(declaration_ok);
    testing_source, testing_read_ok := read_entire_file(tprint("%1/packages/testing/src/module.jai", otter_root()));
    expect(testing_read_ok);

    juice, ok1 := publish_juice_module(declaration);
    testing, ok2 := publish_testing_module(testing_source);
    core, ok3 := publish_juice_core(declaration);
    expect(ok1 && ok2 && ok3);

    // The ticket 049 layout: the modules root holds juice_core.jai and the
    // verbatim plugin face closure copies under
    // juice_internal/plugin_face/ — the generated module's
    // module-relative #load lines resolve through this layout (the 048
    // decision 5 fact proven with a real child). The cache is wiped first
    // so a stale copy can never mask a missing publication step.
    cache := otter_scratch("publication-e2e-cache");
    delete_directory_full(cache);
    expect(make_directory_if_it_does_not_exist(tprint("%1/Juice", cache), recursive = true));
    expect(make_directory_if_it_does_not_exist(juice_plugin_face_dir(cache), recursive = true));
    expect(write_entire_file(tprint("%1/Juice/module.jai", cache), juice));
    expect(testing == testing_source);
    expect(write_entire_file(tprint("%1/Testing.jai", cache), testing));
    expect(write_entire_file(tprint("%1/juice_core.jai", cache), core));
    for file: JUICE_CORE_LOAD_FILES {
        closure_source, closure_ok := read_entire_file(tprint("%1/src/%2", otter_root(), file));
        expect(closure_ok);
        expect(write_entire_file(juice_plugin_face_file_path(cache, file), closure_source));
    }
    driver_path := tprint("%1/driver.jai", cache);
    driver_source := publication_smoke_driver_code(driver_path);
    expect(write_entire_file(driver_path, driver_source));
    failure_offset := find_index_from_left(driver_source, "        expect(false);");
    expect(failure_offset >= 0);
    failure_lines := split(slice(driver_source, 0, failure_offset), "\n");

    result, output, _, _ := run_command("jai", driver_path, "-import_dir", cache, "-quiet", working_directory = otter_root(), capture_and_return_output = true);
    expect(expect_exit("publication-smoke", result, 0));
    expect(child_output_contains("publication-smoke", output,
        tprint("driver.jai:%1:9: expect failed", failure_lines.count)));
    {
        ok := output_matches("publication-smoke", output, string.[
            "package=pub-smoke",
            "builtins=2",
            "[test] pub-smoke",
            "1 passed, 0 failed",
            "failures=0",
            "[test] pub-smoke-fail",
            "driver.jai:",
            "expect failed",
            "0 passed, 1 failed",
            "failures=1",
        ]);
        expect(ok);
    }
}

// The Juice declaration vocabulary remains a publication source directory,
// separate from the standard packages/testing workspace member.
test "Real source: the declaration vocabulary lives in packages/juice" {
    declaration_path := tprint("%1/packages/juice/module.jai", otter_root());
    expect(file_exists(declaration_path));
    declaration_source, read_ok := read_entire_file(declaration_path);
    expect(read_ok);
    expect(contains(declaration_source, "Package :: struct"));
    expect(contains(declaration_source, "Plugin_Declaration :: struct"));
    expect(contains(declaration_source, "Workspace_Config :: struct"));
    // A publication source directory is not a package: no manifest, so no
    // workspace member, no Package.name, nothing to #import as a package.
    expect(!file_exists(tprint("%1/packages/juice/package.jai", otter_root())));

    // The published face is that file verbatim behind the standard import line,
    // with no section marker involved.
    published, published_ok := publish_juice_module(declaration_source);
    expect(published_ok);
    expect(contains(published, "Package :: struct"));
    expect(!contains(published, "PUBLICATION-SECTION"));
}

// The member entry is the only Testing implementation. Its self-tests belong
// to the member's tests, never to the source copied into a consumer's program.
test "Real source: the Testing member entry has bare names and no self-tests" {
    testing_path := tprint("%1/packages/testing/src/module.jai", otter_root());
    testing_source, read_ok := read_entire_file(testing_path);
    expect(read_ok);
    for declaration: string.["Path_Pair :: struct", "path_mapping:", "expect ::", "expect_eq ::", "fail ::", "run ::", "finish ::"] {
        expect(contains(testing_source, declaration), "the member entry must export %", declaration);
    }
    expect(!contains(testing_source, "Testing_"));
    expect(!contains(testing_source, "@test"));
    expect(!pipeline_has_anchors(default_transpile_pipeline(), testing_source, testing_path),
           "the member entry must be standard Jai without inline test blocks");
    expect(!contains(testing_source, "#load"), "the published flat module must be self-contained");
    expect(file_exists(tprint("%1/packages/testing/package.jai", otter_root())));
    expect(!file_exists(tprint("%1/packages/juice/testing.jai", otter_root())));
}
