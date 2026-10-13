// ---------------------------------------------------------------------------
// Test support（测试支撑代码，组织决议 0027、规格 0032；2026-10 用户修订：
// 纯测试支撑代码不驻 src/，由 src/test_support.jai 移至 tests/test_support.jai）
// ——测试程序共享声明的唯一允许位置。收录旧 tests/ 测试文件顶层迁移而来的
// 全部共享声明——helper、recording fake 与记录全局、GOLDEN_CASES 等测试
// 常量，供 src 内联 test block（票 0034）与 Testing 自测共同引用（Test
// discovery 全包扫描收录本文件进测试程序，声明程序级共享）。
//
// 纪律：测试共享声明只允许位于本文件；其他文件（尤其 src/）顶层不放测试
// 专用声明（src 文件的顶层声明经 STRIP 会保留进发布产物）；modules/
// Testing.jai 顶层不驻测试 helper。
//
// 本文件不被 src/main.jai #load → 不在 Build 入口闭包 → 不转译、不编译、
// 不进发布产物。测试程序路径下本文件 test-free，EXPAND 视图恒等输出。
// 扫描排除集（root 级 target/、tests/data/、modules/）不含 tests/ 本身，
// 本文件被全包扫描正常收录。
//
// 本文件含 Testing 模块自测支撑段，以机器标记注释行框定（标记名见下段
// 首尾，开头带 `//` 前缀；注意：本处与任何其他注释不得含该标记行的完整
// 文本——生成器按子串定位标记，误命中会切错段）。src/commands/test.jai 的
// testing_module_support_block 按标记整段切取进模块编译视图。标记是切段的
// 稳定锚点：改段内注释不再破坏切段；移动段内声明时同步移动标记。
// ---------------------------------------------------------------------------

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
#import "Juice";

// ===========================================================================
// Testing 模块自测支撑段（票 0033）：模块编译视图以本段 + 生成器前置的
// #scope_file 与文件级 import 构成。模块是密封作用域（how_to 151），自测块
// 引用的声明必须驻模块自身作用域；本段内的全部声明（记录全局、child 场景
// helper、自足 juice_root）必须位于两个机器标记之间，缺标记或声明移出段外
// 会使模块自测编译失败。child 场景 helper 亦供本文件之外的测试块共用
// （test support 程序级共享）。
// ===========================================================================

// __testing_module_support_begin__

