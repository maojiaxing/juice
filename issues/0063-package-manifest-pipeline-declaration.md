---
title: Package 配置面：TRANSPILE_PLUGIN 协议记录 + 校验门 + 组装接线
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [0062]
---

> 父 spec：`issues/0060-spec-transpile-pipeline-pluginization.md`（决定 6 + Testing Decisions 接缝 4）。057 先例（manifest jaix 标记协议 + 校验矩阵）。

# 0063: Package 配置面：TRANSPILE_PLUGIN 协议记录 + 校验门 + 组装接线

**What to build:** 包作者在 package.jai 声明自己的转译管线（jaix 风格：插件 id + version + 类型化选项槽）——Package 声明面新增管线字段；manifest 求值器按声明序打印 `TRANSPILE_PLUGIN=<id>|<version>` 可重复协议记录（JAIX_CONFIG 同族先例：恒打印）；严格解析两 case（重复 = Duplicate ... record.）+ 纯函数校验门（validate_jaix_marker 同款拆分：未知 id / 重复 id / 非法选项 = 诊断拒绝；load 路径进程内不可测的测试缝同款）；build/test 组装按声明序建管线（声明序 = 管线序）；**未声明 = 缺省管线**（两内置插件按现状交互契约——现状行为零变化）；显式声明两内置插件（缺省序）== 缺省管线（视图与缓存键同值）。v1 两内置插件选项集为空（选项槽就位、无实际选项行——跨进程协议只带 id+version）。

**Blocked by:** 0062（声明管线变化必须先有缓存键敏感面——否则显式声明包的视图陈旧正确性隐患）

**Status:** ready-for-agent

- [ ] Package 声明字段（id + version + 类型化选项槽）+ 求值器 `TRANSPILE_PLUGIN=<id>|<version>` 记录（声明序、可重复、恒打印）
- [ ] 严格解析两 case（重复拒绝）+ 校验门矩阵（未知 id / 重复 id / 非法选项 = 诊断拒绝；可测缝拆分）
- [ ] build/test 组装接线：声明序 = 管线序；未声明 = 缺省管线（现状行为零变化）
- [ ] 单测/矩阵 + E2E：fixture 包显式声明两内置插件（缺省序）→ 视图与缓存键与缺省同值；声明未知 id → 清晰拒绝
- [ ] 三路径全绿 + golden 30/30 零重定
