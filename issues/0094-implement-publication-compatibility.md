---
title: 实施：配套模块兼容与可搬迁安装
status: closed
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

## Resolution

- 实现分支 `implement/publication-compatibility`（基于 `a5d550c`），提交 `cd2f951`（发布安装标记）、`dc9e3bf`（命令工作前拒绝不兼容安装）、`95a62e4`（把安装单元固定到仓库外安装）。经 `167fc46`（--no-ff）合入 `integration/package-declaration-semantics`。
- 安装单元由 `<modules>/juice_internal/install_manifest.txt` 描述，唯一写入方 `publish_install_set`（`build.jai` 与测试脚手架共用）：标记格式 `1`、兼容纪元 `1`（`INSTALL_COMPATIBILITY_VERSION`）、插件 ABI 从 `JUICE_PLUGIN_ABI_VERSION` 自身声明行读取、每个产物一个 16 位十六进制 FNV-1a 64 内容摘要。`install_artifact_paths(modules_dir)` 是已发布集合的唯一描述（Juice 面、Testing、juice_core、discovery 源、四个插件支持源）。
- `src/main.jai` 在任何命令工作前调用一次 `require_compatible_install(juice_modules_dir(), JUICE_PLUGIN_ABI_VERSION)`；失败硬性且单一原因：标记缺失/不可解析、纪元不匹配、插件 ABI 不匹配、标记描述的产物集合不同、产物缺失、摘要不匹配。无任何回退：标记只从 `<exe>/modules` 读取，不回落到全局安装或同级开发源码。
- 新增可消费接口：`install_manifest_path`、`install_artifact_paths`、`install_artifact_digest`、`constant_integer_value`、`publish_install_manifest`、`parse_install_manifest`、`verify_install`、`require_compatible_install`、`publish_install_set`，以及 `juice_module_path_in`/`testing_module_path_in`/`juice_core_module_path_in`。
- 验收（A16、决策 28 与 Testing 7）：debug 与 release 自举均 exit 0，发布新类型/协议/插件入口与支持源为完整单元；release 产物在仓库外用真实工程跑通 `build`/`run`/`test`/`update`/`build --offline`，并拒绝混装单元（exit 1，`content digest mismatch`）、恢复后再接受。仓库外工程放在机器临时根而非本仓库内，覆盖模块+程序+`default_run`+显式内建插件+PATH/GIT/WORKSPACE 依赖+workspace，`run` 输出 `path=21 git=34 member=55`、`test` 1/0。缺模块/混装/缺插件支持源的反例构建完整 `<exe>/../modules` 与 `<exe>/../src` 后仍失败，证明无回退。
- 红证据：关掉门禁行重建后 `test publication_install_cli` 为 1 passed / 4 failed，四个反例均报 `EXITED/0, want 1`，即门禁启用前损坏/混装安装被静默容忍；恢复门禁后 5/5 绿。
- 门禁证据（Windows）：`jai.exe build.jai` exit 0（合入后再次）；`jai.exe build.jai - release` exit 0；聚焦 `install_compatibility_`/`publication_` 16/0、`bootstrap_` 1/0、`declaration_schema_` 11/0、`plugin_derived_` 16/0、`command_selection_` 7/0、`workspace_` 12/0、`dependency_resolution_` 14/0；完整套件两轮 380 passed / 0 failed、EXIT 0（`full-1.log`、`full-2.log`），合入后第三次同样 380/0 EXIT 0（`full-final.log`）。主检出独立复核：fresh 构建 exit 0，`target/modules/juice_internal/install_manifest.txt` 按上述格式落盘（`compatibility 1`、`plugin_abi 1`、`artifacts 8`）；上述聚焦过滤全部 exit 0；完整套件两轮 380 passed / 0 failed、EXIT 0（`target/evidence/verify-0094-full-1.log`、`-2.log`）。
- 既有断言的迁移：两条已安装布局反例改为断言新的更早诊断（同一契约：exit 1、指名产物、不产生绿色运行），已在交接文档记录。
- 已知限制：同契约的两次构建彼此不可区分 —— exe 自身不带构建标识，故构建 A 的 exe 配上构建 B 的完整自洽 `modules` 在格式/纪元/ABI/产物集合一致时会被接受；按文件粒度的混装以及任何纪元/ABI/集合变化均被拒；发布内容变化时提升 `INSTALL_COMPATIBILITY_VERSION` 可闭合该情形。摘要为 FNV-1a 64，用于防混装而非签名。门禁无条件执行，故 `version`/`clean` 在损坏安装下也会被拒绝（有意，但对 0093 是用户可见变化）。仅 Windows 验证；POSIX 外部临时根未实测；外部验收假设 `git` 在 PATH；`MAX_PATH` 仍限制极深目录。迁移文档留 0095，验收留 0096；本票不构成 0087 全部交付。
