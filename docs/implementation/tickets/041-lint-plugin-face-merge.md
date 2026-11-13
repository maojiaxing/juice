---
id: 041
title: lint 插件面 + 合并收集
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: []
blocks: [042, 044]
---

> 父 spec：`040-spec-third-party-plugin-member-lint.md`（决定 5；US 8-11）。上游规格：`docs/spec.md` §5.1（插件面）、§5.2（合并查重）。

# 041: lint 插件面 + 合并收集

**What to build:** 插件作者可以在 `Juice_Plugin` 上声明一个 lint 面，经合并注册后由消费方拿到 `lint_plugins`；空规则名与跨插件重名在合并期被拒绝。这个票只交付库面与合并语义，宿主消费在 042。

**Blocked by:** None（可立即开工）

**Status:** ready-for-agent

- [x] 插件库面新增 `Lint_Level`（ERROR/WARNING/INFO）、`Lint_Finding`（1 基 line/column、message、默认 WARNING）、`Lint_Plugin`（name、version、`inspect_test_header(header: *Code_Procedure_Header, subexpressions: [] *Code_Node) -> [..] Lint_Finding`）；`plugin` 库面新增 `#import "Compiler"`。
- [x] `Juice_Plugin` 增可空 `lint: *Lint_Plugin = null`；`Merged_Plugins` 增 `lint_plugins: [..] Lint_Plugin`。
- [x] `merge_plugins` 收集非空 lint 面；空 `name`、跨插件重名 = 诊断 + `ok = false`；既有 id/版本、transpile 名、at 独占查重不回归。
- [x] `juice_core` 发布面照常编译、产物数量与文本契约不变（`plugin` 已在 `#load` 闭包内）。
- [x] 姊妹测试覆盖面形状、收集顺序、空名/重名拒绝；既有套件根自跑 debug+release 全绿。

## Resolution

**状态：closed（2026-10-21）**

### 实现摘要

- `src/plugin.jai` 新增 lint 面：`Lint_Level`（ERROR/WARNING/INFO）、`Lint_Finding`（1 基 line/column 契约、message、`level` 默认 `.WARNING`）、`Lint_Plugin`（name/version/`inspect_test_header(header: *Code_Procedure_Header, subexpressions: [] *Code_Node) -> [..] Lint_Finding`）；文件顶部新增 `#import "Compiler"`，仅供 header/node 类型引用。
- `Juice_Plugin` 增可空面 `lint: *Lint_Plugin = null`；`Merged_Plugins` 增 `lint_plugins: [..] Lint_Plugin`。
- `merge_plugins` 按注册序收集非空 lint 面（值拷贝）；空规则名 = 诊断 + `ok=false`；跨插件重名 = 诊断 + `ok=false`（消息形如 `lint plugin name conflict: <name> (<owner> vs <id>)`，与 transpile 名冲突同款式）。既有 id/版本、transpile 名、at 独占查重路径未改动；被拒的 lint 面仍进入合并产物，与既有"产物填充优先、`ok=false` 阻断调用方"的形状一致。
- 姊妹测试新增 5 条：面形状（可空、1 基字段、默认 WARNING、观察者经面可调用）、注册序收集（无面插件不占位）、无 lint 面零贡献（含内置注册表）、空名拒绝、跨插件重名拒绝。
- `src/plugin.jai` 保持 test-free；未触及 `plugin_scan.jai`、`test_metaprogram.jai`、`commands/test.jai`、成员包等任何其他生产模块（本票只交付库面与合并语义）。
- 发布面：`JUICE_CORE_LOAD_FILES` 与 `publish_juice_core` 文本未改动，产物仍四件（`Juice/module.jai`、`Testing.jai`、`juice_core.jai`、`juice_internal/test_discovery.jai`）；`plugin.jai` 新增的 `#import "Compiler"` 在消费程序内解析编译器标准模块，不新增发布产物。

### 变更文件

- `C:\Users\maojiaxing\Workspace\projects\jai\otter\src\plugin.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\plugin_tests.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\docs\implementation\tickets\041-lint-plugin-face-merge.md`

### 验证矩阵（串行；各路径前清 `target/transpile`、`target/testing-module`）

| 路径 | 命令 | 结果 | 证据 |
| --- | --- | --- | --- |
| debug 自举 | `jai build.jai` | exit 0，产出 `target/juice.exe` | `target/audit-041-bootstrap-debug.txt` |
| debug 直跑 | `target/juice.exe test` | exit 0；SKIP 2（已知环境条件形态）；顶层条目 460（max `juice_test_N` 455 + 手写 5）；274 passed / 0 failed；白名单恰 6 行 | `target/audit-041-direct-test-debug.txt` |
| release 自举 | `jai build.jai - release` | exit 0 | `target/audit-041-bootstrap-release.txt` |
| release 直跑 | `target/juice.exe test` | exit 0；SKIP 2；460（455 + 5）；274 passed / 0 failed；白名单恰 6 行 | `target/audit-041-direct-test-release.txt` |
| 发布面编译 | 探针程序 `#import "juice_core"` 并构造 `Lint_Finding` | exit 0；产物仍四件、`juice_core.jai` 仍 `#load` `plugin.jai` | `target/audit-041-juice-core-compile.txt`、`target/probe-041/core_import.jai` |

基线（039 收口）：455 条目（450 + 5）、269 passed。本次 +5 条姊妹测试全部通过，计数增量与新增测试数一致。

### 偏差

无功能性偏差。两处记录性决定：

1. 诊断文案未由票据固定，取与 transpile 冲突一致的英文形（`lint plugin name must not be empty` / `lint plugin name conflict: …`），由姊妹测试钉住。
2. 重名检测沿用 transpile 款的 owner 记账；当首个占用者插件 `id` 为空时不会追加"重名"诊断——该场景本身已因空 id 使 `ok=false`，与既有 transpile 名查重行为一致（继承边角，非回归）。
