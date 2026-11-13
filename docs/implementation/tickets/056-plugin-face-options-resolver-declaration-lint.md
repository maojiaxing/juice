---
id: 056
title: 插件面：options apply + registry/resolver + 声明驱动 lint
labels: [implementation]
status: closed
assignee: maojiaxing
blocked-by: [055]
blocks: [057]
---

# 056: 插件面：options apply + registry/resolver + 声明驱动 lint

> 上游规格：`docs/spec.md` §5.1/§5.2/§8.2/§11.15（2026-10-21 设计修订）。本票把 055 的声明面变成可解析、可配置、可按声明序执行的插件面；不接 PRESTEP、不引入 jaix。

**What to build:** 让 `Package.plugins` 真正驱动插件发现、配置与排序：`Juice_Plugin.options` + `Config_Option.apply`；`merge_plugins` 返回 registry；新增 `resolve_plugin_configs` 产出有序 transpile 管线/钩子表/options；成员插件扫描改为声明驱动；lint 从根 DEP 激活迁到声明。

## 交付

1. `src/plugin.jai`
   - `Juice_Plugin` 增加 `options: *void`；`get_juice_plugin` 的派生插件把 `options` 指向自身。
   - `Config_Option` 增加 `apply(options: *void, key: string, value: string) -> string`；`config_option` 构造器同步扩展；未知 key = 错误；所有行应用后跑 `validate`。
   - `Plugin_Config` / `Option_Row`（插件面类型，host 与静态路径共用）；`Merged_Plugins` 保留 registry（`[] *Juice_Plugin`）而不是只留 `[] Transpile_Plugin`。
   - `merge_plugins`：合并/查重语义不变；返回 registry + lint 列表 + 诊断。
   - 新增 `resolve_plugin_configs(registry, configs) -> Resolved_Plugins { pipeline, hook_table, diagnostics, ok }`：按声明序过滤；transpile face 入管线（无 transpile 声明 = 缺省 `[load, test-block]`）；hooks 入钩子表（槽对齐）；options 按 schema apply/validate；未知 id / version 不匹配 / 一包多插件 / 选项错误 = 诊断 + ok=false。
2. `src/plugin_scan.jai`
   - `scan_workspace_plugins` 改为按 `Package.plugins` 的成员插件 id 定位成员包（id = 包名），不再遍历根 DEP；扫描顺序 = 声明序 → 包内 DFS 词法序。
   - 已声明成员写 import shim（复用成员链接）；内置 id 跳过扫描；未知成员 = 响亮错误。
   - 注册文件 codegen 顺序改为声明序。
3. `src/transpile_config.jai`
   - `resolve_transpile_pipeline` 委托 `resolve_plugin_configs` 或退役；`build_plan_entry` / `test_transpile_front` 使用解析结果，不再各自解析。
4. 根包 / lint 迁移
   - `package.jai`：`workspace.members` 保留 `packages/juice-plugin-lint`；`dependencies` 移除 lint 项；`plugins` 增加 `{id="juice-plugin-lint", version="0.1.0"}`。
   - `packages/juice-plugin-lint/module.jai`：`plugin.id = "juice-plugin-lint"`；lint 规则名不变。
   - 成员链接/import shim 由插件 prepare 覆盖（build 与 test 都需要）。
5. 测试
   - resolver 矩阵：face 默认值、声明序、未声明不参与、未知 id、版本不匹配、options apply/validate、重复键。
   - 扫描矩阵：声明驱动、成员定位、shim、注册顺序、未知成员失败。
   - lint 全链 E2E：根包声明驱动、无 DEP 激活、警告照常、安装布局前形态。
   - fixture 更新；计数基线随票记录。

## 验收

- `jai build.jai` debug exit 0；根 test 全绿。
- 根包 lint 在无同名 DEP 的情况下经 `Package.plugins` 声明生效（E2E 断言警告 + 成员根套件）。
- `resolve_plugin_configs` 是管线/钩子/options 的单一落点；`transpile_view_key` 的管线描述与解析结果一致。
- 未声明插件不跑 hooks/lint/transpile（负向测试）。

## Out of scope

- PRESTEP / 源替换表（057）。
- jaix 插件（058）。
- host / 命令级 prepare 的注册复用（060）。

## Resolution

实现摘要（按交付项）：

