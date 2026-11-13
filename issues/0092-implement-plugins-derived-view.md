---
title: 实施：独立插件来源与包级派生视图
status: open
labels: [ready-for-agent]
assignee: maojiaxing
parent: "0087"
blocked-by: ["0091"]
---

## Goal and contract

父规格 [0087](0087-spec-package-declaration-semantics.md) 是权威，相关已关闭决策为补充；本票必须交付以下可观察行为。

Decisions 21–25及15插件校验提交边界；A05/A06/A07/A08。插件独立builtin或source/module选择，不要求普通依赖/成员名，公开模块唯一插件入口与独立ABI检查，去掉用户version。实际插件重复或同模块双重普通引用失败，普通API另一导出可用。省略默认load/test-block、[]全禁用、非空完全替换不补默认；options重复/未知/必填/非法hook前失败。固定stage顺序+列表顺序，各所选包自身仅一次prepare/私有view；依赖/未选插件不激活，update不hook。保留lint/test-block/生命周期贡献。substitute/drop/generated显式注册，本轮视图仅当前输出、消费包target私有区、逻辑路径保留、冲突失败、源/共享检出只读、不修改Package声明或将辅助文件变公开根入口。

## Ownership

src/plugin.jai、src/plugin_host.jai、src/plugin_scan.jai、src/transpile*.jai、src/lifecycle.jai、packages/juice-plugin-*/module.jai及相关测试。

## Validation

真实CLI覆盖默认/空/非空插件、坏配置无hook副作用、一次包prepare、多包隔离、lint和jaix普通API分离、替换/丢弃/辅助注册与旧文件不消费、写失败和冲突、共享源未修改。提供commands只prepare一次的接口，保留现有插件安装能力。

读 tdd 技能，在此前用户已确认的CLI/现有函数测试边界逐行为red-green，不再请求边界批准。读完整修改文件，避免无约束Any/void。不要删除、降级或整体跳过旧测试掩盖行为缺失。

## Integration

自己的独立worktree/branch从 integration/package-declaration-semantics 最新tip开始；路径与执行纪律见 C:/Users/maojiaxing/DevTools/msys/tmp/juice-package-implementation/README.md。不要写主checkout或其它agent文件。完成前merge最新integration、验证并commit，返回精确命令/exit/计数/限制和接口说明；由merger核对合入并写Resolution关闭。前置票未完成前不要使用假接口声称验证通过。
