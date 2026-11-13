---
id: 004
title: 阶段 1c spec：插件加载面骨架
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [003]
blocks: [005]
---

> 父 map：`../map.md`。上游规格：`docs/spec.md` §5（插件系统规格）、§6（lifecycle 挂载规格）、§8（转译与 lint 规格）、§10 阶段 1；研究文档 A（`docs/research/plugin-auto-discovery.md`）、L（`docs/research/plugin-lifecycle-hooks.md`）、R§3（现有插件机制与可泛化点）。
> 参照面（只读）：juice/src 的 transpile.jai / transpile_plugin.jai / transpile_cache.jai / transpile_front.jai / transpile_config.jai / commands/{build,test}.jai；jaix/src/plugin.jai（get_plugin 契约 + merge_plugins 形状）；juice/src 内联测试（语义先例）。

## Problem Statement

1a/1b 收口后 otter 六命令全部真实现，但**转译层整块缺席**（002 切线 C + 1b 切线 A 移交面）：build 的 b5 依赖剥离/b7 入口选择是恒等占位（011 偏差，`build.jai:256-261`），test 命令对 test 块文件直接撞语法错误（018 偏差：otter 自身根 exe test 不可用 = 切线 A 预期状态）。同时插件系统只有 spec 级形状，无一行实现：`Juice_Plugin` 接口面、扫描发现 + 注册文件 codegen、合并查重、lifecycle 挂载面全部待落地。

1c 交付**插件加载面骨架**（chart 拍板：第三方插件全链路端到端留后续票）= 转译层全量 + 插件接口面 + lifecycle 机制，使 build/test 的转译视图面真实现、otter 自身套件经 EXPAND → `@test` → note 发现端到端可跑。

## Solution

按 spec §5/§6/§8 语义重写（旧 juice 转译族模块为参照面）：内置 transpile 插件（load/test 块）静态注册并接 build b5/b7 与 test t3/t5-t9/t11；`Juice_Plugin` 全字段 + `get_juice_plugin` 获取契约 + `@juice_plugin` 尾注标记；扫描发现（scan_walk 确定性 DFS 词法序 + 词法锚点识别）→ 注册文件 codegen；合并查重；lifecycle 骨架（封闭阶段枚举 + 钩子形状 + 确定性排序 + 显式 ctx 槽 + 失败语义 + 核心阶段 at 接线）。

范围切线（用户拍板 2026-10-20）：**① jaix PRESTEP defer**——PRESTEP 阶段枚举保留（§6.1 九阶段不动），b6/t2 恒等占位照旧，jaix_front 移植（扫描/spawn/镜像/exe 解析全链）留后续票；**② at 接线 = 代表性子集**——机制全立，at 派发只接 build+test 的 TRANSPILE/COMPILE 四挂载点，其余 seam 留 `#type` 形参（机械接线后续票）；**③ 验证面 = 合成 fixture 插件包**——tests/data/ 下合成插件包走全链 E2E，真实成员插件包（packages/ 布局）留后续票；**④ lint defer**——§8.2 留后续票。

## User Stories

1. As a plugin author, I want to write one file defining `get_juice_plugin` with an `@juice_plugin` tail note, so my plugin is discovered without editing any central registry.
2. As a plugin author, I want the `Juice_Plugin` struct to carry id, version, transpile contribution, hooks and options schema, so one value describes all my plugin's faces.
3. As a plugin author, I want a derived struct with typed options members, so my options are compile-time type-checked at the call site.
4. As a plugin author, I want my transpile contribution to declare mode applicability (strip/expand), so I am only dispatched in modes I support.
5. As a plugin author, I want paired probe hooks (has_anchor/load_edges), so closure-view decisions and dependency DFS edges work without transpiling whole files.
6. As a plugin author, I want claim semantics covering exactly the tokens I consume, so unconsumed regions continue dispatching to later plugins.
7. As a plugin author, I want the line-fidelity gate enforced on my edits (1 line in = 1 line out, token-bounded), so a bad edit fails loudly instead of silently drifting line numbers.
8. As a plugin author, I want per-pipeline state shared across files (plugin_state slots), so numbering and other state continue across files in one compile.
9. As a plugin author, I want duplicate ids, conflicting versions, hook mount conflicts and claim conflicts rejected with full diagnostics at merge time, so misconfiguration is caught at registration, not at runtime.
10. As a plugin author, I want my id+version+order in the pipeline description feeding cache keys, so views regenerate whenever my pipeline changes.
11. As a juice user, I want the built-in test-block transpile plugin to EXPAND test blocks into `juice_test_N` procedures with `@test` notes, so existing test suites work unchanged.
12. As a juice user, I want the built-in load transpile plugin to handle #load (same-line placeholder in EXPAND, target rewrite in STRIP), so bootstrap-style loads keep line fidelity.
13. As a juice user, I want global test numbering to continue across files with base 1, so generated names stay unique and ordered.
14. As a juice user, I want handwritten `@test` procedures and test blocks unified under one discovery source, so both test styles run through the same enumeration.
15. As a juice user, I want build to strip test-bearing dependency closures into `target/transpile/deps/` with rewritten shims, so my executable builds even when dependencies embed tests.
16. As a juice user, I want build's entry selection to compile test-free sources verbatim and strip views for test-bearing closures, so only my own tests stay out of my build.
17. As a juice user, I want content-addressed view caching, so unchanged files skip re-transpiling.
18. As a juice user, I want dependency tests neither discovered nor executed (strip views for the dependency closure), so my test run covers only my package.
19. As a juice user, I want the Testing module compile-view special case (target/testing-module/), so packages with modules/Testing.jai self-test correctly.
20. As a juice user, I want path_mapping from view lines back to original source lines, so test failures point at my source, not the view.
21. As a juice user, I want `juice test` on the juice repo itself to pass via EXPAND + note discovery, so stage 1c closes the known test-block gap from stage 1b.
22. As an otter developer, I want built-in plugins in a static registry with an explicit #load list, so the bootstrap closure stays test-free and auditable.
23. As an otter developer, I want an empty plugin registry to resolve to the default pipeline in one place, so views and their keys always reflect the same pipeline.
24. As an otter developer, I want third-party plugin discovery by deterministic DFS lexical scan with lexical anchor recognition of `@juice_plugin`, so registration files are reproducible.
25. As an otter developer, I want generated registration files with per-name codegen plus a hook-assembly segment, so Jai's lack of runtime top-level execution is not a blocker.
26. As an otter developer, I want the lifecycle stage enum closed (add-only), so stage renames can't silently break plugin surfaces.
27. As an otter developer, I want deterministic hook ordering (hardcoded stage order, declaration order within a stage, before/after both forward), so pipeline behavior is reproducible.
28. As an otter developer, I want hook failure (false or ERROR diagnostic) to fail the stage, the command and the exit code, so observer hooks can't silently pass.
29. As an otter developer, I want explicit ctx state channels (no closures), so plugin code works under Jai's closure restriction.
30. As an otter developer, I want at-hook dispatch wired for the core stages (TRANSPILE/COMPILE in build and test), so the at mechanism is proven on real orchestration paths.
31. As an otter developer, I want the plugin scan, codegen, merge and hook surfaces verified end-to-end with synthetic fixture plugin packages, so the full third-party chain is provably working without monorepo member changes.
32. As an otter developer, I want old juice to keep building and testing the otter root with zero special-casing (debug+release), so the bootstrap invariant holds through stage 1c.

