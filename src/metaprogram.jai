// 进程内编译 metaprogram 生成器（票 0036，CONTEXT：Metaprogram
// generator）：Build、Test 与 bootstrap（票 0052）共用，生成驱动 jai 编译
// 器的一次性 workspace/拦截/消息循环源文本骨架。历史上有两份生成器
// （generate_build_metaprogram / generate_test_metaprogram）加一份
// bootstrap 手写版（build.jai，ADR 0006 对称复制），骨架与 "" 哨兵约定
// 靠注释互相承诺；收口后骨架与哨兵在本文单点成立。票 0052：bootstrap 改
// 走「生成 + 子进程」后成为第三个消费方——本文件必须 test-free（其测试
// 驻 tests/metaprogram_tests.jai，先例 tests/transpile_tests.jai，票 0053）。
//
// 字节一致不变量：两种输出形状与收口前逐字节一致——
//   可执行形状（no_output = false）：output_executable_name/output_path/
//   intermediate_path 三行（含列对齐空格），不输出 output_type 行；
//   测试形状（no_output = true）：output_type = .NO_OUTPUT 行加不齐头的
//   intermediate_path 行，不输出 executable name/path 行。
// Test 形状由 tests/data/transpile/golden/*/first.jai 逐字节锁定；可执行
// 形状由 tests/metaprogram_tests.jai 的内联测试锁定。
//
// 哨兵约定（票 0033 特例）：testing_view_dir == "" 表示「未启用 Testing
// 模块编译视图特例」——与共享 testing_module_strip_view_dir 的返回值、
// Test 的 testing_module_view、bootstrap build.jai 的 testing_view_dir
// 同一约定（生成输出与特例前逐字节一致）。

#import "Basic";
#import "String";

// One generated compiler metaprogram: the workspace name, the output shape
// (executable vs no-output), the intermediate directory, the extra import
// directories (in emission order), and the single build file added after the
// intercept begins. All paths must be "/" separated (the generator slashes
// the ones it quotes anyway). testing_view_dir follows the "" sentinel
// convention above. very_optimized（票 0052）：true 时在 set_build_options
// 前发射 set_optimization(.VERY_OPTIMIZED)——默认 false 零发射，既有消费方
// 的输出逐字节不变（bootstrap 的 release 验证路径靠它保留）。
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
        // Testing module compile view special case (ticket 0033): the view
        // directory is prepended so `#import "Testing"` resolves to the
        // test-free view instead of the module source file.
        print_to_builder(*builder, "    array_add(*import_paths, %1);\n", quote_jai_string(options.testing_view_dir));
    }
    for dir: options.import_dirs {
        print_to_builder(*builder, "    array_add(*import_paths, %1);\n", quote_jai_string(dir));
    }
    print_to_builder(*builder, "    options.import_path = import_paths;\n");
    if options.very_optimized {
        // 票 0052：bootstrap 的 release 验证路径——仅在非默认时发射，既有
        // 消费方的输出逐字节不变。
        print_to_builder(*builder, "    set_optimization(*options, .VERY_OPTIMIZED);\n");
    }
    print_to_builder(*builder, "    set_build_options(options, workspace);\n");
    print_to_builder(*builder, "    compiler_begin_intercept(workspace);\n");
    print_to_builder(*builder, "    add_build_file(%1, workspace);\n", quote_jai_string(front_slashes(options.build_file)));
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

// 生成文本的字节形状测试（可执行形状逐字节锁定、测试形状关键行、哨兵
// 开关、very_optimized 发射）驻 tests/metaprogram_tests.jai——本文件是
// bootstrap 的 #load 目标，必须保持 test-free（票 0052；票 0053 测试组织
// 规则）。
