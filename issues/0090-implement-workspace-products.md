---
title: 实施：独立产物与工作区发现选包
status: open
labels: [ready-for-agent]
assignee: maojiaxing
parent: "0087"
blocked-by: ["0088", "0089"]
---

## Goal and contract

父规格 [0087](0087-spec-package-declaration-semantics.md) 是权威，相关已关闭决策为补充；本票必须交付以下可观察行为。

Decisions 4–8、16–18、20；A01/A13/A14/A15。模块/程序独立零/一/多项与固定候选、默认名称/entry/重复与default_run严格校验。工作区members明确目录和单层*、exclude子树、根自动成员、重叠去重、嵌套工作区边界、同名包允许。cwd向上最近声明、无效不跳过，归属只最近合法workspace、未收录/排除独立。实现共享选包结果：默认成员与位置规则，--workspace/-p/--package-path的冲突/歧义/去重/完整基数预校验和目录排序；命令票消费结果。全成员声明先校验但仅选包图获取。test扫描在任何下级package.jai处剪枝。

## Ownership

src/target.jai、src/workspace.jai、src/scan_walk.jai、src/test_discovery.jai 及对应测试；必要的内部模型字段与schema owner完成后协调。

## Validation

CLI临时根包/纯workspace/独立包/被排除包/嵌套workspace/同名包，cwd子目录、零默认、显式集合与子包test不泄漏；提供给commands的准确选包接口。

读 tdd 技能，在此前用户已确认的CLI/现有函数测试边界逐行为red-green，不再请求边界批准。读完整修改文件，避免无约束Any/void。不要删除、降级或整体跳过旧测试掩盖行为缺失。

## Integration

自己的独立worktree/branch从 integration/package-declaration-semantics 最新tip开始；路径与执行纪律见 C:/Users/maojiaxing/DevTools/msys/tmp/juice-package-implementation/README.md。不要写主checkout或其它agent文件。完成前merge最新integration、验证并commit，返回精确命令/exit/计数/限制和接口说明；由merger核对合入并写Resolution关闭。前置票未完成前不要使用假接口声称验证通过。
