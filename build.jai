#import "Basic";
#import "String";
#import "File";
#import "Compiler";
#import "Process";

// 自举转译前置（ADR 0006，票 0031；票 0050 共享化；票 0052 骨架收敛）：
// metaprogram #load test-free 共享模块——src/transpile_front.jai（闭包探测、
// 视图计算与生产 transpile 步骤，PLAIN 布局：<base>/<rel> 恒写、全闭包落
// 盘含入口）与 src/metaprogram.jai（共享 Metaprogram generator，本文件生
// 成编译 metaprogram 后 spawn 子进程 jai 编译——与 Build command 同形状，
// 入口视图经 add_build_file 编译、诊断精确文件+行号，add_build_string 的
// +5 偏移退役）。src/transpile_cache.jai 提供共享前端引用的内容寻址路径函
// 数。被 #load 的代码编译进 metaprogram 执行环境、绝不进入被构建程序（研
// 究 0028 e1c）。已知无碍：beta 0.2.009 下编译 transpile.jai 会出两条
// `%%` print 兼容警告（勿"修复"，避免触碰转译器）。
#load "src/transpile.jai";
#load "src/transpile_cache.jai";
#load "src/transpile_front.jai";
#load "src/metaprogram.jai";

// 剥离前端（票 0031 探测语义；票 0050 机器共享；票 0052 入口落盘）：探测
// 入口（src/main.jai）沿字面量 in-package #load 的传递闭包。test-free 闭包
// 返回原文件绝对路径（零转译零落盘，原样直编）；闭包含 test block 则全有
// 全无视图化——含入口的全部闭包视图落盘 target/transpile/bootstrap/
// （target directory 转译子树下的自举构建专属子目录，不与 Build command
// 的内容寻址缓存混用），返回入口视图路径；in-package #load 重写为视图绝
// 对路径（STRIP 已有机制，无新增转译规则）。与 Build command 共用同一转译
// 器与视图契约，行号保真不变量一致（ADR 0005）。
bootstrap_build_entry :: (entry_rel: string) -> string, bool {
    root := front_slashes(get_working_directory());
    closure, ok := probe_package_closure(root, entry_rel, "[Build System] ❌ ");
    if !ok return "", false;
    if !closure_has_tests(closure) return tprint("%1/%2", root, entry_rel), true;

    state: Strip_View_State;
    state.closure = closure;
    state.transpile = transpile_build_file;
    state.transpile_dir = tprint("%1/target/transpile/bootstrap", root);
    state.layout = .PLAIN;
    state.error_prefix = "[Build System] ❌ ";
    for _: closure {
        array_add(*state.states, 0);
        array_add(*state.view_paths, "");
    }
    entry_index, found := closure_index(*state, entry_rel);
    if !found {
        print("[Build System] ❌ 入口不在闭包中: %1\n", entry_rel);
        return "", false;
    }
    entry_path, view_ok := view_of_file(*state, entry_index);
    return entry_path, view_ok;
}

