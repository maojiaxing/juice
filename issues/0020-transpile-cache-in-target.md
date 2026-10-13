---
title: 转译缓存落 target/transpile
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: [0014-unified-target-directory.md, 0018-minimal-end-to-end-loop.md]
---

> 父票：[Spec: juice test 命令与 test block 单元测试](0013-spec-juice-test-command-and-test-block.md)

## What to build

转译产物按内容寻址缓存落 `target/transpile/`：键 = hash(package 相对路径 + 源内容 + 模式 build/test + juice 版本)，hash 目录内镜像相对结构（防撞名）；build 模式视图的 load 重写指向目标视图路径，键构成 Merkle 链、确定可算；driver 与 metaprogram 每次生成写入、不缓存。内容不变即命中缓存不重转（jai 无增量，无 fingerprint/mtime）；无主动清理，Clean 删 target/ 自然覆盖。

## Acceptance criteria

- [x] 视图经内容寻址落 `target/transpile/<hash>/...`，目录内镜像 package 相对结构
- [x] 键 = hash(相对路径 + 源内容 + 模式 + juice 版本)；build 模式 load 重写目标可经 Merkle 链算出
- [x] 内容不变重复运行命中缓存（不重转）；内容变更生成新 hash 目录
- [x] driver / metaprogram 每次生成写入、不缓存
- [x] Clean 删 target/ 覆盖转译子树（无残留）
- [x] 缓存路径计算为纯函数，经单元测试锁定（含防撞名路径形态）
