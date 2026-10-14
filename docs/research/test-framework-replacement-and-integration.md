# juice 单元测试框架替换与集成机制研究

> 研究问题：juice 内置单元测试机制（test block 收集与编译、Test 命令、Testing 断言模块、测试发现）的接口边界在哪里？Jai 生态有哪些测试框架/机制？juice 如何设计「允许替换内置单元测试」的集成口（参考 cargo `harness = false`、Zig test runner），开口子落在哪个层？
> 日期：2026-10-14 | 环境：Windows 11 + Git Bash；Jai beta 0.2.009（2025-02-06），编译器 `C:/Users/maojiaxing/DevTools/jai/bin/jai.exe`
> 证据标注：【源码】= 读本仓库/发行版源码逐行确认（行号以 2026-10-14 工作树 6a9621c 为准）|【实验】= 引用既有研究笔记已做实验（实验在本会话未重跑）|【外部资料】= 网络检索佐证（本会话 WebFetch 被网络策略拦截，外部结论只作参考，不承载结论）|【推断】= 基于事实的推理
> 一手来源：本仓库源码与文档（第一来源）、Jai 发行版（第二来源）。外部资料只作参考，结论以 juice 代码与文档为准。

## 结论摘要

juice 的内置测试是一条「发现 → 转译 → 视图落盘 → driver 生成 → metaprogram 编译（编译期执行）」的五段流水线，全部由 Test 命令编排（`src/commands/test.jai`）。它有三个可被替换/集成的自然接口边界：

| 边界 | 现状 | 替换口 |
| --- | --- | --- |
| 断言模块（Testing） | `#import "Testing"` 解析到全局模块；driver 以裸名协议调用 `run`/`finish`/`path_mapping` | **已有雏形**：in-package `modules/Testing.jai` 优先 + import path 前置（test.jai:345-362）；缺口是语义绑死自测场景 |
| runner（driver） | 生成文件 `driver.jai`：`#load` 全部视图 + `#run { run 清单 + finish 收口 }` | **最小开口**：测试清单独立生成物 + 用户 runner 约定（Zig `test_runner` 式） |
| 整条测试前端 | 发现+转译+driver 全由 juice 生成 | **最大开口**：harness=false 式开关，juice 只出编译管道（metaprogram + import 路径 + 依赖剥离 + Testing STRIP 特例） |

**推荐方向**（详见 §5）：断言模块协议化（小步，对称既有特例）→ runner 协议出口（核心集成机制，收集复用、执行替换）→ harness=false 开关（runner 出口的退化特例，届时几乎免费）。发现层排除钩子是所有方案的公共前置（现状会误伤社区框架文件：`.test.jai` 被全包扫描收录、其 in-package `#load` 被 EXPAND 模式剥离）。**硬约束**：test block 不是合法 Jai，收集必须与转译绑定（juice 转译器是唯一实现）；测试在编译期执行，不存在运行期 runner 进程（issues/0007 决议），任何替换方案的执行模型都受此约束。

## 1. juice 内置测试机制的现状与边界（被替换对象）

### 1.1 总体架构：编译期执行模型

测试程序**没有运行期 runner 进程**：全部测试在编译期执行，输出即编译期输出，失败经「强制编译错误 → jai 退出码」通道上报（CONTEXT.md:110-111 Test driver 词条；issues/0007 Resolution「模型决定：测试在编译期执行，不在运行期」）。五段流水线【源码】：

```text
collect_test_files（全包扫描）→ transpile_test_file（EXPAND 转译、全包编号）
→ 内容寻址视图落盘 target/transpile/<hash>/<rel> → generate_test_driver（driver.jai）
→ generate_compiler_metaprogram（first.jai）→ jai -quiet first.jai（编译期执行测试）
```

编排入口 `test_prepared_workspace`（test.jai:96-254）按 8 个步骤注释组织；编译 seam 与 build 同构（test.jai:58-60 注释）：生产 handler 调真实 jai，测试跨同一接口注入 recording fake。

### 1.2 各层接口边界

#### (1) 发现层

`collect_test_files`（test.jai:460-477）：package root 全量递归扫描**小写** `.jai` 文件，不跟随符号链接；排除点开头条目、root 级 `target/`、`tests/data/`、`modules/` 与 root 自身 manifest（test.jai:526-545）；member 子树经 workspace discovery 快照剪枝（test.jai:463-468）。枚举顺序 = 确定性 DFS（每目录内文件先于子目录、均按字典序，test.jai:551-582），转译枚举、driver 调用序、报告序全部由它派生（CONTEXT.md:100-101）。

