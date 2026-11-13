---
id: 066
title: Member hook 面与 registration state
labels: [wayfinder:grilling]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [067, 068]
---

# 066: Member hook 面与 registration state

## Question

Member hook 面收窄与 registration state 的接口怎么定？

已拍板（2026-10-22）：成员 hook 只允许 PRESTEP/before，其它 stage/position 声明在 prepare 期响亮失败；host 在声明了成员插件时 spawn，词法 `hooks` 探测退役；`Hook_Registration` 携带 `state: *void`，`slot_options` / `plugin_state` 平行数组退役；AT 明确为 in-process 测试 seam。

要定：

- 校验发生在哪一层（prepare / scan / resolver / host）；诊断文本与失败路径（`fatal` vs lifecycle ERROR）。
- host spawn 条件与 `Plugin_Prepare_Result.member_hooks` 的退役；`hits.count > 0` 是否足够。
- `Hook_Registration` 结构变化对 `register_hooks` / `merge_hook_tables` / `resolve_plugin_configs` / `run_mounted_hooks` 的传播。
- registration 生成文本与 host 文本的改动范围；`get_scanned_hook_entries` 是否一并退役（当前只被测试消费）。
- in-process hook 仍可挂 AT 的边界如何写进 CONTEXT.md / spec，避免误读为 plugin 承诺。
- 测试面：member hook 拒绝、host spawn、registration state 对齐、generated text pin。

相关锚点：`src/plugin_scan.jai:132-143,216-219,279-341`、`src/plugin_host.jai:36-41,74-80,184-197,295-317`、`src/plugin.jai:472-479,579-582`、`src/lifecycle.jai:283-300,326-339`。

## Answer

**1. 校验层级 = host 权威。** 只有 host 能加载成员插件的真实 hook 值。生成的 host 在 merge → resolve 之后、构造 / 运行 `Prestep_Stage_State` 之前遍历 `resolved.hook_table`：任何 `(stage, position) != (.PRESTEP, .before)` 的 hook 都写成 `DIAG=ERROR|<message>`（每个违规 hook 一条），然后 `OK=0` 返回；不运行任何 hook，不产生部分效果。父进程 `apply_plugin_host_effects` 打印 `[juice ERROR]` 并使 `begin` 失败。诊断文本包含 `stage_name` 与 position，例如：`member hook not supported: TRANSPILE before (v1 supports PRESTEP/before only)`。in-process caller hook 不受此校验，仍可挂任意 stage/position。

**2. Host spawn 条件 = `plugin_prepare.registration_path != ""`。** `prepare_workspace_plugins` 只在声明了成员且 registration 写入成功时设置该字段；session 以它作为唯一 spawn 条件。退役 `Plugin_Prepare_Result.member_hooks` 与 `Plugin_Scan_Result.has_hooks`；删除 `scan_plugin_package` 里的词法 `IDENT "hooks"` 探测（`plugin_scan.jai:216-219`）。`hits` 保留用于报告 / 测试，不再承担 spawn 判定。`plugin_host_options` 消费 prepare 的 `registration_path`，不再用 `workspace_plugin_registration_path` 重新推导。

**3. `Hook_Registration` 携带 state，平行数组退役。**

- `Hook_Registration :: struct { hooks: [..] Lifecycle_Hook; state: *void; }`。
- `register_hooks(table, hooks, state)`：拷贝 hooks 并保存 state；空 hooks 仍然跳过（不占槽）。
- `merge_hook_tables` 拷贝 registration，state 随行。
- `resolve_plugin_configs` 调 `register_hooks(*out.hook_table, plugin.hooks, plugin.options)`；`Resolved_Plugins.slot_options` 删除。
- `run_mounted_hooks` 把 `r.state` 传给 `h.hook(ctx, r.state)`；`Lifecycle_Context.plugin_state` 字段删除。caller hook table 由测试 / in-process 调用方在 registration 上设置 state（允许 null）。
- `Transpile_Context.plugin_state` 不变（pipeline 插件的 per-run state，另一机制）。

**4. Registration / host 生成文本。**

- registration 文件只保留 `JUICE_PLUGIN_<i> :: #import ...` 与 `get_scanned_plugins()`；`JUICE_HOOK_<i>` 与 `get_scanned_hook_entries()` 退役（后者当前只被测试消费）。
- host 文本删除 `for slot: resolved.slot_options ... lctx.plugin_state`；加入第 1 条的 validation loop；`run_mounted_hooks` 直接读 registration state。
- 顺带退役 host 文本里已死的 `HOST_MODE` / `Plugin_Host_Options.mode`（emitted but never read；无行为变化）。
- test metaprogram 不引用 `slot_options`；`Resolved_Plugins` 的类型变化对它透明。生成文本 pin 由 067 更新。

**5. AT 边界文档。** `CONTEXT.md` 新增 **Member hook face** 术语：成员插件经 host 执行的 hook 集合；v1 只支持 PRESTEP/before；AT 是 in-process 测试 seam，不是成员插件的承诺。spec §6/§8.3 在 068 收口时同步一句。in-process lifecycle 测试继续挂任意 stage/position；新增 host 拒绝测试（`.TRANSPILE/.before`、`.PRESTEP/.after`）与 `.PRESTEP/.before` 运行测试（jaix 插件 E2E）。

**6. 迁移顺序。**

1. `lifecycle.jai`：`Hook_Registration.state`；`register_hooks` / `merge_hook_tables` / `run_mounted_hooks`；删除 `Lifecycle_Context.plugin_state`。
2. `plugin.jai`：`resolve_plugin_configs` 设置 state；删除 `slot_options`。
3. `plugin_scan.jai`：删除 `has_hooks` / 词法探测；registration codegen 删除 hook entries。
4. `plugin_host.jai`：prepare 删除 `member_hooks`；host 文本删除 slot loop、加入 validation loop；spawn 条件改为 `registration_path != ""`；`plugin_host_options` 消费 prepare 的路径；退役 `mode`。
5. `commands/build.jai` / `test.jai`：session.begin 用 `registration_path` 判定 host；删除 slot_options 拷贝；caller hook table 设置 state。
6. 测试：更新 `Hook_Registration` 构造、`run_mounted_hooks` state 传播、registration / host pins、host 拒绝 / 运行矩阵、零工作 host spawn。

**不改变**：`Lifecycle_Stage` 枚举、hook 签名 `(ctx, state: *void) -> bool`、`Package.plugins` 声明面、`Transpile_Context.plugin_state`、host 的 PRESTEP/before only 边界。
