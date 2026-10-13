---
title: prepared workspace 守卫集中为单一 helper
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: []
---

> 架构体检（improve-codebase-architecture）候选 4。

## Problem Statement

「获取 prepared workspace，空则报错并失败」的守卫在 build/test/run 三个 handler 逐字重复（各 5 行，报错文案仅 command 名不同）；文案与返回约定没有 locality。

## Solution

`src/workspace.jai` 新增 `require_prepared_workspace(name, state) -> *Prepared_Workspace`（null = 已打印 `[juice ERROR] Command '%' requires workspace preparation.` 并失败）；三个 handler 替换为两行；报错文案与现在逐字一致；`get_prepared_workspace` 保留（workspace 测试仍直接使用）；helper 补直接单测。

## Acceptance criteria

- [x] 三 handler 改用 helper，既有守卫/命令测试原样通过（错误文案逐字不变）
- [x] helper 直接单测：空状态返回 null、已 prepared 返回结果
- [x] `juice test` 0 failed

## Out of Scope

- Command_Context 的其他收敛

## Further Notes

- 语言：中文交流与文档。

## Resolution

已实施：`src/workspace.jai` 新增 `require_prepared_workspace(name, state) -> *Prepared_Workspace`（null = 已打印与旧守卫逐字一致的 `[juice ERROR] Command '%' requires workspace preparation.`），build/test/run 三个 handler 各缩为两行；`get_prepared_workspace` 保留为原始状态访问器；helper 直接单测 ×2（空状态 / 已 prepared）。全量 `juice test` 152 块 0 failed，既有守卫与命令参数测试原样通过。
