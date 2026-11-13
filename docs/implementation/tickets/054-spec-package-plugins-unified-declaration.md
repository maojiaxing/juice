---
id: 054
title: 设计修订：Package.plugins 统一声明面 + jaix 插件化
labels: [design]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [055]
---

# 054: 设计修订：Package.plugins 统一声明面 + jaix 插件化

**What to build:** 把本轮 grilling 达成的设计写成权威记录：`docs/spec.md` 的 2026-10-21 设计修订、新建 `CONTEXT.md` 的领域词汇、本 effort map 与 055-062 票链。本票不改生产代码。

## 设计摘要

- **统一声明面**：`Package.plugins = [{id, version, options}]` 是唯一的插件声明、配置、激活与排序面。声明 = 可用 + 激活 + 配置 + 顺序；运行时 `dependencies` 永不激活插件；`workspace.members` 提供成员包。成员插件 id = 成员包名；内置 id `load` / `test-block` 保留。v1 一个插件包只提供一个插件；声明 version 必须等于插件 version。
- **硬切**：`Package.jaix`、`Package.transpile`、`JAIX_CONFIG`/`JAIX_EXE`/`TRANSPILE_PLUGIN` 协议记录、`validate_jaix_marker`、`validate_transpile_pipeline` 移除；旧 package.jai 在 manifest 求值期以未知成员失败。属 breaking change（spec §11.12）。
- **face 默认值**：transpile 管线 = 声明的 transpile face；一个都没声明时用缺省 `[load, test-block]`。hooks 与 lint 只对声明的插件生效；lint 不再以 DEP 激活。
- **PRESTEP**：`before` 挂载、可堆叠、声明序、无内置实现；源替换表 + 剔除集，append-only、仅 root package、不新增文件；build 入口命中替换则直编并跳过探测；test 已收集文件命中替换则 EXPAND 于替换路径，`rel_path` / 编号 / `path_mapping` 不变。
- **配置**：`Config_Option.apply(options: *void, key, value) -> string`；插件负责类型化赋值；`validate` 在所有行应用后运行；`Juice_Plugin.options` 指向插件实例，hook 经 `plugin_state` 槽取同一指针。
- **校验**：manifest 解析期只做结构校验；语义校验（未知 id、版本、options schema、跨插件冲突）在 `resolve_plugin_configs` / merge 期。
- **Phase 2 host**：PRESTEP-only；命令级 prepare 扫描声明的成员插件并写注册；生成 host driver 嵌入输入、记录文件输出；test metaprogram 复用注册；零声明 hooks = 不 spawn。
- **Phase 1 / Phase 2**：Phase 1 = Candidate 1 + 4（静态内置 `juice-plugin-jaix`）；Phase 2 = Candidate 2（成员包 + host）。Candidate 3 出范围。

## Resolution

**2026-10-21，设计会话完成，docs-only。**

- `docs/spec.md`：新增顶部设计修订块；§0 概要/树、§1 原则 1、§2.1 Package 字段与迁移说明、§2.2 协议/校验、§2.3 专属层、§3.2/§3.3 成员与激活面、§4.6 命令阶段序、§5.1 Juice_Plugin/options、§5.2 声明驱动扫描/合并 vs 选择/lint/host、§6.1/6.2/6.3/6.4 PRESTEP 与状态槽、§7.1 排除集、§8.2 lint、新增 §8.3 jaix pre-step 插件、§9.2/§9.5 发布面、§10 自举注记、§11.12-16 风险、§12 设计锚点。
- `CONTEXT.md`：新建领域词汇（package/workspace、plugin、transpile/test 三组）。
- `docs/implementation/jaix-plugin-map.md`：新建 effort map。
- `docs/implementation/tickets/054-062`：本票链。

**未改**：`src/`、`build.jai`、`package.jai`、`packages/`、测试。

**Verification**：docs-only；检查 spec 中旧记录（`JAIX_*` / `TRANSPILE_PLUGIN` / `jaix marker`）只出现在设计修订、历史注记或 §8.3 的 jaix 插件描述中；054-062 依赖链闭合。

**Out of scope**：任何代码实现；旧 juice 仓；Candidate 3。
