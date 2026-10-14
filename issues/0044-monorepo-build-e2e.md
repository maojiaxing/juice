---
title: monorepo build E2E：root 依赖 member 构建
status: closed
labels: [wayfinder:task]
assignee: maojiaxing
blocked-by: [0042-monorepo-fixture-family]
---

## Question

补「root 依赖 member → shim 链接（link 非 fetch）→ 真实编译出 root artifact → 运行 artifact」的 monorepo E2E build，当前零覆盖。已锁定决策（grilling 2026-10-13）：

- **E2E 只碰 member 依赖**：不涉及外部依赖（测试不碰网络）；外部 fetch 保持 fake seam 单测水位。
- 放置：`src/commands/build.jai`，用既有 helper `run_juice_child("workspace-ok", "build")`（`tests/test_support.jai`）。

场景与断言：

1. `run_juice_child("workspace-ok", "build")` → 退出 0；root artifact 出现在 `tests/data/workspace-ok/target/<root 包名>.exe`。
2. **link 非 fetch**：`tests/data/workspace-ok/target/packages/` 下 `member-lib` 与 `member-extra` 的 shim 均生成；读 shim 内容断言其 `#load` 指向 member 的导入入口路径（`member-lib/src/module.jai` 与 `member-extra/module.jai`，覆盖两种布局），而非 fetch 来源。
3. **多 member 皆 link**：两个 member 的 shim 都存在（root 依赖两者）。
4. 运行 artifact（`run_command` 子进程）→ 退出 0，输出断言证明两 member 的函数被实际调用（如成员函数返回值出现在输出）。
5. 测试结束 `defer delete_directory_full` 清 fixture 的 target，仓库保持干净。

## Acceptance criteria

- [ ] 上述 E2E 测试落地 `src/commands/build.jai` 且全绿。
- [ ] shim 内容断言（link 指向 member 路径）落地，不只断言 shim 存在。
- [ ] `jai build.jai` + `./target/juice.exe test` 全绿（新增 src 测试块后先清 `target/transpile` 缓存）。

## Out of Scope

- 外部依赖 fetch 的 E2E；member 自身依赖外部包的场景。
- run 命令的 monorepo 语义变化（只解析 root effective target 是既有决策）。

## Further Notes

- 环境隐患：fixture 不提交 `target/`（本票运行时产生后即清）；`target/juice.exe` 运行中不可重链接（E2E 以子进程 spawn juice.exe 属既有模式）。
- 若实测发现 shim 未生成或 link 断裂，立缺陷票（本地图内），不擅自修实现。

## Resolution

落地 `src/commands/build.jai` 的 `test "E2E: monorepo build links members and builds the root"`，全绿（`jai build.jai` + `./target/juice.exe test`：**156 passed, 0 failed**）。断言链：

1. `run_juice_child("workspace-ok", "build")` 退出 0 + `Compiling Target 'ws_root' ...` 阶段行。
2. **link 非 fetch**：读 `target/packages/member_lib.jai` 与 `member_extra.jai` shim 内容（`shim_content_for`），断言 `#load` 分别指向 `member_lib/src/module.jai`（src 布局）与 `member_extra/module.jai`（根布局）——两种导入入口布局 + 多 member 皆 link。
3. 运行 `target/ws_root.exe` → 退出 0 + 输出 `ws_root: hello from member_lib | hello from member_extra`（两 member 函数被实际调用）。
4. 附加断言：root 入口闭包 test-free → `target/transpile` 不存在（member 的 `#import` 不进 Build 探测闭包，零转译）。

未发现缺陷、无修复票。defer 清理 fixture target，git 状态干净。
- **勘误（2026-10-14 用户修订）**：本测试自 `src/commands/build.jai` 迁移至 `tests/test_monorepo.jai`（monorepo E2E 集中于此文件，不内联 command）。

