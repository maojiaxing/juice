---
title: ADR 与 CONTEXT.md 更新范围
status: open
labels: [wayfinder:grilling]
assignee:
blocked-by: [0027-test-helper-organization-and-strip-boundary.md, 0028-research-jai-metaprogram-view-feeding.md]
---

> 父票：[Spec: src 内联 test block 与构建剥离](0025-spec-src-inline-test-blocks.md)

## Question

helper 组织（0027）与 metaprogram 机制（0028）定案后，本票定三件事：

1. **ADR 与否**：自举剥离机制（build.jai 内嵌 STRIP 视图喂编译器）是否值得 ADR？按三条件审查：hard to reverse（构建机制变更的返工成本）、surprising without context（未来读者会问"build.jai 为什么 load 转译器喂字符串"）、real trade-off（备选：发布视图树、src test-free 纪律、build.jai 退役——均已被用户排除或搁置，ADR 需记录排除理由）。
2. **CONTEXT.md 增/改词清单**：候选新词——自举构建路径（bootstrap build）、测试共享代码的组织术语（依 0027 定案）、Build/Transpile 词条的语义微调（src 内联后闭包必含 test block，语义本身是否需改字；modules/ 保持 test-free 纪律是否入词）。既有词不改义、新词不撞词。
3. **规格文档结构**：docs/ 下新建 spec 文档（src 内联 test block 与自举剥离）的章节形态，供 0030 实施计划落位。
