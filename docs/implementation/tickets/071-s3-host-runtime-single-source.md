---
id: 071
title: S3 host 协议单源：发布 runtime，生成文本只留数据
labels: [wayfinder:grilling]
status: open
assignee: ""
blocked-by: [069, 070]
blocks: [068]
---

# 071: S3 host 协议单源：发布 runtime，生成文本只留数据

## Question

S3 的 runtime 边界怎么定？

**已拍板方向（用户 2026-10-22）**：host 的 merge / resolve / validate / dispatch / record 收进一个发布 runtime module；生成 host 文本只留 data constants、registration `#load` 和一次调用。

> 069 已闭：host dispatch 走 typed prestep seam（`Seam_Registration` / `run_seam`）；S3 只需把 merge / resolve / record 也收进 runtime。

要定：

- **runtime 落点**：新发布模块 `juice_host`，还是扩 `juice_core`？发布树（exe + modules/）与 `JUICE_CORE_LOAD_FILES` 如何变？
- **入口形状**：`run_prestep_host(plugins, options)` 的输入（`get_scanned_plugins()` 的返回值、`Plugin_Host_Options`、record 路径）与失败返回；host driver 是否仍能编译期报错？
- **其它复制点**：`src/test_runner.jai` 的 merge/resolve 前奏与 `tests/test_support.jai:1148-1155` 的 scan driver 是否也走同一 runtime，还是只收 host？
- **生成文本与 pin**：host 的 substring pin、registration 的 byte pin、test runner 的 byte pin 如何更新；067 的“只改强制项”是否被本票取代？
- **安装契约**：runtime module 是否只依赖发布面（Basic / File / String / juice_core），不读 `src/` / `target/`？
- **测试**：host runtime 的直接单测；真子进程 E2E 是否仍保留。

相关锚点：`src/plugin_host.jai:252-334,494-584`；`src/test_runner.jai:299-309`；`tests/test_support.jai:1148-1155`；`src/publication.jai:83`；ticket 067；复评报告 `architecture-review-20261022-114721.html`。

## Answer

<!-- grilling 后填写。 -->
