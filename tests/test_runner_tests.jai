#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// Test runner module tests (ticket 017, candidate 2's single-program
// slice): the generated driver source and test runner entry text shapes
// byte-locked (the generator faces in src/test_runner.jai, which enter this
// test program's application scope through Test discovery's full-package
// scan), the injected runner
// code shapes, and the E2E start — real jai children compiling the
// generated metaprogram on the @test fixtures (discovery, execution, the
// mapped failure coordinates and the aggregated exit code).
// Ticket 042 adds the plugin registration face: the zero-plugin text stays
// byte-identical, the registration-backed text loads and merges the scanned
// plugin set at the top of #run and observes the merged lint faces at
// collection time, and the synthetic plugin-lint fixture proves the whole
// chain in a real child (lint warning with the original package-relative
// path and 1-based coordinates, tests still running, imported modules and
// pattern filtering never touching lint, merge failure failing the
// compile).
// ---------------------------------------------------------------------------

// The generated test driver, byte for byte (ticket 035's single shape plus
// the C4 package-root constant): the root constant, the chdir #run anchoring
// the package root, the published Testing face import, then the discovered
// files in #load order.
EXPECTED_TEST_DRIVER :: "#import \"Basic\";\n\n// Compile-time execution resolves relative paths against the metaprogram's\n// own directory (the jai child anchors its working directory at the entry\n// file); the package root anchor is set explicitly so test bodies resolve\n// relative paths against it (the 009 deviation 2 discipline).\n// The package root constant (C4): the test program's intermediate path is\n// target/build/ (C5), so test helpers use this constant instead of\n// Build_Options.intermediate_path.\nJUICE_TEST_PACKAGE_ROOT :: \"C:/pkg\";\n\n#run { set_working_directory(\"C:/pkg\"); }\n\n#import \"Testing\";\n\n#load \"C:/pkg/src/a.jai\";\n#load \"C:/pkg/src/b.jai\";\n";

test "The generated test driver matches the byte-locked shape" {
    options: Test_Driver_Options;
    options.package_root   = "C:\\pkg";
    options.source_files   = string.["C:\\pkg\\src\\a.jai", "C:\\pkg\\src\\b.jai"];
    expect(generate_test_driver(options) == EXPECTED_TEST_DRIVER);
}

// The published-face import is unconditional (ticket 035): the driver never
// #loads a source-face cut — the t9 compile view on the import path serves
// every package, so the injected bare runner and the test bodies' bare
// assertions share one register.
test "The generated test driver always imports the published Testing face" {
    options: Test_Driver_Options;
    options.package_root   = "C:\\pkg";
    options.source_files   = string.["C:\\pkg\\src\\a.jai"];
    generated := generate_test_driver(options);
    expect(find_index_from_left(generated, "#import \"Testing\";\n") >= 0);
    expect(find_index_from_left(generated, "module.jai") < 0);
    expect(find_index_from_left(generated, tprint("#run { set_working_directory(\"C:/pkg\"); }\n\n#import \"Testing\";\n\n#load \"C:/pkg/src/a.jai\";\n")) >= 0);
}

