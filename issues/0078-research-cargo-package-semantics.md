---
title: 研究：Cargo 的包、产物、依赖与工作区语义
status: closed
labels: [wayfinder:research]
assignee: maojiaxing
parent: "0077"
blocked-by: []
research-branch: research/package-declaration-cargo
research-asset: docs/research/package-declaration-cargo.md
research-commit: 43e8fdde29e941294ffd86719acd8c3244601c26
---

## Question

依据 Cargo 官方文档及必要的官方实现，哪些语义能帮助 Juice 区分包、导入模块、可执行产物、依赖和工作区，哪些不能直接映射到 Jai？记录参考版本/文档渠道及核查日期，不把研究结论当作 Juice 已选方案。

需回答：
- package、crate、lib/bin/example/test target 的关系与基数；显式声明、约定发现及禁用发现的优先规则。说明此处 target 与编译平台 target 的区别。
- 虚拟工作区与带根包工作区；members、exclude、default-members 及 build/run/test 的默认选包和产物选择。
- 本地路径、Git、registry 来源如何声明与校验；package 名、依赖别名、版本约束、Git revision/branch/tag 和锁定结果分别是什么，workspace 继承或覆盖是否显式。
- build script、普通依赖、构建/测试依赖及声明数据的分工。不要将 Rust crate 机制等同于 Jai 的导入模块。
- 用 4–6 个最小官方语义示例暴露取舍：模块加程序、纯工作区、别名、显式 Git 与同名本地成员、运行目标歧义。

完成条件：形成一份逐项附官方来源链接的研究笔记，区分“查证事实 / 可借鉴取舍 / 尚未核实项”，并列出留给人工决策票的问题。资产只提交并推送到本票的研究分支，不合入主分支，不修改产品代码。

## Comments

- 已由 maojiaxing 认领并启动后台研究。独立工作目录：`.claude/worktrees/package-declaration-cargo`；代理句柄 `cargo-package-research`，任务 `491b8b44-a283-4ff`。研究完成后由主会话核读报告、提交并推送研究分支，再填写 Resolution 和不可变资产链接；当时尚无研究结论；核读与补证结果见下方 Resolution。

## Resolution

[Cargo 研究报告（不可变资产）](https://github.com/maojiaxing/juice/blob/43e8fdde29e941294ffd86719acd8c3244601c26/docs/research/package-declaration-cargo.md) 已推送到 `research/package-declaration-cargo`，未创建 PR、未合入主分支。

- 文档基线为 Cargo 1.85.0；一包可有一个 library 和多个程序，工作区成员与命令默认选包分开，自动发现可显式关闭。
- 包身份、导入别名、来源与锁定结果不同；`package` 指实际包名，不是 Git 子目录。工作区依赖必须显式继承，不能从成员同名推导来源替换。
- 本机 Cargo 1.96.0 的全本地 Git/工作区 metadata 实验确认：相同包名与版本可以同时以成员与 Git 来源存在，使用者仍解析到显式 Git 来源；版本与文档基线不同已明示。
- 已修正草稿的 Git 选包错误，并补充 workspace 依赖继承、多位置声明、补丁候选与版本约束的区别。
- 未验证旧版二进制、全部历史发现边界及网络 Git 行为；研究报告保留限制，不把这些边界用于已定规则。

本票提供事实而非 Juice 方案。模块基数、约定发现、默认产物及来源表达留给命名的人工决策票。
