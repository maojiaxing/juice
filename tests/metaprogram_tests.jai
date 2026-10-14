// ---------------------------------------------------------------------------
// Metaprogram 生成器测试（票 0052 自 src/metaprogram.jai 迁入，3 块 + 新增
// 1 块；2026-10-14 测试组织规则后驻 tests/——票 0053）。
//
// 关键约束（与 transpile_tests.jai 同）：src/metaprogram.jai 自票 0052 起是
// bootstrap build.jai 的 #load 目标——test block 随 metaprogram 编译期文本
// 包含会非法，该文件必须保持 test-free。测试块因此不能内联，按测试组织规
// 则驻 tests/ 本文件：不被任何 #load 引用（不进入口闭包、不进发布产物），
// Test discovery 全包扫描收录进测试程序。本文件仅含 test block；生产代码零
// 耦合。
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// 生成文本的字节形状（票 0036）：可执行形状逐字节锁定（无 golden 覆盖）；
// 测试形状的完整字节锁定由 golden 夹具承担，这里只锁关键行与哨兵开关的
// 零变化语义。
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

// ---------------------------------------------------------------------------
// 票 0052 新增：very_optimized 的发射形状——默认零发射（既有消费方逐字节
// 不变），true 时恰多一行、位置在 import_path 设置之后、set_build_options
// 之前。
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