## Implementation Decisions

1. **范围切线（用户拍板 2026-10-20）**：① jaix marker 前置 defer——PRESTEP 阶段枚举保留，b6/t2 恒等占位照旧（011/1b 现状不动），jaix_front 移植留后续票；② at 挂载接线 = 代表性子集（见决定 17）；③ 第三方验证面 = 合成 fixture 插件包（tests/data/ 下，不进根 package.jai 依赖面）；④ lint defer（§8.2 留后续票）。
2. **1c 内容 = 转译层 + 插件面 + lifecycle 骨架**：转译层全量（build b5 依赖剥离前端 + b7 入口选择视图面——接替 011 恒等占位；test t3 EXPAND + t5-t9 视图面 + t11 依赖剥离——1b 切线 A 接替面）；插件加载面骨架（§5.1 接口面 + §5.2 扫描/codegen/合并机制）；lifecycle 骨架（§6 全机制 + 核心阶段接线）。
3. **Juice_Plugin 结构**（spec §5.1 定稿形状，全字段）：

   ```
   Juice_Plugin :: struct {
       id:            string;                     // 身份（进管线描述/缓存键）
       version:       string;
       transpile:     *Transpile_Plugin = null;   // 转译管线贡献面（可空；非空则注册进声明序管线，
                                                  //   继承行号保真契约与成对探测钩子——R§3.1/L§3.2）
       hooks:         [..] Lifecycle_Hook;        // lifecycle 挂载面（§6）
       options_schema: [..] Config_Option;        // 选项 schema {default, validate}（jaix 形状，R§3.2）
   }
   ```

4. **获取契约**：插件模块导出 `get_juice_plugin :: () -> *Juice_Plugin` + 尾注 `@juice_plugin`（标记名随命名定稿统一）；返回派生结构体指针（基类 `using` 继承 + 类型化 options 成员），框架侧 `as_plugin` 显式 cast 上转消费——派生指针保证配置侧编译期类型检查（jaix `get_plugin` 官方契约，`plugin.jai:10-35,185-187`）。
5. **Transpile_Plugin 接口**（§8.1，旧 juice `transpile_plugin.jai:76-83` 语义等价重写）：

   ```
   Transpile_Plugin :: struct {
       name:       string;
       version:    string;
       modes:      Transpile_Plugin_Modes;   // {strip, expand} 模式适用性声明
       has_anchor: #type (source: string, path: string) -> bool;   // 可空
       load_edges: #type (source: string, path: string) -> [..] string;  // 可空
       transpile:  #type (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool;
   }
   ```

