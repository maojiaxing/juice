---
title: Test 命令内聚 Testing 模块视图特例
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: []
---

> 架构体检（improve-codebase-architecture）候选 3，形态 C（用户拍板）：不建新模块，特例内聚为 test.jai 内部 helper；build 侧 STRIP 函数原地不动。

## Problem Statement

`test_prepared_workspace` 的编排被 Testing 模块编译视图特例（票 0033）撑爆：约 90 行来源探测 / EXPAND+支撑段 / STRIP 分支嵌在主流程中间，与「转译、视图落盘、driver 生成」的编排骨架混在一起。

## Solution

test.jai 内新增 `testing_module_view(package_root, support_view, next_test_number) -> Testing_Module_View_Result, bool`：

- `Testing_Module_View_Result { enabled, dir, view_path, view_text, tests, next_test_number }`（dir "" = 未启用哨兵）
- 计算（来源探测、EXPAND/STRIP、支撑段切取）全部内聚；**写盘留在编排的既有位置**（zero-match 早退之后）——行为与现在逐字节一致
- `testing_module_source` 收窄为 `(package_root)`；`testing_module_support_block` 不动
- 编排特例段缩为：调用 + pattern 过滤自测块 + 编号续接 + path_mapping 行
- build.jai 的 `testing_module_strip_view_dir` 原地不动；bootstrap 不动（ADR 0006）

## Acceptance criteria

- [x] 三路径全绿；`juice test` 0 failed、golden 原样通过
- [x] 现有 E2E/seam 测试行为零变化（fixture 测试计数不变）
- [x] 新增直接单测：来源探测 in-package、支撑段标记缺失失败、哨兵禁用路径（全局分支单测因编译期 exe 解析限制改由 E2E child 场景覆盖）
- [x] IMPLEMENTATION.md test 行措辞对齐

## Out of Scope

- 共享模块 src/testing_module.jai（形态 A，已否决）
- build 侧 STRIP 函数迁移

## Further Notes

- 语言：中文交流与文档。
- 验证前清 `target/transpile`（新增 test block 移编号）。

## Resolution

已实施（形态 C）：`test_prepared_workspace` 的约 90 行特例段收敛为 `testing_module_view(package_root, support_view, next_test_number) -> Testing_Module_View_Result, bool`——来源探测、EXPAND（+支撑段切取）/STRIP 计算全部内聚；只算不写盘，写盘留在编排 zero-match 检查之后的既有位置，行为逐字节一致。`testing_module_source` 收窄为 (package_root)；编排缩为：支撑段视图查找 + 调用 + pattern 过滤 + 编号续接 + 写盘 + path_mapping 行。build 侧 `testing_module_strip_view_dir` 与 bootstrap 未动。新增直接单测 ×4：in-package 来源探测、test-free 哨兵禁用、EXPAND+支撑段与编号续接、支撑段标记缺失失败。全局模块分支的两条直接单测因编译期 `juice_modules_dir()` 解析到 jai 编译器目录而撤回，该分支由既有 E2E child 场景端到端覆盖（真实 juice.exe）。验证：三路径全绿——debug/release 自举、juice build 自构建、juice test 156 块 0 failed（debug 与 release 各一遍）、30 处 GOLDEN PASS、fixture 计数零变化。