// ---------------------------------------------------------------------------
// 路径基准（0027 决议）：所有 fixture 与 scratch 路径共同派生的包根。基准
// 是 juice 的调用 cwd——juice 于 package root 运行，workspace discovery 由
// 进程 cwd 推导 root，生成的测试 metaprogram 将其带进构建选项：
// intermediate_path = <root>/target。旧实现基于测试文件位置（测试程序入口
// target/transpile 向上两级）推导仓库根，随迁移弃用：它绑定生成文件的
// 布局，与共享声明的组织无关。
//
// 自足形态（票 0033）：本段被整体切取进 Testing 模块编译视图——模块是密封
// 作用域，看不到 src/path_safety 的 lexical_absolute_path 声明，故此处不
// 调用它。测试 metaprogram 以绝对 target 目录设置 intermediate_path
// （"/" 分隔），剥掉尾部分隔符即为包根，无需路径归一。
// ---------------------------------------------------------------------------
juice_root :: () -> string {
    options := get_build_options();
    // path_strip_filename 保留尾部分隔符（String 模块语义）；剥掉后为绝对
    // 路径，与 src/commands/test.jai 的 scan_entry_parent 同姿势。
    root := path_strip_filename(options.intermediate_path);
    while root.count > 0 && (root[root.count - 1] == #char "/" || root[root.count - 1] == #char "\\") root.count -= 1;
    return root;
}

// Testing 模块自测的记录全局（旧 tests/ 测试文件顶层声明迁移，票 0032）。
g_reached := false;
g_first_reached := false;
g_second_reached := false;
g_defer_ran := false;

// The tests below drive Testing's run()/finish() directly, which resets the
// global register. Each test drains leftover failures at its start into the
// accumulator so the final latch test can still fail the suite — otherwise a
// failure registered before a finish() call would be silently masked (in the
// old per-executable harness each process was isolated). The scenario's own
// counts are checked directly by the assertions instead.
testing_module_failures: s64 = 0;

// Absolute path of juice.exe in the repository's target directory. The
// package root comes from juice_root(): the test program executes at compile
// time in the jai compiler child of juice, where the process working
// directory is the entry file's directory (target/transpile), not the
// invocation cwd. 历史上按来源前缀存在四份同体拷贝（juice_exe/
// test_command_juice_exe/testing_juice_exe/tp_juice_exe），已合并为本一份。
juice_exe :: () -> string {
    return tprint("%1/target/juice.exe", juice_root());
}

// Child 场景：真实 juice.exe 在 fixture package 上跑 `juice test`。
// fixture_base 区分 fixture 树（commands 场景 tests/data/、转译 run matrix
// tests/data/transpile/run/、Testing 自测 tests/data/testing-child/）。
// 历史上 tp_run_juice_test 与本实现同体（仅 fixture 基目录不同），已合并。
run_juice_test :: (fixture: string, pattern := "", fixture_base := "tests/data/") -> Process_Result, string, string {
    juice := juice_exe();
    fixture_abs := tprint("%1/%2%3", juice_root(), fixture_base, fixture);
    args: [..] string;
    array_add(*args, juice);
    array_add(*args, "test");
    if pattern != "" array_add(*args, pattern);
    result, output, errors, _ := run_command(..args, working_directory = fixture_abs, capture_and_return_output = true);
    return result, output, errors;
}

testing_child_run :: (scenario: string) -> Process_Result, string, string {
    result, output, errors := run_juice_test(scenario, "", "tests/data/testing-child/");
    return result, output, errors;
}

// 退出码检查（child 场景共用）：历史上按来源前缀存在四份同体拷贝
// （expect_child_exit/expect_exit/testing_expect_exit/tp_expect_exit），
// 差异仅在失败诊断前缀；合并为一份后以前缀参数保留各自的诊断文本。
expect_exit :: (name: string, result: Process_Result, want: s32, tag := "child") -> bool {
    if result.type == .EXITED && result.exit_code == want return true;
    print("[%1 %2] exit result %3/%4, want %5\n", tag, name, result.type, result.exit_code, want);
    return false;
}

// Normalize CRLF to LF so expected blocks are compared line by line
// regardless of the child process's native line endings. 历史上按来源前缀
// 存在三份逐字拷贝（normalize_crlf/testing_normalize_crlf/
// tp_normalize_crlf），已合并为本一份。
normalize_crlf :: (s: string) -> string {
    has_cr := false;
    for ch: s {
        if ch == #char "\r" {
            has_cr = true;
            break;
        }
    }
    if !has_cr return s;
    builder: String_Builder;
    cursor := 0;
    i := 0;
    while i < s.count {
        if s[i] == #char "\r" {
            print_to_builder(*builder, "%", slice(s, cursor, i - cursor));
            print_to_builder(*builder, "\n");
            if i + 1 < s.count && s[i+1] == #char "\n" i += 1;
            cursor = i + 1;
        }
        i += 1;
    }
    if cursor < s.count print_to_builder(*builder, "%", slice(s, cursor, s.count - cursor));
    return builder_to_string(*builder);
}

// 输出断言（child 场景共用）：逐 needle 检查出现/不出现（want）。历史上按
// 来源前缀存在三份同体拷贝（output_matches/testing_output_matches/
// tp_output_matches），差异仅在失败诊断前缀；合并后以前缀参数保留。
output_matches :: (name: string, output: string, needles: [] string, want := true, tag := "child") -> bool {
    normalized := normalize_crlf(output);
    for needle: needles {
        found := find_index_from_left(normalized, needle) >= 0;
        if found != want {
            print("[%1 %2] output %3 '%4'\n", tag, name, ifx found then "unexpectedly contains" else "missing", needle);
            print("  output was:\n%\n", output);
            return false;
        }
    }
    return true;
}

// 1-based line/column of the first occurrence of `needle` in `file`; 0,0 if
// the source cannot be read or the needle is missing. Used to build expected
// failure lines without hardcoding line numbers. 历史上 testing_line_col 与
// 本实现逐字相同，已合并。
fixture_line_col :: (file: string, needle: string) -> (line: s64, col: s64) {
    source, ok := read_entire_file(file);
    if !ok return 0, 0;
    index := find_index_from_left(source, needle);
    if index < 0 return 0, 0;
    line := 1;
    line_start := 0;
    for i: 0..index-1 {
        if source[i] == #char "\n" {
            line += 1;
            line_start = i + 1;
        }
    }
    return line, index - line_start + 1;
}

// __testing_module_support_end__

// ===========================================================================
// 旧 tests/ 测试文件顶层声明迁移（票 0032）——run/clean/compile 记录 fake、
// build transpile seam 与 E2E child 场景 helper
// ===========================================================================

