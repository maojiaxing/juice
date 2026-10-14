---
title: 缺陷：test 编译缺 target/packages import 路径——root 测试无法 import 依赖
status: closed
labels: [wayfinder:task]
assignee: maojiaxing
blocked-by: []
---

## Problem Statement

`src/commands/test.jai:233` 的测试程序编译选项 `metaprogram.import_dirs = string.[juice_modules_dir()]` 只注入 juice 模块目录——依赖 shim 所在的 `target/packages/` 不在搜索路径。Build 有 `compiler_import_directories`（`src/commands/build.jai:38`）注入 modules + packages，Test 没有。后果：root 测试程序里任何 `#import "<依赖名>"`（含 workspace member）编译失败。

由 [monorepo test E2E 缺口](0046-monorepo-test-e2e-gap.md) 的 E2E 复现（workspace-ok 上 `juice test`）：依赖准备正常生成 shim，但测试程序编译报 `Error: Unable to find a module called 'member_lib' in any of the module search directories.`，child 退出 1；搜索路径仅 transpile/modules、testing-module 与 juice modules，无 packages 目录。

## Solution

- 把 `compiler_import_directories` 从 `src/commands/build.jai` 移入 `src/dependency.jai`（`packages_dir` 的派生持有者，票 0038 路径按持有者内聚方向），build 与 test 共用同一推导。
- `src/commands/test.jai` 的 `metaprogram.import_dirs` 改用 `compiler_import_directories(packages_dir(prepared.discovery.root_dir))`（packages 目录存在时注入，与 build 同构）。

## Acceptance criteria

- [ ] [monorepo test E2E 缺口](0046-monorepo-test-e2e-gap.md) 的 E2E 转绿：root 测试程序经 shim 解析 member 并执行断言。
- [ ] 全量 `jai build.jai` + `./target/juice.exe test` 0 failed（新增 src 测试块后先清 `target/transpile`）。
- [ ] build 行为不变（其 E2E 保持全绿，helper 移除不改变编译语义）。

## Out of Scope

- 外部依赖 fetch 的 E2E（网络不进测试）。
- import 路径机制的重构（如统一为单一 options 结构）——只补 Test 的缺漏，不扩大改动。

## Resolution

已修复：`compiler_import_directories` 移入 `src/dependency.jai`（`packages_dir` 的派生持有者，票 0038 内聚方向），build 删除本地定义（调用点不变，同一程序作用域解析到新持有者），`src/commands/test.jai` 的 `metaprogram.import_dirs` 改用 `compiler_import_directories(packages_dir(prepared.discovery.root_dir))`——packages 目录存在时注入，与 build 同构。

验证：[monorepo test E2E 缺口](0046-monorepo-test-e2e-gap.md) 的 E2E 由红转绿（修复前 child 退出 1、`Unable to find a module called 'member_lib'`，修复后 root 测试程序经 shim 解析 member 并执行断言）；全量 `jai build.jai` + `./target/juice.exe test`：**158 passed, 0 failed**，build 的既有 E2E（含零转译断言）保持全绿——build 语义不变。

