---
title: Spec: src 内联 test block 与构建剥离
status: closed
labels: [wayfinder:map]
assignee: maojiaxing
blocked-by: []
---

## Destination

一张规格：juice 的 src 原文件允许内联 test block（Zig 风格，贴近实现）；两条构建路径——自举 `jai build.jai` 与 `juice build`——都正确剥离 test block，编译不再报错；tests/ 的 147 个存量 test block 全部迁入 src（tests/ 仅保留 data/ fixture）。本地图只产出决策清单 + CONTEXT.md/ADR 更新 + 后续实施计划，不实施。

## Notes

- 语言：中文交流与文档。
- 技能：grilling 与 domain-modeling 每会话必用；research 用于 Jai 编译器机制查证（本地 jai 模块目录为 primary source）。
- 已定决策（用户拍板）：自举剥离 = build.jai 内嵌 STRIP 视图（`#load` 转译器纯函数，视图喂给编译器）；存量全迁；build 闭包外缺口排除；收尾票由 agent 执行（提交 + 关旧票）。
- 关键事实：src/transpile.jai 仅依赖 Basic/String，纯函数无 IO；build.jai 只 `add_build_file("src/main.jai")`，#load 树由编译器跟随；src/ 目前零 test block（147 块全在 tests/）。
- 旧票 0013–0024 实现完整但全部未提交、status open（AC 已勾选）——收尾票负责。
- 规格文档落点：docs/ 下新建 spec 文档；决策细节记录在各子票的 resolution 评论。

## Decisions so far

<!-- 关闭一张子票追加一行：gist + 链接 -->

- [研究：Jai metaprogram 内加载转译器并喂视图的机制](0028-research-jai-metaprogram-view-feeding.md): 三问全可行——`#load` 编译进 metaprogram 执行环境不进入被构建程序；`add_build_string` 存在（行号偏移恒 +5、相对 `#load` 以调用点文件目录为基准、目标须字符串字面量）；插入点 set_build_options 后 begin_intercept 前，入口视图 add_build_string、闭包其余视图落盘，ADR 0005 行号映射成立。详情见 docs/research/jai-metaprogram-view-feeding.md。
- [收尾：提交 test block 体系实现并关闭旧票](0026-commit-and-close-test-block-implementation.md): 5 条主题提交（313805c 转译器+Testing / f6a9d3e build 转译前置+target 目录 / e2cbce0 test 命令 / e53da6e 测试迁移 / 文档+tracker）；`juice test` 仓库根 64 passed, 0 failed；旧票 0013–0024 全关；.claude/ 不入库。

- [测试共享代码组织与 STRIP 语义边界](0027-test-helper-organization-and-strip-boundary.md): 约 40 个共享声明集中 `src/test_support.jai` 单文件——不在 #load 树上（Build 零影响）、Test 全包扫描恒等收录（程序级共享）、STRIP 语义不扩展、排除集不调整、tests/ 仅剩 data/；新词条 Test support 定稿留给 0029。

- [ADR 与 CONTEXT.md 更新范围](0029-adr-and-context-update.md): ADR 0006 已写（自举构建内嵌转译器、入口视图 add_build_string、与 Build command 同一视图契约，三备选排除理由入文）；CONTEXT.md 新增 Bootstrap build 与 Test support 两词条（Build/Transpile/Test discovery 不改字）；spec 文档定稿为 docs/spec-src-inline-test-blocks.md 单文件六章。改动在工作区待用户审查提交。

- [实施计划：src 内联迁移与 build.jai 剥离改造](0030-implementation-plan.md): Testing 自测内联 modules/Testing.jai + 测试程序生成器收录其视图替代 #import（排除集不变、用户包零变更）；5 票实施序列；验收硬判据 0 failed + 退出码 0（passed 数不硬判——finish 重置语义）。规格收口 docs/spec-src-inline-test-blocks.md，way 已清。

## Not yet specified

<!-- 全部毕业：实施计划与验收清单已入 docs/spec-src-inline-test-blocks.md -->

## Out of scope

- build 闭包外文件的剥离覆盖扩大（用户明确排除；维持 CONTEXT.md 现语义：非字面量/包外 `#load` 目标的 test block 由编译错误暴露）
- modules/ 内联 test block（modules/ 保持 test-free 纪律，写进规格即可）
- 转译器演化为通用语法扩展框架（CONTEXT.md Transpile 词条已 Avoid）
