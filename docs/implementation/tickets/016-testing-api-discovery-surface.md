---
id: 016
title: Testing API 面 + 发现纯函数面
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [017]
---

> 父 spec：`003-spec-test-note-discovery.md`（决定 5/8 + US 1-6/15/16）。上游规格：`docs/spec.md` §7.1/§9.5；研究 N§1.4/N§3.2（note 机制实验面）。

# 016: Testing API 面 + 发现纯函数面

**What to build:** 两面：**(a) Testing API 面**落 src/module.jai——run/finish/path_mapping/assert，API 兼容旧 juice/modules/Testing.jai（bootstrap 同一套测试两代工具跑；本票 #load 直测，bootstrap 期 driver #load 源面——003 决定 2 切线 B）；**(b) 发现纯函数面**（#load 直测，metaprogram 接线归 017）——note 精确匹配（`"test"` 或前缀 `"test("`，子串不匹配 + name != ""）、排序（按名词典 + `juice_test_N` 前缀数值感知）、查重拒绝、编号续号、文件来源隔离判定（enclosing load path ∈ 包视图文件集 + Testing 白名单）。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] Testing API 面落 src/module.jai（run/finish/path_mapping/assert——旧 juice/modules/Testing.jai API 兼容契约）
- [x] 发现纯函数面：note 精确过滤/排序/数值感知编号/查重/来源隔离判定
- [x] module_tests 扩展（Testing API 契约）+ test_command_tests 纯函数面矩阵（#load 直测）
- [x] 旧 juice build/test 于 otter 根零特判全绿（debug + release）
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**（2026-10-19）：

