---
title: 实施：新 Package 声明与求值边界切换
status: closed
labels: [ready-for-agent]
assignee: maojiaxing
parent: "0087"
blocked-by: ["0088"]
---

## Goal

实施 [0087](0087-spec-package-declaration-semantics.md) 的公开接口、省略状态、纯工作区容器和输入/内部模型分离（Decisions 1–7、9–10 的结构部分、21–22 的字段部分、26、28）。这是一项跨文件编译保持迁移；路径/XDG基础0088独立进行，本票不得编辑其文件。完整语义由后续票完成，但公开旧字段在本票即移除，不建立永久兼容解析。

## Exact change

- `src/module.jai` 的用户 `Package` 仅有 name/version/description/modules/executables/dependencies/plugins/workspace/default_run，唯一 PACKAGE，workspace 普通嵌套。modules/executables 共享简单 name/entry item。公开 source 为 PATH/GIT/WORKSPACE 互斥标记与载荷，Dependency 具有 name/source/modules 平铺选择（path/name/alias）；插件具有 builtin 或独立 source 选择与 options，不再用户填写 version 或按成员 id 推断来源。具体命名应简洁一致并记入交接。
- 普通字符串、数组、嵌套结构使用已实验的保留默认值，仅在求值转换边界解码。显式空仍是显式存在，纯 workspace 不产生根包。使用 docs/design/package-declaration-presence-check.md，不能把数组count==0当省略。
- `src/manifest.jai` 的 build_eval_code、Manifest_Parse_Result、parse_manifest_data_strict、load_package_manifest 切到新字段/协议并保留原始值、字段位置和错误诊断。未知老字段由编译器拒绝时保留真实错误，并给准确迁移指南路径/替代字段提示。不能声称源级拦截所有错误。
- 将运行时 dir、已解析路径等从公开 Package 移出到明确内部包/加载结果；load_package_manifest 返回该内部结果。当前 `Juice.Package` 同时用于用户输入与运行时，因此需要机械迁移其调用者及签名。可新增 `src/package_model.jai` 并接 main/build 的load；不要新建用户 Manifest/Some、发布兼容字段或无约束状态容器。
- `Workspace_Discovery` 必须区分有声明/有workspace/有根包，member内部模型持有声明根；后续00890工作区票会实现完整成员和选择。公开模块与程序集合独立，内部模型不可继续以互斥LIB/BIN阻止二者并存。
- `target.jai` 对新字段做固定入口与显式空基础解释，保留后续0090可扩展接口。`workspace.jai`、`dependency.jai`、`plugin*.jai`、`transpile_config.jai`、commands、lifecycle、metaprogram等旧Package消费者只做必要的编译适配，不在此票猜测新增高级语义。
- 迁移根package.jai、packages/**/package.jai、tests中的实际声明与内嵌字符串/对象构造。旧字段负例保留并加强诊断；旧语义断言按规格更新，不能删除整类测试/硬编码跳过以通过。

## Ownership

本票拥有 schema/manifest 和上述跨文件机械迁移，以及全部旧声明fixture形状迁移。不得修改 `src/path_safety.jai`、`src/xdg.jai`、`tests/declaration_paths_tests.jai`（0088所有）。不要修改docs/spec、迁移指南及其它effort。后续功能票仅在本票merge后启动，避免共享类型冲突。不要更改Testing公开接口/模块组织。

## Validation

先读 tdd 技能并按已确认真实CLI/现有函数边界逐例red-green。增加 `tests/declaration_schema_tests.jai`，覆盖实际新声明编译/求值、省略/空/非空、纯工作区、包+workspace、零产物、模块+多程序、旧字段拒绝及诊断。保持源码 `jai build.jai` 和全套自托管test可编译运行，逐项解释旧行为变化导致的断言迁移；不以孤立哨兵实验代替CLI。只使用自己的worktree目标目录。

## Handoff

将新公开类型和内部加载/模型/产物签名，新增load接线，已完成与后续语义清晰写到仓库外共享目录 `C:/Users/maojiaxing/DevTools/msys/tmp/juice-package-implementation/schema-handoff.md`。完成前merge integration/package-declaration-semantics最新tip，提交，返回精确证据，由merger关闭。不能把后续依赖/插件尚未完成说成完整规格交付。

## Resolution

- 实现提交 `aa752016e5fb11f39a6ba1f72718a739dab9a8aa`，已通过 `0252db77ec4147773e12d5719289457295a876c9` 串行合入 `integration/package-declaration-semantics`。
- 公开 Package 精确保留九字段，模块与程序独立；退休字段由真实声明编译器拒绝。运行时路径、presence、产物计划和工作区快照移到不发布的 `src/package_model.jai`。Testing 公开实现及其测试段未变。
- schema-2 求值协议保留省略/显式空/非空，Dependency、Plugin 和 Workspace 默认标记完整匹配。计算生成声明只改 `workspace.default_members` 的回归先失败后通过；不再丢失显式空默认成员。
- loader 成功前规范化并校验真实无链接包根、包身份、产物入口和 default_run。三个真实 `clean` 负例确认非法声明失败且保留目标文件。纯 workspace 可以通过准备入口，不产生根包或根产物。
- 插件省略状态贯穿解析、配置、转换与缓存；显式空禁用默认插件，非空列表完全替换。依赖生成 driver 显式传递发布模块目录，保留工作区三参数回调契约。
- 测试迁移保留并恢复准确错误文本/协议行号、完整静态发布字节基准和实际产物缺失断言。修复 publication smoke 中未断言子进程退出码造成的假绿；smoke 现以公开 `Juice.Package` 编译并运行。未删除整类测试、降低断言或新增跳过。
- 最终实现门禁 `package-schema-merge-gate-20261114-104810.json`：fresh `jai build.jai` exit 0；同目录 exe 副本完整 `test` exit 0，末尾 `339 passed, 0 failed`。合入后独立验证 `merged-0089-20261114-105246.json`：fresh build exit 0，schema 11/11，loader 3/3，full exit 0，221.47 秒，末尾 339/0，无被掩盖的子进程退出失败。
- 全量日志包含 594 个测试开始行（含嵌套 Testing 自测）。Testing 的 `finish()` 会重置计数，339 是末尾汇总，不是全部执行总数；不能据此推断新增测试遗漏。exe 副本均在实际进程退出后删除。
- 日志及 JSON 保存于仓库外 `C:/Users/maojiaxing/DevTools/msys/tmp/juice-package-implementation/schema-evidence/`；接口与分工交接见同级 `schema-handoff.md`。0088 三个受保护文件无变化，publication/plugin_host CRLF 保留，diff-check 通过。
- 后续边界：0090 完成成员展开/归属/cwd/选包/扫描剪枝，0091–0093 完成依赖、插件和命令语义，0094–0096 完成发布兼容、迁移文档及总体验收。本票不是 0087 全部交付。Linux/case-sensitive runtime 仍未验证，现有 WSL 工具链限制不变。
