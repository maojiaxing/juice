---
id: 037
title: 发现面源码第四件发布 + `<exe>/../src` 退役
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [036]
blocks: [039]
---

> 父 spec：`006-spec-stage3-bootstrap-closeout.md`（决定 4/5/14；接缝 1/3）。上游规格：`docs/spec.md` §9/§10。

# 037: 发现面源码第四件发布 + `<exe>/../src` 退役

**What to build:** `juice test` 在没有同级 `src/` 的安装布局下也能工作（只有 `<exe>/modules`）：测试发现面源码随构建发布为第四份内部件 `<modules_dir>/juice_internal/test_discovery.jai`。发布每跑重生；源缺失/不可读响亮失败；`discovery_face_source` 从 modules 目录推导，`<exe>/../src` 推导删除。

**Blocked by:** 036（语义上依赖 035 的裸面终态；与 036 共享 test support 与 test 命令验证面，按串行纪律接线）

**Status:** closed

- [x] 第四份件逐字复制发现面源码，落 `<modules_dir>/juice_internal/test_discovery.jai`；`jai build.jai` 与测试侧发布助手都产出它。
- [x] 源缺失/不可读 = 发布失败（响亮、非零退出），不产出半套发布物。
- [x] 安装布局 E2E：复制 exe + modules 到 scratch 目录，对一个 fixture/用户包跑 `test` 成功（改动前该路径因缺 `../src` 失败）。
- [x] `discovery_face_source` 从 modules 目录推导；`bootstrap_src_dir` 与 `<exe>/../src` 推导从生产面删除。
- [x] 发布物逐字节钉（第四件与源相等）；自举 debug/release 全绿；根套件全绿、白名单 6 不变。

## Resolution

**实现摘要**（2026-10-20）：发现面源码成为第四份内部发布物——`<modules_dir>/juice_internal/test_discovery.jai`，`src/test_discovery.jai` 的逐字复制（无变换），由 `jai build.jai` 发布步骤与测试侧 `ensure_published_modules` 同一落点助手族产出；发布前先读全两份源（缺失/不可读 = 先于任何写入的 exit 1，不落半套）。`discovery_face_source` 改由 `juice_modules_dir()`（`<exe>/modules`）经同一路径助手推导，`bootstrap_src_dir` 与 `<exe>/../src` 推导从生产面删除；生成 metaprogram 仍以绝对路径 `#load` 内部件（不是 import 面）。安装布局 E2E 实证：exe + modules 复制到无同级 `src/` 的 scratch 布局，fixture 包 `test` exit 0；旧推导在同一布局 exit 1（`Unable to open file '<bin>/../src/test_discovery.jai'`）。

**生产面改动**：

- `src/publication.jai`：新增 `JUICE_INTERNAL_DIR :: "juice_internal"` 与两个落点助手 `juice_internal_dir(modules_dir)` / `test_discovery_module_path(modules_dir)`——第四件助手以 **modules 目录**为参数（三份模块面助手以 target 目录为参数），因为消费侧唯一知道的根是 `juice_modules_dir()`；文件头与发布说明同步为「三份模块面 + 一份内部源件」。
- `build.jai`：发布步骤（先发布后编译）先读 `src/module.jai` 与 `src/test_discovery.jai`（任一不可读即 exit 1，此刻零写入），再做三段转换、创建 `juice_internal/` 并落四份件；每跑重生。
- `src/main.jai`：闭包追加 `publication.jai`（置于 `metaprogram.jai` 后）——生产发布与消费共用同一落点助手，路径单一来源；头注释同步。
- `src/commands/test.jai`：删除 `bootstrap_src_dir`（`<exe>/../src` 唯一来源）；`discovery_face_source := test_discovery_module_path(juice_modules_dir())`。

**测试面改动**：

- `tests/test_support.jai`：`ensure_published_modules` 读源前置于写入，产出第四件（并创建 `juice_internal/`）；头注释同步。
- `tests/publication_tests.jai`：landing paths 测试扩为四件（两组 modules-dir 助手路径钉）；新增「Real source: the discovery source publication is byte-identical」（测试侧助手产物与源逐字节相等）。
- `tests/bootstrap_tests.jai`：`bootstrap_published_paths` 扩为四元组；debug 自举 E2E 追加第四件逐字节钉、release E2E 追加存在性钉；新增「E2E: a missing discovery source fails the self-build without a partial publication」（先整删 `target/modules` → 自举 exit 1 → 四件全不落；defer 恢复源并 `ensure_published_modules` 复发布，测试隔离）。
- `tests/test_command_tests.jai`：新增「E2E: the test command works in an installed layout without a sibling src」——复制 exe + `target/modules` 到 `<target>/installed-layout-e2e/bin`（断言无同级 `src/`），对 `tests/data/test-fixture` 跑 `test`：exit 0、5 passed；并钉生成 metaprogram 的 `#load` = 安装布局 `modules/juice_internal/test_discovery.jai`、零 `../src/test_discovery.jai`。

