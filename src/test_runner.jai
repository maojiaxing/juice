#import "Basic";
#import "String";
#import "File";
#import "File_Utilities";
#import "Process";

// ---------------------------------------------------------------------------
// The test runner module (candidate 2's single-program slice): the driver
// source generator, the test runner entry generator (the compiler drive
// skeleton with the note-enumeration message loop), and the COMPILE front
// that embeds the driver source into the single generated test_runner.jai
// entry and spawns the compiler child.
//
// The driver is no longer a second generated file: generate_test_metaprogram
// embeds its text as an add_build_string argument. Spike-pinned: an added
// build string resolves #import / #load, and its #run executes before the
// runner string injected at TYPECHECKED_ALL_WE_CAN — so the driver's
// set_working_directory anchor still lands before the test bodies run.
//
// This file must stay test-free (the src module discipline — its tests live
// in tests/test_runner_tests.jai). Every path the generated text quotes must
// be absolute and "/"-separated: the child jai switches its #run working
// directory to the metaprogram's own directory (target/transpile for the
// test runner, target/build for the build drivers), so relative paths would
// resolve one layer deeper (the old juice 058 deviation ④ discipline).
// ---------------------------------------------------------------------------

// The test driver generation options: the discovered package files in #load
// order (the scan order — deterministic) and the package root the
// compile-time #run anchors as the working directory. The driver always
// imports the published Testing face (ticket 035's single register): the t9
// compile view on the metaprogram's import path resolves `#import
// "Testing"` to the flat published face (or to the package's in-package
// module EXPAND view), so the test bodies' bare assertions and the injected
// bare-name runner share one register (006 spec decision 2).
Test_Driver_Options :: struct {
    source_files:        [] string;
    package_root:        string;
}

// The generated test driver: an entry-point-free source whose compile-time
// #run anchors the working directory at the package root (the jai child
// would otherwise resolve relative paths against the metaprogram's own
// directory — the 009 deviation 2 discipline), declares the package root as
// a constant (C4: the test program's intermediate path is target/build/,
// C5, so helpers cannot recover the root from Build_Options.intermediate_path),
// then imports the published Testing face and #loads every discovered package
// file's view into the test program. The test list itself is not known at
// generation time — the runner injects it after collection (spec section
// 7.2). The source is embedded in the runner entry via add_build_string; it
// never lands as its own file.
generate_test_driver :: (options: Test_Driver_Options) -> string {
    builder: String_Builder;
    print_to_builder(*builder, "#import \"Basic\";\n\n");
    print_to_builder(*builder, "// Compile-time execution resolves relative paths against the metaprogram's\n");
    print_to_builder(*builder, "// own directory (the jai child anchors its working directory at the entry\n");
    print_to_builder(*builder, "// file); the package root anchor is set explicitly so test bodies resolve\n");
    print_to_builder(*builder, "// relative paths against it (the 009 deviation 2 discipline).\n");
    print_to_builder(*builder, "// The package root constant (C4): the test program's intermediate path is\n");
    print_to_builder(*builder, "// target/build/ (C5), so test helpers use this constant instead of\n");
    print_to_builder(*builder, "// Build_Options.intermediate_path.\n");
    print_to_builder(*builder, "JUICE_TEST_PACKAGE_ROOT :: %1;\n\n", quote_jai_string(path_slashes(options.package_root)));
    print_to_builder(*builder, "#run { set_working_directory(%1); }\n\n", quote_jai_string(path_slashes(options.package_root)));
    // The published Testing face (ticket 035): every test program consumes
    // the single register through this import — the t9 compile view on the
    // import path resolves it to the flat published face (or the package's
    // in-package module view), and the injected runner drives the same bare
    // names the test bodies assert through.
    print_to_builder(*builder, "#import \"Testing\";\n\n");
    for file: options.source_files {
        print_to_builder(*builder, "#load %1;\n", quote_jai_string(path_slashes(file)));
    }
    return builder_to_string(*builder);
}