test_launch_count: s64;
test_launched_plan: Artifact_Plan;
test_launched_root: string;
test_launch_success: bool;

test_launch_artifact :: (plan: Artifact_Plan, package_root: string) -> bool {
    test_launch_count += 1;
    test_launched_plan = plan;
    test_launched_root = package_root;
    return test_launch_success;
}

test_clean_validated: [..] string;
test_clean_deleted: [..] string;
test_clean_invalid_path: string;
test_clean_failed_delete: string;
test_clean_expected_validations: s64;
test_clean_deleted_too_early: bool;

reset_clean_test :: (expected_validations: s64) {
    array_reset(*test_clean_validated);
    array_reset(*test_clean_deleted);
    test_clean_invalid_path = "";
    test_clean_failed_delete = "";
    test_clean_expected_validations = expected_validations;
    test_clean_deleted_too_early = false;
}

test_validate_clean_path :: (path: string) -> bool {
    array_add(*test_clean_validated, path);
    return path != test_clean_invalid_path;
}

test_delete_clean_path :: (path: string) -> bool {
    if test_clean_validated.count != test_clean_expected_validations test_clean_deleted_too_early = true;
    array_add(*test_clean_deleted, path);
    return path != test_clean_failed_delete;
}

test_compile_count: s64;
test_compiled_plan: Artifact_Plan;
test_compiled_driver_root: string;
test_compiled_entry: string;
test_compile_success: bool;

test_compile_artifact :: (root_dir: string, plan: Artifact_Plan, entry: string) -> bool {
    test_compile_count += 1;
    test_compiled_plan = plan;
    test_compiled_driver_root = root_dir;
    test_compiled_entry = entry;
    return test_compile_success;
}

// Fake transpile step: records every call and returns a canned view with a
// flat (collision-free by construction) key. The orchestration feeds the key
// through the pure path function; the fake only fills in content. build 与
// test 两个 seam 的 fake 共用同一键函数（历史上 build_fake_key/fake_key
// 两份同体，仅前缀不同，已合并）——fake 键只在 seam 内部流通，测试块以
// 同一函数重建期望路径。
fake_key :: (rel: string) -> string {
    result := copy_string(rel);
    for i: 0..result.count-1 {
        if result[i] == #char "/" result[i] = #char "_";
    }
    return tprint("key-%1", result);
}

test_build_transpile_calls: s64;
test_build_transpiled_files: [..] string;
test_build_transpiled_rewrites: [..] string;
test_build_fake_diagnostic: string;

fake_build_transpile :: (file: Build_Source_File, load_targets: [] Load_Target) -> Build_File_Output {
    test_build_transpile_calls += 1;
    array_add(*test_build_transpiled_files, file.rel_path);
    for target: load_targets {
        array_add(*test_build_transpiled_rewrites, tprint("%1 -> %2", target.from, target.to));
    }
    output: Build_File_Output;
    output.view = tprint("// fake build view of %1\n", file.rel_path);
    output.key = fake_key(file.rel_path);
    if test_build_fake_diagnostic != "" {
        array_add(*output.diagnostics, .{line = 2, column = 1, message = test_build_fake_diagnostic});
    }
    return output;
}

test_build_compile_calls: s64;
test_build_compiled_entries: [..] string;
test_build_compile_success: bool;

fake_build_compile :: (root_dir: string, plan: Artifact_Plan, entry: string) -> bool {
    test_build_compile_calls += 1;
    array_add(*test_build_compiled_entries, entry);
    return test_build_compile_success;
}

reset_build_seam :: () {
    test_compile_count = 0;
    test_compile_success = true;
    test_build_transpile_calls = 0;
    array_reset(*test_build_transpiled_files);
    array_reset(*test_build_transpiled_rewrites);
    test_build_fake_diagnostic = "";
    test_build_compile_calls = 0;
    array_reset(*test_build_compiled_entries);
    test_build_compile_success = true;
}

// A prepared workspace over a real temp fixture root: the transpile front
// probes real files even in seam tests (same posture as the revalidation
// gate running over the real filesystem).
build_seam_plan :: (root: string, main_file: string) -> Artifact_Plan {
    plan: Artifact_Plan;
    plan.target = .{name = "app", main_file = main_file, source_path = tprint("%1/%2", root, main_file)};
    plan.target_dir = tprint("%1/target", root);
    plan.artifact_path = tprint("%1/target/app.exe", root);
    return plan;
}

build_seam_prepared :: (root: string, plan: Artifact_Plan) -> Prepared_Workspace {
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    // The plan must live in a heap-backed array: a static literal here would
    // leave the slice pointing at this frame's stack.
    plans: [..] Artifact_Plan;
    array_add(*plans, plan);
    prepared.artifact_plans = plans;
    return prepared;
}