**注意**：排除集只认「小写 `.jai` 后缀」——社区框架的 `x.test.jai`（gs_test 默认扩展名）满足 `ends_with(".jai")`，会被收录（test.jai:540-545）。

#### (2) 转译层

`transpile_source`（transpile.jai:617-756）是纯函数（source + context → view + tests + diagnostics）。EXPAND 模式（test 用）对每个发现的文件：

- test block 锚点（顶层语句位置的 `test "name" {` 或 `test {`，transpile.jai:669-678）→ `juice_test_N :: () -> () { ... } @test`（transpile.jai:716-735）——`@test` 注记与官方进行中约定对齐（research 0002 建议，零成本）；
- 测试清单产出 `Test_Entry { name, number, line }`（transpile.jai:43-48）：命名测试 = 裸名，匿名测试 = `package相对路径:行号`；
- **in-package `#load` 一律剥离为占位注释**（transpile.jai:647-649）——含 test-free 文件，因为 driver 把全部视图 `#load` 进同一编译单元、顶层符号程序级共享（issues/0007 E1/E2：Jai 不做 `#load` 去重，重复收录即歧义重载）；
- 视图行号与原文件一一对应（ADR 0005，docs/transpiled-output-formatting.md §1.1）。

#### (3) 视图落盘层

内容寻址缓存：key = 纯函数（path + source + mode + version + load targets，transpile_cache.jai:53；JUICE_VERSION 19）。命中跳过写入、无主动清理（test.jai:175-196；test.jai:658-678 注释）。

#### (4) driver 生成层——「运行协议」所在

`generate_test_driver`（test.jai:416-439），四个参数化点（test.jai:400-415 注释）：视图清单（`#load` 每文件恰一次）、path_mapping 注入、pattern 过滤后的测试清单、`finish()`/`assert` 收口。golden 实测形态【源码】（tests/data/transpile/golden/expand-basic/driver.jai）：

```jai
#import "Basic";
#load "<abs>/target/transpile/997dcb6f5a40cb22/expand-basic/sample.jai";
#import "Testing";
#run {
    array_reset(*path_mapping);
    array_add(*path_mapping, .{ view = "<abs>/.../sample.jai", original = "expand-basic/sample.jai" });
    run("addition", juice_test_1);
    run("expand-basic/sample.jai:7", juice_test_2);
    if finish() != 0 assert(false);
}
```

**协议事实**：driver 以**裸名**引用 `path_mapping`/`run`/`finish`——「a plain #import does not open a `Testing.` namespace」（test.jai:405-407，票 0017 发现），故注入用 `array_reset`/`array_add` 原地改全局，不能整体赋值静态数组。

#### (5) 编译层（metaprogram）

`compile_test_program`（test.jai:80-90）：`jai -quiet first.jai`，退出码即测试结果。metaprogram 由共享生成器产出（metaprogram.jai:46-105）：`NO_OUTPUT`（无入口点要求——user main 作为无人引用顶层过程留在视图，issues/0007 决议 2）、import 路径 = Testing 视图目录（哨兵 "" = 未启用，metaprogram.jai:69-74）前置 + `compiler_import_directories`（全局 modules 目录 + `target/packages` 依赖 shim，dependency.jai:68-79，票 0048）、`add_build_file(driver)` 后拦截消息循环。

#### (6) Testing 断言模块——测试程序协议

`modules/Testing.jai`（仅依赖 Basic，modules/Testing.jai:20）：

- 断言三件（`#expand` 宏 + `#caller_location`）：`expect`（63-72）、`expect_eq`（`$T` 同型，76-85）、`fail`（88-91）。失败 = 全局登记 + 宏内 `` `return `` 中止当前测试、套件继续（Zig try expect 语义，issues/0005 决议 1）。
- 执行协议：`run(name, proc: () -> ())`（96-103，打 `[test] <名>` 开始行 + 维护当前测试名）；`finish() -> s32`（108-116，打 `N passed, M failed` 汇总、返回失败数、重置计数）。
- 坐标协议：`path_mapping : [..] Path_Pair` 可变全局（34；Path_Pair 27-30），driver 注入「视图绝对路径 ↔ 原 package 相对路径」改写表，精确匹配改写、空表透传（1-18 注释）。
- 报告格式（1-18 注释）：失败行 `path:line,col: 消息`（无 `Error:` 前缀，编辑器可跳转）。

**协议边界小结**：driver 与断言模块之间的契约 = 裸名 `run`/`finish`/`path_mapping` + 输出格式约定（`[test]` 开始行、失败行坐标、汇总行）。用户测试代码的契约 = `#import "Testing"` + 三断言宏。

