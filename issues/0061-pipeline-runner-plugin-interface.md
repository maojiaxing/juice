---
title: 管线 runner + 插件接口 + 两内置插件 + 探测聚合
status: closed
labels: [ready-for-agent]
assignee: maojiaxing
blocked-by: []
---

> 父 spec：`issues/0060-spec-transpile-pipeline-pluginization.md`（决定 2/3/4/7/8 + Testing Decisions 接缝 1/2/3）。研究 B 结论 4 的最小改造主体。

# 0061: 管线 runner + 插件接口 + 两内置插件 + 探测聚合

**What to build:** juice 自身 Transpile 机制跑在注册表驱动的管线上——扫描循环升级为管线 runner，test block 与 `#load` 处理成为前两个内置插件（缺省静态注册表、声明序 = 派发序）；插件接口 = {name, version, 模式适用性声明（STRIP/EXPAND）, 探测钩子成对（has_anchor / 可选 load_edges）, 转译钩子（扫描位点回调 → Edit/清单条目/诊断）, 跨文件状态经 Transpile_Context 扩展字段}；区域交互契约显式化（EXPAND 下 test 体内 `#load` 仍剥离、STRIP 下随占位消失）；闭包探测改为管线聚合（closure_has_tests / probe_package_closure 走插件钩子、test-free 闭包零转译短路不变）；ADR 0005 硬约束由 runner 强制（无法等行数展开的输入形态转译期拒绝——多行 test 头先例语义不变）。新共享模块 test-free（bootstrap `#load` 目标）、测试驻 tests/ 姊妹文件。**零可观测行为变化**：三路径全绿 + 既有 transpile_tests / transpile_front_tests / metaprogram_tests 一字不改 + golden 30/30 零重定。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] 插件接口落地（{name, version, 模式适用性, 探测钩子成对, 转译钩子}）；新 test-free 模块（bootstrap `#load` 目标）；测试驻 tests/ 姊妹文件（0053 规则）
- [x] runner = transpile_source 扫描循环保留；`#load` 分支与 test 锚点分支改为插件派发；交互契约显式化（EXPAND 下 test 体内 `#load` 仍剥离 / STRIP 下随占位消失）
- [x] 探测聚合：closure_has_tests / probe_package_closure 走管线；test-free 闭包零转译短路不变
- [x] ADR 0005 强制：等行数展开失败 → 诊断拒绝（多行 test 头语义不变）
- [x] 姊妹测试起步：合成第三插件——派发三通道（Edit/清单/诊断）/ 跨文件状态续走 / 模式适用性 / 探测聚合 / 违反拒绝
- [x] 三路径全绿（bootstrap debug/release + juice test + 自构建）；transpile_tests / transpile_front_tests / metaprogram_tests 一字不改；golden 30/30 零重定

## Resolution

### 实现摘要

- 新 test-free 共享模块 `src/transpile_plugin.jai`（bootstrap `#load` 目标——build.jai 与 main.jai 均于 transpile.jai 之后装载）：
  - **插件接口**：`Transpile_Plugin {name, version, modes, has_anchor, load_edges, transpile}`——身份进管线描述（缓存键分量归 0062）；`Transpile_Plugin_Modes {strip, expand}` 模式适用性声明（runner 派发门控，探测钩子模式无关）；`has_anchor(source, path)`（必选，喂闭包视图判定）与 `load_edges(source, path)`（可选 null，喂闭包 DFS）成对；`transpile(scan, ctx, state)` 转译钩子 = 扫描位点回调。`Transpile_Scan` = runner 派发状态（游标 + 花括号深度 + 语句位置簿记 + 三汇 Edit/清单/诊断）；声明者拥有其区域的游标与簿记，未声明 token 走 runner 缺省追踪
  - **runner = `transpile_source`**（自 transpile.jai 迁入，签名不变）：扫描循环骨架（深度 + 语句位置 + 编辑收集）保留，`#load` 分支与 test 锚点分支改为向 `ctx.plugins` 注册插件按声明序派发；**空注册表 = 缺省管线**（`default_transpile_pipeline()` = [load, test-block]，旧硬编码分支序 #load 先）——既有调用方全部零改动。**区域交互契约在 runner 层显式化**（注释 + 测试锁定）：test 插件 EXPAND 声明替换头行后游标进体（depth+1）不消费体——runner 继续向其余插件派发，test 体内 `#load` 仍被剥离；STRIP 声明消费整块至闭括号——占位内 token 永不再派发，test 体内 `#load` 随占位消失
  - **两内置插件**：`load_plugin`（转译钩子 = 旧 #load 分支原语义含全部诊断；load_edges = 旧 source_load_targets；has_anchor = null——#load 不触发视图化）、`test_block_plugin`（转译钩子 = 旧 test 锚点分支原语义——多行头/嵌套/闭括号尾随诊断、"缺少闭合 }" 的 break 语义经 index = tokens.count 保留；has_anchor = 旧 source_has_test_block）。identity：name "load"/"test-block"、version "1.0.0"
  - **探测聚合**：`pipeline_has_anchors` / `pipeline_load_edges`；`probe_package_closure` 的 has_tests/loads、`testing_module_strip_view_dir`、`testing_module_view`、jaix mirror 排除集全部改走聚合；旧 `source_has_test_block` / `source_load_targets` 删除（closure_has_tests 消费聚合后的 has_tests 旗标，全有全无判定与零转译短路原样）
  - **ADR 0005 强制（runner 层）**：`enforce_line_fidelity` 应用前过滤——每条编辑须「1 行换 1 行」（`line_count_of` 等行数展开，多行 test 头拒绝的一般形式）且「以 token 为界」（start/end 各落在某 token 的起点或终点边界——`@test` 零宽插入坐落在闭括号 token 终点边界的先例）；违反编辑丢弃 + 诊断「编辑违反行号保真：等行数展开失败」/「编辑未以 token 为界」（`offset_location` 定位）。内置插件永不违反 → 零行为变化
  - **跨文件状态通道**：`Transpile_Context` 扩展字段 `plugins: [..] Transpile_Plugin` + `plugin_state: [..] *void`（与管线序对齐的槽位，插件自转类型，调用方持有存储、跨调用续走——next_test_number 续号同族通道）
