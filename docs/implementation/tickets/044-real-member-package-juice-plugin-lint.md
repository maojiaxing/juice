---
id: 044
title: 真实成员包 packages/juice-plugin-lint + 根声明 + 自身测试
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: [041]
blocks: [045]
---

> 父 spec：`040-spec-third-party-plugin-member-lint.md`（决定 1、7、10、12；US 5-7、16-18、20-22、32）。上游规格：`docs/spec.md` §3（仓库布局）、§8.2（lint）。

# 044: 真实成员包 packages/juice-plugin-lint + 根声明 + 自身测试

**What to build:** 仓库里出现第一个真实的第三方插件成员包：标准 LIB 包，根部模块实现 v1 lint 规则（测试过程名 snake_case），模块 test-free、自身测试驻 `tests/`；根包把成员与依赖声明进工作区。成员包作为自身根可构建、可测试。

**Blocked by:** 041

**Status:** closed

- [x] `packages/juice-plugin-lint/package.jai`：`type = .LIB`，`name = "juice-plugin-lint"`（= 目录名 = 模块名），`dependencies` 声明 `juice_core source="../../"`。
- [x] `module.jai` 根部入口：`#import "Basic"/"Compiler"/"juice_core"`；snake_case 谓词（`[a-z0-9_]`、非空）；`inspect_test_header` 返回 findings（违规 = 一条 WARNING，消息含过程名，锚定 header）；`get_juice_plugin` 设置 id/version 与 lint 面 name/version，尾注 `@juice_plugin`；模块无 test 块。
- [x] 成员包 `tests/` 覆盖 snake_case 谓词正反例；成员根 `juice test` 全绿（发现、依赖准备、发布面导入全通）。
- [x] 根 `package.jai` 增 `workspace.members = ["packages/juice-plugin-lint"]` 与同名 `dependencies` 项；根发现快照包含该成员。
- [x] 根 `build`/`test` 自跑 debug+release 仍全绿（成员子树从根测试程序剪除、成员 shim 零动作）；白名单仍恰 6 行。
- [x] 本票不接线测试命令扫描（归 045）；根自跑此时不会执行 lint。

## Resolution

**状态：closed（2026-10-21）**

### 实现摘要

- 新增真实成员包 `packages/juice-plugin-lint/`（仓库首个 `packages/` 成员）：
  - `package.jai`：`Package.{ name = "juice-plugin-lint", version = "0.1.0", type = .LIB, dependencies = Dependency.[.{name = "juice_core", source = "../../"}] }`——目录名 = 包名 = 模块名；成员引根用官方异名 DEP 形态（spec §3.3）。
  - `module.jai`（包根入口，约定 1）：`#import "Basic"/"Compiler"/"juice_core"`；派生结构体 `Test_Name_Lint_Plugin :: struct { using base: Juice_Plugin; }`；谓词 `test_name_is_snake_case`（非空、仅 `[a-z0-9_]`）；观察者 `test_name_lint_inspect`（违规 = 一条 `Lint_Finding`，`line = header.l0`、`column = header.c0` 原样透传——beta 0.2.009 实测 1 基，宿主不 re-base；消息 `[juice lint] test procedure name must be snake_case: <过程名>`、`.WARNING`）；`get_juice_plugin` 设 `id = "lint"`、`version = "0.1.0"`、`lint.name = "test-name-snake-case"`、`lint.version = "0.1.0"`、`lint.inspect_test_header`，尾注 `@juice_plugin`。模块零 test 块（注册程序直接编译它）。
  - `tests/lint_rule_tests.jai`：成员自身测试（published Testing 面裸名断言、手写 `@test`，与用户包 fixture 同形态）——接受 `juice_test_1` / `note_suite_x` / `test_name_2` / `a`；拒绝 `BadName` / `hasUpper` / `Test` / 空串 / 非法字符（`has-dash`、`has space`、`dotted.name`）。
- 根 `package.jai`：增 `workspace.members = string.["packages/juice-plugin-lint"]` 与同名 `dependencies` 项（`version = "0.1.0"`），其余字段不变。根 prep 按名链接成员，生成 `target/packages/juice-plugin-lint.jai` shim（#load 成员源 `module.jai`）；成员模块 test-free，依赖剥离前端对 shim 零动作。
- 未改 `src/test_metaprogram.jai`、`src/plugin_scan.jai`、`src/commands/test.jai`、`main.jai`（扫描接线归 045）。验证用临时驱动（仅会话产物，驻 `target/`）：`target/check-044-root-discovery.jai`、`target/check-044-root-scan.jai`、`target/plugins-check-044/{driver,registration}.jai`。

### 变更文件

- `C:\Users\maojiaxing\Workspace\projects\jai\otter\packages\juice-plugin-lint\package.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\packages\juice-plugin-lint\module.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\packages\juice-plugin-lint\tests\lint_rule_tests.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\package.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\docs\implementation\tickets\044-real-member-package-juice-plugin-lint.md`

