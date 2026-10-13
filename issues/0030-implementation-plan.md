---
title: 实施计划：src 内联迁移与 build.jai 剥离改造
status: open
labels: [wayfinder:grilling]
assignee:
blocked-by: [0027-test-helper-organization-and-strip-boundary.md, 0028-research-jai-metaprogram-view-feeding.md, 0029-adr-and-context-update.md]
---

> 父票：[Spec: src 内联 test block 与构建剥离](0025-spec-src-inline-test-blocks.md)

## Question

三张前置票定案后，本票把规格收口为**实施计划**：将「147 个 test block 迁入 src + build.jai 内嵌剥离 + 验收」拆成后续 effort 的实施票清单（票级粒度、依赖顺序、每票验收），写入 docs/ 规格文档。

计划必须覆盖：迁移映射表（tests/ 各文件 → src 各文件的对应与顺序）、helper 迁移（依 0027 定案）、build.jai 剥离改造步骤（依 0028 定案）、CONTEXT.md/ADR 落地（依 0029 定案）、三条验收路径（`jai build.jai` 自举、`juice build`、`juice test`）的精确判据、迁移期中间态（半迁移时测试如何保持可跑）。

本票产出即目的地：way 已清，实施交给后续 effort。