6. **两内置插件**：`load`（#load 处理：EXPAND 等行数占位 / STRIP 目标改写；`load_edges` 喂闭包 DFS；无 anchor）与 `test 块`（两模式重写 + `@test` 注记 + Test_Entry 簿记；`has_anchor` 喂闭包视图决策）——声明序 = 管线序（spec 0060 决定 6）；空注册表 = 缺省管线（`resolve_pipeline` 单一落点，视图与其键恒反映同一管线）。
7. **runner 硬约束**（ADR 0008 决定 2）：声明序派发；claim 覆盖恰好消费的 token、未消费区域继续派发；模式适用性门控（未声明 token 走 runner 缺省追踪）；行号保真门 = 每条编辑「1 行换 1 行 + 以 token 为界」，违反丢弃 + 诊断拒绝——坏插件在转译期响亮失败，不静默漂移行号。
8. **内置注册 = 静态**（A§4.1）：静态数组 + 显式 `#load` 列表——自动发现对内置件无收益且违反 bootstrap 纪律（第三方痛点不适用于内置件）；1c 内置注册表 = 两 transpile 插件（命令面仍走六命令注册表，正交不动）。
9. **扫描发现（第三方面机制，§5.2 候选 (c)）**：`scan_walk` 确定性 DFS 词法序（015 骨架 + 排除谓词注入复用）+ 词法锚点识别 `@juice_plugin` 尾注挂 `get_juice_plugin` 声明（juice `is_test_anchor` 同款手法）；插件包入口探测序 = `module.jai` → `src/module.jai` → `<name>.jai`。1c 的扫描 = 库面 + fixture 验证，不接命令编排面（声明面随第三方全链路票）。
10. **注册文件 codegen 形状**（§5.2 定稿；Metaprogram_Plugins 逐名 codegen 先例）：

    ```
    JUICE_PLUGIN_<i> :: (#import "<模块名>").get_juice_plugin();   // 按扫描序的显式调用
    JUICE_HOOK_<i> :: .{stage = …, position = …, hook = …};        // 钩子条目装配段（L§5.4 收敛）
    ```

    落点 = `target/` 下生成件（不进 bootstrap 闭包、不入库）；会话产物、每跑重生、clean 随 target/ 整删；具体文件名 = 拆链票定（约束见本决定）。
11. **合并查重**（`merge_plugins` 形状，jaix `plugin.jai:336-471`）：重复 id/异版本冲突、钩子挂点冲突、transpile claim 冲突 → 全部 ERROR 诊断 + `ok=false` 拒绝继续——构建期拒绝，早于 linkme 式运行期 panic 兜底（A§4.2.4）。
12. **Lifecycle_Stage 封闭枚举**（§6.1 九阶段定稿，只增不改——jaix Node_Kind 纪律 + spec 版本化承诺）：

    ```
    Lifecycle_Stage :: enum { DISCOVER; PREPARE; VALIDATE; DEP_STRIP; PRESTEP;
                              TRANSPILE; COMPILE; EXECUTE; CLEAN; }
    ```

13. **Lifecycle_Hook 形状 + ctx**（§6.2）：

    ```
    Lifecycle_Hook :: { stage: Lifecycle_Stage; position: Hook_Position;   // {before, at, after}
                        hook: #type (ctx: *Lifecycle_Context, state: *void) -> bool; }
    ```

    `Lifecycle_Context` = 阶段名 + 该阶段可观测状态（§6.1 表列：artifact plans / 视图表 / 产物路径等）+ `diagnostics` 三汇 + `plugin_state` 槽。
14. **确定性排序**（§6.4 已裁）：阶段序 = 命令编排硬编码序（§6.1 表）；阶段内钩子序 = 注册声明序；`before` 与 `after` 同为注册序正序（逆序对称方案已否决）；未经过的阶段（如无 marker 时的 PRESTEP）其钩子静默不触发。
15. **失败语义**（§6.5）：钩子返回 `false` 或产 ERROR 诊断 = 阶段失败 → 命令失败 → 退出码（`HANDLER_FAILED` 传播）；观察类钩子失败同样中止（失败继续属测试执行层，不属钩子层）；部分状态防护不豁免钩子（prepare「全部成功才发布」、clean「先全量校验后删除」——钩子失败发生在发布/删除之前）。
16. **跨阶段状态 = 槽协议**（§6.5 已裁）：`plugin_state` 槽与钩子注册序对齐、宿主持有存储、跨阶段续走（构造期恒 null——juice 先例已在生产验证，非 jaix 强注入）；无闭包纪律 = 全部显式 ctx 数据传递（0063 偏差 5）。
17. **at 接线（代表性子集，用户拍板）**：build 的 TRANSPILE（b5/b7 的 transpile 形参面）与 COMPILE（b8 compile 形参面）、test 的 TRANSPILE（t3/t11）与 COMPILE（t12）四挂载点改为钩子表派发——执行形状 = seam `#type` 形参换钩子集数据形参 + 生产默认 = 内置实现（0063 偏差 5 的「seam #type 增默认空数据形参」先例）；`at` 替换身份进管线描述（换实现 = 换视图键，语义文档化）；其余 10 seam（discover/resolve/prepare_dependencies、build/test 的 prestep、clean 两、run launch、jaix spawn）留 `#type` 形参，机械接线留后续票。
18. **转译视图面**：b5 依赖剥离前端（探测 + STRIP 视图落 `target/transpile/deps/` + shim `#load` 改写）；b7 入口选择（test-free 直编原文 / 含 test 闭包全有全无 STRIP 视图）；t3 逐文件 EXPAND + 全局编号基 1 续号 + Test_Entry 降级为转译簿记（行号保真/path_mapping——发现源仍是 note 枚举）；t5/t8 内容寻址视图（`target/transpile/<hash>/<rel>`，命中跳过写入）；t9 Testing 模块编译视图（`target/testing-module/`——`metaprogram.jai:74` testing_view_dir 移交点 + `test_metaprogram.jai:59` 白名单移交点）；t11 依赖剥离（依赖测试不发现不执行）；path_mapping = 视图行 → 原文行表随 driver 生成时嵌入。
19. **缓存键契约**：视图键 = hash(路径 + 源 + 模式 + 版本 + load 重写表 + 管线描述)（0062）；otter 键带自身版本分量、与旧 juice 键不共享（spec §11.9 有意选择）；`JUICE_VERSION` 语义 = 管线输出契约版本。
20. **完成定义**：① otter exe `test` 于根自跑套件全绿（test 块 → EXPAND → `juice_test_N` + `@test` → note 发现统一——018 切线 A 预期状态解除，path_mapping 指向原文行）；② otter exe `build` 于根真剥离视图编译（b5/b7 接替 011 恒等占位）；③ 三接缝全绿（旧 juice 不变式 debug+release 4/4 + 238 存量测试不回归 + 1c 新测试）；④ 合成 fixture 插件包全链 E2E（扫描 → codegen → 合并 → 真编译加载）。
21. **实现纪律**：旧 juice 语义等价重写（参照面非复制——015/017 惯例）；1c 新模块（transpile_plugin/transpile_cache/transpile_front/plugin/lifecycle 等）test-free、测试驻 `tests/` 姊妹文件（阶段 2 bootstrap #load 集纪律——前三者正是旧 juice 的 test-free 五模块之三）；子进程绝对路径、Windows-first（cmd /c、LNK1104 副本纪律）照旧。
22. **四硬约束全程**（R§1/§6）：模块名 "Juice" load-bearing；bootstrap 期 Package 不加字段；TRANSPILE_PLUGIN id 集 ⊆ juice 合法集（otter/package.jai 无声明 = 缺省管线，天然安全）；lint 零先例（1c 不涉）。