- **新建 src/test_discovery.jai**（test-free——017 生成 metaprogram 的 #load 纪律）：发现纯函数面全集，注释英文。签名清单见文末「017 移交面」。
- **src/module.jai 追加 Testing API 面**：prefixed 公开名（`Testing_Path_Pair`/`Testing_path_mapping`/`Testing_expect`/`Testing_expect_eq`/`Testing_fail`/`Testing_run`/`Testing_finish`，默认作用域）+ 裸名内部态（`current_test_name`/`current_test_failed`/`passed_count`/`failure_count`/`mapped_path`/`report_failure`）在 `#scope_file` 下——语义逐条同旧 juice Testing.jai（含 backticked `return 中止、defer 正常触发、finish 汇总重置、path_mapping 精确改写）。声明形状由 spike 定形（偏差 1）。
- **tests/test_command_tests.jai（新建）**：纯函数面矩阵 8 块（note 过滤/头判定/前缀解析/数值感知排序/查重/编号续号/来源隔离）。
- **tests/module_tests.jai 扩展**：Testing API 契约对拍——进程内 7 块（expect 通过续行/失败中止续套/fail 必记/defer 触发/裸 return 通过/finish 计数重置/path_mapping 空默认）+ 3 块子进程场景（pass/fail/mapped 打印格式逐字节对拍两代面）+ latch 1 块 + 死锁预解析锚 1 块。**fixture：tests/data/testing-face/{pass,fail,mapped}/src/scenarios.jai**（每场景一对过程组——juice 裸名组 + otter 前缀名组）。
- 旧 juice 仓零改动；map.md 未动（主会话负责）。

**验证矩阵**（串行全跑，验证前清 target/transpile）：

| 步骤 | 命令 | 结果 |
| --- | --- | --- |
| 1 | juice `jai build.jai`（debug） | exit 0 |
| 2 | otter `juice build` + `juice test`（debug juice） | exit 0，207 tests 全绿 |
| 3 | juice `jai build.jai - release` | exit 0 |
| 4 | otter `juice build` + `juice test`（release juice） | exit 0，207 tests 全绿 |
| 5 | 追加 3 次重复全跑（确定性复核） | exit 0 ×3，零 stall |

（输出中旧 juice 对无 modules/ 包根的 import dir 探测提示 = 通用无害，忽略。）

**偏差清单**：

1. **Testing 面声明形状 = prefixed 公开名 + #scope_file 裸内部态**（spike 定形，`AppData/Local/Temp/otter-testing-shape-spike/`）：候选「模块级顶层过程」实证判死——裸 `run` 与旧 juice 测试程序自身 `#import "Testing"` 撞 "Two overloaded definitions of the same procedure can't have identical argument lists"（s1 复现 007 偏差 1 同族碰撞）；Jai 无命名空间包裹构造（无 `#scope` 具名作用域；struct 不能装 #expand 宏）——prefixed 形状 = 唯一同时满足「全包扫描可见」（module_tests 先例）与「零撞名」的形态。实证：prefixed 面与裸 import 同程序共存 + 宏经定义点解析 #scope_file'd 内部过程 + `#caller_location`/path_mapping 改写全链正确（s2/s5）；005 发布转换 = 公开块剥前缀 → 平铺 Testing.jai 模块（s4 冒烟：转换产物裸 import 编译运行通过）。bootstrap 期 API 兼容 = 语义级（对拍锁死打印格式逐字节）；裸名 API 兼容在 005 发布落位后由 import 发布面承接。
2. **旧 juice 测试程序 #run 嵌套死锁 hazard + 预解析锚**：套件增长到 206 块后触发类型检查/执行竞态——version_tests 过程体（引用 `JAI_COMPILER_VERSION` = `#run` 常量）在旧 juice driver 的 #run 执行中途才被定型，嵌套 #run 等待外层结束 → "While executing this #run, we stalled waiting for another directive" 死锁（bisect 实测：触发面 = 测试块名字符串长度，与内容/位置/数量无关——竞态边界，基线 187 恰在赢侧）。解法 = module_tests 首块「Version constant preload anchor holds」预解析锚：套件最早处引用该常量，求值序确定化（6 次连续全跑零 stall）。该 hazard 属旧 juice 测试程序架构（stage 3 note-based runner 接管后锚随退场）；留给未来票的观察面。
3. **子进程对拍 driver = 裸 `#import "Testing"` + #load src/module.jai**：juice 面裸名、otter 面前缀名共存（spike s2 形状）；"Testing" 经 `-import_dir` 解析到 **strip 视图**（模块源内联 self-test 块、裸 import 不可编译——driver 生成前按首个 test 块切文，`testing_module_strip_view`）。
4. **子进程输出断言 = 子串钉死**（child_output_contains）：jai "creating library" 通知行 -quiet 不抑制且先于程序打印，整输出逐字节相等不可行——语义块整体作子串逐字节钉死（既有 E2E 姿态）。
5. **数值感知排序混合对**：N§风险 6 裁决只覆盖双方均带 `juice_test_N` 前缀的对；混合对回落普通字典序（`juice_test_10` < `juice_test_abc`——'1'<'a'），并在测试中锁定。

**017 移交面（纯函数面签名清单，src/test_discovery.jai）**：

- `note_matches_test :: (text: string) -> bool`——精确 `"test"` 或前缀 `"test("`。
- `header_is_test :: (name: string, note_texts: [] string) -> bool`——name != "" 且任一 note 命中。
- `parse_test_number_prefix :: (name: string) -> (number: s64, rest: string, ok: bool)`——`juice_test_` 前缀剥离（≥1 位数字；>18 位回落普通比较）。
- `test_name_less :: (a: string, b: string) -> bool` + `sort_test_names :: (names: [] string)`——数值感知全序（数值 → 余部字典序 → 原串裁决），插入排序稳定。
- `first_duplicate_test_name :: (names: [] string) -> s64`——收集期查重（-1 = 无重复），诊断归 017。
- `Numbered_Test :: struct { number: s64; name: string; }` + `number_tests :: (names: [] string, start: s64 = 1) -> [] Numbered_Test`——全局续号（调用方以 start 续传）。
- `source_path_allowed :: (path: string, package_view_paths: [] string, whitelist_paths: [] string) -> bool`——精确字符串判定，双端由调用方归一化到编译器 fully-pathed 形式。
- Testing 面消费形状（017/018 driver）：#load src/module.jai + `Testing_run`/`Testing_finish`/`Testing_path_mapping`；fixture 测试体写 `Testing_expect`/`Testing_expect_eq`/`Testing_fail`（前缀名至 005 切换）。
