// ===========================================================================
// monorepo（workspace member）E2E 测试（票 0042-0046）
//
// 2026-10-14 用户修订：monorepo 的 E2E 测试集中于此文件，不内联在
// command 文件（build/clean/test.jai）中。本文件被 Test discovery 全包
// 扫描收录，与 src 内联测试同一测试程序执行；child 场景 helper
// （run_juice_child、run_juice_test、expect_exit、output_matches、
// child_output_contains、shim_content_for、make_test_link）见
// tests/test_support.jai（程序级可见）。
//
// fixture 家族 tests/data/workspace-* 见票 0042。
// ===========================================================================

#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import "Testing";

// ---------------------------------------------------------------------------
// discovery 校验矩阵（票 0043）：每个失败分支一条 E2E，经真实 juice.exe
// 断言具体错误消息。直测不可行——manifest 求值器的模块目录从运行中可执行
// 文件推导，测试程序内指向 jai 编译器而非 juice（路径门槛的进程内直测见
// src/workspace.jai 的 "Workspace member path validity gate"）。
//
// 两个防御分支不入矩阵：`Workspace member directory does not exist`
// （normalize_existing_path 只做词法归一，不验证存在）与 `escapes package
// root`（路径有效性门槛已拒绝全部可达拼写：逃逸组件、绝对路径与卷标；
// junction/symlink 被更早的 safe-directory 检查拦截）。
// ---------------------------------------------------------------------------

test "E2E: discovery rejects an invalid root manifest" {
    result, output, _ := run_juice_child("workspace-bad-root-manifest", "build");
    expect(expect_exit("bad-root-manifest", result, 1, "build child"));
    expect(child_output_contains("bad-root-manifest", output, "[juice ERROR] Existing package.jai is invalid."));
}

test "E2E: discovery rejects a member path with escape components" {
    result, output, _ := run_juice_child("workspace-bad-escape", "build");
    expect(expect_exit("bad-escape", result, 1, "build child"));
    expect(child_output_contains("bad-escape", output, "[juice ERROR] Invalid workspace member path: ../outside"));
}

// 实测（票 0042 Resolution）：不存在的 member 目录命中 not-a-safe-real-
// directory 分支——normalize_existing_path 不验证存在，inspect 发现
// !exists 后走同一分支。
test "E2E: discovery rejects a member directory that does not exist" {
    result, output, _ := run_juice_child("workspace-bad-missing-dir", "build");
    expect(expect_exit("bad-missing-dir", result, 1, "build child"));
    expect(child_output_contains("bad-missing-dir", output, "[juice ERROR] Workspace member is not a safe real directory: ghost_member"));
}

test "E2E: discovery rejects a member without a manifest" {
    result, output, _ := run_juice_child("workspace-bad-no-manifest", "build");
    expect(expect_exit("bad-no-manifest", result, 1, "build child"));
    expect(child_output_contains("bad-no-manifest", output, "[juice ERROR] Workspace member lacks package.jai:"));
}

test "E2E: discovery rejects an invalid member manifest" {
    result, output, _ := run_juice_child("workspace-bad-invalid-manifest", "build");
    expect(expect_exit("bad-invalid-manifest", result, 1, "build child"));
    expect(child_output_contains("bad-invalid-manifest", output, "[juice ERROR] Workspace member manifest is invalid:"));
}

// member_lib/. 与 member_lib 文本不同、归一化后同目录（票 0042 实测拼写）。
test "E2E: discovery rejects duplicate member paths" {
    result, output, _ := run_juice_child("workspace-bad-duplicate", "build");
    expect(expect_exit("bad-duplicate", result, 1, "build child"));
    expect(child_output_contains("bad-duplicate", output, "[juice ERROR] Duplicate workspace member path: member_lib/."));
}

// 边界用例：root 把 "." 列为 member——归一化后与 root 相同，root 已先入
// 成员清单，命中 duplicate 分支（钉住当前行为）。
test "E2E: discovery rejects the root listed as its own member" {
    result, output, _ := run_juice_child("workspace-edge-self", "build");
    expect(expect_exit("edge-self", result, 1, "build child"));
    expect(child_output_contains("edge-self", output, "[juice ERROR] Duplicate workspace member path: ."));
}

// 边界用例：member 的 manifest 再声明 members——当前实现只迭代 root 的
// members 清单，嵌套声明静默忽略，discovery 与 build 成功（钉住当前行为，
// 与 CONTEXT.md「member 由 root package 声明」一致）。
test "E2E: a member declaring its own members is ignored" {
    fixture_root := tprint("%1/tests/data/workspace-edge-nested", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));

    result, output, _ := run_juice_child("workspace-edge-nested", "build");
    expect(expect_exit("edge-nested", result, 0, "build child"));
    expect(child_output_contains("edge-nested", output, "Build completed successfully!"));
    expect(file_exists(tprint("%1/target/edge_nested.exe", fixture_root)));
}