- `src/transpile.jai` 缩为共享基础设施（类型/lexer/Edit/行号保真 helper/锚点机器），头注释改为分工表述；`tests/transpile_plugin_tests.jai`（0053 规则姊妹文件）起步 10 块：合成第三插件（synth：STRIP-only、语句位点 `synth_anchor` 锚点 + `#synth_load` 边钩子）证明派发三通道（Edit/清单/诊断）、跨文件计数器续走（state 槽位跨两次调用 1,2 → 3）、模式适用性门控（EXPAND 永不派发、STRIP 声明）、区域契约（剥离体内不派发后续插件）、探测聚合（has_anchor/load_edges 合成 + 缺省）；两个违反夹具插件（非等行展开 / 非 token 界）证明 runner 拒绝 + 视图逐字保留；缺省注册表 identity/序与空注册表 = 缺省管线锁定
- 既有 transpile_tests / transpile_front_tests / metaprogram_tests **逐字节未改**；golden/negative/run 矩阵零重定（无 JUICE_UPDATE_GOLDEN 运行）

### 验证结果

- 三路径全绿（先清 target/transpile）：`jai build.jai`（debug）+ `jai build.jai - release` 构建成功（`-` 分隔符传参）；`./target/juice.exe test` debug 与 release 产物各验一遍 = **exit 0** + latch「Testing module register stays clean between tests」**5/0** + **30 GOLDEN PASS** 零重定 + **222 passed, 0 failed**（212 + 新增 10 块）；`juice build` 自构建绿（exe 复制为 target/juice-build.exe 运行，毕后删除——LNK1104 规避）
- 零行为变化证据：既有三测试文件逐字节未改、原样通过；golden 零 UPDATE；工作树 jaix 系 E2E（pre-step build/test、monorepo）原样通过

### 偏差清单

1. 工作树机制：`git worktree add <path> juice-transpile-pipeline-pluginization` 因分支已在主仓库检出而失败——以 `--detach` 建树后树内 `git switch -c implement/0061-pipeline-runner`（结果等价）。本工作树位于 jai/juice-0061-implement（父目录 = jai/），`../jaix` / `../jaix-cli` 自然解析到真实仓库——0055/0057/0059 的 junction 挂载陷阱未触发，无需挂接（jaix E2E 实测全绿）
2. 「编辑以 token 为界」的具体规则：首版实现要求编辑起点 = 某 token 起点且终点 = 某 token 终点——误拒内置 `@test` 零宽插入（坐落在闭括号 token 的终点边界）；实施中修正为「起点与终点各落在某 token 的起点或终点边界」（ADR 0005 的正确读法），由套件（dependency.jai 内联测试）当场暴露、提交前已修
3. 测试计数 212 → 222（新增 10 块姊妹测试，spec 接缝 3 预期内）
4. 缓存键管线描述分量（spec 决定 5）与 Package 配置注册面（决定 6）归 0062-0064 票，本票不触碰 transpile_cache.jai；文档收口（新 ADR / CONTEXT.md / IMPLEMENTATION.md，spec 决定 11）同样留后续票，本票不动文档
