// The in-process compiler metaprogram generator (CONTEXT: Metaprogram
// generator): shared by Build, Test and bootstrap, it produces the one-shot
// workspace/intercept/message-loop source text skeleton that drives the jai
// compiler. Historically there were two generators
// (generate_build_metaprogram / generate_test_metaprogram) plus a hand-
// written bootstrap copy (build.jai, the ADR 0006 symmetric duplicate),
// with the skeleton and the "" sentinel convention promised to each other
// only through comments; after the consolidation the skeleton and sentinel
// hold in this single file. Bootstrap became the third consumer when it
// switched to "generate + child process" — this file must stay test-free
// (its tests live in tests/metaprogram_tests.jai, following the
// tests/transpile_tests.jai precedent and the test organization rule).
//
// Bootstrap's options assembly also lives here as the pure function
// bootstrap_compiler_metaprogram_options (build.jai's #run is the call
// site): output_path and intermediate_path derive from the root as absolute
// paths — the generated metaprogram's child jai switches its #run working
// directory to the metaprogram's own directory (target/), so a relative
// "target" would resolve one layer deeper into target/target/ (058
// deviation ④, fixed here).
//
// Byte-identity invariant: both output shapes are byte-identical to their
// pre-consolidation forms —
//   executable shape (no_output = false): the output_executable_name/
//   output_path/intermediate_path three lines (with column-aligned spaces),
//   no output_type line;
//   test shape (no_output = true): the output_type = .NO_OUTPUT line plus an
//   unaligned intermediate_path line, no executable name/path lines.
// The Test shape is byte-locked by tests/data/transpile/golden/*/first.jai;
// the executable shape is locked by the inline tests in
// tests/metaprogram_tests.jai.
//
// Sentinel convention: testing_view_dir == "" means "the Testing module
// compile view special case is disabled" — the same convention as the shared
// testing_module_strip_view_dir's return value, Test's testing_module_view
// and bootstrap build.jai's testing_view_dir (generated output stays
// byte-identical to the pre-special-case shape).

#import "Basic";
#import "String";

// One generated compiler metaprogram: the workspace name, the output shape
// (executable vs no-output), the intermediate directory, the extra import
// directories (in emission order), and the single build file added after the
// intercept begins. All paths must be "/" separated (the generator slashes
// the ones it quotes anyway). testing_view_dir follows the "" sentinel
// convention above. very_optimized: when true, emits
// set_optimization(.VERY_OPTIMIZED) before set_build_options — false by
// default emits nothing, so existing consumers' output stays byte-identical
// (bootstrap's release verification path relies on it).
Compiler_Metaprogram_Options :: struct {
    workspace_name:    string;
    no_output:         bool = false;
    executable_name:   string = "";
    output_path:       string = "";
    intermediate_path: string;
    import_dirs:       [] string;
    build_file:        string;
    testing_view_dir:  string = "";
    very_optimized:    bool = false;
}

