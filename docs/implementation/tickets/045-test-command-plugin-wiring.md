---
id: 045
title: test 命令生产接线：扫描 → 注册 → metaprogram
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: [042, 043, 044]
blocks: [046]
---

> 父 spec：`040-spec-third-party-plugin-member-lint.md`（决定 9、11、13；US 28-30、35）。上游规格：`docs/spec.md` §8.2。

# 045: test 命令生产接线：扫描 → 注册 → metaprogram

**What to build:** `juice test` 在测试 COMPILE 阶段扫描工作区插件包，写工作区级注册文件并把路径交给测试 metaprogram；从此真实工作区的 lint 插件随每次测试运行生效。零命中工作区行为完全不变，任何扫描/写盘失败都让命令失败。

**Blocked by:** 042、043、044

**Status:** closed

- [x] 测试 COMPILE 阶段、写 metaprogram 之前执行工作区扫描；命中非零 → 建目录、写注册文件、填入 metaprogram 选项；零命中 → 不写文件、不传选项。
- [x] 扫描或注册写盘失败 = `HANDLER_FAILED`；非致命扫描诊断以 `[juice WARNING]` 打印。
- [x] `plugin_scan` 库面加入工具 `#load` 闭包（顺序在 scan_walk/dependency/juice_module 之后、命令之前）；不新增 lifecycle 阶段。
- [x] 命令层注入 `spawn` 测试：扫描结果传递、零命中不变、失败路径；既有 `test-dep-root` 等非成员 DEP fixture 不触发扫描。
- [x] 根包自跑 `juice test`（debug+release、副本跑）全绿：lint 插件已加载、零警告、白名单恰 6 行、SKIP 0。

## Resolution

**状态：closed（2026-10-21）**

### 实现摘要

- `src/commands/test.jai` 的 COMPILE 内置前端 `test_compile_front`，在写 driver/metaprogram 之前接入工作区插件扫描：
  - `scan := scan_workspace_plugins(prepared.discovery)`；`!scan.ok` → `[juice ERROR] Could not scan the workspace's plugin member packages for <root>` + 返回 false（HANDLER_FAILED，响亮失败，不降级为「无插件」）；诊断逐条以 `[juice WARNING] <rel_path>: <message>` 打印（非致命，之后继续）。
  - `scan.hits.count > 0` → 落点 `workspace_plugin_registration_path(<root>/target)` = `<root>/target/plugins/registration.jai`；先递归建父目录、再 `write_entire_file(generate_plugin_registration(scan.hits))`；mkdir/写盘失败各打 `[juice ERROR]` 并返回 false。
  - 命中非零时同时设置 `metaprogram_options.plugin_registration`（绝对路径）与 `metaprogram_options.package_root = prepared.discovery.root_dir`（042 偏差 1 的成对约束）；零命中两者保持 `""`——生成文本逐字节维持插件前形态、不建 `target/plugins/`。
- `src/commands/test.jai` 的 spawn 缝补齐子进程模块搜索面（偏差 1）：`spawn_test_compiler` 与两处 seam `#type` 增加 `import_dirs: [] string`，子进程命令行为 `jai -quiet [-import_dir <dir> ...] <metaprogram>`——import 目录放在入口文件之前，保持 `build.jai` 的测试程序守卫（最后一个参数以 first.jai 结尾即跳过自构建）继续生效。命令装配好的 `compiler_import_directories(packages_dir(root))`（`<exe>/modules` + `target/packages`）同时喂给 metaprogram 的内层 workspace 与子进程顶层搜索面。
- `src/main.jai`：`#load "plugin_scan.jai";` 落在 `test_metaprogram.jai` 之后、`commands/` 之前（juice_module/dependency/plugin/scan_walk/transpile lexer 均已先行）；头注释补 045 说明。
- `tests/test_support.jai`：注入 spawn 假件同步新签名，记录 `test_test_spawn_import_dirs`（reset 清空）。
- `tests/test_command_tests.jai` 新增 5 条命令层测试（真实 collect/TRANSPILE 前端 + 注入 spawn 假件 + 构造发现快照）：命中路径（注册文件内容、spawn 收到的 metaprogram 路径、生成文本含 `#import "juice_core"` / `#load "<注册文件>"` / `set_working_directory("<root>")` / merge 与 lint 观察行）、零命中（不写文件、无 plugins 目录、生成文本无插件段）、扫描失败（ok=false → 命令失败、spawn 零调用、driver/first 均未写）、写盘失败（注册文件名被目录占位 → 命令失败、spawn 零调用）、非成员 DEP fixture（`tests/data/test-dep-root` 经生产 discovery：成员集仅根、扫描零命中、无注册文件、metaprogram 无插件段）。
- 未改 `src/test_metaprogram.jai`、`src/plugin_scan.jai`、成员包与 `package.jai`；未新增 lifecycle 阶段。

### 变更文件

- `C:\Users\maojiaxing\Workspace\projects\jai\otter\src\commands\test.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\src\main.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\test_command_tests.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\test_support.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\docs\implementation\tickets\045-test-command-plugin-wiring.md`

### 验证矩阵（串行；根路径前清 `target/transpile`、`target/testing-module`、`target/plugins`）

