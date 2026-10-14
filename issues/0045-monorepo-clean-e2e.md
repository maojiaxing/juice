---
title: monorepo clean E2E：root+member target 递归删除
status: closed
labels: [wayfinder:task]
assignee: maojiaxing
blocked-by: [0042-monorepo-fixture-family]
---

## Question

补「clean 递归删除 root 与全部 member 的 target directory 整目录」的 monorepo E2E，当前 clean 只有 fake seam 单测。已锁定决策（grilling 2026-10-13）：

- **target 垃圾运行时制造**：fixture 不提交 `target/`（.gitignore 陷阱）；测试块先向 `workspace-ok` 的 root 与 `member-lib` 各写一个真实 `target/` 目录 + 垃圾文件（如伪 artifact 与伪转译产物）。
- 放置：`src/commands/clean.jai`，用既有 helper `run_juice_child("workspace-ok", "clean")`。

场景与断言：

1. 造垃圾：root 与 `member-lib` 各建 `target/`（含子文件）；`member-extra` 不建（覆盖「member 无 target 不失败」）。
2. `run_juice_child("workspace-ok", "clean")` → 退出 0。
3. root 与 `member-lib` 的 `target/` **整目录消失**（`!file_exists` / `!path_exists`）。
4. 非 target 内容原样保留：`package.jai`、`src/main.jai`、`member-lib/src/module.jai` 仍存在（clean 不越界）。
5. 测试结束 defer 清理 scratch（若 clean 断言失败，残留垃圾由 defer 兜底）。

## Acceptance criteria

- [ ] 上述 E2E 测试落地 `src/commands/clean.jai` 且全绿。
- [ ] 断言覆盖「两 target 消失 + 源文件保留 + 无 target 的 member 不失败」。
- [ ] `jai build.jai` + `./target/juice.exe test` 全绿（新增 src 测试块后先清 `target/transpile` 缓存）。

## Out of Scope

- 删除失败继续语义的 E2E（fake seam 单测已覆盖）。
- 变更 clean 实现（缺陷另立票）。

## Further Notes

- 环境隐患：垃圾目录只在运行时存在、不进 git；`target/juice.exe` 运行中不可重链接。
- 若实测 clean 未删 member 的 target 或误删源文件，立缺陷票（本地图内）。

## Resolution

落地 `src/commands/clean.jai` 的 `test "E2E: clean removes root and member target directories"`，全绿（`jai build.jai` + `./target/juice.exe test`：**157 passed, 0 failed**）。

- 运行时制造垃圾：root 与 `member_lib` 各写一个真实 `target/`（含伪 artifact `junk.exe` / `junk.lib`）；`member_extra` 不建 target。
- `run_juice_child("workspace-ok", "clean")` → 退出 0 + `[juice Clean] Workspace cleaned.`。
- 断言两 `target/` 整目录消失（含垃圾）；`package.jai`、`src/main.jai`、两 member 的 manifest 与入口源文件原样保留（clean 不越界）。
- **「member 无 target 不失败」成立**：`delete_directory_full` 是仓库本地 helper（`src/dependency.jai:228`），对不存在路径返回 true；`clean_path_is_safe` 对不存在路径也放行。无缺陷、无修复票。
- defer 兜底清理，git 状态干净。
- **勘误（2026-10-14 用户修订）**：本测试自 `src/commands/clean.jai` 迁移至 `tests/test_monorepo.jai`（monorepo E2E 集中于此文件，不内联 command）。