build_seam_write :: (root: string, rel: string, content: string) -> bool {
    path := tprint("%1/%2", root, rel);
    if !make_directory_if_it_does_not_exist(path_strip_filename(path), recursive = true) return false;
    return write_entire_file(path, content);
}

run_juice_child :: (fixture: string, command: string, target := "") -> (Process_Result, string, string) {
    juice := juice_exe();
    fixture_abs := tprint("%1/tests/data/%2", juice_root(), fixture);
    args: [..] string;
    array_add(*args, juice);
    array_add(*args, command);
    if target != "" array_add(*args, target);
    result, output, errors, _ := run_command(..args, working_directory = fixture_abs, capture_and_return_output = true);
    return result, output, errors;
}

child_output_contains :: (name: string, output: string, needle: string) -> bool {
    if find_index_from_left(output, needle) >= 0 return true;
    print("[build child %1] output missing '%2'\n  output was:\n%\n", name, needle, output);
    return false;
}

// ===========================================================================
// 旧 tests/ 测试文件顶层声明迁移（票 0032）——记录 handler 与测试 registry
// ===========================================================================

test_a_calls: s64 = 0;
test_b_calls: s64 = 0;
test_c_calls: s64 = 0;
test_d_calls: s64 = 0;
test_fail_calls: s64 = 0;

reset_dispatch_counters :: () {
    test_a_calls = 0;
    test_b_calls = 0;
    test_c_calls = 0;
    test_d_calls = 0;
    test_fail_calls = 0;
}

test_handler_a :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_a_calls += 1;
    return true;
}

test_handler_b :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_b_calls += 1;
    return true;
}

test_handler_c :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_c_calls += 1;
    return true;
}

test_handler_d :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_d_calls += 1;
    return true;
}

test_handler_fail :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_fail_calls += 1;
    return false;
}

strict_arguments_are_invalid :: (arguments: [] string) -> bool {
    return false;
}

TEST_REGISTRY_SIMPLE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.[], handler = test_handler_b},
];

TEST_REGISTRY_DUPLICATE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], handler = test_handler_a},
    .{name = "a", description = "Command A Duplicate", usage = "test a", prerequisites = string.[], handler = test_handler_b},
];

TEST_REGISTRY_MISSING_PREREQ :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.["nonexistent"], handler = test_handler_a},
];

TEST_REGISTRY_CYCLE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.["b"], handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.["a"], handler = test_handler_b},
];

TEST_REGISTRY_DIAMOND :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.["a"], handler = test_handler_b},
    .{name = "c", description = "Command C", usage = "test c", prerequisites = string.["a"], handler = test_handler_c},
    .{name = "d", description = "Command D", usage = "test d", prerequisites = string.["b", "c"], handler = test_handler_d},
];

TEST_REGISTRY_FAILURE :: Command.[
    .{name = "failing", description = "Failing Command", usage = "test failing", prerequisites = string.[], handler = test_handler_fail},
    .{name = "target", description = "Target Command", usage = "test target", prerequisites = string.["failing"], handler = test_handler_b},
];

TEST_REGISTRY_ARGUMENTS :: Command.[
    .{name = "sideeffect", description = "Side Effect Command", usage = "test sideeffect", prerequisites = string.[], handler = test_handler_a},
    .{name = "strict", description = "Strict Command", usage = "test strict", prerequisites = string.["sideeffect"], validate_arguments = strict_arguments_are_invalid, handler = test_handler_b},
];

// ===========================================================================
// 旧 tests/ 测试文件顶层声明迁移（票 0032）——discovery/resolution/dependency
// 记录 fake 与 import shim helper
// ===========================================================================

test_discovery_attempts: s64 = 0;
test_fake_discovery_ok: bool = false;
test_fake_discovery: Workspace_Discovery;

test_fake_discover :: (root_dir: string, cache_dir: string) -> Workspace_Discovery, bool {
    test_discovery_attempts += 1;
    return test_fake_discovery, test_fake_discovery_ok;
}

test_plan_resolution_success: bool = false;
test_resolved_plans: [] Artifact_Plan;
test_dependency_attempts: s64 = 0;
test_dependency_ok: bool = false;
test_dependency_snapshot: [] Package;

test_fake_resolve :: (pkg: Package) -> Artifact_Plan_Result {
    if !test_plan_resolution_success return .{success = false, error_message = copy_string("resolution failure")};
    return .{success = true, plans = test_resolved_plans};
}