generate_compiler_metaprogram :: (options: Compiler_Metaprogram_Options) -> string {
    builder: String_Builder;
    print_to_builder(*builder, "#import \"Basic\";\n");
    print_to_builder(*builder, "#import \"Compiler\";\n\n");
    print_to_builder(*builder, "#run {\n");
    print_to_builder(*builder, "    set_build_options_dc(.{do_output = false});\n");
    print_to_builder(*builder, "    workspace := compiler_create_workspace(%1);\n", quote_jai_string(options.workspace_name));
    print_to_builder(*builder, "    if !workspace return;\n");
    print_to_builder(*builder, "    options := get_build_options(workspace);\n");
    if options.no_output {
        // Test program shape: no artifact, plain (unaligned) option lines.
        print_to_builder(*builder, "    options.output_type = .NO_OUTPUT;\n");
        print_to_builder(*builder, "    options.intermediate_path = %1;\n", quote_jai_string(front_slashes(options.intermediate_path)));
    } else {
        // Executable shape: aligned option lines, byte-locked by the inline
        // test in tests/metaprogram_tests.jai (this is the pre-consolidation
        // build output exactly).
        print_to_builder(*builder, "    options.output_executable_name = %1;\n", quote_jai_string(options.executable_name));
        print_to_builder(*builder, "    options.output_path            = %1;\n", quote_jai_string(front_slashes(options.output_path)));
        print_to_builder(*builder, "    options.intermediate_path      = %1;\n", quote_jai_string(front_slashes(options.intermediate_path)));
    }
    print_to_builder(*builder, "    import_paths: [..] string;\n");
    print_to_builder(*builder, "    array_add(*import_paths, .. options.import_path);\n");
    if options.testing_view_dir != "" {
        // Testing module compile view special case: the view
        // directory is prepended so `#import "Testing"` resolves to the
        // test-free view instead of the module source file.
        print_to_builder(*builder, "    array_add(*import_paths, %1);\n", quote_jai_string(options.testing_view_dir));
    }
    for dir: options.import_dirs {
        print_to_builder(*builder, "    array_add(*import_paths, %1);\n", quote_jai_string(dir));
    }
    print_to_builder(*builder, "    options.import_path = import_paths;\n");
    if options.very_optimized {
        // Bootstrap's release verification path — emitted only when
        // non-default, so existing consumers' output stays byte-identical.
        print_to_builder(*builder, "    set_optimization(*options, .VERY_OPTIMIZED);\n");
    }
    print_to_builder(*builder, "    set_build_options(options, workspace);\n");
    print_to_builder(*builder, "    compiler_begin_intercept(workspace);\n");
    print_to_builder(*builder, "    add_build_file(%1, workspace);\n", quote_jai_string(front_slashes(options.build_file)));
    // The message loop only consumes messages — jai exits non-zero on its
    // own when the intercepted workspace has errors, and calling exit() from
    // a metaprogram would kill the process before jai flushes the collected
    // print output.
    print_to_builder(*builder, "    while true {\n");
    print_to_builder(*builder, "        msg := compiler_wait_for_message();\n");
    print_to_builder(*builder, "        if !msg continue;\n");
    print_to_builder(*builder, "        if msg.workspace == workspace {\n");
    print_to_builder(*builder, "            if msg.kind == {\n");
    print_to_builder(*builder, "                case .ERROR;\n");
    print_to_builder(*builder, "                case .COMPLETE;\n");
    print_to_builder(*builder, "                    break;\n");
    print_to_builder(*builder, "            }\n");
    print_to_builder(*builder, "        }\n");
    print_to_builder(*builder, "    }\n");
    print_to_builder(*builder, "    compiler_end_intercept(workspace);\n");
    print_to_builder(*builder, "}\n");
    return builder_to_string(*builder);
}

// The bootstrap options assembly (the mirror of the Build command's inline
// options assembly): a pure function — input (root, entry, testing_view_dir,
// is_release), output the ready Compiler_Metaprogram_Options; bootstrap
// build.jai's #run is the assembly call site. output_path and
// intermediate_path derive from the root as absolute paths ("<root>/target"):
// the generated metaprogram's child jai switches its #run working directory
// to the metaprogram's own directory (target/), so a relative "target" would
// resolve one layer deeper — target/target/ (058 deviation ④; the fix mirrors
// the Build command's absolute plan.target_dir). front_slashes keeps the
// contract shape regardless of the caller's path separator style.
bootstrap_compiler_metaprogram_options :: (root: string, entry: string, testing_view_dir: string, is_release: bool) -> Compiler_Metaprogram_Options {
    r := front_slashes(root);
    target_dir := tprint("%1/target", r);

    options: Compiler_Metaprogram_Options;
    options.workspace_name    = "Juice Build";
    options.executable_name   = "juice";
    options.output_path       = target_dir;
    options.intermediate_path = target_dir;
    import_dirs: [..] string;
    array_add(*import_dirs, tprint("%1/src", r));
    array_add(*import_dirs, tprint("%1/modules", r));
    array_add(*import_dirs, r);
    options.import_dirs       = import_dirs;
    options.build_file        = entry;
    options.testing_view_dir  = testing_view_dir;
    options.very_optimized    = is_release;
    return options;
}

// Byte-shape tests of the generated text (the executable shape is
// byte-locked, the test shape's key lines, the sentinel switch and the
// very_optimized emission) and the bootstrap options assembly's
// absolute-path contract live in tests/metaprogram_tests.jai — this file
// is bootstrap's #load target and must stay test-free (per the test
// organization rule).
