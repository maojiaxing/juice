# Jai 测试收集与构建机制研究

> 研究票：[issues/0002-research-jai-test-collection.md](../issues/0002-research-jai-test-collection.md)
> 日期：2026-10-13 | 环境：Jai beta 0.2.009（2025-02-06），Windows 11 + Git Bash，编译器 `C:/Users/maojiaxing/DevTools/jai/bin/jai.exe`
> 证据标注：【实验】= 本机编译运行验证 | 【源码】= 发行版/社区源码逐行阅读（gs_test 部分经网络核验）| 【推断】= 基于事实的推理 | 【官方文档】= 发行版文档/注释原文
> 实验目录 `C:/Users/maojiaxing/AppData/Local/Temp/juice-test-research/`，未修改仓库产品代码。

## 结论摘要

`juice test` 的测试收集与执行，三条候选路径的判定：

| 路径 | 判定 | 证据 |
| --- | --- | --- |
| 1. 编译期注册（`#run` 填全局数组 + 过程指针） | **不可行**：编译期对可变全局的修改不持久化到运行期（实验 B）；且编译期 `#run` 执行顺序为逆 `#load` 序，非源码序 | 【实验】 |
| 2. metaprogram 扫描（Program_Info 遍历） | **技术可能但对 Juice 冗余**：扫描发生在转译之后，只能扫到 Juice 自己生成的函数，而生成时信息已完备 | 【推断】 |
| 3. 先例复用 | **gs_test 证实运行期过程值注册 + 文件扫描 + 聚合退出码**；发行版内有进行中的官方约定 `@test` 注记（框架未 formalize，无消费方） | 【源码】 |

**对 Juice 的推荐（MVP）**：转译期枚举测试 + runner main 显式顺序调用 + gs_test 式失败汇总退出码。Juice 的转译器解析全部源文件，天然掌握每个 `test` 块的名字与位置，**不需要任何编译期/运行期发现机制**。运行期过程值数组（gs_test 模式）已被验证可作后备机制；编译期注册正式判死。

## 背景：juice test 的需求

用户在源文件顶层写 Zig 风格 `test "name" { ... }` 或匿名 `test { ... }`，Juice 转译成标准 Jai 并生成 test runner，编译运行全部测试，失败继续，汇总退出码。

先前研究已验证的语言事实（【实验】，见 [syntax-transpiler.md](syntax-transpiler.md)）：

- Jai 不支持尾随块调用（`my_proc("hello") { ... }` 报 "Semicolon expected after expression"）——test 块不能转译成"注册调用 + 尾随块"，必须拆成"命名过程 + 调用"两件套。
- 顶层 `#run` 在编译期执行。
- `#load` 是文本包含，被包含文件与包含者共享同一 program 的全局作用域；`#load "a"` 不带扩展名无法解析（须 `#load "a.jai"`）。

## 路径一：编译期注册 —— 实验判死

设想机制：`test "name" {...}` 转译为 `test_1 :: () {...}`，同文件顶层追加 `#run test_register("name", test_1)` 存入全局数组；runner main 运行期读数组遍历执行。

**实验 A/B/C**（工程见文末实验记录，一个 main 覆盖三个判定点）：

- **A（完备性）**：`#load` 链上多个文件各自的顶层 `#run` **全部被执行** ✓。但执行顺序为 **b_test_2 → b_test_1 → a_test_1，即逆 `#load` 序**，不是源码序——即使注册可行，收集顺序也不可靠。
- **B（持久性，判死点）**：编译期 `#run` 修改的可变全局（`registered_count`、`registered_tests` 数组）**运行期初值为 0/空**（`--- before runtime register: registered_count=0`）。编译期分配器是编译器堆，可变全局在编译期的修改不会序列化进产物。编译期注册路径**不可行**。
- **C（过程值）**：运行期注册 + 过程指针存数组 + 遍历调用，端到端成功 ✓（gs_test 模式成立）；编译期写入过程指针（C1）随 B 不可行。

**gs_test 的对照证据**【源码】：gs_test 选择了运行期注册而非编译期注册，与本实验结论互为印证。

## 路径二：metaprogram 扫描 —— 对 Juice 冗余

设想：Juice 生成 build 脚本，编译期经 `modules/Compiler` 的 Program_Info API（`build_engine_get_info_for_build_index()` / `t_load_engine()`；字段含 `procedures`、`constants`、`ordered_proc_values` 等）遍历过程按名字模式收集测试并生成调用。

**判定**：冗余。扫描对象是"已存在于编译单元里的标准 Jai 函数"，而 `test` 块不是标准 Jai，必须先经 Juice 转译；扫描发生在转译之后，只能扫到 Juice 自己生成的函数——生成它们时信息已完备。该路径只在"用户以普通 Jai 函数 + 命名约定写测试、不经转译"的场景有价值，与 Juice 的转译架构正交。**不进 MVP。**（Program_Info 细节为【推断】，对结论无影响：即使 API 齐备，结论仍是冗余。）

