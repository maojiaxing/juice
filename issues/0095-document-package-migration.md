---
title: 实施：产品规格与完整人工迁移示例
status: closed
labels: [ready-for-agent]
assignee: maojiaxing
parent: "0087"
blocked-by: ["0094"]
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

## Resolution

- 实现分支 `implement/package-migration-docs`（基于 `bbaba74`），提交 `67d1646`（迁移指南）、`1b3fff7`（产品规格统一）、`691a4f6`（CONTEXT 术语）。经 `4e6b3c5`（--no-ff）合入 `integration/package-declaration-semantics`。无 `src/`/`tests/` 改动，故未跑完整套件；合入后 `jai build.jai` exit 0（`target/evidence/post-merge-build.log`）。
- `docs/migrations/package-declarations.md`（新，910 行）：`Package`/`Dependency`/`Plugin`/`workspace`/已删除行为逐字段迁移表、省略与显式空矩阵、名称与路径规则、依赖与插件语义、安装单元、E01–E10 完整示例、A01–A16 对照、决策 1–29 追溯（含代码锚点）、已知限制与证据索引。`src/manifest.jai:276` 与 `:416` 两条诊断指向的路径现在真实存在且内容与解析器一致。
- `docs/spec.md`：以新的权威 §2（§2.1–§2.10）替换旧的兼容面描述，并修正 §0/§1/§3/§4/§5/§8/§9/§11/§12/§13 中与决策冲突的旧描述（LIB/BIN 角色、`targets`/`main_file`、六命令注册表、run 的 build 前置、传递闭包、插件版本门禁、成员名猜测、anchor）。`CONTEXT.md` 更新 Dependency、Plugin declaration、Plugin id、Plugin prepare，新增「声明三态」；`GLOSSARY.md` 已是新词汇，未改。
- E01–E10 全部按真实安装单元（exe + 相邻 `modules`，隔离 XDG 根）在仓库外执行并记录：E01 build 0/run 0；E02 build 0/run 1；E03 build 0、run(default_run) 0、run adder 0、run nosuch 1；E04 纯工作区 build 0、`--workspace` 0、`run --workspace` 1；E05 根包+工作区 root build 0、`--workspace` 0、member build 0、root-default/`-p`/`--package-path` 0、未知名字 1；E06 PATH+WORKSPACE run 0、环探针 1；E07 Git 首次 0/复用 0/update 0/更新后 0/offline 0；E08 lint test 0（含告警）；E09 jaix+普通 API build 0/run 0/角色冲突 1/重复启用 1；E10 零产物 build 0/run 1/test 0。另有旧字段拒绝、按名搜索与插件猜测移除、产物解析失败、连字符自动名、空声明/空工作区/`default_run`、插件三态、空依赖模块清单、消费方与提供方模块导入不对称等探针。复现脚本 `target/evidence/reproduce-examples.sh`，逐条 cwd/参数/退出码见 `migration-examples-index.txt`（合入后重放：25 条 exit 0、8 条有意 exit 1）。
- A01–A16 对照表逐组标注「已执行 / 部分 / 未执行」，未执行项（A08、A11、A12、A16；A02/A03/A04/A06/A07/A09/A10/A13/A15 部分）明确写明由 0092/0094/0096 覆盖或本次未跑，未把未执行冒充通过；无 Linux 执行，不作跨平台声明。
- 本票在写文档过程中发现一个真实规格缺口而非措辞问题：被构建包自身的公开模块无法按公开名被本包程序/模块引用（`#import "calc"` 失败，只有 `#load` 可用），与 story 37、决策 11「最终导入名不得覆盖本包模块」、A04「同包模块可用」冲突。已在仓库外以真实安装单元复现，另立 [0097](0097-implement-own-module-imports.md) 修复，并成为 0096 的前置；0095 文档先把该行为如实记入 §4.3 与「已知限制」，由 0097 改成交付行为并同步文档。
- 其余遗留观察（未编辑）：`packages/juice-plugin-lint/package.jai`、`packages/juice-plugin-jaix/package.jai`、`packages/juice-plugin-jaix/module.jai` 存在描述旧模型的过时注释（“LIB, no targets”“declaration must repeat version”）；建议在 0096 或独立小票清理。
- 已知限制：无 Linux/大小写敏感文件系统执行；文档只覆盖 Windows 上实际跑过的命令；A 组中标注为未执行的组不构成验收证据。验收留 0096；本票不构成 0087 全部交付。
