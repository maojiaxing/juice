#import "Basic";
#import "String";

// The in-process compiler metaprogram generator: produces the one-shot
// workspace/intercept/message-loop source text skeleton that drives the jai
// compiler (the old juice src/metaprogram.jai executable shape). The Build
// command assembles the options and writes the generated text as a session
// product (<target_dir>/build-<name>.jai); the child jai compiles the chosen
// entry through it.
//
// This file must stay test-free: stage 2's bootstrap build.jai metaprogram
// #loads it (the old juice bootstrap discipline — its tests live in
// tests/build_tests.jai, following the test organization rule). Faces that
// did not exist yet at ticket 011 landed at their handover points: the
// test shape (no_output) with the test command (ticket 017); the Testing
// module compile view special case (testing_view_dir) with ticket 027's
// build wiring; very_optimized and the bootstrap options assembly
// (bootstrap_compiler_metaprogram_options — build.jai's #run is the call
// site) with ticket 031's bootstrap metaprogram (the stage-2 release path);
// the compile-time version assertion driver
// (generate_version_assertion_driver — the ticket 032 publish-wiring call
// site) with ticket 032's publication wiring.
//
// Every path the generated text quotes must be absolute and "/"-separated:
// the child jai switches its #run working directory to the metaprogram's own
// directory (target/build/ for the build drivers, target/transpile for the
// test runner), so relative paths would resolve one layer deeper (the old
// juice 058 deviation ④ discipline).
//
// The program-level quote/escape pair lives in src/transpile.jai (ticket
// 022's canonical face, the old juice home). Ticket 027 retired this
// module's prefixed local copies (the ticket 011 stand-in) and wired the
// build closure to #load transpile.jai before this file — every caller now
// uses the canonical pair. Ticket 031 switched the path separator
// normalization from path_safety's path_slashes to transpile_front's
// front_slashes (identical semantics, the self-contained implementation):
// the bootstrap #load closure does not include path_safety.jai, so every
// cross-file reference here must resolve inside the closure (transpile →
// transpile_plugin → transpile_cache → transpile_front → metaprogram, the
// pinned #load order — build.jai's header is the contract).

// The generated test runner's entry file name (the test program's compile
// entry): one source shared by the test command's producer
// (src/commands/test.jai) and build.jai's test-program guard. Both sides
// #load this module (the bootstrap closure and main.jai both include it), so
// a rename touches one constant. The name is a cross-file contract, not a
// Jai convention: jai treats the entry by command-line position, not name.
TEST_RUNNER_FILE_NAME :: "test_runner.jai";

