---
title: 研究：Cargo 全局缓存与 XDG 目录契约
status: closed
labels: [wayfinder:research]
assignee: maojiaxing
parent: "0077"
blocked-by: []
---

## Question

为 [依赖身份、显式来源与可复现解析](0081-decision-dependency-identity-sources.md) 中用户新增的“参考 Cargo 设置全局缓存目录，并符合 XDG 规范”要求核实外部事实，不代替用户选择路径策略。

核对 XDG Base Directory 规范对缓存/状态的用途区分、XDG_CACHE_HOME 的默认值、未设置/空值/相对路径处理、目录归属与跨平台适用范围；核对 Cargo Home 的默认位置与覆盖方式、Git 数据库/检出目录如何共享、缓存与工程依赖选择记录的职责区别。不能把 Cargo 自身默认目录直接称为符合 XDG，也不能从它使用锁文件推导 Juice 必须引入锁文件。

来源限定官方规范、Cargo 官方文档或对应源码，报告记录版本/核查日期、每项事实出处与无法核实的边界。重点回答：哪些是 XDG 的规范要求，哪些只是 Cargo 的惯例，哪些 Windows 回退或 Juice 子目录仍须人工决定。

研究资产写入独立 research/package-declaration-cache-xdg 分支的 docs/research/package-declaration-cache-xdg.md；只提交该报告，推送但不开 PR、不合入主分支。完成后将不可变链接与结果摘要记于本票；不实施目录解析器、缓存或依赖解析代码。

## Comments

已认领。当前依赖票已确认无需可提交锁文件、工程解析记录互相隔离、Git 内容可全局共享且缓存可删除；本研究仅核实目录规范与参考实现事实。

## Resolution

研究于 2026-11-13 完成；主会话已完整核读报告，并对照 XDG Base Directory Specification 0.8 和三份 Cargo 官方页面核验关键事实。Cargo Book 为核查日在线滚动版，页面不标具体 Cargo 发行版本；未运行下载/离线行为实验。

研究资产：[Cargo 全局内容缓存与 XDG 目录契约报告](https://github.com/maojiaxing/juice/blob/66cf31c95160d24feb41589ea9ca15bbcfe53227/docs/research/package-declaration-cache-xdg.md)。分支 research/package-declaration-cache-xdg；本地 worktree 为 .claude/worktrees/package-declaration-cache-xdg。唯一报告提交为 66cf31c95160d24feb41589ea9ca15bbcfe53227，已用远程分支引用核验推送成功；未开 PR、未合入 master，未修改生产实现。

事实摘要与边界：

- XDG 区分可重建缓存和跨重启保留的本机状态；缓存/状态基目录分别有 HOME 下的默认值。相关变量必须是绝对路径，遇到相对值应忽略，不以 cwd 解释。完整条文和目录创建规则见报告及其官方链接。
- Cargo 默认 ~/.cargo 并非纯 XDG 缓存目录；其中还包括配置等非缓存内容。git/db 与 git/checkouts 展示全局源码复用，不能替代工程自己的提交选择记录；Cargo 的锁文件做法不构成 Juice 引入锁文件的要求。
- Juice 应用子目录、相对值忽略后的默认回退、Windows 的 XDG/LOCALAPPDATA 优先级以及解析记录归入缓存或状态，都是依赖决策票仍须人工选择的政策。本研究没有替用户接受这些建议。

本票完成的是外部事实核查；目录契约与缓存生命周期继续在 [依赖身份、显式来源与可复现解析](0081-decision-dependency-identity-sources.md) 中决定。
