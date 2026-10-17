---
title: "Spec: juice 转译机制插件化——管线 runner + 内置插件 + Package 配置面（jaix 风格）"
status: closed
labels: [ready-for-agent]
assignee: maojiaxing
blocked-by: []
---

> 决策来源（合成自，无新增决策）：研究 B（`docs/research/transpile-plugin-architecture.md`，2026-10-14——本 spec 的既有研究基准，路线已画）+ 本会话与用户拍板（三问：四接缝 / 范围 = 进程内管线、第三方宿主出范围 / 注册形态 = 扩展 juice Package 配置支持 jaix 风格配置）。上游权威：ADR 0004（义务转译）、ADR 0005（行号保真硬约束）、ADR 0006（bootstrap 剥离）、ADR 0007（jaix 前置并存）；CONTEXT.md Transpile 词条（juice 自身 Transpile 与 jaix 前置并存不替代）。

## Problem Statement

juice 的转译机制今天处于「半插件化」状态：通用 source-to-source 基础设施（lexer、Edit 机制、行号保真 helper、内容寻址缓存、闭包探测/视图落盘、seam 形参注入）与 test block 专用逻辑（锚点识别、`juice_test_N` 重写、`@test` 注记、Test_Entry 清单）同处一个扫描循环内——`#load` 与 test 锚点两个分支硬编码在 `transpile_source` 单函数里。对用户（包作者与 juice 维护者）这意味着：

1. juice 恰好支持两种硬编码转换，任何新的语法扩展/转换需求都要改核心循环；没有声明过的插件契约，转换逻辑无法新增或替换。
2. 缓存失效是全局版本号（JUICE_VERSION）一刀切——任何输出契约变化都要 bump 整个转译器，没有管线级别的失效粒度。
3. 包作者无法声明自己的包走什么管线；管线的组成、顺序、交互契约（loads inside test bodies）全部隐式存在于扫描实现里。

研究 B 已核验：当前机制分层边界清晰、可无损拆分（结论 1/2/3），最小改造路径明确（结论 4、3.2 节）——本 spec 把这条路线锁成可实施的规格。

## Solution

juice 自身 Transpile 机制插件化，用户可见的结果：

1. 转译管线成为注册表驱动的机制：test block 与 `#load` 处理成为前两个内置插件，扫描循环升级为管线 runner；新的转换以后只写插件、不改核心。
2. 缓存键获得管线描述分量（有序插件 name+version）——管线变化精准失效视图，JUICE_VERSION 语义泛化为「管线输出契约版本」。
3. 包作者可以在 Package 配置（package.jai）里声明自己的转译管线（jaix 风格：插件 id + version + 类型化选项），声明序 = 管线序；未声明 = 缺省管线（现状行为零变化）。
4. 零可观测行为变化：三路径全绿、既有测试一字不改、golden 零重定——重构的保真由既有逐字节锁定持续证明。

## User Stories

