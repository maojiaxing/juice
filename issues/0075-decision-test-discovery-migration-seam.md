---
title: 决策：test discovery 迁入 testing 的切面与集成协议
status: open
labels: [wayfinder:grilling]
assignee:
blocked-by: []
parent: 0065
---

> 2026-10-22 补充（用户拍板）：测试发现同样迁入 testing；juice 只提供集成接口/协议。共同事实见 `0065` Notes「发现面（2026-10-22 补充）」条。
>
> 2026-10-22 0067 定案：testing root LIB + `packages/Jaix_Plugin_Test_Block` 成员；Testing 面 `testing/modules/Testing.jai`；dev-time 定位 = `src/testing_location.jai`（`JUICE_TESTING_ROOT` > 兄弟 `../testing`）。

## Question

`test discovery`（从编译器注记流枚举测试过程）迁入 `testing/` 后，testing 提供什么、juice 保留什么、两者之间的接口/协议是什么？

新实现事实：

- 权威源 = `src/test_discovery.jai`（285 行）：note 匹配（`note_matches_test` / `header_is_test`）、确定性排序（`test_name_less` / `sort_test_names`）、查重（`first_duplicate_test_name`）、编号（`number_tests`）、源隔离（`source_path_allowed`）、收集复合（`collect_test_entries`）、pattern 过滤（`filter_test_entries`）、注入 runner 文本生成（`generate_test_runner_code`）。
- 消费面 1：生成的测试 metaprogram 经 `Test_Metaprogram_Options.discovery_source`（`src/test_runner.jai:99-144`，字段在 113）以绝对路径 `#load`；运行期路径 = `test_runner_discovery_source()`（`src/test_runner.jai:464-474`）→ `test_discovery_module_path(juice_modules_dir())` = `<exe>/modules/juice_internal/test_discovery.jai`；发布 = `build.jai:197/250` 逐字复制（发布树 8 件之一，`docs/spec.md` §9.2）。
- 消费面 2：`src/main.jai:62` 在 juice 自身构建闭包内 `#load`；`tests/test_command_tests.jai:11` 直接加载同一源做纯函数直测。
- 消费面 3（耦合）：lint 观察在收集期复用 `source_path_allowed` 同一隔离谓词（spec §8.2）；pattern 过滤、零入口短路、全局编号续号语义都在发现面/生成文本的交界；`test_runner.jai` 同时拥有 driver 生成与 metaprogram 生成。
- 安装布局契约：exe + 相邻 `modules/`，exe 自带测试所需全部源件（`build.jai:170-177`）；发现源迁出 juice 后如何继续满足该契约是本票核心。
- 文件扫描（`scan_walk` / `collect_test_files`）按 `CONTEXT.md` 词汇是 **test scan**，不是 discovery；默认不在本票迁移范围，若用户意图包含须显式扩票。

需要定清：

1. **切面**：整文件迁移，还是只迁 note 匹配 / 收集 / 排序 / 编号 / 源隔离谓词，`generate_test_runner_code`（注入 runner 文本）留在 juice 作为集成协议？`test_runner.jai` 的 driver / metaprogram 生成中哪些属于「juice 只提供集成接口/协议」，哪些随发现面迁入 testing？
2. **接口形状**：testing 侧以什么模块/文件面暴露发现函数？落位候选 = `testing/modules/` 或另一个 `packages/` 成员（0067 已定 root 形态；本票定切面）。host-neutral 纯函数（不依赖 juice 类型）、还是依赖 juice 的 `Transpile` / `Testing` 类型？与 0068 的 text-block API 形状如何保持一致（同属 testing 库面时）。
3. **依赖方向 / 自包含**：juice 的 bootstrap `jai build.jai` 与已安装 exe 如何获得发现源——(a) testing 权威源 + juice vendored 副本 + 同步测试（与 0066 同构）；(b) 已安装 exe 运行时定位 testing 包（消费 `src/testing_location.jai`：`JUICE_TESTING_ROOT` > 兄弟 `../testing`；发布树/安装布局变化；bootstrap 仍须自包含，不破 0065 Out of scope 的自包含约束）；(c) 其他。写明 `build.jai` 发布步、`test_discovery_module_path`、`Test_Metaprogram_Options.discovery_source`、`src/main.jai` 闭包与 `tests/` 夹具的改动面。
4. **发布契约**：`target/modules/juice_internal/test_discovery.jai` 是否保留、改由 testing 提供、或从发布树移除；8 件发布树如何变；`juice_internal/` 私有目录契约是否继续。
5. **语义不变量**：note 匹配规则、数值前缀排序、查重诊断、全局编号基 1 续号、pattern 过滤后置、零入口短路、源隔离白名单——哪些由 testing 保证、哪些由 juice 的集成协议保证；迁移后 `juice_test_N` 计数与既有 pin 零重定如何验证。
6. **lint 与插件面**：生成 metaprogram 的 lint 观察复用隔离谓词；发现面迁出后 lint 继续消费 testing 的谓词（import / `#load` 路径），还是 juice 协议层持有该谓词？成员插件是否暴露/消费发现 API？

**Done when:** 切面与接口/协议写清（testing 提供面 + juice 保留面 + 依赖方向 + 自包含/发布形态）；0076 可直接照做；若结论改变 0066/0067 的前提，回写那两张票或说明无需变更。
