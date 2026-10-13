---
title: 退役旧设施 + 文档
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: [0023-repo-test-migration-and-bootstrap.md]
---

> 父票：[Spec: juice test 命令与 test block 单元测试](0013-spec-juice-test-command-and-test-block.md)

## What to build

测试单轨化收尾：删除旧测试 harness（metaprogram 测试脚本）与旧测试 exe 产物；更新 IMPLEMENTATION.md 的构建/测试节——开发循环改为「构建 juice → `juice test`」自举形态，测试设施描述对齐新体系。全量测试经 `juice test` 单一入口全绿。

## Acceptance criteria

- [x] 旧 harness 与旧测试 exe 删除（git 历史保底，无观察期）
- [x] IMPLEMENTATION.md 构建/测试节更新：`juice test` 为唯一测试入口，自举循环成文
- [x] 仓库内无旧测试设施残留引用
- [x] `juice test` 于仓库根全绿——全部实现票完成后唯一的测试验证路径
