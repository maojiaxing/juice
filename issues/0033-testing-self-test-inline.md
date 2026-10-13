---
title: Testing 自测块内联与测试程序生成器特例
status: closed
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

- [x] `juice test` 全绿（0 failed、退出码 0），输出含全部 10 个 Testing 自测名
- [x] 测试块总数不变（147 + Testing 自测 10）
- [x] 用户 package（无 modules/Testing.jai）行为零变更
- [x] 三路径（`jai build.jai` / `juice build` / `juice test`）不受影响

## Out of Scope

- Test discovery 排除集调整（明确不变）
- modules/ 其他文件内联 test block（modules/ 保持 test-free 纪律）

## Further Notes

- 语言：中文交流与文档。
- 与第 4 票并行：两者都改 src/commands/test.jai（本票改生成器、第 4 票迁入 27 个 test block），合并时留意冲突。

## Resolution

已实施（4e43cff/ee6f66c/eb0400b + 三方合并修复 a31a915）：10 个自测块以 test block 形式内联 modules/Testing.jai（#scope_export 段内）；顶层不驻测试 helper（helper 在 test_support.jai）。测试程序生成器特例：package 的 Testing 模块含 test block 时收录其视图（仓库自身 = EXPAND 视图 + 内嵌 test_support 自测支撑段，块编号续接全局序列；用户 package = STRIP 视图）替代 `#import "Testing"`，经 metaprogram import_path 前置命中同一视图、模块只加载一份；path_mapping 映射回 modules/Testing.jai 原文坐标。排除集不变。

设计缺口（实施中发现、main 裁定方案 A 批准）：模块含 test block 后不可被 jai 直编，用户 package 的 juice build/run 若 `#import "Testing"` 必挂（fixture 452/505 实测复现）——与"用户 package 语义零变更"冲突。故 Build command（eb0400b，testing_module_strip_view_dir）与自举构建（a31a915）增加对称特例：模块含 test block 时重写 <package>/target/testing-module/Testing.jai 为 STRIP 视图并前置 import_path。未导入 Testing 的 package 零变化（触发条件唯一 + build-empty 等 fixture 证据）。三路径全绿、Found 147、10 自测名全出现。spec 第二章已补记该特例。
