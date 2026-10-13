---
title: 转译器核心纯函数
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: [0015-old-test-harness-parameterization.md]
---

> 父票：[Spec: juice test 命令与 test block 单元测试](0013-spec-juice-test-command-and-test-block.md)

## What to build

进程内转译器纯函数：完整 lexer（token span 与 trivia 保留，字符串/注释免疫）+ 锚点级 parser（`test` + 字符串 + `{` / `test` + `{`，仅顶层语句位置）+ 展开/剥离双模式变换 + 转译期诊断。产物严格遵守 [转译产物排版规范](../docs/transpiled-output-formatting.md)（行号保真硬约束，[ADR 0005](../docs/adr/0005-view-line-fidelity.md)）：任何视图行数与原文件一致、编辑点 token 锚定、占位注释带该行原文、`@test` 贴 `}` 后、输出统一 `\n`、无头尾注记、生成行保留前导空白。首批 golden 基线经参数化 harness 跑通。

## Acceptance criteria

- [x] 纯函数接口：源文本 + 上下文 → 视图文本 + 测试清单 + 诊断（无 IO）
- [x] 展开模式：test 头 → `juice_test_N :: () -> () {`（N 按清单顺序编号）、匿名名 `package 相对路径:行号`、`} @test` 贴闭括号且尾随注释后移、in-package `#load` 剥离为带原文占位注释（跨行语句等行数 `(cont)`）
- [x] 剥离模式：test block 语义删除（等行数注释占位）、in-package `#load` 目标字符串重写为视图路径、test-free 文件恒等输出
- [x] 诊断：函数体/类型体内 test、多行 test 头、与他语句同行的 `#load` → 转译期拒绝、位置精确
- [x] 逐字区逐字保留（含注释、空白、空行）；行号保真零例外；命名测试 name 原样复用源 token
- [x] 首批 golden 基线锁定（逐字节对比，经参数化 harness 测试程序跑通）
- [x] 转译产物可手工交 jai 编译通过（含一行成块、一行多测试边界形态）
