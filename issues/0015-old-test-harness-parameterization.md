---
title: 旧测试 harness 参数化
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: []
---

> 父票：[Spec: juice test 命令与 test block 单元测试](0013-spec-juice-test-command-and-test-block.md)

## What to build

旧 build 测试脚本（metaprogram harness，当前硬编码编译单一测试程序）改为循环编译一份**测试程序清单**：逐个构建、汇总各程序成败、任一失败即非零退出。清单初始含现有测试程序与一个空骨架新程序（转译器测试的载体）。这是 prefactor——后续转译器与 Testing 模块的独立测试程序依赖多程序编译能力。

## Acceptance criteria

- [x] harness 编译测试程序清单中的每个程序（不再硬编码单一入口）
- [x] 清单含现有测试程序 + 空骨架新程序，两者均构建成功
- [x] 任一程序构建失败即整体非零退出并报出程序名
- [x] 存量 53 测试经新入口跑通全绿（行为零变化）
