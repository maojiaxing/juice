// ---------------------------------------------------------------------------
// 剥离前端（票 0050，架构体检候选 2）：闭包探测、视图计算与生产 transpile
// 步骤的 test-free 共享模块。
//
// 三个消费方：
// - bootstrap build.jai 以 #load 复用（metaprogram 编译单元不能包含 test
//   block，#load 目标必须 test-free——本文件测试驻
//   tests/transpile_front_tests.jai，先例 tests/transpile_tests.jai，票
//   0053 测试组织规则）；
// - Build command 与依赖剥离前端经程序级 #load 复用（main.jai 装载序：
//   transpile.jai → transpile_cache.jai → 本文件，与 build.jai 的 #load 序
//   对称）。
//
// 两个 adapter 成立的真实 seam：视图落点与入口处理按 Strip_View_Layout
// 参数化——CONTENT_ADDRESSED（runtime：内容寻址 + 缓存命中跳过写入，入口
// 落盘）与 PLAIN（bootstrap：<base>/<rel> 恒写、入口视图留内存喂
// add_build_string，行号偏移恒 +5）。报错前缀按消费方注入（error_prefix）。
// ---------------------------------------------------------------------------

#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

// 路径分隔符归一为斜杠。本模块自包含的本地实现：bootstrap #load 本模块，
// 不能依赖 path_safety/manifest 的运行时代码（与 path_safety.jai 的
// path_slashes 同语义；bootstrap 的原本地复制随票 0050 删除）。
front_slashes :: (path: string) -> string {
    result := copy_string(path);
    for i: 0..result.count-1 {
        if result[i] == #char "\\" result[i] = #char "/";
    }
    return result;
}

// One build source file: package-relative path ("/" separated) and absolute
// path, mirroring the test command's Test_Source_File. A dependency closure
// file's rel_path is relative to the dependency package root (views land
// under deps/<name>/..., the path itself stays dependency-relative).
// 原驻 dependency.jai（票 0049），票 0050 随剥离前端迁入。
Build_Source_File :: struct {
    rel_path: string;
    abs_path: string;
}

// One probed closure file: its resolved in-package literal #load targets in
// statement order, and whether it contains test blocks.
Build_Closure_File :: struct {
    file:      Build_Source_File;
    loads:     [..] string;
    has_tests: bool;
}

// The transpile step's output for one file: the strip-mode view, the
// content-addressed cache key, and transpile diagnostics (rejected with the
// original file coordinates).
Build_File_Output :: struct {
    view:        string;
    key:         string;
    diagnostics: [..] Transpile_Diagnostic;
}

probe_visited :: (visited: [] string, rel_path: string) -> bool {
    for seen: visited {
        if seen == rel_path return true;
    }
    return false;
}

// Probe one package's closure: DFS from the entry over literal in-package
// #load edges, with `package_root` as the resolution boundary. Non-literal
// and out-of-package targets are not followed (issue 0008 resolution 4).
// Files are listed in DFS preorder — the entry first, then each load
// target's subtree in statement order. The consumer package's build closure
// (build.jai's probe_build_closure), dependency closures (dependency.jai 的
// 依赖剥离前端) and the bootstrap closure (build.jai) share this probe.
// error_prefix 由消费方注入（bootstrap 用 "[Build System] ❌ "）。
probe_package_closure :: (package_root: string, entry_rel: string, error_prefix: string = "[juice ERROR] ") -> [..] Build_Closure_File, bool {
    entry: Build_Source_File;
    entry.rel_path = entry_rel;
    entry.abs_path = front_slashes(tprint("%1/%2", package_root, entry_rel));

    files: [..] Build_Closure_File;
    visited: [..] string;
    stack: [..] Build_Source_File;
    array_add(*stack, entry);

    while stack.count > 0 {
        file := stack[stack.count - 1];
        stack.count -= 1;
        if probe_visited(visited, file.rel_path) continue;
        array_add(*visited, copy_string(file.rel_path));

        source, ok := read_entire_file(file.abs_path);
        if !ok {
            print("%1无法读取源文件: %2\n", error_prefix, file.abs_path);
            return files, false;
        }

        cf: Build_Closure_File;
        cf.file = file;
        cf.has_tests = source_has_test_block(source);
        cf.loads = source_load_targets(source, file.rel_path);
        array_add(*files, cf);

        // Push in reverse so targets pop in statement order.
        i := cf.loads.count;
        while i > 0 {
            i -= 1;
            target: Build_Source_File;
            target.rel_path = cf.loads[i];
            target.abs_path = front_slashes(tprint("%1/%2", package_root, cf.loads[i]));
            array_add(*stack, target);
        }
    }
    return files, true;
}