// junction 用例运行时制造（票 0043）：在 target/ scratch 复刻 workspace-ok
// 形状，member_lib 替换为指向真实目录的 junction → 命中 not-a-safe-real-
// directory 分支。make_test_link 失败（机器拒绝 mklink）时沿用 SKIP 惯例。
test "E2E: discovery rejects a junctioned member directory" {
    scratch := tprint("%1/target/workspace-junction", juice_root());
    delete_directory_full(scratch);
    defer delete_directory_full(scratch);

    expect(make_directory_if_it_does_not_exist(tprint("%1/member_target/src", scratch), recursive = true));
    expect(write_entire_file(tprint("%1/member_target/package.jai", scratch),
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"member_lib\",\n    version = \"0.1.0\",\n    type    = .LIB,\n};\n"));
    expect(write_entire_file(tprint("%1/member_target/src/module.jai", scratch), "#import \"Basic\";\n"));
    expect(make_directory_if_it_does_not_exist(tprint("%1/src", scratch), recursive = true));
    expect(write_entire_file(tprint("%1/package.jai", scratch),
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"junction_root\",\n    version = \"0.1.0\",\n    type    = .BIN,\n    workspace = .{\n        members = string.[\"member_lib\"],\n    },\n};\n"));
    expect(write_entire_file(tprint("%1/src/main.jai", scratch), "#import \"Basic\";\n\nmain :: () {\n    print(\"fixture main\\n\");\n}\n"));

    if !make_test_link(tprint("%1/member_lib", scratch), tprint("%1/member_target", scratch), directory = true, junction = true) {
        print("[junction] SKIP: this machine refuses mklink; junction rejection not exercised\n");
        return;
    }

    result, output, _, _ := run_command(juice_exe(), "build", working_directory = scratch, capture_and_return_output = true);
    expect(expect_exit("junction", result, 1, "build child"));
    expect(child_output_contains("junction", output, "[juice ERROR] Workspace member is not a safe real directory:"));
}

// ---------------------------------------------------------------------------
// monorepo build E2E（票 0044 / 0049）：root 依赖 member → link 非 fetch →
// shim 指向两种布局的导入入口 → 真实构建 → artifact 调用两 member 函数。
// member_lib 闭包含 test block（入口自身 + extra.jai）→ 依赖剥离前端视图化
// 并改写其 shim；root 入口闭包 test-free，无 root 自己的视图。
// ---------------------------------------------------------------------------

test "E2E: monorepo build links members and builds the root" {
    fixture_root := tprint("%1/tests/data/workspace-ok", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));

    result, output, _ := run_juice_child("workspace-ok", "build");
    expect(expect_exit("monorepo-build", result, 0, "build child"));
    expect(child_output_contains("monorepo-build", output, "Compiling Target 'ws_root' (src/main.jai) -> target/..."));

    // link 非 fetch：member_extra（test-free）shim 指向导入入口原文；
    // member_lib 的 shim 被依赖剥离前端改写指向入口剥离视图。
    packages_dir := tprint("%1/target/packages", fixture_root);
    lib_content, lib_ok := shim_content_for(packages_dir, "member_lib");
    expect(lib_ok);
    expect(find_index_from_left(lib_content, "#load ") >= 0);
    expect(find_index_from_left(lib_content, "target/transpile/deps/member_lib/") >= 0);
    expect(find_index_from_left(lib_content, "module.jai\";") >= 0);
    extra_content, extra_ok := shim_content_for(packages_dir, "member_extra");
    expect(extra_ok);
    expect(find_index_from_left(extra_content, "#load ") >= 0 && find_index_from_left(extra_content, "member_extra/module.jai") >= 0);

    // artifact 运行：两 member 函数被实际调用（剥离不改产物语义）。
    artifact := tprint("%1/target/ws_root.exe", fixture_root);
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("monorepo-artifact", run_result, 0, "build child"));
    expect(child_output_contains("monorepo-artifact", run_output, "ws_root: hello from member_lib | hello from member_extra"));

    // 依赖剥离视图落 target/transpile/deps/member_lib/...，test block 被
    // 剥离（纯函数契约路径逐字节可重建）；root 入口闭包 test-free——
    // transpile 树存在但只有 deps 子树。rel 以 member 包根（src/ 目录，
    // 入口所在处）为基准。
    extra_source, read_ok := read_entire_file(tprint("%1/member_lib/src/extra.jai", fixture_root));
    expect(read_ok);
    extra_key := transpile_view_key("extra.jai", extra_source, .STRIP, Load_Target.[], JUICE_VERSION);
    extra_view := tprint("%1/target/transpile/deps/member_lib/%2/extra.jai", fixture_root, extra_key);
    expect(path_exists_as_regular_file(extra_view));
    extra_view_text, view_ok := read_entire_file(extra_view);
    expect(view_ok && find_index_from_left(extra_view_text, "// juice: test stripped") >= 0);
}

