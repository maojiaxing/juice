---
title: workspace 准备退出 Command 类型——准备成为单一幂等入口
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: []
---

> 架构体检（improve-codebase-architecture）候选 1。

## Problem Statement

`discover-workspace` / `prepare-workspace` 以 `visible=false` 的 Command 形态混入 registry：dispatcher 拒绝直接执行它们（INTERNAL_COMMAND_INVOKED），usage 却写着 `juice prepare-workspace`——接口自相矛盾。两者各是一行转发的浅模块（8 字段 Command 接口 vs 一次函数调用），visible 机制只为它们泄漏进 dispatcher、registry 测试与测试 fixture；准备行为本体在 workspace.jai，命令层还包一层纯转发 adapter，locality 分散。

## Solution

- `src/workspace.jai` 新增 `ensure_workspace_prepared(root_dir, cache_dir, state, discover = discover_workspace, resolve = resolve_artifact_plans, prepare_dependencies = resolve_and_fetch_dependencies) -> *Prepared_Workspace`（null = 失败，错误内部打印；幂等，链现有两步；两步降为模块内部 seam，可注入参数与 `prepare_workspace` 同风格）。
- 删除 `require_prepared_workspace`（票 0037 守卫职责被吸收：失败时打印具体的发现/准备错误）；build/run/test handler 首行改调 ensure，形态统一为「校验参数 → ensure → 消费」。
- `Command` 删除 `visible` 字段；dispatcher 删除 INTERNAL_COMMAND_INVOKED、find_command 的 visible_only、print_usage 的过滤；`src/commands/prepare.jai` 删除；registry 收为 4 个可执行 command。
- build/test 的 prerequisites 清空；run → build 保留为唯一 command 前置边，字符串前置 + DAG dispatcher 不动。
- 零值 ctx 的 handler 失败用例改为纯参数拒绝用例（零值 ctx 会触发真实 IO）；fixture 的 `visible = true` 字段全部清除。

## Acceptance criteria

- [x] `jai build.jai` 后 `./target/juice.exe test` 0 failed
- [x] registry 4 条目，无 visible 相关断言
- [x] ensure 直接单测：空状态失败、幂等（二次调用零重做）、失败传播
- [x] `juice prepare-workspace` → Unknown command + 用法列表（E2E 或人工验证）
- [x] CONTEXT.md / IMPLEMENTATION.md / SUMMARY.md / package.jai 注释同步

## Out of Scope

- 前置图类型化（候选：Speculative）
- Transpile 前端 / Testing 特例 owner / Import entry / manifest 副本 / TYPE 协议（候选 2-6）

## Further Notes

- 语言：中文交流与文档。
- 决策树（grilling）：Q1-A handler 自调；Q2 单一幂等入口 + 守卫吸收；Q3 run 同形态；Q4 前置图保留；Q5-a 保留 Prerequisite command 词条并收紧为 run→build。

## Resolution

已实施：`src/workspace.jai` 新增 `ensure_workspace_prepared(root_dir, cache_dir, state, discover/resolve/prepare_dependencies = 生产默认) -> *Prepared_Workspace`（null = 失败已打印；幂等，链现有两步，两步降为模块内部 seam）；`require_prepared_workspace`（票 0037）删除，职责被吸收——build/run/test handler 形态统一为「校验参数 → ensure → 消费」；`Command` 删除 `visible` 字段，dispatcher 删除 INTERNAL_COMMAND_INVOKED、visible_only 与 print_usage 过滤，`src/commands/prepare.jai` 删除，registry 收为 4 个可执行 command；build/test 前置清空，run→build 保留为唯一前置边。零值 ctx 的 handler 失败用例改为纯参数拒绝用例，fixture 的 `visible = true` 全部清除；ensure 直接单测 ×3（空状态失败、交出结果、幂等）。全量 `jai build.jai` + `./target/juice.exe test`：145 passed, 0 failed（155 发现块含 Testing 自测组）；`juice prepare-workspace` 现为 Unknown command + 4 命令用法列表。CONTEXT.md（Prerequisite command 收紧为 run→build、Test/Workspace preparation/Command registry 词条）、IMPLEMENTATION.md、SUMMARY.md、package.jai 注释同步。