// 闭包全有全无判定的共享判定（issue 0008 决议 1/2）：任一文件含 test block
// 即整闭包视图化。bootstrap 前端、Build command 前端与依赖剥离前端三处同
// 体扫描收敛于此（票 0050）。
closure_has_tests :: (closure: [] Build_Closure_File) -> bool {
    for file: closure {
        if file.has_tests return true;
    }
    return false;
}

// 内容寻址缓存的 skip-existing 判定。本模块自包含的本地实现：bootstrap
// #load 本模块，不能依赖 path_safety.jai 的运行时代码（其
// path_exists_as_regular_file 经 inspect_path_entry 同语义——存在且是普通
// 文件即跳过写入）。目标目录受「普通目录、非符号链接」约束（CONTEXT.md），
// 视图路径上的符号链接是既有防御之外的同级边角；PLAIN 布局不经过本判定
// （恒写）。
front_view_exists :: (path: string) -> bool {
    return file_exists(path) && !is_directory(path);
}

// 视图落点与入口处理的两种布局（两个 adapter，真实 seam）：
// - CONTENT_ADDRESSED：runtime——内容寻址视图路径（transpile_cache.jai 的
//   transpile_view_path / transpile_dependency_view_path），缓存命中跳过写
//   入（skip existing）；
// - PLAIN：bootstrap——<transpile_dir>/<rel> 恒写、无缓存。票 0052 起入口
//   同样落盘（bootstrap 改走「生成 + 子进程」，生成的 metaprogram 以
//   add_build_file 编译入口视图，诊断精确文件+行号——add_build_string 的
//   +5 偏移与「入口进内存」分支随之退役）。
Strip_View_Layout :: enum {
    CONTENT_ADDRESSED;
    PLAIN;
}

// Shared state of one closure's view computation: per-file states (0 =
// uncomputed, 1 = computing, 2 = done) and the resulting view paths.
// "Computing" re-entry means the literal in-package #load graph has a
// cycle and the path rewrites cannot be resolved (issue 0008 resolution 2).
// dep_name non-empty marks a dependency closure: views land under
// deps/<dep_name>/ instead of the tree root (票 0049). 原 Build_View_State
// （dependency.jai，票 0049），票 0050 泛化迁入。
Strip_View_State :: struct {
    closure:       [] Build_Closure_File;
    transpile:     #type (file: Build_Source_File, load_targets: [] Load_Target) -> Build_File_Output;
    transpile_dir: string;   // CONTENT_ADDRESSED：转译树根；PLAIN：视图基目录（绝对）
    dep_name:      string;   // CONTENT_ADDRESSED 非空 → deps/<名> 子树
    layout:        Strip_View_Layout;
    error_prefix:  string = "[juice ERROR] ";
    states:        [..] s64;
    view_paths:    [..] string;
    failed:        bool;
}

closure_index :: (state: *Strip_View_State, rel_path: string) -> (s64, bool) {
    for i: 0..state.closure.count-1 {
        if state.closure[i].file.rel_path == rel_path return i, true;
    }
    return -1, false;
}

// Compute one closure file's strip view in dependency order (children
// first, Merkle chain) and write it per the state's layout. Returns the
// absolute view path. 票 0052：两种布局的入口都落盘（PLAIN 的「入口进内
// 存」分支随 add_build_string 退役）。
view_of_file :: (state: *Strip_View_State, index: s64) -> string, bool {
    if state.failed return "", false;
    if state.states[index] == 2 return state.view_paths[index], true;
    if state.states[index] == 1 {
        print("%1%2: 循环加载无法重写路径\n", state.error_prefix, state.closure[index].file.rel_path);
        state.failed = true;
        return "", false;
    }
    state.states[index] = 1;

    // Children first: every in-package load target is in the closure by
    // construction, so its view path exists before the parent's key embeds
    // it in a load rewrite.
    load_targets: [..] Load_Target;
    for resolved: state.closure[index].loads {
        child_index, found := closure_index(state, resolved);
        if !found {
            print("%1%2: in-package #load 缺少视图目标\n", state.error_prefix, state.closure[index].file.rel_path);
            state.failed = true;
            return "", false;
        }
        child_path, ok := view_of_file(state, child_index);
        if !ok return "", false;
        target: Load_Target;
        target.from = resolved;
        target.to = child_path;
        array_add(*load_targets, target);
    }

    output := state.transpile(state.closure[index].file, load_targets);
    if output.diagnostics.count > 0 {
        for diagnostic: output.diagnostics {
            print("%1%2:%3,%4: %5\n", state.error_prefix, state.closure[index].file.rel_path, diagnostic.line, diagnostic.column, diagnostic.message);
        }
        state.failed = true;
        return "", false;
    }

    rel := state.closure[index].file.rel_path;
    view_path := ifx state.layout == .CONTENT_ADDRESSED
        then ifx state.dep_name == ""
            then transpile_view_path(state.transpile_dir, output.key, rel)
            else transpile_dependency_view_path(state.transpile_dir, output.key, state.dep_name, rel)
        else tprint("%1/%2", front_slashes(state.transpile_dir), rel);

    // The parent must exist before the existence check: the inspection
    // scans the parent directory, and a missing parent would make
    // visit_files log a spurious "Unable to open directory" error.
    if !make_directory_if_it_does_not_exist(path_strip_filename(view_path), recursive = true) {
        print("%1无法创建视图目录: %2\n", state.error_prefix, rel);
        state.failed = true;
        return "", false;
    }
    if state.layout == .PLAIN || !front_view_exists(view_path) {
        if !write_entire_file(view_path, output.view) {
            print("%1无法写入视图: %2\n", state.error_prefix, rel);
            state.failed = true;
            return "", false;
        }
    }

    state.view_paths[index] = copy_string(view_path);
    state.states[index] = 2;
    return view_path, true;
}

