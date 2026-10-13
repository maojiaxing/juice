---
title: ADR 与 CONTEXT.md 更新范围
status: closed
labels: [wayfinder:grilling]
assignee: maojiaxing
blocked-by: [0027-test-helper-organization-and-strip-boundary.md, 0028-research-jai-metaprogram-view-feeding.md]
---

> 父票：[Spec: src 内联 test block 与构建剥离](0025-spec-src-inline-test-blocks.md)

## Question

helper 组织（0027）与 metaprogram 机制（0028）定案后，本票定三件事：

1. **ADR 与否**：自举剥离机制（build.jai 内嵌 STRIP 视图喂编译器）是否值得 ADR？按三条件审查：hard to reverse（构建机制变更的返工成本）、surprising without context（未来读者会问"build.jai 为什么 load 转译器喂字符串"）、real trade-off（备选：发布视图树、src test-free 纪律、build.jai 退役——均已被用户排除或搁置，ADR 需记录排除理由）。
2. **CONTEXT.md 增/改词清单**：候选新词——自举构建路径（bootstrap build）、测试共享代码的组织术语（依 0027 定案）、Build/Transpile 词条的语义微调（src 内联后闭包必含 test block，语义本身是否需改字；modules/ 保持 test-free 纪律是否入词）。既有词不改义、新词不撞词。
3. **规格文档结构**：docs/ 下新建 spec 文档（src 内联 test block 与自举剥离）的章节形态，供 0030 实施计划落位。

## Resolution

1. **ADR：写，已落地** [ADR 0006](../docs/adr/0006-bootstrap-build-strips-inline-test-blocks.md)——三条件全中（构建管线返工成本中高；build.jai 喂视图必问为何；三个备选被真实权衡排除且排除理由入 ADR）。决定：build.jai 内嵌转译器纯函数、入口视图 `add_build_string`（行号偏移恒 +5）、闭包其余视图落盘、与 Build command 同一视图契约、Test support 不进两条构建路径。被否备选及理由：发布视图树（多一条生成步骤 + bootstrap 鸡生蛋）、src test-free 纪律（与目的地冲突）、自举构建退役（快照腐烂）。
2. **CONTEXT.md：新增两词条，已落地**（文本定稿见 CONTEXT.md）——**Bootstrap build（自举构建）**：`build.jai` metaprogram 直编路径，src 内联后构建输入为剥离视图、与 Build command 共用转译器与视图契约，_Avoid_ 发布视图树；**Test support（测试支撑代码）**：`src/test_support.jai` 约定位置、不进 Build 闭包与 Bootstrap build 输入、Test discovery 扫描收录、测试共享声明只允许位于此，_Avoid_ 测试专用声明散落其他源文件顶层。Build/Transpile/Test discovery 词条**不改字**——闭包语义与扫描语义已覆盖新事实（改字画蛇添足）；modules/ test-free 纪律不入词（既有事实，写进 spec 即可）。Relationships 补一行：Bootstrap build 与 Build command 共用契约；Test support 被扫描收录、不进闭包。
3. **规格文档结构：定稿**——`docs/spec-src-inline-test-blocks.md` 单文件（与 docs/ 扁平结构一致），章节：①背景与目的地（引地图 0025）；②决策摘要（引 0026/0027/0028 决议 gist）；③测试组织规范（src 内联 + Test support + tests/data + modules/ test-free 纪律）；④自举剥离改造（引 ADR 0006 与研究报告）；⑤验收标准（三路径判据）；⑥实施计划（0030 产出落此章）。

**文件改动状态**：CONTEXT.md 与 docs/adr/0006 已写入工作区，未提交——待用户审查后提交（或由后续收尾处理）。