// One generated compiler metaprogram: the workspace name, the output shape
// (executable vs no-output), the executable output (name/path), the
// intermediate directory (jai has no command-line flag for
// Build_Options.intermediate_path, so the metaprogram sets it to the target
// directory — compiler intermediates land there instead of a .build
// directory next to the entry, and Clean removes them with target/), the
// extra import directories (in emission order), and the single build file
// added after the intercept begins.
//
// Byte-identity invariant (the old juice discipline): both output shapes are
// byte-locked — the executable shape (no_output = false: the aligned
// output_executable_name/output_path/intermediate_path three lines, no
// output_type line) by the inline test in tests/build_tests.jai; the test
// shape (no_output = true: the output_type = .NO_OUTPUT line plus an
// unaligned intermediate_path line, no executable name/path lines) by the
// ticket 017 test next to it.
Compiler_Metaprogram_Options :: struct {
    workspace_name:    string;
    no_output:         bool = false;
    executable_name:   string = "";
    output_path:       string = "";
    intermediate_path: string;
    // Windows PDB output path (C5): link.exe writes the PDB next to the
    // output artifact by default; a non-empty value adds
    // /PDB:<path> to the linker arguments so the PDB lands under
    // target/build/ with the other intermediates. The exe embeds this
    // absolute path, so the moved PDB stays findable. "" = the linker
    // default (byte-identical generated text). Ignored by the no-output
    // shape and on POSIX.
    pdb_path:          string = "";
    import_dirs:       [] string;
    build_file:        string;
    // Testing module compile view special case (ticket 027, the "" sentinel
    // convention = disabled — the same convention as
    // testing_module_strip_view_dir's return value): the view directory is
    // prepended to the import paths so `#import "Testing"` resolves to the
    // test-free view instead of the module source file.
    testing_view_dir:  string = "";
    // Bootstrap's release verification path (ticket 031, stage 2): when
    // true, emits set_optimization(.VERY_OPTIMIZED) before set_build_options
    // — false by default emits nothing, so existing consumers' output stays
    // byte-identical (the byte-locks in tests/build_tests.jai).
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
        // Test program shape: no artifact, plain (unaligned) option lines
        // (the old juice test shape).
        print_to_builder(*builder, "    options.output_type = .NO_OUTPUT;\n");
        print_to_builder(*builder, "    options.intermediate_path = %1;\n", quote_jai_string(front_slashes(options.intermediate_path)));
    } else {
        // Executable shape: the aligned option lines, byte-locked by the
        // inline test in tests/build_tests.jai (the old juice build output
        // exactly).
        print_to_builder(*builder, "    options.output_executable_name = %1;\n", quote_jai_string(options.executable_name));
        print_to_builder(*builder, "    options.output_path            = %1;\n", quote_jai_string(front_slashes(options.output_path)));
        print_to_builder(*builder, "    options.intermediate_path      = %1;\n", quote_jai_string(front_slashes(options.intermediate_path)));
        #if OS == .WINDOWS {
            if options.pdb_path != "" {
                // Redirect the linker's default PDB location (next to the
                // output exe) into the intermediate directory. The absolute
                // path is embedded in the exe's debug directory, so the
                // debugger still finds the moved file.
                print_to_builder(*builder, "    options.additional_linker_arguments = string.[%1];\n",
                                 quote_jai_string(tprint("/PDB:%1", front_slashes(options.pdb_path))));
            }
        }
    }
    print_to_builder(*builder, "    import_paths: [..] string;\n");
    print_to_builder(*builder, "    array_add(*import_paths, .. options.import_path);\n");
    if options.testing_view_dir != "" {
        // Testing module compile view special case: the view directory is
        // prepended so `#import "Testing"` resolves to the test-free view
        // instead of the module source file.
        print_to_builder(*builder, "    array_add(*import_paths, %1);\n", quote_jai_string(options.testing_view_dir));
    }
    for dir: options.import_dirs {
        print_to_builder(*builder, "    array_add(*import_paths, %1);\n", quote_jai_string(front_slashes(dir)));
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
// is_release), output the ready Compiler_Metaprogram_Options; build.jai's
// #run is the assembly call site. output_path and intermediate_path derive
// from the root as absolute paths ("<root>/target" and "<root>/target/build"):
// the generated metaprogram's child jai switches its #run working directory
// to the metaprogram's own directory (target/build/), so a relative "target"
// would resolve one layer deeper — target/build/target/ (the 058 deviation ④
// discipline; the fix mirrors the Build command's absolute plan.target_dir).
// front_slashes keeps the contract shape regardless of the caller's path
// separator style.
//
// The module import directory is <root>/target/modules (not the old juice
// shape's <root>/modules — otter has no in-repo modules/ directory; the
// bootstrap window's seed home is target/modules, and ticket 032's publish
// step lands the real module face at the same path). The directory is added
// unconditionally: a missing directory only costs jai's harmless import-dir
// probing hint, while a missing Juice seed surfaces loudly in the child as
// an unresolved import.
bootstrap_compiler_metaprogram_options :: (root: string, entry: string, testing_view_dir: string, is_release: bool) -> Compiler_Metaprogram_Options {
    r := front_slashes(root);
    target_dir := package_target_dir(r);

    options: Compiler_Metaprogram_Options;
    options.workspace_name    = "Juice Build";
    executable_name           := "juice";
    options.executable_name   = executable_name;
    options.output_path       = target_dir;
    // C5: the compiler intermediates (.obj/.lib/.exp/.pdb/.added_strings)
    // land in target/build, next to the generated build drivers; the
    // artifact stays at target/<name>.exe (modules_dir derives from the exe
    // directory). The PDB needs the explicit linker redirect: link.exe
    // otherwise writes it next to the artifact.
    options.intermediate_path = target_build_dir(target_dir);
    options.pdb_path          = tprint("%1/%2.pdb", target_build_dir(target_dir), executable_name);
    import_dirs: [..] string;
    array_add(*import_dirs, tprint("%1/src", r));
    array_add(*import_dirs, target_modules_dir(target_dir));
    array_add(*import_dirs, r);
    options.import_dirs       = import_dirs;
    options.build_file        = entry;
    options.testing_view_dir  = testing_view_dir;
    options.very_optimized    = is_release;
    return options;
}

// The compile-time version assertion driver (ticket 032, 005 decision 9): a
// generated evaluator program in the manifest evaluator's shape (ticket
// 007's driver discipline — #load the manifest, #run main(), do_output
// false). The driver #loads the package manifest and asserts
// PACKAGE.version == JUICE_VERSION — the constant declaration line
// extracted verbatim from src/commands/version.jai (the single source, the
// published juice_core discipline). The comparison is a compile-time
// #assert: a drift fails the child's compile with the message below (jai
// prints it with file:line and exits nonzero; build.jai propagates that as
// exit 1). A runtime print would be swallowed — the pinned Jai fact: prints
// emitted inside a #run compile flush only on normal exit, and the failure
// path's exit(1) would take the message with it. The `#import "Juice"`
// resolves through the caller's -import_dir (the published modules
// directory — the same face the manifest evaluator children use).
generate_version_assertion_driver :: (package_path: string, juice_version_line: string) -> string {
    builder: String_Builder;
    print_to_builder(*builder, "#import \"Basic\";\n");
    print_to_builder(*builder, "#import \"Compiler\";\n");
    print_to_builder(*builder, "#import \"Juice\";\n\n");
    print_to_builder(*builder, "#load %1;\n\n", quote_jai_string(front_slashes(package_path)));
    print_to_builder(*builder, "%1\n\n", juice_version_line);
    print_to_builder(*builder, "// Compile-time version assertion (ticket 032): a runtime print would be\n");
    print_to_builder(*builder, "// swallowed by the failure path's exit (prints from a #run compile flush\n");
    print_to_builder(*builder, "// only on normal exit); the compile error is the loud failure surface.\n");
    print_to_builder(*builder, "#assert PACKAGE.version == JUICE_VERSION \"package.jai VERSION must equal JUICE_VERSION (src/commands/version.jai) — versions drifted; update one.\";\n\n");
    print_to_builder(*builder, "#run {\n");
    print_to_builder(*builder, "    set_build_options_dc(.{do_output = false});\n");
    print_to_builder(*builder, "    main();\n");
    print_to_builder(*builder, "}\n\n");
    print_to_builder(*builder, "main :: () {\n");
    print_to_builder(*builder, "    print(\"[Version Assert] ✅ package.jai VERSION \% == JUICE_VERSION.\\n\", PACKAGE.version);\n");
    print_to_builder(*builder, "}\n");
    return builder_to_string(*builder);
}