1. `src/plugin.jai`
   - `Juice_Plugin.options: *void`（派生插件在 `get_juice_plugin` 里指向自身；内置也指向自身）。
   - `Config_Option.apply(options, key, value) -> string` + `config_option` 四参构造；apply 负责把字符串行写进类型化字段（未知 key 返回错误），resolver 在所有行应用后跑 `validate`。
   - 新增插件面共享配置类型 `Option_Row {key, value}` / `Plugin_Config {id, version, options}`（host 与静态路径共用；host driver 可仅 `#import "juice_core"` 消费）。
   - `Merged_Plugins` 改为 `{registry: [..] *Juice_Plugin, lint_plugins, diagnostics, ok}`：merge 保留全部 faces，不再预过滤 pipeline/hook 表。
   - 新增 `Resolved_Plugins {pipeline, lint_plugins, hook_table, slot_options, diagnostics, ok}` 与 `resolve_plugin_configs(registry, configs)`：按声明序过滤；transpile face 入管线（没有任何 transpile 声明 = 缺省 `[load, test-block]`）；hooks 入钩子表且 `slot_options` 与 registration 对齐（每项 = 该插件 options 指针，供 host 填 `plugin_state`）；options 按 schema apply/validate；未知 id / 版本不匹配 / 一声明匹配多插件（一包多插件）/ 重复声明 / 重复 option key / 未知 option / apply/validate 拒绝 = 诊断 + ok=false；未声明插件不贡献任何 face。
2. `src/plugin_scan.jai`
   - `scan_workspace_plugins` 改为声明驱动：只遍历根包 `Package.plugins`；内置 id（`load`/`test-block`）跳过；其余 id 按“成员插件 id = 包名”定位 `workspace.members` 成员包（未知成员 = 致命诊断）；成员包按 `scan_plugin_package` 的包内 DFS 词法序扫描，且须恰好提供一个锚定插件（0/多个 = 致命诊断，v1 一包一插件）；已声明成员经 `link_workspace_member_dependency` 写 import shim；根 DEP 不再参与激活。注册 codegen 顺序 = 声明序。
   - `Plugin_Scan_Diagnostic` 增加 `fatal`；读源失败标 fatal；跨包同名模块仍按探测序裁定（非致命）。
3. `src/transpile_config.jai`
   - 退役 `resolve_transpile_pipeline`；新增 `resolve_package_plugins(decls)`（命令侧适配器：按 Phase-1 边界只把内置 id 转成 `Plugin_Config` 后委托 `resolve_plugin_configs`）与 `plugin_configs_from_declarations`（全量转换，供测试 metaprogram 嵌入）。
   - `build_plan_entry` 改为接收解析后的 pipeline（`Build_Transpile_Stage.pipeline`，commands/build 解析一次）；`test_transpile_front` 解析一次并存入 `Test_Transpile_Stage.pipeline`。
4. 根包 / lint 迁移
   - `package.jai`：`dependencies` 移除 lint 项；`plugins = [{id="juice-plugin-lint", version="0.1.0"}]`；`workspace.members` 保留。
   - `packages/juice-plugin-lint/module.jai`：`plugin.id = "juice-plugin-lint"`，options 指向自身。
   - `validate_plugin_declarations` 过渡门从 `src/manifest.jai` 移除（语义校验由声明驱动扫描 + resolver 接管）。
   - build 在零 plan 早退之前做插件准备（声明扫描 + 解析），因此零 plan 包的未知插件 id 也会响亮失败；test 的 COMPILE front 扫描/写注册文件，并把声明 configs 嵌入 metaprogram；metaprogram 在 `#run` 内 merge 内置+扫描 registry 后 `resolve_plugin_configs`，lint 只观察 `resolved_plugins.lint_plugins`。

验收证据：

