---
id: 053
title: 复查修复：安装布局插件加载（048）
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: [052]
blocks: []
---

> 父 spec：`048-spec-installed-layout-plugin-loading.md`（决定 1-16；US 1-44）。上游规格：`docs/spec.md` §9.2、§11.11。来源：048 effort 完成后的独立复查（2026-10-21），结论「approve with minor issues」——五项发现，无功能缺陷。本票只改测试与文档，不改生产语义；已关票 048-052 正文不改，修复记录写在本票与 `old-juice-exit.md`。

# 053: 复查修复：安装布局插件加载（048）

**What to build:** 关闭复查的五项发现：补齐安装布局缺闭包件的负向 E2E（F1）；把缺源测试从「仅内存备份 + 未校验恢复」改为崩溃安全的 target/ 备份移出（F2）；订正 `old-juice-exit.md` 的历史口径（F3）；把「无构建根」断言从 `juice_core` 扩展到整棵已发布 `modules/` 树（F4）；记录可执行文件内嵌构建机 caller-location 路径的残留风险（F5）。

**Blocked by:** 052（已关）

## 发现与修复

| # | 级别 | 发现 | 修复 |
| --- | --- | --- | --- |
| F1 | minor | 安装布局 E2E 没有「安装缺一个插件面闭包件」的负向用例（048 决定 12 / US 4） | 在 `tests/test_command_tests.jai` 的安装布局全链 E2E（`juice_test_328`）末尾、全部正向断言之后，仅从 scratch 安装删除 `juice_internal/plugin_face/plugin.jai`，重跑安装版 exe 的 `test`：断言 exit 1、stderr 含 jai 原始编译错误（`Error: Unable to open file`，路径命名 `plugin.jai`）、stdout 报 `[juice ERROR] Test compilation failed.` 且不出现测试启动行/汇总/`No tests found`（不降级为绿或零插件）。 |
| F2 | minor | 两处缺源测试对仓库源文件只做内存备份与未校验恢复，进程被杀时源可能丢失 | `tests/test_support.jai` 新增 `park_source_file` / `restore_source_file`：先把源写入 `target/missing-source-backups/` 备份并回读校验，再删除原文件；恢复时回读校验并删除备份。`tests/publication_tests.jai` 的缺闭包源测试与 `tests/bootstrap_tests.jai` 的三处缺源 E2E（定义源、发现源、闭包源）全部改用该助手；恢复在 defer 中 `expect` 断言。覆盖复查要求的两处，并顺带覆盖同模式的既有两处。 |
| F3 | nit | `old-juice-exit.md` §3（~41 行）仍写「131 / 237 / 12 / 285 行」，§1（~11 行）描述四件产物，均缺四份插件面副本 | §1/§3 加历史口径说明：这两节记录 2026-10-20（039）观测；2026-10-21（048）起产物集为八件、`juice_core` 为 16 行，当前口径见 §4/§5。历史矩阵按原观测保留，不回填。 |
| F4 | nit | US 33 的「无构建根」自动断言只扫 `juice_core` | 安装布局 E2E 新增整棵已发布 `modules/` 树的 `.jai` 扫描：每个文件不得含构建根或 `otter_root()`，所有行首 `#load` 目标必须相对（无盘符/绝对路径/反斜杠），并钉产物数为 8（三模块面 + 发现源 + 四闭包副本）。exe 不在扫描范围。 |
| F5 | nit | 可执行文件内嵌构建机 caller-location 路径（既有，非本 effort） | 无代码修复。本票与 `old-juice-exit.md` §5 记录残留风险：失败诊断可能打印构建机源码路径；不影响模块/插件解析；「整棵安装树无构建根」断言必须排除 exe。 |

## 变更文件

- `C:/Users/maojiaxing/Workspace/projects/jai/otter/tests/test_command_tests.jai`：新增 `Published_Tree_Scan_Context` / `published_tree_scan_visitor` / `scan_published_tree`（F4）；安装 E2E 增加整树扫描与缺闭包件负向用例（F1）。
- `C:/Users/maojiaxing/Workspace/projects/jai/otter/tests/test_support.jai`：新增 `park_source_file` / `restore_source_file`（F2）。
- `C:/Users/maojiaxing/Workspace/projects/jai/otter/tests/publication_tests.jai`：缺闭包源测试改用崩溃安全移出（F2）。
- `C:/Users/maojiaxing/Workspace/projects/jai/otter/tests/bootstrap_tests.jai`：三处缺源 E2E 改用崩溃安全移出（F2）。
- `C:/Users/maojiaxing/Workspace/projects/jai/otter/docs/implementation/old-juice-exit.md`：§1/§3 历史口径说明（F3）；§5 残留风险（F5）。
- 本票。

