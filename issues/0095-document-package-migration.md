---
title: 实施：产品规格与完整人工迁移示例
status: open
labels: [ready-for-agent]
assignee: maojiaxing
parent: "0087"
blocked-by: ["0089"]
---

## Goal and contract

父规格 [0087](0087-spec-package-declaration-semantics.md) 是权威，相关已关闭决策为补充；本票必须交付以下可观察行为。

Decisions 29和Testing 5/8。统一新规格删除冲突旧描述；逐字段迁移表明确type/targets/main_file、依赖version/package搜索、plugin成员名猜测/version、build_script去除，workspace保留。依据真实schema-handoff编写最终public写法，E01–E10全部含目录树/完整PACKAGE/源码必要内容/cwd命令/成功失败预期/规则，覆盖最小程序/模块/多程序/纯和根工作区/PATH+WORKSPACE/Git context/lint/jaix+普通API/零产物。A01–A16对照，已运行证据仅引用真实日志，尚未执行要明确。保留decision追溯，不扩到另一Testing effort或兄弟repo。

## Ownership

docs/spec.md、docs/migrations/package-declarations.md、CONTEXT.md、GLOSSARY.md。

## Validation

用发布模块真实编译示例由0096验收票执行；本票先检查所有声明类型与真实schema一致及链接/字段无冲突，不虚构运行成功。

读 tdd 技能，在此前用户已确认的CLI/现有函数测试边界逐行为red-green，不再请求边界批准。读完整修改文件，避免无约束Any/void。不要删除、降级或整体跳过旧测试掩盖行为缺失。

## Integration

自己的独立worktree/branch从 integration/package-declaration-semantics 最新tip开始；路径与执行纪律见 C:/Users/maojiaxing/DevTools/msys/tmp/juice-package-implementation/README.md。不要写主checkout或其它agent文件。完成前merge最新integration、验证并commit，返回精确命令/exit/计数/限制和接口说明；由merger核对合入并写Resolution关闭。前置票未完成前不要使用假接口声称验证通过。
