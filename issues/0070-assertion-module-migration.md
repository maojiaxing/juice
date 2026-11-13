---
title: 断言模块与自测迁移到 testing
status: open
labels: [wayfinder:task]
assignee:
blocked-by: [0069, 0071]
parent: 0065
---

> 2026-10-22 重锚：按新 juice（otter 实现）重写；旧 `modules/Testing.jai` 已不存在，定义源改为 `src/module.jai` 的 testing 段。共同事实见 `0065` Notes。
>
> 2026-10-22 0066 定案：保留完整 vendored prefixed 镜像（API + 自测）；同步测试在 juice `tests/`，整文件逐字节比较 publication 输出与 testing 权威面，testing 缺席 SKIP、漂移失败。详见 `0066` Resolution。

## Question

把新 juice 的 Testing 定义面迁到 `jai/testing/`：

- 权威面 = `testing/modules/Testing.jai`（裸名；旧 juice `modules/Testing.jai` API 兼容：expect / expect_eq / fail / run / finish / path_mapping）；来源 = `src/module.jai` 的 `// [PUBLICATION-SECTION testing]` 段（157 起）经 `src/publication.jai:publish_testing_module`（221）剥前缀后的公开面；
- 新 juice 侧按 0066 结论保留 vendored prefixed 完整镜像（API + 自测）；新增 juice `tests/` 同步测试，整文件逐字节比较 `publish_testing_module(src/module.jai)` 输出与 testing 权威面（`testing/modules/Testing.jai`，定位经 `src/testing_location.jai`：`JUICE_TESTING_ROOT` > 兄弟 `../testing`；含 `#import "Basic";` 头、注释、自测块与行尾；testing 缺席 SKIP，漂移失败并指向 `src/module.jai`）；
- 自测与 fixture：testing 权威侧落裸名自测；juice 保留 vendored prefixed 镜像自测（`src/module.jai:315-389`）与 `tests/module_tests.jai` 双面矩阵（可复制权威侧用例，不删 juice 面）；`tests/data/testing-face/{pass,fail,mapped}/src/scenarios.jai` 子 fixture 迁 `testing/tests/data/testing-face/...`；若 testing 根跑测试需要 support 段，按 `src/commands/test.jai:testing_module_support_block`（324）的 marker 契约落 `testing/tests/test_support.jai` 段（真实 in-package 场景见 0071；现有合成视图单测在 `tests/test_transpile_tests.jai:337/359/512/1113`）；
- testing 根的测试程序经 in-package `modules/Testing.jai` 得到 EXPAND 视图（自测计入 + support 段）；global `<exe>/modules/Testing.jai` 由 juice 自身套件与 0066 同步测试覆盖；
- 在 testing 根跑 `juice test` 全绿，输出契约（`[test]` 行、失败行 `path:line,col: message`、`N passed, M failed` 汇总）逐字节不变。

**Done when:** testing 根 `juice test` 全绿（含 child pass/fail/mapped 场景与原输出断言）；juice 侧按 0066 决策保留 vendored 副本并加同步测试。