// The test metaprogram generation options: the workspace name, the
// intermediate directory (absolute — jai has no command-line flag for it),
// the extra import directories (in emission order), the Testing module
// compile view directory (ticket 028 t9 — prepended before the import
// directories so `#import "Testing"` resolves to the generated view instead
// of the module source file; "" = disabled, the same convention as
// Compiler_Metaprogram_Options.testing_view_dir), the embedded driver
// source (the #import "Testing" + #load view text — added as one build
// string, never a second file), the source-isolation file set (the package
// files exactly as the driver #loads them, fully pathed — the compiler's
// enclosing_load echo), the Testing module whitelist (the in-package
// self-test blocks' compile view — wired by ticket 028, empty before), the
// path-mapping pairs embedded at generation time, the discovery surface
// source (#loaded by the generated text), the global numbering continuation
// (juice t3 semantics), the post-collection pattern filter (ticket 018,
// spec section 7.3) and the workspace plugin registration file (ticket 042,
// spec §8.2): "" = no plugins (the generated text stays byte-identical to
// the pre-plugin shape — zero-plugin workspaces pay no import or compile
// cost); non-empty = the generated text imports juice_core, #loads the
// registration, merges the scanned registry at the top of #run and observes
// every isolated test header through the merged lint faces. The injected
// runner is always the published bare-name register (ticket 035) — there is
// no face-selection option.
Test_Metaprogram_Options :: struct {
    workspace_name:     string;
    intermediate_path:  string;
    import_dirs:        [] string;
    testing_view_dir:   string = "";
    // The driver source (generate_test_driver's output), embedded with
    // add_build_string after the intercept begins. The driver's #run runs
    // before the injected runner (the spike-pinned ordering), so its
    // set_working_directory anchor lands first. "" = no driver (test-only
    // shapes; the production COMPILE front always fills it).
    driver_source:      string = "";
    package_view_paths: [] string;
    whitelist_paths:    [] string;
    path_pairs:         [] Test_Path_Pair;
    discovery_source:   string;
    numbering_start:    s64 = 1;
    // "" runs every collected test; otherwise only names containing the
    // pattern (substring, case-sensitive — the old juice filter semantics).
    // Discovery never sees the filter (spec section 7.3).
    pattern:            string = "";
    // "" = no plugin registration (the generated text is byte-identical to
    // the pre-plugin shape); otherwise the absolute path of the generated
    // workspace registration file. The generated text imports juice_core,
    // #loads the registration, merges the built-in + scanned registry
    // (a merge failure reports every diagnostic as a compile error), then
    // resolves the declaration configs (ticket 056: options apply/validate,
    // version checks, declared face order — a resolver failure is a compile
    // error too) and invokes the resolved lint faces for every isolated test
    // header at collection time (ticket 042).
    plugin_registration: string = "";
    // The Package.plugins declarations converted to the shared plugin-face
    // config shape (src/plugin.jai's Plugin_Config / Option_Row). Embedded
    // as a literal; the generated #run resolves the scanned registry against
    // them. Only meaningful with plugin_registration != "" (member plugin
    // values exist only in this generated program in Phase 1).
    plugin_configs:      [] Plugin_Config;
    // The package root the generated metaprogram anchors as its working
    // directory when a plugin registration is loaded. The jai child anchors
    // at the metaprogram's own directory (target/transpile), and the
    // driver's own #run chdir runs too late for collection-time reports —
    // compiler_report opens the reported file on disk when it prints the
    // source line, so the original package-relative display paths only
    // resolve with this anchor. Ignored when plugin_registration == "" (the
    // zero-plugin text stays byte-identical).
    package_root:        string = "";
}

