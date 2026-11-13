---
title: 文本 test-block 转换迁移与 vendored 同步
status: open
labels: [wayfinder:task]
assignee:
blocked-by: [0068, 0069, 0071]
parent: 0065
---

> 2026-10-22 重锚：按新 juice（otter 实现）重写；旧内联转换实现与新插件面锚点已更新。共同事实见 `0065` Notes。
>
> 2026-10-22 0067 定案：testing root LIB + `packages/` 成员；文本转换的落位（root `modules/` 或另一个 member）由 0068/0072 定。

## Question

按 0068 的 API 形状：

- 把文本 test-block 转换的权威源迁入 testing（新实现源 = `src/transpile_plugin.jai:test_block_plugin`（214）的语义；目标 = testing 的 host-neutral 实现）；
- juice 侧保留薄适配器与 bootstrap vendored 副本（新实现落点 = `src/transpile_plugin.jai` / `src/plugin.jai:builtin_test_block_plugin`（296）/ `default_transpile_pipeline`（392）；发布面 = `JUICE_CORE_LOAD_FILES` 四件中的 `transpile_plugin.jai`），并加同步测试（副本与权威源逐字节一致）；
- 保持 EXPAND / STRIP 行为、`Test_Entry` 清单、行号保真与 `transpile_view_key` 缓存键语义不变；
- juice 的 runtime test 命令与 Build/bootstrap 改为调用 testing 提供的转换（经适配器）；
- 更新 `docs/spec.md` §8.1 与 `CONTEXT.md` 的归属描述（归属迁移；行为不变）。

**Done when:** juice `test` 与 bootstrap 三路径全绿；现有 view / 计数 / pin 零重定（或记录必要重定）；同步测试在副本漂移时失败；旧 juice 内联转换实现删除或降为适配器。
