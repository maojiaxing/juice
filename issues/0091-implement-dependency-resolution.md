---
title: 实施：显式来源、模块可见性与 Git 解析状态
status: open
labels: [ready-for-agent]
assignee: maojiaxing
parent: "0087"
blocked-by: ["0088", "0089", "0090"]
---

## Goal and contract

父规格 [0087](0087-spec-package-declaration-semantics.md) 是权威，相关已关闭决策为补充；本票必须交付以下可观察行为。

Decisions 9–15、26；A02/A03/A04/A09/A10/A11/A12。按PATH/GIT/WORKSPACE显式取源，不能同名覆盖、版本字段或包名搜索。modules path/name/alias平铺选择；每消费包实际模块和最终导入名去重，禁止覆盖本包/直接/标准模块。提供方自行解析传递依赖、同包模块互用、传递不可向外泄漏；完整环链。Git检出内workspace/path边界和来源身份保留。内容cache与state分离；键区分消费工程/声明包/来源selector，不受alias/reference/modules变化影响；默认分支/branch/tag/rev互斥，已有选择不联网追新，缺内容只补选定commit。完整图成功后原子发布，损坏状态错误，失败保旧且失败，编译失败不回滚。offline完整缓存/选择及完整SHA无记录例外；update全图只更新所选消费context，拒offline。共享源码只读、每消费方私有import准备。普通依赖与插件来源复用typed resolver，不通过全局mutable当前工程传context。

## Ownership

src/dependency.jai、src/metaprogram.jai、新内部解析状态文件、相关main/build加载接线和依赖验收测试；必要内部模型扩展。

## Validation

必须真实临时本地Git repo验证分支移动、普通复用、alias不更新、双工程及双成员隔离、传递更新、失败保旧、清内容后补同commit、离线/损坏状态与环。提供resolve/update/offline及import准备接口给插件和命令；不把函数对象测试代替CLI关键链路。

读 tdd 技能，在此前用户已确认的CLI/现有函数测试边界逐行为red-green，不再请求边界批准。读完整修改文件，避免无约束Any/void。不要删除、降级或整体跳过旧测试掩盖行为缺失。

## Integration

自己的独立worktree/branch从 integration/package-declaration-semantics 最新tip开始；路径与执行纪律见 C:/Users/maojiaxing/DevTools/msys/tmp/juice-package-implementation/README.md。不要写主checkout或其它agent文件。完成前merge最新integration、验证并commit，返回精确命令/exit/计数/限制和接口说明；由merger核对合入并写Resolution关闭。前置票未完成前不要使用假接口声称验证通过。