// The generated test metaprogram, byte for byte: the discovery surface
// #load, the NO_OUTPUT workspace, the message loop collecting headers and
// injecting once at TYPECHECKED_ALL_WE_CAN, and the embedded isolation and
// mapping sets.
EXPECTED_TEST_METAPROGRAM :: "#import \"Basic\";\n#import \"Compiler\";\n\n#load \"X:/otter/src/test_discovery.jai\";\n\n#run {\n    set_build_options_dc(.{do_output = false});\n    workspace := compiler_create_workspace(\"Juice Test Program\");\n    if !workspace return;\n    options := get_build_options(workspace);\n    options.output_type = .NO_OUTPUT;\n    options.intermediate_path = \"X:/demo/target\";\n    import_paths: [..] string;\n    array_add(*import_paths, .. options.import_path);\n    array_add(*import_paths, \"X:/demo/modules\");\n    options.import_path = import_paths;\n    set_build_options(options, workspace);\n    compiler_begin_intercept(workspace);\n    add_build_string(\"DRIVER\", workspace);\n    while true {\n        msg := compiler_wait_for_message();\n        if !msg continue;\n        if msg.workspace == workspace {\n            if msg.kind == {\n                case .TYPECHECKED;\n                    typechecked := cast(*Message_Typechecked) msg;\n                    collect_test_headers(typechecked);\n                case .PHASE;\n                    phase := cast(*Message_Phase) msg;\n                    if phase.phase == .TYPECHECKED_ALL_WE_CAN && !injected {\n                        inject_test_runner(msg.workspace);\n                        injected = true;\n                    }\n                case .ERROR;\n                case .COMPLETE;\n                    break;\n            }\n        }\n    }\n    compiler_end_intercept(workspace);\n}\n\n// The one-shot injection guard: adding the runner re-runs the phase, and\n// the collection must never emit twice (how_to/460:68-75 shape).\ninjected := false;\n\n// The accumulated header stream (name + enclosing load path), fed by the\n// message loop and consumed once at TYPECHECKED_ALL_WE_CAN.\ncollected_sources: [..] Collected_Test_Source;\n\n// The embedded isolation and mapping sets (known at generation time,\n// spec section 7.2).\npackage_view_paths: [] string = string.[\"X:/demo/src/a.jai\", \"X:/demo/src/b.jai\"];\nwhitelist_paths: [] string = string.[];\npath_pairs: [] Test_Path_Pair = Test_Path_Pair.[.{ view = \"X:/demo/src/a.jai\", original = \"src/a.jai\" }];\n\n// The post-collection pattern filter constant (spec section 7.3): \"\" runs\n// every collected test, otherwise only names containing the pattern.\npattern: string = \"\";\n\ncollect_test_headers :: (typechecked: *Message_Typechecked) {\n    for tc: typechecked.procedure_headers {\n        header := tc.expression;\n        note_texts: [..] string;\n        for note: header.notes array_add(*note_texts, note.text);\n        if !header_is_test(header.name, note_texts) continue;\n        path := \"\";\n        if header.enclosing_load path = header.enclosing_load.fully_pathed_filename;\n        array_add(*collected_sources, .{ name = header.name, path = path });\n    }\n}\n\ninject_test_runner :: (workspace: Workspace) {\n    entries, duplicate_name := collect_test_entries(collected_sources, package_view_paths, whitelist_paths, 1);\n    if duplicate_name != \"\" {\n        compiler_report(tprint(\"duplicate test name: %\", duplicate_name));\n        return;\n    }\n    matched := filter_test_entries(entries, pattern);\n    if entries.count == 0 {\n        print(\"[juice Test] No tests found.\\n\");\n        return;\n    }\n    if matched.count == 0 {\n        print(\"[juice Test] No tests matched '%'.\\n\", pattern);\n        return;\n    }\n    add_build_string(generate_test_runner_code(matched, path_pairs), workspace);\n}\n";

test "The generated test metaprogram matches the byte-locked shape" {
    options: Test_Metaprogram_Options;
    options.workspace_name     = "Juice Test Program";
    options.intermediate_path  = "X:\\demo\\target";
    options.import_dirs        = string.["X:\\demo\\modules"];
    options.driver_source         = "DRIVER";
    options.package_view_paths = string.["X:\\demo\\src\\a.jai", "X:\\demo\\src\\b.jai"];
    options.path_pairs         = Test_Path_Pair.[.{ view = "X:\\demo\\src\\a.jai", original = "src/a.jai" }];
    options.discovery_source   = "X:\\otter\\src\\test_discovery.jai";
    generated := generate_test_metaprogram(options);
    expect(generated == EXPECTED_TEST_METAPROGRAM);
}

// The pattern option (ticket 018): the embedded constant carries the
// pattern, the filter call sits after collection, and the zero-match report
// interpolates it — the discovery machinery itself never sees the filter.
test "The generated test metaprogram embeds the pattern filter" {
    options: Test_Metaprogram_Options;
    options.workspace_name     = "Juice Test Program";
    options.intermediate_path  = "X:\\demo\\target";
    options.driver_source         = "DRIVER";
    options.package_view_paths = string.["X:\\demo\\src\\a.jai"];
    options.discovery_source   = "X:\\otter\\src\\test_discovery.jai";
    options.pattern            = "add";
    generated := generate_test_metaprogram(options);
    expect(find_index_from_left(generated, "pattern: string = \"add\";\n") >= 0);
    expect(find_index_from_left(generated, "matched := filter_test_entries(entries, pattern);") >= 0);
    expect(find_index_from_left(generated, "print(\"[juice Test] No tests matched '%'.\\n\", pattern);") >= 0);
    expect(find_index_from_left(generated, "print(\"[juice Test] No tests found.\\n\");") >= 0);
    // The empty pattern keeps the same shape with an empty constant.
    options.pattern = "";
    generated = generate_test_metaprogram(options);
    expect(find_index_from_left(generated, "pattern: string = \"\";\n") >= 0);
}

