---
id: 047
title: 收尾：spec 折回 + 验收矩阵 + 关闭 040
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: [046]
blocks: []
---

> 父 spec：`040-spec-third-party-plugin-member-lint.md`（决定 13；US 36）。

# 047: 收尾：spec 折回 + 验收矩阵 + 关闭 040

**What to build:** 把设计规格折回执行级现实，跑完整验收矩阵并留下可审计记录，然后关闭父 spec。

**Blocked by:** 046

**Status:** closed

- [x] `docs/spec.md` 折回：§0（概述 + 目录树成员行）、§3.2（成员 = `packages/juice-plugin-lint`；内置 transpile 仍静态驻 src）、§5.1（`Juice_Plugin.lint`）、§5.2（声明面 = dependencies；扫描根；注册落点；lint 经测试 metaprogram 挂载）、§8.2（执行形态：观察面 + findings + 宿主报告；移除未落地的 `at_RUNNER_GEN`/`after_COMPILE` 收集步表述）。
- [x] `old-juice-exit.md` §5 插件行状态更新（真实成员包/lint 已交付）。
- [x] 验收矩阵记录：`jai build.jai` debug/release 各 exit 0；产物副本于根 build/test 全绿（SKIP 0、白名单恰 6、无新增失败）；真实成员根 test 全绿；全链 E2E 警告 + exit 0。
- [x] 040 写 `## Resolution` + `status: closed`；链票 Resolution 与计数记录随票落实。
- [x] 出范围面零改动（第三方 hook/transpile CLI 挂载、build 扫描、规则配置、非成员插件包等）。

## 复查修复（2026-10-21）

> 040 spec 独立复查的四项 minor findings 修复记录（F1-F4）。本票状态保持 open；本段是 047 收尾代理折回 `docs/spec.md` 与关闭 040 的证据面。

### F1 插件源读取失败 = 响亮失败（US 27）

- `scan_plugin_package`：`read_entire_file` 失败时保留 `could not read plugin source` 诊断并置 `result.ok = false`（此前 `ok` 保持 true、仅警告）；其余文件继续扫描以保持报告完整，消费者见 `ok = false` 整体弃用。`Plugin_Scan_Diagnostic` / `Plugin_Scan_Result` / 扫描函数与模块头注释同步（诊断桶不再只是被丢弃的重复项）。
- 传播链未改：`scan_workspace_plugins` 聚合 `member_scan.ok`；`test_compile_front` 的 `!scan.ok` → `[juice ERROR] Could not scan the workspace's plugin member packages for <root>` + 返回 false（HANDLER_FAILED）；该通道已由 045 命令层测试（构造 `ok=false` 快照 → 命令失败、spawn 零调用）钉住。
- 姊妹测试：`tests/plugin_scan_tests.jai`「源读取失败 = ok=false 响亮失败」——Windows 下用 share_mode=0 的独占读句柄（与 `artifact_is_running` 相同的 `CreateFileW` 开文件纪律）确定性制造共享冲突；断言 per-package `ok=false`、命中 0、诊断 1，再以构造快照经 `scan_workspace_plugins` 断言同频道 `ok=false`。非 Windows 分支为空（项目 Windows-first；POSIX 未覆盖，见残留风险）。
- 观测：套件日志出现两行 `Could not open file ... code 32`（per-package 与 workspace 各读一次），属预期响亮噪声，不改变计数/白名单。

### F2 跨包同名模块保留 DEP 段序

- `scan_workspace_plugins` 改为两阶段：先按 DEP 声明序收集每个成员的命中段（段内仍由既有 `scan_plugin_package`/`place_scan_hit` 裁定），再按段序经新增 `place_workspace_scan_hit` 合并。低探测序胜时把旧命中从其段位移除、把胜者追加到当前包段位（不再就地替换导致上提）；同级仍先累积者胜；丢弃诊断文案不变。
- 按包 `scan_plugin_package` 行为未改（`plugin-fixture` / `plugin-fixture-bad` 的 fixture E2E 输出不变）。
- 姊妹测试：扩展 `tests/data/plugin-workspace-rank`（zeta-extra 增 `alpha.jai`），命中序钉为 `[zeta-extra/alpha.jai, packages/extra/module.jai]`——后来的 rank-1 胜者必须排在先声明包的幸存命中之后；诊断仍恰 1 条（丢弃 `zeta-extra/extra.jai`）。

