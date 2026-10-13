#import "Basic";
#import "Process";
#import "File";
#import "File_Utilities";
#import "String";
#import "Juice";
#import "Testing";

BUILD_COMMAND :: Command.{
    name          = "build",
    description   = "Build all targets in the root package",
    usage         = "juice build",
    prerequisites = string.["prepare-workspace"],
    visible       = true,
    handler       = build_command,
};

build_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if !command_arguments_are_valid(BUILD_COMMAND, arguments) return false;
    prepared := require_prepared_workspace("build", *ctx.workspace);
    if prepared == null return false;
    if !build_prepared_workspace(ctx.driver, prepared) return false;
    if prepared.artifact_plans.count == 0 {
        if prepared.package_type == .LIB {
            print("[juice] Library package '%'; nothing to build.\n", prepared.discovery.root_package.name);
        } else {
            print("[juice] No executable targets; nothing to build.\n");
        }
    }
    print("[juice] Build completed successfully!\n");
    return true;
}

// Import directories every compile gets beyond jai's own defaults: the
// juice module directory (adjacent to the running executable, holds
// Testing.jai/Juice.jai) and the package's dependency shim directory.
// juice_modules_dir is the shared derivation (src/path_safety.jai, 票 0036).
compiler_import_directories :: (driver: *Build_Driver) -> [..] string {
    dirs: [..] string;
    dirs.allocator = temp;

    global_modules_dir := juice_modules_dir();
    if is_directory(global_modules_dir) array_add(*dirs, global_modules_dir);

    if is_directory(driver.packages_dir) {
        array_add(*dirs, to_forward_slashes(driver.packages_dir));
    }
    return dirs;
}

// Revalidate the whole build input before compiling anything, so an unsafe
// plan cannot produce a partial build. Plan structure and paths are owned by
// this gate; compile_artifact_plan pre-checks only its own source file.
revalidate_build_plans :: (prepared: *Prepared_Workspace) -> bool {
    package_root := prepared.discovery.root_dir;
    root_entry := inspect_path_entry(package_root);
    if !root_entry.exists || !root_entry.is_directory || root_entry.is_symlink || root_entry.is_junction {
        print("[juice ERROR] Package root changed or is unsafe before build.\n");
        return false;
    }

    for plan: prepared.artifact_plans {
        if !revalidate_artifact_plan(plan, package_root) {
            print("[juice ERROR] Artifact path became unsafe before build: %\n", plan.artifact_path);
            return false;
        }
        source_entry := inspect_path_entry(plan.target.source_path);
        if !source_entry.exists || source_entry.is_directory || source_entry.is_symlink || source_entry.is_junction {
            print("[juice ERROR] Target source became unsafe before build: %\n", plan.target.source_path);
            return false;
        }
    }
    return true;
}

compile_artifact_plan :: (driver: *Build_Driver, plan: Artifact_Plan, entry: string) -> bool {
    // The compile entry is chosen by the transpile front: the original
    // entry file (test-free closure, zero transpile) or its strip view.
    source_file := to_forward_slashes(entry);
    if !path_exists_as_regular_file(source_file) {
        print("[juice ERROR] Target source file not found: %\n", source_file);
        return false;
    }

    if !make_directory_if_it_does_not_exist(plan.target_dir, recursive = true) {
        print("[juice ERROR] Could not create target directory: %\n", plan.target_dir);
        return false;
    }

    print("[juice Build] Compiling Target '%' (%) -> target/...\n", plan.target.name, plan.target.main_file);

    // The compile runs through a generated metaprogram (session product in
    // the target directory, like the test command's driver/metaprogram):
    // jai has no flag for Build_Options.intermediate_path, so the
    // metaprogram sets it to the target directory — compiler intermediates
    // (.obj, .lib, .added_strings_*) land there instead of a .build
    // directory next to the entry, and Clean removes them with target/.
    metaprogram_path := to_forward_slashes(tprint("%1/build-%2.jai", plan.target_dir, plan.target.name));
    testing_dir := testing_module_strip_view_dir(driver.root_dir);
    metaprogram: Compiler_Metaprogram_Options;
    metaprogram.workspace_name    = "Juice Build";
    metaprogram.executable_name   = plan.target.name;
    metaprogram.output_path       = to_forward_slashes(plan.target_dir);
    metaprogram.intermediate_path = to_forward_slashes(plan.target_dir);
    metaprogram.import_dirs       = compiler_import_directories(driver);
    metaprogram.build_file        = source_file;
    metaprogram.testing_view_dir  = testing_dir;
    if !write_entire_file(metaprogram_path, generate_compiler_metaprogram(metaprogram)) {
        print("[juice ERROR] Could not write build metaprogram: %\n", metaprogram_path);
        return false;
    }

    result := run_command("jai", metaprogram_path);
    if result.exit_code != 0 {
        print("[juice ERROR] Compilation failed for target '%'.\n", plan.target.name);
        return false;
    }

    if !file_exists(plan.artifact_path) {
        print("[juice ERROR] Compiler did not produce expected artifact: %\n", plan.artifact_path);
        return false;
    }
    return true;
}

