---
id: 051
title: 安装布局插件全链 E2E
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: [049, 050]
blocks: [052]
---

> 父 spec：`048-spec-installed-layout-plugin-loading.md`（决定 1-3、7-9、12；US 1-9、18-25、33-35、39-40）。上游规格：`docs/spec.md` §9.2、§11.11。

# 051: 安装布局插件全链 E2E

**What to build:** 用真实安装形态证明第三方插件加载：把真实 exe 与 `modules/` 整树复制到无 `src/` 的 scratch 安装，驱动含真实成员包的 scratch 工作区，得到 lint 警告、测试照常执行、exit 0；同一安装版 exe 在复制出的成员根跑其自身套件全绿。测试同时钉住安装产物契约：`juice_core` 只含相对 `#load`、无绝对路径、每个目标都存在于安装内。

**Blocked by:** 049、050

**Status:** closed

- [x] scratch 安装 = 真实 exe + 递归复制的 `modules/` 整树；断言安装内没有同级 `src/` 或 `target/`。
- [x] 安装产物契约：`juice_core.jai` 只含相对 `#load`，不出现构建根、盘符或绝对路径；四个闭包件齐全且每个 `#load` 目标都存在于安装内。
- [x] scratch 工作区含根清单（`workspace.members` + 同名 DEP）、从真实成员包逐字节复制的完整包树（含 `tests/`）、一个坏命名的 `@test`。
- [x] 安装版 exe 在 scratch 根跑 `test`：exit 0；两个测试照常执行并计数；stderr 含 `[juice lint]` 警告、原始包相对路径与 1 基坐标；警告不改变退出码。
- [x] 同一安装版 exe 在复制出的成员根跑 `test`：exit 0，成员自身测试全绿。
- [x] 既有「无插件安装布局」E2E 保持全绿；新 E2E 运行前清理 scratch 安装与工作区，避免陈旧副本掩盖缺失的复制逻辑。
- [x] 根自跑套件 debug+release 与副本跑全绿；记录 found/passed/白名单。

## Resolution

**实现摘要**（2026-10-21）：新增安装布局第三方插件全链 E2E（`tests/test_command_tests.jai` 的 `E2E: an installed juice runs the real member plugin and lints a scratch workspace`，套件内为 `juice_test_328`）。测试只用会话产物目录：把真实 `target/juice.exe` 与发布后的 `target/modules` 整树（递归含 `juice_internal/plugin_face/` 四件）复制到 `target/installed-plugin-e2e/bin`，断言安装树内及其 exe 邻接层都没有 `src/` 或 `target/`；随后在安装的 `modules/juice_core.jai` 上钉安装产物契约——逐行解析 `#load` 目标，要求恰为 `JUICE_CORE_LOAD_FILES` 顺序的四个相对路径、无盘符/绝对路径/反斜杠、文件不含构建根，四件闭包副本存在，每个目标解析后位于安装 modules 内。scratch 工作区（`target/installed-plugin-e2e-workspace`）使用既有 046 常量（`workspace.members` + 同名根 DEP）与坏命名测试源，成员包树经 `visit_files` 逐字节复制整棵真实 `packages/juice-plugin-lint`（`package.jai`、`module.jai`、`tests/lint_rule_tests.jai`；成员会话产物 `target/` 不随树复制）并逐文件与源比对。安装版 exe 在 scratch 根 `test`：exit 0、`BadName` 与 `test_good_name` 都执行、`2 passed, 0 failed`、stderr 带 `tests/bad_name_tests.jai:3,12: Warning: [juice lint] test procedure name must be snake_case: BadName`（坐标由 scratch 源按 1 基现算）且无 `Error:` 行、workspace 级注册文件落地。同一安装版 exe 在复制出的成员根 `test`：exit 0、`3 passed, 0 failed`。scratch 安装与工作区在测试前后各删除一次。未改生产代码（未发现缺陷）；既有「无插件安装布局」E2E（`juice_test_320`）与成员根 E2E 保持全绿。

**变更文件**：

- `C:/Users/maojiaxing/Workspace/projects/jai/otter/tests/test_command_tests.jai`：文件头补 051 说明；新增 `PUBLISHED_LOAD_PREFIX`、`published_module_load_paths`（解析发布模块的行首 `#load "<path>";`）、`Copy_Member_Tree_Context` / `copy_member_tree_visitor` / `copy_real_member_tree`（整棵真实成员包树逐字节复制，跳过成员 `target/`）与 051 E2E 测试块；复用 046 的 `LINT_FULL_CHAIN_PACKAGE_SOURCE` / `LINT_FULL_CHAIN_TEST_SOURCE`、`fixture_line_col`、`child_output_contains`、`expect_exit`、`output_matches` 与发布/安装助手，未新增第二份清单或第二套契约常量。
- `C:/Users/maojiaxing/Workspace/projects/jai/otter/docs/implementation/tickets/051-installed-layout-plugin-e2e.md`：验收框全勾、`status: closed`、本 Resolution。

