---
id: 042
title: 测试 metaprogram 观察挂载 + 合成 fixture 全链
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: [041]
blocks: [045]
---

> 父 spec：`040-spec-third-party-plugin-member-lint.md`（决定 6、8；US 9-15、19、28-31）。上游规格：`docs/spec.md` §8.2。参照面：`tests/plugin_scan_tests.jai` 的 driver E2E、`how_to/480_custom_checks/first.jai`。

# 042: 测试 metaprogram 观察挂载 + 合成 fixture 全链

**What to build:** 生成的测试 metaprogram 可以在注册文件存在时加载合并后的 lint 插件，对隔离集内的每个测试过程调用观察者，并把 findings 经 `compiler_report` 三汇报告到原始包相对路径与 1 基坐标。用合成 fixture 插件在真 jai 子进程里端到端证明。

**Blocked by:** 041

**Status:** closed

- [x] `Test_Metaprogram_Options` 增 `plugin_registration: string = ""`；为空时生成文本与现文本逐字节相同（新增字节锁）。
- [x] 非空时生成文本增补 `#import "juice_core";` + `#load "<绝对路径>"`；`#run` 内合并注册表，合并诊断逐条 `compiler_report`（ERROR → 编译失败），不执行 lint。
- [x] `.TYPECHECKED` 收集路径上，测试注记判定 + `source_path_allowed` 隔离判定之后，对每个测试 header 依序调用各 lint 观察者；pattern 过滤不影响 lint；runner 注入面不变。
- [x] findings 的 level 映射 `Report` 三汇；路径用 `path_pairs` 映射回原始包相对路径；坐标取 findings 的值（插件负责 0→1 基换算），宿主不二次换算。
- [x] 合成 fixture 插件增加 lint 面；生产扫描 + 生产注册 codegen + 真 jai 子进程 E2E 断言警告文本、原始路径、测试照常执行、exit 0。
- [x] 合并失败（重复 id / lint 重名）在子进程中是编译错误；导入模块不进 lint；姊妹测试 + 既有套件 debug+release 全绿。

## Resolution

**状态：closed（2026-10-21）**

### 实现摘要

- `src/test_metaprogram.jai`：
  - `Test_Metaprogram_Options` 增 `plugin_registration: string = ""`（非空 = 绝对注册文件路径）与支撑字段 `package_root: string = ""`（见偏差 1）。两者都只在非空分支生效——`plugin_registration == ""` 时生成文本逐字节不变（parent 决定 8）。
  - 非空生成文本：`#import "juice_core";`（与注册文件里的插件模块共享同一个按名导入模块——类型同一性；025 偏差 3 形态）、discovery 源 `#load` 之后 `#load "<注册文件绝对路径>"`、程序级 `merged_plugins: Merged_Plugins;` 全局；`#run` 里 `set_build_options_dc` 之后、`compiler_create_workspace` 之前 `set_working_directory(package_root)` 与 `merged_plugins = merge_plugins(get_scanned_plugins())`，`!ok` 时逐条 `compiler_report(diagnostic.message, mode = .ERROR)` 后 `return`（编译失败，不建 workspace、不跑 lint）。
  - `collect_test_headers`：note 判定 + `enclosing_load` 路径读取之后、`source_path_allowed(path, package_view_paths, whitelist_paths)` 通过时，按 `merged_plugins.lint_plugins` 顺序调用 `inspect_test_header(header, tc.subexpressions)`；每个 finding 以 `compiler_report(display_path_for(path), finding.line, finding.column, finding.message, mode)` 报告，`Lint_Level.ERROR/WARNING/INFO` → `Report.ERROR/WARNING/INFO`（默认 WARNING）。观察发生在收集期，pattern 过滤在之后的 `inject_test_runner` 内，过滤不可能隐藏 finding；runner 注入面未改。
  - 新增生成助手 `display_path_for`：用嵌入的 `path_pairs` 把编译视图路径映射回原始包相对路径，无匹配回退原路径。
- `src/test_metaprogram.jai` 保持 test-free；未改 `src/commands/test.jai`、`src/plugin_scan.jai`、`package.jai`，未建真实成员包（045/044 归属）。
- 合成 fixture `tests/data/plugin-lint-fixture/`：`module.jai`（`get_juice_plugin` + `@juice_plugin`，lint 面规则 = 测试过程名含 `Bad` 即一条 WARNING，锚 header 自身 1 基坐标）、`imported_tests.jai`（含 `BadImportedTest` 的导入模块，隔离面反例）、`tests/bad_name_tests.jai`（`BadNameTest` + `test_good_name`，导入上述模块）。既有 `plugin-fixture`/`plugin-fixture-bad` 未改动，其 E2E 输出保持逐字节不变。
- `tests/test_support.jai` 新增 E2E 助手 `run_plugin_lint_child(registration_fixture, test_fixture, test_files, pattern)`：生产 `scan_plugin_package` → 生产 `generate_plugin_registration` → 生产 driver/metaprogram 生成器（`plugin_registration` + `package_root`）→ 真 jai 子进程；外层 import dirs = `target/modules` + `tests/data`（目录模块名）+ 注册 fixture 根（stem 模块）；子进程 cwd = 测试包根。
- `tests/test_metaprogram_tests.jai` 新增 7 条：空注册逐字节锁、注册加载/合并位置与失败通道形状、收集期观察 + 三汇 + 路径映射 + pattern 前后关系形状（3 条单元）；lint 警告文本/原始路径/1 基坐标 + 测试照常执行 exit 0、pattern 过滤不隐藏 finding、导入模块不进 lint、合并失败编译错误且零执行（4 条 E2E）。