#### (7) Testing 模块编译视图特例（三路径）

模块源文件内联 test block 后不可被 jai 直接编译（issues/0033）：

- **Test**：`testing_module_view`（test.jai:277-336）——in-package 模块用 EXPAND 视图 + 追加 test_support 自测段（支撑段以 `__testing_module_support_begin__/end__` 标记切取，test.jai:374-398），自测块进测试列表；用户 package 无此文件时对**全局**模块做 STRIP 视图。写盘 `target/testing-module/Testing.jai`，其目录前置进 import path。
- **Build / bootstrap**：共享 `testing_module_strip_view_dir`（transpile_front.jai:285-314，票 0051）——Build command 传 `juice_modules_dir()/Testing.jai`（build.jai:85），bootstrap 传 cwd 相对 `"modules/Testing.jai"`（build.jai:110）。
- 来源选择 `testing_module_source`（test.jai:345-362）：**package 内 `modules/Testing.jai` 优先，exe 邻接全局模块回退**；rel_path 恒为 `"modules/Testing.jai"`（文件名必须是 Testing.jai 才能被 import path 解析，test.jai:343-344）。

#### (8) 依赖剥离前端

`prepare_dependency_strip_views`（dependency.jai:231，票 0049）：Build 与 Test 共用——对每个依赖 shim 探测依赖入口闭包，含 test block 时整闭包 STRIP 视图落 `target/transpile/deps/<依赖名>/...` 并改写 shim 指向入口视图；依赖测试不发现、不执行（CONTEXT.md:88-89、143）。

#### (9) 编排 seam（既有注入点）

`test_prepared_workspace` 的 `transpile`/`compile`/`dep_transpile` 三个参数默认生产实现、测试注入 recording fake（test.jai:96-103）——与 build 的 compile seam 同构。这是「替换测试前端」在代码层面**已经存在**的接口形状，但目前是编译期注入（测试专用），不是运行期选择。

### 1.3 编译期 vs 运行期边界

| 阶段 | 执行环境 | 证据 |
| --- | --- | --- |
| 发现/转译/视图/driver/metaprogram 生成 | juice 进程内（运行期） | test.jai:96-254 |
| 测试程序编译 + **测试体执行** | jai 子进程的**编译期**（`#run` 顶层执行） | driver 形态（golden）、issues/0007 决议 |
| 失败上报 | 编译错误（`assert(false)`）→ jai 退出码 1；编译失败与测试失败同码 | test.jai:80-90、issues/0006 决议 4（勘误后） |
| 测试崩溃 | 编译器进程崩溃 → 非零退出、无干净归因行 | issues/0004 决议 7 + 勘误 |
| 产物 | 全部生成物在 `target/`（转译子树 + `target/testing-module/`），**不是 artifact** | CONTEXT.md:69、110-111 |

### 1.4 与替换相关的硬约束

1. **收集必须与转译绑定**：test block 不是合法 Jai（CONTEXT.md:97），任何框架想用 test block 语法都必须经 juice 转译器（或自持转译器）。「发现」产出的不是函数指针表，而是 `Test_Entry` 清单 + 视图。
2. **执行模型 = 编译期**：不存在运行期 runner 进程（CONTEXT.md:111 Avoid）；运行期设施（线程、子进程）在测试体内不可用（issues/0007 语义边界）。需要运行期执行的框架（gs_test 式独立可执行）不能被 Test 命令直接承载——Test 不产生 artifact、不启动进程。
3. **`#load` 无去重**：单编译单元聚合要求每个文件恰收录一次（issues/0007 E1）——用户 runner 若自行 `#load` 视图会与 juice 视图清单撞车，必须靠协议规避。
4. **依赖闭包剥离**：任何替换方案都必须处理「依赖/member 源码含 test block 不可编译」——依赖剥离前端（dependency.jai:231）是独立于测试前端的公共设施，替换方案应复用而非重造。
5. **视图行号保真（ADR 0005）**：替换 runner 若想要「失败坐标指回原文件」，必须消费 juice 的 path_mapping 协议或自建等价机制。
6. **裸名协议**：`#import "Testing"` 不开启 `Testing.` 命名空间（test.jai:405-407）——driver 生成模板与断言模块是裸名耦合的，换断言模块必须实现同一裸名协议（或连 driver 一起换）。

## 2. Jai 生态的测试框架与机制

