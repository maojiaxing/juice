// ---------------------------------------------------------------------------
// Publication transform tests (ticket 030): the pure text-to-text
// generators producing the three published module artifacts from the single
// definition source src/module.jai — the Juice directory module (package
// section cut), Testing.jai (Testing_ prefix strip) and juice_core.jai
// (module-relative #load closure generation, ticket 049) — plus the
// target/modules landing paths. Ticket 049 also pins the plugin face
// closure copies: the four JUICE_CORE_LOAD_FILES sources published verbatim
// under <modules>/juice_internal/plugin_face/, and the published
// juice_core's relative #load lines naming exactly those landed files.
//
// The section boundary markers are the single-source contract: the real
// source is pinned byte for byte through the publication, so any drift in
// src/module.jai's published sections fails here loudly (spec US 19). The
// fake-source matrix pins the contract rules (missing/duplicated/misordered/
// unknown markers fail loudly; blank edges trimmed; the prefix strip
// touches IDENT tokens only — line structure preserved, comments and string
// literals untouched, self-test blocks retained). The E2E block compiles
// and runs all three artifacts under bare imports in a real jai child (the
// 016 spike s4 smoke shape).
//
// Key constraint (same as the other sibling test files): src modules are
// bootstrap #load targets / entry closure members — test blocks would be
// illegal inside them, so src/publication.jai stays test-free and its tests
// live here (tests/), per the test organization rule: referenced by no
// #load, collected into the test program by Test discovery's full-package
// scan. Good-test standard: only external behavior is pinned (given source
// text -> published artifact text), never the transform internals.
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