- `jai build.jai`（debug）exit 0。
- `rm -rf target/transpile && ./target/juice.exe test` exit 0；`310 passed, 0 failed`；直跑 SKIP 2（既有自托管 posture）。found 基线 = 最大 `juice_test_N` 489 + 手写 `note_suite_*` @test 5 = **494**（055 基线 484，本票 +10）。
- 根包声明驱动 lint（无同名 DEP）：`LINT_FULL_CHAIN_PACKAGE_SOURCE` 已改为 `workspace.members` + `Package.plugins`，E2E 测试 `E2E: the real member plugin lints a scratch workspace and the tests still run`（警告 + `2 passed, 0 failed` + registration 落盘）、`E2E: the real member package root runs its own suite green`（成员根套件 3 passed）、安装布局 `E2E: an installed juice runs the real member plugin and lints a scratch workspace` 全绿。手工复跑（scratch root，无 DEP）stderr 输出 `tests/bad_name_tests.jai:3,12: Warning: [juice lint] test procedure name must be snake_case: BadName`，stdout `[test] BadName` / `[test] test_good_name` / `2 passed, 0 failed`，exit 0；`target/packages/juice-plugin-lint.jai` shim 与 `target/plugins/registration.jai` 均生成。
- 单一落点与 key 一致：`The resolved pipeline is exactly the view key's pipeline description`（同 pipeline 同 key、重排换 key）；`resolve_plugin_configs` 是 build/test/测试 metaprogram/E2E driver 的管线/钩子/options/lint 唯一入口。
- 未声明插件不跑：`Resolver: declaration order drives the pipeline, hooks and lint; undeclared plugins never run`（未声明的 transpile/lint/hooks 全部缺席）+ `Resolver: face default`。
- resolver 矩阵：`Resolver: an unknown plugin id rejects`、`Resolver: a version mismatch rejects`、`Resolver: one package providing several plugins rejects (the v1 rule)`、`Resolver: a repeated declaration id rejects`、`Resolver: option rows apply through the schema, then validate runs`（含未知 key / 重复 key）、`Resolver: a plugin without a schema rejects option rows`、`Resolver: face default — no declared transpile face yields [load, test-block]`。
- build 侧插件准备：`Build plugin preparation fails on invalid declarations before the zero-plan short circuit`（未知 id / 内置版本不匹配都在零-plan 早退前失败）。
- 扫描矩阵：`工作区插件扫描：按 Package.plugins 声明序（优先于目录序），未声明成员与 DEP 不扫描`（含 shim 断言）、`跨包同名模块同级累积序裁定`、`跨包低探测序胜 + 命中位置守声明序`、`不可扫成员根 = ok=false`、`未知成员插件 id = 致命诊断`、`成员包必须恰好提供一个插件`、`内置 id 跳过扫描`、`真实仓库根声明面`。

Deviations：

1. 类型化 options 成员不能命名 `options`：`Juice_Plugin.options` 是基类字段，Jai 对 using 导入的同名成员直接报 redeclaration（spike 验证）。派生插件改用 `config`（fixtures/tests 同步）；`Juice_Plugin.options` 仍按规格指向插件实例，`Config_Option.apply/validate` 经 `*void` cast 回派生类型访问 `config`。规格只要求“类型化 options 成员”，未规定成员名。
2. “一包多插件”分两层把关：声明驱动的成员扫描强制每个已声明成员包恰好一个锚定插件（0/多个 = fatal + ok=false）；resolver 另对“一个声明 id 在 registry 中匹配多个值”做防御性拒绝（raw/unmerged registry 可达）。ticket 把该项列在 resolver 交付下，两处都实现并各有测试。
3. Phase-1 命令进程边界：`resolve_package_plugins` 只把内置 id 转成 config 交给 resolver（成员值不在命令进程）；成员插件的 version/options 校验发生在生成的测试 metaprogram 内（registry 含扫描值）。未知 id / 成员定位 / 一包一插件在命令侧扫描即失败（build 与 test 共用）。这与任务给出的 Phase-1 边界一致，未在命令进程伪造成员插件实例。
4. build 的插件准备放在零-plan 早退之前（仍不做任何编译）：这样 055 的 `bad-manifest-plugin-id` 零-plan E2E 语义（未知 id 失败）得以保留，错误阶段从 manifest 加载变为插件准备；该 E2E 已按新输出更新。
5. 坏 fixture E2E（`plugin-fixture-bad`）的行号保真观察点退化为“歧义插件不贡献 face”：重复 id 的 registry 在 resolver 处被拒绝后，两个重复插件都不入管线，故已无法同时观察 bad-mark 的两行编辑。行号保真门本身仍由 `tests/transpile_plugin_tests.jai` 的矩阵覆盖；E2E 现在固定 merge + resolver 双重拒绝与默认管线回退。
6. `scan_workspace_plugins` 现在会为已声明成员写 import shim（复用 `link_workspace_member_dependency`），build 也调用它 —— 带声明但零 plan 的包会创建 `target/packages/`（会话产物，clean 随 target 整删）。这是“成员链接/import shim 由插件 prepare 覆盖（build 与 test 都需要）”的落地。
7. 测试 fixture 迁移：`plugin-workspace*` 从根 DEP 激活改为 `Package.plugins` 声明；`plugin-workspace-rank` 按一包一插件规则重构为 alpha-first / zeta-extra / extra 三个各一个锚点的成员；`bad-manifest-plugin-id` 从“manifest gate”改为“插件准备期扫描失败”断言；manifest_tests 的四个过渡 Gate 测试移除（对应 loader 现在只做结构解析的语义）。