test_fake_prepare_dependencies :: (root_dir: string, cache_dir: string, member_packages: [] Package) -> bool {
    test_dependency_attempts += 1;
    test_dependency_snapshot = member_packages;
    return test_dependency_ok;
}

reset_preparation_test :: () {
    test_discovery_attempts = 0;
    test_fake_discovery_ok = false;
    test_fake_discovery = .{};
    test_plan_resolution_success = false;
    test_resolved_plans = Artifact_Plan.[];
    test_dependency_attempts = 0;
    test_dependency_ok = false;
    test_dependency_snapshot = Package.[];
}

test_fetched_dependency_names: [..] string;
test_fetch_result: bool = false;
test_linked_member_names: [..] string;
test_link_result: bool = false;

test_fake_fetch :: (root_dir: string, cache_dir: string, dep: Dependency) -> bool {
    array_add(*test_fetched_dependency_names, copy_string(dep.name));
    return test_fetch_result;
}

test_fake_link_member :: (root_dir: string, member: Package) -> bool {
    array_add(*test_linked_member_names, copy_string(member.name));
    return test_link_result;
}

// Consumers resolve "#import <name>" through a generated shim in the
// dependency directory; the shim loads the dependency's real entry by path,
// so any source directory name and any of the three layouts work.
shim_content_for :: (packages_dir: string, name: string) -> string, bool {
    shim_path := tprint("%1/%2.jai", packages_dir, name);
    if !file_exists(shim_path) return "", false;
    content, ok := read_entire_file(shim_path);
    return content, ok;
}

// ===========================================================================
// 旧 tests/ 测试文件顶层声明迁移（票 0032）——LIB fixture package 构造
// ===========================================================================

// A LIB package is an import source: it declares no executable targets and
// resolves to zero plans once its module.jai import entry is verified.
library_fixture_package :: () -> Package {
    pkg: Package;
    pkg.name    = "libdemo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data/lib-module", juice_root());
    pkg.type    = .LIB;
    return pkg;
}

// ===========================================================================
// 旧 tests/ 测试文件顶层声明迁移（票 0032）——test 编排 seam 的记录 fake、
// 缓存树扫描 helper
// ===========================================================================

test_transpiled_files: [..] Test_Source_File;
test_transpiled_numbers: [..] s64;
test_fake_tests_per_file: s64 = 1;
test_fake_diagnostic: string = "";

// Each file yields test_count tests named "<rel> test <n>" plus, optionally,
// one canned diagnostic (for the rejection path). The key is canned too (flat
// by construction): the orchestration only feeds it through the pure path
// function.
fake_transpile :: (file: Test_Source_File, next_test_number: s64) -> Test_File_Output {
    array_add(*test_transpiled_files, file);
    array_add(*test_transpiled_numbers, next_test_number);
    output: Test_File_Output;
    output.view = tprint("// fake view of %1\n", file.rel_path);
    output.key = fake_key(file.rel_path);
    for i: 0..test_fake_tests_per_file-1 {
        entry: Test_Entry;
        entry.name = tprint("%1 test %2", file.rel_path, i);
        entry.number = next_test_number + i;
        array_add(*output.tests, entry);
    }
    if test_fake_diagnostic != "" {
        array_add(*output.diagnostics, .{line = 3, column = 1, message = test_fake_diagnostic});
    }
    return output;
}

test_compile_calls: s64;
test_compile_transpile_dir: string;
test_compile_driver_path: string;
test_compile_metaprogram_path: string;
test_seam_compile_success: bool;

fake_compile :: (transpile_dir: string, driver_path: string, metaprogram_path: string) -> bool {
    test_compile_calls += 1;
    test_compile_transpile_dir = transpile_dir;
    test_compile_driver_path = driver_path;
    test_compile_metaprogram_path = metaprogram_path;
    return test_seam_compile_success;
}

seam_files :: () -> [] Test_Source_File {
    return Test_Source_File.[
        .{rel_path = "src/a.jai", abs_path = "seam-root/src/a.jai"},
        .{rel_path = "src/b.jai", abs_path = "seam-root/src/b.jai"},
    ];
}

seam_prepared :: (root := "") -> Prepared_Workspace {
    prepared: Prepared_Workspace;
    seam_root := root;
    if seam_root == "" seam_root = tprint("%1/target/seam-root", juice_root());
    prepared.discovery.root_dir = seam_root;
    return prepared;
}

