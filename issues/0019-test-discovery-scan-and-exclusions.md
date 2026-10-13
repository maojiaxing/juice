---
title: 全包发现与排除集
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: [0018-minimal-end-to-end-loop.md]
---

> 父票：[Spec: juice test 命令与 test block 单元测试](0013-spec-juice-test-command-and-test-block.md)

## What to build

`juice test` 从 package root 自动发现测试源（替换显式清单）：全量递归扫描仅小写 `.jai`、不跟随符号链接；排除点开头条目、root 的 target/、root 的 tests/data/（fixture 目录）、root 的 modules/（模块目录）与各 package 的 manifest；root 扫描不进 member 子树（member 自为 root 测试）；扫描消费 workspace discovery 快照（member 边界）但不并入 discovery；遍历确定性（目录内条目字典序）派生枚举、调用与报告顺序。

## Acceptance criteria

- [x] package root 全量递归发现全部合法测试源（含嵌套目录、独立测试文件、内嵌测试源文件）
- [x] 排除集逐条生效：点开头条目、target/、tests/data/、modules/、manifest 均不进扫描；任意深度同名目录不误伤
- [x] 不跟随符号链接（目录与文件）
- [x] member 子树不进 root 扫描；member 自为 root 可测；依赖中的 test 不发现不跑
- [x] 枚举/调用/报告顺序 = 扫描顺序（字典序），重复运行输出字节稳定
- [x] 无测试包 `juice test` 成功退出 + 说明