| 路径 | 命令 | 结果 | 证据 |
| --- | --- | --- | --- |
| debug 自举 | `jai build.jai` | exit 0，产出 `target/juice.exe` | 会话日志 |
| debug 直跑 | `target/juice.exe test` | exit 0；顶层条目 476（max `juice_test_N` 471 + 手写 5，较基线 471 恰好 +5 条新测试）；290 passed / 0 failed；白名单恰 6 行（组成不变）；`juice lint` 零行；`target/plugins/registration.jai` 生成（`JUICE_PLUGIN_0 :: #import "juice-plugin-lint";`）；`target/transpile/first.jai` 含第 3 行 `#import "juice_core";`、第 7 行 `#load "<root>/target/plugins/registration.jai"`、第 11 行 `set_working_directory("<root>")`、merge 与 `lint.inspect_test_header` 调用（第 12/88 行） | `target/audit-045-direct-test-debug.txt` |
| release 自举 | `jai build.jai - release` | exit 0 | `target/audit-045-bootstrap-release.txt` |
| release 直跑 | `target/juice.exe test` | exit 0；476（471 + 5）；290 passed / 0 failed；白名单 6；`juice lint` 零行；注册文件生成 | `target/audit-045-direct-test-release.txt` |
| 成员根冒烟 | `cd packages/juice-plugin-lint && ../../target/juice.exe test` | exit 0；3 passed / 0 failed；`juice lint` 零行；无 `target/plugins`（成员根只声明非成员 DEP `juice_core`，零命中不写文件） | `target/audit-045-member-test.txt` |
| 正向 lint 冒烟（补充证据，非套件测试） | scratch 工作区 `target/smoke-045`（根 manifest = 真实成员声明 + 复制自真实成员包的 `packages/juice-plugin-lint` + 一个 `@test BadName`）→ `target/juice.exe test` | exit 0；stderr 一条 `tests/bad_name_tests.jai:4,12: Warning: [juice lint] test procedure name must be snake_case: BadName`（原始包相对路径 + 1 基坐标）；stdout `[test] BadName`、`[test] test_good_name`、`2 passed, 0 failed`（警告不阻断执行）；`target/plugins/registration.jai` 生成——证明观察者真实执行，根套件零警告为真阴性 | `target/audit-045-smoke-positive.txt` |
| 副本跑（权威，SKIP 0） | `cp target/juice.exe target/juice-copy.exe` → `juice-copy.exe build` → `juice-copy.exe test` | build exit 0；test exit 0；SKIP 0；476（471 + 5）；290 passed / 0 failed；白名单恰 6 行；`juice lint` 零行；注册文件生成 | `target/audit-045-copy-build.txt`、`target/audit-045-copy-test-debug.txt` |

计数口径：found = max `juice_test_N` 471 + 手写 5 = 476 顶层条目（045 前基线 471 = 466 + 5；新增 5 条命令层测试全部执行通过，无跳过）；直跑 SKIP 2 为已知自锁环境形态，副本跑 SKIP 0 为权威。根套件零 `[juice lint]` 警告：全部既有测试过程名为 snake_case / `juice_test_N`，成员插件真实加载并观察全部收集 header 后无 finding。

### 偏差

1. **spawn 缝增加 `import_dirs`（真实集成缺陷修复，票面允许的小修）**：首次根自跑失败——`target/transpile/first.jai` 顶层 `#import "juice_core"` 与注册文件顶层 `#import "juice-plugin-lint"` 在子进程初始模块搜索面解析（早于 `#run` 安装内层 workspace 的 import path），只给内层 workspace 传目录不够，报 `Unable to find a module called 'juice_core'` / `'juice-plugin-lint'`。修复 = `spawn_test_compiler` 与两处 seam `#type` 增 `import_dirs: [] string`，调用点（按名传函数）零改动；目录取 `compiler_import_directories(packages_dir(root_dir))`（与 metaprogram 内层同一函数），零命中路径同样传递但生成文本不引用、编译不动。**参数序约束**：`-import_dir` 必须在入口文件之前，`build.jai` 靠最后一个命令行参数以 `first.jai` 结尾识别测试程序编译并跳出自构建；中间版本把目录放在文件之后，导致嵌套自构建 LNK1104（运行中的 `target/juice.exe` 被链接），已按「metaprogram 路径恒为最后参数」修正并写入注释。046 若再改子进程 argv，必须保持该约束。
2. **命令层测试快照用堆数组承载 DEP slice**：`plugin_wiring_prepared` 最初用定长字面量赋值 `root_package.dependencies`，slice 指向已返回的栈帧（028 偏差记录的 Jai 事实），表现为扫描零命中（命中/写盘两条测试失败）；改为 `[..] Juice.Dependency` 堆数组后全绿。仅测试侧，生产代码不受影响。
3. **扫描诊断的打印无进程内断言**：测试程序无 stdout 捕获面，`[juice WARNING]` 打印路径只由代码审查覆盖；诊断的产生逻辑（跨包重名）已由 043 姊妹测试锁定，本票只负责消费与打印。
4. **直跑 SKIP 2 / 副本 SKIP 0** 沿用既有约定（033 起的自锁形态）：直跑两个 bootstrap E2E 因 `target/juice.exe` 运行中而 SKIP，副本跑真实执行并全绿。

### 046 需知

- 生产链路已全部就位：真实 exe 在 scratch 工作区跑 `juice test` 会扫描 → 写 `<root>/target/plugins/registration.jai` → 生成 metaprogram 编译 `juice_core` + 插件模块 → 收集期 lint 观察。E2E 只需断言 `[juice lint]` 警告文本、原始包相对路径 + 1 基坐标、测试照常执行与 exit 0。
- lint finding 走子进程 stderr（042 偏差 3），stdout 只有测试执行行；scratch 工作区必须带 `workspace.members` + 同名 DEP（成员复制自 `packages/juice-plugin-lint`），坏命名 `@test` 过程会触发 `test-name-snake-case`。
- 子进程 argv 顺序约束（偏差 1）对任何后续 spawn 改动生效。