reset_seam_test :: () {
    delete_directory_full(tprint("%1/target/seam-root", juice_root()));
    array_reset(*test_transpiled_files);
    array_reset(*test_transpiled_numbers);
    test_fake_tests_per_file = 1;
    test_fake_diagnostic = "";
    test_compile_calls = 0;
    test_compile_transpile_dir = "";
    test_compile_driver_path = "";
    test_compile_metaprogram_path = "";
    test_seam_compile_success = true;
}

file_contains :: (path: string, needle: string) -> bool {
    content, ok := read_entire_file(path);
    if !ok return false;
    return find_index_from_left(content, needle) >= 0;
}

// Creates a directory/file link with mklink. Returns false when the machine
// refuses link creation (needs developer mode or elevation).
make_test_link :: (link: string, target: string, directory: bool, junction: bool) -> bool {
    args: [..] string;
    array_add(*args, "cmd");
    array_add(*args, "/c");
    array_add(*args, "mklink");
    if junction {
        array_add(*args, "/J");
    } else if directory {
        array_add(*args, "/D");
    }
    // Backslashes throughout: cmd's builtin mklink parses forward-slash
    // path segments as option switches (same reason rmdir calls do).
    array_add(*args, path_backslashes(link));
    array_add(*args, path_backslashes(target));
    result := run_command(..args);
    return result.exit_code == 0;
}

// 目录扫描（转译树与 golden case 目录共用）：直接子项按文件/目录收集。
// 历史上 Cache_Dir_Scan/Case_Dir_Scan 两对同形结构与 visitor 各自一份，
// 已合并。
Dir_Scan :: struct {
    dirs:  [..] string;
    files: [..] string;
}

dir_scan_visitor :: (info: *File_Visit_Info, scan: *Dir_Scan) {
    if info.is_directory {
        array_add(*scan.dirs, copy_string(info.short_name));
    } else {
        array_add(*scan.files, copy_string(info.short_name));
    }
}

dir_scan_entries :: (dir: string) -> (Dir_Scan, bool) {
    scan: Dir_Scan;
    visited := visit_files(dir, false, *scan, dir_scan_visitor, visit_files = true, visit_directories = true);
    return scan, visited;
}

// 字节序字典比较（strcmp 语义）与插入排序。历史上 sort_strings（基于
// String.compare）与 tp_sort_strings/tp_string_less（转译测试）两份同语义
// 实现并存，已合并为显式字节序比较的一份。
string_less :: (a: string, b: string) -> bool {
    n := min(a.count, b.count);
    for i: 0..n-1 {
        if a[i] != b[i] return a[i] < b[i];
    }
    return a.count < b.count;
}

sort_strings :: (items: [] string) {
    for i: 1..items.count-1 {
        if i >= items.count break;
        key := items[i];
        j := i - 1;
        while j >= 0 && string_less(key, items[j]) {
            items[j+1] = items[j];
            j -= 1;
        }
        items[j+1] = key;
    }
}

// ===========================================================================
// 旧 tests/ 测试文件顶层声明迁移（票 0032）——golden/negative harness 与
// compile-and-run matrix helper
// ===========================================================================

// ---------------------------------------------------------------------------
// Golden baselines (docs/transpiled-output-formatting.md §4). Every case dir
// holds one or more input *.jai files plus the expected view files
// (<name>.view.jai); negative cases hold the expected rendered diagnostics
// (diagnostic.txt). Rewrite the baselines by running `juice test` with the
// JUICE_UPDATE_GOLDEN environment variable set to any non-empty value (CI
// never sets it).
// ---------------------------------------------------------------------------

GOLDEN_CASES :: string.[
    "expand-basic",
    "loads",
    "immunity",
    "one-line",
    "test-free",
    "strip-basic",
    "multi",
];

NEGATIVE_CASES :: string.[
    "nested-in-proc",
    "nested-in-struct",
    "multiline-head",
    "shared-load-before",
    "shared-load-after",
    "strip-trailing",
    "unterminated",
];

// (GetEnvironmentVariableA comes from src/xdg.jai, loaded as a test view.)

wants_update :: () -> bool {
    #if OS == .WINDOWS {
        buffer: [512] u8;
        result := GetEnvironmentVariableA("JUICE_UPDATE_GOLDEN", buffer.data, 512);
        if result > 0 && result < 512 return true;
    }
    return false;
}

expand_ctx :: (path := "src/foo.jai", next := 1) -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = .EXPAND;
    ctx.path = path;
    ctx.next_test_number = next;
    return ctx;
}

strip_ctx :: (path := "src/foo.jai", targets: [] Load_Target) -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = path;
    ctx.next_test_number = 1;
    ctx.load_targets = targets;
    return ctx;
}

