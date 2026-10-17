---
title: 收口：ADR + 词汇 + 关闭 spec 0060
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [0061, 0062, 0063]
---

> 父 spec：`issues/0060-spec-transpile-pipeline-pluginization.md`（决定 11 + Testing Decisions 四接缝 + 收口定义）。060/0059 同款收口票纪律（零产品代码改动——文档例外）。

# 0064: 收口：ADR + 词汇 + 关闭 spec 0060

**What to build:** 新 ADR（管线契约：ADR 0005「1 行换 1 行」硬约束 + 配置驱动注册形态——ADR 0004/0005/0007 家族续篇）+ CONTEXT.md 词条（转译管线 / 插件声明面；Transpile 词条同步）+ IMPLEMENTATION.md 模块表补行。四接缝全量复核（三路径 + 逐字节零重定 + 姊妹测试面 + 配置面矩阵）；spec 0060 收口关闭（票内 `## Resolution`——决定 1-11 直落与偏差清单 + `status: closed`）。

**Blocked by:** 0061（管线核心）+ 0062（缓存键面）+ 0063（配置面）——收口需四接缝全绿

**Status:** ready-for-agent

- [ ] ADR 新篇（管线契约：硬约束 + 注册形态）+ CONTEXT.md 词条 + IMPLEMENTATION.md 模块表
- [ ] 四接缝全量复核全绿：juice 三路径（bootstrap debug/release + test + 自构建）+ golden 30/30 零重定 + 姊妹测试面 + 配置面矩阵
- [ ] spec 0060 票内 Resolution（决定 1-11 直落映射 + 链上偏差汇总）+ status: closed
