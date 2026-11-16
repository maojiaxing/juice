---
title: 地图：package 声明语义优化
status: closed
labels: [wayfinder:map]
assignee: maojiaxing
---

## Destination

形成可交接实施的 Juice 包声明语义规格：概念关系、字段及默认值、解析与校验规则、典型声明示例和破坏性变更迁移方案均无待决项。继续使用 Jai 的 `package.jai`；本地图只做决策，不修改生产实现。

## Notes

- 立图约束已经用户两轮确认；具体字段、默认行为和迁移规则由各子票 Resolution 记录，草稿推荐不作为决定。
  - 允许有明确迁移方案的破坏性变更，不维持两套永久声明语义。
  - 包可同时提供导入模块和可执行产物，不再由包级 LIB/BIN 限定二选一。
  - 依赖来源显式；同名工作区成员不能覆盖已写明的来源。导入名、包身份和版本约束分开定义。
  - 工作区可以只有成员而没有根包；成员关系与命令选包分别定义。
  - 包声明描述包、产物、依赖和插件；复杂构建编排留给构建脚本或插件，不照搬完整构建图。
- 每个会话先读本图；设计讨论使用 grilling、domain-modeling 和 codebase-design，研究票使用 research。以 [领域术语表](../GLOSSARY.md) 为共同语言；Cargo 的 target、Zig 的 target 与 Juice 的构建产物不得未经说明混用。
- 配置简洁性是用户已确认的约束：沿用唯一 `PACKAGE :: Package.{...}`，workspace 嵌套其中；不公开 Manifest/Some/三态包装，不另加 WORKSPACE 入口。具体表达及内部保留标记边界见 [Jai 声明表达、默认值与校验契约](0084-decision-declaration-evaluation-validation.md#resolution)。
- 事实基线为提交 `8d689b3`，主要实现锚点：`src/module.jai`、`src/manifest.jai`、`src/target.jai`、`src/dependency.jai`、`src/workspace.jai`、`src/commands/{build,run,test}.jai`。现有 [产品规格](../docs/spec.md) 描述当前产品，不代表本轮已承诺兼容其全部字段。
- 本地 tracker 沿用 `issues/NNNN-*.md`：`parent` 关联本图，`blocked-by` 记录前置票，`status: open/closed` 和 `assignee` 表示开放/认领状态。frontier = 本图的开放、未认领且前置票均关闭的子票，按文件编号取首项。开始工作前设 `assignee: maojiaxing`；完成后追加 `## Resolution`、关闭票并向本图追加命名链接。
- 子票仅使用 wayfinder 标签；每会话最多解决一张非研究票。建图会话不关闭人工决策票，也不自动实施。
- Cargo、Zig 仅借鉴语义与取舍，研究必须指向官方资料并记录版本/核查日期。研究资产放在独立 `research/package-declaration-*` 分支，推送但不开 PR、不合入主分支；票中保存不可变提交链接。研究结论不替用户决定方案。
- 与 [测试能力迁出地图](0065-map-test-migration-to-testing-package.md) 分开推进：其模块/插件需求可作为本图的案例，不隐式改写已关闭决定，也不执行其迁移工作。
- 本图是索引，详细决定只放在对应票的 Resolution。全部决定清楚时交接规格整理与实施，不把编码任务塞入本图。
- 本图已完成决策并关闭；已生成 [Juice 包声明语义优化与迁移实施规格](0087-spec-package-declaration-semantics.md)，标记 ready-for-agent。产品实现及产品规格/迁移指南的更新尚未执行，交付标准见 [声明迁移、典型示例与规格交接标准](0085-decision-declaration-migration-handoff.md#resolution)。

## Decisions so far

- [Cargo 的包、产物、依赖与工作区语义](0078-research-cargo-package-semantics.md)：已核对包/产物分层、显式继承与来源规则，并用本地 metadata 实验验证同名成员不覆盖 Git 来源；版本和限制见票内研究资产。

- [Zig 的包描述、模块导出与构建编排分工](0079-research-zig-package-semantics.md)：已核对版本固定的身份/内容来源与模块/产物导出分层；构建图、配置重试和未运行示例的限制见研究资产。

- [包、导入模块与可执行产物的声明模型](0080-decision-package-products-defaults.md)：确定两类独立声明、固定自动入口、显式清单与空清单语义，以及名称/入口冲突规则；允许零公开产物，完整矩阵及交接见票内决定。

- [Cargo 全局缓存与 XDG 目录契约](0086-research-cargo-xdg-cache.md)：已核验 XDG 的缓存/状态分工、绝对路径要求及 Cargo 全局源码复用，规范事实与 Juice 政策分开记录。

- [依赖身份、显式来源与可复现解析](0081-decision-dependency-identity-sources.md#resolution)：确定扁平模块引用、来源边界与身份、包内可见性及无锁文件的 XDG 缓存/解析状态契约；统一失败矩阵与后续交接见票内决定。

- [独立工作区、成员关系与命令选包](0082-decision-workspace-members-selection.md#resolution)：确定包/工作区共存、成员及嵌套归属、默认与显式选包、四类命令和批量隔离契约；完整目录树与验收表见票内决定。

- [插件依赖、启用顺序与构建定制的声明边界](0083-decision-plugins-build-customization.md#resolution)：确定插件独立来源、默认/显式启用、options 校验、私有派生视图、固定阶段及构建脚本边界；完整输出冲突和工作区执行契约见票内决定。

- [Jai 声明表达、默认值与校验契约](0084-decision-declaration-evaluation-validation.md#resolution)：确定简单 Package 嵌套写法、内部省略标记、字段/名称/路径校验及分阶段失败与提交边界；草案、实验限制和验收矩阵见票内决定。

- [声明迁移、典型示例与规格交接标准](0085-decision-declaration-migration-handoff.md#resolution)：确定人工迁移、配套发布和规范落点；字段映射、必备示例、组合验收及三条实施验证路径见票内交接。

## Not yet specified

无。所有已识别的范围内决策均已关闭，组合核对未发现新的阻塞；后续规格整理与实施按交接票开展。

## Out of scope

- 本 effort 不实施代码、批量迁移清单、改动编译器/测试运行器或发布产品；只明确所需变更与验收约束。
- 不更换成 TOML、ZON 或新 DSL；不把 package 声明变成通用任务图。
- 暂不新增静态/动态二进制库产物声明；本轮提供方模型仅覆盖源码导入模块和可执行程序，依据 [包、模块与产物模型讨论](0080-decision-package-products-defaults.md)。
- 不在本轮建设包注册中心、发布服务或构建图运行时，也不以“参考 Cargo/Zig”为由默认引入它们的全部功能。