count_lines :: (s: string) -> s64 {
    n := 1;
    for ch: s {
        if ch == #char "\n" n += 1;
    }
    return n;
}

Case_Config :: struct {
    mode:        Transpile_Mode = .EXPAND;
    path:        string;
    next_number: s64 = 1;
    load_targets: [..] Load_Target;
}

read_case_config :: (dir: string) -> Case_Config {
    config: Case_Config;
    content, ok := read_entire_file(tprint("%1/config.txt", dir), log_errors = false);
    if !ok return config;
    lines := split(content, "\n");
    for line: lines {
        trimmed := trim(line);
        if trimmed == "" || starts_with(trimmed, "#") continue;
        eq := -1;
        for i: 0..trimmed.count-1 {
            if trimmed[i] == #char "=" {
                eq = i;
                break;
            }
        }
        if eq <= 0 continue;
        key := slice(trimmed, 0, eq);
        value := slice(trimmed, eq + 1, trimmed.count - eq - 1);
        if key == "mode" {
            if value == "strip" config.mode = .STRIP;
        } else if key == "path" {
            config.path = copy_string(value);
        } else if key == "next_number" {
            number, parsed, _ := string_to_int(value);
            if parsed config.next_number = number;
        } else if key == "load_target" {
            eq2 := -1;
            for i: 0..value.count-1 {
                if value[i] == #char "=" {
                    eq2 = i;
                    break;
                }
            }
            if eq2 > 0 {
                array_add(*config.load_targets, .{
                    from = copy_string(slice(value, 0, eq2)),
                    to = copy_string(slice(value, eq2 + 1, value.count - eq2 - 1)),
                });
            }
        }
    }
    return config;
}

// A case directory's input files in production scan order (issue 0003,
// ticket 0019): within each directory, files first (lexicographic by name),
// then subdirectories (lexicographic), recursing. The driver golden derives
// its view list, mapping table and test numbering from this exact order.
collect_case_files :: (dir: string) -> [..] string {
    files: [..] string;
    collect_case_files_rec(dir, "", *files);
    return files;
}

collect_case_files_rec :: (dir: string, rel_prefix: string, files: *[..] string) {
    scan, visited := dir_scan_entries(dir);
    if !visited return;
    sort_strings(scan.files);
    sort_strings(scan.dirs);
    for name: scan.files {
        // driver.jai / first.jai are the case's own expected products,
        // never inputs.
        if ends_with(name, ".jai") && !ends_with(name, ".view.jai") && name != "driver.jai" && name != "first.jai" {
            array_add(files, tprint("%1%2", rel_prefix, name));
        }
    }
    for name: scan.dirs {
        if name.count > 0 && name[0] == #char "." continue;
        collect_case_files_rec(tprint("%1/%2", dir, name), tprint("%1%2/", rel_prefix, name), files);
    }
}

// The package root the generated products refer to. Expected files spell it
// as the <abs> placeholder (docs/transpiled-output-formatting.md §4.2).
golden_root :: () -> string {
    return juice_root();
}

// Replace every occurrence of the absolute root prefix with "<abs>", so the
// generated driver/metaprogram text compares byte for byte against the
// machine-independent expected files.
normalize_golden_abs :: (text: string) -> string {
    root := golden_root();
    result := text;
    while true {
        index := find_index_from_left(result, root);
        if index < 0 break;
        result = tprint("%1<abs>%2", slice(result, 0, index), slice(result, index + root.count, result.count - index - root.count));
    }
    return result;
}

compare_or_update :: (expected_path: string, actual: string, update: bool) -> bool {
    if update {
        ok := write_entire_file(expected_path, actual);
        print("[GOLDEN UPDATE] wrote %\n", expected_path);
        return ok;
    }
    expected, ok := read_entire_file(expected_path);
    if !ok {
        print("[GOLDEN FAIL] %: expected file missing\n", expected_path);
        return false;
    }
    if expected == actual {
        print("[GOLDEN PASS] %\n", expected_path);
        return true;
    }
    print("[GOLDEN FAIL] % (expected % bytes, actual % bytes)\n", expected_path, expected.count, actual.count);
    first_diff := 0;
    while first_diff < expected.count && first_diff < actual.count && expected[first_diff] == actual[first_diff] first_diff += 1;
    from := max(first_diff - 30, 0);
    print("  expected: ...%...\n", slice(expected, from, min(90, expected.count - from)));
    print("  actual:   ...%...\n", slice(actual, from, min(90, actual.count - from)));
    return false;
}