// The generated test runner entry (the old juice shape — entry first.jai —
// extended with the note-enumeration collection, spec section 7.1/7.2):
// NO_OUTPUT so the test program has no entry point, the driver source added
// as a build string after the intercept begins, and a message loop that
// accumulates every .TYPECHECKED procedure header with a matching note and,
// once at .PHASE == .TYPECHECKED_ALL_WE_CAN (the official collection time,
// guarded so later phases never re-inject), wires the discovery surface:
// collect_test_entries isolates, orders, rejects duplicates and numbers the
// accumulated stream; the ticket 018 extension filters the collected list
// by the embedded pattern constant, short-circuits the zero-entry case with
// the old juice "No tests found" message (t4 semantics — the compile IS the
// discovery in 1b, so the short circuit prints instead of skipping the
// compile) and reports a pattern zero-match with "No tests matched";
// generate_test_runner_code builds the explicit call table, added with
// add_build_string — single compilation, no two-compilation probe. A
// duplicate name reports a compile error through compiler_report; the
// injected #run executes at compile time with the old juice semantics
// (failures continue, finish() aggregates the exit code).
//
// Registration-backed metaprograms (ticket 042; declaration-driven since
// ticket 056): the text additionally imports juice_core and #loads the
// workspace registration file, merges the built-in + scanned registry at the
// top of #run (every merge diagnostic becomes a compile error; no workspace
// and no lint on failure), resolves the embedded declaration configs through
// resolve_plugin_configs (options apply/validate, version checks, declared
// face order — resolver diagnostics are compile errors too) and calls every
// resolved lint face's inspect_test_header for each isolated test header at
// collection time. Findings map their level onto the compiler_report
// three-sink and their view path back to the original package-relative path
// through the embedded path pairs. The zero-plugin text stays byte-identical
// (parent decision 8).
generate_test_metaprogram :: (options: Test_Metaprogram_Options) -> string {
    builder: String_Builder;
    print_to_builder(*builder, "#import \"Basic\";\n");
    print_to_builder(*builder, "#import \"Compiler\";\n");
    if options.plugin_registration != "" {
        // The plugin face (Juice_Plugin / Lint_Plugin / merge_plugins) comes
        // from the published juice_core module — the same name-imported
        // module the registration file's plugin modules import (one shared
        // type identity per program; a #load duplicate would split it).
        print_to_builder(*builder, "#import \"juice_core\";\n");
    }
    print_to_builder(*builder, "\n");
    print_to_builder(*builder, "#load %1;\n\n", quote_jai_string(path_slashes(options.discovery_source)));
    if options.plugin_registration != "" {
        // The generated workspace registration file (ticket 043): its
        // get_scanned_plugins() assembly and the plugin module imports are
        // visible to the #run below. The path is absolute and
        // "/"-separated, like every path the generated text quotes.
        print_to_builder(*builder, "#load %1;\n\n", quote_jai_string(path_slashes(options.plugin_registration)));
    }
    print_to_builder(*builder, "#run {\n");
    print_to_builder(*builder, "    set_build_options_dc(.{do_output = false});\n");
    if options.plugin_registration != "" {
        if options.package_root != "" {
            // Anchor the report working directory at the package root: the
            // lint findings print the original package-relative path through
            // compiler_report, which opens the file on disk to show the
            // source line. The jai child anchors at the metaprogram's own
            // directory and the driver's #run chdir runs too late for
            // collection-time reports, so the anchor is set here, before the
            // workspace exists.
            print_to_builder(*builder, "    set_working_directory(%1);\n", quote_jai_string(path_slashes(options.package_root)));
        }
        // Merge the built-in registry with the scanned member plugins before
        // any workspace exists: the merged registry keeps every plugin value
        // (ticket 056 — merge no longer pre-filters a pipeline). A rejected
        // plugin set (duplicate ids, lint name conflicts, at-mount clashes)
        // reports every diagnostic as a compile error and never observes a
        // test header (ticket 042; the generated registration is the only
        // third-party injection surface — the CLI process never consumes
        // these values).
        print_to_builder(*builder, "    plugins: [..] *Juice_Plugin;\n");
        print_to_builder(*builder, "    for plugin: builtin_plugins() array_add(*plugins, plugin);\n");
        print_to_builder(*builder, "    for plugin: get_scanned_plugins() array_add(*plugins, plugin);\n");
        print_to_builder(*builder, "    merged_plugins = merge_plugins(plugins);\n");
        print_to_builder(*builder, "    if !merged_plugins.ok {\n");
        print_to_builder(*builder, "        for diagnostic: merged_plugins.diagnostics compiler_report(diagnostic.message, mode = .ERROR);\n");
        print_to_builder(*builder, "        return;\n");
        print_to_builder(*builder, "    }\n");
        // The declaration-driven resolution (ticket 056): options are
        // applied/validated on the scanned values, versions checked, and the
        // declared faces selected in declaration order. The resolved product
        // is the only source the lint observation below consumes — an
        // undeclared rule never runs.
        print_to_builder(*builder, "    resolved_plugins = resolve_plugin_configs(merged_plugins.registry, plugin_configs);\n");
        print_to_builder(*builder, "    if !resolved_plugins.ok {\n");
        print_to_builder(*builder, "        for diagnostic: resolved_plugins.diagnostics compiler_report(diagnostic.message, mode = .ERROR);\n");
        print_to_builder(*builder, "        return;\n");
        print_to_builder(*builder, "    }\n");
    }
    print_to_builder(*builder, "    workspace := compiler_create_workspace(%1);\n", quote_jai_string(options.workspace_name));
    print_to_builder(*builder, "    if !workspace return;\n");
    print_to_builder(*builder, "    options := get_build_options(workspace);\n");
    print_to_builder(*builder, "    options.output_type = .NO_OUTPUT;\n");
    print_to_builder(*builder, "    options.intermediate_path = %1;\n", quote_jai_string(path_slashes(options.intermediate_path)));
    print_to_builder(*builder, "    import_paths: [..] string;\n");
    print_to_builder(*builder, "    array_add(*import_paths, .. options.import_path);\n");
    if options.testing_view_dir != "" {
        // Testing module compile view special case: the view directory is
        // prepended so `#import "Testing"` resolves to the generated view
        // instead of the module source file.
        print_to_builder(*builder, "    array_add(*import_paths, %1);\n", quote_jai_string(options.testing_view_dir));
    }
    for dir: options.import_dirs {
        print_to_builder(*builder, "    array_add(*import_paths, %1);\n", quote_jai_string(path_slashes(dir)));
    }
    print_to_builder(*builder, "    options.import_path = import_paths;\n");
    print_to_builder(*builder, "    set_build_options(options, workspace);\n");
    print_to_builder(*builder, "    compiler_begin_intercept(workspace);\n");
    // The embedded driver source: one build string carrying the
    // #import "Testing" face and the #load view list. add_build_string
    // resolves imports/loads, and the driver's #run executes before the
    // runner injection below (the spike-pinned ordering) — the working
    // directory anchor lands before any test body runs.
    print_to_builder(*builder, "    add_build_string(%1, workspace);\n", quote_jai_string(options.driver_source));
    // The message loop only consumes messages — jai exits non-zero on its
    // own when the intercepted workspace has errors, and calling exit() from
    // a metaprogram would kill the process before jai flushes the collected
    // print output.
    print_to_builder(*builder, "    while true {\n");
    print_to_builder(*builder, "        msg := compiler_wait_for_message();\n");
    print_to_builder(*builder, "        if !msg continue;\n");
    print_to_builder(*builder, "        if msg.workspace == workspace {\n");
    print_to_builder(*builder, "            if msg.kind == {\n");
    print_to_builder(*builder, "                case .TYPECHECKED;\n");
    print_to_builder(*builder, "                    typechecked := cast(*Message_Typechecked) msg;\n");
    print_to_builder(*builder, "                    collect_test_headers(typechecked);\n");
    print_to_builder(*builder, "                case .PHASE;\n");
    print_to_builder(*builder, "                    phase := cast(*Message_Phase) msg;\n");
    print_to_builder(*builder, "                    if phase.phase == .TYPECHECKED_ALL_WE_CAN && !injected {\n");
    print_to_builder(*builder, "                        inject_test_runner(msg.workspace);\n");
    print_to_builder(*builder, "                        injected = true;\n");
    print_to_builder(*builder, "                    }\n");
    print_to_builder(*builder, "                case .ERROR;\n");
    print_to_builder(*builder, "                case .COMPLETE;\n");
    print_to_builder(*builder, "                    break;\n");
    print_to_builder(*builder, "            }\n");
    print_to_builder(*builder, "        }\n");
    print_to_builder(*builder, "    }\n");
    print_to_builder(*builder, "    compiler_end_intercept(workspace);\n");
    print_to_builder(*builder, "}\n\n");
    if options.plugin_registration != "" {
        print_to_builder(*builder, "// The merged plugin registry (registration-backed only): filled at the\n");
        print_to_builder(*builder, "// top of #run from the generated registration file. A merge failure\n");
        print_to_builder(*builder, "// reports every diagnostic as an error and never observes a header.\n");
        print_to_builder(*builder, "merged_plugins: Merged_Plugins;\n\n");
        print_to_builder(*builder, "// The declaration-driven resolution (ticket 056): the resolved pipeline,\n");
        print_to_builder(*builder, "// declared lint list and hook table. A resolver failure (unknown id,\n");
        print_to_builder(*builder, "// version mismatch, option rejection) is a compile error too.\n");
        print_to_builder(*builder, "resolved_plugins: Resolved_Plugins;\n\n");
        print_to_builder(*builder, "// The Package.plugins declarations, embedded as the shared plugin-face\n");
        print_to_builder(*builder, "// config values (Plugin_Config / Option_Row come from juice_core).\n");
        print_to_builder(*builder, "plugin_configs: [] Plugin_Config = Plugin_Config.[");
        for config, config_index: options.plugin_configs {
            if config_index > 0 print_to_builder(*builder, ", ");
            print_to_builder(*builder, ".{ id = %1, version = %2, options = Option_Row.[", quote_jai_string(config.id), quote_jai_string(config.version));
            for row, row_index: config.options {
                if row_index > 0 print_to_builder(*builder, ", ");
                print_to_builder(*builder, ".{ key = %1, value = %2 }", quote_jai_string(row.key), quote_jai_string(row.value));
            }
            print_to_builder(*builder, "] }");
        }
        print_to_builder(*builder, "];\n\n");
    }
    print_to_builder(*builder, "// The one-shot injection guard: adding the runner re-runs the phase, and\n");
    print_to_builder(*builder, "// the collection must never emit twice (how_to/460:68-75 shape).\n");
    print_to_builder(*builder, "injected := false;\n\n");
    print_to_builder(*builder, "// The accumulated header stream (name + enclosing load path), fed by the\n");
    print_to_builder(*builder, "// message loop and consumed once at TYPECHECKED_ALL_WE_CAN.\n");
    print_to_builder(*builder, "collected_sources: [..] Collected_Test_Source;\n\n");
    print_to_builder(*builder, "// The embedded isolation and mapping sets (known at generation time,\n");
    print_to_builder(*builder, "// spec section 7.2).\n");
    print_to_builder(*builder, "package_view_paths: [] string = string.[");
    for path, index: options.package_view_paths {
        if index > 0 print_to_builder(*builder, ", ");
        print_to_builder(*builder, "%1", quote_jai_string(path_slashes(path)));
    }
    print_to_builder(*builder, "];\n");
    print_to_builder(*builder, "whitelist_paths: [] string = string.[");
    for path, index: options.whitelist_paths {
        if index > 0 print_to_builder(*builder, ", ");
        print_to_builder(*builder, "%1", quote_jai_string(path_slashes(path)));
    }
    print_to_builder(*builder, "];\n");
    print_to_builder(*builder, "path_pairs: [] Test_Path_Pair = Test_Path_Pair.[");
    for pair, index: options.path_pairs {
        if index > 0 print_to_builder(*builder, ", ");
        print_to_builder(*builder, ".{ view = %1, original = %2 }", quote_jai_string(path_slashes(pair.view)), quote_jai_string(pair.original));
    }
    print_to_builder(*builder, "];\n\n");
    print_to_builder(*builder, "// The post-collection pattern filter constant (spec section 7.3): \"\" runs\n");
    print_to_builder(*builder, "// every collected test, otherwise only names containing the pattern.\n");
    print_to_builder(*builder, "pattern: string = %1;\n\n", quote_jai_string(options.pattern));
    print_to_builder(*builder, "collect_test_headers :: (typechecked: *Message_Typechecked) {\n");
    print_to_builder(*builder, "    for tc: typechecked.procedure_headers {\n");
    print_to_builder(*builder, "        header := tc.expression;\n");
    print_to_builder(*builder, "        note_texts: [..] string;\n");
    print_to_builder(*builder, "        for note: header.notes array_add(*note_texts, note.text);\n");
    print_to_builder(*builder, "        if !header_is_test(header.name, note_texts) continue;\n");
    print_to_builder(*builder, "        path := \"\";\n");
    print_to_builder(*builder, "        if header.enclosing_load path = header.enclosing_load.fully_pathed_filename;\n");
    print_to_builder(*builder, "        array_add(*collected_sources, .{ name = header.name, path = path });\n");
    if options.plugin_registration != "" {
        // Lint observation at the discovery collection point (ticket 042,
        // spec §8.2; declaration-driven since ticket 056): after the note
        // match and the source-isolation predicate — the same predicate
        // collect_test_entries applies — so imported modules and dependency
        // shims never reach an observer, and the post-collection pattern
        // filter never hides a finding (collection runs before filtering).
        // The observers come from the resolved product: only declared lint
        // faces run, in declaration order, with their options applied.
        // Findings carry 1-based coordinates by contract; the host maps the
        // level onto the compiler_report three sink and rewrites the compiled
        // view path back to the original package-relative path through the
        // embedded path pairs.
        print_to_builder(*builder, "        if source_path_allowed(path, package_view_paths, whitelist_paths) {\n");
        print_to_builder(*builder, "            for lint: resolved_plugins.lint_plugins {\n");
        print_to_builder(*builder, "                for finding: lint.inspect_test_header(header, tc.subexpressions) {\n");
        print_to_builder(*builder, "                    mode := Report.WARNING;\n");
        print_to_builder(*builder, "                    if finding.level == .ERROR mode = Report.ERROR;\n");
        print_to_builder(*builder, "                    if finding.level == .INFO mode = Report.INFO;\n");
        print_to_builder(*builder, "                    compiler_report(display_path_for(path), finding.line, finding.column, finding.message, mode);\n");
        print_to_builder(*builder, "                }\n");
        print_to_builder(*builder, "            }\n");
        print_to_builder(*builder, "        }\n");
    }
    print_to_builder(*builder, "    }\n");
    print_to_builder(*builder, "}\n\n");
    if options.plugin_registration != "" {
        // The original package-relative display path for a lint finding: the
        // embedded path pairs (the same mapping the test failure report uses)
        // rewrite the compiled view path back to the source path; an unmapped
        // path passes through untouched.
        print_to_builder(*builder, "display_path_for :: (path: string) -> string {\n");
        print_to_builder(*builder, "    for pair: path_pairs {\n");
        print_to_builder(*builder, "        if pair.view == path return pair.original;\n");
        print_to_builder(*builder, "    }\n");
        print_to_builder(*builder, "    return path;\n");
        print_to_builder(*builder, "}\n\n");
    }
    print_to_builder(*builder, "inject_test_runner :: (workspace: Workspace) {\n");
    print_to_builder(*builder, "    entries, duplicate_name := collect_test_entries(collected_sources, package_view_paths, whitelist_paths, %1);\n", options.numbering_start);
    print_to_builder(*builder, "    if duplicate_name != \"\" {\n");
    print_to_builder(*builder, "        compiler_report(tprint(\"duplicate test name: \%\", duplicate_name));\n");
    print_to_builder(*builder, "        return;\n");
    print_to_builder(*builder, "    }\n");
    print_to_builder(*builder, "    matched := filter_test_entries(entries, pattern);\n");
    print_to_builder(*builder, "    if entries.count == 0 {\n");
    print_to_builder(*builder, "        print(\"[juice Test] No tests found.\\n\");\n");
    print_to_builder(*builder, "        return;\n");
    print_to_builder(*builder, "    }\n");
    print_to_builder(*builder, "    if matched.count == 0 {\n");
    print_to_builder(*builder, "        print(\"[juice Test] No tests matched '\%'.\\n\", pattern);\n");
    print_to_builder(*builder, "        return;\n");
    print_to_builder(*builder, "    }\n");
    print_to_builder(*builder, "    add_build_string(generate_test_runner_code(matched, path_pairs), workspace);\n");
    print_to_builder(*builder, "}\n");
    return builder_to_string(*builder);
}

