---
title: build 转译前置接入
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: [0018-minimal-end-to-end-loop.md, 0020-transpile-cache-in-target.md]
---

> 父票：[Spec: juice test 命令与 test block 单元测试](0013-spec-juice-test-command-and-test-block.md)

## What to build

build 命令接入转译前置：从 effective target 入口沿字面量 in-package `#load` 的传递闭包探测；闭包任一文件含 test block → 整个闭包视图化（test-free 文件 = 原文 + load 重写）并以剥离视图编译；test-free 闭包零转译零缓存、原样直编。非字面量与 out-of-package `#load` 的目标不转译不改写，其含 test block 由 jai 编译错误自然暴露。run 经 build 继承剥离语义。转译前置走编排层注入式 seam（与 test 命令同构，默认真实现、测试注入假实现）；转译器本体跨命令共享。

## Acceptance criteria

- [x] 含内嵌 test 的 fixture 包 `juice build` 成功——测试被剥离、产物语义不变
- [x] 无测试包 build 零转译零缓存（注入 fake 验证转译步骤未被调用）
- [x] 探测范围 = 入口字面量 in-package `#load` 传递闭包；闭包含 test 即全有全无视图化
- [x] 非字面量 / out-of-package `#load` 语句原文保留、目标不改写
- [x] run 经 build 继承剥离语义（含测试包 run 正常启动产物）
- [x] seam 注入测试：fake 转译验证调用时机、假产物参与编译