// ---------------------------------------------------------------------------
// Plugin registration option (ticket 042, parent decision 8): the zero-plugin
// text is byte-identical — every plugin extension lives inside the non-empty
// branch — and the registration-backed text carries the plugin face import,
// the registration #load, the compile-time merge and the lint observation.
// ---------------------------------------------------------------------------

test "The generated test metaprogram stays byte-identical with an empty plugin registration" {
    options: Test_Metaprogram_Options;
    options.workspace_name     = "Juice Test Program";
    options.intermediate_path  = "X:\\demo\\target";
    options.import_dirs        = string.["X:\\demo\\modules"];
    options.driver_source         = "DRIVER";
    options.package_view_paths = string.["X:\\demo\\src\\a.jai", "X:\\demo\\src\\b.jai"];
    options.path_pairs         = Test_Path_Pair.[.{ view = "X:\\demo\\src\\a.jai", original = "src/a.jai" }];
    options.discovery_source   = "X:\\otter\\src\\test_discovery.jai";
    // The default is "", and an explicit "" produces the pre-plugin text
    // byte for byte: no juice_core import, no registration load, no merge,
    // no lint call, no display-path helper.
    expect(options.plugin_registration == "");
    expect(generate_test_metaprogram(options) == EXPECTED_TEST_METAPROGRAM);
    options.plugin_registration = "";
    options.package_root        = "X:\\demo";
    generated := generate_test_metaprogram(options);
    expect(generated == EXPECTED_TEST_METAPROGRAM);
    expect(find_index_from_left(generated, "juice_core") < 0);
    expect(find_index_from_left(generated, "merged_plugins") < 0);
    expect(find_index_from_left(generated, "display_path_for") < 0);
}

test "The generated test metaprogram loads the registration and merges it before the workspace" {
    options: Test_Metaprogram_Options;
    options.workspace_name      = "Juice Test Program";
    options.intermediate_path   = "X:\\demo\\target";
    options.import_dirs         = string.["X:\\demo\\modules"];
    options.driver_source          = "DRIVER";
    options.package_view_paths  = string.["X:\\demo\\src\\a.jai"];
    options.discovery_source    = "X:\\otter\\src\\test_discovery.jai";
    options.plugin_registration = "X:\\demo\\target\\plugins\\registration.jai";
    options.package_root        = "X:\\demo";
    generated := generate_test_metaprogram(options);

    // The plugin face import precedes the discovery #load, which precedes
    // the registration #load (the registration's references resolve through
    // the shared name-imported juice_core module).
    expect(find_index_from_left(generated,
        "#import \"Compiler\";\n#import \"juice_core\";\n\n#load \"X:/otter/src/test_discovery.jai\";\n\n#load \"X:/demo/target/plugins/registration.jai\";\n") >= 0);
    expect(find_index_from_left(generated, "\"X:\\demo") < 0);

    // The merge runs at the top of #run, before the workspace exists; the
    // package-root anchor is set before it (the relative lint display paths
    // must open on disk). The built-in registry joins the scanned values,
    // then the embedded declaration configs resolve (ticket 056), all before
    // the workspace exists.
    chdir_index := find_index_from_left(generated, "    set_working_directory(\"X:/demo\");\n");
    plugins_index := find_index_from_left(generated, "    plugins: [..] *Juice_Plugin;\n");
    merge_index := find_index_from_left(generated, "    merged_plugins = merge_plugins(plugins);\n");
    resolve_index := find_index_from_left(generated, "    resolved_plugins = resolve_plugin_configs(merged_plugins.registry, plugin_configs);\n");
    workspace_index := find_index_from_left(generated, "    workspace := compiler_create_workspace(");
    expect(chdir_index >= 0 && plugins_index > chdir_index && merge_index > plugins_index && resolve_index > merge_index && workspace_index > resolve_index);

    // Program-level registry/resolver storage, the embedded declaration
    // configs and the loud failure channels: every merge and resolver
    // diagnostic is a compiler error (the compile fails) and the #run
    // returns before any lint can observe.
    expect(find_index_from_left(generated, "merged_plugins: Merged_Plugins;\n") >= 0);
    expect(find_index_from_left(generated, "resolved_plugins: Resolved_Plugins;\n") >= 0);
    expect(find_index_from_left(generated, "plugin_configs: [] Plugin_Config = Plugin_Config.[];") >= 0);
    expect(find_index_from_left(generated, "    if !merged_plugins.ok {\n") >= 0);
    expect(find_index_from_left(generated, "        for diagnostic: merged_plugins.diagnostics compiler_report(diagnostic.message, mode = .ERROR);\n") >= 0);
    expect(find_index_from_left(generated, "    if !resolved_plugins.ok {\n") >= 0);
    expect(find_index_from_left(generated, "        for diagnostic: resolved_plugins.diagnostics compiler_report(diagnostic.message, mode = .ERROR);\n") >= 0);
    expect(find_index_from_left(generated, "        return;\n") >= 0);
}

