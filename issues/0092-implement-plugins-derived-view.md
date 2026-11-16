---
title: 实施：独立插件来源与包级派生视图
status: closed
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

## Resolution

- 实现分支 `implement/plugin-derived-view`（基于 `49c327f`），提交 `6996f55`（可编译基线）、`d1bed88`（来源/模块选择/入口诊断/options/ABI）、`19f64c8`（重复启用、普通角色、builtin 三态、update、单次 prepare）、`f34abec`（私有输出规则绑定第三方宿主契约）、`91eec8f`（旧断言迁移、缺口覆盖、缓存命中守卫恢复）、`4ab7aa8`（合入最新集成分支）。经 `b3d0ad5`（--no-ff）合入 `integration/package-declaration-semantics`。
- 插件模型：`JUICE_PLUGIN_ABI_VERSION :: 1` 与 `Juice_Plugin.abi_version` 取代用户声明 version；`Plugin_Config{id, options}`（去掉 version，生成文本为 `.{ id = "...", options = Option_Row.[...] }`）；`Plugin_Declaration` 携带显式 `source`（`.BUILTIN`/`.PATH`/`.WORKSPACE`/`.GIT`）、显式 `module` 选择与 `options`，`.PATH` 来源必须是声明包的同级目录。插件入口为提供方的唯一公开模块，零/多候选失败，ABI 检查独立于普通依赖角色。
- 派生视图：`Prestep_Stage` 增加 `generated`/`package_root`/`derived_root` 与 `prestep_add_generated`/`prestep_write_derived`/`prestep_register_generated`/`prestep_derived_source_for`；`Generated_Source{logical_path, physical_path}`。视图只保留当前输出、落在消费包 target 私有区、逻辑路径保留、冲突失败、源与共享检出只读；`substitute`/`drop`/`generated` 显式注册，辅助文件不成为公开根入口。
- 行为边界（A05/A06/A07/A08，决策 21–25 与 15）：省略插件 = 内建 `[load, test-block]`；`[]` = 全部禁用（同一源码因此不再编译，属声明的后果）；非空 = 完全替换不补默认。options 重复/未知/缺必填/非法 hook 在 hook 前失败；stage 顺序与列表顺序固定；每个所选包自身仅一次 prepare 与私有 view；未选成员与依赖中的插件不激活；`update` 不跑 hook；保留 lint/test-block/生命周期贡献，lint 与 jaix 普通 API 分离。
- 修复的真实缺陷：命令的单次插件解析未把 `pipeline_omitted=false` 透传到每文件转录，导致 `plugins = Plugin_Declaration.[]` 仍执行内建 test-block 转换（现经 `Transpile_Stage` → `transpile_test_file` → `Transpile_Context.plugins_omitted` → `resolve_pipeline` 贯通）；转录前端的缓存命中守卫 `path_exists_as_regular_file(view_path) continue` 曾被删除，导致已存在视图被覆盖（已恢复；视图键本就包含解析后的流水线名称/版本/计数与省略语义，不会与旧视图冲突）。
- 旧断言按 0087 的退役决定迁移而非弱化：`tests/data/plugin-workspace-rank`、`-dup` 改为显式模块选择与独立 PATH 来源（`packages/extra` 增加其真实的第二公开模块 `helper.jai`，歧义用例需要真正多导出的提供方）；`plugin_scan_tests`、`plugin_host_tests`、`plugin_tests`、`jaix_plugin_tests`、`packages/juice-plugin-jaix/tests/jaix_plugin_tests.jai` 改为断言声明驱动的注册文本、独立 ABI 常量与角色分离；`test_command_tests` 的 `plugin_configs` 文本去掉 `version = ""`。
- 覆盖补齐（`tests/plugin_derived_view_tests.jai`，16 个可过滤 proc 全部绿）：未选成员插件隔离、Git 检出在 hook 后仍只读（`git status --porcelain` 空）、CLI 三态（build 与 test 各一组）、PATH 来源同级限制、重复启用与同模块双重普通引用失败、普通 API 另一导出可用、options 错误在 hook 前失败、单次 prepare、update 不跑 hook、视图规则与旧 stage 兼容。
- 门禁证据（Windows）：实现树 fresh `jai build.jai` exit 0；`test plugin_derived_` 16/0；完整 `test` 连续两轮 362 passed / 0 failed、EXIT 0（`target/evidence/fix4-full-1.log`、`fix4-full-2.log`），合入集成分支后再次 362/0 EXIT 0（`fix5-full-1.log`）。合入 `integration/package-declaration-semantics` 后在主检出独立复核：fresh 构建 exit 0；`plugin_derived_` 16/0、`module_` 3/0、`workspace_` 11/0、`declaration_schema_` 11/0、`dependency_resolution_` 14/0、`plugin_` 18/0；完整 `test` 连续两轮 362 passed / 0 failed、EXIT 0（`verify-0092-full-1.log`、`verify-0092-full-2.log`）。
- 全量日志中的 `path:line:col: expect failed` 行是 Testing 模块与 `module_tests` 自测的故意失败夹具（`definition_*` 与 `imported_*` 成对场景），数量与基线一致，不计入失败。
- 已知限制：仅 Windows 验证；POSIX 分支未实测；绝对路径未加 `\?\` 前缀，超深路径仍受 MAX_PATH 限制。另一项**既有**缺陷（在集成版 `target/juice-m0091d.exe` 上同样复现，非本票引入）：测试文件中 `#string NAME … NAME` 块内的 `test "…" { … }` 会被 test-block 转录器在本文件视图里改写，`plugin_derived_view_tests` 因此改为运行期拼接该夹具头。建议单独立票让原始 `#string` 块对转录器不透明。命令选包与参数组合留 0093，发布兼容与迁移文档留 0094/0095，验收留 0096；本票不构成 0087 全部交付。