#run {
    // -------------------------------------------------------------
    // 1. 读取命令行参数
    // -------------------------------------------------------------
    build_args := get_toplevel_command_line();

    // 本文件被 `juice test` 作为视图加载进测试程序时（测试程序的编译入口是
    // 生成的 target/transpile/first.jai），跳过构建：编译期执行会连累整棵
    // 构建树进入测试程序编译。直接 `jai build.jai` 时末参数是本文件自身。
    if build_args.count > 0 {
        last_arg := build_args[build_args.count - 1];
        if ends_with(last_arg, "/first.jai") || ends_with(last_arg, "\\first.jai") return;
    }

    is_release := false;
    for arg: build_args {
        if arg == "release" || arg == "-release" {
            is_release = true;
        } else if arg == "debug" || arg == "-debug" {
            is_release = false;
        }
    }

    root := front_slashes(get_working_directory());

    // -------------------------------------------------------------
    // 2. 声明构建由本 metaprogram 自理（票 0052）：jai 在 #run 未创建任何
    //    workspace 时会回落 Default_Metaprogram 编译命令行文件本身
    //    （build.jai 无 main → "No program entry point" 错误、退出码 1）。
    //    创建空 workspace 是「构建已由本 metaprogram 处理」的信号——真正
    //    编译发生在步骤 5 的子进程 jai。
    // -------------------------------------------------------------
    set_build_options_dc(.{do_output = false});
    delegation := compiler_create_workspace("Bootstrap Delegation");
    if !delegation return;

    // -------------------------------------------------------------
    // 3. 剥离前端：探测入口闭包，选择编译入口（原文件或入口视图）。
    // -------------------------------------------------------------
    entry, ok := bootstrap_build_entry("src/main.jai");
    if !ok return;

    // -------------------------------------------------------------
    // 4. Testing 断言模块自举特例（票 0033 对称；票 0051 收口：实现驻共享
    //    剥离前端 testing_module_strip_view_dir，bootstrap 与 Build
    //    command 共用一份，此处仅传 cwd 相对模块路径与报错前缀）：
    //    modules/Testing.jai 内联 test block 后不可被 jai 直接编译，而闭包
    //    内 `#import "Testing"` 会解析到模块源文件。模块含 test block 时把
    //    STRIP 视图写到 target/testing-module/Testing.jai 并把其目录前置进
    //    生成 metaprogram 的 import path。模块 test-free 或不存在时
    //    testing_view_dir 保持 ""，零变化。
    //    哨兵约定：testing_view_dir == "" 表示「未启用编译视图特例」——与
    //    共享 Metaprogram generator 的 testing_view_dir 参数（票 0036）、
    //    共享 testing_module_strip_view_dir 的返回值同一约定。
    // -------------------------------------------------------------
    testing_view_dir := testing_module_strip_view_dir(root, "modules/Testing.jai", "[Build System] ❌ ");

    // -------------------------------------------------------------
    // 5. 生成编译 metaprogram（票 0052：与 Build command 共用共享
    //    Metaprogram generator）并 spawn 子进程 jai 编译。子进程输出实时
    //    透传（本 metaprogram 的打印由 jai 收集、正常结束时才刷出——故
    //    🚀/✅ 行出现在编译输出之后；失败路径 exit(1) 会吞掉本 metaprogram
    //    的 ❌ 行，退出码与子进程错误输出仍完整，票 0015 机制）。失败时以
    //    exit(1) 传递退出码，保持三路径 seam。
    // -------------------------------------------------------------
    meta: Compiler_Metaprogram_Options;
    meta.workspace_name    = "Juice Build";
    meta.executable_name   = "juice";
    meta.output_path       = "target";
    meta.intermediate_path = "target";
    import_dirs: [..] string;
    array_add(*import_dirs, tprint("%1/src", root));
    array_add(*import_dirs, tprint("%1/modules", root));
    array_add(*import_dirs, root);
    meta.import_dirs       = import_dirs;
    meta.build_file        = entry;
    meta.testing_view_dir  = testing_view_dir;
    meta.very_optimized    = is_release;

    // 关键：确保 target 目录存在，防止链接器报错 LNK1104
    make_directory_if_it_does_not_exist("target");
    meta_path := "target/bootstrap-meta.jai";
    if !write_entire_file(meta_path, generate_compiler_metaprogram(meta)) {
        print("[Build System] ❌ 无法写入构建 metaprogram: %1\n", meta_path);
        exit(1);
    }

    if is_release {
        print("[Build System] 🚀 Building in RELEASE mode (Very Optimized)...\n");
    } else {
        print("[Build System] 🛠️  Building in DEBUG mode...\n");
    }
    result := run_command("jai", meta_path);
    if result.exit_code != 0 {
        print("[Build System] ❌ Build failed.\n");
        exit(1);
    }

    mode_str := ifx is_release then "Release" else "Debug";
    print("[Build System] ✅ %1 build succeeded! Binary -> target/juice.exe\n", mode_str);
}
