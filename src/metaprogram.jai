// 进程内编译 metaprogram 生成器（票 0036，CONTEXT：Metaprogram
// generator）：Build 与 Test 共用，生成驱动 jai 编译器的一次性
// workspace/拦截/消息循环源文本骨架。历史上有两份生成器
// （generate_build_metaprogram / generate_test_metaprogram）加一份
// bootstrap 手写版（build.jai，ADR 0006 对称复制），骨架与 "" 哨兵约定
// 靠注释互相承诺；收口后骨架与哨兵在本文单点成立。
//
// 字节一致不变量：两种输出形状与收口前逐字节一致——
//   可执行形状（no_output = false）：output_executable_name/output_path/
//   intermediate_path 三行（含列对齐空格），不输出 output_type 行；
//   测试形状（no_output = true）：output_type = .NO_OUTPUT 行加不齐头的
//   intermediate_path 行，不输出 executable name/path 行。
// Test 形状由 tests/data/transpile/golden/*/first.jai 逐字节锁定；本文件
// 的内联测试锁定可执行形状。
//
// 哨兵约定（票 0033 特例）：testing_view_dir == "" 表示「未启用 Testing
// 模块编译视图特例」——与 Build 的 testing_module_strip_view_dir 返回值、
// Test 的 testing_module_view、bootstrap build.jai 的 testing_view_dir
// 同一约定（生成输出与特例前逐字节一致）。

#import "Basic";
#import "String";
#import "Testing";

// One generated compiler metaprogram: the workspace name, the output shape
// (executable vs no-output), the intermediate directory, the extra import
// directories (in emission order), and the single build file added after the
// intercept begins. All paths must be "/" separated (the generator slashes
// the ones it quotes anyway). testing_view_dir follows the "" sentinel
// convention above.
Compiler_Metaprogram_Options :: struct {
    workspace_name:    string;
    no_output:         bool = false;
    executable_name:   string = "";
    output_path:       string = "";
    intermediate_path: string;
    import_dirs:       [] string;
    build_file:        string;
    testing_view_dir:  string = "";
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
        print_to_builder(*builder, "    options.intermediate_path = %1;\n", quote_jai_string(to_forward_slashes(options.intermediate_path)));
    } else {
        // Executable shape: aligned option lines, byte-locked by the inline
        // test below (this is the pre-consolidation build output exactly).
        print_to_builder(*builder, "    options.output_executable_name = %1;\n", quote_jai_string(options.executable_name));
        print_to_builder(*builder, "    options.output_path            = %1;\n", quote_jai_string(to_forward_slashes(options.output_path)));
        print_to_builder(*builder, "    options.intermediate_path      = %1;\n", quote_jai_string(to_forward_slashes(options.intermediate_path)));
    }
    print_to_builder(*builder, "    import_paths: [..] string;\n");
    print_to_builder(*builder, "    array_add(*import_paths, .. options.import_path);\n");
    if options.testing_view_dir != "" {
        // Testing module compile view special case (ticket 0033): the view
        // directory is prepended so `#import "Testing"` resolves to the
        // test-free view instead of the module source file.
        print_to_builder(*builder, "    array_add(*import_paths, %1);\n", quote_jai_string(options.testing_view_dir));
    }
    for dir: options.import_dirs {
        print_to_builder(*builder, "    array_add(*import_paths, %1);\n", quote_jai_string(dir));
    }
    print_to_builder(*builder, "    options.import_path = import_paths;\n");
    print_to_builder(*builder, "    set_build_options(options, workspace);\n");
    print_to_builder(*builder, "    compiler_begin_intercept(workspace);\n");
    print_to_builder(*builder, "    add_build_file(%1, workspace);\n", quote_jai_string(to_forward_slashes(options.build_file)));
    // The message loop only consumes messages — jai exits non-zero on its
    // own when the intercepted workspace has errors, and calling exit() from
    // a metaprogram would kill the process before jai flushes the collected
    // print output (ticket 0015 finding).
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

// ---------------------------------------------------------------------------
// 内联测试（票 0036）：生成文本的字节形状。可执行形状逐字节锁定（无
// golden 覆盖）；测试形状的完整字节锁定由 golden 夹具承担，这里只锁
// 关键行与哨兵开/关的零变化语义。
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

// 哨兵约定："" 表示未启用 Testing 模块编译视图特例——启用时只多一行
// import_paths 前置行，其余文本零变化。
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