## Testing Decisions

- **接缝 1（旧 juice 不变式）**：1c 每步 `juice build`/`juice test` 于 otter 根零特判全绿（debug+release 4/4）；otter/package.jai 无 TRANSPILE_PLUGIN 声明（缺省管线，id 集纪律天然守）；开发循环仍用旧 juice。
- **接缝 2（姊妹测试）**：`tests/*_tests.jai`（test 块——阶段 0-2 约束）；1c 实现模块 test-free（bootstrap #load 集纪律）。面清单：transpile_plugin_tests（声明序派发/claim 契约/模式门控/行号保真门矩阵/成对探测）、transpile_front_tests（剥离前端探测/视图落盘/shim 改写）、transpile_cache_tests（键成分/命中跳过）、plugin_tests（合并查重矩阵/挂点冲突/claim 冲突）、plugin_scan_tests（词法锚点判定/扫描序/入口探测序）、registration codegen（生成文件形状/逐名 import/钩子装配段）、lifecycle_tests（排序/失败传播/ctx 槽/未经过阶段静默）、build b5/b7 与 test t3/t5-t9/t11 接线测试。
- **接缝 3（E2E 真子进程）**：build-with-tests fixture（含 test 块包 build 剥离成功 + artifact 产出运行）；test 全链（EXPAND → 编号 → 注记发现 → 编译执行 + path_mapping 指向原文行）；**合成插件包 fixture ×2**（tests/data/ 下，不进根 package.jai 依赖面——排除集豁免区纪律）：一个良构（transpile 贡献 + hook，注册文件生成 → 真 jai 编译加载），一个坏（重复 id / 行号保真违规 → 响亮拒绝）；旧 juice 不变式复核。
- **好测试标准** = 只测外部行为（给定源文本 + 插件集 → 视图文本/诊断文本/注册表内容/退出码/盘上产物），不测 runner 内部状态与派发轨迹。
- **先例**：015 排除谓词注入、016 发现纯函数面、017 生成器形状测试、014/019 fixture 家族（静态 fixture 化惯例）；旧 juice `tests/` 下 transpile 族测试语义先例（同语义迁姊妹文件，非复制）。

## Out of Scope

- **jaix PRESTEP 全链**（jaix_front 移植 / b6+t2 接线 / 扫描-spawn-镜像面）——后续票；PRESTEP 枚举保留、b6/t2 恒等占位不动。
- **at 接线其余 10 seam** 的钩子表派发——后续机械票（机制已立，接线面机械）。
- **真实第三方成员插件包**（packages/juice-plugin-* monorepo 布局 + workspace.members 变更 + 插件声明面——package.jai 兄弟常量/协议面的设计）——后续票。
- **lint**（§8.2 observer metaprogram 插件：init_plugins 逐名 codegen + 观察诊断三汇立规）——后续票。
- 第三方宿主（DLL/进程外，§11.7）、linkme 式链接期聚合（§11.1）、未来特性（glob members/exclude/--workspace 聚合/版本继承，§11.8）。
- 阶段 2（005：build.jai metaprogram + modules 发布）与阶段 3（006）。
- 旧 juice 仓任何改动（零特判原则）。

## Further Notes

- **文档折回**：1c 收口后 spec.md 执行级订正折回（1a/1b 惯例）——spec §4.6「t2 jaix 前置归 1c」表述订正为后续票（002 切线 B 与 §4.6 的冲突以本票拍板为准）；§6.3 at 接线子集执行级订正；§8 如有偏差随票记录。
- **拆链参考（/to-tickets 用）**：transpile_plugin（接口 + runner + 行号保真门）→ transpile_front / transpile_cache 并列 → plugin 表面（Juice_Plugin + 静态注册 + 合并查重）→ 扫描 + codegen → lifecycle 骨架（枚举/钩子/ctx/排序/失败）→ build b5/b7 接线 → test t3/t5-t9/t11 接线 → fixture 收口（关闭本票）。文件面互不重叠处可并列（015/016 并列先例）。
- **注册文件命名/落点** = 拆链票定（约束：target/ 下、不进 bootstrap 闭包、不入库、会话产物）。
- 238 存量测试是 1c 的基线（019 终态双路径计数），1c 每票递增。
- 编号续号面：1b 的 `juice_test_N` 已由 EXPAND 前的手写 `@test` 编号承担（017 偏差），1c 接线后 EXPAND 生成的 `juice_test_N` 与手写 `@test` 经同一 note 发现统一（§7.1 单一发现源）。

---

