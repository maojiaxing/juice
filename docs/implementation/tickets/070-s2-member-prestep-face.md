---
id: 070
title: S2 成员插件面只留 prestep hooks，删 host 运行时校验
labels: [wayfinder:grilling]
status: open
assignee: maojiaxing
blocked-by: [069]
blocks: [071, 068]
---

# 070: S2 成员插件面只留 prestep hooks，删 host 运行时校验

## Question

S2 的 plugin 面怎么定？

**已拍板方向（用户 2026-10-22）**：成员插件面只留 `prestep_hooks`；host 不再做 stage/position 的运行时校验；in-process 的任意 stage 测试钩子走独立 seam。

> 069 已闭：internal seam = `Seam_Hook(Prestep_Stage_State)` / `Seam_Registration`；成员面只剩公开 `prestep_hooks` 的形状待本票定。

要定：

- **`Juice_Plugin.hooks` 的替代形状**：`prestep_hooks: [..] Prestep_Hook`（无 stage/position），还是保留 `hooks` 但只暴露一个构造器？`Prestep_Hook` 与现有 `Lifecycle_Hook` 的关系？
- **in-process 测试钩子的落点**：独立 test-only seam（不进发布插件面），还是 `Lifecycle_Hook` 仍留在 `lifecycle.jai` 但不进 `Juice_Plugin`？测试如何注册任意 stage 的 fake？
- **Host 生成文本**：删除 validation loop、`DIAG=ERROR` 拒绝文本与 pin；host spawn 条件是否仍为 `registration_path != ""`？066 的 registration state 如何跟随 typed prestep hooks？
- **发布面版本**：`Juice_Plugin` 是 `juice_core` 发布面；形状变化是否需要版本说明 / 兼容 shim？`Package.plugins` 不变。
- **测试迁移**：066 的 member hook 拒绝矩阵（`.TRANSPILE/.before`、`.PRESTEP/.after`）删除还是改成类型级测试？host 生成的 substring pin 更新。
- **与 069 的交互**：如果 069 后只剩 PRESTEP + COMPILE 两个 seam，`Prestep_Hook` 是否就是唯一的成员 hook 类型？

相关锚点：`src/plugin.jai:214-242,427-441,579-582`；`src/plugin_host.jai:310-318`；ticket 066；`tests/plugin_host_tests.jai`；复评报告 `architecture-review-20261022-114721.html`。

## Answer

<!-- grilling 后填写。 -->
