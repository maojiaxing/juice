// ---------------------------------------------------------------------------
// 剥离前端测试（票 0050 新建，2 块自 commands/build.jai 迁入；2026-10-14 测
// 试组织规则后驻 tests/——票 0053）。
//
// 关键约束（与 transpile_tests.jai 同）：src/transpile_front.jai 是 build.jai
// 的 #load 目标——test block 随 metaprogram 编译期文本包含会非法，该文件必
// 须保持 test-free。测试块因此不能内联，按测试组织规则驻 tests/ 本文件：不
// 被任何 #load 引用（不进入口闭包、不进发布产物），Test discovery 全包扫描
// 收录进测试程序。本文件仅含 test block；生产代码零耦合。
//
// 共享声明（juice_root、build_seam_write、fake_build_transpile 等 seam fake
// 与记录全局）见 tests/test_support.jai（组织决议 0027），测试程序程序级共享。
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// 生产 transpile 步骤（自 commands/build.jai 迁入，票 0050）
// ---------------------------------------------------------------------------

// The real per-file step strips fixture test blocks and derives the
// content-addressed key from the pure function.
test "Real build transpile step strips fixture tests" {
    target: Load_Target;
    target.from = "src/math.jai";
    target.to = "C:/virtual/target/transpile/hash0001/src/math.jai";
    output := transpile_build_file(.{rel_path = "src/main.jai", abs_path = tprint("%1/tests/data/test-package/src/main.jai", juice_root())}, Load_Target.[target]);
    expect(output.diagnostics.count == 0);
    expect(find_index_from_left(output.view, "// juice: test stripped: test \"greeting\" {") >= 0);
    expect(find_index_from_left(output.view, "juice_test_") < 0);
    expect(find_index_from_left(output.view, "C:/virtual/target/transpile/hash0001/src/math.jai") >= 0);
    source, ok := read_entire_file(tprint("%1/tests/data/test-package/src/main.jai", juice_root()));
    expect(ok);
    expect(output.key == transpile_view_key("src/main.jai", source, .STRIP, Load_Target.[target], JUICE_VERSION));
}

// Only literal in-package #load targets are rewritten: non-literal and
// out-of-package statements stay verbatim (issue 0008 resolution 4).
test "Build strip keeps unrewritable loads verbatim" {
    root := tprint("%1/target/build-strip-verbatim", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    source := "#load \"helper.jai\";\n#load CONST_NAME;\n#load \"../../outside.jai\";\n#load \"other\" + \".jai\";\n";
    expect(build_seam_write(root, "src/main.jai", source));
    target: Load_Target;
    target.from = "src/helper.jai";
    target.to = "X:/virtual/views/helper.jai";
    output := transpile_build_file(.{rel_path = "src/main.jai", abs_path = tprint("%1/src/main.jai", root)}, Load_Target.[target]);
    expect(output.diagnostics.count == 0);
    expect(find_index_from_left(output.view, "#load \"X:/virtual/views/helper.jai\";") >= 0);
    expect(find_index_from_left(output.view, "#load CONST_NAME;") >= 0);
    expect(find_index_from_left(output.view, "#load \"../../outside.jai\";") >= 0);
    expect(find_index_from_left(output.view, "#load \"other\" + \".jai\";") >= 0);
}

// ---------------------------------------------------------------------------
// PLAIN 布局（bootstrap 策略，票 0050）：<base>/<rel> 恒写、入口进内存
// ---------------------------------------------------------------------------

// 入口与其他文件同样落盘（票 0052：bootstrap 改走「生成 + 子进程」后，生
// 成的 metaprogram 以 add_build_file 编译入口视图——PLAIN 布局不再有「入
// 口进内存」分支，诊断精确文件+行号）。
test "Strip front: PLAIN layout writes the entry view to disk" {
    root := tprint("%1/target/front-plain-entry", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"helper.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/helper.jai", "helper :: () -> s32 { return 1; }\n\ntest \"helper test\" {\n}\n"));

    reset_build_seam();
    closure, ok := probe_package_closure(root, "src/main.jai");
    expect(ok && closure_has_tests(closure) && closure.count == 2);

    state: Strip_View_State;
    state.closure = closure;
    state.transpile = fake_build_transpile;
    state.transpile_dir = tprint("%1/target/transpile/bootstrap", root);
    state.layout = .PLAIN;
    for _: closure {
        array_add(*state.states, 0);
        array_add(*state.view_paths, "");
    }
    entry_index, found := closure_index(*state, "src/main.jai");
    expect(found);
    entry_path, ok2 := view_of_file(*state, entry_index);
    expect(ok2 && entry_path == tprint("%1/target/transpile/bootstrap/src/main.jai", root));
    // 入口与子视图都落盘（依赖序：helper 先于入口）。
    expect(file_exists(entry_path));
    expect(file_exists(tprint("%1/target/transpile/bootstrap/src/helper.jai", root)));
}

