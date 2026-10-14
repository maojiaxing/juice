---
title: discovery 成员校验矩阵
status: closed
labels: [wayfinder:task]
assignee: maojiaxing
blocked-by: [0042-monorepo-fixture-family]
---

## Question

为 `discover_workspace` 的全部失败分支补真实 fixture 直测（目前这些分支零真实覆盖，只有 fake seam 单测），外加 E2E 代表用例与两个边界用例。已锁定决策（grilling 2026-10-13）：

- **全 8 分支，每支一直测**：直接调 `discover_workspace(cache_dir, fixture_root)` 打真实 fixture 目录，断言返回 false 与具体失败分支（不只断言 false——用每分支独有的可观察差异区分，如 discovery 状态、成员清单、或错误分支的独占路径行为）。错误消息的文本断言走 E2E 代表用例。
- **直测放置**：`src/workspace.jai`（持有者内聚）。**E2E 代表放置**：`src/commands/build.jai`（build 是消费 discovery 的入口）。
- **cache_dir 用 target/ scratch**（manifest 求值需要可写目录），defer 清理。
- **junction 用例运行时制造**：把 `workspace-ok` 拷贝进 `target/` scratch，将其 `member-lib` 目录替换为 junction（`File` 模块可造 junction，无需管理员权限；代码同时检查 `is_symlink` 与 `is_junction`），断言「not a safe real directory」分支命中。不进 git。

分支矩阵（对照 `discover_workspace` 实现）：

| 分支 | fixture / 制造方式 |
|---|---|
| root manifest 无效 | `workspace-bad-root-manifest` |
| member 路径非法（逃逸组件） | `workspace-bad-escape` |
| member 目录不存在 | `workspace-bad-missing-dir` |
| member 非安全真实目录 | `workspace-ok` 拷贝 + runtime junction |
| member 逃逸 package root | 与「路径非法」同 fixture 语义区分（`../outside` 同时含逃逸组件；若分支判定先于组件检查，则此支由该 fixture 命中——以实际代码顺序为准，必要时补拼写） |
| member 路径重复 | `workspace-bad-duplicate` |
| member 缺 package.jai | `workspace-bad-no-manifest` |
| member manifest 无效 | `workspace-bad-invalid-manifest` |

E2E 代表用例（2 条即可）：`run_juice_child("workspace-bad-escape", "build")` 与 `run_juice_child("workspace-bad-invalid-manifest", "build")` → 非零退出码 + 错误消息文本对用户可见（`output_matches` 断言 `[juice ERROR]` 行）。

边界用例（钉住当前行为，不在本票拍板语义）：

- `workspace-edge-self`：root 列 `"."` → 预期命中重复路径错误（`"."` 归一化后与 root 相同，root 已先入 member 清单）。
- `workspace-edge-nested`：member 再声明 members → 预期 discovery **成功**且 member 的 members 不进入 discovery（当前实现只迭代 root 的 members 清单）。若实测行为与此不同或明显意外（如静默忽略值得记录为文档事实之外的问题），**立缺陷票**（本地图内），不擅自改语义。

## Acceptance criteria

- [ ] 全 8 分支直测落地于 `src/workspace.jai`，每条断言具体分支（非笼统 false）。
- [ ] junction 用例运行时制造、随 scratch 清理，不进 git。
- [ ] 2 条 E2E 代表用例断言非零退出与错误消息文本。
- [ ] 2 个边界用例行为被钉住（断言当前行为），或缺陷票已立。
- [ ] `jai build.jai` + `./target/juice.exe test` 全绿（新增 src 测试块后先清 `target/transpile` 缓存）。

## Out of Scope

- 变更 discovery 语义（修复缺陷另立票）。
- 外部依赖 fetch 的 E2E。

## Further Notes

- 直测断言「具体分支」的手段若因 discovery 无内部状态而受限，允许经 E2E 消息断言补齐（Resolution 说明取舍）。
- 环境隐患：新增含 test block 的 src 文件后必清 `target/transpile`；`target/juice.exe` 运行中不可重链接。

## Resolution

矩阵落地并全绿（`jai build.jai` + `./target/juice.exe test`：**155 passed, 0 failed**，165 发现块）。

**放置取舍（与票面「全分支直测」的偏差，按 Further Notes 授权执行）**：直测不可行——`load_package_manifest` 的模块目录从 `get_path_of_running_executable()` 推导（`src/manifest.jai:244`），测试程序运行于 jai 编译器内，模块目录指向 jai 安装目录而非仓库 `modules/`，任何真实 manifest 求值都会失败。故分支矩阵整体走 **E2E（真实 juice.exe + 消息断言）**，进程内直测改为钉住可进程内验证的路径有效性门槛。

- **`src/workspace.jai`** 新增 `test "Workspace member path validity gate"`（进程内直测）：空/绝对（含卷标）/`..` 逃逸组件拒绝，`.` 组件与普通相对路径放行（`.` 放行使 `member_lib/.` 拼写能走到 duplicate 分支）。
- **`src/commands/build.jai`** 新增 9 条 E2E，每分支一条、经 `child_output_contains` 断言专属错误消息：
  1. root manifest 无效 → `Existing package.jai is invalid.`
  2. 逃逸组件 → `Invalid workspace member path: ../outside`
  3. member 目录不存在 → 实测命中 `not a safe real directory: ghost_member`（票 0042 实测事实，测试按实测分支断言）
  4. member 缺 manifest → `lacks package.jai:`
  5. member manifest 无效 → `Workspace member manifest is invalid:`
  6. 重复路径 → `Duplicate workspace member path: member_lib/.`
  7. 边界：root 自列 `"."` → `Duplicate workspace member path: .`（钉住）
  8. 边界：member 再声明 members → **build 成功、嵌套声明静默忽略**（钉住，与 CONTEXT.md 词汇一致；建议 wrap-up 在 CONTEXT.md Workspace member 词条补一句事实）
  9. junction → 运行时在 `target/workspace-junction` scratch 复刻 workspace-ok 形状，`make_test_link(junction=true)` 把 member_lib 换成 junction → `not a safe real directory`。实测机器上 junction 真实创建（未 SKIP），defer 清理 scratch。
- **两个防御分支不入矩阵**（代码注记 + 本 Resolution 记录）：`does not exist`（normalize_existing_path 只做词法归一、不验证存在，仅 `get_absolute_path` 自身失败时可达）与 `escapes package root`（有效性门槛已拒绝全部可达拼写，junction/symlink 被更早的 safe-directory 检查拦截）——两者经 fixture 声明的 member 路径均不可达。
- 边界行为无意外 → **未立缺陷票**；地图 Not yet specified 的「边界用例行为裁断」部分已由本票裁断（嵌套静默忽略 = 文档事实，非缺陷）。
- E2E 全绿后 fixture 无 target/ 残留（defer 清理），git 状态干净。
- **勘误（2026-10-14 用户修订）**：本票的 9 条 E2E 自 `src/commands/build.jai` 迁移至 `tests/test_monorepo.jai`（monorepo E2E 集中于此文件，不内联 command）；workspace.jai 的路径门槛直测保留原位。