### F3 真实仓库根声明面永久测试

- `tests/plugin_scan_tests.jai` 新增「真实仓库根声明面」：`ensure_published_modules()` → `discover_workspace(otter_root(), <root>/target/plugin-scan-cache/repo-root, plugin_face_modules_dir())` → `scan_workspace_plugins`；断言 `ok`、诊断 0、恰 1 命中、`module_name == "juice-plugin-lint"`、`rel_path == "module.jai"`。
- modules 目录显式传发布面（`target/modules`）：测试程序在编译期由 jai.exe 承载，默认推导指向编译器旁 `modules/`，无法解析根 manifest 的 `#import "Juice"`。缓存与全部产物仅落 `target/` 下，不污染仓库。
- 043/044 的临时驱动（`target/check-044-*` 等）不再需要作为证据面；本测试为永久回归。

### F4 lint 级别默认零安全

- `Lint_Level` 重排为 `WARNING; ERROR; INFO;`（WARNING 成为零值成员，注释同步）；`Lint_Finding.level` 默认仍 `.WARNING`。生成 metaprogram 的 level→Report 映射按名比较，不依赖序号。
- 既有 `tests/plugin_tests.jai` lint 面测试增一条 `cast(Lint_Level) 0 == .WARNING` 断言（不新增测试计数）。
- 面序变更属 pre-release。040 决定 5 的原型枚举文序与 041 Resolution 的 `Lint_Level（ERROR/WARNING/INFO）` 表述已与代码不符；按「改记录不改已关票」原则在此记录——047 折回 `docs/spec.md` §5.1 时应写 WARNING 为零值成员，041 的表述以本段为准。

### 变更文件

- `C:\Users\maojiaxing\Workspace\projects\jai\otter\src\plugin_scan.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\src\plugin.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\plugin_scan_tests.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\plugin_tests.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\data\plugin-workspace-rank\package.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\data\plugin-workspace-rank\packages\zeta-extra\package.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\data\plugin-workspace-rank\packages\zeta-extra\alpha.jai`（新增）
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\docs\implementation\tickets\047-lint-effort-closeout.md`（本段）

### 验证矩阵（串行；各根路径前清 `target/transpile`、`target/testing-module`、`target/plugins`）

| 路径 | 命令 | 结果 | 证据 |
| --- | --- | --- | --- |
| debug 自举 | `jai build.jai` | exit 0，产出 `target/juice.exe` | `target/audit-review-fix-bootstrap-debug.txt` |
| debug 直跑 | `target/juice.exe test` | exit 0；SKIP 2（既有自锁形态）；顶层条目 480（max `juice_test_475` + 手写 5；046 基线 478，本次 +2 = 两条新增测试）；294 passed / 0 failed（基线 292 +2）；白名单恰 6 行（组成不变）；根套件 `juice lint` 零行 | `target/audit-review-fix-direct-test-debug.txt` |
| release 自举 | `jai build.jai - release` | exit 0 | `target/audit-review-fix-bootstrap-release.txt` |
| release 直跑 | `target/juice.exe test` | exit 0；SKIP 2；480（475 + 5）；294 passed / 0 failed；白名单 6；`juice lint` 零行 | `target/audit-review-fix-direct-test-release.txt` |
| 副本跑（权威，SKIP 0） | `cp target/juice.exe target/juice-copy.exe` → `target/juice-copy.exe build` → `target/juice-copy.exe test` | build exit 0；test exit 0；SKIP 0；480（475 + 5）；294 passed / 0 failed；白名单恰 6 行；`juice lint` 零行 | `target/audit-review-fix-copy-build.txt`、`target/audit-review-fix-copy-test.txt` |
| 成员根冒烟 | `cd packages/juice-plugin-lint && ../../target/juice.exe test` | exit 0；`3 passed, 0 failed`；`juice lint` 零行 | `target/audit-review-fix-member-test.txt` |
| 生产产物 | 副本跑后检查 | `target/plugins/registration.jai` 含 `JUICE_PLUGIN_0 :: #import "juice-plugin-lint";`；`target/transpile/first.jai` 含 `#import "juice_core";`、registration `#load`、`set_working_directory("<root>")`、merge 与 lint 观察调用；F3 缓存落 `target/plugin-scan-cache/repo-root/` | 副本跑日志 + 现场检查 |

