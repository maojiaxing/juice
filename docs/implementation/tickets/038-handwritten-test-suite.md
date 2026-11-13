---
id: 038
title: 手写 @test 套件面 + 阶段 0-2 约束退役
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [039]
---

> 父 spec：`006-spec-stage3-bootstrap-closeout.md`（决定 6/7；接缝 2）。上游规格：`docs/spec.md` §7.1/§7.3/§10。

# 038: 手写 @test 套件面 + 阶段 0-2 约束退役

**What to build:** otter 自身套件新增手写 `@test` 过程（独立姊妹测试文件），与存量 test 块经同一 note 发现源运行，共享确定性排序与全局编号。至少一条 `@test(custom_name)` 被发现（显示名仍取过程名）。map/文档中的"阶段 0-2 只写 test 块"约束退役，阶段 3 起新测试可直接使用 `@test`。

**Blocked by:** None (can start immediately；根包已是 face-discovered 裸面)

**Status:** closed

- [x] 新手写 `@test` 过程在根套件 debug/release 下被发现并执行。
- [x] 至少一条 `@test(custom_name)` 被发现；显示名保持过程名（显示名恢复不在本票）。
- [x] 手写 `@test` 与存量 test 块混跑：无重复编号、顺序确定、计数按新增递增。
- [x] map/文档的阶段 0-2 写法约束改为历史说明；阶段 3 起允许手写 `@test`。
- [x] 根套件全绿；白名单 6 行不变。

## Resolution

**实现摘要**（2026-10-20）：otter 自身套件新增手写 `@test` 面——`tests/note_suite_tests.jai` 的 5 条手写过程与存量 test 块经**同一 note 枚举**发现、同一确定性排序与全局编号混跑；一条 `@test(custom_name)` 被发现并执行，显示名保持过程名。阶段 0-2「只写 test 块」约束在 map Notes 退役为历史说明。生产代码零改动，存量 test 块零改写。

**测试面改动**：

- `tests/note_suite_tests.jai`（新增，5 条 `@test` 过程）：
  - `note_suite_published_face`（`@test`）：经发布裸面 `expect`/`expect_eq` 全链通过——手写过程与用户包测试同面。
  - `note_suite_custom_note`（`@test(custom_name)`）：参数化注记形态被发现并执行；套件日志显示名 = 过程名（无 `[test] custom_name` 行）。注记参数须标识符形（Jai 拒绝字符串字面量注记参数），显示名恢复留未来票。
  - `note_suite_mixed_order`：混合名单排序钉定——`juice_test_N` 数值感知（2 先于 10）+ 手写名字典序，全序且重复排序不变（确定性）。
  - `note_suite_mixed_numbering`：`collect_test_entries` 在混合来源上自基 1 连续编号无空号（1..4），来源隔离后无重复。
  - `note_suite_mixed_duplicate_rejected`：混合查重在收集期拒绝（`note_suite_dup`），entries 为空——重复名永不进入运行表。
- **命名约定**：手写过程名以 'n' 开头（`note_suite_*`），排序落在全 `juice_test_*`（'j'）块族之后——套件日志尾部即混合发现顺序的直接证据；过程名不占用 `juice_test_` 前缀（编号语义归 EXPAND 生成的块族）。
- 该文件只含被发现的 5 个过程，不放共享测试声明（`tests/test_support.jai` 仍是唯一共享家）；存量 test 块零改写。

**验证矩阵**（2026-10-20，串行；各先清 `target/transpile`/`target/testing-module`；证据 `otter/target/audit-038-*.txt`）：

| 路径 | 结果 |
| --- | --- |
| 自举 debug（`jai build.jai`） | exit 0；exe + 三份模块面 + 第四件；第四件与 `src/test_discovery.jai` `cmp` 逐字节相等 |
| 产物 build（debug；直跑 + 副本同步） | 直跑 exit 0（LNK1104 hand-off「rebuilding through a copy」）；副本同步 exit 0 + `Build completed successfully!`、exe 更新 |
| 产物直跑 test（debug） | exit 0；**455 顶层条目**（max juice_test_N 450 + 5 手写）；269 passed / 0 failed；`expect failed` 恰 6 行；SKIP 2（自锁 = 环境条件形态） |
| 副本跑 test（debug） | exit 0；455；269 passed / 0 failed；白名单 6；**SKIP 0**（权威验收） |
| 自举 release（`jai build.jai - release`） | exit 0；四件齐备；第四件逐字节相等 |
| 产物 build（release 产物；直跑 + 副本同步） | 直跑 exit 0（hand-off）；副本同步 exit 0 + `Build completed successfully!` |
| 产物直跑 test（release） | exit 0；455；269 passed / 0 failed；白名单 6；SKIP 2 |
| 副本跑 test（release） | exit 0；455；269 passed / 0 failed；白名单 6；**SKIP 0**（权威验收） |
| 模式过滤直跑（`test note_suite`） | exit 0；5 条手写条目逐名可见、`5 passed, 0 failed`（收集后过滤，其余条目不执行） |

**混跑证据**：

- 四个全量日志的顶层尾部完全一致（`note_suite_custom_note` → `..._mixed_duplicate_rejected` → `..._mixed_numbering` → `..._mixed_order` → `..._published_face`，四份 md5 相同）——顺序确定。
- 顶层条目名唯一：`juice_test_1..450` 无重复、5 条 `note_suite_*` 各出现恰一次（嵌套 `run`/`Testing_run` 的 `t-*` 行属测试体内层调用，不计入顶层表）。
- 计数按新增递增：顶层条目 450 → 455；终局 `264 passed` → `269 passed`（+5；手写名排序在块族之后，故全部计入最后一次 finish 之后）。

**计数口径**：otter test 不打印 "Found N tests"（017 起的既有形态）。本票权威数 = max juice_test_N（**450**，未变——新文件不含 test 块，EXPAND 编号零位移）+ 手写发现条目 **5** = **455**；`juice_test_247` 行在日志中被并行子进程 stderr 部分覆盖（`t] juice_test_247`，与 037 基线同位置同形态，既有观测噪声，最大编号口径不受影响）。白名单 6 行组成/坐标与 037 基线一致（`src/module.jai:354/380`、`tests/module_tests.jai:182/187/211/216`）。

**偏差清单**（全有意，无遗留缺陷）：

1. **手写过程命名以 'n' 开头**：保证排序落在 450 条块族之后，终局 passed 计数可直接按 +5 读取；这是证据可读性选择，不是发现契约（手写名本身自由）。
2. **计数口径扩展**：块族取 max juice_test_N，手写条目逐名计数，两者相加为 found；039 终态基线按此口径记录。
3. **自定义注记参数 = 标识符形**：`@test(custom_name)`（Jai 拒绝字符串字面量注记参数）；显示名仍为过程名，恢复归未来票（父 spec 出范围）。
4. **排序/编号/查重钉定放同一手写文件**：这些钉定过程本身即以 `@test` 形态被发现，既测发现复合面又自证手写面；不改写 `tests/test_command_tests.jai` 的既有块。
5. **新增文件不放共享测试声明**：`tests/test_support.jai` 仍是唯一共享声明家；该文件只有被发现的 5 个过程。
6. **生产面零改动**：`src/`、`build.jai`、`package.jai` 零改动；map.md 仅 Notes 中阶段 0-2 约束一条退役，不触其余面。

**边界/落盘**：存量 test 块零改写；旧 juice 仓未运行、未读取、零改动；父 spec 006 与 039 不动（终态收口归 039）；验证产物仅 `target/`（`audit-038-*.txt` 日志 + 生成物）。