- [x] 主会话与用户拍板：三接缝 + 完成定义 + 范围边界（骨架 vs 全链路切线）+ 关键执行决策（2026-10-20 四条切线全按推荐选项拍板）
- [x] 拆 tracer bullet 实现链（/to-tickets，2026-10-20：020-029）
- [x] 链全关后本票写 `## Resolution` + status: closed（map Decisions so far 追加一行归主会话）

## Resolution

**收口结论（2026-10-20，票 029 落笔）**：US 32 条全兑现、决定 1-22 全部直落（四条范围切线照拍板落实；spike 修正见偏差指认：决定 8 内置注册表构造器形状、决定 10 codegen 绑定与调用分离、决定 17 派发粒度阶段级、决定 19 缓存键版本分量独立常量）；三接缝全绿（旧 juice 不变式 debug+release 4/4，Found 409）；实现链 020-029 全 closed。**1c 闭环 → 下一步 = 阶段 2（005：build.jai metaprogram + modules 发布）。**

### US 32 条兑现映射

| # | US | 落点 | 兑现证据 |
| --- | --- | --- | --- |
| 1 | get_juice_plugin + @juice_plugin 尾注免中央注册发现 | 025 | is_juice_plugin_anchor 词法锚点矩阵 + scan_plugin_package + plugin-fixture E2E（扫描零中央注册） |
| 2 | Juice_Plugin 全字段（id/version/transpile/hooks/options_schema） | 024 | src/plugin.jai 全字段 + 矩阵测试 |
| 3 | 派生结构体类型化 options 编译期检查 | 024 | plugin_tests「derived struct's typed options」+ 双 fixture 派生结构体真编译 |
| 4 | transpile 贡献声明模式适用性（strip/expand） | 020 | plugin_mode_applies 模式门控 + transpile_plugin_tests「mode applicability gates」 |
| 5 | 成对探测钩子（has_anchor/load_edges） | 020 + 022 + 026 | 探测聚合可空跳过 + load_edges 喂闭包 DFS + pipeline_has_anchors 闭包视图决策（test-blocks E2E） |
| 6 | claim 覆盖恰好消费的 token、未消费继续派发 | 020 | runner 区域交互契约 + transpile_plugin_tests（共享 token 声明序/头进入体/整块消费） |
| 7 | 行号保真门响亮失败 | 020 | enforce_line_fidelity 矩阵 ×2（不等行/非 token 界）+ **029 坏插件包全链 E2E（真 jai 编译 + 响亮拒绝实证）** |
| 8 | 跨文件管线状态（plugin_state 槽） | 020 | Transpile_Context.plugin_state + transpile_plugin_tests「cross-file state continues」 |
| 9 | 重复 id/版本冲突/挂点冲突/claim 冲突合并期全诊断拒绝 | 024 | merge_plugins 全诊断累积 + ok=false + plugin_tests 矩阵 + **029 坏插件包 E2E（重复 id 合并响亮拒绝）** |
| 10 | id+version+序进管线描述喂缓存键 | 026 | transpile_view_key 管线描述分量 + transpile_cache_tests |
| 11 | 内置 test 块插件 EXPAND → juice_test_N + @test | 023 + 028 | test_block_plugin（两模式重写 + @test 零宽插入）+ t3 接线 + **otter 根自跑（juice_test_401-409 可见）** |
| 12 | 内置 load 插件（EXPAND 占位/STRIP 改写/load_edges） | 022 | load 插件 + transpile_tools_tests 矩阵 |
| 13 | 全局编号跨文件续号基 1 | 023 + 028 | ctx.next_test_number 推进契约 + t3 跨文件续号（test_transpile_tests） |
| 14 | 手写 @test 与 test 块统一单一发现源 | 028 | EXPAND 产物裸 @test 经同一 note 枚举（US 直接后果偏差 11：手写名可撞 = 编译期查重） |
| 15 | build 依赖剥离闭包落 target/transpile/deps/ + shim 改写 | 027 | prepare_dependency_strip_views + build-with-tests E2E（剥离成功 + artifact 运行） |
| 16 | 入口选择：test-free 直编 / 含 test 闭包全有全无剥离 | 027 | build_plan_entry + closure_has_tests + build-with-tests E2E |
| 17 | 内容寻址视图缓存命中跳过 | 026 + 028 | transpile_cache 键/路径四助手 + t5/t8 命中跳过（视图纯契约 E2E） |
| 18 | 依赖测试不发现不执行 | 028 | t11 依赖剥离 + test-dep-root/test-dep-lib E2E（剥净 + 零发现零执行 + shim 改写） |
| 19 | Testing 模块编译视图特例 | 026 + 028 | testing_module_strip_view_dir + t9 全族 + in-package 模块自测 E2E（编译视图 + 白名单） |
| 20 | path_mapping 视图行 → 原文行 | 028 | 映射对嵌入 + test-blocks-fail E2E（src/math.jai:L:C 原文坐标 + exit 1） |
| 21 | juice test 于 juice 仓自身经 EXPAND + note 发现通过 | 028 + 029 复核 | **完成定义①实跑**：otter exe 于根 test exit 0、239 passed 0 failed |
| 22 | 内置插件静态注册表 + 显式 #load 列表 | 024 | 内置静态注册表（构造器函数 + 纪律注释）+ 闭包可审计 |
| 23 | 空注册表 = 缺省管线单一落点 | 020/022/023/024 | resolve_pipeline + merge_plugins 空注册表分支（视图与键恒同管线） |
| 24 | 确定性 DFS 词法扫描 + @juice_plugin 词法锚点 | 025 | scan_plugin_package（015 骨架复用）+ is_juice_plugin_anchor（防误报矩阵） |
| 25 | 注册文件逐名 codegen + 钩子装配段 | 025 | generate_plugin_registration 两段逐字节形状测试 ×2 + 双 fixture E2E |
| 26 | Lifecycle_Stage 封闭枚举只增不改 | 021 | 九阶段声明序 = 阶段序 + spec §6.1 版本化注释 |
| 27 | 确定性钩子序（阶段序/声明序/before-after 正序） | 021 + 027/028 | merge_hook_tables 按序拼接 + **派发矩阵全序钉**（两注册 8 钩子 before 正序跨注册 → at → after → 下一阶段） |
| 28 | 钩子失败 → 阶段失败 → 命令失败 → 退出码 | 021 + 027/028 | fail-fast + HANDLER_FAILED + 派发矩阵（before/at/after 失败中止 + ERROR 败 WARNING 过） |
| 29 | 显式 ctx 通道无闭包 | 021 + 027/028 | *void 槽族 + 注释映射 + 首生产消费者铸型 + fixture 钩子经诊断槽 |
| 30 | core 阶段 at 派发接线（TRANSPILE/COMPILE × build/test） | 027 + 028 | 四挂载点钩子表派发（决定 17 子集）+ 派发矩阵 + 有/无 at 双形态 E2E |
| 31 | 合成 fixture 插件包全链 E2E | 025 + 029 | 良构包（扫描→codegen→合并→真编译加载→双钩子触发）+ **坏包双面（重复 id / 行号保真违规 → 响亮拒绝）** |
| 32 | 旧 juice 零特判不变式 | 全链 + 029 复核 | debug+release 各 build/test 于 otter 根 4/4 全绿（2026-10-20，Found 409） |

