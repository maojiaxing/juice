---
title: 收口：ADR + 词汇 + 关闭 spec 0060
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: [0061, 0062, 0063]
---

> 父 spec：`issues/0060-spec-transpile-pipeline-pluginization.md`（决定 11 + Testing Decisions 四接缝 + 收口定义）。060/0059 同款收口票纪律（零产品代码改动——文档例外）。

# 0064: 收口：ADR + 词汇 + 关闭 spec 0060

**What to build:** 新 ADR（管线契约：ADR 0005「1 行换 1 行」硬约束 + 配置驱动注册形态——ADR 0004/0005/0007 家族续篇）+ CONTEXT.md 词条（转译管线 / 插件声明面；Transpile 词条同步）+ IMPLEMENTATION.md 模块表补行。四接缝全量复核（三路径 + 逐字节零重定 + 姊妹测试面 + 配置面矩阵）；spec 0060 收口关闭（票内 `## Resolution`——决定 1-11 直落与偏差清单 + `status: closed`）。

**Blocked by:** 0061（管线核心）+ 0062（缓存键面）+ 0063（配置面）——收口需四接缝全绿

**Status:** ready-for-agent

- [x] ADR 新篇（管线契约：硬约束 + 注册形态）+ CONTEXT.md 词条 + IMPLEMENTATION.md 模块表
- [x] 四接缝全量复核全绿：juice 三路径（bootstrap debug/release + test + 自构建）+ golden 30/30 零重定 + 姊妹测试面 + 配置面矩阵
- [x] spec 0060 票内 Resolution（决定 1-11 直落映射 + 链上偏差汇总）+ status: closed

## Resolution

**实现摘要：**

- `docs/adr/0008-transpile-pipeline-contract.md`（新 ADR——0004/0005/0007 家族续篇，管线契约）：注册表驱动管线（两内置插件 + runner 派发 + 区域交互契约显式化 + 空注册表 = 缺省管线）+ ADR 0005 硬约束由 runner 强制（「1 行换 1 行」+「编辑以 token 为界」，违反编辑诊断拒绝）+ 闭包探测聚合 + 缓存键管线描述（JUICE_VERSION 泛化为「管线输出契约版本」）+ Package 配置面注册（`TRANSPILE_PLUGIN` 协议记录 + 校验门 + 声明序 = 管线序 + 未声明 = 缺省）+ 进程内锚点级文本管线（不采用 jaix AST 模型）。Considered Options 录实现实拍板面：静态注册表 vs 配置驱动（静态保留为机制底座、Package 配置面叠加其上）、第三方宿主 defer（spec 决定 1）、jaix AST 模型否决（并存不替代）；Consequences 承接 0063 偏差（依赖/Testing 模块视图恒缺省、声明 version 不校验不进键、v1 选项集空）与 0062 偏差 1（driver.jai 金样哈希列随键变重定）。
- `docs/adr/0005-view-line-fidelity.md`：补修订行（2026-10-18，ADR 0008）——硬约束由机制承载（0004 修订行同款惯例——偏差 2）。
- `CONTEXT.md`：新增 **转译管线（transpile pipeline）** 与 **插件声明面（plugin declaration surface）** 两词条（Scan walk 词条风格——承载什么、消费者、_Avoid_）；**Transpile** 词条同步管线现实（test block 与 `#load` 处理为前两个内置插件、扫描循环为 runner + 指向新词条）。
- `IMPLEMENTATION.md`：模块表补 `src/transpile_plugin.jai` 与 `src/transpile_config.jai` 两行（按 main.jai 装载序插于 transpile_cache 行前）；transpile_cache 行补管线描述分量与 JUICE_VERSION 语义（票 0062——偏差 3）。
- `issues/0060-spec-transpile-pipeline-pluginization.md`：票内 `## Resolution`（决定 1-11 直落映射 + 三票偏差汇总）+ frontmatter `status: closed`（labels / assignee 不动）。
- 零产品代码改动（收口票纪律——060/0059 同款）：本票仅文档 + 票文件。

**验证结果（四接缝全量复核）：**

- 接缝 1（三路径不变式，先清 target/transpile）：`jai build.jai`（debug）+ `jai build.jai - release` 构建成功；`./target/juice.exe test` debug 与 release 产物各验一遍 = **exit 0** + latch「Testing module register stays clean between tests」**5/0** + **30 GOLDEN PASS**（无 JUICE_UPDATE_GOLDEN 运行）+ **242 passed, 0 failed**；`juice build` 自构建绿（exe 复制为 target/juice-build.exe 运行，毕后删除——LNK1104 规避）。
- 接缝 2（转译输出契约面）：transpile_front_tests / metaprogram_tests 逐字节未改、原样通过；transpile_tests 按 0062 缓存键契约测试演化（11 行——成分注释 + 异管线/缺省值断言）；golden/negative/run 矩阵零重定（唯一 UPDATE 运行在 0062——7/7 golden driver.jai 哈希列一次性重定，0062 偏差 1）。
- 接缝 3（插件接口姊妹测试）：tests/transpile_plugin_tests.jai 13 块全绿（0061 的 10 + 0062 的 2 + 0063 显式声明 1——合成第三插件：探测聚合 / 派发三通道 / 跨文件状态续走 / 模式适用性 / 缓存键敏感性 / ADR 0005 违反拒绝）。
- 接缝 4（Package 配置面）：manifest 内联 9 块 + transpile_config 内联 4 块 + 姊妹文件显式声明 1 块 + 组装接线 2 块 + E2E 2 块（pipeline-explicit / pipeline-unknown）全绿。
- 工作树位于 jai/juice-0064-implement（父目录 = jai/），`../jaix` / `../jaix-cli` 自然解析（0061 偏差 1 同款布局）——jaix 系 E2E（pre-step build/test、monorepo）原样通过，无 junction 挂载。

**偏差清单：**

1. **工作树机制**：`git worktree add --detach` 建树后树内 `git switch -c implement/0064-closeout`（PR 分支已在主仓库检出——0061 偏差 1 同款）。
2. **ADR 0005 补修订行（票面未列）**：runner 强制是 ADR 0005 决定 1 的机制化——家族文档互链为 0004 修订行既有惯例。
3. **IMPLEMENTATION.md transpile_cache 行同步（票面只列新模块两行）**：模块表职责列与管线现实（0062 键分量）同步的极小区间。
