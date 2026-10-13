---
title: "Spec: juice test 命令与 test block 单元测试"
status: closed
labels: [ready-for-agent]
assignee:
---

> 决策来源（合成自，无新增决策）：[地图：test command 与 test block 单元测试](0001-map-test-command-and-test-block.md) 及其全部决议票（0002–0012）、[ADR 0003 统一 target/](../docs/adr/0003-unified-target-directory.md)、[ADR 0004 转译内建](../docs/adr/0004-transpile-baked-into-juice.md)、[ADR 0005 视图行号保真](../docs/adr/0005-view-line-fidelity.md)、[转译产物排版规范](../docs/transpiled-output-formatting.md)。本 spec 与既有决议冲突时以票面决议为准。

## Problem Statement

Jai 没有语言级单元测试设施：用户无法在包源码中声明测试，也没有工具统一收集、运行并报告测试结果。包作者想要 Zig 风格的 `test` block（内嵌于源码或独立测试文件），一条命令跑全包测试，失败报告给出可点击跳转的原文件坐标；同时，含测试语法的包在正常构建时不应为此付出任何成本。

## Solution

Juice 提供 Zig 风格 `test` block（文件顶层 `test "name" { ... }` 或匿名 `test { ... }`）与 `juice test` 命令：发现全包测试源、经进程内转译器把 test block 转换为带注记的普通过程、生成测试程序并在**编译期**执行、Testing 断言模块提供断言与失败汇总、失败报告以原文件 `path:line,col` 坐标输出、非零退出码反映结果、`<pattern>` 过滤命中测试。build 经探测后剥离，使内嵌测试的包正常编译且零转译成本（test-free 闭包原样直编）。

## User Stories