### 决定 1-22 直落对照

| # | 决定 | 直落 | 偏差指认 |
| --- | --- | --- | --- |
| 1 | 范围切线四条（PRESTEP defer/at 子集/合成 fixture/lint defer） | 021（PRESTEP 枚举保留）+ 011 现状不动（b6/t2 恒等占位）+ 027/028（at 子集）+ 025/029（fixture） | 全照拍板；jaix_front 移植/真实成员包/lint 全留后续票（Out of Scope 不动） |
| 2 | 1c = 转译层全量 + 插件面 + lifecycle 骨架 | 020-028 全链 | 无 |
| 3 | Juice_Plugin 结构全字段 | 024 src/plugin.jai | 无（字段逐名直落） |
| 4 | 获取契约（get_juice_plugin + 尾注 + as_plugin 上转） | 024 + 025 | 无（025 偏差 5：插件值运行期构造——`::` 常量字面量不能承载 [..] 数组字段，jaix get_plugin 同款 New + array_add） |
| 5 | Transpile_Plugin 接口全字段 | 020 | 无 |
| 6 | 两内置插件 + 空注册表 = 缺省管线 | 022（load）+ 023（test 块）+ 024（空注册表分支） | 023 偏差 1：缺省管线期望 020→022→023 三连翻转（链票惯例，终态 = load + test 块声明序） |
| 7 | runner 硬约束（声明序/claim/模式门控/行号保真门） | 020 | 020 偏差 2：Transpile_Context 落位 transpile_plugin.jai（旧 juice 在 transpile.jai） |
| 8 | 内置注册 = 静态 | 024 | **024 偏差 5 形状成形**：内置注册表 = 构造器函数 + New 堆存储（transpile 指针须稳定存储；模块级静态数组与 [..] 字段字面量互斥）——「静态」= 固定成员显式列表，纪律注释落文件头 |
| 9 | 扫描发现（候选 (c) 机制链） | 025 | 025 偏差 7：扫描排除集插件包自身 tests/ 不排除（无锚无害）；扫描 = 库面 + fixture 验证，命令编排面留后续票（决定字面） |
| 10 | 注册文件 codegen 形状 | 025 | **025 偏差 1 spike 修正字面形**：顶层调用 Jai 判死（A E1/E2/E4 同款实证）→ `JUICE_PLUGIN_<i> :: #import "<模块名>";` 绑定与显式调用分离（装配过程内执行）；偏差 2：钩子装配段 = 每插件一条显式条目（逐钩子 .{} 生成期不可知）；偏差 3：类型同一性 → juice_core 按名 import 种子（#load 双作用域 = 不兼容重复类型） |
| 11 | 合并查重全诊断 + ok=false 拒绝 | 024 | 024 偏差 1：合并语义钉定（at 独占/before-after 合法堆叠/transpile 重名拒绝 = jaix 关键字 claim 等价面）；偏差 2：合并诊断无 level 字段（line/column 恒 0，无源锚点）；029 坏包 E2E 全链实证 |
| 12 | Lifecycle_Stage 封闭枚举 | 021 | 021 偏差 6：Hook_Position 小写成员（spec 决定 13 字面） |
| 13 | Lifecycle_Hook 形状 + ctx | 021 | 021 偏差 1：可观测状态槽族 = *void + 注释映射（异构存储理由，027/028 首生产消费者铸型；PRESTEP 槽随 jaix_front 票）；偏差 3：register_hooks 拷贝钩子元素；偏差 4：三汇 = 级别三通道（compiler_report 形状，§8.2 锚） |
| 14 | 确定性排序 | 021 | 偏差 2：槽对齐 = 每注册一槽（Hook_Registration 两级形状——多钩子插件共享状态不碎） |
| 15 | 失败语义（false/ERROR = 中止） | 021 + 027/028 派发矩阵 | 021 偏差 5：fail-fast（「中止」直读） |
| 16 | 跨阶段状态 = 槽协议（构造期恒 null） | 021 + 027/028 | 无（宿主槽恒 null 钉死在派发矩阵） |
| 17 | at 接线代表性子集（四挂载点） | 027（build TRANSPILE/COMPILE）+ 028（test TRANSPILE/COMPILE） | **027/028 偏差 1 派发粒度 = 阶段级**（§6.3 执行级订正折回）：TRANSPILE at 替换整个 b5+b7 / t3+t5-t9+t11 前端、COMPILE at 替换整个 b8 / t12；at 替换身份进管线描述 = 文档化语义（换实现 = 换视图键）；其余 10 seam 留 #type 形参（后续机械票） |
| 18 | 转译视图面（b5/b7/t3/t5-t9/t11/path_mapping） | 026 + 027 + 028 全落地 | 026 偏差 3：PLAIN 布局 + testing_module_strip_view_dir 随库面全量落地（阶段 2 bootstrap/US 19 消费面）；028 偏差 7：双面并存结构代价（otter finish 门只守 prefixed 面、旧 juice 对称反向——互补覆盖 + 白名单 grep 兜底） |
| 19 | 缓存键契约 | 026 | **026 偏差 1**：缓存键版本分量 = VIEW_CONTRACT_VERSION 独立常量（"otter-0.1.0"）——JUICE_VERSION 名已被 013 产品版本契约占用；"otter-" 前缀 = 与旧 juice 键空间不共享；偏差 2：管线描述 = 有序 name+version 序列 |
| 20 | 完成定义①-④ | 029 复核全绿 | 见下「完成定义复核」 |
| 21 | 实现纪律（语义等价重写/test-free/绝对路径/Windows-first） | 全链 | 零违反；transpile 族五模块 test-free（bootstrap #load 集纪律）；测试助手 prefixed（022/023/026） |
| 22 | 四硬约束全程 | 全链 | 零违反：模块名 "Juice" load-bearing（007 命名空间绑定惯例延续）；Package 零新字段；otter/package.jai 无 TRANSPILE_PLUGIN 声明（缺省管线，id 集天然安全）；lint 不涉 |

