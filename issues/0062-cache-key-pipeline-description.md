---
title: 缓存键管线描述 + JUICE_VERSION 泛化
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [0061]
---

> 父 spec：`issues/0060-spec-transpile-pipeline-pluginization.md`（决定 5 + Testing Decisions 接缝 3 缓存键面）。研究 B 3.2.3。

# 0062: 缓存键管线描述 + JUICE_VERSION 泛化

**What to build:** 视图缓存键获得管线描述分量（有序插件 name+version 序列——jaix 管线描述同款形状）——插件版本 bump 即键变、管线变化精准失效视图；JUICE_VERSION 语义泛化为「管线输出契约版本」（输出契约变化 = 管线描述变化）；load 重写表嵌入与 Merkle 链性质不变。缓存键契约测试演进：成分敏感性面扩展（name 变 / version 变 / 序变逐成分敏感）+ 缺省管线键形状锁定；Merkle 链既有测试保持绿。视图文本零变化（缓存落点变化属预期——golden 30/30 零重定）。

**Blocked by:** 0061（管线描述类型与缺省管线组装先落地）

**Status:** ready-for-agent

- [ ] transpile_view_key 增管线描述分量（有序 name+version 序列）
- [ ] JUICE_VERSION 语义泛化（输出契约变化 = 管线描述变化）
- [ ] Merkle 链性质不变（load 重写表嵌入照旧——既有 Merkle 链测试保持绿）
- [ ] 缓存键测试演进：name 变 → 键变 / version 变 → 键变 / 序变 → 键变 / 缺省管线键形状锁定
- [ ] 三路径全绿 + golden 30/30 零重定（视图文本零变化）
