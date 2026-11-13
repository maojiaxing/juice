---
id: 050
title: 规范成员包分发契约：删除 juice_core DEP
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: [049]
blocks: [051]
---

> 父 spec：`048-spec-installed-layout-plugin-loading.md`（决定 9-10、16；US 10-17、36-37）。上游规格：`docs/spec.md` §3.2、§3.3。

# 050: 规范成员包分发契约：删除 juice_core DEP

**What to build:** 规范成员包 `packages/juice-plugin-lint` 成为可原样复制的分发形态：不再声明 `juice_core` 依赖，`#import "juice_core"` 由安装版工具的 `<exe>/modules` 提供。成员根作为自身 root 仍可构建与测试，根工作区的插件激活面（`workspace.members` + 根同名 DEP）完全不变。

**Blocked by:** 049

**Status:** closed

- [x] 规范成员包删除 `DEP juice_core source="../../"` 及相应注释；包仍是 LIB、根部 test-free 模块、自身测试驻 `tests/`。
- [x] 成员根作为自身 root 运行测试全绿：`juice_core` 经 `<exe>/modules` 解析，不依赖成员自己的依赖 shim。
- [x] 新增加固测试：解析规范成员包的清单，断言其依赖集为空（无工具依赖），防止分发契约回退。
- [x] 根工作区的插件扫描/激活面不变；真实仓库根声明面测试仍恰 1 命中（`juice-plugin-lint` / `module.jai`）。
- [x] 既有套件不回归；记录 found/passed/白名单。

## Resolution

**实现摘要**（2026-10-21）：规范成员包 `packages/juice-plugin-lint` 成为可原样复制的分发形态。`package.jai` 删除 `DEP juice_core source="../../"`，头注释改写为分发契约：`juice_core` 是工具提供的模块面（由已安装可执行文件的相邻 `modules/` 目录在每个编译子进程的导入路径上解析），包不声明该依赖、不携带任何 juice 检出路径；根工作区的激活面保持 `workspace.members` + 根同名 DEP 不变；成员根单独运行即自身 root，从运行它的工具解析 `juice_core`。成员形态不变：LIB、根部 test-free `module.jai`、自身测试驻 `tests/`。新增加固测试：经生产发现面（真 jai 评估子进程）加载真实成员清单，断言依赖集为空、成员为 LIB 且根部模块与 `tests/lint_rule_tests.jai` 存在；不做源文本 pin。变异自检证明该 pin 真实生效：临时恢复 DEP 即失败。

**变更文件**：

- `C:/Users/maojiaxing/Workspace/projects/jai/otter/packages/juice-plugin-lint/package.jai`：删除 `juice_core` 依赖声明；注释改写为分发契约（工具提供 `juice_core`、无 checkout 路径、激活面不变、成员根独立运行）。
- `C:/Users/maojiaxing/Workspace/projects/jai/otter/tests/plugin_scan_tests.jai`：文件头补 050 说明；在真实仓库根声明面测试旁新增 `工作区分发契约：规范成员包清单零依赖（juice_core 由工具提供）`（`juice_test_199`）：`discover_workspace` 生产发现 + 发布模块面评估真实清单，断言 `dependencies.count == 0`、`type == .LIB`、根 `module.jai` 与 `tests/lint_rule_tests.jai` 存在。

未改动：根 `package.jai` 激活面（`workspace.members` + 同名 DEP）、`src/plugin_scan.jai` 与扫描语义、父 spec 048、票 049、票 051/052。

**验证矩阵**（2026-10-21，串行；每次 test 前清 `target/transpile` / `target/testing-module` / `target/plugins`；证据 `otter/target/audit-050-*.txt`）：

| 步骤 | 命令 | 结果 |
| --- | --- | --- |
| 1 | `jai build.jai` | exit 0（`audit-050-01-build-debug.txt`） |
| 2 | `target/juice.exe test`（debug） | exit 0；**484 found**（`juice_test_N` 最大编号 479 + 手写 `note_suite_*` 5）；297 passed / 0 failed；`expect failed` 恰 6 行白名单；**SKIP 2**（自锁环境形态，`audit-050-02-test-debug.txt`） |
| 3 | `jai build.jai - release` | exit 0（`audit-050-03-build-release.txt`） |
| 4 | `target/juice.exe test`（release） | exit 0；同步骤 2：484 found、297 passed、白名单 6、SKIP 2（`audit-050-04-test-release.txt`） |
| 5 | `cp target/juice.exe target/juice-copy.exe`；`target/juice-copy.exe build`；`target/juice-copy.exe test` | build exit 0；test exit 0；**484 found**、297 passed / 0 failed、白名单 6、**SKIP 0**（权威，`audit-050-05-copy-build.txt` / `audit-050-05-copy-test.txt`） |
| 6 | 成员根冒烟：清 `packages/juice-plugin-lint/target`；`cd packages/juice-plugin-lint && ../../target/juice.exe test` | exit 0；成员自身 **3 passed / 0 failed**；无依赖准备失败；运行后 `target/packages` 为空 = 未生成 `juice_core` shim（`#import "juice_core"` 由相邻 `<exe>/modules` 解析）；事后清理成员 `target/`（`audit-050-06-member-root-smoke.txt`） |
| 7 | 根声明面：copy 跑生成的 `target/plugins/registration.jai`；成员清单依赖记录；真实仓库根扫描测试 | 恰一条 `JUICE_PLUGIN_0 :: #import "juice-plugin-lint";`；成员清单无 `dependencies` 记录；真实仓库根声明面测试（`hits.count == 1`、`module.jai`）在三次套件跑中全绿（`audit-050-07-declaration-surface.txt`） |
| 8 | 加固测试变异自检（辅助证据）：临时恢复 DEP → `target/juice.exe test juice_test_199`；还原 → 同命令 | 恢复 DEP 时 exit 1、`tests/plugin_scan_tests.jai:338:5: expect failed`、0 passed / 1 failed；还原后 exit 0、1 passed / 0 failed（`audit-050-08-pin-mutation-check.txt` / `audit-050-09-pin-restored-check.txt`） |

**计数**（基线 049：483 found = 478 + 5，296 passed）：本轮 **484 found = 479 + 5**（+1 = 新增分发契约 pin；它是 `test "..."` 块，由 EXPAND 改名 `juice_test_N`，故增量落在最大编号而非手写 `@test` 计数）；297 passed（+1）；`expect failed` 白名单仍恰 6 行；SKIP 直跑 2 / 副本 0（均不变）。

**偏差/风险**（无遗留缺陷）：

1. **契约 pin 的编号形态**：`test "..."` 块由 EXPAND 改名 `juice_test_N`，故 found 增量为最大编号 +1；与既有 found 约定一致，无测试丢失。
2. **`<exe>/modules` 解析的证明方式**：成员根跑后 `target/packages` 为空（无 `juice_core` 依赖 = 无 shim），编译仍成功；成员根无本地 `juice_core`，编译器默认模块目录也不含该面——解析只能来自相邻 `target/modules`（生产 `juice_modules_dir()` 按运行中可执行文件路径推导）。未做「移走 modules 应失败」的破坏性对照。
3. **安装布局全链 E2E 不在本票**：scratch 安装 + 真实成员 + lint 的全链归父 spec 048 的后续票（051/052；051 由本票解除阻塞）；本票以副本跑与成员根冒烟证明工具导入路径足够。
4. **文档折回未做**：`docs/spec.md` §0/§3.2/§3.3（成员描述仍写 `DEP juice_core source="../../"`）与 `old-juice-exit.md` 的折回归 048 决定 15 的收尾票；本票按范围未改 spec 048、049、051/052。