// ---------------------------------------------------------------------------
// monorepo clean E2E（票 0045）：target 垃圾运行时制造（fixture 不提交
// target/），root 与 member 的 target 整目录删除、源文件保留、无 target
// 的 member 不失败（delete_directory_full 对不存在路径返回 true，见
// src/dependency.jai）。
// ---------------------------------------------------------------------------

test "E2E: clean removes root and member target directories" {
    fixture_root := tprint("%1/tests/data/workspace-ok", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));
    defer delete_directory_full(tprint("%1/member_lib/target", fixture_root));

    // 运行时制造垃圾：root 与 member_lib 各一个真实 target/；member_extra 不建。
    expect(make_directory_if_it_does_not_exist(tprint("%1/target", fixture_root), recursive = true));
    expect(write_entire_file(tprint("%1/target/junk.exe", fixture_root), "junk"));
    expect(make_directory_if_it_does_not_exist(tprint("%1/member_lib/target", fixture_root), recursive = true));
    expect(write_entire_file(tprint("%1/member_lib/target/junk.lib", fixture_root), "junk"));

    result, output, _ := run_juice_child("workspace-ok", "clean");
    expect(expect_exit("monorepo-clean", result, 0, "clean child"));
    expect(child_output_contains("monorepo-clean", output, "[juice Clean] Workspace cleaned."));

    // 整目录消失（含垃圾）。
    expect(!file_exists(tprint("%1/target", fixture_root)));
    expect(!file_exists(tprint("%1/member_lib/target", fixture_root)));

    // 非 target 内容原样保留（clean 不越界）。
    expect(file_exists(tprint("%1/package.jai", fixture_root)));
    expect(file_exists(tprint("%1/src/main.jai", fixture_root)));
    expect(file_exists(tprint("%1/member_lib/package.jai", fixture_root)));
    expect(file_exists(tprint("%1/member_lib/src/module.jai", fixture_root)));
    expect(file_exists(tprint("%1/member_extra/package.jai", fixture_root)));
    expect(file_exists(tprint("%1/member_extra/module.jai", fixture_root)));
}

// ---------------------------------------------------------------------------
// monorepo test E2E（票 0046 / 0049）：root 的测试程序 #import lib member——
// discovery → 依赖准备（shim）→ 视图编译 → 编译期执行全链路。member 自带
// 的测试（tests/ 与 src 内联）不随 root 运行（member 边界重申）；src 内联
// test block 经依赖剥离前端以 STRIP 视图编译（票 0049）。此场景暴露过缺陷
// 票 0048（test 编译缺 target/packages import 路径，已修复）。
// ---------------------------------------------------------------------------

test "E2E: monorepo root tests import a member library" {
    fixture_root := tprint("%1/tests/data/workspace-ok", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));
    defer delete_directory_full(tprint("%1/member_lib/target", fixture_root));

    result, output, _ := run_juice_test("workspace-ok");
    expect(expect_exit("monorepo-test", result, 0));
    expect(output_matches("monorepo-test", output, string.["[juice Test] Found 1 tests; compiling test program..."]));
    expect(output_matches("monorepo-test", output, string.["[test] root test imports the member\n1 passed, 0 failed\n"]));
    expect(output_matches("monorepo-test", output, string.["member test must not run in root", "member inline test", "member extra inline test"], want = false));
    // 依赖剥离在 test 路径同样生效：member_lib 闭包视图落 deps 子树。
    expect(path_exists_as_directory(tprint("%1/target/transpile/deps/member_lib", fixture_root)));
}

// 含 src 内联 test block 的 member 自为 root 时正常发现并执行全部测试
// （入口内联块 + 入口闭包内文件块 + tests/ 独立块，按扫描序）。
test "E2E: member with inline tests runs them as its own root" {
    fixture_root := tprint("%1/tests/data/workspace-ok", juice_root());
    defer delete_directory_full(tprint("%1/member_lib/target", fixture_root));

    result, output, _ := run_juice_test("workspace-ok/member_lib");
    expect(expect_exit("member-own", result, 0));
    expect(output_matches("member-own", output, string.["[juice Test] Found 3 tests; compiling test program..."]));
    expect(output_matches("member-own", output, string.[
        "[test] member extra inline test\n[test] member inline test\n[test] member test must not run in root\n3 passed, 0 failed\n"]));
}
