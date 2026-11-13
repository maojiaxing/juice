---
id: 043
title: 工作区级插件扫描 + 合并注册文件
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: []
blocks: [045]
---

> 父 spec：`040-spec-third-party-plugin-member-lint.md`（决定 2、3、4；US 1-4、23-27）。上游规格：`docs/spec.md` §5.2；研究依据 A§4.2.2。

# 043: 工作区级插件扫描 + 合并注册文件

**What to build:** 给定工作区发现快照，工具按根包依赖声明序挑出能对上成员的插件包、逐包扫描、合并命中，并落一份工作区级注册文件。声明面只用既有 `workspace.members` + `dependencies`，零协议扩展。

**Blocked by:** None（可立即开工）

**Status:** closed

- [x] `plugin_scan` 库面新增工作区级扫描：遍历根包 `dependencies`，按名匹配 `member_packages`，按 DEP 声明序扫描；重复 DEP 名只处理首次出现；非成员 DEP 跳过。
- [x] 命中序 = 「DEP 声明序 → 包内词法扫描序」；跨包同名模块复用既有探测序裁定（低秩胜、同级先者胜）并产生非致命诊断；任一扫描根不可扫 = `ok=false`。
- [x] 工作区级注册落点 `<root>/target/plugins/registration.jai`（会话产物）；复用既有两段注册 codegen；既有按包落点助手保留。
- [x] 真实 fixture 工作区矩阵：DEP 序优先于目录序、无锚成员零命中、非成员 DEP 跳过、重复 DEP 名单次、跨包同名裁定 + 诊断、不可扫根失败通道。
- [x] 姊妹测试 + 既有套件 debug+release 全绿；本票不改命令编排（接线归 045）。

## Resolution

**状态：closed（2026-10-21）**

### 实现摘要

- `src/plugin_scan.jai` 新增工作区级扫描 `scan_workspace_plugins(discovery: Juice.Workspace_Discovery) -> Plugin_Scan_Result`：按 `root_package.dependencies` 声明序遍历；重复 DEP 名线性去重（首次出现处理）；按名经 `find_workspace_member` 匹配 `member_packages`，非成员 DEP 跳过；对每个选中成员调用既有 `scan_plugin_package(member.dir)`，命中按「DEP 声明序 → 包内词法扫描序」累积；跨包同名模块复用 `place_scan_hit` 裁定（低探测序胜、同级先者胜）并沿用其非致命诊断。任一成员根不可扫 = `ok=false`（其余成员继续扫描以保持诊断完整；消费者见 `ok=false` 即整体弃用）。
- 新增工作区级注册落点 `workspace_plugin_registration_path(target_dir)` = `<target_dir>/plugins/registration.jai`（"/" 分隔、单文件会话产物）；既有按包 `plugin_registration_path` 保留；两段注册 codegen `generate_plugin_registration` 未改动，按合并后的扫描序原样复用。
- 模块头补充加载序约束：`Juice.Workspace_Discovery` 依赖 `src/juice_module.jai` 的命名空间绑定、`find_workspace_member` 来自 `src/dependency.jai`，故 juice_module / dependency 必须先于 plugin_scan 加载；叠加其既有的 plugin.jai / scan_walk / transpile lexer 依赖，生产 `#load` 闭包的安全位置在 src 列表末尾（建议 test_metaprogram.jai 之后）。测试程序全量词法序天然满足。
- 未改动 `main.jai`、`src/commands/test.jai`、`src/test_metaprogram.jai`、成员包与 `package.jai`；本票不接任何命令。

### 变更文件

- `C:\Users\maojiaxing\Workspace\projects\jai\otter\src\plugin_scan.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\plugin_scan_tests.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\data\plugin-workspace\package.jai` 及 `packages\alpha-plugin\{package.jai,module.jai}`、`packages\plain-member\{package.jai,module.jai}`、`packages\zeta-plugin\{package.jai,module.jai}`（均相对 `tests\data\plugin-workspace\`）
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\data\plugin-workspace-dup\package.jai` 及 `packages\first-plugin\{package.jai,extra.jai}`、`packages\second-plugin\{package.jai,extra.jai}`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\data\plugin-workspace-rank\package.jai` 及 `packages\zeta-extra\{package.jai,extra.jai}`、`packages\extra\{package.jai,module.jai}`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\docs\implementation\tickets\043-workspace-plugin-scan-registration.md`

### 验证矩阵（串行；各路径前清 `target/transpile`、`target/testing-module`）

| 路径 | 命令 | 结果 | 证据 |
| --- | --- | --- | --- |
| debug 自举 | `jai build.jai` | exit 0，产出 `target/juice.exe` | `target/audit-043-bootstrap-debug.txt` |
| debug 直跑 | `target/juice.exe test` | exit 0；SKIP 2（已知环境条件形态）；顶层条目 464（max `juice_test_N` 459 + 手写 5）；278 passed / 0 failed；白名单恰 6 行 | `target/audit-043-direct-test-debug.txt` |
| release 自举 | `jai build.jai - release` | exit 0 | `target/audit-043-bootstrap-release.txt` |
| release 直跑 | `target/juice.exe test` | exit 0；SKIP 2；464（459 + 5）；278 passed / 0 failed；白名单恰 6 行 | `target/audit-043-direct-test-release.txt` |

基线（041 收口）：460 条目（455 + 5）、274 passed。本票 +4 条姊妹测试全部通过，计数增量与新增测试数一致；白名单组成与既有 6 行完全相同。

### 姊妹测试覆盖（`tests/plugin_scan_tests.jai`，+4）

1. 主矩阵（`tests/data/plugin-workspace`，真实 manifest 经生产 `discover_workspace` + 真 jai 求值子进程）：DEP 声明序（zeta 先于 alpha）压过 workspace.members 序与目录序；非成员 DEP（external-lib）跳过；无锚成员（plain-member）零命中；重复 zeta DEP 单次——若处理两次会多出一条重复诊断，断言 `diagnostics = 0`。
2. 跨包同级重名（`plugin-workspace-dup`，两成员各持 `extra.jai` → 模块名 "extra"）：先声明者胜（first-plugin 的 extra.jai），后者被丢弃 + 恰好 1 条非致命诊断。
3. 跨包低探测序胜（`plugin-workspace-rank`）：后声明的 `packages/extra/module.jai`（秩 1）压过先声明的 `zeta-extra/extra.jai`（秩 3），+1 条诊断——裁定与声明序无关。
4. 不可扫成员根失败通道（构造快照指向不存在的成员目录）：`ok = false`。

落点测试扩展为同时钉住按包与工作区级两个路径助手。

### 偏差

1. 跨包重复诊断沿用 `place_scan_hit` 既有文案（包相对路径 + 模块名，不含包身份）——按票面「复用既有落位裁定并产生其诊断」执行；胜者身份由命中项 `abs_path` 与累积序确定，测试以此断言。
2. 成员根不可扫时其余成员仍继续扫描（诊断完整），`ok=false` 标记整体不可用；与按包 `scan_plugin_package` 的「失败即无命中」形状不同，已写入函数头注释。
3. 新 fixture 用真实 `package.jai` manifest 走生产 `discover_workspace`；仅失败通道用构造快照（票面允许）。三份 fixture 按关注点分离（主矩阵 / 同级重名 / 低秩胜），未合并为单工作区以免诊断互相污染。
