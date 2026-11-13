---
title: 地图：test 功能迁入 testing 包并在 juice 集成（新实现重锚）
status: open
labels: [wayfinder:map]
assignee: maojiaxing
---

## Destination

把 juice 的测试库面（断言模块 Testing + 两套 test-block 转换 + 测试发现面）与 jaix 的 test-block 插件迁入仓库根独立包 `testing/`，并在新 juice（otter 重写版；2026-10-22 已替换旧实现）中完成集成：`#import "Testing"` / `#import "Juice"` 拼写不变，juice 侧只保留集成接口/协议（发现、断言、转换由 testing 提供），juice 三路径测试全绿且既有 pin 零重定，jaix 自家测试与 fixture 更新后全绿。本 effort 决策与实施一体：票关闭时代码已落地并有测试证据。

> **2026-10-22 重锚**：juice 仓工作树已由 otter 实现替换（旧 `src/`、`tests/`、`modules/`、`docs/` 删除；新 `docs/spec.md`、`CONTEXT.md`、`packages/` 就位；master 工作树未提交）。旧票里的 `modules/Testing.jai`、`IMPLEMENTATION.md`、旧 build/bootstrap 路径全部失效；0066-0074 已按新实现重写，锚点以本票 Notes 为准。

## Notes

- 已定前提（2026-10-22 与用户逐轮敲定；仍有效，除注明「新实现复核」者）：
  - 实施型地图：每张票关闭时对应改动已落地。
  - `testing` = 仓库根独立 LIB 包（`jai/testing/`，与 juice/jaix 平级）；不新建 git 仓库（与 jaix 同状）。
  - 迁移范围 = 断言模块 + 两套 test-block 转换（juice 文本 Edit 管线版、jaix AST 插件版）+ **测试发现面**（`src/test_discovery.jai`；2026-10-22 用户补充：「testing test discover 功能也一样迁移到 testing 模块，juice 只提供集成接口/协议」）。juice 保留集成接口/协议层（test 命令编排、文件扫描、驱动生成与编译接线中属于集成协议的部分）；发现面迁出后的权威源/自包含/发布形态由 0075 定，实施归 0076。
  - 双实现共存于 testing；juice 继续使用文本版（引擎收敛不在本 effort）。
  - juice 自举保持「仓库自包含」：`build.jai` 只 `#load` juice 仓库内源码（当前闭包 = `src/{transpile,transpile_plugin,transpile_cache,transpile_front,target_layout,metaprogram,publication}.jai`，`build.jai:60-66`）；testing 权威源与 juice 内 vendored 副本共存时用同步测试钉死。
  - `#import "Testing"` 与 `#import "Juice"` 拼写不变；jaix 插件模块名 `Jaix_Plugin_Test_Block` 不变。
  - jaix 的 test-block 插件测试 / fixture 随代码迁入 testing；jaix 的 `package.jai` 去掉该依赖；try/catch 插件留在 jaix。
  - **模块面落位（0067 已定）**：Testing 权威面 = `testing/modules/Testing.jai`（in-package 约定、扫描排除集）；jaix AST 插件 = `testing/packages/Jaix_Plugin_Test_Block/` 成员包（root `module.jai` = 插件源）；包入口 = 根 `testing/module.jai`，不提供 `#import "testing"` 面。runtime 仍走 `testing_module_source` 的 in-package/global 两分支，零代码泛化。详见 0067 Resolution；0069 照做。
