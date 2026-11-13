---
id: 003
title: 阶段 1b spec：test 命令 + note 发现
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [002]
blocks: [004]
---

> 父 map：`../map.md`。上游规格：`docs/spec.md` §7（test 命令规格）、§4.6（test 序 t1-t12）、§10 阶段 1；研究文档 N（`docs/research/note-based-testing.md`）、L（`docs/research/plugin-lifecycle-hooks.md` test 阶段清单）。
> 参照面（只读）：juice/src/commands/test.jai（t1-t12 序、driver 形状 :502-517、Testing 模块视图面）、juice/src/scan_walk.jai（共享扫描骨架）、juice/modules/Testing.jai（API 兼容契约）、旧 juice test.jai 内联测试（语义先例，87 测试名清单见参照面笔记）。

## Problem Statement

1a 闭环后 test 命令仍是占位（not-implemented）。1b 交付 = **note-based 发现**（用户拍板：test 不再作插件——spec §7.1 单一发现源）：测试 metaprogram 消息循环枚举 `.TYPECHECKED`、note 文本精确匹配 `"test"`/前缀 `"test("`、文件来源隔离（依赖闭包剔除）、排序（词典 + `juice_test_N` 数值感知）、runner = 注入显式调用表（单编译，无运行期顶层执行）、零收集短路、pattern 过滤、全局编号续号。Testing API 面落 src/module.jai（与旧 juice/modules/Testing.jai 兼容——bootstrap 同一套测试两代工具跑）。

## Solution

发现机制照 N 研究定稿形状（TYPECHECKED_ALL_WE_CAN 一次性处理 + 精确 note 文本 + 文件来源隔离 + 排序查重）；runner = 收集后 `add_build_string` 注入 `#run` 调用表；metaprogram 接替 011 移交的 no_output 测试形状；scan_walk 共享扫描骨架归 1b。范围切线（用户拍板 2026-10-19）：**A** 1b 发现面 = 手写 `@test` 过程，test 块 EXPAND 转译归 1c（1b 期间 otter 自身测试仍由旧 juice 跑；阶段 3 零改写枢轴不动摇——EXPAND 产物带 `@test` 是 1c 内置插件面，发现机制零改动接收）；**B** Testing 模块面 = **无独立 staging 目录**——bootstrap 期测试 driver 直接 #load 源面（src/module.jai 的 Testing API 面），阶段 2 发布落位后切 import 发布面（`target/modules/Testing.jai`，`<exe>/modules` 推导下与 exe 相邻）；**scan_walk 归 1b**（共享骨架 + driver 垃圾谓词，1c 插件包扫描同族复用）；**at 钩子五挂点**（§7.4 表）形状保留内置实现（1c 接线）。

## User Stories