test "The generated test metaprogram embeds the declaration configs (ids, versions, option rows)" {
    options: Test_Metaprogram_Options;
    options.workspace_name      = "Juice Test Program";
    options.intermediate_path   = "X:\\demo\\target";
    options.driver_source          = "DRIVER";
    options.package_view_paths  = string.["X:\\demo\\src\\a.jai"];
    options.discovery_source    = "X:\\otter\\src\\test_discovery.jai";
    options.plugin_registration = "X:\\demo\\target\\plugins\\registration.jai";
    options.package_root        = "X:\\demo";
    options.plugin_configs      = Plugin_Config.[
        .{id = "juice-plugin-lint", version = "0.1.0"},
        .{id = "opt", version = "1.0.0", options = Option_Row.[
            .{key = "label", value = "clean"},
        ]},
    ];
    generated := generate_test_metaprogram(options);
    expect(find_index_from_left(generated,
        "plugin_configs: [] Plugin_Config = Plugin_Config.[.{ id = \"juice-plugin-lint\", version = \"0.1.0\", options = Option_Row.[] }, .{ id = \"opt\", version = \"1.0.0\", options = Option_Row.[.{ key = \"label\", value = \"clean\" }] }];") >= 0);
}

test "The generated test metaprogram observes lint findings at collection time" {
    options: Test_Metaprogram_Options;
    options.workspace_name      = "Juice Test Program";
    options.intermediate_path   = "X:\\demo\\target";
    options.driver_source          = "DRIVER";
    options.package_view_paths  = string.["X:\\demo\\src\\a.jai"];
    options.path_pairs          = Test_Path_Pair.[.{ view = "X:\\demo\\src\\a.jai", original = "src/a.jai" }];
    options.discovery_source    = "X:\\otter\\src\\test_discovery.jai";
    options.plugin_registration = "X:\\demo\\target\\plugins\\registration.jai";
    options.package_root        = "X:\\demo";
    options.pattern             = "some";
    generated := generate_test_metaprogram(options);

    // The observer call sits inside collect_test_headers, after the note
    // match, the enclosing-path read and the source-isolation predicate —
    // the same predicate collection applies — so imported modules never
    // reach a rule. The pattern filter runs later (in inject_test_runner),
    // so filtering can never hide a finding.
    collect_index := find_index_from_left(generated, "collect_test_headers :: (typechecked: *Message_Typechecked) {");
    collect_add_index := find_index_from_left(generated, "array_add(*collected_sources, .{ name = header.name, path = path });");
    allowed_index := find_index_from_left(generated, "if source_path_allowed(path, package_view_paths, whitelist_paths) {");
    observer_index := find_index_from_left(generated, "for finding: lint.inspect_test_header(header, tc.subexpressions) {");
    report_index := find_index_from_left(generated, "compiler_report(display_path_for(path), finding.line, finding.column, finding.message, mode);");
    filter_index := find_index_from_left(generated, "matched := filter_test_entries(entries, pattern);");
    expect(collect_index >= 0 && collect_add_index > collect_index && allowed_index > collect_add_index);
    expect(observer_index > allowed_index && report_index > observer_index);
    expect(filter_index > report_index);

    // The level mapping onto the compiler_report three-sink (WARNING is the
    // default; findings carry 1-based coordinates the host passes through).
    expect(find_index_from_left(generated, "mode := Report.WARNING;") >= 0);
    expect(find_index_from_left(generated, "if finding.level == .ERROR mode = Report.ERROR;") >= 0);
    expect(find_index_from_left(generated, "if finding.level == .INFO mode = Report.INFO;") >= 0);

    // The display path comes from the embedded path pairs, with the raw path
    // as the no-match fallback.
    expect(find_index_from_left(generated, "display_path_for :: (path: string) -> string {") >= 0);
    expect(find_index_from_left(generated, "        if pair.view == path return pair.original;\n") >= 0);
    expect(find_index_from_left(generated, "    return path;\n}\n\ninject_test_runner ::") >= 0);

    // The runner injection surface is unchanged.
    expect(find_index_from_left(generated, "add_build_string(generate_test_runner_code(matched, path_pairs), workspace);\n") >= 0);
}

