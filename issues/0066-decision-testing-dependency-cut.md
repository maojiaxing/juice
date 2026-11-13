---
title: 决策：新 juice 构建的 Testing 依赖切割
status: closed
labels: [wayfinder:grilling]
assignee: maojiaxing
blocked-by: []
parent: 0065
---

> 2026-10-22 重锚：按新 juice（otter 实现）重写；旧 `modules/Testing.jai` 与旧 build 路径已不存在。共同事实见 `0065` Notes。
>
> 2026-10-22 补充：测试发现源（`src/test_discovery.jai`）的自包含/发布问题与 Testing 定义面同构但独立，归 0075；本票只定 Testing 定义面。

## Question

Testing 模块迁出 juice 后，新 juice 自身构建（bootstrap `build.jai` + Build command + 自托管测试程序）如何满足 `#import "Testing"` / Testing 定义面？

先核实新实现事实：

- `src/module.jai` 的 `// [PUBLICATION-SECTION testing]`（157 起）是 Testing 定义源；`src/publication.jai:publish_testing_module`（221）剥 `Testing_` 前缀生成 `target/modules/Testing.jai`；`build.jai` 发布步（163-267）在编译前读 `src/module.jai` 并落盘。
- `src/main.jai` 的 `#load` 闭包含 `module.jai`（52），所以 Testing 定义面当前编译进 exe；测试程序经发布面 `#import "Testing"` 消费裸名。
- 新根包没有 in-package `modules/Testing.jai`；`src/commands/test.jai:testing_module_source`（232）在根无该文件时回退 `<exe>/modules/Testing.jai`（`in_package=false`，STRIP 视图）。

三选一（按新实现重述）：

- (a) `src/module.jai` 的 testing 段保留为 vendored 定义源（prefixed），testing 权威面 = `testing/` 的裸名 `Testing.jai`；发布转换输出与 testing 权威面做同步测试（逐字节或行级）。bootstrap 自包含不破。
- (b) juice 侧移除 Testing 定义段，构建期从 testing 包读取（破 bootstrap 自包含，或需额外 vendoring 机制）。
- (c) 其他（说明；例如生产构建剥离 Testing 定义面，仅在测试程序导入发布面——需核实 exe/test command 是否真的不需要该面）。

**Done when:** 选定方案并写清对 bootstrap 发布步、`publish_testing_module`、Build command 的 Testing 特例、自托管测试程序、`tests/module_tests.jai` 双面矩阵的影响；若选 (a)，写清同步测试的位置、比较对象（`testing/Testing.jai` vs `target/modules/Testing.jai` / 转换输出）与漂移失败语义。

## Resolution

（2026-10-22 grilling 敲定，选方案 (a)；Q1-Q4 逐轮确认）

1. **依赖切割 = (a) vendored 定义源**：`src/module.jai` 的 `// [PUBLICATION-SECTION testing]` 保留为 juice 内 vendored **prefixed** 定义源；testing 包的裸名 `Testing.jai` 是权威面（落位按 0067）。bootstrap 仍只读 juice 仓库源码，自包含不破。
2. **vendored 形态 = 完整镜像**：镜像包含 API + `src/module.jai:315-389` 自测块；`publish_testing_module` 输出保持不变（含自测）。`tests/module_tests.jai` 的 definition-source vs imported-face 双面矩阵留在 juice；0070 可把权威侧用例复制到 testing，但不删 juice 面。同一套自测在 juice 套件（prefixed 镜像）与 testing 套件（裸名权威）各跑一遍，作为可接受代价。
3. **同步测试位置**：juice `tests/` 新增集成测试（建议 `tests/testing_authority_sync_tests.jai`），随 `juice test` 运行；权威面路径经 0067 的定位契约解析，不硬编码 `../testing`。testing 缺席（单独 clone juice）时打印明确 SKIP 并返回；存在但漂移时失败。SKIP 白名单/基线由 0074 收口时更新。
4. **比较对象与漂移语义**：整文件逐字节比较 `publish_testing_module(src/module.jai)` 的完整输出与 testing 权威面文件——包含 `#import "Basic";` 头、注释、自测块与行尾，不做 CRLF/LF 或空白归一化。testing 为权威：漂移时更新 juice `src/module.jai` 的 testing 段（手工重新加 `Testing_` 前缀；本 effort 不做再生成工具，因为前缀是语义变换）。失败信息打印两个路径、首个不同行号与两侧行文本，并明确指向 `src/module.jai`。既有 `tests/bootstrap_tests.jai` / `tests/publication_tests.jai` 继续钉住构建产物与进程内 publication 输出一致，不新增 pin。
5. **各消费面影响**：bootstrap 发布步不变（仍读 `src/module.jai`）；`publish_testing_module` 不变；Build command 的 Testing STRIP 特例不变（仍消费 `<exe>/modules/Testing.jai`）；自托管测试程序不变（继续经发布面导入裸名，vendored prefixed 面经全包扫描进入，无重载冲突）。
6. **exe 死面**：已核实 `src/` 内除 `src/module.jai` 外无任何 `Testing_*` 实际调用；exe 继续携带无人引用的 prefixed Testing 定义，行为无影响。清理它（拆分 `src/module.jai` / 裁剪 `main.jai` 闭包）列为后续独立 effort，不在本图。
7. **实施归属**：0070 按本结论落同步测试与镜像；发现源的同类问题归 0075，不在本票。