### 2.1 编译器自带约定（发行版 0.2.009，无官方测试框架）

- **`@test` 尾注记 = 进行中的官方约定，无消费方**【源码】：`} @test` 共 8 处——`modules/Basic/tests.jai:17,238,334`、`modules/Math/tests.jai:66,73,91,126`、`modules/RadixSort.jai:177`、`modules/String/module.jai:1549`；`modules/Compiler/Compiler.jai` 内无任何 test 注记处理逻辑（research 0002 已核验）。`modules/Math/tests.jai:1-9` 注释明言官方 test framework「尚未 formalize」。juice 转译产物带 `@test` 注记（transpile.jai:728）即与未来官方方向对齐。
- **各模块 `tests.jai` 自测文件 = 普通可执行 + 手写顺序调用 + `assert`（崩溃式）**【源码】：发行版 `modules/` 下找到 4 个：`Basic/tests.jai`（含 103 处 `assert`）、`Math/tests.jai`、`File_Utilities/tests/tests.jai`、`macos/tests.jai`。即官方惯例是「手写清单 + 崩溃式断言」。
- **`#run` 顶层编译期执行惯例**【源码】：`how_to/` 下 30 个文件含 `#run`——「文件尾部自测」是 how_to 文档的常见形态（如 how_to/700_stack_trace.jai:59 附近测试 c_call）。
- **`modules/Check/` 不是测试框架**【源码】：是编译期错误检查 Metaprogram_Plugin（modules/Check/module.jai:1-5）。
- **无 test block 语法**：0.2.009 无 `test "..." {}` 块语法（juice 的 test block 是 Zig 风格扩展，CONTEXT.md:97）。第三方 open-jai 项目有 `docs/open_jai_test_spec.md`，本会话网络受限未能核验正文，仅记录存在性【外部资料】。

### 2.2 gs_test（社区框架，research 0002 源码级核验）

机制【源码 + 实验，见 docs/research/test-collection-mechanisms.md】：

- **运行期注册**：`Test(name, proc)` 宏在运行期把过程值 `array_add` 进全局 harness 数组（编译期注册已实验判死——编译期对可变全局的修改不持久化到运行期）；
- **发现**：metaprogram 用 `visit_files` 按扩展名（默认 `.test.jai`）扫描；
- **执行**：**每个测试文件独立 workspace、独立可执行**（单 runner 需处理 `#load` 去重，README 明示）；跨文件聚合由 shell 脚本承担（失败继续 + 汇总退出码）。

### 2.3 已判死的收集路径（research 0002）

- **编译期 `#run` 注册**：判死（实验 B：编译期填全局运行期不可见；实验 A：执行顺序为逆 `#load` 序）。
- **metaprogram 扫描（Program_Info）**：对 juice 冗余——扫描发生在转译之后，只能扫到 juice 自己生成的函数。
- **运行期过程值数组**：成立（实验 C + gs_test 互证），是「用户手写普通 Jai 测试函数」场景的可用后备。

### 2.4 社区框架与 juice 的共存现状（隐患）

gs_test 式文件与 juice 的全包发现**不兼容**【源码 + 推断】：

- `x.test.jai` 是小写 `.jai`，被 `collect_test_files` 收录（test.jai:540-545）——而它不含 `test` 锚点，转译透传后混进 juice 测试程序；
- EXPAND 模式对**所有**发现文件剥离 in-package `#load`（transpile.jai:647-649）——gs_test 文件的 `#load "harness.jai"` 会被注释掉，其 `Test(...)` 宏调用失去 harness 定义，测试程序编译失败。

即「零集成」（用户自持框架、juice 不参与）今天都做不到干净共存。这是 §4 基线 0 的内容。

## 3. 外部构建工具的替换机制（参考）

> 本节为【外部资料】：网络检索佐证（cargo 手册/nextest 文档、Zig 文档与社区文章），正文未逐字核验（WebFetch 受限）；**只作设计参考，不承载结论**。映射到 juice 的对照为【推断】。

### 3.1 cargo `harness = false`（Rust）

- 机制：manifest 按 target 声明 `harness = false`（Cargo.toml `[[test]]`），cargo 编译该 test target 但**不链接 libtest、不生成默认 main**，由 crate 自供 `main()`；cargo 职责收缩为：编译（`cfg(test)` 仍生效）、传参（filter 等）、退出码透传。可选的机器可读协议是 libtest JSON 格式（不稳定 feature）。
- 对照 juice：juice 的「默认 harness」= 发现+转译+视图+driver+metaprogram 整条前端；harness=false 对应「前端整体旁路，juice 只出编译管道」。

