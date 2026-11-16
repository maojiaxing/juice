---
title: 实施：命令选包、run 精确编译与 update/offline
status: closed
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

## Resolution

- 实现分支 `implement/command-selection`（基于 `e161b55`），提交 `5913448`（命令选包贯通 build/run/test/update）。经 `8a7485a`（--no-ff）合入 `integration/package-declaration-semantics`。
- 新增 `src/commands/selection.jai`：`Command_Flags`（`request` 的 `all_members`/`names`/`paths`、`offline`、`positionals`、`separator_arguments`、`has_separator`）、`parse_command_flags`、`resolution_mode_for`、`Selected_Package`、`Command_Selection`、`select_command_packages`、`root_package_of`、`Package_Batch`（`completed`/`failed`/`not_executed`/`total`）与 `package_batch_fail`/`package_batch_report_failure`。`Package_Selection` 与 `select_workspace_packages`（0090）成为唯一选包入口，`Dependency_Preparation_Request.selection` 与 `Workspace_State.selection` 承载结果。
- 命令接线：`build_package(prepared, package, plans, ...)`、`Build_Transpile_Stage.package_root`/`.plans`、`Build_Compile_Stage.plans`、`build_plan_entry(...)`；`test_package(prepared, package, pattern, ...)`、`collect_test_files(prepared, package_root)`；`run` 的 `select_run_plan`/`launch_selected_plan`/`run_artifact_plan`；`Command.flag_help` 与 `print_command_usage`。
- 行为边界（A07/A10/A13/A14，决策 17–20、23、27）：build/run/test/update 共用定位+选包+解析；命令上下文取 0088 的失败可观测 cache/state 根，删除旧默认路径兜底。`run` 单包预校验后再执行，支持显式程序名、`default_run`、唯一选择三种方式，只编所选程序并原样透传 `--` 后参数，不重复插件准备。`build` 构建全部程序，零程序时仍校验依赖并明示不承诺模块全类型检查。`test` 允许零产物/零测试/零匹配但不隐藏声明依赖编译错误。`update` 只刷新所选包完整图、不跑编译 hook，offline 冲突早失败。按目录顺序首败停止并报告已完成/失败/未执行，成员成功不跨包回滚。
- 真实缺陷修复：空扫描根曾上溯到盘符根（显式选包路径下 `package.dir == ""`），以 `root_package_of` 加 `collect_test_files`/`test_package` 的硬校验修复；零程序包曾绕过插件校验（回归 0092 的 `bad-manifest-plugin-id`），`build_package` 现始终先做声明校验、再输出“无程序”说明；`prestep_add_substitution` 的保留源规则在夹具上生效而那处 substitution 从未创建源文件，夹具补齐（规则本身即 0092 所述）；`--workspace` + `-p` 冲突由裸 usage 行改为 `select_command_packages` 的结构化诊断。
- 旧断言按 0087 迁移而非弱化：`run` 的 build 前置链与按包名猜程序、`nothing to build` 文案、零目标时 `target/` 不存在的断言（依赖校验现在会创建 `target/packages`）、零包选择现在会失败、help/usage golden 文本。
- 门禁证据（Windows）：实现树 fresh `jai build.jai` exit 0；`command_selection_` 7/0、`run_selection_` 12/0、`workspace_` 12/0、`dependency_resolution_` 14/0、`plugin_derived_` 16/0、`declaration_schema_` 11/0；完整套件两轮 365 passed / 0 failed、EXIT 0，合入集成分支后再次 365/0 EXIT 0。主检出独立复核：fresh 构建 exit 0；上述聚焦过滤全部 exit 0（`command_selection_` 7/0、`run_selection_` 12/0、`workspace_` 12/0、`declaration_schema_` 11/0、`plugin_derived_` 16/0、`dependency_resolution_` 14/0、`plugin_` 18/0）；完整套件两轮 365 passed / 0 failed、EXIT 0（`target/evidence/verify-0093-full-1.log`、`-2.log`）。
- 全量日志中残留的 6 条 `expect failed` 行是 Testing 模块自测的故意失败夹具，与 0092 基线一致。
- 已知限制：仅 Windows 验证，无 Linux/大小写敏感文件系统执行；“run 只编所选程序”以不可解析的兄弟程序证明，未覆盖按程序的插件 hook 差异；批量报告只在多包选择时打印，单包失败走普通诊断；已成功包不回滚（按设计）；`clean`/`version` 有意未改；`run` 复用 build 的编译链，故会打印该程序的编译行；零程序 `build` 现在会创建 `target/packages`。发布兼容留 0094，迁移文档留 0095，验收留 0096；本票不构成 0087 全部交付。
