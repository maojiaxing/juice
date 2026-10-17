// ---------------------------------------------------------------------------
// Metaprogram generator tests (moved here from src/metaprogram.jai: the 3
// existing blocks + 1 new block; living in tests/ per the 2026-10-14 test
// organization rule).
//
// Key constraint (same as transpile_tests.jai): src/metaprogram.jai is
// bootstrap build.jai's #load target — test blocks would be illegal inside a
// metaprogram compile-time text inclusion, so that file must stay test-free.
// The test blocks therefore cannot be inlined and live in tests/ (this
// file): referenced by no #load (outside the entry closure, outside the
// release product), collected into the test program by Test discovery's
// full-package scan. This file contains only test blocks; zero production
// code coupling.
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// Byte shapes of the generated text: the executable shape is byte-locked
// (no golden covers it); the test shape's full byte lock is carried by the
// golden fixtures — here only the key lines and the sentinel switch's
// zero-change semantics are locked.
// ---------------------------------------------------------------------------

test "Metaprogram generator: executable shape is byte-locked" {
    options: Compiler_Metaprogram_Options;
    options.workspace_name    = "Juice Build";
    options.executable_name   = "alpha";
    options.output_path       = "X:/root/target";
    options.intermediate_path = "X:/root/target";
    options.import_dirs       = string.["X:/root/target/packages"];
    options.build_file        = "X:/entry/main.jai";
    expected := "#import \"Basic\";\n#import \"Compiler\";\n\n#run {\n    set_build_options_dc(.{do_output = false});\n    workspace := compiler_create_workspace(\"Juice Build\");\n    if !workspace return;\n    options := get_build_options(workspace);\n    options.output_executable_name = \"alpha\";\n    options.output_path            = \"X:/root/target\";\n    options.intermediate_path      = \"X:/root/target\";\n    import_paths: [..] string;\n    array_add(*import_paths, .. options.import_path);\n    array_add(*import_paths, \"X:/root/target/packages\");\n    options.import_path = import_paths;\n    set_build_options(options, workspace);\n    compiler_begin_intercept(workspace);\n    add_build_file(\"X:/entry/main.jai\", workspace);\n    while true {\n        msg := compiler_wait_for_message();\n        if !msg continue;\n        if msg.workspace == workspace {\n            if msg.kind == {\n                case .ERROR;\n                case .COMPLETE;\n                    break;\n            }\n        }\n    }\n    compiler_end_intercept(workspace);\n}\n";
    expect(generate_compiler_metaprogram(options) == expected);
}

test "Metaprogram generator: test shape emits NO_OUTPUT with plain lines" {
    options: Compiler_Metaprogram_Options;
    options.workspace_name    = "Juice Test Program";
    options.no_output         = true;
    options.intermediate_path = "X:/root/target";
    options.import_dirs       = string.["X:/modules"];
    options.build_file        = "X:/target/transpile/driver.jai";
    text := generate_compiler_metaprogram(options);
    expect(find_index_from_left(text, "options.output_type = .NO_OUTPUT;") >= 0);
    expect(find_index_from_left(text, "options.output_executable_name") < 0);
    expect(find_index_from_left(text, "options.intermediate_path = \"X:/root/target\";") >= 0);
    expect(find_index_from_left(text, "array_add(*import_paths, \"X:/modules\");") >= 0);
    expect(find_index_from_left(text, "add_build_file(\"X:/target/transpile/driver.jai\", workspace);") >= 0);
    expect(find_index_from_left(text, "compiler_create_workspace(\"Juice Test Program\");") >= 0);
}

// The sentinel convention: "" means the Testing module compile view special
// case is disabled — enabling it only prepends one import_paths line, the
// rest of the text changes by zero bytes.
test "Metaprogram generator: sentinel on prepends one view-dir line" {
    base: Compiler_Metaprogram_Options;
    base.workspace_name    = "Juice Test Program";
    base.no_output         = true;
    base.intermediate_path = "X:/root/target";
    base.import_dirs       = string.["X:/modules"];
    base.build_file        = "X:/target/transpile/driver.jai";
    off_text := generate_compiler_metaprogram(base);

    on := base;
    on.testing_view_dir = "X:/root/target/testing-module";
    on_text := generate_compiler_metaprogram(on);
    expect(find_index_from_left(on_text, "array_add(*import_paths, \"X:/root/target/testing-module\");\n    array_add(*import_paths, \"X:/modules\");") >= 0);
    expect(on_text == tprint("%1    array_add(*import_paths, \"X:/root/target/testing-module\");\n%2",
        slice(off_text, 0, find_index_from_left(off_text, "    array_add(*import_paths, \"X:/modules\");")),
        slice(off_text, find_index_from_left(off_text, "    array_add(*import_paths, \"X:/modules\");"),
            off_text.count - find_index_from_left(off_text, "    array_add(*import_paths, \"X:/modules\");"))));
}

// ---------------------------------------------------------------------------
// The very_optimized emission shape — the default emits nothing (existing
// consumers stay byte-identical), true emits exactly one line, positioned
// after the import_path assignment and before set_build_options.
// ---------------------------------------------------------------------------

test "Metaprogram generator: very_optimized emits one line, default emits none" {
    base: Compiler_Metaprogram_Options;
    base.workspace_name    = "Juice Build";
    base.executable_name   = "alpha";
    base.output_path       = "X:/root/target";
    base.intermediate_path = "X:/root/target";
    base.import_dirs       = string.[];
    base.build_file        = "X:/entry/main.jai";
    off_text := generate_compiler_metaprogram(base);
    expect(find_index_from_left(off_text, "set_optimization") < 0);

    on := base;
    on.very_optimized = true;
    on_text := generate_compiler_metaprogram(on);
    expect(find_index_from_left(on_text, "    set_optimization(*options, .VERY_OPTIMIZED);\n") >= 0);
    expect(find_index_from_left(on_text, "    options.import_path = import_paths;\n    set_optimization(*options, .VERY_OPTIMIZED);\n    set_build_options(options, workspace);\n") >= 0);
    expect(on_text == tprint("%1    set_optimization(*options, .VERY_OPTIMIZED);\n%2",
        slice(off_text, 0, find_index_from_left(off_text, "    set_build_options(options, workspace);")),
        slice(off_text, find_index_from_left(off_text, "    set_build_options(options, workspace);"),
            off_text.count - find_index_from_left(off_text, "    set_build_options(options, workspace);"))));
}