// The build transpile step's production default: read the file, strip test
// blocks, rewrite in-package #load targets to the given view paths, and
// derive the content-addressed cache key (path + source + mode + version +
// load targets). The load rewrite table embeds the target views' hash
// directories, so keys form a Merkle chain computable in dependency order.
// 原驻 commands/build.jai（票 0049），票 0050 迁入——bootstrap 与 Build
// command 共用同一生产步骤。
transpile_build_file :: (file: Build_Source_File, load_targets: [] Load_Target) -> Build_File_Output {
    output: Build_File_Output;
    source, ok := read_entire_file(file.abs_path);
    if !ok {
        array_add(*output.diagnostics, .{line = 0, column = 0, message = tprint("无法读取源文件: %1", file.abs_path)});
        return output;
    }
    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = file.rel_path;
    ctx.load_targets = load_targets;
    result := transpile_source(source, ctx);
    output.view = result.view;
    output.key = transpile_view_key(file.rel_path, source, .STRIP, load_targets, JUICE_VERSION);
    output.diagnostics = result.diagnostics;
    return output;
}

// ---------------------------------------------------------------------------
// Testing 断言模块 STRIP 特例（票 0033 对称特例；票 0051 收口于此——bootstrap
// 与 Build command 共用一份，此前两者各持同路径同哨兵的对称副本）：模块源文
// 件内联 test block 后不可被 jai 直接编译，任何 `#import "Testing"` 的构建都
// 必须解析到 test-free 的 STRIP 视图。本函数在每次编译前重写
// <package_root>/target/testing-module/Testing.jai（session product，与 test
// 命令的编译视图同路径——test 写 EXPAND、build/自举写 STRIP，各自运行前重
// 写）。模块 test-free、缺失或不可读时返回 ""：metaprogram 输出与特例前字
// 节一致，零变化。module_source 由消费方给定：bootstrap 传 cwd 相对
// "modules/Testing.jai"，Build command 传 juice_modules_dir() 推导的绝对路径
// （bootstrap 无法引用 path_safety 的运行时代码）。
// ---------------------------------------------------------------------------
testing_module_strip_view_dir :: (package_root: string, module_source: string, error_prefix: string = "[juice ERROR] ") -> string {
    module_abs := front_slashes(module_source);
    if !front_view_exists(module_abs) return "";
    source, ok := read_entire_file(module_abs);
    if !ok return "";
    if !source_has_test_block(source) return "";

    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = "modules/Testing.jai";
    result := transpile_source(source, ctx);
    if result.diagnostics.count > 0 {
        for diagnostic: result.diagnostics {
            print("%1%2:%3,%4: %5\n", error_prefix, ctx.path, diagnostic.line, diagnostic.column, diagnostic.message);
        }
        return "";
    }

    dir := front_slashes(tprint("%1/target/testing-module", package_root));
    if !make_directory_if_it_does_not_exist(dir, recursive = true) {
        print("%1无法创建视图目录: %2\n", error_prefix, dir);
        return "";
    }
    view := tprint("%1/Testing.jai", dir);
    if !write_entire_file(view, result.view) {
        print("%1无法写入视图: %2\n", error_prefix, view);
        return "";
    }
    return dir;
}