test "The generated test metaprogram slashes every quoted path" {
    options: Test_Metaprogram_Options;
    options.workspace_name     = "Juice Test Program";
    options.intermediate_path  = "X:\\demo\\target";
    options.driver_source         = "DRIVER";
    options.package_view_paths = string.["X:\\demo\\src\\a.jai"];
    options.discovery_source   = "X:\\otter\\src\\test_discovery.jai";
    generated := generate_test_metaprogram(options);
    // Every quoted path appears "/"-separated. The ticket 018 print lines
    // carry \n escape sequences, so the blanket no-backslash scan no longer
    // holds — the quoted-path contract is pinned per path instead.
    expect(find_index_from_left(generated, "add_build_string(\"DRIVER\", workspace);\n") >= 0);
    expect(find_index_from_left(generated, "\"X:/otter/src/test_discovery.jai\"") >= 0);
    expect(find_index_from_left(generated, "\"X:/demo/src/a.jai\"") >= 0);
    expect(find_index_from_left(generated, "\"X:/demo/target\"") >= 0);
    expect(find_index_from_left(generated, "\"X:\\demo") < 0);
}

// The Testing module compile view prepend (ticket 028 t9): the view
// directory joins the import paths before the shared import directories so
// `#import "Testing"` resolves to the generated view (the build side's
// Compiler_Metaprogram_Options shape).
test "The generated test metaprogram prepends the Testing module view directory" {
    options: Test_Metaprogram_Options;
    options.workspace_name     = "Juice Test Program";
    options.intermediate_path  = "X:\\demo\\target";
    options.import_dirs        = string.["X:\\demo\\modules"];
    options.testing_view_dir   = "X:/demo/target/transpile/testing-module";
    options.driver_source         = "DRIVER";
    options.package_view_paths = string.["X:\\demo\\src\\a.jai"];
    options.discovery_source   = "X:\\otter\\src\\test_discovery.jai";
    generated := generate_test_metaprogram(options);
    expect(find_index_from_left(generated,
        "    array_add(*import_paths, \"X:/demo/target/transpile/testing-module\");\n    array_add(*import_paths, \"X:/demo/modules\");") >= 0);
    // The whitelist wiring is the paired handover point: the generated text
    // carries the whitelist constant the caller fills.
    expect(find_index_from_left(generated, "whitelist_paths: [] string = string.[];") >= 0);
}

// The injected runner code, byte for byte (ticket 035's single shape): the
// path mapping reset and rewrite, one run call per numbered entry (the
// published bare names), and the finish() aggregate turning the failure
// count into a compile error — the old juice driver run-list shape driven
// through the same register the test bodies assert through.
EXPECTED_RUNNER_CODE :: "#run {\n    array_reset(*path_mapping);\n    array_add(*path_mapping, .{ view = \"C:/pkg/src/a.jai\", original = \"src/a.jai\" });\n    run(\"test_alpha\", test_alpha);\n    run(\"test_beta\", test_beta);\n    if finish() != 0 assert(false);\n}\n";

