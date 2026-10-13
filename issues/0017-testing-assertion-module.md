---
title: Testing 断言模块
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: [0015-old-test-harness-parameterization.md]
---

> 父票：[Spec: juice test 命令与 test block 单元测试](0013-spec-juice-test-command-and-test-block.md)

## What to build

Juice 一级断言模块，用户代码 `#import "Testing"` 即用：最小断言集 expect / expect_eq / fail（`#expand` 宏，`#caller_location` 默认参数），失败 = 全局登记 + 宏内 `return` 中止本测试、套件继续；`run` / `finish` 收口清单执行与汇总计数；`path_mapping` 可变全局（默认空数组 = 透传）供 driver 注入「视图绝对路径 ↔ 原包相对路径」改写。报告格式对齐 spec：每测试开始行 `[test] <报告名>`、失败行 `path:line,col: 消息`（无 `Error:` 前缀）、汇总 `N passed, M failed`。仅依赖 Basic。API 形态经原型验证（E5/E9，与执行模型中立）。

## Acceptance criteria

- [x] `#import "Testing"` 可用 expect（bool + 可选 printf 风格消息）/ expect_eq（`$T` 编译期同型）/ fail
- [x] 断言失败 → 登记 + 中止当前测试，套件其余测试继续
- [x] `run(name, proc)` 维护当前测试名上下文；`finish()` 返回失败数并输出汇总
- [x] 失败即时逐条输出 `path:line,col: 消息`；每测试开始行 `[test] <名>`；匿名名 `路径:行号` 直接可用
- [x] `path_mapping` 精确匹配改写路径；未注入（空表）原样透传
- [x] 仅依赖 Basic；独立测试程序（经参数化 harness）验证全绿
