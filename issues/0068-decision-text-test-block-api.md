---
title: 决策：文本 test-block 转换的跨包 API 形状
status: open
labels: [wayfinder:grilling]
assignee:
blocked-by: []
parent: 0065
---

> 2026-10-22 重锚：按新 juice（otter 实现）重写；旧 `Transpile_Plugin` / 旧发布面路径已更新为新实现的锚点。共同事实见 `0065` Notes。
>
> 2026-10-22 0067 定案：testing root LIB + `packages/` 成员；本票的 API 落位（root `modules/` 或另一个 member）与 0072 一并定。

## Question

文本 test-block 转换迁入 testing 后，对外以什么形状被新 juice（runtime + bootstrap vendored 副本）使用？

新实现事实：

- `Transpile_Plugin :: {name, version, modes, has_anchor, load_edges, transpile}`（`src/transpile_plugin.jai:75`）；`Transpile_Context`（86）携带 mode / path / next_test_number / load_targets / plugins / plugin_state；`Test_Entry`（`src/transpile.jai:44`）是转译簿记（name/number/line）。
- 内置实现 = `test_block_plugin()`（`src/transpile_plugin.jai:214`）+ `src/plugin.jai:builtin_test_block_plugin`（296）+ `default_transpile_pipeline`（392）；插件面发布 = `JUICE_CORE_LOAD_FILES` 四件（`src/publication.jai:83`）逐字复制到 `target/modules/juice_internal/plugin_face/`，`juice_core` 以模块相对 `#load` 消费。
- 行号保真门由 runner 强制（`enforce_line_fidelity` 455 / `transpile_source` 487）；跨文件状态经 `plugin_state` 槽。

候选：

- (a) host-neutral 纯函数 API（输入 source / path / 模式 / 编号，输出 view + `Test_Entry` 清单 + 诊断；自带最小 token 化或接受宿主 token），juice 侧薄适配成 `Transpile_Plugin`；
- (b) 直接迁 juice 的 `Transpile_Plugin` 实现（testing 依赖 juice 类型，存在编译环风险）；
- (c) 其他（说明）。

同时定清：token / 编辑原语归属、行号保真（spec §8.1；ADR 0005 契约）由谁强制、EXPAND/STRIP 两模式与 `next_test_number` 状态如何跨调用传递、`Test_Entry` / 诊断类型归属（testing 自类型 vs juice 发布面类型）。

**Done when:** API 形状、依赖方向、vendored 副本同步面（文件与断言部位）写清；juice 适配器与 bootstrap 副本的接口边界可直接实现。

## Progress

（2026-10-22 grilling，未定案；票保持 open + unclaimed，返回 frontier，供后续 session 续问）

- Q1（API 形状）已问，推荐 A = host-neutral hook + 共享内核；候选 B = 整文件纯函数；C = 整文本转译内核迁移。用户尚未拍板。
- 已核实事实：`test_block_transpile` 只认领 header 并进入 body（`scan.index = brace_index + 1`，`depth += 1`），load 插件继续在 body 内 dispatch；STRIP 整块消费；行号保真门在 runner（`transpile_source` → `enforce_line_fidelity`）；插件 name/version 进 `transpile_view_key`。
- 待下一轮：中立类型 / lexer 的单源方式（juice 复用 vs prefixed 副本）；转换文件落位（root `modules/` vs `packages/` 成员）；vendored 同步与发布树件数；行号保真 / `next_test_number` / `Test_Entry` 归属确认。
