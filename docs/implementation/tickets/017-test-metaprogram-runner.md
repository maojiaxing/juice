---
id: 017
title: 测试 metaprogram 生成器 + runner 注入 + no_output 形状
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [016]
blocks: [018]
---

> 父 spec：`003-spec-test-note-discovery.md`（决定 5/6/7 + US 1-10）。上游规格：`docs/spec.md` §7.1.2/§7.2；研究 N§3.2（注入通道 how_to/460/470 官方模式）；参照面：旧 juice test.jai:502-517（driver run-list 形状）。

# 017: 测试 metaprogram 生成器 + runner 注入 + no_output 形状

**What to build:** @test 源文件端到端编译执行链：测试 metaprogram 生成器（first.jai 形状——消息循环累积全部 `.TYPECHECKED`、`.PHASE == .TYPECHECKED_ALL_WE_CAN` 一次性处理 → 收集（016 纯函数面接线：procedure_headers 过滤 + 文件来源隔离 + 排序查重编号）→ `add_build_string` 注入 `#run { run("name", proc); …; if finish() != 0 assert(false); }` 显式调用表（单编译，无两编译探针）；path_mapping 随生成时嵌入）+ **metaprogram 生成器扩展 no_output 测试形状**（011 偏差 2 移交点接替——测试程序不产 exe）。执行语义 = 编译期 #run、失败继续、run/finish 汇总退出码。

**Blocked by:** 016（收集消费纯函数面）

**Status:** closed

- [x] 测试 metaprogram 生成器：消息循环 + TYPECHECKED_ALL_WE_CAN 一次性收集接线
- [x] runner 注入：add_build_string 显式调用表（单编译）+ path_mapping 嵌入
- [x] metaprogram 生成器 no_output 测试形状接替（011 移交点）
- [x] 生成面姊妹测试（生成文本形状断言 + 收集接线 seam 面）
- [x] E2E 起步：生成 driver 于 fixture（@test 程序真编译真执行）——driver 先 set_working_directory（链约定）
- [x] 旧 juice build/test 于 otter 根零特判全绿（debug + release）
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**（2026-10-19）：

