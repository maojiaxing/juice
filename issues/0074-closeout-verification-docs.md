---
title: 收口：三路径验证与文档
status: open
labels: [wayfinder:task]
assignee:
blocked-by: [0070, 0071, 0072, 0073, 0076]
parent: 0065
---

> 2026-10-22 重锚：按新 juice（otter 实现）重写；旧 `IMPLEMENTATION.md` / `SUMMARY.md` 已随实现替换删除，文档面改为新 `docs/spec.md` / `CONTEXT.md` / `docs/implementation/`。共同事实见 `0065` Notes。

## Question

全量验证与收口：

- juice 三路径（bootstrap debug/release + `juice test` + 自构建）全绿；基线 = 2026-10-22 替换后 545 found（max 540 + 手写 5）、331 passed、白名单 6、副本 SKIP 0（debug/release 两份产物）；jaix `juice test` + embed、testing 根 `juice test` 全绿；
- 既有 pin 零重定（或记录唯一必要重定）；
- 删除 legacy Testing 路径与旧实现（按各票结论）；
- 测试发现权威源已迁 testing（0076）：`docs/spec.md` §7.1/§7.2/§9.2 与 `CONTEXT.md` Test discovery / Test runner 词条、发布树描述同步；
- 更新新实现文档：`docs/spec.md`（§7.5 与转译插件关系、§8.1 内置管线归属、§9.2 发布树 / 行数）、`CONTEXT.md`（Testing / Test / Transpile / testing 包词条）、`docs/implementation/` 相关票 / 地图；`jaix/docs/spec.md` §10.1 与 `jaix/CONTEXT.md`（插件归属）；testing 自身 README（如需要）。旧 `IMPLEMENTATION.md` / `SUMMARY.md` 不再引用；
- 记录发布树变化与安装布局（8 件是否变化、testing 源是否随发布）。

**Done when:** 全部验证命令有实测证据；文档同步；地图 Decisions-so-far 索引完整、雾区清空或按规则划出范围；地图关闭。
