---
title: test discovery 迁移与 juice 接线
status: open
labels: [wayfinder:task]
assignee:
blocked-by: [0069, 0071, 0075]
parent: 0065
---

> 2026-10-22 补充（用户拍板）：测试发现迁入 testing；juice 只提供集成接口/协议。按 0075 结论执行。共同事实见 `0065` Notes「发现面（2026-10-22 补充）」条。
>
> 2026-10-22 0067 定案：testing root LIB + `packages/Jaix_Plugin_Test_Block` 成员；dev-time 定位 = `src/testing_location.jai`（`JUICE_TESTING_ROOT` > 兄弟 `../testing`）。

## Question

按 0075 的切面与协议：

- 把发现权威源迁入 `testing/`（落位按 0067/0069：root 的 `modules/` 或 0075 选定的成员/文件面；文件命名、入口与是否拆分 `generate_test_runner_code` 以 0075 为准）；定位经 `src/testing_location.jai`；
- juice 侧按 0075 选定的自包含/定位方案改造：`build.jai` 发布步、`test_discovery_module_path`、`Test_Metaprogram_Options.discovery_source` / `test_runner_discovery_source()`、`src/main.jai` 闭包、`tests/` 夹具与同步测试；
- 生成 metaprogram 的 `#load` 路径与 lint 观察的隔离谓词按 0075 的协议接线；
- 迁移 `tests/test_command_tests.jai` 的发现面直测，以及 `tests/publication_tests.jai` / `tests/bootstrap_tests.jai` / `tests/test_support.jai` / `tests/test_runner_tests.jai` 中的发布钉与路径断言；
- 保持语义不变量：note 匹配、数值前缀排序、查重、全局编号基 1 续号、pattern 过滤后置、零入口短路、源隔离白名单；`juice_test_N` 计数与既有 pin 零重定（或记录唯一必要重定）；
- 文件扫描（`scan_walk` / `collect_test_files`）与 test 命令编排留在 juice，作为集成协议层（不随本票迁移）。

**Done when:** 三路径全绿（bootstrap debug/release + `juice test` + 自构建）；测试发现权威源只在 testing（或按 0075 保留 vendored 副本并有同步测试）；集成/定位协议有直测；`docs/spec.md` §7.1/§7.2/§9.2 与 `CONTEXT.md` 的 Test discovery / Test runner / 发布树词条同步；发布树变化有记录。