1. As a juice maintainer, I want the transpile scan loop refactored into a pipeline runner, so that test-block and #load handling become dispatched plugins rather than hardcoded branches.
2. As a juice maintainer, I want plugins dispatched by scan position from a registered set, so that new transforms add anchors without editing the runner.
3. As a juice maintainer, I want the test-block/#load interaction contract (loads inside test bodies) explicit at the runner layer, so that plugin composition does not depend on implicit pass ordering.
4. As a juice maintainer, I want closure probing to ask the pipeline (aggregated anchor-detection and load-edge hooks), so that probe functions stop hardcoding the two transforms.
5. As a juice maintainer, I want test-free closures to remain zero-transpile (ADR 0004 决定 1), so that packages without anchors still pay nothing.
6. As a juice maintainer, I want the view cache key to include the pipeline description (ordered plugin name+version), so that pipeline changes invalidate stale views.
7. As a juice maintainer, I want JUICE_VERSION semantics generalized to the pipeline output contract, so that a plugin version bump alone triggers cache invalidation.
8. As a juice maintainer, I want the Merkle-chain property of view keys preserved, so that dependency-ordered computation stays deterministic.
9. As a juice maintainer, I want the new pipeline module test-free and bootstrap-#loadable, so that the bootstrap build keeps sharing the transpiler.
10. As a juice maintainer, I want the existing transpile injection seams unchanged, so that the three orchestration paths and their recording fakes keep working untouched.
11. As a juice maintainer, I want view landing, driver/metaprogram generation and the golden matrix reused as-is, so that the change stays minimal (研究 B 最小改造).
12. As a juice maintainer, I want byte-for-byte identical output (EXPAND/STRIP shapes, diagnostics, line fidelity, CRLF), so that the refactor provably changes nothing observable.
13. As a juice maintainer, I want ADR 0005's 1-line-1-line contract enforced for every plugin, so that line fidelity survives any future plugin.
14. As a juice maintainer, I want violating plugin shapes (reformatting, header notes, non-equal-line expansion) rejected at transpile time, so that bad plugins fail loudly (multi-line test head precedent).
15. As a juice maintainer, I want the pipeline to stay an anchor-level text pipeline and not adopt jaix's AST plugin model, so that the two systems keep their distinct contracts (CONTEXT.md 并存不替代).
16. As an in-repo plugin author, I want identity (name+version) in my plugin declaration, so that my plugin participates in the pipeline description and cache key.
17. As an in-repo plugin author, I want to declare mode applicability (STRIP/EXPAND behaviors), so that I can behave differently per view mode like the test-block plugin does.
18. As an in-repo plugin author, I want paired probe hooks (anchor detection, optional load edges), so that closure probing discovers my anchors and edges.
19. As an in-repo plugin author, I want a transpile hook receiving scan position context, so that I can emit edits, manifest entries and diagnostics at anchors.
20. As an in-repo plugin author, I want cross-file state passed through the transpile context, so that per-file counters (test numbering) keep working across files.
21. As an in-repo plugin author, I want my edits bounded by tokens and line-for-line, so that my output obeys the fidelity contract by construction.
22. As a package author, I want to declare the transpile pipeline in my package manifest (jaix-style: plugin id + version + typed options), so that my package controls which transforms run.
23. As a package author, I want an undeclared pipeline to mean the default (test block + #load), so that existing packages behave identically.
24. As a package author, I want declaration order to be the pipeline order, so that composition is explicit.
25. As a package author, I want unknown or duplicate plugin ids rejected with clear diagnostics, so that misconfiguration fails loudly at manifest validation.
26. As a package author, I want the manifest evaluator to report pipeline records over the established protocol channel, so that build/test read them like the jaix marker records today.
27. As a package author, I want typed options in the declaration shape (compile-time checked), so that option typos fail at manifest compile time rather than silently.
28. As a package author, I want the option surface empty for the two built-in plugins in this release, so that the declaration stays a pure mechanism without new behavior.
29. As a package author, I want explicitly declared built-in plugins in the default order to produce the same views and cache keys as the undeclared default, so that declaring is a no-op unless it changes the pipeline.
30. As a juice developer, I want the three-path verification loop unchanged and green, so that bootstrap/build/test all keep working.
31. As a juice developer, I want the existing transpile tests untouched and green, so that the refactor's fidelity is continuously proven.
32. As a test author, I want a synthetic third plugin in the sister test file, so that pipeline mechanics (probe aggregation, dispatch, state, cache sensitivity, rejection) are proven without touching the two real plugins' locked outputs.
33. As a maintainer of docs, I want CONTEXT.md vocabulary updated with the pipeline terms, so that the codebase stays navigable.
34. As a maintainer of docs, I want an ADR recording the pipeline contract (hard constraint + config-driven registration), so that the decision is durable (ADR 0004/0005/0007 family).

## Implementation Decisions

1. **范围（用户拍板）**：进程内管线 + 两个内置插件（test block、#load）。第三方插件宿主（研究 B 3.3 b/c/d——动态库/独立进程 filter/编译期 -plug）与段二（jai 原生 metaprogram 插件）出范围——机制先行，宿主选择留后续。
2. **插件接口形状**：插件声明 = 身份 {name, version}（进管线描述与缓存键）+ 模式适用性声明（STRIP/EXPAND 下各提供什么行为——test 插件两模式行为完全不同、#load 插件两模式共享识别）+ 探测钩子成对（`has_anchor(source, path)` 喂闭包探测聚合；可选 `load_edges(source, path)` 喂闭包 DFS）+ 转译钩子（扫描位点上下文回调——识别锚点后产 Edit/清单条目/诊断）+ 跨文件状态经 Transpile_Context 扩展字段（现成通道——test 编号续号同款）。
3. **管线 runner**：`transpile_source` 的扫描循环保留为 runner（深度 + 语句位置 + 编辑收集骨架不动）；`#load` 分支与 test 锚点分支改为向注册插件派发。**区域交互契约显式化**：test 插件声明区域（块体）后 runner 继续向其余插件派发——「loads inside test bodies」现契约（EXPAND 下 test 体内 #load 仍被剥离）的显式形式；STRIP 下 test 体整体占位、其内 #load 随之消失的语义不变。
4. **探测聚合**：`probe_package_closure` 与 `closure_has_tests` 改为管线聚合版本（load_edges 聚合 + has_anchor 聚合）；test-free 闭包零转译（ADR 0004 决定 1）短路语义不变。
5. **缓存键**：`transpile_view_key` 增管线描述分量（有序 name+version 序列——jaix 管线描述同款形状）；JUICE_VERSION 语义泛化为「管线输出契约版本」（插件版本 bump 即键变）；load 重写表嵌入与 Merkle 链性质不变。
6. **注册形态（用户拍板）**：扩展 juice Package 配置支持 jaix 风格管线配置——Package 声明面新增管线字段（声明数组：插件 id + version + 类型化选项槽）；manifest 求值器按声明序打印 `TRANSPILE_PLUGIN=<id>|<version>` 可重复协议记录（JAIX_CONFIG 同族先例：恒打印 + 严格解析、重复 = Duplicate ... record.）；纯函数校验门（validate_jaix_marker 同款拆分——未知 id / 重复 id / 非法选项 = 诊断拒绝；load 路径进程内不可测的测试缝同款）；内置插件按声明序参与管线；**未声明 = 缺省管线**（两内置插件按现状交互契约）——现状行为零变化。v1 两内置插件选项集为空（类型化选项槽就位、无实际选项行；跨进程协议只带 id+version——jaix「选项值不跨进程」同款立场，选项面留后续）。
7. **模块落点**：新 test-free 共享模块（bootstrap build.jai 的 `#load` 目标——研究 B 3.2.4 硬约束）；其单元测试驻 tests/ 姊妹文件（0053 测试组织规则）。探针与 seam 全部保持现状：三条路径的注入形参不变（管线以单个 `#type` 值身份注入）。
8. **硬约束（ADR 0005）**：每插件遵守「1 行换 1 行、编辑以 token 为界、同行其余内容属逐字区」；无法等行数展开的输入形态转译期拒绝（多行 test 头先例）；违反形状（重排版、头部注记）一律拒绝。
9. **复用不动**：视图落盘（view_of_file）、driver/metaprogram 生成、golden/negative/编译运行矩阵——它们只依赖「每文件一个视图文本 + 键 + 清单」契约，与管线内部结构无关。
10. **与 jaix 关系**：并存不替代（CONTEXT.md 已立）——juice 管线 = 锚点级文本编辑（行号保真、bootstrap 自足、零依赖），jaix = 整树 AST 变换；本 effort 不采用 jaix 插件模型。
11. **文档收口**：新 ADR（管线契约：ADR 0005 硬约束 + 配置驱动注册形态）+ CONTEXT.md 词条（转译管线/插件声明面）+ IMPLEMENTATION.md 模块表。

## Testing Decisions

- **好测试判据**：只测外部行为——视图逐字节、探测结果、缓存键、manifest 协议记录与校验诊断、管线派发的可观测效果（合成插件）；不测 runner 内部实现细节。
- **接缝 1（三路径不变式）**：`jai build.jai`（debug 与 `- release`）+ `./target/juice.exe test` + `juice build` 自构建全绿；先清 target/transpile（memory 已记）。
- **接缝 2（转译输出契约面）**：transpile_tests / transpile_front_tests / metaprogram_tests 逐字节锁定 + tests/data/transpile golden/negative/run 矩阵**零重定**（30 GOLDEN PASS 原样、零 UPDATE）——既有测试一字不改 = 保真证据。
- **接缝 3（插件接口姊妹测试）**：新姊妹测试文件（模块 test-free → 驻 tests/）——合成第三插件证明管线机制：探测聚合（has_anchor/load_edges 喂闭包探测）/ 转译钩子派发（Edit/清单/诊断三通道）/ 跨文件状态（计数器跨文件续走）/ 模式适用性（STRIP/EXPAND 两行为声明）/ 缓存键对 name+version 敏感（版本变 → 键变）/ ADR 0005 违反拒绝（等行数展开失败 → 诊断）。
- **接缝 4（Package 配置面）**：求值器协议记录单测（声明序 / 空声明缺省）+ 严格解析两 case（重复拒绝）+ 校验门矩阵（未知 id / 重复 id / 非法选项）+ 显式声明两内置插件（缺省序）== 缺省管线（视图与缓存键同值）。
- **先例**：0050（收敛 + 零行为变化 + 文档同步）、0057（manifest 标记协议 + 校验矩阵）、transpile_tests 逐字节锁定（研究 B 引用清单）、golden/negative/run 矩阵（docs/transpiled-output-formatting.md §4）、0053 测试组织规则。

## Out of Scope

- 第三方插件宿主（研究 B 3.3 b/c/d：运行时动态库 / 独立进程 filter / 编译期插件）与段二（jai 原生 `-plug` AST 插件——compiler_modify_procedure 稳定性顾虑随研究 B 4.x）。
- 采用 jaix 插件模型替代 juice 自身管线（并存不替代）。
- 新用户面转译特性（新 transform / 新语法扩展）——本 effort 只交付机制 + 两个既有转换的插件化。
- 两内置插件的选项面实装（选项槽就位、选项集空）。
- 流式/增量转译、packrat 记忆化（既有 out of scope 不变）。
- bootstrap 之外的配置求值第二通道（管线配置经既有 manifest 求值器，无新子进程面）。

## Further Notes

- 上游权威：研究 B = `docs/research/transpile-plugin-architecture.md`（结论 1-8、最小改造 3.2、三选项 3.3）；ADR 0004/0005/0006/0007。
- 语言：中文交流与文档。
- 每会话开工先读 juice CONTEXT.md 与测试组织规则（memory 已记）；juice 三路径验证循环见既有记忆。
- 收口定义：四接缝全绿 + ADR/CONTEXT/IMPLEMENTATION 同步。

## Resolution

**收口（2026-10-18，票 0064）**：接缝 1-4 全绿 + ADR/CONTEXT/IMPLEMENTATION 文档同步——收口定义达成。

- **接缝 1（juice 三路径）**：debug 与 release 构建绿 + 各 **242 passed, 0 failed** + **30 GOLDEN PASS**（全程唯一 UPDATE 运行在 0062：7/7 golden driver.jai 仅键哈希列一次性重定——键变必然落点变化；视图 9/9 + first.jai 7/7 + negative 7/7 零重定，0062 偏差 1）+ `juice build` 自构建绿。
- **接缝 2（转译输出契约面）**：transpile_front_tests / metaprogram_tests 逐字节未改、原样通过；transpile_tests 按 0062 缓存键契约测试演化（11 行：成分注释补管线描述 + 异管线 / 缺省值断言）后原样通过；golden/negative/run 矩阵零重定（唯一重定即 0062 偏差 1 的 driver.jai 哈希列一次性重定——键变必然落点变化，非排版漂移）。
- **接缝 3（插件接口姊妹测试）**：tests/transpile_plugin_tests.jai 13 块全绿——合成第三插件证明探测聚合 / 派发三通道（Edit/清单/诊断）/ 跨文件状态续走 / 模式适用性 / 缓存键对 name+version 敏感 / ADR 0005 违反拒绝。
- **接缝 4（Package 配置面）**：协议记录单测（声明序 / 空声明缺省）+ 严格解析两 case + 校验门矩阵（未知 id / 重复 id / 非法选项）+ 显式声明两内置插件（缺省序）== 缺省管线（视图与缓存键同值）+ E2E fixture 双 case（pipeline-explicit / pipeline-unknown）全绿。
- **story 22 / story 27 字面缺口备注**：两 story 的兑现按 0063 已落档偏差收窄——story 22（声明 version v1 为装饰性字段：不校验、不进键，缓存键反映解析后的内置 version——0063 偏差 3）；story 27（「编译期选项检查」未达字面：选项行在 manifest 编译期可写、load 期校验门响亮拒绝，不静默——0063 偏差 4）。

**决定直落**：1 → 0061（进程内管线 + 两内置插件；第三方宿主与段二留后续）；2 → 0061（插件接口形状：身份 + 模式适用性 + 探测钩子成对 + 转译钩子 + 跨文件状态）；3 → 0061（runner + 区域交互契约显式化）；4 → 0061（探测聚合 + test-free 零转译短路不变）；5 → 0062（缓存键管线描述 + JUICE_VERSION 语义泛化）；6 → 0063（Package 声明面 + 协议记录 + 校验门 + 未声明 = 缺省）；7 → 0061（test-free 共享模块 + 姊妹测试 + seam 注入不变）；8 → 0061（runner 强制 ADR 0005——「1 行换 1 行」+「以 token 为界」）；9 → 0061/0062/0063 全程（视图落盘 / driver/metaprogram 生成 / golden 矩阵复用不动）；10 → 0064 ADR 0008（并存不替代）；11 → 0064（ADR + CONTEXT + IMPLEMENTATION 同步）。US 1-34 全兑现（33/34 文档收口经 0064 落地）。

**实施链**：0061（管线核心，212 → 222）→ 0062（缓存键面，222 → 224）→ 0063（配置面，224 → 242）→ 0064（本收口票，零产品代码）。

**文档**：ADR 0008 新篇（管线契约）+ ADR 0005 修订行（硬约束由 runner 强制——机制承载）；CONTEXT.md 新词条转译管线 / 插件声明面 + Transpile 词条同步；IMPLEMENTATION.md 模块表补 transpile_plugin / transpile_config 行（transpile_cache 行补 0062 语义）。

**偏差（链上汇总）**：0061 四条（工作树机制 / 「编辑以 token 为界」读法修正——起点与终点各落在某 token 的起点或终点边界 / 测试计数 +10 / 缓存键与配置面归后续票）、0062 四条（driver.jai 金样 7/7 哈希列一次性重定——键变必然落点变化 / resolve_pipeline 极小提取 / 计数 +2 / 生产键位点预接 ctx.plugins）、0063 六条（依赖视图与 jaix mirror 排除集恒缺省管线 / Testing 模块视图恒缺省管线 / 声明 version 不校验不进键 / 类型化选项槽执行级形状 = key/value 选项行 / seam #type 增默认空第三形参（本版 jai 无闭包）/ 求值器 codegen 测试为形状锁）。0064 无产品代码偏差（收口票纪律）。
