---
id: 023
title: 内置 test 块插件（EXPAND + 编号）
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [022]
blocks: [024]
---

> 父 spec：`004-spec-plugin-surface-skeleton.md`（决定 6/18 + US 11/13/14）。上游规格：`docs/spec.md` §8.1/§7.5；参照面：旧 juice transpile_plugin.jai:187-334（test 块插件）。

# 023: 内置 test 块插件（EXPAND + 编号）

**What to build:** test 块两模式重写——EXPAND：`test "name" {}` → `juice_test_N` 过程 + `@test` 注记 + Test_Entry 簿记（行号保真/path_mapping 簿记，降级为转译簿记——发现源仍是 note 枚举）；STRIP：整块占位、体内 token 永不再派发；全局编号基 1 跨文件续号；has_anchor 探测（喂闭包视图决策）。姊妹测试 = 重写矩阵（命名/编号续号/嵌套/行号保真/模式门控）。本票接入缺省管线（缺省 = load + test 块，声明序）。

**Blocked by:** 022（工具面 + load 插件）

**Status:** closed

- [x] EXPAND 重写矩阵（命名、编号基 1 续号、`@test` 注记落位、Test_Entry 簿记）
- [x] STRIP 整块占位 + 体内 token 不派发
- [x] has_anchor 探测面（闭包视图决策输入）
- [x] 行号保真门配合（重写恒 1:1）
- [x] 缺省管线 = load + test 块（声明序，resolve_pipeline 单一落点）
- [x] 姊妹测试 + 旧 juice build/test 于 otter 根零特判全绿（debug+release）+ 286 存量不回归
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**：

- **`src/transpile.jai`**（023 接替面兑现，旧 juice transpile.jai:542-571 语义等价重写，test-free）：
  - `find_matching_close`（开括号起深度计数扫流找匹配闭括号——词法器已消费字符串/注释，其括号不现于 token 流）+ `is_test_anchor`（`test`+字符串+`{` / `test`+`{` 形状判定）；落位「Anchor machinery」节（statement-position 簿记后）；头注释与 is_statement_position 注释随 023 更新（接替面注释退役）。
- **`src/transpile_plugin.jai`**（内置 **test 块插件**，旧 juice transpile_plugin.jai:187-334 语义等价重写）：
  - `test_block_plugin`（name "test-block"/version 1.0.0/两模式/has_anchor 钩子/load_edges 空——test 块不贡献闭包边）；
  - `test_block_has_anchor`（语句位顶层锚 + depth>0 锚均计数——嵌套会被拒但闭包仍需视图；非语句位锚如 `if test {` 不计数）；
  - `test_block_transpile`（识别→形状判定→单行头→depth>0 拒（"test block 仅允许文件顶层"）→语句位→跨行头拒（"test 头必须位于同一行"）→find_matching_close 失败诊断 + **扫描全停**（旧 break 语义）→ STRIP = strip_block_edit 整块占位 + 闭括号后非 test 锚语句拒（"test block 闭括号后不得有其他语句"，链式 test 锚同行豁免）+ 游标跳过闭括号（体内 token 永不再派发）→ EXPAND = `ctx.next_test_number + scan.tests.count` 编号 + 头改写 `juice_test_N :: () -> () {` + 闭括号后零宽插入 ` @test` + Test_Entry（命名 = 解码源 token、匿名 = path:line、line = 原文行）+ 游标入体 depth+1（体内 #load 继续派发——区域交互契约））；
  - **`default_transpile_pipeline` = load + test 块**（声明序 = 派发序，#load 先——022 偏差 5 接替点兑现）+ 头注释随 023 更新。
- **`tests/transpile_test_block_tests.jai`**（新建，23 test 块——好测试标准 = 只测外部行为：给定源 + 管线 → 视图/条目/诊断）：EXPAND 矩阵（命名/匿名 path:line/@test 落位尾注释前/编号续号 next=7→7,8/单行与链式块/体内 #load 剥离/字符串注释调用免疫/括号匹配跳过字符串注释/解码名）；STRIP 矩阵（多行占位/单行原文/链式同线/缩进复制/体内 #load 随占位消失）；诊断矩阵（嵌套拒/跨行头拒×2 形/闭括号后语句拒/未闭合 + **扫描全停钉死**——后续 #load 不派发）；行号保真矩阵×4 输入双模式/CRLF 归一；has_anchor 探测矩阵（缺省管线四向 + load-only 无锚）；编号跨文件通道（调用方推进 next_test_number 契约钉死）；锚机制直测（find_matching_close 真括号/missing close、is_test_anchor 形状矩阵）。
- **`tests/transpile_plugin_tests.jai`**（020 票文件内期望再翻转）：「空注册表 = 缺省管线」→ 023 形状（两内置插件声明序断言 + 源含 test 块 STRIP 占位断言随缺省管线更新——链票惯例，022 先例）。
- **main.jai 零改动**（020/021/022 先例）：首生产消费者 = 027（build 接线）。

**验证矩阵**（旧 juice 双路径，各先清 otter/target/transpile）：

| 路径 | juice build | otter build | otter test |
| --- | --- | --- | --- |
| debug | exit 0 | exit 0 | exit 0，**Found 309 tests**（286 基线 + 23 新），162 passed, 0 failed |
| release | exit 0 | exit 0 | exit 0，**Found 309 tests**，162 passed, 0 failed |

expect failed 白名单 4 行（module_tests Testing face 自测 :178/:183/:207/:212，debug+release 逐行同状，无新增）；零 stall。

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **020 票文件内「空注册表 = 缺省管线」期望再翻转**（023 形状）：022 偏差 5 接替点按链票惯例兑现——resolve_pipeline 空注册表返回两内置插件（load → test-block，声明序）；该测试源文本含 test 块，STRIP 视图断言随缺省管线更新为占位形状（`synth_anchor;` 直通 + test 块占位），测试名改「(023 shape)」。
2. **测试文件助手命名 prefixed（tblock_ 前缀）**：测试程序单命名空间——022 的 expand_ctx/strip_ctx/count_lines 已占裸名，023 助手改 `tblock_expand_ctx`/`tblock_strip_ctx`/`tblock_lines`（022 偏差 2 同族改名先例）。
3. **022 测试局部 find_close 保留不动**：src 的 find_matching_close 落地后，022 测试文件的局部 helper 命名不撞（find_close ≠ find_matching_close）、行为同形——无冲突即无退役收益，测试局部件照旧（020/022 偏差 4 同族）。
4. **编号续号面只落 ctx 槽消费**：023 兑现 `next_test_number + tests.count`（文件内首号种子 + 源序续号）；跨文件续号 = 调用方在两调用间推进 ctx.next_test_number（t3 接线 027/028 面），测试钉调用方契约（file1 → 1,2；next=3 后 file2 → 3）。
5. **main.jai 零改动**（020/021/022 先例）：transpile 两模块仍不入 #load 闭包，接线随首生产消费者（027 build 接线）。
