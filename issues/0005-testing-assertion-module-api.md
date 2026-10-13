---
title: Testing 断言模块 API
status: closed
labels: [wayfinder:grilling]
assignee: maojiaxing
blocked-by: []
---

## Question

Testing 模块（Juice 一级模块，用户代码 `#import "Testing"`）的最小 API：

- 函数集与签名：`expect` / `expect_eq` / `expect_true` …？泛型参数怎么写（`$T`）？
- 失败传播机制：Jai 无异常——expect 失败后当前测试体如何收场（继续执行本测试体只记录失败 / 提前结束该测试 / 返回 bool 由用户传播）？这是"失败继续 + 汇总"语义的关键。
- 失败报告内容：测试名、位置（依赖 诊断与位置映射）、期望 vs 实际；值如何格式化（`Any` 打印？）。
- 模块形态：`modules/Testing.jai` 单文件还是目录；与现有 `modules/Juice.jai` 的 `-import_dir` 暴露方式一致？
- 依赖：Testing 模块是否依赖 runner 提供的运行时接口（失败登记回调），还是自带全局失败登记？

## Resolution

（2026-10-13 grilling 敲定，五项决议）

API 总览（`modules/Testing.jai`，用户 `#import "Testing"`）：

```jai
expect    :: (condition: bool, message := "", args: .. Any, loc := #caller_location) #expand
expect_eq :: (expected: $T, actual: T, message := "", loc := #caller_location) #expand
fail      :: (message: string, loc := #caller_location) #expand
run       :: (name: string, proc: () -> void)
finish    :: () -> s32
```

1. **失败传播 = 中止本测试**：断言失败 → 全局登记 + 宏内 `return;` 立即退出该测试体，套件继续（Zig `try expect` 语义）。机制与官方 assert 同款（发行版 `modules/Basic/module.jai:98`：`assert :: (arg: bool, message := "", args: .. Any, loc := #caller_location) #no_debug #expand`；`#caller_location` 为 Jai 原生，how_to/093 等广泛使用）。选它而非"继续收集本测试全部失败"的关键理由：失败后状态可能已坏，继续断言可能升级为崩溃，而崩溃即 runner 终止（[test block 语言语义](0004-test-block-language-semantics.md)），会破坏"全跑+汇总"承诺。已知边界（spec 写明，不做机制缓解）：void helper 中断言失败提前返回 helper 而非中止测试（Zig try 传播同款 wart）；带返回值过程中为编译错误；仅测试体内是受支持场景；`defer` 随 return 正常触发。
2. **函数集最小三件**：`expect`（形态对齐官方 assert：bool + 可选 printf 风格消息）、`expect_eq`、`fail`（无条件登记并中止）。`expect_true/expect_false/expect_not_eq` 不进 MVP（纯糖，可后续加）。
3. **同型与格式化 = 编译期**：`expect_eq` 用 `$T` 同型约束——类型不匹配即用户测试的编译错误（早期捕获）；失败消息编译期多态拼装（`tprint("% != %", ...)`），不做运行期 Any 类型遍历打印；T 须可 `!=` 且可 print，否则用户测试编译失败。
4. **报告字段与时机**：失败记录三件套 = 测试名（匿名 = `路径:行号`，0004 已定）+ 位置（`#caller_location`，产物坐标；映回原文件归 [诊断与位置映射](0009-diagnostics-and-location-mapping.md)）+ 消息（自动拼装或用户 message）。失败**即时逐条输出** + `finish()` 末尾汇总计数。确切措辞与格式留雾（等 0009 合流）。崩溃报告由 juice 侧输出（归 [test 命令 CLI 语义](0006-test-command-cli-semantics.md)）。
5. **runner 接口 = Testing 收口**：生成的 runner main 只做 `run` 清单 + `exit(finish())`；失败登记、逐条打印、汇总全部收口在 Testing 一处（0007 生成 main 不受输出格式演进影响）。`run` 收 proc 值运行期调用（[研究：Jai 测试收集与构建机制](0002-research-jai-test-collection.md) 实验 C 验证），"当前测试名"上下文由 run 维护。崩溃即终止时无 summary（0004 已接受）。

模块形态：`modules/Testing.jai` 单文件（与 `Juice.jai` 同构），仅依赖 `#import "Basic"`；经既有 `-import_dir` 分发机制暴露（`build.jai:42-43`），接入 test 编译的机械细节归 [测试构建代码组织](0007-test-build-organization.md) 与 [转译集成与缓存架构](0008-transpile-integration-and-cache.md)。

ADR 判断：各项均可逆或可加性扩展（糖、Any 版本断言、措辞演进均不冲突），不满足三条件，不写 ADR（与 0004 先例一致）。Testing 词条入 CONTEXT.md 归 [workspace 模型与词汇修订](0010-workspace-model-and-glossary.md)。

勘误（2026-10-13，[测试构建代码组织](0007-test-build-organization.md) 决议测试编译期执行）：第 5 条「生成的 runner main 只做 `run` 清单 + `exit(finish())`」作废——无 runner main。新形态：生成的 **driver** 以顶层 `#run` 执行清单 + `finish()` 返回非零时 `assert` 强制编译错误（jai 退出码通道）。Testing API（expect/expect_eq/fail/run/finish）**不变**，并被原型证明与执行模型中立（E5 运行期实现在 E9 编译期模型零改动复用）；`run` 的 proc 参数类型应为 `() -> ()` 而非 `() -> void`（Jai 区分零返回值与返回一个 void 值）。
