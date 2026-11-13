---
title: 实施：配套模块兼容与可搬迁安装
status: open
labels: [ready-for-agent]
assignee: maojiaxing
parent: "0087"
blocked-by: ["0093"]
---

## Goal and contract

父规格 [0087](0087-spec-package-declaration-semantics.md) 是权威，相关已关闭决策为补充；本票必须交付以下可观察行为。

Decisions 28及Testing 7；A16。源码自举debug/release发布新类型、协议、插件入口/支持源码为完整安装单元。可执行文件与相邻modules内部兼容标记失败要可观测，缺失/混装不从全局安装或同级开发源码fallback。所有发布生成源仍single source，不能永久手写第二份Public Package。不要改Testing迁移effort组织。

## Ownership

build.jai、src/publication.jai、src/juice_module.jai及必要加载兼容检查、tests/bootstrap_tests.jai、tests/publication_tests.jai、安装测试。

## Validation

实际debug+release bootstrap、配套exe/modules、仓库外独立临时工程build/run/test/update/offline，缺模块/混装/缺plugin support反例，记录编译器平台退出码；用本地Git，不依赖网络新分支。

读 tdd 技能，在此前用户已确认的CLI/现有函数测试边界逐行为red-green，不再请求边界批准。读完整修改文件，避免无约束Any/void。不要删除、降级或整体跳过旧测试掩盖行为缺失。

## Integration

自己的独立worktree/branch从 integration/package-declaration-semantics 最新tip开始；路径与执行纪律见 C:/Users/maojiaxing/DevTools/msys/tmp/juice-package-implementation/README.md。不要写主checkout或其它agent文件。完成前merge最新integration、验证并commit，返回精确命令/exit/计数/限制和接口说明；由merger核对合入并写Resolution关闭。前置票未完成前不要使用假接口声称验证通过。
