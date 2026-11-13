---
title: jaix test-block 插件迁移与接线
status: open
labels: [wayfinder:task]
assignee:
blocked-by: [0069]
parent: 0065
---

> 2026-10-22 重锚：按新 juice（otter 实现）重写；注意新 juice 的 `packages/juice-plugin-jaix` 是 PRESTEP 插件，与本票的 jaix AST test-block 插件无关。共同事实见 `0065` Notes。

## Question

按 0067 的成员包布局：

- 把 `jaix/modules/Jaix_Plugin_Test_Block.jai`（632 行；模块名不变）迁到 `testing/packages/Jaix_Plugin_Test_Block/module.jai`（成员包；`package.jai` 的 `PACKAGE.name = "Jaix_Plugin_Test_Block"`，LIB，零依赖；根 `module.jai` = 插件源，test-free）；`testing/package.jai` 已按 0069 声明该成员；
- `jaix/package.jai` 去掉 `Jaix_Plugin_Test_Block` module dependency（保留 packrat 与 `Jaix_Plugin_Try_Catch`）；需要插件的 jaix 用户按 0067 第 2 条的 DEP source 指向成员根；
- 插件测试迁到 testing root：`testing/tests/plugins/test_block_tests.jai`（源 = `jaix/tests/plugins/test_block_tests.jai`，1082 行）、`jaix/tests/core/sourcemap_tests.jai` 中 test-block 相关用例；经 testing root 的 shim `Jaix_Plugin_Test_Block :: #import "Jaix_Plugin_Test_Block"`（sealed 形态不变）；
- fixture / golden 迁到 `testing/fixture/`：`config-test-block`、golden `test-expand` / `test-expand-prefix` / `test-strip`、negative `multiline-test-head`、run `test-run`；`.jai` 沿用 dot-prefix（扫描排除集覆盖）；
- 测试 harness / golden 支撑（`jaix/tests/test_support.jai`、`jaix/tests/data` 相关部分）随迁或复制必要部分；与 0070 的 Testing 自测 support 段合并到 `testing/tests/test_support.jai`；
- testing root 跑 `juice test` 全绿；成员包不作为独立 test root（0067）；jaix 剩余测试与 embed 验证全绿（新 juice exe 于 jaix 根跑 `test` + `jaix/examples/embed-consumer`）；
- 更新 jaix 文档 / 规格中对该插件的引用（`jaix/docs/spec.md` §10.1、CONTEXT 如有）。

**Done when:** jaix `juice test` + embed 全绿；testing root 的插件测试全绿；jaix 包不再声明或引用 test-block 插件；模块名与 `#import` 拼写不变；成员包不作为独立 test root 运行。