### 3.2 Zig `test_runner`（Zig）

- 机制：`zig test` 构建 root 文件时，**编译器在语义分析阶段收集全部 `test "..." {}` 块进 `builtin.test_functions`**；默认 runner 是一个可替换的源文件（`std.testing` 的 TestRunner 迭代函数表、打印、按失败数退出）；build.zig 里 `test_runner = <path>` 换 runner 源文件，契约是固定入口 + `builtin.test_functions` 数据。
- 对照 juice：**收集者 = juice 转译器（扮演 Zig 编译器的收集角色），runner = driver.jai（扮演 runner 源文件角色），断言命名空间 = Testing 模块**。Zig 的「收集与 runner 分离」正是 juice driver 生成层可打开的口子——收集结果（Test_Entry 清单 + 视图）以数据形式交给可替换的 runner。

## 4. 替换/集成机制的设计选项

每个选项：开口子位置（具体文件/函数）→ 改动面 → 优点 → 缺点。

### 基线 0：零集成——共存兼容性修补（公共前置）

- **开口**：`collect_file_is_excluded`（test.jai:540-545）增加排除规则；manifest 声明「非 juice 测试文件」的排除模式（如扩展名 `*.test.jai`、目录 `tests/framework/`）。
- **改动面**：发现层一个函数 + manifest 解析 + CONTEXT.md Test discovery 词条。
- **优点**：让 gs_test 式自持框架与 juice 互不干扰（框架文件不进测试程序，其 `#load` 不被剥离）。
- **缺点**：只是「不挡路」，无集成价值；排除集随框架增多会变成方言清单。

### 选项 A：harness=false 式开关——测试前端整体旁路

- **开口**：Test 命令编排（test.jai:29-39 或 test_prepared_workspace 之前）；manifest 字段（如 `test.harness = .JET | .CUSTOM`）或约定（`tests/test_main.jai` 存在即启用）。启用时跳过发现/转译/视图/driver，直接把用户入口文件作为 metaprogram 的 `build_file` 编译。
- **改动面**：Test 命令增一个分支；**复用**：workspace 准备（force_dependencies 语义不变）、`compiler_import_directories`、依赖剥离前端（dependency.jai:231）、Testing STRIP 特例（transpile_front.jai:285-314，经 metaprogram `testing_view_dir` 哨兵）、metaprogram generator（metaprogram.jai:46-105，`no_output` 两种形状都已存在）、compile seam。
- **优点**：改动小（管道全是现成的，只是 build_file 换源）；用户框架完全自持（gs_test 式、任何模型）。
- **缺点**：用户框架**不能用 test block 语法**（juice 转译器旁路后 test block 就是编译错误）——框架必须用普通 Jai 函数写测试；测试体在编译期执行的模型约束仍在（除非用户框架自走 metaprogram，但那已不是 juice 的 Test 命令）；运行期执行（独立 exe）需要 Test 命令增加「产出并运行 artifact」语义，与「测试生成物不是 artifact」（CONTEXT.md:69）冲突，是更大的改动。

### 选项 B：Zig 式 runner 协议——收集复用、执行替换（核心机制）

- **开口**：`generate_test_driver`（test.jai:416-439）拆两层——
  1. **编译形态层**（juice 保留）：视图 `#load` 清单 + `path_mapping` 注入，生成 `test-program.jai` 骨架；
  2. **运行协议层**（可替换）：测试清单（name + `juice_test_N`）从 `#run` 调用序列变成**独立生成物**（如 `target/transpile/test-list.jai`：`TEST_LIST :: Test_Entry.[...]` 或含 `#run` 的过程列表）。
  - 用户声明 runner（manifest 字段或约定 `tests/test_runner.jai`）时：juice 生成 wrapper driver = `#load` 视图 + `#load` 用户 runner（绝对路径，`#load` 目标必须字面量——研究 0028 e2e）；用户的 runner 是普通文件顶层代码 + 自己的 `#run` 块，消费 `TEST_LIST` 按自己框架执行。
- **改动面**：test.jai 的 driver 生成函数重构（默认路径输出逐字节不变——golden 锁定）；清单文件格式规格；wrapper 生成；CONTEXT.md Test driver 词条。
- **优点**：**收集与执行正式分离**——juice 出发现、转译、视图、缓存、行号保真、`@test` 注记、依赖剥离；用户出执行语义与报告格式。断言层同时解放：用户 runner 不调 `run`/`finish` 的话，其测试代码可以 `#import` 任意断言模块（连 driver 都没了，裸名协议不再约束）。执行模型仍是编译期（Test 命令不变）。
- **缺点**：runner 及其 `#load` 目标若含 test block 需要同样走视图（可约定 runner test-free）；wrapper 层把「每文件恰收录一次」的纪律交还给用户 runner（它不能自己再 `#load` 视图）。是三个选项中改动面中等、价值最高的一个。

