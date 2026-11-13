---
title: juice Testing 解析接线与特例泛化
status: open
labels: [wayfinder:task]
assignee:
blocked-by: []
parent: 0065
---

> 2026-10-22 重锚：按新 juice（otter 实现）重写；旧函数 / 路径锚点已更新为新实现的 `src/commands/test.jai` / `src/transpile_front.jai`。共同事实见 `0065` Notes。
>
> 2026-10-22 0067 定案：定位零泛化——`<pkg>/modules/Testing.jai` 的 in-package 分支就是 testing 包的路径，global 回退不变；in-package 是约定，不是待删 legacy。本票只落 dev-time 定位器、真实验证与文档。

## Question

按 0067 的定位契约：

- 新增 `src/testing_location.jai`（test-free）：`testing_package_root(root_dir)`，解析顺序 `JUICE_TESTING_ROOT` > `<root_dir>/../testing`；校验 `package.jai` + `modules/Testing.jai`；显式 env 无效 = 失败，默认缺失 = 调用方 SKIP，默认存在但权威面缺失 = 失败（0067 第 6 条）；
- **不改** `testing_module_source`（`src/commands/test.jai:232`）/ `testing_module_view`（251）/ `testing_module_strip_view_dir`（`src/transpile_front.jai:313`）/ `juice_modules_dir()`；in-package 分支保留；
- 用真实 testing 包验证两分支：testing 根 `juice test`（in-package EXPAND + 自测 + support 段）与 jaix/用户包（global `<exe>/modules/Testing.jai` STRIP）；补真实场景直测，补足现有合成视图单测（`tests/test_transpile_tests.jai:337/359/512/1113`）；
- 更新三处函数的注释与 `CONTEXT.md` 的 Testing / 定位说明：in-package 是约定，不是 legacy；无删除计划；
- Build 侧 `<exe>/modules/Testing.jai` 消费面与 bootstrap 三路径复核，不改代码。

**Done when:** `src/testing_location.jai` 落地并有直测；真实 in-package/global 两分支全绿；三路径（bootstrap debug/release + `juice test` + 自构建）全绿；注释 / 文档同步；三个定位函数零代码改动。