1. 作为包作者，我可以在包内任意 `.jai` 文件的顶层写 `test "name" { ... }`，声明一个命名测试，让构建工具为我收集并运行它。
2. 作为包作者，我可以写匿名 `test { ... }`，它的报告名自动为「package 相对路径:行号」，无需手工起名。
3. 作为包作者，我的测试体是普通过程体：可以声明局部变量、使用 `defer`、裸 `return` 提前结束当前测试（已登记的失败不丢失）。
4. 作为包作者，我的测试可以看到所在文件顶层的符号、`#load` 链共享的全局作用域符号与本文件 `#import` 的模块符号，与普通顶层过程同权。
5. 作为包作者，我可以声明多个同名测试（按编号生成、无冲突）；撞名时报告自动附 package 相对路径消歧，平时保持裸名字。
6. 作为包作者，我把 test block 写在函数体或类型声明体内时，会得到精确指向该位置的转译期诊断，而不是晦涩的编译器错误。
7. 作为包作者，我声明名为 `test` 的过程或变量完全不受影响——只有 `test` + 字符串 + `{`（或 `test` + `{`）的顶层锚点形态被接管，其余用法原样透传。
8. 作为包作者，我把 test 头写在多行（`test` 与字符串或 `{` 跨行）时，会得到精确的转译期拒绝诊断；一行内写多个测试、或一行成块 `test "x" { body }` 都是合法的。
9. 作为包作者，我在测试内 `#import "Testing"` 即可使用最小断言集 `expect` / `expect_eq` / `fail`。
10. 作为包作者，`expect(cond)` 的形态对齐官方 assert（bool + 可选 printf 风格消息），上手零成本。
11. 作为包作者，`expect_eq(expected, actual)` 在编译期做同型校验——类型不匹配直接是编译错误，不会等到运行才暴露。
12. 作为包作者，一个断言失败后当前测试立即中止（登记失败并 `return`），套件其余测试继续执行——不会因状态已坏而升级成崩溃。
13. 作为包作者，失败报告包含三件套：测试名（匿名即 `路径:行号`）、原文件位置（`path:line,col`，可点击跳转）、期望 vs 实际消息。
14. 作为包作者，运行测试时能看到每个测试的开始行 `[test] <报告名>`，结束时看到汇总 `N passed, M failed`。
15. 作为包作者，我在 package root 运行 `juice test`，内嵌于源文件的测试与独立测试文件中的测试会被一并发现并运行。
16. 作为包作者，我运行 `juice test <pattern>` 可以只跑名字匹配的测试——大小写敏感的子串匹配，作用于最终报告名（匿名测试按 `路径:行号` 匹配）。
17. 作为包作者，我的包没有任何测试（或 pattern 零命中）时，`juice test` 成功退出并给出说明，而不是报错。
18. 作为包作者，任何测试失败时退出码非零（统一 1），全部通过为零——CI 可直接依据退出码判定。
19. 作为包作者，失败行的位置语法与 jai 编译器一致（`path:line,col: 消息`，无 `Error:` 前缀），编辑器和终端的点击语义通用。
20. 作为包作者，测试的枚举顺序、调用顺序与报告顺序是确定的（字典序派生），diff 输出稳定。
21. 作为包作者，我在含内嵌测试的包里运行 `juice build`，构建照常成功——测试被探测后剥离，不进入产物。
22. 作为包作者，我的包没有任何测试时，构建零转译、零缓存、原样直编，与 Juice 不存在之前完全等价。
23. 作为库作者，我的 LIB 包（无 effective target）可以被 `juice test` 正常测试。
24. 作为 workspace 用户，member 以自身为 package root 跑自己的测试；依赖中的 test block 不被发现、不执行。
25. 作为包作者，我把测试 fixture 放在 `tests/data/`、可导入模块放在 `modules/`，它们不会被当成测试源扫描。
26. 作为包作者，`Clean` 递归删除 root 与 member 的 `target/`，转译缓存与产物随之清理。
27. 作为包作者，我理解测试在**编译期环境**执行（allocator/context 为编译期实例，运行期线程/子进程不可用）——适用域是纯逻辑单测。
28. 作为包作者，测试内崩溃式失败（裸 assert、空指针等）会使编译器进程崩溃：非零退出、无干净归因行——我用 Testing 断言替代裸 assert 写测试。
29. 作为包作者，每次 `juice test` 都是全量编译（jai 无增量），这是已知的构建成本。
30. 作为包作者，`juice_test_` 前缀保留给转译器；我撞上该前缀时得到的是 jai 重定义编译错误（MVP 不做规避）。

## Implementation Decisions

