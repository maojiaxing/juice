---
title: 研究：Zig 的包描述、模块导出与构建编排分工
status: closed
labels: [wayfinder:research]
assignee: maojiaxing
parent: "0077"
blocked-by: []
research-branch: research/package-declaration-zig
research-asset: docs/research/package-declaration-zig.md
research-commit: 18285bd8c459a7bf80e626ef2bf0f05ad530b141
---

## Question

依据明确版本的 Zig 官方资料及官方实现，build.zig.zon、build.zig、包依赖和模块/产物导出分别承担什么职责，哪些设计可用于仍采用 Jai 声明但不提供完整任务图的 Juice？先核实稳定版本，开发版差异必须单列。

需回答：
- 包身份、包元数据、源码范围、依赖来源与内容身份分别如何表达；版本字符串是否承担依赖求解职责，是否存在锁文件/其他可复现机制，不能凭 Cargo 类比推断。
- 包、可导入模块、静态/动态库和可执行产物的关系；依赖消费方怎样选择导出的模块或产物，名字属于哪一层。
- build.zig.zon 与 build.zig 的职责分离、默认值及校验；声明阶段与构建执行的区分。
- 本地依赖、远程依赖、惰性依赖、编译平台/优化选项如何传递；与 Cargo 式 workspace 是否有直接对应，没有则明确说明。
- 用 4–6 个最小版本固定示例呈现包同时提供模块与程序、依赖重命名、可复现来源、构建定制，以及“不复制完整构建图”时无法原样移植的部分。

完成条件：研究笔记逐项附官方链接、版本与核查日期，区分查证事实、可借鉴取舍和待核实项；为人工决策提供问题，不选择 Juice 方案。资产只提交并推送到本票的研究分支，不合入主分支，不修改产品代码。

## Comments

- 已由 maojiaxing 认领并启动后台研究。独立工作目录：`.claude/worktrees/package-declaration-zig`；代理句柄 `zig-package-research`，任务 `ef842b2b-ccf3-4e5`。研究完成后由主会话核读报告、提交并推送研究分支，再填写 Resolution 和不可变资产链接；当时尚无研究结论；核读结果见下方 Resolution。

## Resolution

[Zig 研究报告（不可变资产）](https://github.com/maojiaxing/juice/blob/18285bd8c459a7bf80e626ef2bf0f05ad530b141/docs/research/package-declaration-zig.md) 已推送到 `research/package-declaration-zig`，未创建 PR、未合入主分支。

- 官方下载索引与固定 tag 核实本报告使用 Zig 0.17.1；该版包元数据/来源描述与 build.zig 构建编排职责分开。
- 包身份、具体内容 hash、依赖键、模块导出名、导入名和程序产物名是不同层次；版本字符串不是 Cargo 式依赖范围求解条件，hash 也不是独立锁文件。
- 同包可导出模块和多个编译产物，但 addModule 不等于构建二进制库；artifact 查询与安装步骤相关，不能直接挪成无构建图的声明语义。
- 惰性依赖涉及配置重试，生成文件涉及执行顺序；这些需要单独评估，不因参考 Zig 就纳入 Juice。
- 主会话复核了官方下载索引、字段文档、模块/产物选择和 dependencyLazy 关键源码。示例没有编译运行，负面结论仅限所查版本及源码范围；平台链接、生态工作区扩展不作为本轮既定事实。

本票仅提供事实与取舍。Juice 导出基数、默认值、来源形状和有限扩展机制仍交人工决策票。