### 验证矩阵（串行；各路径前清 `target/transpile` + `target/testing-module`，成员路径清成员 target 同名目录）

| 路径 | 命令 | 结果 | 证据 |
| --- | --- | --- | --- |
| 成员根 test（debug exe） | `cd packages/juice-plugin-lint && ../../target/juice.exe test` | exit 0；`3 passed, 0 failed`（三条测试全绿：接受生成/手写 snake_case、拒绝大写、拒绝空与非 snake_case 字符） | `target/audit-044-member-test.txt` |
| 成员根 test（release exe） | 同上（release `target/juice.exe`） | exit 0；`3 passed, 0 failed` | `target/audit-044-member-test-release.txt` |
| 根发现快照（生产 discovery 面） | `jai target/check-044-root-discovery.jai -import_dir target/modules` | exit 0；`root=juice`、`root-member-path=packages/juice-plugin-lint`、`root-dep=juice-plugin-lint`、`member=juice-plugin-lint type=LIB`（绝对 dir）、`member-dep=juice-plugin-lint:juice_core source=../../` | `target/audit-044-root-discovery.txt` |
| 根工作区扫描（生产 scan 面，045 预检） | `jai target/check-044-root-scan.jai ...` | exit 0；`scan-ok=true`、`hits=1`、`diagnostics=0`、`hit=juice-plugin-lint rel=module.jai`；注册 codegen 产出 `JUICE_PLUGIN_0 :: #import "juice-plugin-lint";` | `target/audit-044-root-scan.txt` |
| 注册程序编译 + 合并（045/046 预检） | `jai target/plugins-check-044/driver.jai -import_dir <abs target/modules> -import_dir <abs target/packages>` | exit 0；`merge-ok=true`、`merge-diags=0`、`transpile-plugins=0`、`lint-plugins=1`、`lint=test-name-snake-case v=0.1.0`——成员经根依赖 shim 解析、`as_plugin` 上转与 lint 面合并全通 | `target/audit-044-registration-merge.txt` |
| 根 debug 自举 | `jai build.jai` | exit 0，产出 `target/juice.exe` | `target/audit-044-bootstrap-debug.txt` |
| 根 debug 直跑 | `target/juice.exe test` | exit 0；SKIP 2（已知环境条件形态）；顶层条目 471（max `juice_test_N` 466 + 手写 5）；285 passed / 0 failed；白名单恰 6 行；`juice lint` 零出现（扫描未接线） | `target/audit-044-direct-test-debug.txt` |
| 根 release 自举 | `jai build.jai - release` | exit 0 | `target/audit-044-bootstrap-release.txt` |
| 根 release 直跑 | `target/juice.exe test` | exit 0；SKIP 2；471（466 + 5）；285 passed / 0 failed；白名单恰 6 行；`juice lint` 零出现 | `target/audit-044-direct-test-release.txt` |

计数与 042 基线（471 条目、285 passed、白名单 6）完全一致：成员子树经 discovery 快照从根测试程序剪除，成员 shim 无剥离动作。

### 偏差与观察

1. **成员根 test 的 juice_core shim 被剥离前端改写（预期/无害，票面预设事项）**：成员根 prep 把 `DEP juice_core source="../../"` 解析为仓库根 `src/module.jai`（入口探测第二顺位），该文件含 Testing 自测 test 块，依赖剥离前端遂按既有语义把 `packages/juice-plugin-lint/target/packages/juice_core.jai` 改写为 `target/transpile/deps/juice_core/fa35a6317d24ae7f/module.jai`（等行数 STRIP 视图、无 test 块）。实际编译不受影响：测试 metaprogram 的 import 目录序中 `<exe>/modules`（仓库 `target/modules` 发布面）先于成员的 `target/packages`，`#import "juice_core"` 命中发布生成模块；剥离视图仅作为成员会话 `target/` 产物存在，随 clean 清除。
2. **成员根 test 输出一行 Jai 编译器的良性提示** `Unable to open directory '<成员根>/modules'`（用户包无内嵌 `modules/` 时的目录探测；与 035 审计中的同类行同源），exit 0、测试计数正确，无影响。
3. **未向根套件新增测试**（新增测试会改变根计数，违背「根计数不变」验收）：根发现/扫描断言以 `target/` 下临时驱动走生产 discovery/scan/codegen 面完成（证据见矩阵），驱动是会话产物、不入库、不参与测试发现或插件扫描。
4. **045 导入解析链路已确认**：根声明成员 DEP 后自动生成 `target/packages/juice-plugin-lint.jai` shim（#load 成员 `module.jai`），test 命令已有的 import 目录 `target/packages` 即可让注册文件的 `#import "juice-plugin-lint"` 解析——045 无需新增导入目录；注册程序合并预检已按该链路验证（`merge-ok=true`、lint 面 1 条）。