- **src/metaprogram.jai 扩展 no_output**（011 移交点接替）：`Compiler_Metaprogram_Options` 加 `no_output: bool = false`（executable_name/output_path 随旧 juice 同形补 `""` 默认）；生成器 if/else 两形状——测试形状 = `options.output_type = .NO_OUTPUT;` + 不对齐 intermediate_path 行、无可执行名/路径行（旧 juice metaprogram.jai:72-75 逐字节同构，build_tests 字节锁）；可执行形状字节不变（存量锁回归）。头注释移交点更新（testing_view_dir → 1c、very_optimized → 阶段 2）。
- **src/test_discovery.jai 扩展（016 面加法扩展，偏差 1）**：`Collected_Test_Source{name, path}`、`Test_Path_Pair{view, original}`、`collect_test_entries(sources, package_view_paths, whitelist_paths, numbering_start = 1) -> ([] Numbered_Test, duplicate_name)`（来源隔离 → 排序 → 查重 → 全局续号——016 五纯函数全接线）、`generate_test_runner_code(entries, pairs) -> string`（旧 juice test.jai:502-517 run-list 形状 + prefixed Testing 名：array_reset/array_add path_mapping → `Testing_run("名", 过程)` → `if Testing_finish() != 0 assert(false);`）。生成的 metaprogram 的 #load 面保持单文件（test_discovery.jai）；文件自足（补 `#import "String"`——生成子进程程序作用域不靠测试扫描的连带 import）；quote 助手 #scope_file'd 本地副本（与 metaprogram.jai 的 quote_jai_string 同扫描作用域共存）。
- **src/test_metaprogram.jai（新建，test-free）**：`Test_Driver_Options{source_files, testing_source, package_root}` + `generate_test_driver`（`#import "Basic"` → 注释 → `#run { set_working_directory(包根); }`（009 偏差 2 纪律，注入 runner 执行前锚定包根 cwd）→ `#load src/module.jai`（Testing 面，016 消费形状）→ 按发现序 #load 包文件）；`Test_Metaprogram_Options{workspace_name, intermediate_path, import_dirs, build_file, package_view_paths, whitelist_paths, path_pairs, discovery_source, numbering_start = 1}` + `generate_test_metaprogram`（生成文本 = `#import Basic/Compiler` + `#load test_discovery.jai` + NO_OUTPUT workspace + intercept + add_build_file(driver) + 消息循环：`.TYPECHECKED` 累积 procedure_headers（header_is_test 过滤 + enclosing_load 全路径）→ `.PHASE == .TYPECHECKED_ALL_WE_CAN && !injected` 一次性 `collect_test_entries` → 查重命中 `compiler_report`（Report.ERROR 停编译，偏差 4）→ 否则 `add_build_string(generate_test_runner_code(...))`；隔离集/path_mapping 对随生成时嵌为静态数组）。**未入 main.jai 闭包**（010 偏差 5 惯例——首次生产消费者 = 018）。
- **tests/build_tests.jai +1**：no_output 测试形状字节锁（`EXPECTED_METAPROGRAM_TEST_SHAPE`）。
- **tests/test_command_tests.jai +1**：collect_test_entries 矩阵（隔离/白名单/续号/查重/空路径/空流）。
- **tests/test_metaprogram_tests.jai（新建，8 块）**：driver 字节锁、metaprogram 字节锁、路径 slash、runner 码字节锁、空 runner 形状、引号转义、**E2E ×2**（test-fixture：3 测试真发现真执行 + 排序输出序断言 + "3 passed, 0 failed" + exit 0；test-fail：失败继续（test_after 先于 test_boom）+ 映射坐标 `src/failing.jai:` + "1 passed, 1 failed" + exit 1）。
- **tests/test_support.jai**：`run_test_program_child`（生产生成器面直驱：driver/metaprogram 落 target/test-metaprogram-e2e/<fixture>/，真 `jai` 子进程编译 metaprogram；fixture 文件列表显式硬编码——018 scan_walk 收集前不读目录，偏差 7）。
- **fixture 2 组**：tests/data/test-fixture/src/{tests_a,tests_b}.jai（手写 `@test` ×3 + 无注记过程 + `@testy` 子串近失手——计数断言守过滤）、tests/data/test-fail/src/failing.jai（`Testing_fail("boom")` + 续跑测试）。
- **016 偏差 2 死锁 hazard 终局解法（偏差 3）**：预解析锚方案失效（套件 217 块：module_tests 锚位置 119 先 stall；锚前移 clean_tests 位置 25 仍 stall；顶层常量锚惰性不触发求值、stall 移到契约测试本体）——**终局 = 套件进程内零引用 #run 常量**：version_tests 契约测试删 `JAI_COMPILER_VERSION` 进程内断言（保留 JUICE_VERSION），E2E 子进程（真 exe 逐字节对拍）兜底该契约；记忆文件已更新。旧 juice 仓零改动；map.md 未动（主会话负责）。

**验证矩阵**（串行全跑，验证前清 target/transpile）：

| 步骤 | 命令 | 结果 |
| --- | --- | --- |
| 1 | juice `jai build.jai`（debug） | exit 0 |
| 2 | otter `juice build` + `juice test`（debug juice） | exit 0，216 tests 全绿 |
| 3 | juice `jai build.jai - release` | exit 0 |
| 4 | otter `juice build` + `juice test`（release juice） | exit 0，216 tests 全绿 |
| 5 | 追加 3 次重复全跑（确定性复核，release juice） | exit 0 ×3，零 stall |
| 6 | 终态代码 debug 路径复核 | exit 0，216 tests 全绿 |

（输出中旧 juice 对无 modules/ 包根的 import dir 探测提示 = 通用无害，忽略；末行 "82 passed, 0 failed" = 旧 juice Testing 模块自测 start-drain 重置计数器的既有行为，绿信号 = exit 0 + "Found 216 tests"。）