// ---------------------------------------------------------------------------
// COMPILE stage: the single test runner entry and the spawned compiler child
// ---------------------------------------------------------------------------

// The COMPILE stage state: the TRANSPILE stage's outputs plus the pattern
// constant. The command builds the stage and dispatches the lifecycle
// hooks; the built-in COMPILE front below consumes it.
Test_Compile_Stage :: struct {
    prepared:            *Juice.Prepared_Workspace;
    files:               [] Scan_File;
    view_paths:          [] string;
    transpile_dir:       string;
    testing_module_dir:  string;
    testing_module_view: string;
    pattern:             string;
    // The command-level prepare's workspace registration path (ticket 060;
    // "" = no declared member plugins). The COMPILE front consumes it
    // directly — it never scans or writes the registration itself.
    registration_path:   string;
}

// Production spawn of the test program child: jai compiles the generated
// test runner with -quiet (the compiler's banner and stats are noise; the
// test program's compile-time output — start lines, failures, the summary
// and the zero-entry short circuit messages — passes through untouched),
// and the jai exit code carries pass/fail (compile errors from the
// finish()/assert gate included).
//
// import_dirs are the same compiler_import_directories the generated runner
// installs on the inner workspace (the juice modules directory and the
// dependency shim directory). They must also reach the child's own module
// search path: a plugin registration (ticket 045) makes the runner file
// itself `#import "juice_core"` and the registration `#import` the scanned
// plugin module names at the top level — before #run can configure the
// workspace, so the inner import path is too late for them. Zero-plugin
// runs pass the same directories; their generated text imports nothing from
// them, so the compile is unchanged.
spawn_test_compiler :: (runner_path: string, import_dirs: [] string) -> Process_Result {
    args: [..] string;
    array_add(*args, "jai");
    array_add(*args, "-quiet");
    // The import directories precede the entry file: build.jai's #run (a
    // root file joined into every test program) recognizes a test-program
    // compile by the last command-line argument ending in the shared
    // TEST_RUNNER_FILE_NAME (src/metaprogram.jai) and skips its own
    // self-build — the runner path must stay last.
    for dir: import_dirs {
        array_add(*args, "-import_dir");
        array_add(*args, dir);
    }
    array_add(*args, runner_path);
    return run_command(..args);
}

