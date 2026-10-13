#import "Basic";
#import "String";
#import "File";
#import "Compiler";

// 自举转译前置（ADR 0006，票 0031）：metaprogram 内嵌转译器纯函数。被
// #load 的代码编译进 metaprogram 执行环境、绝不进入被构建程序（研究 0028
// e1c）。已知无碍：beta 0.2.009 下编译 transpile.jai 会出两条 `%%` print
// 兼容警告（勿"修复"，避免触碰转译器）。
#load "src/transpile.jai";

// ---------------------------------------------------------------------------
// 转译前置：探测入口（src/main.jai）沿字面量 in-package #load 的传递闭包。
// test-free 闭包原样直编（零转译、零落盘，与改造前一致）；闭包含 test
// block 则全有全无视图化——入口视图经 add_build_string 喂入（虚拟路径，
// 行号偏移恒 +5、列精确），闭包其余视图落盘 target/transpile/bootstrap/
// （target directory 转译子树下的自举构建专属子目录，不与 Build command
// 的内容寻址缓存混用），in-package #load 重写为视图绝对路径（STRIP 已有
// 机制，无新增转译规则）。与 Build command 共用同一转译器与视图契约，
// 行号保真不变量一致（ADR 0005）。
// ---------------------------------------------------------------------------

// 本地小工具：路径分隔符归一为斜杠。与 src/manifest.jai 的
// to_forward_slashes 同语义（build.jai 不 #load 运行时源码，本地复制）。
bootstrap_slashes :: (path: string) -> string {
    result := copy_string(path);
    for i: 0..result.count-1 {
        if result[i] == #char "\\" result[i] = #char "/";
    }
    return result;
}

// 探针闭包文件：包相对路径（"/" 分隔）与其字面量 in-package #load 目标
// （已解析、语句序）。
Bootstrap_Closure_File :: struct {
    rel_path:  string;
    loads:     [..] string;
    has_tests: bool;
}

// 闭包视图计算状态：每文件 0 = 未计算、1 = 计算中（循环加载）、2 = 完成；
// view_paths 与 closure 平行存放各文件的绝对视图路径；入口视图文本单独
// 保存（不落盘，喂给 add_build_string）。
Bootstrap_View_State :: struct {
    closure:    [] Bootstrap_Closure_File;
    entry:      string;   // 入口的包相对路径
    views_dir:  string;   // 视图绝对基目录（"/" 分隔）——#load 重写目标
    disk_dir:   string;   // 视图落盘基目录（相对 cwd、"/" 分隔）
    states:     [..] s64;
    view_paths: [..] string;
    entry_view: string;
    failed:     bool;
}

bootstrap_visited :: (visited: [] string, rel_path: string) -> bool {
    for seen: visited {
        if seen == rel_path return true;
    }
    return false;
}

// DFS 自入口沿字面量 in-package #load 边探测闭包（预序：入口在前，随后按
// 语句序展开各 load 目标的子树）。非字面量与 out-of-package 目标不探测
// 不改写（与 Build command 一致，issue 0008 决议 4）。
bootstrap_probe_closure :: (entry_rel: string) -> [..] Bootstrap_Closure_File, bool {
    files: [..] Bootstrap_Closure_File;
    visited: [..] string;
    stack: [..] string;
    array_add(*stack, entry_rel);

    while stack.count > 0 {
        rel := stack[stack.count - 1];
        stack.count -= 1;
        if bootstrap_visited(visited, rel) continue;
        array_add(*visited, copy_string(rel));

        source, ok := read_entire_file(bootstrap_slashes(rel));
        if !ok {
            print("[Build System] ❌ 无法读取源文件: %1\n", rel);
            return files, false;
        }

        cf: Bootstrap_Closure_File;
        cf.rel_path = rel;
        cf.has_tests = source_has_test_block(source);
        cf.loads = source_load_targets(source, rel);
        array_add(*files, cf);

        // 逆序压栈使 load 目标按语句序弹出。
        i := cf.loads.count;
        while i > 0 {
            i -= 1;
            array_add(*stack, cf.loads[i]);
        }
    }
    return files, true;
}