**偏差清单**：

1. **test_discovery.jai 加法扩展（016 面）**：收集接线复合（collect_test_entries）+ runner 码生成（generate_test_runner_code）落 016 文件——生成的 metaprogram 的 #load 面保持单文件、纯函数章程不破（列表/字符串 only）；016 移交面签名零改动。
2. **重复测试名诊断 = `compiler_report`**（metaprogram 内 #compiler 内建，Report.ERROR 停编译 + jai 非零退出；spec §8.2 lint 三汇同族通道），非注入 #assert 文本——错误位置 = 生成的 metaprogram 文件（收集期无更佳坐标）。
3. **#run 死锁 hazard 终局 = 套件进程内零引用 #run 常量**（016 偏差 2 修正）：test-block 锚（前移仍 stall）+ 顶层常量锚（未用常量不求值）双失效；version_tests 契约测试删进程内 `JAI_COMPILER_VERSION` 断言，E2E 子进程逐字节兜底。src/ 早处理文件的既有引用（version_command 过程体）实测稳定。
4. **Jai 事实：print 格式串 `%%` 不消费参数**（字面 % + 参数告警）——`"\\x%%"` 两参调用实际输出 `\x%`（旧 juice transpile.jai:355 同款潜伏缺陷）：test_discovery.jai 新 escape 用 `%1%2`；**顺带修正 src/metaprogram.jai**（011 拷贝同一模式——控制字符路径的 escape 从损坏 `\x%` 修正为 `\xNN`；两处字节锁文本均不含控制字符，零影响）。生成器内嵌字面 `%` 用 `\%` 转义（编译器指导形式）。
5. **1b 显示名 = 过程名**：`@test(custom_name)` 参数化形式只参与 016 过滤（前缀匹配），自定义名解析未入 1b（spec 未要求）；`Testing_run(名, 过程)` 两参数同值。
6. **driver 的 chdir 落生成 driver 文本**（`#run { set_working_directory(包根); }`），非 metaprogram 内——注入 runner 编译期执行时 cwd 已锚包根（009 偏差 2 纪律的测试程序侧落实）。
7. **E2E fixture 文件列表显式硬编码**于 test_support（每 fixture 常量表）——018 的 scan_walk 生产收集接管前不引入目录读取；metaprogram/intermediate 落 target/test-metaprogram-e2e/（clean 随 target/ 整删）。

**018 移交面（生成器签名/调用形状清单）**：

- `Compiler_Metaprogram_Options.no_output: bool = false`（src/metaprogram.jai）——可执行/测试两形状。
- src/test_discovery.jai：`Collected_Test_Source`/`Test_Path_Pair`；`collect_test_entries(sources, package_view_paths, whitelist_paths, numbering_start = 1) -> ([] Numbered_Test, duplicate_name)`；`generate_test_runner_code(entries, pairs) -> string`。
- src/test_metaprogram.jai：`generate_test_driver(Test_Driver_Options{source_files, testing_source, package_root}) -> string`（Testing 面 #load 序在包文件前）；`generate_test_metaprogram(Test_Metaprogram_Options{...}) -> string`。
- 018 接线：scan_walk 收集 → driver（testing_source = src/module.jai 绝对路径，package_root = 包根）→ metaprogram（build_file = driver；package_view_paths = 各文件编译全路径、path_pairs = (全路径, 包相对路径)——双端由 018 归一化到编译器 fully-pathed 形式；intermediate_path = 包 target；import_dirs = compiler_import_directories）→ 写盘 spawn jai → 退出码透传；零收集短路 "No tests found"（t4）与 pattern 过滤归 018；main.jai 闭包接 test_metaprogram.jai（018 = 首次生产消费者）。
- 测试纪律：**新测试进程内禁引 #run 常量**（016 偏差 2 终局，E2E 子进程兜底）；E2E 助手复用 run_test_program_child。