### 残留风险

- F1 读取失败测试仅 Windows 生效（POSIX 分支为空，未覆盖）；项目现为 Windows-first。
- 读取失败时 File 模块会额外打一行原始 `Could not open file ... code 32` 日志（每个失败文件一次），与扫描诊断并存，属预期响亮输出。
- 043 Resolution 的「跨包复用 `place_scan_hit`」描述已被 F2 取代；裁定规则（低秩胜、同级先者胜、诊断文案）未变，仅位置语义修正。折回 040/043 相关叙述时以本段为准。

## Resolution

**状态：closed（2026-10-21）**

### 实现摘要

- `docs/spec.md` 折回执行级现实：
  - §0：概述加入真实交付面（真实成员 = `packages/juice-plugin-lint`；内置 transpile 插件仍静态驻 `src/`；test/transpile 插件成员未创建）；目录树成员行改为唯一真实成员。
  - §3.2：成员 = `packages/juice-plugin-lint`（LIB，`package.jai` + test-free 根部 `module.jai` + `tests/`）；其余计划成员未创建。
  - §5.1：`Juice_Plugin` 增 `lint: *Lint_Plugin = null`；补 `Lint_Level`（最终文序 `WARNING; ERROR; INFO;`，WARNING 零值成员）/`Lint_Finding`（1 基）/`Lint_Plugin` 形状；写明零值安全决定与 041 Resolution 文序的记录修正。
  - §5.2：声明面 = 既有 `workspace.members` + `dependencies`（零协议扩展）；扫描根 = 根 DEP 匹配成员、DEP 声明序 → 包内词法序；跨包同名模块保持 DEP 段序；读取/扫描失败 = `ok=false`；合并注册落 `<root>/target/plugins/registration.jai`；lint 由生成测试 metaprogram 加载（juice_core + registration + merge）。
  - §8.2：改写为执行形态（`.TYPECHECKED` 收集期观察 header + 扁平子表达式；宿主 `compiler_report` 三汇 + 原始包相对路径 + 1 基坐标；合并失败 = 编译错误；WARNING 不改退出码；pattern 过滤不隐藏 finding）；原 `at_RUNNER_GEN`/`after_COMPILE` 草案标记已废弃。
  - §11：新增第 11 项未来票（安装/打包布局下第三方插件加载受 `juice_core` 绝对路径闭包限制）；阶段 3 终态处置第 5 项更新为 lint 已交付。
- `docs/implementation/old-juice-exit.md`：§4 覆盖表 §0/§3/§5/§8/§11 行由「未来票」改为已交付（真实成员包 + 全链 lint）；§5 风险表第 5 项改为已交付（观察类诊断形状经 lint 面兑现）；新增第 11 项未来票行。
- `docs/implementation/tickets/040-spec-third-party-plugin-member-lint.md`：frontmatter `status: closed`，追加 `## Resolution`（逐决定 1-14 结果、交付摘要、验收矩阵、偏差/记录修正、未来票）。
- 本票：勾选验收项、`status: closed`、追加本 Resolution。
- **零生产代码改动**：本票只改 docs + 运行验证；`src/`、`tests/`、`packages/`、`package.jai`、`build.jai` 相对 046/复查修复终态均未变更；041-046 已关票未改动（记录修正写在本票与 040 Resolution）。

