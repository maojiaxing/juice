---
title: testing 包骨架与模块面
status: open
labels: [wayfinder:task]
assignee:
blocked-by: []
parent: 0065
---

> 2026-10-22 重锚：按新 juice（otter 实现）重写。共同事实见 `0065` Notes。
>
> 2026-10-22 0067 定案：testing root LIB + `packages/Jaix_Plugin_Test_Block` 成员；Testing 面 `testing/modules/Testing.jai`；包入口根 `testing/module.jai`，无 `#import "testing"` 面。详见 `0067` Resolution。

## Question

落地 `jai/testing/` 包骨架（按 0067）：

- `testing/package.jai`（LIB；依赖 `jaix` = `../jaix`、`packrat` = `../packrat`、`Jaix_Plugin_Test_Block` = 工作区成员按名链接；`workspace.members = ["packages/Jaix_Plugin_Test_Block"]`；按新 juice manifest 面 `#import "Juice"`）；
- 包入口 `testing/module.jai`（仅 `PACKAGE`；不提供包级 `#import "testing"` 面）；
- Testing 面 `testing/modules/Testing.jai`（in-package 约定、扫描排除；内容迁移归 0070，先放最小占位）；
- jaix 插件成员 `testing/packages/Jaix_Plugin_Test_Block/`（`package.jai` 的 `PACKAGE.name = "Jaix_Plugin_Test_Block"`；根 `module.jai` = 插件源，test-free；成员零依赖、不作为独立 test root；内容迁移归 0073，先放最小占位）；
- `testing/tests/` 与 `testing/fixture/`（fixture `.jai` 沿用 dot-prefix，扫描排除集覆盖）、版本号；
- 确保新 juice `build` 能验证 LIB 导入面（`target/juice.exe build` 于 testing 根；或同等的 juice exe）。

**Done when:** 在 testing 根 `juice build` 通过（LIB 导入面校验）；目录与模块面符合 0067；不触碰 juice/jaix 的现有代码。