// The compile runs through a metaprogram generated by the shared
// Metaprogram generator (src/metaprogram.jai, 票 0036): Build assembles the
// options here — executable output into the plan's target directory, the
// juice module directory and the dependency shim directory as import
// directories, and the (possibly viewed) entry as the build file.

// Build transpile front (ADR 0004, tickets 0008/0021): per target, probe the
// entry's closure of literal in-package #loads. A test-free closure compiles
// the original entry unchanged (zero transpile, zero cache); a closure
// containing test blocks is viewed wholesale — every closure file gets a
// strip view and the entry becomes the entry file's view. Non-literal and
// out-of-package #load targets are never viewed or rewritten; test blocks
// there surface as plain jai compile errors.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Testing 断言模块构建特例（票 0033）：模块源文件内联 test block 后不可被
// jai 直接编译，任何 `#import "Testing"` 的构建都必须解析到 test-free 的
// STRIP 视图。本函数在每次编译前重写 <package>/target/testing-module/
// Testing.jai（session product，与 test 命令的编译视图同路径——test 写
// EXPAND、build 写 STRIP，各自运行前重写）。模块 test-free 或不存在时
// 返回 ""：metaprogram 输出与特例前字节一致，零变化。
// ---------------------------------------------------------------------------
testing_module_strip_view_dir :: (package_root: string) -> string {
    module_abs := to_forward_slashes(tprint("%1/Testing.jai", juice_modules_dir()));
    if !path_exists_as_regular_file(module_abs) return "";
    source, ok := read_entire_file(module_abs);
    if !ok return "";
    if !source_has_test_block(source) return "";

    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = "modules/Testing.jai";
    result := transpile_source(source, ctx);
    if result.diagnostics.count > 0 {
        for diagnostic: result.diagnostics {
            print("[juice ERROR] %1:%2,%3: %4\n", ctx.path, diagnostic.line, diagnostic.column, diagnostic.message);
        }
        return "";
    }

    dir := to_forward_slashes(tprint("%1/target/testing-module", package_root));
    if !make_directory_if_it_does_not_exist(dir, recursive = true) {
        print("[juice ERROR] Could not create Testing module view directory: %\n", dir);
        return "";
    }
    view := to_forward_slashes(tprint("%1/Testing.jai", dir));
    if !write_entire_file(view, result.view) {
        print("[juice ERROR] Could not write Testing module view.\n");
        return "";
    }
    return dir;
}

// One build source file: package-relative path ("/" separated) and absolute
// path, mirroring the test command's Test_Source_File.
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

// The build transpile seam's production default: read the file, strip test
// blocks, rewrite in-package #load targets to the given view paths, and
// derive the content-addressed cache key (path + source + mode + version +
// load targets). The load rewrite table embeds the target views' hash
// directories, so keys form a Merkle chain computable in dependency order.
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