### 选项 C：断言模块替换——Testing 协议显式化与泛化

- **现状雏形**：in-package `modules/Testing.jai` 优先（test.jai:345-362）+ import path 前置（metaprogram.jai:69-74）——机制已经存在。
- **现状缺口**【源码】：
  1. in-package 模块语义绑死**自测场景**：EXPAND 视图必须追加 test_support 支撑段（标记缺失即报错，test.jai:308-317）——用户 package 没有这些标记文件；
  2. **test-free 用户模块被静默忽略**：`testing_module_view` 对 test-free 模块返回未启用（test.jai:285），`#import "Testing"` 落到全局模块——用户无法用自己的 test-free 断言模块替换；
  3. Build/bootstrap 侧 module_source 钉死：Build 传 `juice_modules_dir()/Testing.jai`（build.jai:85），bootstrap 传 cwd 相对路径（build.jai:110）——三路径的选择逻辑不统一。
- **开口**：`testing_module_view`（test.jai:277-336）与 `testing_module_strip_view_dir`（transpile_front.jai:285-314）的模块来源统一为「package 内 `modules/Testing.jai` 优先、全局回退」；test-free 模块原样启用（直接把其目录前置进 import path，无需编译视图）；含 test block 时编译视图照旧（支撑段需求只在 juice 自测场景出现，用户模块走通用路径）；协议文档化（§1.2(6) 的裸名协议 + 输出格式收口进 docs）。
- **改动面**：两个函数的来源选择 + 一个哨兵语义扩展 + 文档；golden 零变化（juice 自测路径不变）。
- **优点**：最小改动、与剥离侧对称；用户测试代码零变化（仍是 `#import "Testing"`）；断言库、报告格式、计数语义全可换（只要实现 run/finish/path_mapping 裸名协议与输出格式）。
- **缺点**：只能换**断言层**——执行模型（编译期）、清单形态、driver 骨架不能换；协议要求 run/finish/path_mapping 裸名可用（Jai 模块作用域约束）。

### 选项 D：编排 seam 运行期化——测试前端插件

- **开口**：把 test_prepared_workspace 的 `transpile`/`compile`/`dep_transpile` 注入参数（test.jai:96-103）从编译期默认参数升级为运行期可选的「测试前端」组件（manifest 声明选择器 → registry 风格分发）。
- **改动面**：前端接口类型、选择/注册机制、Test 命令流程改造——改动面最大，且大部分能力被 B 覆盖。
- **定位**：B/C 落地后若仍有需求（如社区贡献「参数化测试前端」）再考虑；不进首选。

## 5. 推荐方向与票化建议

**推荐**：按 **C → B → A** 递进，基线 0 作为公共前置与 C 并行。理由：

1. **C 先**：机制雏形已存在（in-package 优先 + import path 前置），缺的是语义泛化与协议文档化；改动最小、与既有三路径特例对称、用户可见价值直接（换断言库）。
2. **B 是核心**：juice 架构里「收集」与「执行」本就在 driver 生成层交界——Zig 的「编译器收集、runner 可换」分工恰好映射为「juice 转译器收集、driver 可换」。清单独立生成物是唯一的协议新面孔，其余全部复用现有管道（视图、缓存、行号保真、依赖剥离、metaprogram）。
3. **A 是 B 的退化特例**：B 落地后「用户 runner = 全部、连视图清单都不要」只差一个开关（build_file 换源 + 跳过前端）；等 B 稳定后 A 几乎免费。若先做 A 再回填 B，收集协议要重设计一遍。
4. **基线 0 先行**：它是所有方案的公共前置——不解决发现层误伤，任何「用户自持框架」的包都会被 juice test 弄坏。

**票化建议**（按依赖序）：