### 链偏差汇总（020-028，62 项 + 029 补缺面）

| 票 | 偏差数 | 一览 |
| --- | --- | --- |
| 020 | 5 | src/transpile.jai = 最小支撑面（票面未列，022/023 接替点注释）；Transpile_Context 落位 transpile_plugin.jai；resolve_pipeline 恒等（022/023 落地后翻转期望）；swallow 假插件匹配闭括号 = 测试局部 helper；synth_load_edges 录原始字面量；main.jai 零改动 |
| 021 | 7 | 状态槽族 = *void + 注释映射（PRESTEP 槽随 jaix_front 票）；槽对齐 = 每注册一槽；register_hooks 拷贝钩子元素；三汇 = 级别三通道；fail-fast；Hook_Position 小写成员；Jai 事实钉 ×3（前缀 * 恒取地址/枚举 cast 全限定/切片不进 [..] 字段） |
| 022 | 5 | escape_jai_string 旧 juice `%%` 潜伏缺陷不复制（`\x%1%2` 修正）；metaprogram 本地对 prefixed 改名（027 退役兑现）；020「空注册表=空管线」期望翻转；strip_block_edit 测试闭括号匹配局部化；缺省管线只含 load（023 追加 test 块）；main.jai 零改动 |
| 023 | 5 | 020 缺省管线期望再翻转（023 形状）；测试助手 prefixed（tblock_*）；022 测试局部 find_close 保留不动；编号续号面只落 ctx.next_test_number 消费（调用方推进契约，027/028 t3 接线面）；main.jai 零改动 |
| 024 | 7 | 合并语义钉定（at 独占/before-after 合法堆叠/transpile 重名拒绝）；合并诊断无 level 字段（line/column 恒 0）；stage_name 落 lifecycle.jai；内置注册表 = 构造器函数 + New 堆存储；JUICE_PLUGIN_NOTE 常量单一来源；测试助手 plug_ 前缀；Jai 事实钉 ×2（cast 括号序/真前向引用跨 #load 合法） |
| 025 | 9 | 顶层调用非法 → 绑定与调用分离（spike 实证 + A E1/E2/E4）；钩子装配段 = 每插件一条显式条目；类型同一性 → juice_core 按名 import 种子（#load 双作用域类型不统一 spike）；模块名 = 路径作用域；插件值运行期构造；JUICE_HOOK 装配序依赖（生成文件注释文档化）；扫描排除集 tests/ 不排除；Jai 事实钉 ×3；main.jai 零改动 |
| 026 | 5 | VIEW_CONTRACT_VERSION 独立常量（"otter-" 前缀键空间隔离）；管线描述 = 有序 name+version 序列；PLAIN 布局 + testing_module_strip_view_dir 全量落地；测试助手 prefixed（tfront_*/tcache）；前端测试 = 旧 juice 8 块语义 + 新面 5 块；main.jai 零改动 |
| 027 | 8 | at 派发粒度 = 阶段级（§6.3 折回）；at 替换身份进管线描述文档化；build_compile_loop 保留内部 compile 参数（非 lifecycle 挂载，三参适配器）；resolve_transpile_pipeline 落新 transpile_config.jai；main.jai 闭包新增 module.jai（内置 id 单一来源）；E2E driver 闭包补 transpile 族四模块；LNK1104 普通 seam + hand-off/零 plan 先于派发零钩子；expect 宏裸 return 不能用于返回值函数 |
| 028 | 11 | 显示名 = 过程名（命名块/匿名 path:line 显示名恢复留后续票）；"Found N" 不产（018 延续）；零测试不短路（next_number==1 在手写 @test 下不等价）；产品落 target/transpile（1b target/test 退役）；at 粒度阶段级（027 偏差 1 同款）；face 跳过 = face_is_discovered 纯函数；双面并存结构代价（互补覆盖 + 白名单 grep 兜底）；ensure_bootstrap_modules 种子扩展 Testing.jai；t9 白名单 spike 钉（module 作用域 @test 进 TYPECHECKED 流 + #scope_export 引用实证）；Jai 事实钉（Type.[..] 字面量落栈帧悬垂）；手写 juice_test_N 与 EXPAND 生成名可撞（US 14 直接后果） |
| 029 | — | **补缺面**：坏插件包全链 E2E 补缺（025 只覆盖良构包全链）——新 fixture plugin-fixture-bad 坏双面（重复 id → merge 响亮拒绝 ok=false + 行号保真违规 → transpile 响亮拒绝编辑丢弃）+ run_plugin_scan_child/driver 构造器 marker 参数化 + merge/transpile 诊断逐条打印（好包 E2E 输出增量行无害，pin 子串不动）；盘点结论 = build-with-tests/test-blocks 家族/test-dep 双包（027/028）与良构插件包（025）已就位，无重复建设 |

