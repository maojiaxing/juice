---
id: 022
title: 转译工具面 + 内置 load 插件
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [020]
blocks: [023]
---

> 父 spec：`004-spec-plugin-surface-skeleton.md`（决定 6/7 + US 12/15/16）。上游规格：`docs/spec.md` §8.1；参照面：旧 juice transpile.jai（语义等价）+ transpile_plugin.jai:96-186（load 插件）。

# 022: 转译工具面 + 内置 load 插件

**What to build:** 转译工具面（lexer + 行起点表 + 行工具 + load 目标解析 + Edit 应用 + 行尾归一化——旧 juice transpile.jai 语义等价重写）+ 内置 load 插件（#load 处理：EXPAND 等行数占位 / STRIP 目标改写 + load_edges 喂闭包 DFS + 无 anchor）。姊妹测试 = load 重写矩阵 + 行号保真对拍。本票接入 020 的缺省管线注册（resolve_pipeline 缺省 = load 插件）。

**Blocked by:** 020（runner/门/接口面）

**Status:** closed

- [x] 工具面全集落地（lex/行工具/load 目标解析/Edit/apply_edits——旧 juice transpile.jai 语义等价）
- [x] load 插件两模式重写矩阵（EXPAND 等行数占位 / STRIP 改写目标 / load_edges 边源）
- [x] 行号保真（每编辑 1 行换 1 行、以 token 为界——经 020 门验证）
- [x] 缺省管线接入（resolve_pipeline 缺省 = load 插件）
- [x] 姊妹测试 + 旧 juice build/test 于 otter 根零特判全绿（debug+release）+ 263 存量不回归
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**：

- **`src/transpile.jai`**（续 020 最小支撑面，旧 juice transpile.jai 工具面语义等价重写，test-free）：
  - 行内容工具：`line_content_end`（行内容排他尾偏移）/`first_non_whitespace`；
  - 字符串助手：`is_hex_digit`/`hex_value`/`decode_jai_string`（已知转义解码、未知转义逐字保留——反斜杠路径存活）/`escape_jai_string`/`quote_jai_string`；
  - load 目标解析：`is_absolute_load_target`/`resolve_load_target`（反斜杠归一 + ".." 越界判出包 + 规范化拼接）/`find_load_target`；
  - strip 编辑构造器：`strip_block_edit`（**023 test 块插件要用的占位构造器，本票落地**——首行带原文、续行纯标记、缩进复制）/`load_strip_edit`（首行带原文、跨行 "(cont)" 标记、缩进复制）。
  - 023 接替面保留：find_matching_close/is_test_anchor（头注释已标）。
- **`src/transpile_plugin.jai`**（续 020 框架面）：
  - 内置 **#load 插件**：`load_plugin`（name/version 1.0.0、两模式、has_anchor 空——#load 不自触闭包视图、load_edges/transpile 钩子）+ `load_plugin_edges`（字面量包内目标解码+解析，语句序喂闭包 DFS）+ `load_plugin_transpile`（DIRECTIVE(#load) STRING ; 识别；独占行门——违反诊断 "#load 必须独占其行" 不 claim；EXPAND = load_strip_edit 等行数占位；STRIP = 目标串改写（跨行目标诊断 "#load 目标字符串不可跨行"、缺表项诊断 "in-package #load 缺少视图目标"、命中经 quote_jai_string 改写））；
  - **`default_transpile_pipeline` 落地 = load 插件单独**（023 追加 test 块）+ `resolve_pipeline` 接替点注释兑现（空注册表 = 缺省管线，视图与键恒同一管线）。
- **`tests/transpile_tools_tests.jai`**（新建，23 test 块——好测试标准 = 只测外部行为：给定源 + 管线 → 视图/条目/诊断）：工具面直测（字符串解码/未知转义/转义引号往返/目标解析矩阵/查表/单行-多行-链式 strip 构造器/行工具）+ load 插件重写矩阵（EXPAND 占位三形/出包与非字面量逐字/双模式 test-free 恒等/STRIP 改写+转义/缺目标诊断/跨行两形/独占行两向/claimed region 内剥离（本地 region 假插件——test 块插件 023 前身，claim 契约交互钉死）/load_edges 语句序+解码归一/行号保真矩阵/CRLF 归一）。
- **`tests/transpile_plugin_tests.jai`**（020 票文件内期望翻转）：「空注册表 = 空管线」→「空注册表 = 缺省管线（load）」（018 更新 010 E2E 链票惯例，随票记录）。
- **main.jai 零改动**（020/021 先例）：transpile 两模块仍不入 #load 闭包，接线随首生产消费者（027 build 接线）。

**验证矩阵**（旧 juice 双路径，各先清 otter/target/transpile）：

| 路径 | juice build | otter build | otter test |
| --- | --- | --- | --- |
| debug | exit 0 | exit 0 | exit 0，**Found 286 tests**（263 基线 + 23 新），139 passed, 0 failed |
| release | exit 0 | exit 0 | exit 0，**Found 286 tests**，139 passed, 0 failed |

expect failed 白名单 4 行（module_tests Testing face 自测 :178/:183/:207/:212，debug+release 逐行同状，无新增）；零 stall。

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **escape_jai_string 的 `%%` 潜伏缺陷不复制**：旧 juice transpile.jai:355 的 `"\\x%%"` 在当前编译器下不消费参数（出 "Incorrect number of arguments" 警告且 `%%` 语义将变）——控制字符转义分支从未正确产出 \xNN。otter 按 017 先例修正为 `"\\x%1%2"`（src/metaprogram.jai:35/test_discovery.jai:263 同形状），行为 = 旧 juice 意图（\xNN），旧仓警告照旧零改动。
2. **metaprogram.jai 本地 quote/escape 对改名 prefixed**：011 stand-in（`quote_jai_string`/`escape_jai_string`/`HEX_CHARS`）与 022 规范面（transpile.jai = 旧 juice 之家）在测试程序同程序撞名（编译报 2 overloads）。按 test_discovery.jai `escape_test_string`/`TEST_HEX_CHARS` 先例改 `quote_metaprogram_string`/`escape_metaprogram_string`/`METAPROGRAM_HEX_CHARS`，test_metaprogram.jai 10 处调用点随改名；规范名留给 transpile.jai；注释标注退役条件 = 027 接线（build 闭包先 #load transpile.jai）后删本地副本统一走规范对。
3. **「空注册表 = 空管线」测试期望翻转**（020 票测试文件内更新）：020 偏差 3 的钉死形状按链票惯例翻转——resolve_pipeline 空注册表返回 default_transpile_pipeline()（load 插件单独；023 追加 test 块）。
4. **strip_block_edit 的匹配闭括号 = 测试局部 helper（find_close）**：find_matching_close 归 023（test 块插件锚机制），与 020 偏差 4（test_find_close）同族。
5. **缺省管线只含 load 插件**：023 接替点 = default_transpile_pipeline 追加 test_block_plugin()（声明序 = 派发序，#load 先）。