case_context :: (config: Case_Config, case_name: string, file: string) -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = config.mode;
    ctx.path = ifx config.path != "" then config.path else tprint("%1/%2", case_name, file);
    ctx.next_test_number = config.next_number;
    ctx.load_targets = config.load_targets;
    return ctx;
}

run_golden_cases :: (update: bool) -> bool {
    all_ok := true;
    for case_name: GOLDEN_CASES {
        dir := tprint("%1/tests/data/transpile/golden/%2", juice_root(), case_name);
        config := read_case_config(dir);
        files := collect_case_files(dir);
        if files.count == 0 {
            print("[GOLDEN FAIL] %1: no input files\n", dir);
            all_ok = false;
            continue;
        }
        next := config.next_number;
        // Driver inputs accumulated in enumeration order: every file exactly
        // once, its case-relative path, and the content-addressed test-mode
        // view path (the driver is a test-program product; the key derives
        // from the same source the view was generated from).
        driver_files: [..] Test_Source_File;
        driver_view_paths: [..] string;
        matches: [..] Test_Entry;
        for file: files {
            source, ok := read_entire_file(tprint("%1/%2", dir, file));
            if !ok {
                print("[GOLDEN FAIL] %1/%2: cannot read input\n", dir, file);
                all_ok = false;
                continue;
            }
            ctx := case_context(config, case_name, file);
            ctx.next_test_number = next;
            result := transpile_source(source, ctx);
            if result.diagnostics.count > 0 {
                for d: result.diagnostics {
                    print("[GOLDEN FAIL] %1/%2: diagnostic %3:%4,%5: %6\n", dir, file, ctx.path, d.line, d.column, d.message);
                }
                all_ok = false;
                continue;
            }
            next += result.tests.count;
            if !compare_or_update(tprint("%1/%2.view.jai", dir, file), result.view, update) all_ok = false;

            key := transpile_view_key(ctx.path, source, .EXPAND, Load_Target.[], JUICE_VERSION);
            array_add(*driver_view_paths, tprint("%1/target/transpile/%2/%3", golden_root(), key, ctx.path));
            file_rec: Test_Source_File;
            file_rec.rel_path = ctx.path;
            array_add(*driver_files, file_rec);
            for entry: result.tests array_add(*matches, entry);
        }
        // Every case locks the generated driver and metaprogram too
        // (docs/transpiled-output-formatting.md §4.1); absolute paths are
        // normalized to the <abs> placeholder before comparing.
        driver_text := generate_test_driver(driver_files, driver_view_paths, matches);
        if !compare_or_update(tprint("%1/driver.jai", dir), normalize_golden_abs(driver_text), update) all_ok = false;
        // 共享 Metaprogram generator 的测试形状（票 0036）：绝对路径经
        // <abs> 占位符归一后与期望文件逐字节对比——字节一致不变量由
        // golden 夹具锁定。
        metaprogram: Compiler_Metaprogram_Options;
        metaprogram.workspace_name    = "Juice Test Program";
        metaprogram.no_output         = true;
        metaprogram.intermediate_path = tprint("%1/target", golden_root());
        metaprogram.import_dirs       = string.[tprint("%1/modules", golden_root())];
        metaprogram.build_file        = tprint("%1/target/transpile/driver.jai", golden_root());
        first_text := generate_compiler_metaprogram(metaprogram);
        if !compare_or_update(tprint("%1/first.jai", dir), normalize_golden_abs(first_text), update) all_ok = false;
    }
    return all_ok;
}

run_negative_cases :: (update: bool) -> bool {
    all_ok := true;
    for case_name: NEGATIVE_CASES {
        dir := tprint("%1/tests/data/transpile/negative/%2", juice_root(), case_name);
        config := read_case_config(dir);
        files := collect_case_files(dir);
        rendered: String_Builder;
        total := 0;
        for file: files {
            source, ok := read_entire_file(tprint("%1/%2", dir, file));
            if !ok {
                print("[NEGATIVE FAIL] %1/%2: cannot read input\n", dir, file);
                all_ok = false;
                continue;
            }
            ctx := case_context(config, case_name, file);
            result := transpile_source(source, ctx);
            total += result.diagnostics.count;
            for d: result.diagnostics {
                print_to_builder(*rendered, "%1:%2,%3: %4\n", ctx.path, d.line, d.column, d.message);
            }
        }
        if total == 0 {
            print("[NEGATIVE FAIL] %1: expected diagnostics, got none\n", dir);
            all_ok = false;
            continue;
        }
        if !compare_or_update(tprint("%1/diagnostic.txt", dir), builder_to_string(*rendered), update) all_ok = false;
    }
    return all_ok;
}
