---
id: 068
title: 收口 Command lifecycle session spec
labels: [wayfinder:task]
status: open
assignee: ""
blocked-by: [063, 064, 065, 066, 067, 069, 070, 071]
blocks: []
---

# 068: 收口 Command lifecycle session spec

## Question

把 063-067 与 069-071 的答案收口成什么交付物？

产出：一份 `docs/implementation/lifecycle-session-spec.md`（或并入 `docs/spec.md` 的新章节），作为 `/implement-spec` 的输入。至少包含：

- Command lifecycle session 的 interface：configure / execute 边界、失败语义、host adapter。
- **S1 的 typed stage seam**：active seam 集合（PRESTEP + COMPILE）、TRANSPILE 作为 COMPILE 的 before hook、state 合并、AT = body、enum / vocabulary 处置。
- **S2 的 member plugin 面**：只留 `prestep_hooks`；host 无运行时 stage/position 校验；in-process 测试 seam 的边界。
- **S3 的 host runtime**：发布模块、生成文本只留数据、pin / 测试策略。
- 零文件 `juice test` 的统一校验与唯一有意行为变化。
- 对 063-067 的取代关系：065 的 tagged union、066 的 host 运行时校验、067 的 generated-text 策略由 069-071 复评；064 的 session 归属与零文件校验保留。
- spec §6.1/§6.3 的矩阵承诺如何改写；9 值枚举是否保留为 vocabulary。
- Out of scope 清单（general host、C02、C05、C06、C07、C08、公开声明面、stage plan engine）。

同时：更新 `CONTEXT.md` 中 Command lifecycle session / Stage state / Stage seam 的最终措辞；在 map 的 Decisions so far 记录 063-067 与 069-071 的一行 gist；本票 `## Answer` 记录 spec 路径与审查结论。不改生产代码。

## Answer

<!-- 收口会话填写。 -->
