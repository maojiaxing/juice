---
title: 管线 runner + 插件接口 + 两内置插件 + 探测聚合
status: open
labels: [ready-for-agent]
assignee:
blocked-by: []
---

> 父 spec：`issues/0060-spec-transpile-pipeline-pluginization.md`（决定 2/3/4/7/8 + Testing Decisions 接缝 1/2/3）。研究 B 结论 4 的最小改造主体。

# 0061: 管线 runner + 插件接口 + 两内置插件 + 探测聚合

**What to build:** juice 自身 Transpile 机制跑在注册表驱动的管线上——扫描循环升级为管线 runner，test block 与 `#load` 处理成为前两个内置插件（缺省静态注册表、声明序 = 派发序）；插件接口 = {name, version, 模式适用性声明（STRIP/EXPAND）, 探测钩子成对（has_anchor / 可选 load_edges）, 转译钩子（扫描位点回调 → Edit/清单条目/诊断）, 跨文件状态经 Transpile_Context 扩展字段}；区域交互契约显式化（EXPAND 下 test 体内 `#load` 仍剥离、STRIP 下随占位消失）；闭包探测改为管线聚合（closure_has_tests / probe_package_closure 走插件钩子、test-free 闭包零转译短路不变）；ADR 0005 硬约束由 runner 强制（无法等行数展开的输入形态转译期拒绝——多行 test 头先例语义不变）。新共享模块 test-free（bootstrap `#load` 目标）、测试驻 tests/ 姊妹文件。**零可观测行为变化**：三路径全绿 + 既有 transpile_tests / transpile_front_tests / metaprogram_tests 一字不改 + golden 30/30 零重定。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 插件接口落地（{name, version, 模式适用性, 探测钩子成对, 转译钩子}）；新 test-free 模块（bootstrap `#load` 目标）；测试驻 tests/ 姊妹文件（0053 规则）
- [ ] runner = transpile_source 扫描循环保留；`#load` 分支与 test 锚点分支改为插件派发；交互契约显式化（EXPAND 下 test 体内 `#load` 仍剥离 / STRIP 下随占位消失）
- [ ] 探测聚合：closure_has_tests / probe_package_closure 走管线；test-free 闭包零转译短路不变
- [ ] ADR 0005 强制：等行数展开失败 → 诊断拒绝（多行 test 头语义不变）
- [ ] 姊妹测试起步：合成第三插件——派发三通道（Edit/清单/诊断）/ 跨文件状态续走 / 模式适用性 / 探测聚合 / 违反拒绝
- [ ] 三路径全绿（bootstrap debug/release + juice test + 自构建）；transpile_tests / transpile_front_tests / metaprogram_tests 一字不改；golden 30/30 零重定
