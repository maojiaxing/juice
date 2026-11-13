---
id: 030
title: 发布转换模块（段裁剪 + 剥前缀 + juice_core 生成）
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [032]
---

> 父 spec：`005-spec-stage2-build-metaprogram.md`（决定 5/6/7/11 + US 11-14/19/22）。上游规格：`docs/spec.md` §9；参照面：016 偏差（prefixed 形状 + 005 转换）+ 022 文本变换工具面 + 025 juice_core stand-in。

# 030: 发布转换模块（段裁剪 + 剥前缀 + juice_core 生成）

**What to build:** 三份发布产物的纯函数生成面——**Juice 目录模块** = Package 段裁剪（src/module.jai 段边界标记契约 + 文本抽取，字段形状与旧 juice `modules/Juice.jai:97-118` 声明兼容，Testing 面除外）；**Testing.jai** = 剥前缀平铺文本变换（公开块 `Testing_run`→`run` 等裸名 + `#scope_file` 内部态调整，行号保真同款纪律，自测 test 块保留）；**juice_core.jai** = 生成模块（`#load` src/plugin.jai 及其依赖闭包——025 stand-in 的发布形态替身）+ 落点路径助手（target/modules 下三份）。产物逐字节钉测试。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] Package 段裁剪矩阵（段边界标记契约/漏标响亮失败/字段形状全集/Testing 面排除）
- [x] 剥前缀平铺矩阵（公开名全集裸名化/`#scope_file` 内部态调整/行号保真/自测 test 块保留）
- [x] juice_core 生成模块形状（#load 闭包清单钉死）
- [x] 落点路径助手（target/modules 三份）
- [x] 产物逐字节测试（真 src/module.jai 面 + 假源矩阵）
- [x] 姊妹测试 + 旧 juice build/test 于 otter 根零特判全绿（debug+release）+ 409 存量不回归
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**（2026-10-20）：

- **`src/publication.jai`**（新建，test-free——005 决定 3 bootstrap #load 集候选，纪律照旧）：
  - **段裁剪**：`extract_package_section`/`extract_testing_section`（`scan_section_markers` 单次扫描——恰好一个 `package` 标记 + 一个 `testing` 标记、顺序正确；重复/缺失/改名/乱序 = 响亮失败 ok=false；段边界空白行修剪）；标记契约 = 行的 trimmed 内容精确等于 `// [PUBLICATION-SECTION <name>]`——src/module.jai 头部注释已钉契约文本（「keep the marker lines verbatim」）。
  - **发布三函数**：`publish_juice_module`（`#import "Basic";` + 空行 + Package 段原文 + 换行）、`publish_testing_module`（Testing 段经 `strip_testing_prefix`——lex 出 IDENT token、剥 `Testing_` 前缀、Edit/apply_edits 装配：token 定界 = 行号保真逐行可对，注释/字符串不受碰，自测 test 块原样保留且块内前缀剥净）、`publish_juice_core`（生成头注释 + 两个内置 id 常量**声明行逐字抽取**（`extract_constant_line`——名称后空白+`::` 判定，缺行响亮失败）+ `JUICE_CORE_LOAD_FILES` 四文件绝对路径 #load）。
  - **落点助手**：`juice_module_dir`/`juice_module_path`/`testing_module_path`/`juice_core_module_path`（target_dir → target/modules 下三份，path_slashes 归一）。
- **`src/module.jai`**：段标记两行（头注释契约段 + 标记行；package 标记在 Package_Type 前、testing 标记在 Testing 横幅前——横幅属 testing 段，发布面携带为来源文档）+ **Testing 段尾追加 7 个自测 test 块**（005 决定 6「产物含自测 test 块」+ spec §9.1 定义源唯一的兑现形：prefixed 名 bootstrap 跑、剥前缀后发布面跑——同一套块两代工具，016 前提兑现；排水纪律同旧 juice——每块起始 drain 进 `self_testing_failures`、末尾 latch 断言；共享全局 `self_testing_failures`/`g_self_*` 落 tests/test_support.jai）。
- **`tests/publication_tests.jai`**（新建，15 块）：假源矩阵 11 块（段裁剪正反矩阵/剥前缀矩阵/行号保真/发布字节形状/juice_core 形状与失败通道/落点助手）+ **真 src/module.jai 面逐字节 pin 3 块**（Juice 95 行 + Testing 237 行全行 pin + juice_core 动态路径 pin——US 19 发布漂移响亮失败）+ **E2E 1 块**（三份产物落 scratch 缓存 → 真 jai 子进程裸 import：`Juice :: #import "Juice"`（007 偏差 1 形状——juice_core 重声明 id 常量须命名空间绑定）+ 裸 `#import "Testing"`（切文面）+ 裸 `#import "juice_core"` → Package 结构体/builtin_plugins/run-fail 双场景/path_mapping 改写逐输出 pin——016 spike s4 冒烟的正式形态）。
- **`tests/transpile_test_block_tests.jai`** 追加 1 块：裸指令后 test 块 STRIP/EXPAND 双双 claim（偏差 2 回归面）。
- **main.jai 零改动**；旧 juice 仓零改动；map.md 未动。

