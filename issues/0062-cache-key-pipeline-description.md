---
title: 缓存键管线描述 + JUICE_VERSION 泛化
status: closed
labels: [ready-for-agent]
assignee: maojiaxing
blocked-by: [0061]
---

> 父 spec：`issues/0060-spec-transpile-pipeline-pluginization.md`（决定 5 + Testing Decisions 接缝 3 缓存键面）。研究 B 3.2.3。

# 0062: 缓存键管线描述 + JUICE_VERSION 泛化

**What to build:** 视图缓存键获得管线描述分量（有序插件 name+version 序列——jaix 管线描述同款形状）——插件版本 bump 即键变、管线变化精准失效视图；JUICE_VERSION 语义泛化为「管线输出契约版本」（输出契约变化 = 管线描述变化）；load 重写表嵌入与 Merkle 链性质不变。缓存键契约测试演进：成分敏感性面扩展（name 变 / version 变 / 序变逐成分敏感）+ 缺省管线键形状锁定；Merkle 链既有测试保持绿。视图文本零变化（缓存落点变化属预期——golden 30/30 零重定）。

**Blocked by:** 0061（管线描述类型与缺省管线组装先落地）

**Status:** ready-for-agent

- [x] transpile_view_key 增管线描述分量（有序 name+version 序列）
- [x] JUICE_VERSION 语义泛化（输出契约变化 = 管线描述变化）
- [x] Merkle 链性质不变（load 重写表嵌入照旧——既有 Merkle 链测试保持绿）
- [x] 缓存键测试演进：name 变 → 键变 / version 变 → 键变 / 序变 → 键变 / 缺省管线键形状锁定
- [x] 三路径全绿 + golden 30/30 零重定（视图文本零变化）

## Resolution

### 实现摘要

- `transpile_view_key` 增第六形参 `pipeline: [] Transpile_Plugin = Transpile_Plugin.[]`（src/transpile_cache.jai）：序列化管线描述分量——插件数 + 有序 name\0version 对（声明序 = 管线序，jaix Pipeline_Plugin 同款形状）——插在版本之后、load 重写表之前。省略或空管线 = 缺省管线（resolve_pipeline 解析）。load 重写表嵌入与 Merkle 链性质不变（既有 Merkle 链测试一字不改、原样通过）
- **JUICE_VERSION 语义泛化**（src/transpile_cache.jai:25-33）：常量改为「管线输出契约版本」——逐插件输出契约经管线描述分量表达（插件版本 bump 即键变、精准失效），常量只覆盖 runner 级契约（视图布局、driver 格式、键序列化形状自身）；值保持 "0.1.0"
- **「空注册表 = 缺省管线」约定单一落点**：transpile_plugin.jai 新增 `resolve_pipeline`（0061 runner 内联解析的提取），`transpile_source` 与 `transpile_view_key` 同走此门——视图与其键恒反映同一管线（键从不与产视图的管线失配）
- **生产键位点显式传管线**：`transpile_build_file`（transpile_front.jai）与 `transpile_test_file`（commands/test.jai）改传 `ctx.plugins`——今日空数组 = 缺省（零行为变化），0063 配置面落地后键自动跟踪配置管线，无需再改位点
- **测试演进**：
  - tests/transpile_plugin_tests.jai（姊妹文件，spec 接缝 3 落点）新增 2 块：「管线描述逐成分敏感」（synth 管线基线：name 变 → 键变 / version 变 → 键变 / 序变 → 键变，同输入同管线键不变）+「省略管线 = 缺省管线」（省略 / 空数组 / default_transpile_pipeline() 三键同值；反转缺省序必不同——缺省键形状锁定）
  - tests/transpile_tests.jai 缓存键契约测试按票演化（键增分量）：成分清单注释补管线描述、增「异管线 → 键变」与「省略版本/管线 = 缺省值」两断言；Merkle 链测试块逐字未改

### 验证结果

- 三路径全绿（先清 target/transpile）：`jai build.jai`（debug）+ `jai build.jai - release` 构建成功（`-` 分隔符传参）；`./target/juice.exe test` debug 与 release 产物各验一遍 = **exit 0** + latch「Testing module register stays clean between tests」**5/0** + **30 GOLDEN PASS** 零 UPDATE + **224 passed, 0 failed**（222 + 新增 2 块）；`juice build` 自构建绿（exe 复制为 target/juice-build.exe 运行，毕后删除——LNK1104 规避）
- 视图文本零变化：9/9 .view.jai 金样逐字节未动；first.jai 7/7 与 negative 7/7 零重定（首次运行即通过，无 UPDATE 运行介入）；工作树 jaix 系 E2E（pre-step build/test、monorepo）原样通过

### 偏差清单

1. **7 个 golden driver.jai 重定（一次 UPDATE，仅哈希列）**：driver.jai 金样内嵌键哈希（`<abs>/target/transpile/<key>/...` 落点路径），键增管线描述分量后落点必然变化——票面「golden 30/30 零重定」对 driver.jai 不可达，且正是票面「缓存落点变化属预期」的金样显现。以 JUICE_UPDATE_GOLDEN 重定后逐字节 diff 证明：7 文件仅 16 hex 键值变化（期望/实际字节数逐文件相等），无任何其他文本变化。视图 9/9 + first.jai 7/7 + negative 7/7 = 23/30 零重定；driver.jai 7/7 属预期落点变化
2. `resolve_pipeline` 为票面未列的极小提取（runner 内联解析搬出、行为逐字节不变）——缓存键与 runner 共享约定的必要单一落点，0061 既有测试原样通过
3. 测试计数 222 → 224（新增 2 块姊妹测试，spec 接缝 3 预期内）
4. 生产键位点（transpile_build_file / transpile_test_file）改传 ctx.plugins——今日行为零变化，为 0063 配置面预接（否则配置管线落地后键位点需回头改，且存在键与管线失配的静默缓存 bug 风险）
