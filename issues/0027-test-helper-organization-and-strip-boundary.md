---
title: 测试共享代码组织与 STRIP 语义边界
status: open
labels: [wayfinder:grilling]
assignee:
blocked-by: []
---

> 父票：[Spec: src 内联 test block 与构建剥离](0025-spec-src-inline-test-blocks.md)

## Question

147 个存量 test block 内联进 src 后，tests/ 文件顶层的测试共享代码迁到哪？已知事实：`tests/test_commands.jai:13-15` 有共享 helper `juice_root()`、`tests/test_test_command.jai:9-16` 有 recording fake 与记录全局；这些是普通顶层声明，EXPAND 视图下被展开的 `juice_test_N` 过程引用。

候选：

- **a. 内联进对应 src 文件顶层**：STRIP 产物携带测试专用声明（发布 exe 含死代码）。最贴近实现、无新机制；代价是发布产物多几行仅测试使用的代码。
- **b. 保留 tests/ 作测试共享代码目录**（如 `tests/test_helpers.jai`）：测试文件内联后 tests/ 不只剩 data/；EXPAND 下测试程序需 #load 它；Test discovery 扫到无 test block 的 .jai 文件无副作用，但需在规格中写明。
- **c. 测试专用文件剥离**：helper 移入独立文件（如 `src/test_support.jai`），STRIP 模式新增规则整体剥离该文件——需扩展转译器与 Build 语义（STRIP 语义扩展）。
- **d. 自给自足**：每个 test block 复制所需小 helper，消除共享（147 块规模下会有重复）。

连带决策：STRIP 语义是否扩展（c 的"测试专用文件剥离"规则）；Test discovery 排除集是否随之调整；src 内联后的 tests/ 目录形态。

候选 a 与 c 是主要竞争者：a 接受发布产物携带 helper 死代码（零新机制），c 追求发布产物纯净（转译器 + Build 语义扩展）。
