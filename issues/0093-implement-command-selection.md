---
title: 实施：命令选包、run 精确编译与 update/offline
status: open
labels: [ready-for-agent]
assignee: maojiaxing
parent: "0087"
blocked-by: ["0090", "0091", "0092"]
---

## Goal and contract

父规格 [0087](0087-spec-package-declaration-semantics.md) 是权威，相关已关闭决策为补充；本票必须交付以下可观察行为。

Decisions 17–20、23、27；A07/A10/A13/A14。所有build/run/test/update共用已完成的定位/选包/解析；command context接入0088失败可观测cache/state roots，清除旧默认路径兜底。完整参数与run一包预校验再执行；run显式program/default_run/唯一选择，只编所选程序并原样透传--后参数，不由build前置链编全部或重复插件。build全部程序、零程序校验依赖后明示不承诺模块全类型检查；test允许零产物/零测试/零匹配但不得隐藏声明依赖编译错误。update只刷新所选包完整图无编译hook，offline冲突早失败。按目录顺序首败停止报告已完成/失败/未执行，成员成功状态不跨包回滚。必要help接线，不重写无关clean/version。

## Ownership

src/commands/*.jai、src/dispatcher.jai、src/main.jai、src/test_runner.jai与命令测试；必要lifecycle接线。

## Validation

真实CLI从子目录、根/纯工作区、显式名字/路径/混用、零集合、同名、run未选坏程序不编译、透传参数、零程序/test、update/offline和多包首败范围；使用同目录exe副本避免Windows替换运行exe。

读 tdd 技能，在此前用户已确认的CLI/现有函数测试边界逐行为red-green，不再请求边界批准。读完整修改文件，避免无约束Any/void。不要删除、降级或整体跳过旧测试掩盖行为缺失。

## Integration

自己的独立worktree/branch从 integration/package-declaration-semantics 最新tip开始；路径与执行纪律见 C:/Users/maojiaxing/DevTools/msys/tmp/juice-package-implementation/README.md。不要写主checkout或其它agent文件。完成前merge最新integration、验证并commit，返回精确命令/exit/计数/限制和接口说明；由merger核对合入并写Resolution关闭。前置票未完成前不要使用假接口声称验证通过。
