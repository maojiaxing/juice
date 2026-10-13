---
title: 147 个存量测试块迁入 src
status: open
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

**关键约束（0031 已知风险落地）**：`src/transpile.jai` 与 `src/transpile_cache.jai` 是 build.jai 的 `#load` 目标 / 入口闭包成员——test block 随 metaprogram 编译期文本包含会非法。**这两个文件必须保持 test-free**。转译器的 45 个测试块落独立 src 文件（推荐 `src/transpile_tests.jai`）：不被入口 #load 引用即不进闭包，Test discovery 全包扫描收录（与 test_support.jai 同机制）。落地前 grep 确认无任何 `#load` 指向该文件。

**执行纪律**：

1. 分批迁移（按映射表逐文件），每批后 `juice test` 必须全绿（0 failed、退出码 0）。
2. 迁移期中间态：Test discovery 全包扫描同时收录 src 与 tests，批次间测试保持可跑。
3. 测试块总数不变（147）；passed 汇总数不做硬判据（Testing.finish 重置语义）。
4. 不新增测试专用顶层声明于非 test_support 文件（纪律见 spec 第三章）。
5. 与第 3 票并行：两者都改 src/commands/test.jai（第 3 票改生成器、本票迁入 27 个测试块），合并时留意冲突。

## Acceptance criteria

- [ ] 147 块全部迁入 src 对应文件；tests/ 仅剩 data/
- [ ] `juice test` 全绿（0 failed、退出码 0），输出含全部测试名
- [ ] `jai build.jai` 全绿、`juice build` 全绿（src 含 test block 后剥离正确）
- [ ] src/transpile.jai 与 src/transpile_cache.jai test-free（grep 无 test block）
- [ ] grep 仓库无旧测试文件（tests/test_*.jai 名称）引用

## Out of Scope

- Testing 自测内联（第 3 票）、收尾（第 5 票）
- modules/ 内联 test block（test-free 纪律）

## Further Notes

- 语言：中文交流与文档。
- beta 0.2.009 下 `#load` 转译器出现两条 `%%` print 兼容警告（无碍；勿"修复"，避免触碰转译器）。