## 路径三：先例调查

### gs_test（社区，源码级核验）

gs_test（github.com/peter-slattery/gs_test，zlib，2023）是 GitHub 上可完整读源码的 Jai 测试框架。核心机制【源码】：

```jai
// harness.jai —— 运行期注册
Test_Proc :: #type () -> ();
Test_Desc :: struct { name: string; proc: Test_Proc; }
#add_context global_test_harness: Test_Harness;  // harness.tests: [..]Test_Desc

Test :: (name: string, proc: Test_Proc, loc := #caller_location) #expand {
    h := harness();
    array_add(*h.tests, .{ name = name, proc = proc });  // 运行期：过程值入动态数组
}
Run_Test_Harness :: () #expand {
    for h.tests { run_single_test(h, it); }   // 运行期：取出过程值调用
    return_code := finish_all_tests(); exit(return_code);  // 有失败 → 1
}
```

```jai
// module.jai —— 构建期发现：文件扫描而非 AST
record_test_file :: (info, test_files) {
    // 按 category.file_extension（默认 ".test.jai"）匹配 visit_files 结果
}
configure :: (...) { for root_path: config.root_paths { visit_files(root_path, true, *test_files, record_test_file); } }
build_test_file :: (path_string, category) -> string {
    workspace := compiler_create_workspace(...);
    add_build_file(path_string, workspace);
    add_build_string(tprint("#load \"%harness.jai\";\n", #filepath), workspace);  // 注入 harness
}
output :: () { /* 生成 run_all_tests.sh：SUCCESS=0；每测试后 if [ $? != 0 ] SUCCESS=1；exit $SUCCESS */ }
```

要点：

- (a) 过程值可存数组、运行期取出调用（与本仓库实验 C2 互证）；name 是字符串字面量（静态存储），无分配器问题。
- (b) `add_build_string` 可向 workspace 注入 `#load` 字符串——Juice 生成 runner 可用同一手法。
- (c) **每个测试文件独立 workspace、独立可执行文件**。README 原文警示单 runner 方案的坑："Because of the way Jai handles imports, we have to either have a single test executable which runs all your tests... In the former case, we'd be forced to do a bunch of complicated things to deduplicate #load calls."——单 runner 必须保证同一文件只被 `#load` 一次。
- (d) 跨文件聚合由脚本承担（失败继续 + 汇总退出码），可直接照搬其语义。

### 发行版内：`@test` 注记 —— 进行中的官方约定（实验 D 新发现）

发行版没有测试框架或收集模式（grep `Run_Test|Test_Harness|test_framework|test_register` 全发行版零命中【源码】），但存在一个**进行中的官方约定**：

- 过程尾部注记 `@test`，共 8 处【源码】：`modules/Basic/tests.jai:17,238,334`、`modules/Math/tests.jai:66,73,91,126`、`modules/RadixSort.jai:177`、`modules/String/module.jai:1549`。形态均为：

```jai
print_int_tests :: () {
    assert(...);
} @test
```

- `modules/Compiler/Compiler.jai` 内无任何 `test` 注记处理逻辑【源码】——`@test` 不是编译器指令，只是注记，当前**无消费方**（消费者应在未来官方 test framework 中）。
- `modules/Math/tests.jai:1-9` 注释原文【官方文档】："These were tests that were in Math.jai, but it doesn't seem like a good idea to pay for tests every time everyone compiles... Once we formalize someplace for tests to go, we can probably put these back into Math as something that gets optionally loaded...!" 与 "// @note @abner Yes. I'm going to decide whether the test framework should opt to load these from a tests.jai file."——官方 test framework 明确**尚未 formalize**。
- 各模块自带 `tests.jai`（Math、Basic、Memory、File_Utilities、Default_Allocator 等）目前是普通可执行文件，手写顺序调用 + `assert`（崩溃式）。
- funniman/testify（社区另一测试库）网络持续不可达，仅记录存在性。

**对 Juice 的含义**：转译产物中给生成的测试函数带上 `@test` 注记是零成本的（注记是纯语法元素，不影响编译），且与官方未来方向对齐——官方框架落地时 Juice 生成的测试天然可被发现。建议作为 [0007 测试构建代码组织](../issues/0007-test-build-organization.md)票的设计输入。

## 实验记录

环境：Windows 11 + Git Bash；编译 `jai -quiet main.jai`，运行产物 `main.exe`。工程四个文件（`reg.jai` / `a.jai` / `b.jai` / `main.jai`）见 `C:/Users/maojiaxing/AppData/Local/Temp/juice-test-research/`。

`reg.jai`（注册器）：

