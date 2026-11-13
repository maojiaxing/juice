---
id: 034
title: fixture 收口 + 关闭 005
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [033]
blocks: []
---

> 父 spec：`005-spec-stage2-build-metaprogram.md`（完成定义 + 三接缝 + 出范围 + Further Notes 折回面）。上游规格：`docs/spec.md` §9/§10（收口折回面）。

# 034: fixture 收口 + 关闭 005

**What to build:** 阶段 2 收口——完成定义①-⑥ 逐条复核（自举三路径 + 求值器切换 + 版本断言 + fixture 家族）+ E2E fixture 家族复核（build-with-tests/test-blocks/test-blocks-fail/test-dep 族/plugin-fixture 良构+坏经自举 exe）+ spec 005 Resolution（US 24 兑现映射 + 决定 15 直落对照 + 链偏差汇总）+ **spec.md 执行级订正折回**（§9 三份产物 + 段裁剪形态 + 求值器切换拍板——R§5.3 与 §10 划分冲突以本拍板为准；§10 阶段 2 验收 = 自构建自测）+ map Decisions so far 追加（行归主会话）。

**Blocked by:** 033（自举验收——收口的先决面）

**Status:** closed

- [x] 完成定义①-⑥ 复核全绿（自举三路径/切换/断言/不回归/fixture）
- [x] E2E fixture 家族经自举 exe 复核
- [x] spec 005 写 `## Resolution`（US 24 兑现 + 决定 15 直落 + 链偏差汇总）+ status: closed
- [x] spec.md 执行级订正折回（§9/§10）
- [x] map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**（2026-10-20）：本票为阶段 2 收口票，无生产代码改动——完成定义①-⑥ 逐条复核 + fixture 家族复核 + spec 005 关闭 + spec.md 执行级订正折回。

**完成定义①-⑥ 复核**（2026-10-20，串行；各先清 `target/transpile`/`target/testing-module`；证据日志 `otter/target/audit-*.txt`）：

| 完成定义 | 结果 |
| --- | --- |
| ① 两模式 `jai build.jai` 产物 + 三份发布物 | debug exit 0（exe 994816B）、release exit 0（exe 582656B）；`target/modules/{Juice/module.jai 131 行, Testing.jai 237 行, juice_core.jai 12 行}` 每跑重生 |
| ② 两产物各于根 build/test 全绿（求值经发布面，path_mapping 指原文行） | 两模式 build exit 0（011 hand-off 行）+ test exit 0、**258 passed / 0 failed**、白名单 6、自锁 SKIP 2；失败坐标原文行双面实证（`src/module.jai:353:9` prefixed 面、`tests/module_tests.jai:178:5` 发布面） |
| ③ 旧 juice 不变式全绿 | debug + release 4/4 exit 0；**Found 443**、258 passed、0 failed、白名单 6、SKIP 0（两模式各一遍） |
| ④ 存量 + 新增全绿（双路径） | 409 → 443（030 +23 / 031 +6 / 032 +2 / 033 +3）；258 执行面全绿 |
| ⑤ 版本断言触发面 | 套件内 drift E2E（声明版本 ≠ JUICE_VERSION → 自举 exit 1 + stderr 编译期断言消息）随 258 全绿；绿向 = 两模式自举 |
| ⑥ fixture 包经自举 exe 全绿 | 见下节 |

**fixture 家族复核（经自举 exe）**：

- 套件内 E2E（自托管 exe 实跑，258/0）：`E2E: the test-block fixture expands, discovers and runs every test`、`E2E: a failing test-block reports the original file:line and exits 1`、`E2E: the pattern filters the generated test-block names`、`E2E: dependency tests are neither discovered nor executed`、`E2E: the in-package Testing module self-tests run through the compile view`、`E2E: build-with-tests strips test blocks and produces a runnable artifact`、`E2E：fixture 插件包全链（扫描→注册文件→真编译→合并执行）`、`E2E：坏 fixture 插件包全链（扫描→注册→合并响亮拒绝 + 行号保真门）`、`E2E: published modules compile and run under bare imports`（旧 juice 运行面逐名可见；自托管面同名程序 258/0）。
- 自举 exe 直接 CLI 复核（release 产物）：build-with-tests `run` →「hello from build-with-tests: 2 + 3 = 5」exit 0；test-blocks `test` → 4 passed/0 exit 0；test-blocks-fail `test` → exit 1 + `src/math.jai:13:5`；test-dep-root `test` → 1 passed/0 exit 0（依赖包测试零发现/零执行）；plugin-fixture 良构/坏经套件内全链 E2E（无 CLI 入口，扫描面为内部机制）。
- 复核后 fixture `target/` 已清（树零污染）。

**spec 005 收口**：`005-spec-stage2-build-metaprogram.md` 写 `## Resolution` + `status: closed`——US 24 全兑现映射（逐条证据）+ 决定 1-15 直落对照（spike/执行级修正指认：决定 2 入口锚定/守卫/import 面；决定 5 发布 Juice 面 + 内部结构面四类型；决定 6 自测块保留 + `#scope_export;`；决定 7 常量逐字抽取 + 四文件闭包；决定 9 编译期 `#assert`；决定 10 无 bootstrap hand-off）+ **链偏差汇总 29 项**（030:6 / 031:9 / 032:8 / 033:6，全有意设计决定，无遗留缺陷）。

**spec.md 执行级订正折回**：

- §9：发布产物 = **三份**（Juice 目录模块 + Testing 平铺 + juice_core 生成模块）并写明转换形态（段裁剪 / 剥前缀平铺 / 生成模块）+ 先发布后编译 + **求值器切换 = 发布落位即切换**（用户拍板，R§5.3 与 §10 划分冲突以此为准）+ 发布 Juice 面 = Package 兼容段 + 内部结构面（032 偏差 1）+ 自托管 runner 裸面消费形态（033）。
- §10：阶段 2 行改为「两模式 `jai build.jai` 产出 exe + 三份发布物；**验收 = 两产物各于根自构建自测全绿（求值经发布面）**」+ #load 闭包更新为实际六模块 + bootstrap 无 hand-off 纪律注明；表后补阶段 2 三接缝（005 决定 12）。
- §0：概述与生成件清单同步第三份发布物（同一订正表面的一致性收口）。

**偏差清单**（全有意，无遗留缺陷）：

1. **§0 概述同步纳入订正**：任务指定的折回面为 §9/§10；§0 的「两份发布物」概述与生成件清单属同一执行级事实，同步补 juice_core.jai（避免 spec 内部矛盾）。
2. **fixture 复核的双面证据形态**：自托管套件内测试名显示为 `juice_test_N`（028 偏差 1），fixture E2E 的逐名证据取旧 juice 运行面（同一程序/同一 258 执行面），CLI 面另以自举 exe 直跑补证。
3. **审计承接**：033 由越权方实现，已按主会话指令完成独立审计并签核（票 033「独立复核」节）；本节复核复用其审计产物 + 本票 4/4 与 fixture 复核。

**落盘**：`main.jai` 与生产代码零改动；旧 juice 仓零改动；map.md 不动（033 行由主会话落位；034 行归主会话）。
