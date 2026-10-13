---
title: 测试共享代码组织与 STRIP 语义边界
status: closed
labels: [wayfinder:grilling]
assignee: maojiaxing
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

## Resolution

**决策：测试共享代码集中 `src/test_support.jai`（单文件）**——票面候选的融合变体，事实核查（test 命令对全包扫描到的每个文件无条件转译、test-free 文件恒等输出、测试程序程序级共享，src/commands/test.jai:73）后解锁的选项：

1. **组织**：tests/ 各文件顶层的全部共享声明（约 40 个：helper + recording fake + 记录全局 + GOLDEN_CASES 等常量）迁入 `src/test_support.jai` 单文件（约 600 行）。tests/ 仅剩 data/ fixture。
2. **Build 路径零影响**：test_support.jai 不被 `src/main.jai` #load → 不在 Build 入口闭包 → 不转译、不编译、不进发布产物。零新机制（STRIP 语义不扩展）。
3. **Test 路径天然收录**：Test discovery 全包扫描 src/test_support.jai（不在排除集），恒等转译收录进测试程序，src 内联 test block 经程序级可见性引用其声明。Test discovery 排除集不调整。
4. **纪律**（写进规格）：测试共享声明只允许放 test_support.jai；其他 src 文件顶层不放测试专用声明（若放，STRIP 会保留进发布，由编译/审阅暴露）。
5. **新词条**：Test support（测试支撑代码）——src/test_support.jai 收录测试共享声明的约定位置；词条定稿与 CONTEXT.md 更新留给 [ADR 与 CONTEXT.md 更新范围](0029-adr-and-context-update.md)。