probe_visited :: (visited: [] string, rel_path: string) -> bool {
    for seen: visited {
        if seen == rel_path return true;
    }
    return false;
}

// Probe one target's closure: DFS from the entry over literal in-package
// #load edges. Non-literal and out-of-package targets are not followed
// (issue 0008 resolution 4). Files are listed in DFS preorder — the entry
// first, then each load target's subtree in statement order.
probe_build_closure :: (prepared: *Prepared_Workspace, plan: Artifact_Plan) -> [..] Build_Closure_File, bool {
    package_root := prepared.discovery.root_dir;
    entry: Build_Source_File;
    entry.rel_path = path_slashes(plan.target.main_file);
    entry.abs_path = to_forward_slashes(plan.target.source_path);

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
            print("[juice ERROR] Could not read source file for build: %\n", file.abs_path);
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
            target.abs_path = to_forward_slashes(tprint("%1/%2", package_root, cf.loads[i]));
            array_add(*stack, target);
        }
    }
    return files, true;
}

// Shared state of one closure's view computation: per-file states (0 =
// uncomputed, 1 = computing, 2 = done) and the resulting view paths.
// "Computing" re-entry means the literal in-package #load graph has a
// cycle and the path rewrites cannot be resolved (issue 0008 resolution 2).
Build_View_State :: struct {
    transpile_dir: string;
    closure:       [] Build_Closure_File;
    transpile:     #type (file: Build_Source_File, load_targets: [] Load_Target) -> Build_File_Output;
    states:        [..] s64;
    view_paths:    [..] string;
    failed:        bool;
}

closure_index :: (state: *Build_View_State, rel_path: string) -> (s64, bool) {
    for i: 0..state.closure.count-1 {
        if state.closure[i].file.rel_path == rel_path return i, true;
    }
    return -1, false;
}

// Compute one closure file's strip view in dependency order (children
// first, Merkle chain) and write it content-addressed into the transpile
// tree. Returns the absolute view path.
view_of_file :: (state: *Build_View_State, index: s64) -> string, bool {
    if state.failed return "", false;
    if state.states[index] == 2 return state.view_paths[index], true;
    if state.states[index] == 1 {
        print("[juice ERROR] %1: 循环加载无法重写路径\n", state.closure[index].file.rel_path);
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
            print("[juice ERROR] %1: in-package #load 缺少视图目标\n", state.closure[index].file.rel_path);
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
            print("[juice ERROR] %1:%2,%3: %4\n", state.closure[index].file.rel_path, diagnostic.line, diagnostic.column, diagnostic.message);
        }
        state.failed = true;
        return "", false;
    }

    view_path := transpile_view_path(state.transpile_dir, output.key, state.closure[index].file.rel_path);
    // The parent must exist before the existence check: the inspection
    // scans the parent directory, and a missing parent would make
    // visit_files log a spurious "Unable to open directory" error.
    if !make_directory_if_it_does_not_exist(path_strip_filename(view_path), recursive = true) {
        print("[juice ERROR] Could not create view directory for %\n", state.closure[index].file.rel_path);
        state.failed = true;
        return "", false;
    }
    if !path_exists_as_regular_file(view_path) {
        if !write_entire_file(view_path, output.view) {
            print("[juice ERROR] Could not write view for %\n", state.closure[index].file.rel_path);
            state.failed = true;
            return "", false;
        }
    }

    state.view_paths[index] = copy_string(view_path);
    state.states[index] = 2;
    return view_path, true;
}

