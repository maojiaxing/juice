---
id: 029
title: fixture E2E 收口 + 关闭 004
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [025, 027, 028]
blocks: []
---

> 父 spec：`004-spec-plugin-surface-skeleton.md`（完成定义 + 三接缝 + 出范围）。上游规格：`docs/spec.md` §4.6/§6.3（收口折回面）。

# 029: fixture E2E 收口 + 关闭 004

**What to build:** 1c 收口——E2E fixture 家族（build-with-tests、test 全链深化、合成插件包良构 + 坏——重复 id / 行号保真违规 → 响亮拒绝）+ 旧 juice 不变式 debug+release 4/4 + **otter 自身根 exe test 全绿**（test 块 → EXPAND → `@test` → note 发现，018 切线 A 预期状态解除，path_mapping 指原文行）+ spec 004 Resolution（US 32 兑现映射 + 决定 22 直落对照 + 链偏差汇总）+ spec.md 执行级订正折回（§4.6「t2 归 1c」订正为后续票 + §6.3 at 接线子集）+ map Decisions so far 追加。

**Blocked by:** 025（插件包全链 E2E）、027（build 剥离 E2E）、028（test 全链 E2E）

**Status:** ready-for-agent

- [x] E2E fixture 家族全绿（含合成插件包良构/坏双面）
- [x] 旧 juice 不变式 debug+release 4/4 复核
- [x] otter 自身根 exe test 全绿（018 切线 A 预期状态解除）
- [x] spec 004 写 `## Resolution`（US 32 兑现 + 决定 22 直落 + 链偏差汇总）+ status: closed
- [x] spec.md 执行级订正折回（§4.6/§6.3/§7.2/§7.3）
- [x] map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**（新建 fixture 1 包 2 文件 + 测试面 1 块；改写 tests/{test_support,plugin_scan_tests}.jai；文档面 004 + spec.md）：

- **坏插件包全链 E2E 补缺**（025 只覆盖良构包全链——004 决定 20 ④/三接缝 3「合成插件包 ×2」的坏面缺口）：新 fixture `tests/data/plugin-fixture-bad/`（静态两文件，测试发现豁免区）——`module.jai`（入口，id "bad-shared" + transpile 面 bad-mark 把 IDENT "bad_mark" 改写成**两行文本** = 行号保真违规）+ `extra.jai`（id "bad-shared" 同 id 同版本 = 重复注册）；全链 = 生产扫描（两锚点同形命中）→ 生产 codegen 落 target/plugins/plugin-fixture-bad/registration.jai → juice_core 种子 → 真 jai 编译 → **merge_plugins 响亮拒绝**（merged-ok=false + "duplicate plugin registration: bad-shared" + 合并产品照填 jaix 形状）→ **行号保真门响亮拒绝**（编辑丢弃 + "编辑违反行号保真：等行数展开失败" + 视图保持原文）。
- **E2E 基建最小扩展**（test_support.jai）：run_plugin_scan_child/driver 构造器 `marker` 参数化（默认 "fixture_mark"——好包 E2E 生成文本逐字节不变；纯标识符参数，无转义面）+ merge/transpile 诊断逐条打印（好包零诊断输出增量行无害，pin 全子串匹配）。
- **新测试 1 块**（plugin_scan_tests.jai）：E2E 坏包全链（扫描同形 + 合并拒绝 pin + 行号保真拒绝 pin + 注册文件落位）。

**验证矩阵**（各先清 otter/target/transpile；旧 juice 不变式 4/4）：

| 路径 | juice build | juice test（otter 根） | 完成定义①/② |
| --- | --- | --- | --- |
| debug | exit 0 | exit 0，**Found 409 tests**（408 基线 + 1 新），239 passed, 0 failed | ① exit 0、239 passed（juice_test_401-409，018 切线 A 解除）② exit 0、LNK1104 hand-off 全通、exe 更新 |
| release | exit 0 | exit 0，**Found 409 tests**，239 passed, 0 failed | 自构建后复跑 ①：239 passed exit 0 |

expect failed 白名单 4 行（module_tests Testing face 自测 :178/:183/:207/:212，debug+release 逐行同状，无新增）；坏包 E2E 定向 pattern 复跑 1 passed。

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **坏插件包全链 E2E 补缺**（029 补缺面）：025 只覆盖良构包全链；坏双面（重复 id / 行号保真违规）进程内矩阵在（024 plugin_tests 合并矩阵 + 020 transpile_plugin_tests 保真门矩阵），但「扫描 → 注册 → 合并响亮拒绝」全链无——本票按 029 票体「若 025 未覆盖坏插件包全链，本票补 E2E 或矩阵测试」补 E2E（选 E2E：扫描同形 + 拒绝分层都是生产链行为）。
2. **坏包拒绝分层**（执行形状钉定）：重复 id 拒绝发生在 merge（合并诊断 line/column 恒 0 无源锚——024 偏差 2 同款）；行号保真违规拒绝发生在 transpile（编辑丢弃 + 带源坐标诊断）——两层都响亮、都 ok=false 拒绝继续；E2E 演示面 = 合并产品照填（jaix 形状）后跑管线，生产消费方须按 ok=false 拒续（merge_plugins 契约注释）。
3. **driver 构造器 marker 参数化**（test_support.jai）：默认参保持好包 E2E 生成文本逐字节不变；诊断逐条打印追加行对好包 pin（子串匹配）零影响。

**收口面**：

- **E2E fixture 家族复核**：build-with-tests（027 剥离成功 + artifact 运行）、test-blocks（028 全链 4 块展开 + 视图纯契约）、test-blocks-fail（028 原文 file:line 映射 + exit 1）、test-dep-root + test-dep-lib（028 剥净 + 零发现零执行）、plugin-fixture 良构（025 全链 + 双钩子触发）——全部在 239 passed 中实跑；坏面 = 本票新补（见上）。
- **spec 004 收口**（见 004 票 `## Resolution`）：US 32 全兑现 + 决定 1-22 直落（spike 修正指认：决定 8/10/17/19）+ 链偏差汇总 62 项（020-028）+ 完成定义①-④ 复核。
- **spec.md 执行级订正折回**：§4.6（t2 jaix 前置归后续票——004 决定 1 拍板为准；t3/t5-t9/t11 已由 1c 接管）、§6.3（at 接线子集 = core 四挂载点 + 派发粒度阶段级 + 其余 10 seam 留后续票）、§7.2（产品落 target/transpile/ + Testing 面编译视图）、§7.3（单一发现源统一 + 显示名 = 过程名 + "Found N" 不产 + 零测试判定收集期零条目）。
- **下一步 = 阶段 2（005：build.jai metaprogram + modules 发布）**；后续票面（jaix PRESTEP 全链 / at 接线其余 10 seam / 真实第三方成员插件包 / lint）只记不建。