1. As a test author, I want `@test`-annotated procedures discovered via the test metaprogram's message loop, so hand-written tests are found without registration code.
2. As a test author, I want note text matched exactly as `"test"` or prefix `"test("` (no substring matching), so compiler-internal notes (PrintLike/NoProfile) are never mis-collected.
3. As a test author, I want test collection to happen once at `.PHASE == .TYPECHECKED_ALL_WE_CAN`, so collection runs on the final typed state (how_to/460:68-75).
4. As a test author, I want file-source isolation (enclosing load path must be in the package view file set, plus the Testing-module whitelist), so dependency declarations entering via shims are never discovered — the compiler-level equivalent of "Dependency tests are neither discovered nor executed".
5. As a test author, I want deterministic ordering: name sort, with `juice_test_N` prefix compared numerically, so runs are reproducible regardless of message order.
6. As a test author, I want duplicate test names rejected with a diagnostic at collection time, so name collisions can't silently shadow.
7. As a test author, I want test blocks and hand-written `@test` procedures unified under one discovery source (both arrive as `@test`-annotated procedures in the message stream after EXPAND — stage 1c's plugin; the discovery mechanism receives them unchanged), so there is a single discovery path.
8. As a command user, I want the runner injected as an explicit call table via add_build_string (single compilation, no two-compilation probe), so test execution stays a compile-time `#run` program.
9. As a command user, I want execution semantics identical to juice: compile-time `#run` execution, failure continues to the next test, `run`/`finish` aggregate the exit code.
10. As a command user, I want path_mapping embedded when the metaprogram is generated (the file list is known at generation time), so error locations map back to real sources.
11. As a command user, I want zero collected tests to short-circuit with "No tests found" (juice t4 semantics).
12. As a command user, I want pattern filtering applied after collection (at most one argument), so filters never change discovery.
13. As a command user, I want `juice_test_N` global numbering continuing across the whole program (juice t3 semantics).
14. As a command user, I want the test program compiled with the no-output test shape (metaprogram handoff from 1a), spawned jai, with the exit code passed through.
15. As a test author, I want the Testing API surface (run/finish/path_mapping/assert) API-compatible with old juice's modules/Testing.jai, so the same test suite runs under both generations of the tool during bootstrap.
16. As an otter developer, I want the Testing surface to live in src/module.jai (single definition source per spec §9.1), loaded directly by the test driver during bootstrap — no staging directory.
17. As an otter developer, I want the test command to switch to importing the published module (target/modules/Testing.jai) once stage 2 lands — still no staging directory.
18. As a command user, I want file collection via scan_walk: DFS lexical order with the exclusion set (dot-prefixed, target/, tests/data, modules/, driver litter, member subtrees pruned), so "which files enter the test compile" is deterministic.
19. As a command user, I want the five at-hook shapes of §7.4 (at_DISCOVER/at_TRANSPILE/at_RUNNER_GEN/at_COMPILE/at_EXECUTE) preserved as built-in implementations with seams shaped for 1c wiring.
20. As an otter developer, I want old juice to keep building and testing the otter root with zero special-casing (debug+release) throughout 1b.

## Implementation Decisions

1. **范围切线 A（用户拍板 2026-10-19）**：1b 发现面 = 手写 `@test` 过程；test 块 EXPAND 转译 = 1c 内置 transpile 插件（002 切线 C 的自然延续）。1b 期间 otter 自身测试仍由旧 juice 跑（test 块写法不变）；验收面 = fixture 手写 `@test` 包 + 旧 juice 不变式。
2. **范围切线 B（用户拍板，回答 staging 面之问）**：Testing 模块面**无独立 staging 目录**——bootstrap 期测试 driver 直接 #load 源面（src/module.jai 的 Testing API 面；测试程序全包扫描本已可见，module_tests 先例）；阶段 2 发布落位后 test 命令切 import 发布面（`target/modules/Testing.jai`）。两阶段均无旧 juice 式 `target/testing-module/` 目录（旧 juice 的 staging 是手维护模块布局的产物，otter 模块是生成件——直读源/直读发布）。
3. **scan_walk 归 1b**：src/scan_walk.jai（旧 juice scan_walk.jai 语义等价——DFS 词法序 + 排除集 + driver 垃圾谓词；jaix 0058 先例面；1c 插件包扫描同族复用）。
4. **at 钩子五挂点形状保留内置实现**（§7.4 表），注释标注 1c 接替点——1a seam 保留同款纪律。
5. **发现机制 = N 研究定稿形状**：测试 metaprogram 消息循环累积全部 `.TYPECHECKED`，`.PHASE == .TYPECHECKED_ALL_WE_CAN` 一次性处理；遍历 procedure_headers（注记落 Code_Procedure_Header.notes）；匹配 = note 文本精确 `"test"` 或前缀 `"test("` + `name != ""`；文件来源隔离 = `enclosing_load.fully_pathed_filename` ∈ 包视图文件集（+ Testing 面白名单）；排序 = 按名词典 + `juice_test_N` 前缀数值比较；查重 = 收集期按名拒绝。发现逻辑拆**纯函数面**（note 过滤/排序/编号/来源隔离判定——#load 直测）+ metaprogram 接线面（E2E 测）。
6. **runner = 注入显式调用表**：收集后 `add_build_string` 注入 `#run { run("name", proc); …; if finish() != 0 assert(false); }`（旧 juice driver run-list 形状 test.jai:502-517；注入通道 = how_to/460/470 官方模式）——单编译，无两编译探针方案（N§3.2）。执行语义 = 编译期 #run、失败继续、run/finish 汇总退出码；path_mapping 随 metaprogram 生成时嵌入。
7. **metaprogram 移交点接替**：no_output 测试形状（011 偏差 2 移交——测试程序不产 exe）落 metaprogram 生成器；testing_view_dir（Testing 编译视图特例）仍归 1c。
8. **Testing API 面落 src/module.jai**（002 决定 D 移交）：run/finish/path_mapping/assert——API 兼容旧 juice/modules/Testing.jai（§9.5 契约；bootstrap 同一套测试两代工具跑）。
9. **test 命令序**（§4.6 t1-t12 的 1b 子集）：参数校验（≤1 参 pattern）→ workspace 准备 → 文件收集（scan_walk + 排除集）→ 测试 metaprogram 生成 + spawn jai → 退出码透传；零收集短路 "No tests found"（t4）；pattern 收集后过滤；juice_test_N 全局续号（t3）。测试程序的 workspace/编译面复用 1a（ensure_workspace_prepared 三参形状、compiler_import_directories、metaprogram 生成器）。
10. **链约定全继承**：`Juice :: #import "Juice"` 命名空间绑定、seam 参数注入惯例、E2E 生成 driver 必须先 `set_working_directory`（009 偏差 2 记忆 jai-child-cwd-anchoring）、run_otter_child_at + ensure_bootstrap_modules（011 偏差 6）、src 实现模块 test-free、测试块阶段 0-2 约束、代码注释英文/票面中文、旧 juice 仓零改动。

## Testing Decisions

- **接缝 1（旧 juice 不变式）**：1b 每步 `juice build`/`juice test` 于 otter 根零特判全绿（debug+release）；开发循环仍用旧 juice。
- **接缝 2（姊妹测试）**：tests/*_tests.jai（test 块）；实现模块 test-free；语义先例 = 旧 juice test.jai 内联测试（参照面笔记 87 测试名清单）。面清单：scan_walk_tests（扫描序/排除集/driver 垃圾谓词）、test_command_tests（收集纯函数面：note 过滤/排序/编号/来源隔离判定 + 编排面 + 短路/过滤/编号）、module_tests 扩展（Testing API 面——run/finish/path_mapping/assert 契约）。
- **接缝 3（E2E 真子进程）**：otter exe `test` 于 fixture 包（真 jai 子进程 = 测试程序编译链本身）；复用 run_otter_child_at + ensure_bootstrap_modules。
- **fixture**（tests/data/，测试发现豁免区）：test-fixture（手写 `@test` 包——发现 + 执行 + 排序 + 编号断言）、test-empty（零收集短路 "No tests found" 逐字节）、test-fail（失败继续 + 汇总退出码）、pattern 面（收集后过滤断言）。
- **好测试标准** = 只测外部行为（命令输出/退出码/测试计数/错误文本），不测内部实现形状。

## Out of Scope

- test 块 EXPAND 转译（1c 内置 transpile 插件）、transpile 管线与视图（1c）、lifecycle 挂载接线（1c）、jaix pre-step（1c 后）；
- build.jai 自构建 + modules 发布（005）、自举收口（006）；
- 官方 note test framework 落地后的复核（spec §11.2 未来面）；第三方宿主；linkme。

## Further Notes

- 链票编号自 015 起（/to-tickets 拆分）。
- §7.4 的 at 钩子五挂点 = 1c 接线面；本票只保留形状与内置实现。
- Testing 面的「bootstrap #load 源面 → 阶段 2 import 发布面」切换点 = 005 的收口复核面。
- 本票 = HITL spec 已发布（2026-10-19 /to-spec，用户拍板切线 A/B + scan_walk 归属 + at 钩子纪律）；**已闭环（2026-10-19）**：tracer bullet 链 015-019 全 closed（{015 scan_walk 骨架，016 Testing API + 发现纯函数面} 并列 → 017 测试 metaprogram + runner + no_output → 018 test 命令 handler 全链 → 019 fixture 收口（test-empty 静态 fixture + 编号/pattern 面 E2E 深化 + 旧 juice 不变式复核 + 本票收口））。收口映射与偏差汇总见下方 `## Resolution`。**下一步 = 1c 新 spec（004，/to-spec）**。

## Resolution

**收口结论（2026-10-19，票 019 落笔）**：US 20 条全兑现、决定 1-10 全部直落（两处 spike 修正见偏差指认：决定 2 切线 B 的 Testing 面 prefixed 形状、决定 6 单编译约束下零入口短路 = 打印不注入的 1b 等价形）；三接缝全绿；实现链 015-019 全 closed。**1b 闭环 → 下一步 = 1c 新 spec（004，/to-spec）。**

### US 20 条兑现映射

| # | US | 落点 | 兑现证据 |
| --- | --- | --- | --- |
| 1 | @test 过程经消息循环发现 | 016（note 过滤纯函数）+ 017（metaprogram 消息循环） | test-fixture E2E（真 jai 子进程发现 + 执行 + 计数断言） |
| 2 | note 精确匹配 "test"/前缀 "test(" | 016 | note_matches_test 矩阵（子串/近失手/编译器自用注记全负） |
| 3 | TYPECHECKED_ALL_WE_CAN 一次性收集 | 017 | metaprogram 字节锁 + injected 一次性守卫 |
| 4 | 文件来源隔离 | 016 + 017 | source_path_allowed 矩阵 + collect_test_entries 隔离面（shim 路径全拒） |
| 5 | 确定性排序（juice_test_N 数值感知） | 016 | test_name_less/sort 矩阵 + 019 fixture E2E（juice_test_2 先于 juice_test_10 运行） |
| 6 | 查重拒绝 | 016 + 017 | first_duplicate 矩阵 + 017 偏差 2（compiler_report 停编译） |
| 7 | 单一发现源（EXPAND 产物带 @test） | 016/017 机制不改收 + 切线 A | 发现面 = note 枚举统一——1c 转译产物同形进入，机制零改动（003 决定 1） |
| 8 | runner 显式调用表 add_build_string | 017 | generate_test_runner_code 字节锁 + E2E 真执行 |
| 9 | 执行语义同 juice（失败继续 + run/finish 汇总） | 016（Testing 面对拍）+ 017 | test-fail E2E（test_after 先于 test_boom + "1 passed, 1 failed" + exit 1） |
| 10 | path_mapping 生成时嵌入 | 017 + 018 | 嵌入面字节锁 + test-fail 映射坐标 E2E（src/failing.jai:） |
| 11 | 零收集短路 "No tests found" | 018（命令层零文件）+ 017/018（metaprogram 零入口） | 019 双短路 E2E：test-empty 静态 fixture（真跳过编译）+ 无 @test 文件面（打印不注入） |
| 12 | pattern 收集后过滤（≤1 参） | 018 | filter 矩阵 + E2E（过滤/零命中/019 大小写敏感 + 子串面） |
| 13 | juice_test_N 全局编号续号 | 016 + 017 | number_tests 矩阵 + numbering_start 穿线 + 019 编号基 1 钉生成产品（first.jai） |
| 14 | no_output 形状 + spawn jai + 退出码透传 | 017 + 018 | no_output 字节锁 + spawn seam + test-fail exit 1 全链 |
| 15 | Testing API 兼容（两代工具同套测试） | 016 | module_tests 对拍（进程内 7 块 + 子进程 3 场景打印逐字节） |
| 16 | Testing 面落 src/module.jai | 016 | #load 直测 + driver #load 源面（决定 2 切线 B 落实） |
| 17 | 阶段 2 切 import 发布面 | 018 | bootstrap 源面推导注释标切换点（005 复核面） |
| 18 | scan_walk 文件收集 + 排除集 | 015 + 018 | scan_walk 骨架矩阵 + collect_test_files 排除谓词矩阵（静态 scan-fixture 七文件序） |
| 19 | at 钩子五挂点形状保留 | 015/018 seam 形状 + 1c 接替点注释 | 决定 4 落实（collect/spawn 双 seam = at_COMPILE 等接替点） |
| 20 | 旧 juice 零特判不变式 | 全链 + 019 复核 | debug+release 各 build/test 于 otter 根 4/4 全绿（2026-10-19，238 tests） |

### 决定 1-10 直落对照

| # | 决定 | 直落 | 偏差指认 |
| --- | --- | --- | --- |
| 1 | 切线 A：发现面 = 手写 @test；otter 自身测试仍由旧 juice 跑 | 016/017 手写 @test 链 + 全链 test 块套件 | 无（018 偏差 5 记录预期面：otter 根 exe test 撞 test 块语法错误 = 切线 A 的预期状态，1c EXPAND 接管） |
| 2 | 切线 B：无 staging 目录——driver #load 源面，阶段 2 切 import 发布面 | 016 落位 + 018 exe 相对 ../src 推导 | **016 spike 修正 Testing 面形状**：裸名与旧 juice 测试程序自身 `#import "Testing"` 撞重载判死（Jai 无命名空间包裹构造）→ prefixed 公开名 + #scope_file 裸内部态；005 发布转换 = 剥前缀平铺 Testing.jai，裸名 API 兼容由 import 发布面承接 |
| 3 | scan_walk 归 1b | 015 | 015 偏差 1：生产排除谓词归消费方 018 的 collect_test_files（旧 juice 架构——骨架只管注入机制） |
| 4 | at 钩子五挂点形状保留内置实现 | 015（注入排除谓词 seam）+ 018（collect/spawn 双 seam） | seam 形状保留 + 1c 接替点注释标注 |
| 5 | 发现机制 = N 研究定稿形状 | 016 + 017 | 017 偏差 2：查重诊断 = compiler_report（错误坐标 = 生成 metaprogram 文件，收集期无更佳坐标） |
| 6 | runner = 注入显式调用表（单编译） | 017 | **018 偏差 1 执行级成形**：单编译约束下发现 = 编译，测试清单命令期不可知——零入口短路 = 打印 "No tests found" 后不注入（编译成功退出 0 = "短路"的 1b 等价形）；"Found N tests" 1b 不产（N 编译期才知，1c 可再议） |
| 7 | no_output 测试形状接替（011 移交点） | 017 | 无（011 移交点直落，testing_view_dir 仍归 1c） |
| 8 | Testing API 面落 src/module.jai | 016 | 偏差 1 形状指认（见决定 2） |
| 9 | test 命令序（§4.6 t1-t12 的 1b 子集） | 018 | 偏差 1 双短路分层（见决定 6）+ 偏差 2 产品落 target/test/（无转译层，无 target/transpile 对应物） |
| 10 | 链约定全继承 | 全链 | 零违反；#run 死锁纪律（016 偏差 2 → 017 偏差 3 终局：套件进程内零引用 #run 常量） |

### 链偏差汇总（015-018，22 项 + 019 补缺面）

| 票 | 偏差数 | 一览 |
| --- | --- | --- |
| 015 | 4 | 生产排除谓词归消费方 018（旧 juice 架构）；内联测试迁姊妹文件（test-free 纪律）；member 剪除测试面改列表查找（生产成员边界形状）；main.jai 零改动（018 首生产消费者接线） |
| 016 | 5 | Testing 面 prefixed 形状（spike 定案，决定 2 偏差指认）；旧 juice 测试程序嵌套 #run 死锁 hazard（预解析锚解法）；子进程对拍 driver 裸 import + strip 视图切文；子进程输出子串钉死（"creating library" 行 -quiet 不抑制）；数值感知排序混合对回落普通字典序（锁定） |
| 017 | 7 | test_discovery 加法扩展（metaprogram #load 面保持单文件）；查重诊断 = compiler_report；#run 死锁终局 = 套件进程内零引用 #run 常量（016 锚三连失效）；print %% 不消费参数修正（含 011 潜伏面 \x% → \xNN）；1b 显示名 = 过程名（@test(custom_name) 只过滤不解析）；chdir 落 driver 文本 #run；E2E fixture 文件列表显式硬编码（018 scan_walk 接管前不读目录） |
| 018 | 6 | 零入口短路落 metaprogram 内（1b 等价形，决定 6 偏差指认）；产品落 target/test/（session 产品每跑重生，clean 随 target/ 整删）；bootstrap 源面推导 = exe 相对 ../src（阶段 2 切 import 发布面）；command_not_implemented 删除（零引用死代码）；otter 自身根 exe test 撞 test 块语法错误 = 切线 A 预期状态 + 发现修正 ×2（零命中 print 格式串 '%.' 错序、slash 测试逐 quoted-path 钉死）；015 移交零改动 |
| 019 | — | **补缺面**：test-empty 静态 fixture 化（零文件 scratch → tests/data/test-empty/ 包 + E2E 真 exe 面）+ test-fixture 编号面深化（juice_test_10 先于 juice_test_2 声明 → 数值感知排序 E2E + 编号基 1 钉生成产品）+ pattern 大小写敏感/子串 E2E ×2；盘点结论 = test-fail（017）与 pattern 基础面（018）已覆盖，无重复建设 |

**归属**：全部偏差为有意设计决定（语义等价重写 + bootstrap 窗口绕行 + spike 实证修正），无遗留缺陷——旧 juice 仓改动面不涉（零特判参照面）。

### 完成定义复核

- **验收（Problem Statement）**：note-based 发现（metaprogram 消息循环 + 精确 note 文本 + 文件来源隔离 + 排序查重）✓；runner = 收集后 add_build_string 注入 ✓；零收集短路 + pattern 过滤 + 全局编号续号 ✓（执行级订正面已折回 spec.md §4.6/§7/§9.5）；Testing API 面落 src/module.jai（bootstrap 同一套测试两代工具跑）✓。
- **接缝 1（旧 juice 不变式）**：019 复核 debug+release 各 `juice build`/`juice test` 于 otter 根零特判全绿 4/4（exit 0 + "Found 238 tests"；验证前清 otter/target/transpile；旧 juice 对无 modules/ 包根的 import dir 提示 = 无害通用行为）。
- **接缝 2（姊妹测试）**：238 tests 双路径全绿（018 基线 236 + 019 E2E 深化 2 块：pattern 大小写敏感 + juice_test_N 子串面）；src 实现模块全 test-free（bootstrap #load 集纪律）。
- **接缝 3（E2E 真子进程）**：otter exe `test` 于 fixture 家族 ✓（test-fixture/test-fail/test-empty 静态三包 + pattern 面）；测试程序编译链 = 真 jai 子进程 ✓（生成 metaprogram 真编译 + 注入 #run 真执行）。
- **出范围面**：test 块 EXPAND 转译 + transpile 管线与视图 + lifecycle 挂载接线 → 1c（004）；jaix pre-step → 1c 后；build.jai 自构建 + modules 发布 → 005；自举收口 → 006；官方 note test framework 落地后复核 → spec §11.2 未来面；第三方宿主/linkme → map Out of scope。**下一步 = 1c 新 spec（/to-spec）。**
