---
title: 实施计划：src 内联迁移与 build.jai 剥离改造
status: closed
labels: [wayfinder:grilling]
assignee: maojiaxing
blocked-by: [0027-test-helper-organization-and-strip-boundary.md, 0028-research-jai-metaprogram-view-feeding.md, 0029-adr-and-context-update.md]
---

> 父票：[Spec: src 内联 test block 与构建剥离](0025-spec-src-inline-test-blocks.md)

## Question

三张前置票定案后，本票把规格收口为**实施计划**：将「147 个 test block 迁入 src + build.jai 内嵌剥离 + 验收」拆成后续 effort 的实施票清单（票级粒度、依赖顺序、每票验收），写入 docs/ 规格文档。

计划必须覆盖：迁移映射表（tests/ 各文件 → src 各文件的对应与顺序）、helper 迁移（依 0027 定案）、build.jai 剥离改造步骤（依 0028 定案）、CONTEXT.md/ADR 落地（依 0029 定案）、三条验收路径（`jai build.jai` 自举、`juice build`、`juice test`）的精确判据、迁移期中间态（半迁移时测试如何保持可跑）。

本票产出即目的地：way 已清，实施交给后续 effort。

## Resolution

规格已收口至 [docs/spec-src-inline-test-blocks.md](../docs/spec-src-inline-test-blocks.md)（六章）。本票新增决策：

1. **Testing 自测归属**（用户拍板：测试程序特例）：10 个自测块内联 `modules/Testing.jai`；**Test discovery 排除集不变**；测试程序生成器若发现 package 的 `modules/Testing.jai`，收录其 EXPAND 视图**替代** `#import "Testing"` 作为断言模块来源（同一模块只加载一份，全局计数不分裂；用户 package 语义零变更）。Testing 顶层不驻测试 helper（发布模块纪律），自测 helper 进 `src/test_support.jai`。
2. **交付形态**（用户拍板）：spec 文档实施计划章 = 后续 effort 票清单建议（5 票：build.jai 内嵌剥离先行 → test_support 抽取 → Testing 自测内联 → 测试块迁入 src → 收尾），不预创建实施票。
3. **验收判据事实**：`juice test` 的 passed 汇总数不做硬判据——Testing.finish 的重置语义使计数依赖执行顺序（当前 "64 passed" 是最后一次重置后的计数，driver 实际收录全部 147 块）；硬判据 = **0 failed + 退出码 0** + 块全执行。三路径判据与中间态策略（每批迁移后全绿）见 spec 第五、六章。
4. **映射表**：7 文件 → 对应 src 文件（test_commands 按块主题拆入多文件，test_testing → modules/Testing.jai，test_transpiler 缓存块 → transpile_cache.jai）见 spec 第三章。

地图目的地达成：way 已清，实施交给后续 effort。