### 变更文件

- `C:\Users\maojiaxing\Workspace\projects\jai\otter\docs\spec.md`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\docs\implementation\old-juice-exit.md`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\docs\implementation\tickets\040-spec-third-party-plugin-member-lint.md`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\docs\implementation\tickets\047-lint-effort-closeout.md`
- 证据（会话产物）：`target/audit-047-bootstrap-debug.txt`、`target/audit-047-direct-test-debug.txt`、`target/audit-047-bootstrap-release.txt`、`target/audit-047-direct-test-release.txt`、`target/audit-047-copy-build.txt`、`target/audit-047-copy-test.txt`、`target/audit-047-member-test.txt`、`target/audit-047-artifacts.txt`

### 最终验收矩阵（2026-10-21；串行；各根路径前清 `target/transpile`、`target/testing-module`、`target/plugins`）

| 路径 | 命令 | 结果 | 证据 |
| --- | --- | --- | --- |
| debug 自举 | `jai build.jai` | exit 0 | `target/audit-047-bootstrap-debug.txt` |
| debug 直跑 | `target/juice.exe test` | exit 0；SKIP 2；480（max `juice_test_475` + 手写 5）；294 passed / 0 failed；白名单恰 6；`[juice lint]` 零行 | `target/audit-047-direct-test-debug.txt` |
| release 自举 | `jai build.jai - release` | exit 0 | `target/audit-047-bootstrap-release.txt` |
| release 直跑 | `target/juice.exe test` | exit 0；SKIP 2；480（475 + 5）；294 passed / 0 failed；白名单 6；`[juice lint]` 零行 | `target/audit-047-direct-test-release.txt` |
| 副本跑（权威，SKIP 0） | `cp target/juice.exe target/juice-copy.exe` → `target/juice-copy.exe build` → `target/juice-copy.exe test` | build/test 各 exit 0；SKIP 0；480（475 + 5）；294 passed / 0 failed；白名单恰 6 行；`[juice lint]` 零行 | `target/audit-047-copy-build.txt`、`target/audit-047-copy-test.txt` |
| 成员根冒烟 | `cd packages/juice-plugin-lint && ../../target/juice.exe test` | exit 0；3 passed / 0 failed；`[juice lint]` 零行；无 `target/plugins` | `target/audit-047-member-test.txt` |
| 产物检查 | 副本跑后检查 | `target/plugins/registration.jai` 含 `JUICE_PLUGIN_0 :: #import "juice-plugin-lint";`；`target/transpile/first.jai` 含 `#import "juice_core"`、注册 `#load`、`set_working_directory(<root>)`、merge 与 lint 观察调用；`juice_test_322/323`（046 全链 + 成员根 E2E）已执行；`target/lint-full-chain-e2e` 已清理 | `target/audit-047-artifacts.txt` |

### 偏差

1. 无功能性偏差；矩阵结果与 047 复查修复段预钉数值完全一致（480/294/6/SKIP 2 直跑、SKIP 0 副本、成员 3 passed）。
2. `old-juice-exit.md` 的插件/lint 行实际位于其 §4 覆盖表（而非 §5）；本票按语义更新 §4 的 §0/§3/§5/§8/§11 行与 §5 风险表第 5 项，并补第 11 项未来票行，避免残留「未来票」矛盾。
3. 直跑以 `target/juice.exe` 运行时两处 bootstrap E2E 自锁 SKIP 2，属既有环境形态；权威计数取副本跑（SKIP 0）。

### 残留风险与未来票

- F1 读取失败测试仅 Windows 生效（POSIX 分支为空）；项目 Windows-first。
- 安装/打包布局下的第三方插件加载不可用（`juice_core` 绝对路径闭包指向开发树 `src/`），已登记 spec §11.11 与 040 Resolution 未来票。
- `juice-plugin-test`/`juice-plugin-transpile` 成员、第三方 hook/transpile CLI 挂载、lint 规则配置面仍在 Out of Scope，归未来票。