### 变更文件

- `C:\Users\maojiaxing\Workspace\projects\jai\otter\src\test_metaprogram.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\test_metaprogram_tests.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\test_support.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\data\plugin-lint-fixture\module.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\data\plugin-lint-fixture\imported_tests.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\tests\data\plugin-lint-fixture\tests\bad_name_tests.jai`
- `C:\Users\maojiaxing\Workspace\projects\jai\otter\docs\implementation\tickets\042-test-metaprogram-lint-observation.md`

### 验证矩阵（串行；各路径前清 `target/transpile`、`target/testing-module`）

| 路径 | 命令 | 结果 | 证据 |
| --- | --- | --- | --- |
| debug 自举 | `jai build.jai` | exit 0，产出 `target/juice.exe` | `target/audit-042-bootstrap-debug.txt` |
| debug 直跑 | `target/juice.exe test` | exit 0；SKIP 2（已知环境条件形态）；顶层条目 471（max `juice_test_N` 466 + 手写 5）；285 passed / 0 failed；白名单恰 6 行（组成与 043 完全相同） | `target/audit-042-direct-test-debug.txt` |
| release 自举 | `jai build.jai - release` | exit 0 | `target/audit-042-bootstrap-release.txt` |
| release 直跑 | `target/juice.exe test` | exit 0；SKIP 2；471（466 + 5）；285 passed / 0 failed；白名单恰 6 行 | `target/audit-042-direct-test-release.txt` |
| E2E 子进程（lint 观察） | 复跑生产生成的 metaprogram（套件产物） | exit 0；stderr `tests/bad_name_tests.jai:11,16: Warning: [juice lint] test procedure name contains 'Bad': BadNameTest`（原文片段 + 脱字符）；stdout `[test] BadNameTest`、`[test] test_good_name`、`2 passed, 0 failed`；`BadImportedTest` 零出现 | `target/audit-042-e2e-lint-child.txt` |
| E2E 子进程（合并失败） | 复跑生产生成的坏注册 metaprogram | exit 1；stderr `Error: duplicate plugin registration: bad-shared`；零测试行 | `target/audit-042-e2e-merge-fail-child.txt` |

基线（043 收口）：464 条目（459 + 5）、278 passed。本票 +7 条姊妹测试全部通过，计数增量与新增测试数一致。根包生产 metaprogram（`target/transpile/first.jai`）零 `juice_core`/`merged_plugins`/`display_path_for` 文本——零插件生产路径字节不变（接线归 045）。

### 偏差

1. **新增支撑选项 `package_root`**（票面只列 `plugin_registration`）：jai 子进程把工作目录锚在入口文件目录（metaprogram 所在 `target/`），driver 自身 `#run` 的 chdir 对收集期报告来说太晚；而 `compiler_report(filename, line, col, ...)` 会打开文件读取源码行——相对原始路径在错误 cwd 下会额外产生 `Error: Cannot open ...` 并把 WARNING 变成编译失败（spike 实证）。因此生成文本在 `#run` 里、建 workspace 之前 `set_working_directory(package_root)`，只影响非空注册分支（空分支仍逐字节不变）。**045 必须把 `prepared.discovery.root_dir` 传入 `package_root`**（与 `plugin_registration` 同时设置）。
2. **坐标基准实测定形**：jai beta 0.2.009 的 `Code_Procedure_Header` location 行/列实测为 1 基（行 11 的声明报 l0=11；spike 见 `target/spike-042/header_spike.jai`），与票面「AST 位置 0 基」的表述不一致。换算职责仍在插件（fixture 规则直接取 header 的 1 基值，宿主不二次换算，符合「findings 是 1 基、宿主不 re-base」的契约）。
3. **lint finding 走 stderr**：`compiler_report` 输出到子进程 stderr（源码片段 + 脱字符），E2E 在 stderr 上断言警告；stdout 只含测试执行行。
4. **`compiler_report` 的 filename 需可打开**：E2E 子进程 cwd = 测试包根（生产形态），原始包相对路径才可打开；`display_path_for` 无匹配时回退原始视图绝对路径（必然可打开）作为兜底。
5. 合并失败子进程 E2E 用既有 `plugin-fixture-bad`（重复 id `bad-shared`）作为注册来源，不新建坏 fixture；lint 名冲突的合并拒绝已由 041 的姊妹测试覆盖。