bootstrap_closure_index :: (state: *Bootstrap_View_State, rel_path: string) -> (s64, bool) {
    for i: 0..state.closure.count-1 {
        if state.closure[i].rel_path == rel_path return i, true;
    }
    return -1, false;
}

// 依依赖序（子先父后）计算一个闭包文件的 STRIP 视图：非入口视图落盘、入
// 口视图文本保存进 state（喂字符串）。返回绝对视图路径（同时作为父文件
// 的 #load 重写目标）。
bootstrap_view_of :: (state: *Bootstrap_View_State, index: s64) -> string, bool {
    if state.failed return "", false;
    if state.states[index] == 2 return state.view_paths[index], true;
    if state.states[index] == 1 {
        print("[Build System] ❌ %1: 循环加载无法重写路径\n", state.closure[index].rel_path);
        state.failed = true;
        return "", false;
    }
    state.states[index] = 1;

    // 子视图先落盘：每个 in-package load 目标都在闭包内（探测保证），其视
    // 图路径先于父文件的重写表存在。
    load_targets: [..] Load_Target;
    for resolved: state.closure[index].loads {
        child_index, found := bootstrap_closure_index(state, resolved);
        if !found {
            print("[Build System] ❌ %1: in-package #load 缺少视图目标\n", state.closure[index].rel_path);
            state.failed = true;
            return "", false;
        }
        child_path, ok := bootstrap_view_of(state, child_index);
        if !ok return "", false;
        target: Load_Target;
        target.from = resolved;
        target.to = child_path;
        array_add(*load_targets, target);
    }

    source, ok := read_entire_file(bootstrap_slashes(state.closure[index].rel_path));
    if !ok {
        print("[Build System] ❌ 无法读取源文件: %1\n", state.closure[index].rel_path);
        state.failed = true;
        return "", false;
    }
    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = state.closure[index].rel_path;
    ctx.load_targets = load_targets;
    result := transpile_source(source, ctx);
    if result.diagnostics.count > 0 {
        for diagnostic: result.diagnostics {
            print("[Build System] ❌ %1:%2,%3: %4\n", state.closure[index].rel_path, diagnostic.line, diagnostic.column, diagnostic.message);
        }
        state.failed = true;
        return "", false;
    }

    view_path := tprint("%1/%2", state.views_dir, state.closure[index].rel_path);
    if state.closure[index].rel_path == state.entry {
        state.entry_view = copy_string(result.view);
    } else {
        disk_path := tprint("%1/%2", state.disk_dir, state.closure[index].rel_path);
        parent := bootstrap_slashes(path_strip_filename(disk_path));
        if !make_directory_if_it_does_not_exist(parent, recursive = true) {
            print("[Build System] ❌ 无法创建视图目录: %1\n", parent);
            state.failed = true;
            return "", false;
        }
        if !write_entire_file(bootstrap_slashes(disk_path), result.view) {
            print("[Build System] ❌ 无法写入视图: %1\n", disk_path);
            state.failed = true;
            return "", false;
        }
    }

    state.view_paths[index] = copy_string(view_path);
    state.states[index] = 2;
    return view_path, true;
}

