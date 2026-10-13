# Spec: src 内联 test block 与构建剥离

> 决策过程见地图 [issues/0025](../issues/0025-spec-src-inline-test-blocks.md) 及其子票；本文档是规格的单一收口。纯规格：不实施，实施交给后续 effort（第六章为票清单建议）。

## 1. 背景与目的地

src 原文件允许内联 test block（Zig 风格，贴近实现）；两条构建路径——自举 `jai build.jai` 与 Build command——都正确剥离 test block，编译不再报错；tests/ 的 147 个存量 test block 全部迁入 src（tests/ 保留 data/ fixture 与 `test_support.jai` 测试支撑文件），Testing 模块的 10 个自测块内联进 `modules/Testing.jai`。

## 2. 决策摘要

- **自举剥离机制**（[0028 研究](../issues/0028-research-jai-metaprogram-view-feeding.md)、[ADR 0006](adr/0006-bootstrap-build-strips-inline-test-blocks.md)）：`build.jai` metaprogram 内嵌转译器纯函数；入口视图 `add_build_string`（行号偏移恒 +5、列号精确）；闭包其余视图落盘、`#load` 重写为视图绝对路径；插入点 set_build_options 之后、compiler_begin_intercept 之前；与 Build command 共用同一视图契约。
- **测试共享代码**（[0027 决议](../issues/0027-test-helper-organization-and-strip-boundary.md)）：约 40 个共享声明集中 `tests/test_support.jai` 单文件（2026-10 用户修订：纯测试支撑代码不驻 src/，位置由 `src/test_support.jai` 改为 `tests/test_support.jai`；机制不变）——不被入口 `#load` 引用、不进 Build 闭包、不参与发布构建；Test discovery 全包扫描将其收录进测试程序，程序级共享。STRIP 语义不扩展。
- **Testing 自测归属**（[0030 决议](../issues/0030-implementation-plan.md)）：10 个自测块内联进 `modules/Testing.jai`；**Test discovery 排除集不变**（modules/ 仍排除）；测试程序生成器特例——若 package 存在 `modules/Testing.jai`，收录其 EXPAND 视图**替代** `#import "Testing"` 作为断言模块来源（同一模块只加载一份，全局计数不分裂）。用户 package 语义零变更。模块含 test block 后不可被 jai 直接编译，因此除测试程序生成器（EXPAND 视图）外，**Build command 与自举构建同样收录该模块的 STRIP 视图替代 `#import "Testing"`**（三路径对称特例，0033 决议）：Build command 在每次编译前重写 `<package>/target/testing-module/Testing.jai` 并前置其目录进 import path；自举 build.jai 对仓库根 `modules/Testing.jai` 做同一特例（同路径同语义）。模块 test-free 或不存在时零变化。
- **词条与文档**（[0029 决议](../issues/0029-adr-and-context-update.md)）：CONTEXT.md 新增 **Bootstrap build（自举构建）** 与 **Test support（测试支撑代码）** 两词条（已落地）；spec 即本文档。

## 3. 测试组织规范

**映射表**（tests/ 7 文件 → src）：

| 源文件（块数） | 目标 |
|---|---|
| test_commands.jai（27） | 按块主题拆入 `src/commands/{build,clean,run,registry}.jai`（规划期估计的 `src/{dependency,manifest,target,workspace}.jai` 主题块未出现——实际 27 块全部落在 commands/ 四个文件） |
| test_dispatcher.jai（13） | `src/dispatcher.jai` |
| test_target.jai（11） | `src/target.jai` |
| test_test_command.jai（27） | `src/commands/test.jai` |
| test_testing.jai（10） | `modules/Testing.jai` |
| test_transpiler.jai（45） | 实际落地 `src/transpile_tests.jai`（规划期为 `src/transpile.jai`/`src/transpile_cache.jai`，落地改为独立文件——两者是 build.jai 的 `#load` 目标/入口闭包成员，必须保持 test-free，见 0034 关键约束） |
| test_workspace.jai（14） | `src/workspace.jai` |

**纪律**：

- 测试共享声明只允许位于 `tests/test_support.jai`；其他文件（尤其 src/）顶层不放测试专用声明（src 文件的顶层声明经 STRIP 会保留进发布）。helper 迁移时路径基准改 cwd（原实现基于测试文件位置推导仓库根）。
- `modules/Testing.jai` 顶层不驻测试 helper（它是发布模块，被用户 `#import` 会携带 helper 进用户产物）——Testing 自测所需的 helper 同样进 `tests/test_support.jai`。
- 迁移后测试块总数不变（147 + Testing 自测 10）；`juice test` 的 passed 汇总数**不做硬判据**（Testing.finish 的重置语义使计数依赖执行顺序——当前 "64 passed" 即最后一次重置后的计数）；硬判据 = **0 failed + 退出码 0**。
- 迁移期中间态：Test discovery 全包扫描同时收录 src 与 tests，每个迁移批次后 `juice test` 必须保持全绿。

## 4. 自举剥离改造

按 ADR 0006：`build.jai` 以 `#load` 复用 `src/transpile.jai` 纯函数（被 load 代码编译进 metaprogram 执行环境、不进入被构建程序）；入口文件的 STRIP 视图经 `add_build_string` 喂入（虚拟路径，诊断行号减常量 +5 还原）；闭包其余视图落盘、in-package `#load` 重写为视图绝对路径；test-free 闭包仍原样直编。改造必须**先行**（在 src 仍 test-free 时验证 test-free 直通零回归），随后测试块迁移才有安全落地。

## 5. 验收标准

- **`jai build.jai`**：构建成功；产物 `target/juice.exe` 可运行（烟测：`juice test` 于仓库根跑通）。
- **`juice build`**：仓库根构建成功。
- **`juice test`**：0 failed、退出码 0；测试块总数 147（+Testing 自测 10）全部执行（输出含全部测试名）。
- **中间态**：每个实施批次后 `juice test` 保持全绿。
- **终态**：tests/ 仅剩 data/ 与 test_support.jai；grep 仓库无旧测试文件引用；CONTEXT.md 词条与实现一致。

## 6. 实施计划（后续 effort 票清单建议）

| 票 | 内容 | 验收 | 依赖 |
|---|---|---|---|
| 1. build.jai 内嵌剥离 | 按 ADR 0006 改造；src test-free 期验证 test-free 直通零回归 | `jai build.jai` 全绿、`juice build` 全绿、`juice test` 全绿 | — |
| 2. test_support.jai 抽取 | 约 40 声明迁入（含路径基准调整）；测试文件顶层清理 | `juice test` 全绿 | 1 |
| 3. Testing 自测内联 | 10 块迁 `modules/Testing.jai`；测试程序生成器收录其视图替代 `#import "Testing"` | `juice test` 全绿且输出含 Testing 自测名 | 2 |
| 4. 测试块迁入 src | 按映射表分批迁移，每批后 `juice test` 全绿 | tests/ 仅剩 data/ 与 test_support.jai、`juice test` 全绿 | 2（3 可并行） |
| 5. 收尾 | CONTEXT.md/IMPLEMENTATION.md 对齐、三路径终验、提交 | 三路径全绿 + 文档一致 | 1–4 |