// The discovery surface source (ticket 003 decision 2, ticket 017): the
// generated runner #loads the discovery pure-function face from the
// published internal artifact next to the running executable —
// <exe>/modules/juice_internal/test_discovery.jai, the verbatim copy of
// src/test_discovery.jai the publish step lands every build (spec 006
// decision 4, ticket 037). The dev tree and an installed/packaged layout
// share this path contract: the executable needs only its adjacent modules
// directory, never a sibling src/ (the retired bootstrap_src_dir
// <exe>/../src derivation). The Testing face does not read it: since ticket
// 035 every test program consumes the published face through
// `#import "Testing"` (the t9 compile view on the import path), so the old
// source-face loading path is gone.
discovery_face_source :: () -> string {
    return test_discovery_module_path(juice_modules_dir());
}

// The COMPILE stage's built-in implementation: the t12 single test runner
// entry (the embedded driver source plus the note-enumeration loop) and the
// spawned jai. The spawn step is an internal test seam (the built-in
// implementation's own injection point — NOT a lifecycle mount: the COMPILE
// at hook replaces this whole front). The runner is regenerated and written
// on every run, never cached — it lives at the transpile tree root next to
// the hash directories.
test_compile_front :: (stage: *Test_Compile_Stage, spawn: #type (runner_path: string, import_dirs: [] string) -> Process_Result = spawn_test_compiler) -> bool {
    prepared := stage.prepared;
    root_dir := prepared.discovery.root_dir;

    // Plugin registration consumption (tickets 045/056; command-level prepare
    // since ticket 060): the registration path comes from the command's
    // single prepare step — this front never scans member packages or writes
    // the registration again. Non-empty means the root package declared at
    // least one member plugin: the generated program #loads the same file the
    // PRESTEP host consumed and resolves the embedded member declaration
    // configs against the scanned registry (options apply/validate, version
    // checks, declared lint order). Zero hits leave everything empty, so the
    // generated text stays byte-identical to the pre-plugin shape.
    plugin_registration := stage.registration_path;

    // The single test program shape (ticket 035, spec 006 decision 2):
    // every package's driver imports the published Testing face through
    // `#import "Testing"` (the t9 compile view on the import path resolves
    // it to the published flat face, or to the package's in-package module
    // EXPAND view), and the injected runner drives the same bare register
    // the test bodies' assertions write. The retired prefixed source-face
    // loading path had split the register: the runner counted the prefixed
    // face while bare assertions registered on the published one, so
    // failing user packages printed `expect failed` but exited 0.

    // The embedded driver source: anchors the compile-time working directory
    // at the package root (the 009 deviation 2 discipline), imports the
    // published Testing face and #loads every discovered file's view in scan
    // order. It travels as an add_build_string argument in the runner entry —
    // no driver file lands on disk.
    driver_options: Test_Driver_Options;
    driver_options.package_root = root_dir;
    driver_options.source_files = stage.view_paths;
    driver_source := generate_test_driver(driver_options);

    // The test runner entry: the note-enumeration message loop with the
    // embedded source-isolation set (the compiled views exactly as the
    // driver #loads them, fully pathed — the compiler's enclosing_load echo),
    // the Testing module compile view whitelist (the in-package self-test
    // blocks' view), the path mapping (view = the compiled view path,
    // original = the package-relative path), the Testing module import
    // prepend ("" = disabled), the global numbering base (1 — juice t3)
    // and the post-collection pattern filter.
    runner_path := target_session_driver_path(stage.transpile_dir, TEST_RUNNER_FILE_NAME);
    test_build_dir := target_build_dir(package_target_dir(root_dir));
    if !make_directory_if_it_does_not_exist(test_build_dir, recursive = true) {
        print("[juice ERROR] Could not create the test build directory: %\n", test_build_dir);
        return false;
    }
    metaprogram_options: Test_Metaprogram_Options;
    metaprogram_options.workspace_name     = "Juice Test Program";
    // C5: the test program's compiler intermediates (the .added_strings
    // file, objects if any) land in target/build, not the artifact root.
    metaprogram_options.intermediate_path  = test_build_dir;
    // compiler_import_directories is shared with build: target/packages (the
    // dependency shim directory) must be on the search path so the root test
    // program can #import dependencies (including workspace members).
    import_dirs: [..] string;
    for dir: compiler_import_directories(packages_dir(root_dir)) array_add(*import_dirs, dir);
    metaprogram_options.import_dirs        = import_dirs;
    metaprogram_options.driver_source      = driver_source;
    metaprogram_options.package_view_paths = stage.view_paths;
    if stage.testing_module_view != "" {
        whitelist: [..] string;
        array_add(*whitelist, stage.testing_module_view);
        metaprogram_options.whitelist_paths = whitelist;
    }
    pairs: [..] Test_Path_Pair;
    for file, index: stage.files {
        array_add(*pairs, .{ view = stage.view_paths[index], original = file.rel_path });
    }
    if stage.testing_module_view != "" {
        array_add(*pairs, .{ view = stage.testing_module_view, original = "modules/Testing.jai" });
    }
    metaprogram_options.path_pairs       = pairs;
    metaprogram_options.discovery_source = discovery_face_source();
    metaprogram_options.numbering_start  = 1;
    metaprogram_options.pattern          = stage.pattern;
    metaprogram_options.testing_view_dir = stage.testing_module_dir;
    if plugin_registration != "" {
        // The three options go together (tickets 042/056): the generated
        // text loads the registration and anchors its working directory at
        // the package root (so lint findings' original package-relative paths
        // resolve when compiler_report opens them during collection), and it
        // embeds the declaration configs — the generated program resolves
        // the scanned registry against them, so options apply/validate,
        // version checks and the declared lint order all run where the
        // member plugin values exist.
        metaprogram_options.plugin_registration = plugin_registration;
        metaprogram_options.package_root        = root_dir;
        metaprogram_options.plugin_configs      = plugin_configs_from_declarations(prepared.discovery.root_package.plugins, prepared.discovery.member_packages);
    }
    if !write_entire_file(runner_path, generate_test_metaprogram(metaprogram_options)) {
        print("[juice ERROR] Could not write test runner.\n");
        return false;
    }

    result := spawn(runner_path, import_dirs);
    if result.exit_code != 0 {
        print("[juice ERROR] Test compilation failed.\n");
        return false;
    }
    return true;
}