未改动：`src/`、`build.jai`、`package.jai`、`packages/` 生产文件；已关票 048-052 正文。

## Verification

**2026-10-21，串行执行；每次 test 前清 `target/transpile` / `target/testing-module` / `target/plugins`；证据 `otter/target/audit-053-*.txt`。**

| 步骤 | 命令 | 结果 |
| --- | --- | --- |
| 0 | `target/juice.exe test __no_such_test_pattern__`（编译检查） | exit 0；改动的测试代码编译通过，pattern 零命中不执行 runner（`audit-053-02-compile-check.txt`） |
| 1 | 聚焦安装 E2E：`target/juice.exe test juice_test_328` | exit 0；1 passed / 0 failed。正向根/成员根断言之后，新增的缺闭包件负向用例真实执行并通过：删除 scratch 安装的 `juice_internal/plugin_face/plugin.jai` 后重跑，exit 1、stderr 含 jai 原始错误 `Error: Unable to open file` 且命名 `plugin_face/plugin.jai`、stdout 报 `[juice ERROR] Test compilation failed.`，无测试启动行/汇总/`No tests found`；F4 整树扫描与 8 件产物数断言同块通过（`audit-053-03-focused-installed.txt`） |
| 2 | 缺源聚焦：`juice_test_244`（publication 缺闭包源） | exit 0；1 passed / 0 failed；park/restore 走 target/ 备份并回读校验（`audit-053-04-focused-missing-publication.txt`） |
| 3 | 缺源聚焦：`juice_test_15`（pattern 匹配 15 + 150-159） | exit 0；11 passed / 0 failed；含自举缺定义源 E2E，运行后 `src/module.jai` 存在（`audit-053-05-focused-missing-definition.txt`） |
| 4 | 缺源聚焦：`juice_test_16`（16 + 160-169） | exit 0；11 passed / 0 failed；含自举缺发现源 E2E，运行后 `src/test_discovery.jai` 与四闭包副本存在（`audit-053-06-focused-missing-discovery.txt`） |
| 5 | 缺源聚焦：`juice_test_17`（17 + 170-179） | exit 0；11 个顶层条目执行；含自举缺闭包源 E2E，运行后 `src/lifecycle.jai` 存在；`expect failed` 2 行为 pattern 带入的 Testing 自测白名单（`audit-053-07-focused-missing-closure.txt`） |
| 6 | 全矩阵 debug：`jai build.jai`；`target/juice.exe test` | build exit 0（`audit-053-01`）；test exit 0；**485 found**（max `juice_test_N` 480 + 手写 5）；298 passed / 0 failed；`expect failed` 恰 6 行白名单；**SKIP 2**（自锁环境形态；`audit-053-08-test-debug.txt`） |
| 7 | 全矩阵 release：`jai build.jai - release`；`target/juice.exe test` | build exit 0（`audit-053-09`）；test exit 0；485 found、298 passed / 0 failed、白名单 6、SKIP 2（`audit-053-10-test-release.txt`） |
| 8 | 副本跑：`cp target/juice.exe target/juice-copy.exe`；`target/juice-copy.exe build`；`target/juice-copy.exe test` | build exit 0（`audit-053-11-copy-build.txt`）；test exit 0；**485 found**、298 passed / 0 failed、白名单 6（与直跑逐行相同）、**SKIP 0**（权威；`audit-053-12-copy-test.txt`） |
| 9 | 成员根冒烟：清 `packages/juice-plugin-lint/target`；成员根 `../../target/juice.exe test`；事后清理 | exit 0；成员自身 **3 passed / 0 failed**；成员 `target/` 已清理（`audit-053-13-member-root-smoke.txt`） |
| 10 | 安装产物检查 | 8 件（三模块面 + 发现源 + 四闭包副本）；`juice_core.jai` 16 行、仅四行相对 `#load`；四副本与 `src/` 逐字节相等（`cmp`）；发布树无构建根/`otter_root()`；行数 131 / 237 / 16 / 285 / 571 / 553 / 243 / 380（`audit-053-14-artifact-inspection.txt`） |
| 11 | 套件后仓库源检查 | `src/lifecycle.jai`、`src/module.jai`、`src/test_discovery.jai` 均在；`target/missing-source-backups/` 零残留文件；事后 `jai build.jai` exit 0（`audit-053-15-repo-source-check.txt`） |

