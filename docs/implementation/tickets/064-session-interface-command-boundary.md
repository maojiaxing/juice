---
id: 064
title: Command lifecycle session 接口与命令边界
labels: [wayfinder:grilling]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [067]
---

# 064: Command lifecycle session 接口与命令边界

## Question

Command lifecycle session 的接口与命令边界怎么定？

已拍板（2026-10-22）：session 拥有 full protocol（plugin prepare、resolver、context、PRESTEP host、PRESTEP dispatch、before → at | builtin → after）；命令只给 prelude 与 stage body；`begin` 含 host；模块并入 `src/lifecycle.jai`；术语 = Command lifecycle session；零文件 `juice test` 与 build 统一校验。

要定：

- `begin` 的输入/输出与失败语义；它和 build prelude（revalidate + LNK1104）与 test prelude（prune + collect）的顺序。
- `run_stage` 的调用形状：stage 枚举、state 指针、built-in body 如何传入；at hook 替换 built-in 的判定点。
- `build_prepared_workspace` / `test_prepared_workspace` 是否保留为薄测试 seam，还是测试改走 session。
- 失败/诊断如何从 session 回到 dispatcher（`HANDLER_FAILED` 路径不变）。
- 零文件 `juice test` 的精确顺序：prune / collect / begin / host / 短路。
- `prepare_workspace_plugins` / `resolve_package_plugins` 在 session 内的归属。

相关锚点：`src/commands/build.jai:397-516`、`src/commands/test.jai:519-653`、`src/lifecycle.jai:326-364`、`src/plugin_host.jai:90-146`。Stage state 类型由 065 定；本票只定编排。

## Answer

**1. 顺序 = prelude → begin → zero-work 短路 → stages。** 命令 prelude 是显式调用，不做 callback：

- build：`ensure_workspace_prepared` → `revalidate_build_plans` → LNK1104 检查/hand-off → `begin` → zero-plan 短路 → `run_stage(.PRESTEP, builtin = null)` → `run_stage(.TRANSPILE, build_transpile_front)` → `run_stage(.COMPILE, build_compile_loop)`。
- test：`ensure_workspace_prepared(force_dependencies = true)` → `prune_test_scratch` → `collect_test_files` → `begin` → zero-file 短路 → `run_stage(.PRESTEP, builtin = null)` → `run_stage(.TRANSPILE, test_transpile_front)` → `run_stage(.COMPILE, test_compile_front)`。
- `begin` 在两条命令的 zero-work 短路之前；零 target build 与零文件 test 都会 spawn host（声明了成员插件时），统一校验 member version/options。零工作时 host 的 PRESTEP effects 计算后丢弃，只保留校验/失败语义。
- 这是有意的行为变化：零文件 `juice test` 现在会失败于非法声明；零 target `juice build` 也从“不 spawn host”变为“spawn host 并校验”。其余行为等价。

**2. `begin` 的输入/输出/失败。** 输入：`*Juice.Prepared_Workspace`、caller hook table（默认空）、host spawn seam（默认生产）、mode `"build"` / `"test"`。输出：session 值，持有 `Lifecycle_Context`、合并后的 dispatch table、`Prestep_Stage_State`（065 改名后的类型）、`Resolved_Plugins`（pipeline / hook table / lint）、`Plugin_Prepare_Result` / registration path、ok。内部：`prepare_workspace_plugins` + `report_plugin_prepare` + `resolve_package_plugins`；构造 context / diagnostic sink；`merge_hook_tables`；填 `Prestep_Stage_State` root / member dirs；声明成员时跑 host + `apply_plugin_host_effects`。失败：打印既有 `[juice ERROR]` 诊断并返回 false；不新增 error 类型。`begin` 不派发 PRESTEP before/after；那是 `run_stage(.PRESTEP, builtin = null)`。

**3. `run_stage`。** 形状：`run_stage(session, stage, state, builtin)`；`state` 是 typed stage state 指针，`builtin` 是 `#type (state: *T) -> bool` 或 null。session 设 `ctx.stage` 与 context 的 stage-state 槽（`*Stage_State`，具体形状由 065 定），按 `before → at? at : builtin → after` 派发；false 或新增 ERROR 诊断 fail-fast。PRESTEP 用 `builtin = null`，只跑 before/after；PRESTEP 上 at mount 的处置留给 066。

**4. 现有编排函数。** 保留 `build_prepared_workspace` / `test_prepared_workspace` 作为 session 的薄适配器（prelude + `begin` + zero-work + `run_stage`），现有测试继续用它们注入 fake；session 另加直接测试。适配器内不再复制 hook 顺序。

**5. 失败/诊断。** session 返回 bool；诊断走既有 `[juice ERROR]` 与 lifecycle diagnostic sink；命令返回 false；dispatcher 仍映射 `HANDLER_FAILED`。无新 error enum。

**6. 归属。** `prepare_workspace_plugins` / `report_plugin_prepare` / `resolve_package_plugins` 只在 `session.begin` 调用；命令不再直接调用。session 把 registration path 与 resolved pipeline / hook table 暴露给 stage state。
