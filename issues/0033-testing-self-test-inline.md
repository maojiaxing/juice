---
title: Testing 自测块内联与测试程序生成器特例
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [0032-test-support-extraction.md]
---

> 父票：[实施计划](0030-implementation-plan.md)（实施序列第 3 票）；归属决议见 0030 Resolution 与 [docs/spec-src-inline-test-blocks.md](../docs/spec-src-inline-test-blocks.md) 第二、三章。

## Problem Statement

tests/test_testing.jai 的 10 个自测块（Testing 断言模块的自身测试）需内联进 `modules/Testing.jai`（贴近实现）。但 Test discovery 排除集含 modules/，内联后测试程序仍走 `#import "Testing"` 会加载发布模块（无测试块），自测块不会被展开执行。

## Solution

1. 10 个自测块迁入 `modules/Testing.jai`（test block 形式，与用户用法一致）。
2. modules/Testing.jai 顶层不驻测试 helper（发布模块纪律）；自测所需 helper 已在 [0032](0032-test-support-extraction.md) 迁入 src/test_support.jai，经测试程序程序级共享可见。
3. **Test discovery 排除集不变**（modules/ 仍排除）。
4. **测试程序生成器特例**（src/commands/test.jai）：若 package 存在 `modules/Testing.jai`，收录其 EXPAND 视图**替代** `#import "Testing"` 作为断言模块来源——同一模块只加载一份，全局计数不分裂；用户 package 语义零变更（无 modules/Testing.jai 时走原路径）。

## Acceptance criteria

- [ ] `juice test` 全绿（0 failed、退出码 0），输出含全部 10 个 Testing 自测名
- [ ] 测试块总数不变（147 + Testing 自测 10）
- [ ] 用户 package（无 modules/Testing.jai）行为零变更
- [ ] 三路径（`jai build.jai` / `juice build` / `juice test`）不受影响

## Out of Scope

- Test discovery 排除集调整（明确不变）
- modules/ 其他文件内联 test block（modules/ 保持 test-free 纪律）

## Further Notes

- 语言：中文交流与文档。
- 与第 4 票并行：两者都改 src/commands/test.jai（本票改生成器、第 4 票迁入 27 个 test block），合并时留意冲突。