// Decide one plan's compile entry: probe the entry's closure; a test-free
// closure compiles the original entry unchanged, a closure containing test
// blocks is viewed all-or-nothing (issue 0008 resolution 1/2) and the entry
// becomes the entry file's view.
build_plan_entry :: (
    prepared: *Prepared_Workspace,
    plan: Artifact_Plan,
    transpile: #type (file: Build_Source_File, load_targets: [] Load_Target) -> Build_File_Output
) -> (string, bool) {
    closure, ok := probe_build_closure(prepared, plan);
    if !ok return "", false;

    has_tests := false;
    for file: closure {
        if file.has_tests {
            has_tests = true;
            break;
        }
    }
    if !has_tests return to_forward_slashes(plan.target.source_path), true;

    state: Build_View_State;
    state.transpile_dir = transpile_tree_dir(prepared.discovery.root_dir);
    state.closure = closure;
    state.transpile = transpile;
    for _: closure {
        array_add(*state.states, 0);
        array_add(*state.view_paths, "");
    }
    entry_index, found := closure_index(*state, path_slashes(plan.target.main_file));
    if !found return "", false;
    entry_path, view_ok := view_of_file(*state, entry_index);
    return entry_path, view_ok;
}

// The compile seam mirrors run's launch and clean's validate/delete seams;
// the transpile front mirrors the test command's orchestration seam (spec
// 0013 Testing Decisions): production handlers use the defaults; tests cross
// the same interfaces with recording adapters instead of the real compiler.
build_prepared_workspace :: (
    driver: *Build_Driver,
    prepared: *Prepared_Workspace,
    transpile: #type (file: Build_Source_File, load_targets: [] Load_Target) -> Build_File_Output = transpile_build_file,
    compile: #type (driver: *Build_Driver, plan: Artifact_Plan, entry: string) -> bool = compile_artifact_plan
) -> bool {
    // Empty target sets are an intentional no-op. In particular, do not
    // create target/ and do not prepare dependencies for such a package.
    if prepared.artifact_plans.count == 0 return true;
    if !revalidate_build_plans(prepared) return false;

    // Transpile front: per plan, probe the entry's closure and choose
    // between the original entry and the entry file's strip view.
    entries: [..] string;
    for plan: prepared.artifact_plans {
        entry, ok := build_plan_entry(prepared, plan, transpile);
        if !ok return false;
        array_add(*entries, entry);
    }

    for plan, index: prepared.artifact_plans {
        if !compile(driver, plan, entries[index]) return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// 内联测试（票 0034 自旧 tests/ 迁移）：Build 编排、转译前置
// seam 与 probe、真实剥离步骤，以及 fixture package 的 E2E child 场景。
// 共享 helper（test_compile_* 记录全局、fake_build_transpile 等 seam fake、
// build_seam_* 与 run_juice_child 等 child 场景 helper）见
// tests/test_support.jai。
// ---------------------------------------------------------------------------

test "Build without targets compiles nothing" {
    driver: Build_Driver;
    prepared: Prepared_Workspace;
    prepared.artifact_plans = Artifact_Plan.[];
    test_compile_count = 0;
    expect(build_prepared_workspace(*driver, *prepared, fake_build_transpile, test_compile_artifact) && test_compile_count == 0);
}

test "Unsafe package root blocks every compilation" {
    driver: Build_Driver;
    root := tprint("%1/missing-package-root", juice_root());
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", juice_root())}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/alpha.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    test_build_transpile_calls = 0;
    expect(!build_prepared_workspace(*driver, *prepared, fake_build_transpile, test_compile_artifact));
    expect(test_compile_count == 0 && test_build_transpile_calls == 0);
}

test "Escaping artifact plan blocks compilation" {
    driver: Build_Driver;
    root := juice_root();
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/../escape", root), artifact_path = tprint("%1/../escape/alpha.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    expect(!build_prepared_workspace(*driver, *prepared, fake_build_transpile, test_compile_artifact) && test_compile_count == 0);
}

// The repository's own entry closure contains inline test blocks (they live
// next to the implementation): the transpile front views every closure file
// and compilation receives the entry file's strip view — the fixture 语义
// 随迁移翻转（原断言 test-free 直通：零转译、编译入口为原文件）。
test "Build forwards each prepared plan to compilation" {
    driver: Build_Driver;
    driver.root_dir = "driver-root";
    root := juice_root();
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/alpha.exe", root)},
        .{target = .{name = "beta",  main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/beta.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    closure, ok := probe_build_closure(*prepared, plans[0]);
    expect(ok);
    test_compile_count = 0;
    test_compile_success = true;
    test_build_transpile_calls = 0;
    expect(build_prepared_workspace(*driver, *prepared, fake_build_transpile, test_compile_artifact));
    expect(test_compile_count == 2);
    expect(test_compiled_driver_root == "driver-root");
    // The entry closure contains test blocks: the transpile step ran once
    // per closure file and per plan (children first, the entry last).
    expect(test_build_transpile_calls == 2 * closure.count);
    expect(test_build_transpiled_files.count == 2 * closure.count);
    expect(test_build_transpiled_files[closure.count - 1] == "src/main.jai");
    // Compilation receives the entry file's (fake) strip view, not the
    // original source path.
    entry_view := tprint("%1/target/transpile/%2/src/main.jai", root, fake_key("src/main.jai"));
    expect(test_compiled_entry == entry_view);
    expect(file_exists(entry_view));
    expect(test_compiled_plan.target.name == "beta" && test_compiled_plan.artifact_path == tprint("%1/target/beta.exe", root));
}

// The final gate before the compiler: a plan with an empty target name must
// never reach compile_artifact_plan (which would pass "-exe ''" through).
test "Build rejects a plan with an empty target name" {
    driver: Build_Driver;
    root := juice_root();
    plans := Artifact_Plan.[
        .{target = .{name = "", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    expect(!build_prepared_workspace(*driver, *prepared, fake_build_transpile, test_compile_artifact) && test_compile_count == 0);
}

test "Build fails fast on a compile failure" {
    driver: Build_Driver;
    root := juice_root();
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/alpha.exe", root)},
        .{target = .{name = "beta",  main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/beta.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    test_compile_success = false;
    expect(!build_prepared_workspace(*driver, *prepared, fake_build_transpile, test_compile_artifact));
    expect(test_compile_count == 1);
}

// ---------------------------------------------------------------------------
// Build transpile front（ticket 0021）：seam 测试以记录 fake 驱动生产编排，
// 落在真实临时 fixture 文件上。探针（生产代码）读取并词法扫描闭包；可注入
// 的转译步骤对 test-free 闭包完全不调用（零转译、零缓存），否则按依赖序每
// 闭包文件调用一次。
// ---------------------------------------------------------------------------

// Test-free closure: the transpile step is never called, the compile seam
// receives the original entry, and no transpile tree is created.
test "Build front: a test-free closure skips the transpile step" {
    root := tprint("%1/target/build-seam-clean", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"helper.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/helper.jai", "helper :: () -> s32 { return 1; }\n"));

    driver: Build_Driver;
    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    expect(build_prepared_workspace(*driver, *prepared, fake_build_transpile, fake_build_compile));
    expect(test_build_transpile_calls == 0);
    expect(test_build_compile_calls == 1);
    expect(test_build_compiled_entries[0] == to_forward_slashes(plan.target.source_path));
    // Zero cache: nothing under the transpile tree was created.
    expect(!file_exists(tprint("%1/target/transpile", root)));
}

// Closure with test blocks: every closure file is viewed all-or-nothing
// (dependency order, so the load rewrite embeds the child's view path), the
// entry becomes the entry file's view, and files outside the closure are
// never transpiled.
test "Build front: a test closure is viewed all-or-nothing with load rewrites" {
    root := tprint("%1/target/build-seam-view", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"math.jai\";\n\nmain :: () { print(\"hi\\n\"); }\n"));
    expect(build_seam_write(root, "src/math.jai", "add :: (a: s32, b: s32) -> s32 { return a + b; }\n\ntest \"addition\" {\n}\n"));
    expect(build_seam_write(root, "src/unloaded.jai", "test \"never viewed\" {\n}\n"));

    driver: Build_Driver;
    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    expect(build_prepared_workspace(*driver, *prepared, fake_build_transpile, fake_build_compile));

    // Transpile ran once per closure file, children first (Merkle chain):
    // math.jai before main.jai; unloaded.jai stays untouched.
    expect(test_build_transpile_calls == 2);
    expect(test_build_transpiled_files.count == 2);
    expect(test_build_transpiled_files[0] == "src/math.jai" && test_build_transpiled_files[1] == "src/main.jai");

    // The entry's load rewrite points at the child's fake view path.
    math_view := tprint("%1/target/transpile/%2/src/math.jai", root, fake_key("src/math.jai"));
    expect(test_build_transpiled_rewrites.count == 1);
    expect(test_build_transpiled_rewrites[0] == tprint("src/math.jai -> %1", math_view));

    // The fake views were written content-addressed; the compile seam
    // received the entry file's fake view exactly once.
    expect(test_build_compile_calls == 1);
    entry_view := tprint("%1/target/transpile/%2/src/main.jai", root, fake_key("src/main.jai"));
    expect(test_build_compiled_entries[0] == entry_view);
    main_view, ok := read_entire_file(entry_view);
    expect(ok && main_view == "// fake build view of src/main.jai\n");
    expect(file_exists(math_view));
}

// Transpile diagnostics fail the build before the compile seam, with the
// original file coordinates.
test "Build front: transpile diagnostics fail before compiling" {
    root := tprint("%1/target/build-seam-diag", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "test \"nested in proc\" { }\n\nproc :: () {\n    test \"bad\" { }\n}\n"));

    driver: Build_Driver;
    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    test_build_fake_diagnostic = "test block 仅允许文件顶层";
    expect(!build_prepared_workspace(*driver, *prepared, fake_build_transpile, fake_build_compile));
    expect(test_build_compile_calls == 0);
}

// A cycle in the literal in-package #load graph of a viewed closure cannot
// be rewritten and fails with the dedicated diagnostic (issue 0008).
test "Build front: a load cycle cannot be rewritten" {
    root := tprint("%1/target/build-seam-cycle", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"a.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/a.jai", "#load \"main.jai\";\n\ntest \"cycle\" { }\n"));

    driver: Build_Driver;
    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    expect(!build_prepared_workspace(*driver, *prepared, fake_build_transpile, fake_build_compile));
    expect(test_build_compile_calls == 0);
}

// ---------------------------------------------------------------------------
// Production probe: closure shape over real fixture files (no fakes).
// ---------------------------------------------------------------------------

// The closure is the entry's literal in-package #load reachability: nested
// literal targets are followed, non-literal and out-of-package targets are
// not. Files come back in DFS preorder, loads in statement order.
test "Build probe: only literal in-package loads form the closure" {
    root := tprint("%1/target/build-probe-package", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"a.jai\";\n#load \"sub/b.jai\";\n#load CONST_NAME;\n#load \"../../outside.jai\";\n"));
    expect(build_seam_write(root, "src/a.jai", "x :: 1;\n"));
    expect(build_seam_write(root, "src/sub/b.jai", "y :: 2;\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    closure, ok := probe_build_closure(*prepared, plan);
    expect(ok && closure.count == 3);
    expect(closure[0].file.rel_path == "src/main.jai");
    expect(closure[1].file.rel_path == "src/a.jai" && closure[2].file.rel_path == "src/sub/b.jai");
    expect(closure[0].loads.count == 2);
    expect(closure[0].loads[0] == "src/a.jai" && closure[0].loads[1] == "src/sub/b.jai");
    for file: closure {
        expect(!file.has_tests);
    }
}

test "Build probe: test blocks are detected, pass-through shapes are not" {
    root := tprint("%1/target/build-probe-tests", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    // A top-level anchor, a nested anchor (rejected with a diagnostic when
    // viewed), and a non-statement `test` token that passes through.
    expect(build_seam_write(root, "src/has.jai", "test \"top\" { }\n"));
    expect(build_seam_write(root, "src/nested.jai", "proc :: () {\n    test \"bad\" { }\n}\n"));
    expect(build_seam_write(root, "src/pass.jai", "if test { }\n\ntest := 5;\n"));

    plan := build_seam_plan(root, "src/has.jai");
    prepared := build_seam_prepared(root, plan);
    closure, ok := probe_build_closure(*prepared, plan);
    expect(ok && closure.count == 1 && closure[0].has_tests);

    plan2 := build_seam_plan(root, "src/nested.jai");
    closure2, ok2 := probe_build_closure(*prepared, plan2);
    expect(ok2 && closure2.count == 1 && closure2[0].has_tests);

    plan3 := build_seam_plan(root, "src/pass.jai");
    closure3, ok3 := probe_build_closure(*prepared, plan3);
    expect(ok3 && closure3.count == 1 && !closure3[0].has_tests);
}

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
// E2E child scenarios: real juice.exe on fixture packages（juice_exe、
// run_juice_child、expect_exit、child_output_contains 见
// tests/test_support.jai）。
// ---------------------------------------------------------------------------

// A BIN package with embedded tests builds through strip views: tests are
// stripped, the in-package load is rewritten to the child's view, the views
// match the pure transpile contract byte for byte, and the artifact keeps
// its semantics (prints the same greeting as the original program).
test "E2E: embedded-tests package builds through strip views" {
    fixture_root := tprint("%1/tests/data/test-package", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));

    result, output, _ := run_juice_child("test-package", "build");
    expect(expect_exit("build", result, 0, "build child"));
    expect(child_output_contains("build", output, "[juice Build] Compiling Target 'test-package' (src/main.jai) -> target/..."));

    // The artifact exists and behaves like the original program.
    artifact := tprint("%1/target/test-package.exe", fixture_root);
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("artifact", run_result, 0, "build child"));
    expect(child_output_contains("artifact", run_output, "hello from test-package"));

    // Both closure files have strip views at their pure-contract paths.
    transpile_dir := tprint("%1/target/transpile", fixture_root);
    math_source, ok := read_entire_file(tprint("%1/src/math.jai", fixture_root));
    expect(ok);
    math_key := transpile_view_key("src/math.jai", math_source, .STRIP, Load_Target.[], JUICE_VERSION);
    math_view := transpile_view_path(transpile_dir, math_key, "src/math.jai");
    expect(path_exists_as_regular_file(math_view));
    math_result := transpile_source(math_source, .{mode = .STRIP, path = "src/math.jai"});
    math_view_text, ok2 := read_entire_file(math_view);
    expect(ok2 && math_view_text == math_result.view);

    main_source, ok3 := read_entire_file(tprint("%1/src/main.jai", fixture_root));
    expect(ok3);
    main_key := transpile_view_key("src/main.jai", main_source, .STRIP, Load_Target.[.{from = "src/math.jai", to = math_view}], JUICE_VERSION);
    main_view := transpile_view_path(transpile_dir, main_key, "src/main.jai");
    expect(path_exists_as_regular_file(main_view));
    main_result := transpile_source(main_source, .{mode = .STRIP, path = "src/main.jai", load_targets = Load_Target.[.{from = "src/math.jai", to = math_view}]});
    main_view_text, ok4 := read_entire_file(main_view);
    expect(ok4 && main_view_text == main_result.view);
    // Tests were stripped and the load rewritten to the child view.
    expect(find_index_from_left(main_view_text, "// juice: test stripped") >= 0);
    expect(find_index_from_left(main_view_text, math_view) >= 0);
}

// A test-free package builds without any transpile: no views, no cache
// tree, the artifact comes straight from the original entry.
test "E2E: test-free package builds with zero transpile" {
    fixture_root := tprint("%1/tests/data/build-empty", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));

    result, output, _ := run_juice_child("build-empty", "build");
    expect(expect_exit("build-empty", result, 0, "build child"));
    expect(file_exists(tprint("%1/target/build-empty.exe", fixture_root)));
    expect(!file_exists(tprint("%1/target/transpile", fixture_root)));
}