```jai
#import "Basic";

Test_Proc :: #type () -> ();
Test_Desc :: struct { name: string; proc: Test_Proc; }
registered_tests: [64] Test_Desc;
registered_count := 0;

test_register :: (name: string, proc: Test_Proc) {
    registered_tests[registered_count] = .{ name, proc };
    registered_count += 1;
    print("register: % (count=%)\n", name, registered_count);
}
```

`a.jai`（1 个测试）、`b.jai`（2 个测试）均为 `x_test_N :: () { print(...); }` + `#run test_register(...)`。`main.jai` 依次 `#load "reg.jai"; #load "a.jai"; #load "b.jai";`，main 中先打印运行期初值并尝试执行既有注册，再做运行期注册基线。

| # | 实验 | 结果 | 判定 |
| --- | --- | --- | --- |
| P0-a | 尾随块调用语法 | 报 "Semicolon expected after expression" | 不支持【实验】 |
| P0-b | `#load` 不带扩展名 | 报 "Unable to open file ... /a" | 须写全 `.jai`【实验】 |
| A | `#load` 链多文件顶层 `#run` 完备性与顺序 | 编译期输出 3 条注册：b_test_2 → b_test_1 → a_test_1 | 全部执行；**逆 `#load` 序**【实验】 |
| B | 编译期填充的全局运行期可见性 | `before runtime register: registered_count=0` | **不持久，路径判死**【实验】 |
| C | 过程指针存数组 + 遍历调用（运行期写入） | 2 条运行期注册全部成功调用 | 成立（gs_test 佐证）【实验】 |
| D | 发行版测试先例 | 无框架/收集模式；`@test` 注记 8 处进行中约定，无消费方 | 见路径三【源码】 |

编译期完整输出原文：

```
register: b_test_2 (count=1)
register: b_test_1 (count=2)
register: a_test_1 (count=3)
```

运行期完整输出原文：

```
--- before runtime register: registered_count=0
register: runtime_a_test_1 (count=1)
register: runtime_b_test_1 (count=2)
--- after runtime: registered_count=2
run runtime_a_test_1
a_test_1 ran
run runtime_b_test_1
b_test_1 ran
```

## 对 Juice 的推荐（落点）

1. **发现**：转译期枚举。转译器已解析全部源文件，test 块清单（名字、文件、行号）在转译时即完备；不需要编译期注册（判死）也不需要 metaprogram 扫描（冗余）。
2. **转译形态**：`test "name" {...}` → `juice_test_<n> :: () {...}` 命名过程（尾随块不可用）；建议产物函数带 `@test` 注记与官方未来约定对齐（零成本）。
3. **执行**：runner main 显式顺序调用每个 `juice_test_<n>`，统计失败数，非零退出（gs_test 的 SUCCESS 汇总语义）。失败继续由断言转记录式检查实现（归 [Testing 模块 API 票](../issues/0005-testing-assertion-module-api.md)）。
4. **`#load` 去重**：单 runner 聚合多文件时保证同一文件只 include 一次（gs_test README 警示的唯一坑；Juice 由扫描与转译清单控制）。
5. **后备机制**：运行期过程值数组注册（实验 C + gs_test 双重验证）在任何需要"用户手写普通 Jai 测试函数"的场景可用。

## 引用清单

Jai 发行版（`C:/Users/maojiaxing/DevTools/jai`，beta 0.2.009）：

- `modules/Basic/tests.jai`：`} @test` 注记 17、238、334。
- `modules/Math/tests.jai`：`} @test` 注记 66、73、91、126；"formalize" 注释 1-9。
- `modules/RadixSort.jai:177`、`modules/String/module.jai:1549`：`} @test`。
- `modules/Compiler/Compiler.jai`：全文无 test 注记处理（grep 佐证）。
- 各模块 `tests.jai`（Math、Basic、Memory、File_Utilities、Default_Allocator 等）：普通可执行 + 手写调用 + `assert`。

社区（网络核验，2026-10-13）：

- gs_test 仓库与 README（单/多可执行权衡原文）：https://github.com/peter-slattery/gs_test
- gs_test harness.jai（Test/Test_Desc/Run_Test_Harness 运行期注册）：https://raw.githubusercontent.com/peter-slattery/gs_test/main/harness.jai
- gs_test module.jai（visit_files 发现、add_build_string、run_all_tests.sh 生成）：https://raw.githubusercontent.com/peter-slattery/gs_test/main/module.jai
- funniman/testify（存在性，网络不可达）：https://github.com/funniman/testify
- jai.community wiki（31 主题无测试框架主题）：https://jai.community/c/wiki/7
- Program_Info API 公开佐证（build_engine_get_info_for_build_index / t_load_engine；BSVino/jai-primer 等）：WebSearch 综合，【推断】

本仓库：

- 实验工程：`C:/Users/maojiaxing/AppData/Local/Temp/juice-test-research/`（reg/a/b/main.jai + 本文实验记录）。
- 先前研究：[syntax-transpiler.md](syntax-transpiler.md)（P0 系列语言事实、转译架构）。
