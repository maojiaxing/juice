---
title: test_support.jai 抽取与测试文件顶层清理
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [0031-bootstrap-build-transpile-front.md]
---

> 父票：[实施计划](0030-implementation-plan.md)（实施序列第 2 票）；组织决议见 [0027](0027-test-helper-organization-and-strip-boundary.md)；规格见 [docs/spec-src-inline-test-blocks.md](../docs/spec-src-inline-test-blocks.md) 第三章。

## Problem Statement

147 个 test block 迁入 src 前，tests/ 各文件顶层的共享声明（约 40 个：`juice_root()` 等 helper、recording fake 与记录全局、GOLDEN_CASES 常量）必须先行集中。否则各块迁入 src 后无处引用共享代码；且这些声明若散落 src 文件顶层会被 STRIP 保留进发布产物。

## Solution

按 0027 决议，全部测试共享声明迁入 `src/test_support.jai` 单文件：

1. tests/ 各文件顶层的共享声明逐一迁入，测试块只引用、不再自持。
2. **路径基准调整**：helper 的路径基准改 cwd（原实现基于测试文件位置推导仓库根），迁移时同步修正实现与调用点。
3. **Build 路径零影响**：test_support.jai 不被 `src/main.jai` #load → 不在 Build 闭包 → 不转译、不编译、不进发布产物（STRIP 语义不扩展）。
4. **Test 路径天然收录**：Test discovery 全包扫描收录 test_support.jai（不在排除集），测试程序程序级共享。排除集不调整。
5. **纪律**：测试共享声明只允许位于 src/test_support.jai；其他 src 文件顶层不放测试专用声明（若放，STRIP 保留进发布，由编译/审阅暴露）。
6. **发布模块纪律**：modules/Testing.jai 顶层不驻测试 helper；Testing 自测所需的 helper 同样进 test_support.jai。

## Acceptance criteria

- [ ] `juice test` 全绿（0 failed、退出码 0；passed 汇总数不做硬判据）
- [ ] src/test_support.jai 存在且含全部共享声明；tests/ 各文件顶层无共享声明残留
- [ ] 三路径（`jai build.jai` / `juice build` / `juice test`）不受影响
- [ ] 测试块总数不变（147 + Testing 自测 10）

## Out of Scope

- 测试块迁入 src（第 4 票）、Testing 自测内联（第 3 票）
- STRIP 语义扩展与 Test discovery 排除集调整（0027 已排除）

## Further Notes

- 语言：中文交流与文档。