- 新实现锚点（重写票的共同事实基础）：
  - **定义源**：`src/module.jai` 的 `// [PUBLICATION-SECTION testing]`（157 起）= Testing 定义面；Testing API 159-288（prefixed 公开名 + `#scope_file` 裸内部态）；自测 test 块 315-389。
  - **发布**：`src/publication.jai:publish_testing_module`（221）剥 `Testing_` 前缀生成 `target/modules/Testing.jai`；`strip_testing_prefix`（203）；`testing_module_path`（297）；插件面闭包 `JUICE_CORE_LOAD_FILES`（83）= `transpile.jai` / `transpile_plugin.jai` / `lifecycle.jai` / `plugin.jai`，逐字复制到 `target/modules/juice_internal/plugin_face/`；发布树 8 件（`docs/spec.md` §9.2）。
  - **文本管线**：`src/transpile_plugin.jai:Transpile_Plugin`（75）/ `Transpile_Context`（86）/ `test_block_plugin`（214）/ `default_transpile_pipeline`（392）；`Test_Entry`（`src/transpile.jai:44`）；`src/plugin.jai:builtin_test_block_plugin`（296）与默认注册（276）；resolver = `src/transpile_config.jai`。
  - **test 命令**：`src/commands/test.jai:testing_module_source`（232；`<pkg>/modules/Testing.jai` in-package → `<exe>/modules/Testing.jai` global）、`testing_module_view`（251）、`testing_module_support_block`（324；marker 契约 `__testing_module_support_begin__/end__`）、`support_view` 收集（434-438）。**执行级事实**：新根包没有 in-package `modules/Testing.jai`，in-package 分支目前只由 `tests/test_transpile_tests.jai:337/359/512/1113` 的合成 support view 单测覆盖；真实 testing 包落地时须补真实 in-package 场景。
  - **build 侧**：`src/transpile_front.jai:testing_module_strip_view_dir`（313；`pipeline_has_anchors(..., "modules/Testing.jai")` 318、`ctx.path` 322 是泛化点）；`src/commands/build.jai:248` 消费 `<exe>/modules/Testing.jai`；`src/path_safety.jai:juice_modules_dir`（37）= `<exe>/modules`。
  - **测试面**：`tests/module_tests.jai`（123 起：definition-source vs imported-face 双面矩阵）；`tests/data/testing-face/{pass,fail,mapped}/src/scenarios.jai`（child 输出契约）；`tests/test_support.jai:49` 起（Testing 自测共享态）；`tests/test_transpile_tests.jai`（support block 合成视图）。
  - **发现面（2026-10-22 补充）**：权威源 = `src/test_discovery.jai`（285 行；note 匹配 `note_matches_test` / `header_is_test`、排序 `test_name_less` / `sort_test_names`、查重、编号 `number_tests`、源隔离 `source_path_allowed`、收集 `collect_test_entries`、过滤 `filter_test_entries`、注入 runner 文本 `generate_test_runner_code`）。消费面：`src/main.jai:62` 在 juice 闭包内 #load；生成 metaprogram 经 `Test_Metaprogram_Options.discovery_source`（`src/test_runner.jai:99-144`，字段在 113）以绝对路径 #load，运行期路径 = `test_runner_discovery_source()`（`src/test_runner.jai:464-474`）→ `test_discovery_module_path(juice_modules_dir())` = `<exe>/modules/juice_internal/test_discovery.jai`；发布 = `build.jai:197/250` 逐字复制（发布树 8 件之一，`docs/spec.md` §9.2 第 286 行）；测试钉 = `tests/publication_tests.jai:662-669`（逐字节）、`tests/bootstrap_tests.jai:184/331-390`、`tests/test_command_tests.jai:606-646`、`tests/test_support.jai:112-157/1054/1239`、`tests/test_runner_tests.jai` 的 `discovery_source` 路径断言。安装契约：exe + 相邻 `modules/`，exe 自带测试所需全部源件（`build.jai:170-177`）；发现源迁出后如何维持该契约 = 0075 的核心问题。CONTEXT 词汇：**Test discovery（注记枚举）≠ test scan（文件收集）**；本补充默认只迁发现，不迁 `scan_walk` / `collect_test_files`，除非 0075 显式扩票。
  - **jaix 侧**：`jaix/modules/Jaix_Plugin_Test_Block.jai`（632 行）；`jaix/package.jai`（DEP：packrat + `Jaix_Plugin_Test_Block` source `./modules` + `Jaix_Plugin_Try_Catch`）；`jaix/tests/plugins/test_block_tests.jai`（1082 行）；`jaix/tests/core/sourcemap_tests.jai`；`jaix/tests/test_support.jai`（607 行）；fixture = `jaix/fixture/config/config-test-block/`、golden `test-expand` / `test-expand-prefix` / `test-strip`、negative `multiline-test-head`、run `test-run`；jaix 无根 build.jai，测试经 juice exe 在 jaix 根运行；embed 成员 = `jaix/examples/embed-consumer`。注意：新 juice 的 `packages/juice-plugin-jaix` 是 PRESTEP 插件，与本票的 jaix AST test-block 插件无关。
- 验证基线（2026-10-22 替换后实测）：`jai build.jai` debug/release 各 exit 0；debug/release 产物副本于 juice 根 `build` / `test` 各 exit 0、SKIP 0、白名单 6、found = max `juice_test_N` 540 + 手写 5 = **545**、331 passed / 0 failed；成员套件 `packages/juice-plugin-jaix` 17/0、`packages/juice-plugin-lint` 3/0。收口票按此矩阵复核。
- 本图票 = `issues/0066` … `issues/0076`（`parent: 0065`）。frontier 查询：`status: open` + `blocked-by` 全关 + `assignee` 空。
- 当前 frontier（2026-10-22 清理后）：0068 / 0069 / 0071 / 0075（open + blocked-by 全关 + assignee 空）。
- 领域词汇权威：`juice/CONTEXT.md`（Test / Testing / Transpile / 插件 / Command lifecycle session 等）与 `jaix/CONTEXT.md`。
- 环境：Windows 11 + Git Bash；jai beta 0.2.009；juice 是唯一 git 仓库（当前 master 工作树，替换未提交），jaix/testing 无 git。tracker = `juice/issues/` 本地 markdown 票。
- 票执行 session 应咨询：grilling + domain-modeling；失败诊断参考 diagnosing-bugs。交流语言中文。

## Ticket chain

