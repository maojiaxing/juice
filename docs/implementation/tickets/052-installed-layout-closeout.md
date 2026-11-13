---
id: 052
title: 收尾：docs 折回 + 验收矩阵 + 关闭 048
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: [051]
blocks: []
---

> 父 spec：`048-spec-installed-layout-plugin-loading.md`（决定 15；US 43-44）。

# 052: 收尾：docs 折回 + 验收矩阵 + 关闭 048

**What to build:** 把设计规格折回执行级现实，跑完整验收矩阵并留下可审计记录，然后关闭父 spec。本票只改文档与验收记录，不改生产代码或测试。

**Blocked by:** 051

**Status:** closed

- [x] `docs/spec.md` 折回：§0（生成件清单与目录树）、§3.2/§3.3（成员与分发契约）、§9.2（产物集与相对加载）、§11.11（安装布局插件加载的处置）。
- [x] `old-juice-exit.md` 的 §4/§5 对应行更新：安装布局插件加载已交付，不再列为未来票。
- [x] 验收矩阵记录：`jai build.jai` debug/release 各 exit 0；产物副本于根 build/test 全绿（SKIP 0、白名单恰 6、无新增失败）；真实成员根 test 全绿；安装布局全链 E2E 全绿。
- [x] 048 写 Resolution（逐决定 1-16 结果、交付摘要、验收矩阵、偏差与记录修正），`status: closed`。
- [x] 生产代码与测试零改动（相对 051 终态）；040/047 等已关票不改，记录修正写在本票 Resolution。

## Resolution

**实现摘要**（2026-10-21）：文档折回与验收矩阵完成。`docs/spec.md` 已折回执行级现实：§0 生成件清单与目录树加入 `<modules>/juice_internal/plugin_face/` 四份闭包副本，成员描述改为零工具依赖并写明安装契约（exe + 相邻 `modules/`，无同级 `src/`/`target/`）；§3.2 成员描述与 §3.3 分发契约改写为「`juice_core` 是工具提供的模块面、不是工作区依赖」，成员间 DEP 纪律原样保留；§5.2 引用形态、§9.2 产物集/相对加载/行数、§9.6、§10 阶段 2/3 与接缝 1 的产物集表述同步订正；§11.11 由未来票改为已交付（2026-10-21，048 effort）并补一段处置与证据。`old-juice-exit.md` §4 覆盖表的 §0/§3/§5/§9/§11 行与 §5 风险表第 11 行改为安装布局插件加载已交付。父 spec 048 已写 Resolution 并置 `status: closed`。

**变更文件**：

- `C:/Users/maojiaxing/Workspace/projects/jai/otter/docs/spec.md`：§0（两处 + 生成件行）、§3.2、§3.3、§5.2、§9.2（标题 + `juice_core` 条目 + 新增插件面闭包副本条目 + 行数）、§9.6、§10（阶段 2/3 与接缝 1）、§11.11 与阶段 3 终态处置段。
- `C:/Users/maojiaxing/Workspace/projects/jai/otter/docs/implementation/old-juice-exit.md`：§4 覆盖表 §0/§3/§5/§9/§11 五行；§5 风险表第 11 行。
- `C:/Users/maojiaxing/Workspace/projects/jai/otter/docs/implementation/tickets/048-spec-installed-layout-plugin-loading.md`：`status: closed` + `## Resolution`（交付摘要、逐决定 1-16 结果、验收矩阵、偏差与记录修正）。
- `C:/Users/maojiaxing/Workspace/projects/jai/otter/docs/implementation/tickets/052-installed-layout-closeout.md`：验收框全勾、`status: closed`、本 Resolution。

未改动：任何 `src/`、`tests/`、`build.jai`、`package.jai`、`packages/` 生产文件；票 049-051（已关）与 040/047 等已关票正文。

**验收矩阵**（2026-10-21，串行；每次 test 前清 `target/transpile` / `target/testing-module` / `target/plugins`；证据 `otter/target/audit-052-*.txt`）：

| 步骤 | 命令 | 结果 |
| --- | --- | --- |
| 1 | `jai build.jai` | exit 0（`audit-052-01-build-debug.txt`） |
| 2 | `target/juice.exe test`（debug） | exit 0；**485 found**（`juice_test_N` 最大编号 480 + 手写 `note_suite_*` 5）；298 passed / 0 failed；`expect failed` 恰 6 行白名单；**SKIP 2**（bootstrap 自锁；`audit-052-02-test-debug.txt`） |
| 3 | `jai build.jai - release` | exit 0（`audit-052-03-build-release.txt`） |
| 4 | `target/juice.exe test`（release） | exit 0；485 found、298 passed、白名单 6、SKIP 2（`audit-052-04-test-release.txt`） |
| 5 | 副本跑：`cp target/juice.exe target/juice-copy.exe`；`target/juice-copy.exe build`；`target/juice-copy.exe test` | build exit 0；test exit 0；**485 found**、298 passed / 0 failed、白名单 6（与直跑逐行相同）、**SKIP 0**（权威；`audit-052-05-copy-build.txt` / `audit-052-05-copy-test.txt`） |
| 6 | 成员根冒烟：清 `packages/juice-plugin-lint/target`；成员根 `../../target/juice.exe test`；事后清理 | exit 0；成员自身 **3 passed / 0 failed**（`audit-052-06-member-root-smoke.txt`） |
| 7 | 安装产物检查 | `juice_core.jai` 仅四行相对 `#load`，无盘符/绝对路径/反斜杠/构建根；四闭包副本与 `src/` 逐字节相等；每个加载目标在发布树内；产物集八件；行数 131 / 237 / 16 / 285 / 571 / 553 / 243 / 380（`audit-052-07-artifact-inspection.txt`） |
| 8 | 套件内 E2E 证据 | 安装布局插件全链 `juice_test_328` 与无插件安装布局 `juice_test_320` 在 debug/release/copy 三次跑各出现一次、套件均 0 failed；直跑 SKIP 仅 bootstrap 两行（`audit-052-08-suite-e2e-evidence.txt`） |

**计数**（基线 051：485 found = 480 + 5，298 passed，白名单 6，SKIP 直跑 2 / 副本 0）：本轮完全一致，无新增/丢失测试。终局 `298 passed` 受 Testing 自测 `finish()` 重置影响，不等于 found（既有约定）；权威口径 = exit 0 + max `juice_test_N` + 手写条目 + 白名单恰 6 行。

**偏差/记录修正**（无遗留缺陷）：

1. **行数订正**：`juice_core.jai` 12 → 16 行（049 相对加载形态）；spec §9.2 与 old-juice-exit §4 已就地更新，并补记四闭包副本行数 571/553/243/380。
2. **旧文档措辞订正**：spec §0 成员 DEP/发布清单、§3.3 与 §5.2 的「异名 DEP `juice_core`」形态、§9.6/§10 产物集、§11.11 未来票状态均为 040 时代表述，与本轮执行级现实冲突；按 048 决定 15 折回。040/047 已关票正文未改，修正记录于本票与 048 Resolution。
3. **成员根噪音**：`Unable to open directory .../packages/juice-plugin-lint/modules` 为 `visit_files` 对不存在目录的既有噪音（051 偏差 4 同款），不影响 exit 0 / 3 passed。
4. **生产代码与测试零改动**：相对 051 终态；仅文档与 `target/audit-052-*` 证据新增（会话产物）。本仓库无 git，改动留在工作树。