// The published Testing module cut before its self-test section — the
// special case's strip-view posture (the module source carries self-test
// blocks that raw imports cannot compile).
testing_publication_strip_view :: (published: string) -> string {
    index := find_index_from_left(published, "\ntest \"");
    if index < 0 index = find_index_from_left(published, "\ntest{");
    if index < 0 return published;
    return slice(published, 0, index);
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
    append(*builder, "    pkg.type = .BIN;\n");
    append(*builder, "    print(\"package=%1\\n\", pkg.name);\n");
    append(*builder, "    plugins := builtin_plugins();\n");
    append(*builder, "    print(\"builtins=%\\n\", plugins.count);\n");
    append(*builder, "    array_add(*path_mapping, .{view = \"");
    append(*builder, path_slashes(driver_path));
    append(*builder, "\", original = \"driver.jai\"});\n");
    append(*builder, "    expect(pkg.type == .BIN);\n");
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

FAKE_SOURCE :: "#import \"Basic\";\n\n// file header prose\n// [PUBLICATION-SECTION package]\n\nP1 :: struct {\n    a: string;\n}\n\n// [PUBLICATION-SECTION testing]\n\nT1 :: struct {\n    b: string;\n}\n\n// [PUBLICATION-CUT testing-self-tests]\n\ntest \"kept\" {\n    x := 1;\n}\n";

test "Section cut: both sections extract with blank edges trimmed and self-tests cut" {
    section, ok := extract_package_section(FAKE_SOURCE);
    expect(ok);
    expect(section == "P1 :: struct {\n    a: string;\n}");
    section, ok = extract_testing_section(FAKE_SOURCE);
    expect(ok);
    expect(section == "T1 :: struct {\n    b: string;\n}");
}

test "Section cut: missing markers fail loudly" {
    _, ok := extract_package_section("#import \"Basic\";\n\nP1 :: struct {}\n\nT1 :: struct {}\n");
    expect(!ok);
    _, ok = extract_testing_section("#import \"Basic\";\n\nP1 :: struct {}\n\nT1 :: struct {}\n");
    expect(!ok);
    // One marker alone is not enough — both must be present.
    _, ok = extract_package_section("#import \"Basic\";\n\n// [PUBLICATION-SECTION package]\n\nP1 :: struct {}\n");
    expect(!ok);
    _, ok = extract_testing_section("#import \"Basic\";\n\n// [PUBLICATION-SECTION testing]\n\nT1 :: struct {}\n");
    expect(!ok);
}

test "Section cut: duplicated markers fail loudly" {
    _, ok := extract_package_section("// [PUBLICATION-SECTION package]\n// [PUBLICATION-SECTION package]\nP1 :: struct {}\n// [PUBLICATION-SECTION testing]\nT1 :: struct {}\n");
    expect(!ok);
    _, ok = extract_testing_section("// [PUBLICATION-SECTION package]\nP1 :: struct {}\n// [PUBLICATION-SECTION testing]\n// [PUBLICATION-SECTION testing]\nT1 :: struct {}\n");
    expect(!ok);
}

test "Section cut: missing or duplicated self-test cut marker fails loudly" {
    // No cut marker: the published face would include the self-tests.
    _, ok := extract_testing_section("// [PUBLICATION-SECTION package]\nP1 :: 1;\n// [PUBLICATION-SECTION testing]\nT1 :: 1;\n");
    expect(!ok);
    // Two cut markers: the published face's end is ambiguous.
    _, ok = extract_testing_section("// [PUBLICATION-SECTION package]\nP1 :: 1;\n// [PUBLICATION-SECTION testing]\nT1 :: 1;\n// [PUBLICATION-CUT testing-self-tests]\n// [PUBLICATION-CUT testing-self-tests]\nT2 :: 1;\n");
    expect(!ok);
}

test "Section cut: unknown marker names and misorder fail loudly" {
    // A typo'd marker name must never publish silently.
    _, ok := extract_package_section("// [PUBLICATION-SECTION package]\nP1 :: struct {}\n// [PUBLICATION-SECTION typo]\nT1 :: struct {}\n// [PUBLICATION-SECTION testing]\nT2 :: struct {}\n");
    expect(!ok);
    _, ok = extract_testing_section("// [PUBLICATION-SECTION package]\nP1 :: struct {}\n// [PUBLICATION-SECTION typo]\nT1 :: struct {}\n");
    expect(!ok);
    // The testing marker before the package marker is a misorder.
    _, ok = extract_package_section("// [PUBLICATION-SECTION testing]\nT1 :: struct {}\n// [PUBLICATION-SECTION package]\nP1 :: struct {}\n");
    expect(!ok);
}

test "Prefix strip: the public-name matrix strips to the bare published names" {
    source := "Testing_Path_Pair :: struct {\n    view: string;\n};\n\nTesting_path_mapping : [..] Testing_Path_Pair;\n\nmapped_path :: (view: string) -> string {\n    for pair: Testing_path_mapping {\n        if pair.view == view return pair.original;\n    }\n    return view;\n}\n\nTesting_expect(1);\nTesting_expect_eq(1, 1);\nTesting_fail(\"x\");\nTesting_run(\"n\", run_proc);\nTesting_finish();\n";
    expected := "Path_Pair :: struct {\n    view: string;\n};\n\npath_mapping : [..] Path_Pair;\n\nmapped_path :: (view: string) -> string {\n    for pair: path_mapping {\n        if pair.view == view return pair.original;\n    }\n    return view;\n}\n\nexpect(1);\nexpect_eq(1, 1);\nfail(\"x\");\nrun(\"n\", run_proc);\nfinish();\n";
    expect(strip_testing_prefix(source) == expected);
}

test "Prefix strip: comments, strings and non-prefixed names keep their text" {
    source := "// prose: the Testing_ prefix\nx := Testing_expect;\nprint(\"Testing_run\");\nTesting_ : int;\nmy_Testing_x := 1;\n";
    expected := "// prose: the Testing_ prefix\nx := expect;\nprint(\"Testing_run\");\nTesting_ : int;\nmy_Testing_x := 1;\n";
    expect(strip_testing_prefix(source) == expected);
}

test "Prefix strip: line fidelity holds line for line" {
    source := "Testing_Path_Pair :: struct {\n    view: string;\n};\n\nTesting_path_mapping : [..] Testing_Path_Pair;\n\nmapped_path :: (view: string) -> string {\n    for pair: Testing_path_mapping {\n        if pair.view == view return pair.original;\n    }\n    return view;\n}\n";
    stripped := strip_testing_prefix(source);
    src_lines := split(source, "\n");
    out_lines := split(stripped, "\n");
    expect(out_lines.count == src_lines.count);
    expect(out_lines[0] == "Path_Pair :: struct {");
    expect(out_lines[1] == "    view: string;");
    expect(out_lines[4] == "path_mapping : [..] Path_Pair;");
    expect(out_lines[6] == "mapped_path :: (view: string) -> string {");
    expect(out_lines[7] == "    for pair: path_mapping {");
    expect(out_lines[8] == "        if pair.view == view return pair.original;");
}

test "Publish Juice module: byte shape" {
    text, ok := publish_juice_module(FAKE_SOURCE);
    expect(ok);
    expect(text == "#import \"Basic\";\n\nP1 :: struct {\n    a: string;\n}\n");
    // The failure channel carries the empty text.
    text, ok = publish_juice_module("no markers here\n");
    expect(!ok && text == "");
}

test "Publish Testing module: byte shape with prefixes stripped and self-tests cut" {
    source := "#import \"Basic\";\n// [PUBLICATION-SECTION package]\nP1 :: 1;\n// [PUBLICATION-SECTION testing]\nTesting_expect(true);\n// [PUBLICATION-CUT testing-self-tests]\ntest \"kept\" {\n    Testing_expect(true);\n}\n";
    text, ok := publish_testing_module(source);
    expect(ok);
    expect(text == "#import \"Basic\";\n\nexpect(true);\n");
    text, ok = publish_testing_module(FAKE_SOURCE);
    expect(ok);
    expect(text == "#import \"Basic\";\n\nT1 :: struct {\n    b: string;\n}\n");
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

// The published Juice directory module, line for line (the definition
// source's package section verbatim behind the Basic import). Any change to
// src/module.jai's package section must update this pin — publication drift
// fails loudly here.
EXPECTED_JUICE_MODULE_LINES :: string.[
    "#import \"Basic\";",
    "",
    "// UNSPECIFIED means the role is derived from convention during target",
    "// resolution: src/main.jai (or declared targets) means BIN; an import entry",
    "// means LIB; anything else stays BIN.",
    "Package_Type :: enum {",
    "    LIB;",
    "    BIN;",
    "    UNSPECIFIED;",
    "}",
    "",
    "// Raw target declaration as written by package.jai.",
    "Target :: struct {",
    "    name:      string;",
    "    main_file: string;",
    "}",
    "",
    "// A target after defaults and filesystem validation have been applied.",
    "Effective_Target :: struct {",
    "    name:        string;",
    "    main_file:   string;",
    "    source_path: string;",
    "}",
    "",
    "// The complete output contract consumed by Build and Run. target_dir is the",
    "// package's unified target/ directory root; the artifact lands directly",
    "// inside it (no profile sublayers).",
    "Artifact_Plan :: struct {",
    "    target:        Effective_Target;",
    "    target_dir:    string;",
    "    artifact_path: string;",
    "}",
    "",
    "Dependency :: struct {",
    "    name:    string;",
    "    version: string = \"\";",
    "    source:  string = \"\";",
    "    package: string = \"\";",
    "}",
    "",
    "Workspace_Config :: struct {",
    "    members: [] string;",
    "    exclude: [] string;",
    "}",
    "",
    "// One option row of a plugin declaration. The value is a string; the plugin's",
    "// options schema owns parsing and validation (Config_Option.apply, added by",
    "// the pre-step plugin effort). Options cross the manifest protocol as",
    "// PLUGIN_OPTION records with %XX encoding.",
    "Plugin_Option :: struct {",
    "    key:   string;",
    "    value: string;",
    "}",
    "",
    "// One plugin declaration: the plugin identity (id + version — feeds the",
    "// pipeline/hook description and the cache key) plus the options rows.",
    "// Declaration order = pipeline order = hook registration order = lint",
    "// observation order. An empty Package.plugins list means the default",
    "// pipeline and no hooks/lint. Member plugins use the member package name as",
    "// their id; the built-in ids are TRANSPILE_PLUGIN_LOAD_ID /",
    "// TRANSPILE_PLUGIN_TEST_BLOCK_ID.",
    "Plugin_Declaration :: struct {",
    "    id:      string;",
    "    version: string;",
    "    options: [] Plugin_Option;",
    "}",
    "",
    "// The v1 built-in transpile plugin ids: the reserved built-in declaration",
    "// ids. Member plugin ids are package names and must not collide with these.",
    "TRANSPILE_PLUGIN_LOAD_ID       :: \"load\";",
    "TRANSPILE_PLUGIN_TEST_BLOCK_ID :: \"test-block\";",
    "",
    "Package :: struct {",
    "    name:         string;",
    "    version:      string;",
    "    type:         Package_Type = .UNSPECIFIED;",
    "    description:  string = \"\";",
    "",
    "    targets:      [] Target;",
    "",
    "    dependencies: [] Dependency;",
    "    workspace:    Workspace_Config;",
    "    build_script: string = \"\";",
    "",
    "    // Plugin declarations: the single activation/configuration/ordering",
    "    // surface (2026-10-21 design revision). An empty list means the default",
    "    // transpile pipeline and no hooks/lint.",
    "    plugins:      [] Plugin_Declaration;",
    "",
    "    // Set by the manifest loader; it is not declared in package.jai.",
    "    dir:          string = \"\";",
    "}",
    "",
    "// Discovery retains the evaluated declarations, including the root first.",
    "// Dependencies consume this snapshot rather than executing member manifests",
    "// again.",
    "Workspace_Discovery :: struct {",
    "    root_dir:        string;",
    "    has_package:     bool;",
    "    root_package:    Package;",
    "    member_packages: [] Package;",
    "}",
    "",
    "// State shared by command handlers after discovery, resolution, and (if",
    "// necessary) dependency preparation have completed.",
    "Prepared_Workspace :: struct {",
    "    discovery:             Workspace_Discovery;",
    "    artifact_plans:        [] Artifact_Plan;",
    "    // The package role after UNSPECIFIED has been resolved by convention.",
    "    package_type:          Package_Type;",
    "    dependencies_prepared: bool;",
    "}",
];

// The published Testing module, line for line (the definition source's
// testing section — banner, bare-name declarations, file-private internals;
// the self-tests below the publication cut marker are not published). Any change
// to src/module.jai's testing section must update this pin.
EXPECTED_TESTING_MODULE_LINES :: string.[
    "#import \"Basic\";",
    "",
    "// ---------------------------------------------------------------------------",
    "// Testing API surface (ticket 016, spec section 9.5): the definition-source",
    "// declaration shape of the published \"Testing\" module — expect/expect_eq/",
    "// fail/run/finish/path_mapping, API-compatible with old juice's Testing.jai",
    "// (the published face is what test programs consume since ticket 035).",
    "//",
    "// The public names carry the Testing_ prefix because this file enters every",
    "// test program's application scope through Test discovery's full-package",
    "// scan, while the test driver imports the published Testing face — bare",
    "// run/finish/expect/... declarations here would collide with that face. The",
    "// shape is pinned by the spike at",
    "// AppData/Local/Temp/otter-testing-shape-spike/ (the bare candidate fails",
    "// with \"Two overloaded definitions of the same procedure can't have",
    "// identical argument lists\"); the prefix keeps the definition-source face",
    "// distinct from the imported published face.",
    "//",
    "// The internals stay bare under #scope_file, mirroring the published",
    "// module's structure: the publication step (ticket 030,",
    "// src/publication.jai) strips the Testing_ prefixes from this section and",
    "// emits it as target/modules/Testing.jai — no other transformation (the",
    "// spike's publish smoke compiled the converted module with a bare import).",
    "//",
    "// The published face is the only consumption path (ticket 035): test",
    "// drivers import the published module and drive the bare names. These",
    "// prefixed declarations remain the definition source's internal face — the",
    "// publication transform's input and the face the src self-tests and",
    "// module_tests' definition-source scenarios exercise. (Ticket 003's",
    "// source-face driver loading is retired.)",
    "//",
    "// Semantics (old juice Testing.jai contract): a failing assertion registers",
    "// the failure globally and aborts the current test body immediately (the",
    "// backticked `return is inserted into the caller); the suite keeps running",
    "// and defers fire normally. Each failure prints as `path:line,col: message`",
    "// and each test start as `[test] <name>`; finish() prints",
    "// `N passed, M failed` and returns the failure count. path_mapping is the",
    "// driver-injected \"view absolute path <-> original package-relative path\"",
    "// rewrite table; the default empty array passes paths through untouched.",
    "// ---------------------------------------------------------------------------",
    "",
    "// One rewrite pair: `view` is the absolute path of a view (the path",
    "// #caller_location reports); `original` is the package-relative source path",
    "// printed in its place.",
    "Path_Pair :: struct {",
    "    view:     string;",
    "    original: string;",
    "}",
    "",
    "// Mutable global the driver fills in before running the test list.",
    "// Default empty array = passthrough.",
    "path_mapping : [..] Path_Pair;",
    "",
    "// expect(cond) with an optional printf-style message, mirroring Basic.assert's",
    "// shape.",
    "expect :: (condition: bool, message := \"\", args: .. Any, loc := #caller_location) #expand {",
    "    if !condition {",
    "        if message == \"\" {",
    "            report_failure(loc, \"expect failed\");",
    "        } else {",
    "            report_failure(loc, tprint(message, ..args));",
    "        }",
    "        `return;",
    "    }",
    "}",
    "",
    "// expect_eq(expected, actual) with the $T same-type constraint checked at",
    "// compile time; T must support != and print.",
    "expect_eq :: (expected: $T, actual: T, message := \"\", loc := #caller_location) #expand {",
    "    if expected != actual {",
    "        if message == \"\" {",
    "            report_failure(loc, tprint(\"expect_eq failed: expected %, got %\", expected, actual));",
    "        } else {",
    "            report_failure(loc, tprint(message));",
    "        }",
    "        `return;",
    "    }",
    "}",
    "",
    "// Unconditionally register a failure and abort the current test.",
    "fail :: (message: string, loc := #caller_location) #expand {",
    "    report_failure(loc, message);",
    "    `return;",
    "}",
    "",
    "// Runs one test. run prints the `[test] <name>` start line and counts the",
    "// test as passed unless a failure was registered while it ran.",
    "run :: (name: string, proc: () -> ()) {",
    "    current_test_failed = false;",
    "    print(\"[test] %\\n\", name);",
    "    proc();",
    "    if !current_test_failed passed_count += 1;",
    "}",
    "",
    "// Prints the summary and returns the failure count; the driver turns a",
    "// non-zero result into a compile error. Counters reset so a fresh suite can",
    "// start afterward.",
    "finish :: () -> s32 {",
    "    print(\"% passed, % failed\\n\", passed_count, failure_count);",
    "    result := failure_count;",
    "    passed_count = 0;",
    "    failure_count = 0;",
    "    current_test_failed = false;",
    "    return result;",
    "}",
    "",
    "#scope_file;",
    "",
    "// --- Internal registration state. File-private (the published module keeps",
    "// the same bare names under #scope_file); the #expand macros above resolve",
    "// these names at their definition site, so callers in other files never see",
    "// them. Module-level globals are shared program-wide by every file that",
    "// loads this file. ---",
    "",
    "current_test_failed := false;",
    "passed_count: s32 = 0;",
    "failure_count: s32 = 0;",
    "",
    "mapped_path :: (view: string) -> string {",
    "    for pair: path_mapping {",
    "        if pair.view == view return pair.original;",
    "    }",
    "    return view;",
    "}",
    "",
    "report_failure :: (loc: Source_Code_Location, message: string) {",
    "    current_test_failed = true;",
    "    failure_count += 1;",
    "    print(\"%:%:%: %\\n\", mapped_path(loc.fully_pathed_filename), loc.line_number, loc.character_number, message);",
    "}",
    "",
    "#scope_export;",
];

test "Real source: Juice module publication byte pin" {
    source, ok := read_entire_file(tprint("%1/src/module.jai", otter_root()));
    expect(ok);
    text, pub_ok := publish_juice_module(source);
    expect(pub_ok);
    line, lines_ok := expect_text_lines(text, EXPECTED_JUICE_MODULE_LINES);
    expect(lines_ok, "published Juice module line % differs", line);
}

test "Real source: Testing module publication byte pin" {
    source, ok := read_entire_file(tprint("%1/src/module.jai", otter_root()));
    expect(ok);
    text, pub_ok := publish_testing_module(source);
    expect(pub_ok);
    line, lines_ok := expect_text_lines(text, EXPECTED_TESTING_MODULE_LINES);
    expect(lines_ok, "published Testing module line % differs", line);
}

test "Real source: juice_core publication byte pin" {
    source, ok := read_entire_file(tprint("%1/src/module.jai", otter_root()));
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
        "TRANSPILE_PLUGIN_LOAD_ID       :: \"load\";",
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
    source, ok := read_entire_file(tprint("%1/src/module.jai", otter_root()));
    expect(ok);

    juice, ok1 := publish_juice_module(source);
    testing, ok2 := publish_testing_module(source);
    core, ok3 := publish_juice_core(source);
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
    expect(write_entire_file(tprint("%1/Testing.jai", cache), testing_publication_strip_view(testing)));
    expect(write_entire_file(tprint("%1/juice_core.jai", cache), core));
    for file: JUICE_CORE_LOAD_FILES {
        closure_source, closure_ok := read_entire_file(tprint("%1/src/%2", otter_root(), file));
        expect(closure_ok);
        expect(write_entire_file(juice_plugin_face_file_path(cache, file), closure_source));
    }
    driver_path := tprint("%1/driver.jai", cache);
    expect(write_entire_file(driver_path, publication_smoke_driver_code(driver_path)));

    result, output, _, _ := run_command("jai", driver_path, "-import_dir", cache, "-quiet", working_directory = otter_root(), capture_and_return_output = true);
    if expect_exit("publication-smoke", result, 0) {
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
