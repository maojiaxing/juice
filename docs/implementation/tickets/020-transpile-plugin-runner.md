---
id: 020
title: 转译插件框架（runner + 行号保真门）
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [022]
---

> 父 spec：`004-spec-plugin-surface-skeleton.md`（决定 5/7 + US 4-10）。上游规格：`docs/spec.md` §8.1；参照面：旧 juice transpile_plugin.jai:28-94,335-517（语义等价重写）。

# 020: 转译插件框架（runner + 行号保真门）

**What to build:** 转译管线框架面——`Transpile_Plugin` 接口（name/version/modes/has_anchor/load_edges/transpile）+ `Transpile_Scan` 三汇 + `Transpile_Context`（plugin_state 槽）+ 声明序派发 runner + claim 契约（claim 恰好消费 token、未消费区域继续派发）+ 模式适用性门控 + 行号保真门（每条编辑「1 行换 1 行 + 以 token 为界」，违反丢弃 + 诊断拒绝）+ 探测聚合（has_anchor/load_edges 可空跳过）+ `resolve_pipeline` 单一落点（本票内置注册表空 = 缺省管线空；两内置随 022/023 接入）。姊妹测试全部用假插件（录制适配器，只录派发轨迹与编辑形状）。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] Transpile_Plugin 接口 + Transpile_Scan/Transpile_Context 形状落地（决定 5）
- [x] runner 声明序派发 + claim 契约 + 模式门控矩阵（假插件 ×3 录制适配器）
- [x] 行号保真门矩阵（非法编辑丢弃 + 诊断拒绝；合法编辑通过）
- [x] 探测聚合可空跳过面 + plugin_state 跨文件续走
- [x] resolve_pipeline 单一落点（空注册表 = 缺省管线）
- [x] 姊妹测试 + 旧 juice build/test 于 otter 根零特判全绿（debug+release）+ 238 存量不回归
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**：

- **`src/transpile_plugin.jai`**（新建，本票框架面——旧 juice transpile_plugin.jai:28-94 + 335-517 语义等价重写，test-free，链约定 bootstrap #load 集纪律）：
  - `Transpile_Plugin_Modes {strip, expand}` + `plugin_mode_applies`（模式适用性门控）；`Transpile_Plugin` 接口（name/version/modes + 三 `#type` 钩子：has_anchor/load_edges 可空、transpile 派发面——`#type` 参数个数与函数严格一致）；
  - `Transpile_Scan` 三汇（source/tokens/line_starts + 游标/depth/have_prev/prev_text 簿记 + edits/tests/diagnostics 三输出 sink）+ `Transpile_Context`（旧 juice transpile.jai:34-58 形状迁入：mode/path/next_test_number/load_targets/plugins/plugin_state——plugin_state 槽与管线序对齐、宿主持有存储、跨 transpile_source 调用续走、缺槽读 null）；
  - **runner `transpile_source`**（单一转译入口）：声明序派发 + claim 契约（claim 恰好覆盖消费的 token、未消费位置从管线头继续派发、无 claim 走 runner 缺省簿记）+ 区域交互契约（头部 claim 入体不消费 → 体内 token 继续派发；整块 claim 消费至闭括号 → 占位内 token 不再派发）；
  - **`enforce_line_fidelity`**（每条编辑「1 行换 1 行 + 以 token 为界」）：`offset_location`/`line_count_of`/`edit_token_bounded` 三助手 + 违反丢弃 + 诊断拒绝（"编辑违反行号保真：等行数展开失败"/"编辑未以 token 为界"——诊断文本逐字同旧 juice）；应用前统一执行；
  - **`pipeline_has_anchors`/`pipeline_load_edges`** 探测聚合（可空钩子跳过；load_edges 按管线序合并）；**`resolve_pipeline` 单一落点 = 恒等**（本票内置注册表空 = 缺省管线空；022 接替点注释标注 default_transpile_pipeline 落地——视图与其键恒反映同一管线）。
- **`src/transpile.jai`**（新建，runner 最小支撑面——旧 juice transpile.jai 子集语义等价重写，test-free）：`Transpile_Mode`（STRIP/EXPAND）/`Load_Target` 记录/`Test_Entry`/`Transpile_Diagnostic`/`Transpile_Result` + 词法器全集（Token_Kind/Token/lex_source/token_text——保真门 token 界判据与缺省簿记的输入）+ `compute_line_starts` + `is_statement_position`（have_prev/prev_text 共享解释）+ `Edit`/`sort_edits`/`apply_edits`/`normalize_view_line_endings`。
- **`tests/transpile_plugin_tests.jai`**（新建，12 test 块——全假插件录制适配器，好测试标准 = 只测外部行为：给定源 + 插件集 → 视图文本/测试条目/诊断，不测内部派发轨迹）：synth（三通道 + 跨文件状态槽 + STRIP-only 门控 + 双探测）/claim-a+claim-b（声明序同 token 竞争）/enter（头部 claim 入体不消费 → 体内 later-plugin 继续派发）/swallow（整块消费至闭括号 → 占位内不再派发）/extra_edges（探测聚合管线序）+ violate-line/violate-bounds（保真门拒绝矩阵）。
- **main.jai 零改动**（015 先例）：两新模块不入 #load 闭包（无死代码进发布产物），接线随首生产消费者（022 缺省管线接入）；测试程序经旧 juice 全包扫描自动纳入。

**验证矩阵**（旧 juice 双路径，各先清 otter/target/transpile）：

| 路径 | juice build | otter build | otter test |
| --- | --- | --- | --- |
| debug | exit 0 | exit 0 | exit 0，**Found 250 tests**（238 基线 + 12 新），终局 116 passed, 0 failed（driver 汇总 = 基线 104 + 12；Testing face 自测内部 finish 重置计数所致，debug+release 同状） |
| release | exit 0 | exit 0 | exit 0，**Found 250 tests**，116 passed, 0 failed |

4 次连跑零 stall（嵌套 #run 套件竞态未触发）；仅有的 4 行 expect failed = module_tests「Testing face」失败机制自测的预期输出（:178/:183/:207/:212，debug+release 逐行同状，非回归）。

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **`src/transpile.jai` 新建（票面未列的最小支撑面）**：runner + 保真门 + 外部行为测试需要词法器/Edit 应用/行起点表，而 022 的工具面（旧 juice transpile.jai 语义等价重写）未落地。020 按旧 juice 文件划分同构处理：transpile.jai 承载 runner 支撑子集，022 接续 load 目标解析（resolve_load_target/find_load_target）+ 字符串助手（decode/escape/quote）+ 行内容工具（line_content_end/first_non_whitespace）+ strip 编辑构造器（strip_block_edit/load_strip_edit），023 接续 find_matching_close/is_test_anchor——transpile.jai 头注释已标全部接替面。
2. **Transpile_Context 落位 transpile_plugin.jai**（指令要求；旧 juice 在 transpile.jai:34-58）——框架模块自含上下文面，头注释标注迁入源。
3. **resolve_pipeline = 恒等（缺省管线空）**：本票内置注册表空；022 接替点注释标注（default_transpile_pipeline 落地 = load 插件、023 追加 test 块）。「空注册表 = 空管线」测试钉 020 形状（022/023 落地后翻转该期望——链票惯例，018 更新 010 E2E 先例）。
4. **swallow 假插件的匹配闭括号 = 测试局部 helper（test_find_close）**：find_matching_close 归 023（test 块插件锚机制），不进 020 支撑面。
5. **synth_load_edges 录制原始字面量**（不做转义解码）：录制适配器只管聚合面；解码助手归 022。