**验证矩阵**（串行全跑，各先清 otter/target/transpile）：

| 路径 | juice build | otter build | otter test |
| --- | --- | --- | --- |
| debug | exit 0 | exit 0 | exit 0，**Found 432 tests**（409 基线 + 23：7 src 自测 + 15 publication + 1 transpile 回归），全绿 |
| release | exit 0 | exit 0 | exit 0，**Found 432 tests**，全绿 |

expect failed 白名单 6 行（debug+release 逐行同状）：module_tests Testing face 自测 4 行（:178/:183/:207/:212，存量）+ **src/module.jai 自测 2 行（:304/:330）**——本票新增自测块的故意失败面（另有 `always`/`will-fail` 4 行非 grep 面故意打印，同族）；debug 追加连跑零 stall。

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **自测 test 块落位 = src/module.jai 段尾 + `#scope_export;` 带分号**：005 决定 6「产物含自测 test 块」的兑现形——定义源唯一（spec §9.1），发布变换保留即生成（剥前缀后裸名，两代工具同一套块）。分号 = 语句位硬约束：裸指令后首块不被两代 test-block 扫描器 claim（见偏差 2），`;` 让首块前显著 token 落 `;`——两代编译器实证合法（STRIP/EXPAND 视图与切文面尾各编译通过）。
2. **语句位缺口修正（otter runner + 探测簿记）**：裸指令（无分号）后 test 块 = 首触发（本票自测段初版 `#scope_export` 裸置）——旧 juice transpiler 与 otter runner 同缺口（旧 juice 自身 Testing.jai 的块前是 `}`，从未触发）。otter 侧修正 = runner 默认簿记与 `test_block_has_anchor` 探测：DIRECTIVE token → prev_text=";"（指令占一整个语句，其后 token 即语句位）——语义正确 + 032 发布面预防；旧 juice 侧不可修（零特判），源面分号规避（偏差 1）。回归测试 1 块。
3. **juice_core 闭包演化（025 stand-in 形状替换）**：module.jai 带自测块后不可 raw #load（025 偏差 3 的「阶段 2 发布面替换」兑现）——生成模块 = 两个 id 常量声明行**逐字抽取**（单源保真、字面量不可能漂移）+ 四文件闭包（transpile/transpile_plugin/lifecycle/plugin）；025 E2E 的 stand-in 生成器（tests/test_support.jai `ensure_plugin_face_modules`）切到 `publish_juice_core`（种子文件落点不变，032 退役）。
4. **显式 face 切文面（commands/test.jai）**：自测块使非 discovered 包的测试 driver 不能 raw #load 源面 → `testing_face_strip_view`：读源面切至首 test 块（保留 `#scope_file` 内部态——宏定义点解析面）+ 写 `target/transpile/testing-module.jai`（会话产物）；**不可读回退 raw 路径**（bootstrap seam 形状保持——tt-front 系列 seam 测试零改动，子进程编译期响亮失败照旧）。tests/test_support.jai 新增共享 `src_module_strip_view`（module_tests 子进程 driver + test_metaprogram E2E child 消费，去重）。
5. **build_tests 存量期望更新**：otter 根入口闭包不再 test-free（src/module.jai 自测段）→「Build compiles normally when no artifact is running」期望从「原入口直传」改「strip 视图（target/transpile/ 下 /src/main.jai 尾）」——027「直编/全有全无视图」语义的存量测试兑现修正。
6. **Jai 事实钉**：`#scope_export;` 带分号合法（两代编译器实证）；`#scope_file` 后声明同文件前向引用不受影响（宏定义点解析）。

**032 移交面**：发布三函数 + 落点助手（build.jai metaprogram #load src/publication.jai 即消费）；published Testing.jai 含自测块（Testing 特例 STRIP/EXPAND 消费面现成）；juice_core 生成器（stand-in 已切）；commands/test.jai 的 testing_face_strip_view 为 bootstrap 期形态（033 切 import 发布面后自然退役）。
