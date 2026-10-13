---
title: 统一 target/ 落地（ADR 0003）
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: []
---

> 父票：[Spec: juice test 命令与 test block 单元测试](0013-spec-juice-test-command-and-test-block.md)

## What to build

Package 的全部 Juice 管理生成物统一落入 `<package root>/target/`：artifact 落其根（无 profile 分层），依赖导入 shim 落 `target/packages/` 且 import 解析指向之；Clean 递归删除 root 与 member 的 target/ 整目录。旧 `result/`、`.packages` 遗留目录不再管理。这是宽重构 prefactor——转译缓存（后续票）需要统一的生成物目录。

## Acceptance criteria

- [x] 构建产物（exe 等）落 `<package root>/target/` 根，不再落 `result/`
- [x] 依赖导入 shim 落 `target/packages/`，import 解析（`-import_dir` 指向）正确解析依赖
- [x] Clean 递归删除 root 与 member 的 target/ 整目录；无 manifest 时删当前 root 的 target/
- [x] 旧 `result/` 与 `.packages` 不再被 Clean 触碰（遗留不管）
- [x] 存量测试断言随迁（旧 harness 跑通全绿）