1. **语法锚点与语义**：仅 token 级两种形态在顶层语句位置接管——`test` + 字符串字面量 + `{`，或 `test` + `{`；字符串/注释中的 `test` 文本免疫（完整 lexer，非正则）。接管形态都不是合法 Jai、透传形态不会命中锚点，两类互斥无歧义。测试签名锁定 `() -> ()`（Jai 区分零返回值与返回一个 void 值），失败不走返回值通道、由 Testing 全局登记。可见性 = 所在文件顶层可见性。崩溃语义 = 测试崩溃即终止、余下不执行、非零退出。
2. **执行模型 = 编译期执行**：无运行期 runner、无 main。生成的 driver（无入口点文件）收录全部视图并以顶层 `#run` 执行经 pattern 过滤的测试清单，`finish()` 非零则 `assert` 强制编译错误 → jai 退出码通道。编译入口经生成的 metaprogram（NO_OUTPUT 无入口点要求，`import_path` 注入 Testing 模块目录）驱动。用户 main 原样留在视图、不重命名（无入口点要求使其无冲突）。
3. **测试视图规则**：进入测试程序的每个包文件都是缓存中的「测试视图」：`#import` 逐字保留；in-package `#load` 剥离（等行数注释占位）；test block → `juice_test_N :: () -> () { ... } @test`（N 按发现字典序 + 文件内源码序编号）；test-free 文件也生成视图（恒等 + 剥离 load）；out-of-package `#load` 保留原文并跨视图按解析后绝对路径去重。
4. **发现规则**：从 package root 全量递归，仅小写 `.jai`，不跟随符号链接；排除点开头条目、root 的 `target/`、root 的 `tests/data/`（fixture 目录）、root 的 `modules/`（模块目录）与各 package 的 manifest；root 扫描不进 member 子树（member 自为 root 测试）；依赖中的 test 不发现不跑；扫描顺序确定性（字典序）派生枚举、调用与报告顺序。test 扫描消费 workspace discovery 快照（member 边界）但不并入 discovery。
5. **转译集成与缓存**：build 从 effective target 入口沿字面量 in-package `#load` 的传递闭包探测；闭包任一文件含 test block 才转译（剥离视图），test-free 闭包零转译零缓存原样直编；闭包全有全无视图化。转译器 = 进程内单入口纯函数库（源文本 + 上下文 → 视图文本 + 测试清单 + 诊断），lexer/parser 按锚点级局部解析策略（非完整 Jai 语法）。非字面量与 out-of-package `#load` 的目标不转译、不改写，其含 test block 由 jai 编译错误自然暴露。test block 保证生效范围 = 字面量 in-package `#load` 可达（build）/ 全包发现（test）的文件。
6. **统一生成物目录**：package 的全部 Juice 管理生成物落 `<package_root>/target/`——artifact 落其根、依赖导入 shim 落 `target/packages/`、转译产物落 `target/transpile/`（内容寻址：键 = hash(package 相对路径 + 源内容 + 模式 build/test + juice 版本)，hash 目录内镜像相对结构防撞名；build 视图的 load 重写指向目标视图路径，键构成 Merkle 链）。driver / metaprogram 每次生成写入、不缓存。Clean 递归删除 root 与 member 的 `target/` 整目录。
7. **行号保真排版（硬约束）**：任何视图的行数与原文件严格一致（测试视图与剥离视图同守），任何编辑以「1 行换 1 行」为单位，无法等行数展开的输入形态转译期拒绝。编辑点以 token 为界、三类：test 头替换、`@test` 注记（紧贴 `}` 后、尾随注释前）、in-package `#load` 剥离 / build 剥离的等行数注释占位（首行带该行原文，余行 `(cont)` 形态）。视图无头部/尾部注记；生成行保留原行前导空白；输出统一 `\n`；列保真仅承诺逐字区。build 的「删 test block」= 语义删除（不再进入编译），物理形态为等行数注释占位。
8. **诊断坐标 = 零映射**：行号保真使 `#caller_location` 的行:列在逐字区即原文件坐标；断言位置 = `#caller_location` + driver 注入的显式「视图绝对路径 ↔ 原包相对路径」字符串对表（编译期数据，执行清单前注入 Testing；不注入即透传，不破模块中立）。产物编译错误回指 = MVP 人工对照（行:列已一致，剥缓存路径前缀）；juice 侧输出改写列为可加扩展。
9. **Testing 模块 API**（形态经原型 E5/E9 验证，与执行模型中立）：
   ```jai
   expect    :: (condition: bool, message := "", args: .. Any, loc := #caller_location) #expand
   expect_eq :: (expected: $T, actual: T, message := "", loc := #caller_location) #expand
   fail      :: (message: string, loc := #caller_location) #expand
   run       :: (name: string, proc: () -> ())
   finish    :: () -> s32
   // driver 注入的路径映射（默认空数组 = 透传）
   path_mapping : [..] { view: string; original: string };
   ```
   失败 = 全局登记 + 宏内 `return` 中止本测试、套件继续；`expect_eq` 用 `$T` 编译期同型校验；失败即时逐条输出 + `finish()` 汇总计数；仅依赖 Basic。
