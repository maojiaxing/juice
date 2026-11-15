---
title: 验收：全链路示例与发布覆盖
status: open
labels: [ready-for-agent]
assignee: maojiaxing
parent: "0087"
blocked-by: ["0094", "0095", "0097", "0098"]
---

## Goal and contract

父规格 [0087](0087-spec-package-declaration-semantics.md) 是权威，相关已关闭决策为补充；本票必须交付以下可观察行为。

0087完整故事/29Decisions/16验收组和10示例。把现有新增覆盖映射到A01–A16与E01–E10，补缺失行为的真实CLI测试，不能只报告旧339条通过。所有例用真实新Juice模块编译并执行，临时本地Git和隔离XDG。debug/release源码自举、相邻modules发布、仓库外安装三条路径全跑。Windows和可用大小写敏感FS各执行对应路径契约；平台不可用明确未验，不当pass。完整退出码/编译器/提交/cwd/摘要/skip证据。

## Ownership

新增tests/package_declaration_acceptance_tests.jai及tests/test_support.jai必要扩展，docs/migrations的证据表和仓库外完整日志；发现生产bug应给具体修复并验证。

## Validation

全套自托管tests、所有新CLI关键链路、安装反例、文档示例可运行；不靠0命中过滤、内部快照、删测试或skip充数。验收完成后仍需code-review双轴及单implementer修复所有发现。

读 tdd 技能，在此前用户已确认的CLI/现有函数测试边界逐行为red-green，不再请求边界批准。读完整修改文件，避免无约束Any/void。不要删除、降级或整体跳过旧测试掩盖行为缺失。

## Integration

自己的独立worktree/branch从 integration/package-declaration-semantics 最新tip开始；路径与执行纪律见 C:/Users/maojiaxing/DevTools/msys/tmp/juice-package-implementation/README.md。不要写主checkout或其它agent文件。完成前merge最新integration、验证并commit，返回精确命令/exit/计数/限制和接口说明；由merger核对合入并写Resolution关闭。前置票未完成前不要使用假接口声称验证通过。

## Final review checkpoint

实现与验收补充已通过 `e1743fb` 合入，但本票仍开放。固定 tip 的独立完整套件第一轮为 380/0、EXIT 0；第二轮卡在本地 MSYS Git 自动维护相关等待中，尚无退出码，不能计为通过。

最终双轴审查及独立 Windows/Linux CLI 揭示了此前测试未覆盖的规格缺口，包括成员归属、包级导入隔离、同包模块测试重复加载、插件派生源码消费、名称/XDG校验等。Linux 的真实 debug/release 自举和部分路径检查已成功，不再将其概括为平台不可用；安装测试另有复制丢失执行权限的夹具缺陷。

全部修复由 [0098](0098-fix-package-declaration-final-review.md) 的同一实施者承担，逐项回归并补证后才能关闭本票。既往绿灯不豁免这些失败，也不反向改写当时的验收记录。