**归属**：全部偏差为有意设计决定（语义等价重写 + spike 实证修正 + bootstrap 窗口绕行 + Jai 编译期约束成形），无遗留缺陷——旧 juice 仓改动面不涉（零特判参照面）。

### 完成定义复核

- **① otter exe test 于根自跑套件全绿**（2026-10-20 实跑）：`otter/target/juice.exe test` 于 otter 根 exit 0、239 passed 0 failed——test 块 → EXPAND → `juice_test_N` + `@test` → note 发现统一（018 切线 A 预期状态解除；juice_test_401-409 可见）；失败断言指原文 file:line（双面并存 028 偏差 7：prefixed 面经映射、bare 面行号保真 + 视图路径，白名单 grep 兜底——expect failed 白名单 4 行 module_tests :178/:183/:207/:212 双路径逐行同状）。
- **② otter exe build 于根真剥离视图编译**（2026-10-20 实跑）：`otter/target/juice.exe build` 于 otter 根 exit 0——LNK1104 hand-off 全通（running 检测 → 副本接管 → 编译完成 → exe 更新）；b5/b7 真剥离视图（027 首验 build-with-tests：剥离成功 + artifact 运行 "hello from build-with-tests: 2 + 3 = 5"）。
- **③ 三接缝全绿**：接缝 1 = 旧 juice 不变式 debug+release 4/4（2026-10-20 复核，各先清 otter/target/transpile：debug+release 各 juice build/juice test 于 otter 根 exit 0，Found 409）；接缝 2 = 姊妹测试 409 tests 双路径全绿（408 基线 + 029 坏插件包 E2E 1 块；1c 递增轨迹 250→263→286→309→326→335→353→376→408→409；src 实现模块全 test-free）；接缝 3 = E2E 真子进程全绿（build-with-tests + test-blocks 家族 + test-dep 双包 + plugin-fixture 良构 + plugin-fixture-bad 坏双面；真 jai 子进程 + 真 otter exe 自举面）。
- **④ 合成 fixture 插件包全链 E2E**：良构（025）：扫描 → 注册文件 → juice_core 种子 → driver 真编译 → merge_plugins 合并执行（transpile 面改写 + 双钩子触发 + hook-entries 序钉死）；坏双面（029）：重复 id → 合并响亮拒绝（ok=false + "duplicate plugin registration: bad-shared"）+ 行号保真违规 → 转译响亮拒绝（编辑丢弃 + "编辑违反行号保真：等行数展开失败" + 视图保持原文）——扫描同形、拒绝分层。
- **出范围面**：jaix PRESTEP 全链（jaix_front 移植/b6+t2 接线）→ 后续票（PRESTEP 枚举保留）；at 接线其余 10 seam → 后续机械票（机制已立）；真实第三方成员插件包（packages/ 布局 + 插件声明面）→ 后续票；lint（§8.2）→ 后续票；阶段 2（005）与阶段 3（006）。**下一步 = 阶段 2（005：build.jai metaprogram + modules 发布）。**

### spec.md 执行级订正折回

- **§4.6**：test 序注的 2026-10-19 订正更新——t2 jaix 前置归后续票（004 决定 1 拍板为准；PRESTEP 枚举保留、b6/t2 恒等占位不动）；t3 EXPAND 转译/t5-t9 视图面/t11 依赖剥离已由 1c 接管落地（2026-10-20）。
- **§6.3**：at 接线子集执行级订正——core 四挂载点（build TRANSPILE/COMPILE + test TRANSPILE/COMPILE）已接钩子表派发；派发粒度 = 阶段级；其余 10 seam 留 #type 形参（后续机械接线票）。
- **§7.2**：2026-10-19 订正更新——driver/metaprogram 产品落 target/transpile/（1c 转译层落地后从 1b 的 target/test 迁移）；Testing 面 = 编译视图面（t9：in-package EXPAND + 自测段截取 + 白名单 / global STRIP 视图 / face_is_discovered 跳过）。
- **§7.3**：2026-10-20 追加——test 块与手写 @test 经同一 note 枚举统一（单一发现源）；显示名 = 过程名（命名块/匿名 path:line 显示名恢复留后续票）；"Found N tests" 不产；零测试判定 = 收集期零条目（旧 juice next_number==1 判定不沿用）。