// 转译前置主流程：探测入口闭包；test-free 闭包返回 true 且 use_view 保持
// false（原样直编）；闭包含 test block 时计算全部视图——入口视图文本经
// use_view/entry_view 返回、闭包其余视图落盘。失败返回 false（打印错误后
// 跳过构建，与入口守卫同语义）。
bootstrap_strip_front :: (entry_rel: string, use_view: *bool, entry_view: *string) -> bool {
    closure, ok := bootstrap_probe_closure(entry_rel);
    if !ok return false;

    has_tests := false;
    for file: closure {
        if file.has_tests {
            has_tests = true;
            break;
        }
    }
    if !has_tests return true;

    root := bootstrap_slashes(get_working_directory());
    state: Bootstrap_View_State;
    state.closure = closure;
    state.entry = entry_rel;
    state.views_dir = tprint("%1/target/transpile/bootstrap", root);
    state.disk_dir = "target/transpile/bootstrap";
    for _: closure {
        array_add(*state.states, 0);
        array_add(*state.view_paths, "");
    }

    entry_index, found := bootstrap_closure_index(*state, entry_rel);
    if !found {
        print("[Build System] ❌ 入口不在闭包中: %1\n", entry_rel);
        return false;
    }
    _, ok = bootstrap_view_of(*state, entry_index);
    if !ok return false;

    <<use_view = true;
    <<entry_view = state.entry_view;
    return true;
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

    // -------------------------------------------------------------
    // 2. 创建目标程序的 Workspace
    // -------------------------------------------------------------
    set_build_options_dc(.{do_output = false});
    workspace := compiler_create_workspace("Juice App");
    if !workspace return;

    // -------------------------------------------------------------
    // 3. 配置目标 Workspace 选项
    // -------------------------------------------------------------
    options := get_build_options(workspace);
    options.output_executable_name = "juice";
    options.output_path            = "target";
    options.intermediate_path      = "target";

    // 关键：确保 target 目录存在，防止链接器报错 LNK1104
    make_directory_if_it_does_not_exist(options.output_path);

    // 模块导入路径设置
    import_paths: [..] string;
    array_add(*import_paths, .. options.import_path);
    array_add(*import_paths, "./src");
    array_add(*import_paths, "./modules");
    array_add(*import_paths, ".");
    options.import_path = import_paths;

    if is_release {
        print("[Build System] 🚀 Building in RELEASE mode (Very Optimized)...\n");
        set_optimization(*options, .VERY_OPTIMIZED);
    } else {
        print("[Build System] 🛠️  Building in DEBUG mode...\n");
        set_optimization(*options, .DEBUG);
    }

    // -------------------------------------------------------------
    // 4. 应用配置（必须在 begin_intercept 和 add_build_file 之前）
    // -------------------------------------------------------------
    set_build_options(options, workspace);

    // -------------------------------------------------------------
    // 5. 转译前置（ADR 0006，票 0031）：探测入口闭包。test-free 闭包零转
    //    译零落盘、原样直编；闭包含 test block 时入口视图喂字符串（行号偏
    //    移恒 +5、列精确），闭包其余视图落盘 target/transpile/bootstrap/。
    // -------------------------------------------------------------
    entry_is_view := false;
    entry_view: string;
    if !bootstrap_strip_front("src/main.jai", *entry_is_view, *entry_view) return;

    // -------------------------------------------------------------
    // 6. 开启拦截并加载入口文件（剥离视图或原文件）
    // -------------------------------------------------------------
    compiler_begin_intercept(workspace);
    if entry_is_view {
        add_build_string(entry_view, workspace);
    } else {
        add_build_file("src/main.jai", workspace);
    }

    // -------------------------------------------------------------
    // 7. 编译期消息循环与错误拦截
    // -------------------------------------------------------------
    has_errors := false;
    while true {
        msg := compiler_wait_for_message();
        if !msg continue;

        if msg.workspace == workspace {
            if msg.kind == {
                case .ERROR;
                    has_errors = true;
                case .COMPLETE;
                    break;
            }
        }
    }

    compiler_end_intercept(workspace);

    if !has_errors {
        mode_str := ifx is_release then "Release" else "Debug";
        print("[Build System] ✅ %1 build succeeded! Binary -> %2/%3.exe\n",
              mode_str, options.output_path, options.output_executable_name);
    } else {
        print("[Build System] ❌ Build failed.\n");
    }
}
