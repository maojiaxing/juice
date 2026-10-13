---
title: Build_Driver 拆解：路径按持有者内聚
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: []
---

> 架构体检（improve-codebase-architecture）候选 1。

## Problem Statement

`Build_Driver` 是浅模块：5 字段接口等于零行为实现。data_dir/config_dir 写后无人读；test 命令三个签名把它当货载透传（0 字段读取）；run 从不触碰；名字与生成的 driver.jai 撞名。关键事实：packages_dir 是 root_dir 的纯推导（`main.jai` 一行），全进程真正的路径只有两个——root_dir 与 cache_dir。

## Solution

完全拆解，结构体消失：

1. `Command_Context` 持两个字符串字段 `root_dir` / `cache_dir`；`src/driver.jai` 删除。
2. `packages_dir(root_dir)` helper 落 `src/dependency.jai`（Local dependency directory 的持有者）。
3. data_dir/config_dir 连同 xdg.jai 的 `get_data_home`/`get_config_home`（唯一用途是喂死字段）删除。
4. seam 收窄：discover_workspace(root_dir, cache_dir)；load_package_manifest(cache_dir, pkg_dir)；ensure_workspace_discovered / prepare_workspace / dependency 一系同收两路径（packages_dir 内部推导）；compiler_import_directories(packages_dir)；compile_artifact_plan(root_dir, plan, entry)；build_prepared_workspace(prepared, transpile, compile)——零路径参数；clean_discovered_workspace(root_dir, discovery, …)。
5. test 命令三个签名彻底去掉 driver：collect_test_files(prepared)、compile_test_program(transpile_dir, driver_path, metaprogram_path)、test_prepared_workspace(prepared, pattern, files, transpile, compile)。
6. tests/test_support.jai 的 seam fake 机械更新。

## Acceptance criteria

- [x] 三路径全绿：`jai build.jai`（debug/release）、`juice build` 自构建、`juice test` 0 failed
- [x] grep 无 `Build_Driver` 痕迹；`src/driver.jai` 删除
- [x] 报错文案与行为零变化（既有测试原样通过）
- [x] IMPLEMENTATION.md：删 driver.jai 行、更新 workspace/dependency/main 行

## Out of Scope

- Testing 模块视图特例收口（票 0039）
- EXPAND 缓存键纳入测试编号（既有缺陷，另行立票）

## Further Notes

- 语言：中文交流与文档。
- 验证前清 `target/transpile`：文件集变化会移测试编号，陈旧视图编号冲突（memory 已记）。

## Resolution

已实施：Build_Driver 完全拆解——`Command_Context` 持两个字符串字段 root_dir/cache_dir；`packages_dir(root_dir)` 派生 helper 落 dependency.jai（Local dependency directory 的持有者）；src/driver.jai 删除；xdg.jai 的 get_config_home/get_data_home（唯一用途是喂死字段）删除。seam 按方案收窄：discover_workspace/ensure_workspace_discovered/prepare_workspace/dependency 一系收 (root_dir, cache_dir)；compile_artifact_plan(root_dir, plan, entry)；build_prepared_workspace(prepared, transpile, compile) 零路径参数；clean_discovered_workspace(root_dir, …)；test 三签名（collect_test_files/compile_test_program/test_prepared_workspace）货载清零。tests/test_support.jai 的 7 个 seam fake 机械更新。验证：三路径全绿——debug/release 自举、juice build 自构建（复制 exe 避 LNK1104）、juice test 152 块 0 failed（debug 与 release 产物各一遍）、30 处 GOLDEN PASS；grep 无生产引用残留（仅注释提及拆解出处）。