**验证矩阵**（2026-10-20，串行；各先清 `target/transpile`/`target/testing-module`；证据 `otter/target/audit-037-*.txt`）：

| 路径 | 结果 |
| --- | --- |
| 红态探针（临时恢复 `<exe>/../src` 推导后重建；安装布局手动复现） | **exit 1**；`first.jai:4,1: Unable to open file '<bin>/../src/test_discovery.jai'` + `[juice ERROR] Test compilation failed.` |
| 绿态探针（修复后同一安装布局） | **exit 0**、`5 passed, 0 failed`；metaprogram `#load "<installed>/bin/modules/juice_internal/test_discovery.jai"` |
| 缺失发现面源（手动探针：移走源 + 整删 `target/modules` → `jai build.jai`） | **exit 1**；`target/modules` 整体不存在，四件零残留 |
| 自举 debug（`jai build.jai`） | exit 0；产出四件：131 / 237 / 12 / **285** 行；第四件 `cmp` 与源逐字节相等 |
| 自举 release（`jai build.jai - release`） | exit 0；四件齐备、第四件逐字节相等 |
| 产物 build（debug） | `target/juice.exe build` exit 0（LNK1104 hand-off 行）；副本同步 build exit 0 + `Build completed successfully`、exe 更新（环境注记见偏差 6） |
| 产物直跑 test（debug / release） | 各 exit 0；**450 found**（juice_test 最大编号）、264 passed / 0 failed、`expect failed` 恰 6 行、**SKIP 2**（自锁 = 环境条件形态） |
| 副本跑 test（debug / release 各一次） | 各 exit 0；450 found、264 passed / 0 failed、白名单恰 6 行、**SKIP 0**（权威验收） |

**计数**：036 基线 447 found / 262 passed → **450 found / 264 passed**（+3 测试：安装布局 E2E、第四件字节钉、缺失发现面源 E2E）。"Found" 口径：otter test 命令不打印 "Found N tests"（017 起的既有形态），权威数取 `juice_test_N` 最大编号（编号基 1 连续；036 日志同法复现 447）。终局 `passed` 264 与 262 的 +2 差异是 Testing 自测 `finish()` 重置计数器的既有约定位移（032/033 起记录：终局 M passed 因重置小于 N），不是计数回归——本轮 0 failed、exit 0、白名单 6 行不变。

**偏差清单**（全有意，无遗留缺陷）：

1. **`publication.jai` 加入 `main.jai` 闭包**：第四件的生产者（build.jai）与消费者（test 命令）共用 `test_discovery_module_path` 一个落点助手。该模块 test-free、本已在 bootstrap 闭包与测试程序全包扫描内，闭包新增无行为面变化。
2. **第四件落点助手以 modules 目录为参数**（三份模块面助手以 target 目录为参数）：消费侧（运行中 exe）只知 `juice_modules_dir()`；生产侧持有 target 目录时先派生 `<target>/modules`。两种形态不混用，同一助手同时覆盖 dev 树与安装布局。
3. **测试计数口径**：权威数 = `juice_test_N` 最大编号（450）；终局 `M passed` 因 Testing 自测 finish 重置小于 N（264），与前票基线同口径。
4. **安装布局 E2E 用静态 `test-fixture`**（而非临时用户包）：该 fixture 已是 035/036 迁移后的真实裸面用户包代表；裸名门禁失败/通过的用户包路径由 035 E2E 独立覆盖，本票只钉布局路径契约。
5. **安装布局复制用 stdlib `copy_file` / `copy_directory`**：running exe 的复制已有 011 hand-off 先例；布局根置 `target/` 内，defer 整删。
6. **产物 build 的同步证据用副本执行**：`target/juice.exe build` 的 hand-off（exit 0）在本 harness 下 detached 副本不存活（033 记录的工具环境事实），故另以 `target/juice-copy.exe build` 同步跑通真编译作为 build 路径证据。
7. **缺失发现面源 E2E 先整删 `target/modules` 再断言四件全缺席**，defer 恢复源并 `ensure_published_modules` 复发布——既证明「不产出半套」，又保持后续 E2E 的模块面状态。

**边界/落盘**：`package.jai` 零改动；三份模块面 131/237/12 行与公共兼容面逐字节不变；`juice_internal/` 不是 import 面（生成物只被绝对路径 `#load`）。旧 juice 仓零改动（未运行、未读取）。`docs/spec.md`、map.md、父 spec 006 不动（§9 的「三份发布物 → 三份模块面 + 一份内部源件」表述订正与 map 收口归 039）。**039 移交**：终态验收可把安装布局 E2E 纳入最终矩阵；spec §9 计数订正。