| 票 | 内容 | 开口 | 验收要点 |
| --- | --- | --- | --- |
| 1. 协议文档化 | 把散在 test.jai:405-407 / Testing.jai:1-18 / transpiled-output-formatting.md §2 的隐式协议（裸名 run/finish/path_mapping、输出格式、四参数化点）收口为「测试程序协议」规格节 | docs | 文档与实现一致；无代码变化 |
| 2. 发现排除钩子（基线 0） | manifest 声明排除模式（扩展名/目录）；fixture + E2E（`.test.jai` 文件不被收录、其 `#load` 不被剥离） | test.jai:540-545、manifest.jai | juice test 全绿；新 E2E 钉住共存 |
| 3. 断言模块替换泛化（选项 C） | 三路径 module_source 统一「package 内优先、全局回退」；test-free 用户模块原样启用；支撑段解耦为自测专属 | test.jai:277-362、transpile_front.jai:285-314、build.jai:85、build.jai（根）:110 | 用户 fixture 以自有 modules/Testing.jai 替换成功；juice 自测 golden 零变化 |
| 4. 测试清单拆分（选项 B 前半） | generate_test_driver 拆编译形态/运行协议；TEST_LIST 独立生成物；默认 driver 变其消费方 | test.jai:416-439 | golden 逐字节不变；新增清单格式单测 |
| 5. runner 约定（选项 B 后半） | manifest 声明 runner（或约定 tests/test_runner.jai）；wrapper driver 生成；runner 消费 TEST_LIST | test.jai 编排、manifest.jai | E2E：自持 runner 跑通同一批 test block，输出/退出码自定义 |
| 6. harness=false 开关（选项 A） | 跳过前端、build_file 换源；复用依赖剥离 + Testing STRIP 特例 + metaprogram | test.jai:29-39 | E2E：普通 Jai 测试入口（gs_test 式）经 juice test 编译执行 |

## 引用清单

本仓库（工作树 6a9621c，行号以研究时为准）：

- `CONTEXT.md`：Build 13-14；Test 22-23；Artifact 69（测试生成物不是 artifact）；Target directory 72-74；Transpile 76-78；Strip front 80-82；View 84-86；Local dependency directory 88-89；Test block 96-98；Test discovery 100-101；Testing 103-104；Test support 106-108；Test driver 110-111；Metaprogram generator 122-124；Relationships 141-151。
- `src/commands/test.jai`：TEST_COMMAND 16-23；test_arguments_are_valid 25-27；test_command 29-39（force_dependencies 31-33）；Test_Source_File 43-46；Test_File_Output 51-56；transpile_test_file 61-78；compile_test_program 80-90；test_prepared_workspace 96-254（seam 96-103；转译+编号 104-124；空语义 126-133；视图路径 135-147；Testing 特例 149-168；pattern 零命中 170-173；视图写盘 175-196；模块视图写盘 198-222；driver/metaprogram 224-245；依赖剥离 247-253）；testing_module_view 277-336；testing_module_source 345-362（rel_path 恒 modules/Testing.jai 343-344）；testing_module_support_block 374-398；generate_test_driver 416-439（裸名协议 405-407）；collect_test_files 460-477；collect_directory_is_scanned 526-535；collect_file_is_excluded 540-545；enumerate_test_files 551-582。
- `src/transpile.jai`：Transpile_Mode 15-20；Transpile_Context 30-41；Test_Entry 43-48；source_has_test_block 422-445；source_load_targets 451-470；transpile_source 617-756（EXPAND 剥离 #load 647-649；STRIP 重写 650-658；锚点 669-678；STRIP 占位 699-715；EXPAND juice_test_N + @test 716-735）。
- `src/transpile_cache.jai`：JUICE_VERSION 19；视图 key 53。
- `src/metaprogram.jai`：Compiler_Metaprogram_Options 34-44；generate_compiler_metaprogram 46-105（NO_OUTPUT 57；import 路径 67-78；testing_view_dir 哨兵 69-74；add_build_file 86；消息循环 91-101）。
- `src/transpile_front.jai`：probe_package_closure 78-117；closure_has_tests 122-127；Strip_View_Layout 147-150；view_of_file 182-246；transpile_build_file 255-271；testing_module_strip_view_dir 285-314。
- `src/dependency.jai`：compiler_import_directories 68-79；shim_load_target 160；prepare_dependency_strip_views 231。
- `src/commands/build.jai`：testing_module_strip_view_dir 调用 85（module_source = `juice_modules_dir()/Testing.jai`）；import_dirs 91；testing_view_dir 93；依赖剥离调用 196。
- `src/path_safety.jai`：juice_modules_dir 40。
- `modules/Testing.jai`：输出格式与语义注释 1-18；#import "Basic" 20；Path_Pair 27-30；path_mapping 34；登记全局 41-44；report_failure 53-57；expect 63-72；expect_eq 76-85；fail 88-91；run 96-103；finish 108-116。
- `build.jai`（仓库根，bootstrap）：bootstrap_build_entry 30-53；Testing 特例调用 110；生成+spawn 120-151。
- `docs/transpiled-output-formatting.md`：§1.1 行号保真与编辑点；§1.2 EXPAND 形态；§2 driver 模板（四参数化点、path_mapping、裸名）；§3 first.jai 模板。
- `docs/spec-src-inline-test-blocks.md`：§2 决策摘要（自举剥离、Testing 自测归属、三路径对称特例）。
- `docs/research/test-collection-mechanisms.md`：三条收集路径判定与实验（编译期注册判死、metaprogram 扫描冗余、gs_test 运行期注册；@test 注记 8 处、无消费方）；实验记录（A/B/C 结果原文）。
- `docs/research/jai-metaprogram-view-feeding.md`：#load 语义（进入 metaprogram 执行环境）、add_build_string 虚拟路径与 +5 偏移、`#load` 目标必须字面量（e2e）、诊断映射（e3b）。
- `tests/data/transpile/golden/expand-basic/driver.jai`：driver 生成物的逐字节形态（视图 #load、array_reset/array_add 注入、run 清单、finish/assert 收口）。
- `issues/0002-research-jai-test-collection.md`、`0004-test-block-language-semantics.md`（锚点/签名/同名/崩溃语义决议 1-7）、`0005-testing-assertion-module-api.md`（失败传播、run/finish 收口决议 1-5）、`0006-test-command-cli-semantics.md`（pattern/退出码/空语义决议 1-5）、`0007-test-build-organization.md`（编译期执行模型决议、E1-E9）、`0017-testing-assertion-module.md`、`0039-testing-module-view-helper.md`（形态 C）、`0049-dependency-strip-views.md`（依赖剥离前端 + force_dependencies 缺陷修正）、`0050-strip-front-shared-module.md`、`0051-testing-module-strip-view-shared.md`、`0052-bootstrap-generated-metaprogram.md`、`0053-test-free-module-tests-to-tests-dir.md`。