test "The injected runner code matches the byte-locked call table shape" {
    entries := Numbered_Test.[
        .{ number = 1, name = "test_alpha" },
        .{ number = 2, name = "test_beta" },
    ];
    pairs := Test_Path_Pair.[.{ view = "C:/pkg/src/a.jai", original = "src/a.jai" }];
    code := generate_test_runner_code(entries, pairs);
    expect(code == EXPECTED_RUNNER_CODE);
    // The retired prefixed names never leak into the single-face runner.
    expect(find_index_from_left(code, "Testing_run") < 0);
    expect(find_index_from_left(code, "Testing_finish") < 0);
    expect(find_index_from_left(code, "Testing_path_mapping") < 0);
}

test "The injected runner code with no entries keeps the bare reset/finish shape" {
    expect(generate_test_runner_code(Numbered_Test.[], Test_Path_Pair.[]) ==
        "#run {\n    array_reset(*path_mapping);\n    if finish() != 0 assert(false);\n}\n");
}

test "The injected runner code escapes quoted strings" {
    pairs := Test_Path_Pair.[.{ view = "C:\\pkg\\we\"ird", original = "src/a.jai" }];
    code := generate_test_runner_code(Numbered_Test.[], pairs);
    expect(find_index_from_left(code, "view = \"C:\\\\pkg\\\\we\\\"ird\"") >= 0);
}

// The metaprogram injects the single bare runner with no face-selection
// literal (ticket 035 retired the ticket 033 option).
test "The generated test metaprogram injects the single bare runner" {
    options: Test_Metaprogram_Options;
    options.workspace_name     = "Juice Test Program";
    options.intermediate_path  = "X:\\demo\\target";
    options.driver_source         = "DRIVER";
    options.package_view_paths = string.["X:\\demo\\src\\a.jai"];
    options.discovery_source   = "X:\\otter\\src\\test_discovery.jai";
    generated := generate_test_metaprogram(options);
    expect(find_index_from_left(generated, "add_build_string(generate_test_runner_code(matched, path_pairs), workspace);\n") >= 0);
    expect(find_index_from_left(generated, "path_pairs, true") < 0);
}

// ---------------------------------------------------------------------------
// E2E start: real jai children compile the generated metaprogram on the
// @test fixtures — the test program really compiles and the injected #run
// really executes (run_test_program_child in test_support drives the
// production generator faces directly; the test command lands with 018).
// ---------------------------------------------------------------------------

test "E2E: the test metaprogram discovers and runs the fixture's @test procedures" {
    result, output, _ := run_test_program_child("test-fixture");
    expect(expect_exit("test-fixture", result, 0, "test metaprogram child"));
    expect(child_output_contains("test-fixture", output, "[test] juice_test_2"));
    expect(child_output_contains("test-fixture", output, "[test] juice_test_10"));
    expect(child_output_contains("test-fixture", output, "[test] test_alpha"));
    expect(child_output_contains("test-fixture", output, "[test] test_beta"));
    expect(child_output_contains("test-fixture", output, "[test] test_gamma"));
    expect(child_output_contains("test-fixture", output, "5 passed, 0 failed"));

    // The deterministic order: name sort with the numeric-aware juice_test_N
    // prefix (juice_test_2 runs before juice_test_10 — tests_a.jai declares
    // them the other way around on purpose; plain lexicographic order would
    // put 10 first), whatever the message order.
    n2 := find_index_from_left(output, "[test] juice_test_2");
    n10 := find_index_from_left(output, "[test] juice_test_10");
    alpha := find_index_from_left(output, "[test] test_alpha");
    beta := find_index_from_left(output, "[test] test_beta");
    gamma := find_index_from_left(output, "[test] test_gamma");
    expect(n2 >= 0 && n2 < n10 && n10 < alpha && alpha < beta && beta < gamma);
}

test "E2E: a failing test continues the suite and aggregates the exit code" {
    result, output, _ := run_test_program_child("test-fail");
    expect(expect_exit("test-fail", result, 1, "test metaprogram child"));
    // The suite continues past the failure (the sorted order runs the
    // passing test first), the failure prints the mapped package-relative
    // coordinate, and finish() aggregates the non-zero exit code.
    after := find_index_from_left(output, "[test] test_after");
    boom := find_index_from_left(output, "[test] test_boom");
    expect(after >= 0 && after < boom);
    expect(child_output_contains("test-fail", output, "src/failing.jai:"));
    expect(child_output_contains("test-fail", output, "boom"));
    expect(child_output_contains("test-fail", output, "1 passed, 1 failed"));
}

