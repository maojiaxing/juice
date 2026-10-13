---
title: 收尾：提交 test block 体系实现并关闭旧票
status: closed
labels: [wayfinder:task]
assignee: maojiaxing
blocked-by: []
---

> 父票：[Spec: src 内联 test block 与构建剥离](0025-spec-src-inline-test-blocks.md)

## What to build

test block 体系（旧票 0013–0024 的实现成果）整体仍处于工作区未提交状态：15 个已修改文件、10 个未跟踪新文件、1 个删除。本票完成收尾：分主题提交、验证全绿、关闭旧票。不涉及 src 内联迁移（后续 effort 的活）。

## Acceptance criteria

- [x] 工作区干净：无未提交的 test block 体系实现（含 issues/、docs/ 未跟踪文件一并入库）
- [x] 提交按主题拆分（建议：转译器与 Testing 模块 / build 转译前置 / test 命令 / 测试迁移与旧 harness 退役 / 文档与 tracker）
- [x] `juice test` 于仓库根全绿（0024 的最终验收路径）
- [x] 旧票 0013–0024 全部 `status: closed`（AC 均已勾选，关闭即记录，不在票内重述答案）

## Resolution

- **提交拆分**（5 条，均于 master）：`313805c` 转译器与 Testing 模块（950+ 行新增）；`f6a9d3e` build 转译前置 + 统一 target 目录 + UNSPECIFIED 包类型 + 自举 BIN manifest（package.jai）；`e2cbce0` test 命令与 registry 注册；`e53da6e` 存量测试迁入 test block 体系、旧 harness 退役（110 文件，tests/data/ fixture 全套）；文档与 tracker 一条（本票关闭后提交）。
- **验证**：`juice test` 于仓库根 **64 passed, 0 failed**。
- **旧票关闭**：0013–0024 全部 `status: closed`。
- **不入库**：`.claude/`（本地设置与 worktree 缓存，留工作区忽略）。
