---
title: monorepo test E2E 缺口：root 测试程序 import member
status: closed
labels: [wayfinder:task]
assignee: maojiaxing
blocked-by: [0042-monorepo-fixture-family]
---

## Question

补「root 的测试程序 `#import` 一个 lib member」的 monorepo test E2E——这是 monorepo 下 `juice test` 的真实场景（discovery → 依赖准备 → shim 解析 → 视图编译 → 编译期执行全链路），当前零覆盖。已锁定决策（grilling 2026-10-13）：

- 这是 test 面唯一实质缺口：member 边界（root 扫描不进 member 子树、member 自为 root）已有两条 E2E，不在本票重做，但可在断言中自然重申。

场景与断言：

1. 在 `workspace-ok` 的 root 侧加一个含 test block 的源文件（如 `src/helper.jai`，顶层 `#import "member-lib"`，test 块内断言 member 导出函数的返回值）——root 是 BIN 且有 effective target，依赖准备会执行，member shim 可被 `#import` 解析。
2. 给 `member-lib` 加一个自带 test block（证明 member 的测试存在）。
3. `run_juice_test("workspace-ok")` → 退出 0；输出断言：root 的测试被发现并跑过（`[test]` 行 + `passed` 汇总）；**member 的测试不执行**（`output_matches(..., want = false)`，重申 member 边界）。
4. defer 清理 fixture 的 `target/`。

## Acceptance criteria

- [ ] 上述 E2E 测试落地 `src/commands/test.jai` 且全绿。
- [ ] 断言覆盖「root 测试通过 member 函数 + member 测试不执行」。
- [ ] `jai build.jai` + `./target/juice.exe test` 全绿（新增 src 测试块后先清 `target/transpile` 缓存）。

## Out of Scope

- workspace-wide 测试聚合（地图 0001 已划出）。
- member 依赖外部包的测试场景（网络不进测试）。

## Further Notes

- 环境隐患：本票会新增含 test block 的 src 文件（测试块本身）——EXPAND 缓存键不含测试编号，验证前必清 `target/transpile`。
- 若实测 root 测试程序无法解析 member shim（`#import "member-lib"` 编译失败）或 member 测试被误跑，立缺陷票（本地图内）。

## Resolution

落地 `test "E2E: monorepo root tests import a member library"`（`src/commands/test.jai`），**过程中暴露并修复了真实缺陷**（[缺陷：test 编译缺 target/packages import 路径](0048-defect-test-compile-missing-packages-import-dir.md)）：

- fixture 增补：`workspace-ok/src/helper.jai`（root 侧 test block，`#import "member_lib"` 并断言 `member_lib_greeting()` 返回值）；`workspace-ok/member_lib/tests/member_extra.jai`（member 自带 test block，证明 member 测试存在）。member 测试不放 `member_lib/src/module.jai`——导入入口经 shim 被 root build 直接 `#load`，out-of-package 不转译，含 test block 会破坏 build（票 0044 E2E 会红）。
- E2E 断言：`Found 1 tests`、`[test] root test imports the member` + `1 passed, 0 failed`、member 测试名不出现（member 边界重申）。
- **红灯复现**：test 编译的 import 路径缺 `target/packages`（`test.jai` 只注入 juice modules 目录）→ child 报 `Unable to find a module called 'member_lib'` 退出 1 → 立缺陷票 → 修复（`compiler_import_directories` 移入 dependency.jai，test 与 build 共用）→ 转绿。
- 验证：全量 `jai build.jai` + `./target/juice.exe test`：**158 passed, 0 failed**。defer 清理 fixture target，git 状态干净。
- **勘误（2026-10-14 用户修订）**：本测试自 `src/commands/test.jai` 迁移至 `tests/test_monorepo.jai`（monorepo E2E 集中于此文件，不内联 command）。