Jai 发行版（`C:/Users/maojiaxing/DevTools/jai`，beta 0.2.009，2025-02-06）：

- `modules/Basic/tests.jai`：`} @test` 17、238、334；103 处 assert。
- `modules/Math/tests.jai`：`} @test` 66、73、91、126；"formalize" 注释 1-9。
- `modules/RadixSort.jai:177`、`modules/String/module.jai:1549`：`} @test`。
- `modules/File_Utilities/tests/tests.jai`、`modules/macos/tests.jai`：模块自测文件（普通可执行）。
- `modules/Check/module.jai:1-5`：编译期错误检查插件，非测试框架。
- `how_to/`：30 个文件含 `#run`（顶层编译期自测惯例）；`how_to/700_stack_trace.jai:59` 附近测试 c_call。
- 发行版无 `test` 块语法、无测试收集框架（research 0002 已 grep 核验）。

外部资料（网络检索佐证，正文未经逐字核验，仅作设计参考）：

- cargo 自定义 harness：cargo 手册 cargo-targets 的 `harness` 字段与 cargo-test(1)（https://manpages.ubuntu.com/manpages/jammy/man1/cargo-test.1.html；https://manpages.debian.org/trixie-backports/cargo/cargo-test.1.en.html）；nextest 的 custom-test-harnesses 设计文档（https://nexte.st/docs/design/custom-test-harnesses/）；rust-lang/cargo 文档澄清提交 03a5d8f（https://github.com/rust-lang/cargo/commit/03a5d8f4a7489a05a5eec3b6eef4c1f42f274c52）。
- Zig 自定义 test runner：ziglang.org 文档与社区文章（https://www.openmymind.net/Using-A-Custom-Test-Runner-In-Zig/；https://ziggit.dev/t/when-compiling-a-test-block-where-does-the-import-root-comes-from/12405/4）；ziglang/zig 自定义 runner 提交 5daefc5（https://github.com/ziglang/zig/commit/5daefc5e004a25abb2e1499ed8050d0658d0a384）。
- gs_test（community，zlib，2023）：https://github.com/peter-slattery/gs_test（机制细节以 docs/research/test-collection-mechanisms.md 的源码级核验为准）。
- open-jai 的 Jai 测试规格（存在性记录，正文未核验）：https://github.com/withlang-dev/open-jai/blob/main/docs/open_jai_test_spec.md；The Way to Jai 测试章：https://github.com/Ivo-Balbaert/The_Way_to_Jai/blob/main/book/37A_Testing.md。