未改动：父 spec 048、票 049/050/052、任何 `src/`、`build.jai`、`package.jai`、`packages/` 生产文件。

**验证矩阵**（2026-10-21，串行；每次 test 前清 `target/transpile` / `target/testing-module` / `target/plugins`；证据 `otter/target/audit-051-*.txt`）：

| 步骤 | 命令 | 结果 |
| --- | --- | --- |
| 0 | `target/juice.exe test __no_such_test_pattern__`（辅助编译检查） | exit 0；新测试代码编译通过，pattern 零命中不执行 runner（`audit-051-00-compile-check.txt`） |
| 1 | `jai build.jai` | exit 0（`audit-051-01-build-debug.txt`） |
| 2 | `target/juice.exe test`（debug） | exit 0；**485 found**（`juice_test_N` 最大编号 480 + 手写 `note_suite_*` 5）；298 passed / 0 failed；`expect failed` 恰 6 行白名单（与 050 逐行相同）；**SKIP 2**（自锁环境形态；`audit-051-02-test-debug.txt`） |
| 3 | `jai build.jai - release` | exit 0（`audit-051-03-build-release.txt`） |
| 4 | `target/juice.exe test`（release） | exit 0；同步骤 2：485 found、298 passed、白名单 6、SKIP 2（`audit-051-04-test-release.txt`） |
| 5 | `cp target/juice.exe target/juice-copy.exe`；`target/juice-copy.exe build`；`target/juice-copy.exe test` | build exit 0；test exit 0；**485 found**、298 passed / 0 failed、白名单 6、**SKIP 0**（权威，`audit-051-05-copy-build.txt` / `audit-051-05-copy-test.txt`） |
| 6 | 安装产物契约独立检查（复制 exe + modules 到 scratch，检查 layout、`juice_core.jai` 四行相对 `#load`、四件闭包副本、目标全部存在、无构建根） | 全部通过；无同级 `src/`/`target/`；无构建机路径（`audit-051-06-install-contract.txt`） |
| 7 | 安装形貌手工复现（同一安装版 exe）：scratch 根 `test`；复制出的成员根 `test` | 根：exit 0、`2 passed, 0 failed`、stderr `tests/bad_name_tests.jai:3,12: Warning: [juice lint] ... BadName`、无 `Error:`；成员根：exit 0、`3 passed, 0 failed`（`audit-051-07-installed-e2e-repro.txt`） |
| 8 | 套件内证据 | 新 E2E `[test] juice_test_328` 在 debug/release/copy 三次跑中均出现且 0 failed；既有「无插件安装布局」E2E `[test] juice_test_320` 同样出现且所在套件 0 failed（三份 `audit-051-02/04/05`） |

**计数**（基线 050：484 found = 479 + 5，297 passed）：本轮 **485 found = 480 + 5**（+1 新 E2E；`test "..."` 块由 EXPAND 改名 `juice_test_N`，增量落在最大编号）；298 passed（+1）；`expect failed` 白名单仍恰 6 行（与 050 diff 逐行相同）；SKIP 直跑 2 / 副本 0（均不变）。终局 `M passed` 仍受 Testing 自测 `finish()` 重置的既有约定位移影响，权威口径按 found 与「白名单恰 6 行 + exit 0」。

**偏差/风险**（无遗留缺陷）：

1. **成员树复制的边界**：整棵真实成员包树逐字节复制（`package.jai`、`module.jai`、`tests/lint_rule_tests.jai` 逐文件与源相等 pin），但跳过成员的会话产物 `target/`（非包源码；若上一次成员冒烟留下 target/，复制它会让陈旧产物进入 scratch）。「含 tests/」的验收面完整。
2. **根清单复用 046 常量**：包名仍为 `lint-full-chain-e2e`；本票只钉声明面（`workspace.members` + 同名根 DEP），不复用 046 的 scratch 路径，二者互不干扰。
3. **警告坐标的求法**：与 046 相同，从 scratch 源以 `fixture_line_col` + header `"("` 列偏移现算（1 基），测试程序从不硬编码行号。
4. **辅助证据与自动化测试分离**：步骤 6/7 是审计用的手工复现，正式断言全部在套件内 E2E；两者结论一致。手工复现的 stderr 另含两条 `Unable to open directory .../src`、`.../modules`（`visit_files` 对不存在目录的既有噪音，与结果无关）。
5. **未改生产代码**：安装布局与插件加载路径经本 E2E 证明无需修复；父 spec 048 与 052（文档折回）仍按 048 决定 15 由后续票处理。

