---
id: 046
title: 全链 E2E：scratch 工作区 + 真 exe + 成员根冒烟
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: [045]
blocks: [047]
---

> 父 spec：`040-spec-third-party-plugin-member-lint.md`（决定 6、11；US 33-34）。先例：`tests/test_command_tests.jai` 的 exe E2E、`tests/e2e_cli_tests.jai` 的 `run_otter_child_at`。

# 046: 全链 E2E：scratch 工作区 + 真 exe + 成员根冒烟

**What to build:** 用真实成员布局和真实 `juice.exe` 证明插件声明面到 lint 报告的整条链路：scratch 工作区里的坏命名 `@test` 触发 `[juice lint]` 警告，同时测试照常执行、退出码为 0；真实成员包根上的 CLI 冒烟仍全绿。

**Blocked by:** 045

**Status:** closed

- [x] E2E 搭建 scratch 工作区（仅落 `target/` 下）：根 `package.jai` 声明 `workspace.members` + 同名 DEP；从真实成员包逐字节复制 `packages/juice-plugin-lint/{package.jai,module.jai}`；`tests/bad_name_tests.jai` 含一个 `@test BadName` 过程。
- [x] 真 exe 于 scratch 根跑 `test`：exit 0；输出含 `[juice lint]` 与 `BadName`（原始包相对路径 + 1 基坐标）；输出含 `[test] BadName` 与 `0 failed`。
- [x] 真实成员包根（`packages/juice-plugin-lint`）CLI 冒烟：exit 0、自身测试全绿；不污染仓库（产物仅落 `target/`）。
- [x] E2E 结束后清理 scratch；根套件自跑 debug+release 全绿。
- [x] 本票只加 E2E 与必要测试助手，不改生产语义。

## Resolution

**状态：closed（2026-10-21）**

### 实现摘要

- `tests/test_command_tests.jai` 新增「全链插件 lint E2E」段（票面允许 E2E 落 `e2e_cli_tests.jai` 或本文件；本文件已有 045 插件接线矩阵与 test 命令 E2E 族，`build_seam_write`/`run_otter_child_at`/`fixture_line_col` 可直接复用）：
  - `build_lint_full_chain_scratch`：运行期在 `<otter>/target/lint-full-chain-e2e` 搭 scratch 工作区——根 `package.jai`（BIN、无 targets）声明 `workspace.members = ["packages/juice-plugin-lint"]` + 同名 DEP；`packages/juice-plugin-lint/{package.jai,module.jai}` 从真实成员包 `read_entire_file` → 逐字节写入（非静态镜像）；`tests/bad_name_tests.jai` = `#import "Testing";` + `BadName :: () { expect(true); } @test` + `test_good_name :: () { expect(true); } @test`。
  - E2E 块：测试开始先删 scratch、`defer delete_directory_full(scratch)`；`run_otter_child_at(scratch, string.["test"])` 驱动真实 `target/juice.exe`。断言：exit 0；child **stdout** 含 `[test] BadName`、`[test] test_good_name`、`2 passed, 0 failed`；child **stderr** 含 `tests/bad_name_tests.jai:<line>,<col>: Warning: [juice lint] test procedure name must be snake_case: BadName`（行由 `fixture_line_col` 从 scratch 源算出、列为 header 的 `(` 列 = 起始列 + 11，042 先例；不硬编码）；stderr 无 `Error:`；scratch 的 `target/plugins/registration.jai` 真实生成（045 生产接线）。
  - 成员根冒烟块：先删成员 `target/`（会话产物）并 defer 再删；cwd = `packages/juice-plugin-lint` 跑真实 exe `test`；断言 exit 0、`3 passed, 0 failed`、stderr 无 `[juice lint]`（成员测试名全 snake_case，规则真阴性）。
- 未改生产代码、成员包与根 `package.jai`（零生产语义改动；`build_seam_write`/`fixture_line_col` 为既有测试助手）。

### 变更文件

- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\test_command_tests.jai`（头注释 + 全链 E2E 段：2 条测试 + 2 个源常量 + 1 个搭建助手）
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\docs\implementation\tickets\046-lint-full-chain-e2e.md`（本票）

### 验证矩阵（串行；根路径前清 `target/transpile`、`target/testing-module`、`target/plugins`）

| 路径 | 命令 | 结果 | 证据 |
| --- | --- | --- | --- |
| debug 自举 | `jai build.jai` | exit 0，产出 `target/juice.exe` | `target/audit-046-bootstrap-debug.txt` |
| debug 直跑 | `target/juice.exe test` | exit 0；顶层条目 478（max `juice_test_N` 473 + 手写 5；较 045 基线 476 恰 +2）；292 passed / 0 failed；白名单恰 6 行（组成不变）；SKIP 2（直跑已知自锁形态）；根套件 `juice lint` 零行；scratch 目录与成员 `target/` 运行后均不存在 | `target/audit-046-direct-test-debug.txt` |
| release 自举 | `jai build.jai - release` | exit 0 | `target/audit-046-bootstrap-release.txt` |
| release 直跑 | `target/juice.exe test` | exit 0；478（473 + 5）；292 passed / 0 failed；白名单 6；SKIP 2；`juice lint` 零行；scratch 已清 | `target/audit-046-direct-test-release.txt` |
| 副本跑（权威，SKIP 0） | `cp target/juice.exe target/juice-copy.exe` → `juice-copy.exe build` → `juice-copy.exe test` | build exit 0；test exit 0；SKIP 0；478（473 + 5）；292 passed / 0 failed；白名单恰 6 行；`juice lint` 零行；scratch 已清 | `target/audit-046-copy-build.txt`、`target/audit-046-copy-test.txt` |
| E2E 子进程实证（同形探针；套件内同一断言已过） | scratch 工作区 → `juice.exe test` | exit 0；stdout `[juice] Package 'lint-full-chain-e2e' (v0.1.0) discovered.`、`[test] BadName`、`[test] test_good_name`、`2 passed, 0 failed`；stderr `tests/bad_name_tests.jai:3,12: Warning: [juice lint] test procedure name must be snake_case: BadName`；无 `Error:` | `target/audit-046-e2e-child-probe.txt` |

套件内 E2E 执行证据：292 passed = 045 基线 290 + 2，0 failed 表示两条新 E2E 的全部断言（child stdout/stderr 文本、原始包相对路径 + 1 基坐标、registration 落位、成员根 3 passed 与零 lint）均通过；运行后 `target/lint-full-chain-e2e` 与 `packages/juice-plugin-lint/target` 均无残留。计数口径沿用既有约定（found = max `juice_test_N` + 手写 @test；白名单 = 存量 `expect failed` 6 行）。

### 偏差

1. **scratch 根包类型 = BIN**（票面允许「LIB 或 BIN」）：LIB 首探被 `resolve_artifact_plans` 拒绝——`[juice ERROR] Library package must provide module.jai at the package root or src/module.jai.`；BIN 无 targets 与既有 scratch E2E 根（bare-name-pass 等）一致，test 命令只消费 discovery/依赖准备/文件扫描。
2. **测试落点 = `tests/test_command_tests.jai`**（票面二选一）：该文件的 test 命令 E2E 族与 045 插件接线矩阵复用同一批助手，未改 `tests/e2e_cli_tests.jai`。
3. **成员根冒烟在测试内清理成员 `target/`**：运行前删、defer 再删（均为会话产物），避免 stale 视图遮蔽本次运行；静态成员树（`package.jai`/`module.jai`/`tests/`）零改动。
4. **继承行为（非本票改动）**：scratch 成员的 `DEP juice_core source="../../"` 按 040 决策 12 的根 CWD 锚定解析到 otter 根（shim 指向 `src/module.jai` 的剥离视图）；编译期 `#import "juice_core"` 由导入搜索第一顺位的 `<exe>/modules/juice_core.jai` 命中，该 shim 不参与编译。
