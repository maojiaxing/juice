---
title: 147 个存量测试块迁入 src
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: [0032-test-support-extraction.md]
---

> 父票：[实施计划](0030-implementation-plan.md)（实施序列第 4 票）；映射表与纪律见 [docs/spec-src-inline-test-blocks.md](../docs/spec-src-inline-test-blocks.md) 第三章。

## Problem Statement

tests/ 的 147 个存量 test block 全部迁入 src 对应文件（Zig 风格贴近实现）；tests/ 仅剩 data/ fixture。迁移后两条构建路径（`jai build.jai`、`juice build`）都必须正确剥离 test block。

## Solution

**映射表**：

| 源文件（块数） | 目标 |
|---|---|
| test_commands.jai（27） | 按块主题拆入 `src/commands/{build,clean,run,registry}.jai` 与 `src/{dependency,manifest,target,workspace}.jai` |
| test_dispatcher.jai（13） | `src/dispatcher.jai` |
| test_target.jai（11） | `src/target.jai` |
| test_test_command.jai（27） | `src/commands/test.jai` |
| test_transpiler.jai（45） | `src/transpile.jai`（缓存相关块 → `src/transpile_cache.jai`） |
| test_workspace.jai（14） | `src/workspace.jai` |

> **落地注记（实际实现与本表有出入，表格保留规划期原貌）**：test_commands.jai 的 27 块全部落 `src/commands/{registry,run,clean,build}.jai`（未落 `src/{dependency,manifest,target,workspace}.jai`）；test_transpiler.jai 的 45 块落 `src/transpile_tests.jai`，原因即下方关键约束：`src/transpile.jai` 与 `src/transpile_cache.jai` 是 build.jai 的 `#load` 目标，必须保持 test-free。

**关键约束（0031 已知风险落地）**：`src/transpile.jai` 与 `src/transpile_cache.jai` 是 build.jai 的 `#load` 目标 / 入口闭包成员——test block 随 metaprogram 编译期文本包含会非法。**这两个文件必须保持 test-free**。转译器的 45 个测试块落独立 src 文件（推荐 `src/transpile_tests.jai`）：不被入口 #load 引用即不进闭包，Test discovery 全包扫描收录（与 test_support.jai 同机制）。落地前 grep 确认无任何 `#load` 指向该文件。

**执行纪律**：

1. 分批迁移（按映射表逐文件），每批后 `juice test` 必须全绿（0 failed、退出码 0）。
2. 迁移期中间态：Test discovery 全包扫描同时收录 src 与 tests，批次间测试保持可跑。
3. 测试块总数不变（147）；passed 汇总数不做硬判据（Testing.finish 重置语义）。
4. 不新增测试专用顶层声明于非 test_support 文件（纪律见 spec 第三章）。
5. 与第 3 票并行：两者都改 src/commands/test.jai（第 3 票改生成器、本票迁入 27 个测试块），合并时留意冲突。

## Acceptance criteria

- [x] 147 块全部迁入 src 对应文件；tests/ 仅剩 data/
- [x] `juice test` 全绿（0 failed、退出码 0），输出含全部测试名
- [x] `jai build.jai` 全绿、`juice build` 全绿（src 含 test block 后剥离正确）
- [x] src/transpile.jai 与 src/transpile_cache.jai test-free（grep 无 test block）
- [x] grep 仓库无旧测试文件（tests/test_*.jai 名称）引用

## Out of Scope

- Testing 自测内联（第 3 票）、收尾（第 5 票）
- modules/ 内联 test block（test-free 纪律）

## Further Notes

- 语言：中文交流与文档。
- beta 0.2.009 下 `#load` 转译器出现两条 `%%` print 兼容警告（无碍；勿"修复"，避免触碰转译器）。

## Resolution

已实施（7 提交 604ad3f..2de7ba8）：137 块全部迁入 src，每批后 juice test 全绿（Found 147、0 failed、退出码 0）。test_commands 27 块按实际主题拆入 src/commands/{registry,run,clean,build}.jai（实测 2/5/4/16；规划期映射表的 dependency/manifest/target/workspace 主题块不存在，见落地注记）；dispatcher 13、target 11、workspace 14、commands/test.jai 27 整迁；transpiler 45 块落新文件 src/transpile_tests.jai（grep 确认无 #load 引用、不进闭包）。src/transpile.jai 与 transpile_cache.jai 保持 test-free。fixture 测试 "Build forwards each prepared plan to compilation" 改造为新剥离语义（断言转译调用 == 2×闭包文件数、编译入口 == 入口 strip 视图、视图已落盘）。三路径 + release + 自举产物烟测全绿；tests/ 仅剩 data/（test_testing 由 0033 处理）。

另：迁移期间发现并记录现存缺陷（非本票回归，基线复现）——manifest 求值器共享固定临时文件且不检查写入结果，偶发 member 丢失，由 0035 修复。