**计数**（基线 052：485 found = 480 + 5，298 passed，白名单 6，SKIP 直跑 2 / 副本 0）：本轮完全一致，**delta 0**。F1 的负向用例与 F4 的整树扫描是 `juice_test_328` 块内的新增断言，不新增顶层条目；F2 只替换缺源测试的 park/restore 实现，不新增测试。终局 `298 passed` 仍受 Testing 自测 `finish()` 重置的既有约定位移影响，权威口径 = exit 0 + max `juice_test_N` + 手写条目 + 白名单恰 6 行。

## Resolution

**实现摘要**（2026-10-21）：复查五项发现全部关闭，无生产代码改动。

1. **F1（安装缺闭包件负向 E2E）**：扩展 `tests/test_command_tests.jai` 的安装布局全链 E2E（`juice_test_328`）。在正向根工作区与成员根运行之后，仅从 scratch 安装删除 `juice_internal/plugin_face/plugin.jai`（仓库副本不动），用同一安装版 exe 在 scratch 根重跑 `test`。jai 在编译 `juice_core` 的相对 `#load` 时以原始错误 `Error: Unable to open file '…/plugin_face/plugin.jai' for reading.` 失败；安装版命令 exit 1 并打印 `[juice ERROR] Test compilation failed.`；断言无测试启动行、无通过汇总、无 `No tests found` 降级。048 决定 12 / US 4 由此有了自动负向证据。
2. **F2（崩溃安全缺源移出）**：`tests/test_support.jai` 新增 `park_source_file` / `restore_source_file`。park 先读源、写 `target/missing-source-backups/` 备份、回读校验，再删除原文件；restore 读备份、写回源、回读校验并删除备份。两处复查指出的测试（publication 缺闭包源、bootstrap 缺闭包源）与同模式的两处既有测试（bootstrap 缺定义源、缺发现源）全部改用该助手，恢复在 defer 中 `expect` 断言；不再存在「唯一副本只在内存」的窗口：被杀时备份已在磁盘且已验证。
3. **F3（历史口径）**：`old-juice-exit.md` §1 退场条件与 §3 最终验收矩阵各加历史口径说明：两节记录 2026-10-20（039）观测（四件产物、`juice_core` 12 行）；2026-10-21（048）起为八件产物、`juice_core` 16 行，当前口径以 §4/§5 为准。历史矩阵未回填。
4. **F4（整树无构建根扫描）**：安装 E2E 新增 `scan_published_tree`：遍历安装内 `modules/` 整棵树的每个 `.jai` 文件，断言不含构建根、不含测试面 `otter_root()` 字样，所有行首 `#load` 目标相对且无反斜杠/盘符，并钉产物数 8（三模块面 + 发现源 + 四闭包副本）。US 33 的字节 pin 盲点（只扫 `juice_core`）关闭；exe 明确不在扫描范围。
5. **F5（exe 内嵌构建机路径残留风险）**：无代码修复（既有、非本 effort）。本票与 `old-juice-exit.md` §5 记录：caller-location 诊断可能打印构建机源码路径，不影响模块/插件解析；「整棵安装树无构建根」断言必须排除 exe，只扫发布 `modules/` 树。

**变更文件**：`tests/test_command_tests.jai`（F1/F4）、`tests/test_support.jai`（F2）、`tests/publication_tests.jai`（F2）、`tests/bootstrap_tests.jai`（F2）、`docs/implementation/old-juice-exit.md`（F3/F5）、本票。未改 `src/`、`build.jai`、`package.jai`、`packages/`；未改已关票 048-052 正文。

**验证**：见上表，debug/release/副本三路径全绿，计数与 052 基线逐项一致（delta 0）；成员根 3 passed；安装产物八件且无构建根；套件后仓库源完整、无备份残留。

**残留风险**：
1. **F5（既有，出范围）**：可执行文件内嵌构建机 caller-location 路径；失败诊断可能打印构建机路径。不影响模块/插件解析；整树「无构建根」断言按约定只扫 `modules/` 树。
2. **版本漂移 E2E 的源改写（既有，非缺源模式）**：`tests/bootstrap_tests.jai` 的版本漂移测试把 `package.jai` 在内存中改写成 `9.9.9` 并在 defer 恢复，仍是「内存备份」形态；进程被杀会留下内容确定的漂移（`9.9.9` → `0.1.0` 一处），可按已知内容修复。该测试不删除源文件，不属 F2 的缺源范围，本轮未改，记录为残余风险。
3. **被杀后的下一次运行**：若套件在缺源窗口被杀，`target/missing-source-backups/<name>.jai` 保留且已验证；需先从备份恢复对应 `src/` 文件（内容已校验）才能再次编译套件——这是崩溃安全移出的预期恢复路径。