10. **CLI 语义**：`juice test [pattern]`——pattern 为单个可选参数、大小写敏感子串、匹配最终报告名（含匿名路径名），过滤发生在生成清单时（只列入命中测试）；juice 侧输出 `[juice Test]` 阶段行，runner stdout 原样透传，Testing 加每测试开始行；退出码 MVP 统一 1（失败）/ 0（通过）；无测试或零命中成功退出并说明，零测试跳过 driver 编译。
11. **workspace 模型**：test 复用 prepared workspace——prerequisite 是 prepare-workspace（不依赖 build），消费 discovery 快照但不消费 artifact plan，不造新状态、不拆 artifact plan；LIB 无 effective target 仍可测。
12. **自举与迁移（实施最后一环）**：Juice 自身补 BIN 包 manifest（target 为自身入口）实现自测；迁移分四步——① 转译器库 + 其 golden/负例/编译运行测试先经旧测试设施开发；② `juice test` 命令端到端（fixture 包验证）；③ 仓库存量测试 1:1 迁入 test block（独立测试文件保留，删旧汇总与 `#load` 列表——test 模式全视图加载、顶层符号程序级可见）；④ 迁移全绿后同一提交退役旧测试设施（无观察期）。

## Testing Decisions

- **原则**：只测外部行为、不测实现细节；命令编排一律走生产 seam 的录制适配器（先例：仓库现有 Test seams——dispatch / launch / clean / compile / fetch 注入，生产实现即测试面）。
- **唯一新 seam = command 编排层的转译前置注入**：build 与 test 在 compile seam 之前调用可注入的转译步骤（默认真实现、测试注入假实现录制调用与产物），与现有 compile seam 同构、不引入第二套注入模式。
- **转译器纯函数为单测面**：源文本 + 上下文 → 视图文本 + 测试清单 + 诊断，直接打纯函数；负例断言诊断文本与拒绝语义。
- **golden 三矩阵**（对齐 syntax-transpiler.md 测试矩阵）：文本对比 golden（每输入 `X.jai` 的期望视图 + 期望 driver/metaprogram，绝对路径经 `<abs>` 占位规范化后逐字节对比）、负例（期望诊断 + 非零退出）、编译运行（fixture 包 E2E：`juice test` 于 fixture 包断言退出码与输出）。基线更新经环境变量 `JUICE_UPDATE_GOLDEN`（任意非空重写基线，CI 永不设置），失败打印 diff。
- **fixture 包**：沿用现有 fixture 包形态（完整 package 目录），编译运行矩阵与命令 E2E 共用。
- **实现期验证项**：`#caller_location` 的 file 串与 driver `#load` 传入路径串是否逐字符一致（不一致 → 退化策略前缀 + 后缀匹配）；编译期执行下的文件系统 IO 可用性；jai 自身中间物（obj）位置一次实验定案；编译错误 stderr 与测试 stdout 经缓冲交错（原型 E9 观察，MVP 接受）。

## Out of Scope

- 并行测试执行。
- 崩溃隔离（子进程/信号捕获使崩溃后继续跑）。
- 类型声明体内的 test block（Zig 容器式）。
- workspace-wide 测试模式（root package 一次跑全部 member 的测试）。
- 集成测试（链接/启动 artifact 的测试）。
- 参数化/表驱动测试、mock 框架。
- 通用语法扩展框架：转译器只为 test block 服务，不承诺扩展到任意语法。
- 编辑器/LSP 集成。
- juice 侧编译错误输出改写（解析 jai 输出剥缓存前缀再透传）——列为可加扩展。
- 完整 sourcemap、产物内嵌位置注释。
- 非字面量与 out-of-package `#load` 目标的转译。

## Further Notes

- 交流语言：中文。
- 语义边界（spec 必须写明）：被测代码在编译期环境执行，线程/子进程等运行期设施不可用；测试崩溃 = 编译器进程崩溃（jai 非零退出、无「于测试 X 崩溃」式干净归因行，崩溃点由每测试开始行人眼归因）；测试失败经强制编译错误上报（输出含 assert 行与 stack trace 噪音）；每次全量编译。
- 实施顺序（自举）：四步见 Implementation Decisions 12；开发循环自迁移完成起为「构建 juice → `juice test`」。
- 词汇：Test command / Test block / Test discovery / Testing / Test driver / Target directory / Transpile / View 已入 CONTEXT.md。
