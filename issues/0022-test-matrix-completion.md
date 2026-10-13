---
title: 测试矩阵补齐
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: [0019-test-discovery-scan-and-exclusions.md, 0020-transpile-cache-in-target.md, 0021-build-transpile-front-step.md]
---

> 父票：[Spec: juice test 命令与 test block 单元测试](0013-spec-juice-test-command-and-test-block.md)

## What to build

三矩阵测试完整落地（对齐 [排版规范 §4](../docs/transpiled-output-formatting.md)）：golden 全量——多输入文件 case、每输入期望视图 + 期望 driver + 期望 metaprogram，绝对路径经 `<abs>` 占位规范化后逐字节对比；负例——期望诊断文本逐字对比 + 非零退出；编译运行——包级 fixture 的 E2E（LIB 包可测、pattern 过滤、崩溃语义）。基线更新开关：环境变量 `JUICE_UPDATE_GOLDEN` 任意非空重写期望文件，失败打印 diff，CI 永不设置。

## Acceptance criteria

- [x] golden：多文件 case（跨文件编号、字典序清单）期望视图/driver/metaprogram 逐字节对比通过
- [x] `<abs>` 规范化：期望文件以 `<abs>` 占位绝对路径前缀，比对前替换实际前缀
- [x] 负例：多行 test 头、函数体内 test、同行混排 `#load` 等诊断文本逐字对比 + 退出码非零
- [x] 编译运行：LIB 包 `juice test` 通过；pattern 过滤 E2E（命中/零命中）；崩溃语义 E2E（裸 assert 崩溃 → 非零退出、无干净归因行）
- [x] `JUICE_UPDATE_GOLDEN` 置任意非空重写基线；未设置时失败打印 diff、非零退出
- [x] 三矩阵全绿（经 `juice test` 于 fixture 包 + 旧 harness 转译器测试程序双路径）