// ---------------------------------------------------------------------------
// Plugin lint E2E (ticket 042): the synthetic plugin-lint fixture through the
// production scan -> production registration codegen -> production
// driver/metaprogram generators -> a real jai child. The fixture plugin's
// rule warns on test procedure names containing "Bad"; the test source
// imports a module whose own Bad-named @test must stay untouched (the
// source-isolation face), and the child runs the tests under the fixture
// package root (the lint display paths are original package-relative paths).
// ---------------------------------------------------------------------------

test "E2E: the test metaprogram reports plugin lint findings and still runs the tests" {
    result, output, errors := run_plugin_lint_child("plugin-lint-fixture", "plugin-lint-fixture", string.["tests/bad_name_tests.jai"]);
    expect(expect_exit("plugin-lint", result, 0));
    // Both tests still run and count normally: a WARNING never changes the
    // exit code (parent US 18).
    expect(output_matches("plugin-lint", output, string.[
        "[test] BadNameTest",
        "[test] test_good_name",
        "2 passed, 0 failed",
    ]));
    // The finding arrives as a compiler report (stderr): the original
    // package-relative path, the 1-based declaration line/column and the
    // rule message. The line is computed from the fixture (never hardcoded);
    // the column is the typechecked header's own value (the declaration
    // line's "(" position, 1-based by the compiler's header reporting).
    lint_file := path_slashes(tprint("%1/tests/data/plugin-lint-fixture/tests/bad_name_tests.jai", otter_root()));
    line, _ := fixture_line_col(lint_file, "BadNameTest :: (");
    expect(line != 0);
    expect(child_output_contains("plugin-lint", errors,
        tprint("tests/bad_name_tests.jai:%1,16: Warning: [juice lint] test procedure name contains 'Bad': BadNameTest", line)));
    // A warning must not turn into a compile error.
    expect(output_matches("plugin-lint", errors, string.["Error:"], want = false));
}

test "E2E: the pattern filter never hides lint findings" {
    result, output, errors := run_plugin_lint_child("plugin-lint-fixture", "plugin-lint-fixture", string.["tests/bad_name_tests.jai"], pattern = "test_good");
    expect(expect_exit("plugin-lint pattern", result, 0));
    // Only the matching test executes (lint observes at collection time,
    // before the filter), but BadNameTest's finding still prints.
    expect(output_matches("plugin-lint pattern", output, string.["[test] test_good_name", "1 passed, 0 failed"]));
    expect(output_matches("plugin-lint pattern", output, string.["[test] BadNameTest"], want = false));
    expect(child_output_contains("plugin-lint pattern", errors, "BadNameTest"));
}

test "E2E: imported modules are neither collected nor linted" {
    result, output, errors := run_plugin_lint_child("plugin-lint-fixture", "plugin-lint-fixture", string.["tests/bad_name_tests.jai"]);
    expect(expect_exit("plugin-lint isolation", result, 0));
    // The imported module carries a Bad-named @test too, but its enclosing
    // load is outside the package view set: neither a [test] line nor a lint
    // warning may name it.
    expect(output_matches("plugin-lint isolation", output, string.["BadImportedTest"], want = false));
    expect(output_matches("plugin-lint isolation", errors, string.["BadImportedTest"], want = false));
    // Exactly the two package tests count.
    expect(child_output_contains("plugin-lint isolation", output, "2 passed, 0 failed"));
}

test "E2E: a plugin merge failure fails the test compile and runs nothing" {
    // The bad fixture contributes two plugins with the same id: the merge
    // rejects the set. Pairing it with the lint fixture's test program proves
    // the rejection happens before any workspace or lint observation.
    result, output, errors := run_plugin_lint_child("plugin-fixture-bad", "plugin-lint-fixture", string.["tests/bad_name_tests.jai"]);
    expect(expect_exit("plugin-lint merge", result, 1));
    expect(child_output_contains("plugin-lint merge", errors, "Error: duplicate plugin registration: bad-shared"));
    expect(output_matches("plugin-lint merge", output, string.["[test]"], want = false));
    expect(output_matches("plugin-lint merge", output, string.["passed"], want = false));
}