// PLAIN 布局无缓存语义：已存在的视图每次重写（与 CONTENT_ADDRESSED 的
// skip-existing 相反）。
test "Strip front: PLAIN layout always rewrites existing views" {
    root := tprint("%1/target/front-plain-rewrite", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"helper.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/helper.jai", "helper :: () -> s32 { return 1; }\n\ntest \"helper test\" {\n}\n"));

    // 陈旧视图占位：PLAIN 恒写语义下必须被重写（CONTENT_ADDRESSED 则跳过）。
    helper_view := tprint("%1/target/transpile/bootstrap/src/helper.jai", root);
    expect(build_seam_write(root, "target/transpile/bootstrap/src/helper.jai", "// stale\n"));

    reset_build_seam();
    closure, ok := probe_package_closure(root, "src/main.jai");
    expect(ok && closure.count == 2);

    state: Strip_View_State;
    state.closure = closure;
    state.transpile = fake_build_transpile;
    state.transpile_dir = tprint("%1/target/transpile/bootstrap", root);
    state.layout = .PLAIN;
    for _: closure {
        array_add(*state.states, 0);
        array_add(*state.view_paths, "");
    }
    entry_index, found := closure_index(*state, "src/main.jai");
    expect(found);
    _, ok2 := view_of_file(*state, entry_index);
    expect(ok2);
    helper_text, read_ok := read_entire_file(helper_view);
    expect(read_ok && helper_text == "// fake build view of src/helper.jai\n");
}

// ---------------------------------------------------------------------------
// 探测与全有全无判定（票 0050）
// ---------------------------------------------------------------------------

// 全有全无判定：任一文件含 test block 即整闭包视图化（issue 0008 决议
// 1/2）；全 test-free 闭包零转译。
test "Strip front: closure_has_tests detects any test block" {
    root := tprint("%1/target/front-has-tests", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/clean.jai", "x :: 1;\n"));
    expect(build_seam_write(root, "src/dirty.jai", "test \"t\" {\n}\n"));

    clean, ok1 := probe_package_closure(root, "src/clean.jai");
    expect(ok1 && !closure_has_tests(clean));
    dirty, ok2 := probe_package_closure(root, "src/dirty.jai");
    expect(ok2 && closure_has_tests(dirty));
}

// 入口文件不存在：探测失败（files 空、ok false），调用方跳过构建。
test "Strip front probe: a missing entry file fails the probe" {
    root := tprint("%1/target/front-probe-missing", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    closure, ok := probe_package_closure(root, "src/nope.jai");
    expect(!ok && closure.count == 0);
}

// ---------------------------------------------------------------------------
// Testing 模块 STRIP 特例（票 0051 收口：bootstrap 与 Build command 共用）
// ---------------------------------------------------------------------------

// 模块 test-free：零动作（返回 "" 哨兵、不创建视图目录）。
test "Strip front: Testing module view disabled for a test-free module" {
    root := tprint("%1/target/front-testing-clean", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "mods/Testing.jai", "expect :: (cond: bool) {}\n"));

    dir := testing_module_strip_view_dir(root, tprint("%1/mods/Testing.jai", root));
    expect(dir == "");
    expect(!file_exists(tprint("%1/target/testing-module", root)));
}

// 模块含 test block：STRIP 视图写 <root>/target/testing-module/Testing.jai
// （与 test 命令的编译视图同路径），返回值是其目录。
test "Strip front: Testing module STRIP view writes to the package target" {
    root := tprint("%1/target/front-testing-view", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "mods/Testing.jai", "expect :: (cond: bool) {}\n\ntest \"self\" {\n    expect(true);\n}\n"));

    dir := testing_module_strip_view_dir(root, tprint("%1/mods/Testing.jai", root));
    expect(dir == tprint("%1/target/testing-module", root));
    view, ok := read_entire_file(tprint("%1/Testing.jai", dir));
    expect(ok);
    source, read_ok := read_entire_file(tprint("%1/mods/Testing.jai", root));
    expect(read_ok);
    expected := transpile_source(source, .{mode = .STRIP, path = "modules/Testing.jai"});
    expect(view == expected.view);
}