| # | 标题 | blocked-by | 交付 |
| --- | --- | --- | --- |
| 0066 | 决策：新 juice 构建的 Testing 依赖切割 | — | vendored 定义源 vs 外部源的决策与同步面 |
| 0067 | 决策：testing 包定位与发布布局契约 | — | 目录布局 + 搜索顺序 + 错误面 + 发布树影响 |
| 0068 | 决策：文本 test-block 转换的跨包 API 形状 | — | host-neutral API + 依赖方向 + 同步面 |
| 0069 | testing 包骨架与模块面 | — | `testing/` root + packages 成员骨架、模块面落位、`juice build` 验证 |
| 0070 | 断言模块与自测迁移到 testing | 0069,0071 | `testing/modules/Testing.jai` 权威面 + 自测/fixture 迁移 |
| 0071 | juice Testing 解析接线与特例泛化 | — | 真实 in-package/global 分支验证 + 文档（无代码泛化） |
| 0072 | 文本 test-block 转换迁移与 vendored 同步 | 0068,0069,0071 | testing 实现 + juice 适配器/vendored 副本 + 同步测试 |
| 0073 | jaix test-block 插件迁移与接线 | 0069 | jaix 插件迁入 `testing/packages` 成员 + 测试/fixture |
| 0074 | 收口：三路径验证与文档 | 0070,0071,0072,0073,0076 | 全矩阵 + 文档 + map 关闭 |
| 0075 | 决策：test discovery 迁入 testing 的切面与集成协议 | — | 提供面/保留面 + 接口协议 + 自包含与发布形态 |
| 0076 | test discovery 迁移与 juice 接线 | 0069,0071,0075 | testing 权威源 + juice 集成协议 + 测试证据 |

## Decisions so far

- 2026-10-22 重锚：juice 仓工作树已由 otter 实现替换（用户拍板：代码 + 当前文档、master 工作树、otter 记号保留）；旧路径失效，0066-0074 按新实现重写。基线 = 545 found / 331 passed / 白名单 6 / 副本 SKIP 0。
- 2026-10-22 范围补充（用户拍板）：测试发现面（`src/test_discovery.jai`）随断言/转换一并迁入 `testing/`；juice 只保留集成接口/协议。新增 0075（决策，等 0066/0067）与 0076（实施，等 0066/0067/0069/0071/0075）；收口 0074 追加 0076。
- [决策：新 juice 构建的 Testing 依赖切割](0066-decision-testing-dependency-cut.md)：选 (a) vendored prefixed 定义源 + testing 裸名权威面；juice `tests/` 整文件逐字节同步（testing 缺席 SKIP、漂移失败）；bootstrap/Build/Test 特例零改动，exe 死面保留（后续清理）。
- [决策：testing 包定位与发布布局契约](0067-decision-testing-package-location.md)：`testing/` root LIB + `packages/Jaix_Plugin_Test_Block` 成员；Testing 面 `testing/modules/Testing.jai`，无 `#import "testing"` 面；runtime 定位零改动、发布树 8 件不变；dev-time 定位 = `JUICE_TESTING_ROOT` > 兄弟 `../testing`（`src/testing_location.jai`）。

## Not yet specified

- 双实现（文本 / AST）的语义一致性套件是否需要、以何种形态纳入——取决于 0068。
- `testing` 包的版本策略（自身 version 与兼容承诺）——未定；发布树关系已由 0067 定为 dev-only、不随 juice 携带。
- 外部消费者（jaix-cli、juice-demo、juice fixtures）的兼容验证范围。
- 发现面迁出后 lint 观察（生成 metaprogram 复用 `source_path_allowed` 隔离谓词）与成员插件是否消费发现 API——由 0075 的接口边界决定。

## Out of scope

- test 命令编排 / 文件扫描（`scan_walk`、`collect_test_files`）/ 驱动与编译接线留在 juice——作为集成接口与协议层（测试工具链本体不动）；测试发现本体已补充进迁移范围（0075/0076）。
- 把 juice 的文本转译管线替换为 jaix AST 引擎——并存不替代；引擎收敛是独立 effort。
- jaix 的 try/catch 插件迁移——留在 jaix。
- `#import "Testing"` / `#import "Juice"` 改名或 breaking 变更。
- 放宽 juice 自举的自包含约束（bootstrap 依赖仓库外源码）。
- testing 包作为 otter 或其他构建工具的插件化铺设——未来 effort。
- 新建 testing 独立 git 仓库 / 版本发布流程。
- 并行测试、崩溃隔离、workspace-wide 测试聚合等既有 out-of-scope。
- 旧 juice 仓（git 历史）处置；0060-0064 补回 master（用户 2026-10-22 拍板不补）。
- 清理 exe 内无人引用的 prefixed Testing 定义面（拆分 `src/module.jai` / 裁剪 `main.jai` 闭包）——后续独立 effort。
- 提供 `#import "testing"` 包级面 / 让 testing 包成为按名依赖——本 effort 不做（Windows 大小写近匹配 + 无消费方）。
- 把 monorepo root 提到仓库根 `jai/`（让 testing 成员独立可跑）——本 effort 不做；root 固定为 `testing/`，成员验证由 testing root 承担。
