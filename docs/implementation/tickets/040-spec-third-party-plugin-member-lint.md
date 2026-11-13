---
id: 040
title: 真实第三方插件成员包 spec：packages/juice-plugin-lint + 全链 lint E2E
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: []
blocks: []
---

> 上游规格：`docs/spec.md` §5（插件系统）、§8.2（lint = observer metaprogram 插件）、§10（自举阶段，本轮不涉及）。
> 来源：阶段 3 收口时登记的 map 未来票「真实第三方成员插件包」（`packages/` 布局 + `workspace.members` 变更 + 插件声明面）与「第三方插件全链路 E2E」（真实成员包布局下的扫描 → 注册 → 挂载）。研究依据：A§4.2（构建工具侧扫描 + 消费者 dependencies 声明插件包）、N§4.3（lint 挂 `.TYPECHECKED` 消息流）、L§5.4（钩子装配序）。
> 参照面（只读）：`tests/data/plugin-fixture/`（合成 fixture 全链先例）、`tests/plugin_scan_tests.jai`、`tests/test_command_tests.jai`、`tests/e2e_cli_tests.jai`；`how_to/480_custom_checks/first.jai`（`Message_Typechecked` 观察先例）。

## Problem Statement

插件机制在阶段 1c 只交付了库面与合成 fixture 验证，真实使用路径从未兑现：

1. **真实成员布局不存在**：spec §3 声明仓库成员驻 `packages/`，但仓库里没有任何成员包；根 `package.jai` 没有 `workspace.members`，也没有成员依赖。`packages/` 布局、成员校验、依赖 shim、发布面在「真实成员」形态下从未一起跑过。
2. **插件声明面未落地**：合成 fixture 是 `tests/data/` 下的裸目录，没有 `package.jai`、不是工作区成员、不经过 `workspace.members`/`dependencies`、不经过依赖 shim。用户无法按「声明一个成员依赖即可用插件」的方式使用第三方插件。
3. **扫描 → 注册从未进入生产编排**：`scan_plugin_package`/`generate_plugin_registration` 只有测试调用方；`juice test` 不扫描任何插件包，生成的测试 metaprogram 不加载注册文件，`hook_table` 参数在生产路径上恒为空。
4. **lint 仍是空位**：spec §8.2 把 lint 定为 observer metaprogram 插件（挂测试编译的 `.TYPECHECKED` 消息流），但既没有 lint 插件面，也没有真实 lint 插件包；用户跑 `juice test` 得不到任何 lint 诊断。
5. **全链没有端到端证据**：合成 fixture 的 driver E2E 不经过 CLI、不经过成员发现、不经过真实成员包，无法回答「真实工作区里第三方插件能不能用」。

## Solution

以 **lint 作为真实的第三方插件成员包**，一次把布局、声明面、扫描、注册、挂载与 E2E 全部落到真实路径：

- 新增真实成员包 `packages/juice-plugin-lint`（LIB）：标准 `package.jai`（`DEP juice_core source="../../"`）+ 根部 `module.jai`（`get_juice_plugin` + `@juice_plugin`，贡献 lint 面）；模块保持 test-free，自身测试驻 `tests/`。
- **声明面 = 既有机制**（A§4.2.2）：根包用 `workspace.members` 让成员可发现，用 `dependencies` 按名声明插件包。不新增 manifest 记录、不新增 Package 字段、不引入兄弟常量。扫描根 = 根包 DEP 中能对上工作区成员的包，按 DEP 声明序。
- **扫描进入 `juice test` 生产编排**：测试 COMPILE 阶段扫描这些成员包，按「DEP 声明序 → 包内词法扫描序」合并命中，生成一份工作区级注册文件 `<root>/target/plugins/registration.jai`（会话产物，随 `target/` 清理）。
- **lint 面进 `Juice_Plugin`**：新增可空 `lint` 面（`Lint_Plugin`，观察单个已收集测试过程的 header + 子表达式并返回 findings）。合并面收集 `lint_plugins`；跨插件重名查重。发布面无需新增产物——`juice_core` 的 `#load` 闭包已包含插件面。
- **挂载点 = 生成的测试 metaprogram**：有插件命中时，metaprogram 源码增补 `#import "juice_core"` + `#load <注册文件>`，在 `#run` 内合并注册表，并在 `.TYPECHECKED` 收集路径上对隔离集内的每个测试 header 调用 lint 观察者；findings 由宿主按原始包相对路径 + 1 基坐标经 `compiler_report` 三汇报告。合并失败 = 编译期 ERROR，测试编译失败。
- **v1 lint 规则**：测试过程名必须 snake_case（`[a-z0-9_]`），WARNING 级，不改变退出码。
- **零插件工作区字节不变**：无成员插件命中时，生成的 metaprogram 与今天逐字节相同，行为完全不变。
- **E2E 用真实布局**：真实 `juice.exe` 驱动一个运行期搭出的 scratch 工作区（根包 + 从真实成员复制出的 `packages/juice-plugin-lint` + 一个故意坏命名的 `@test` 文件），断言 lint 警告、测试照常运行、exit 0；另在真实成员包根跑 CLI 冒烟。

第三方 transpile/hook 面**不在 CLI 进程内挂载**（类型同一性约束：注册文件消费的是按名 `#import` 的 `juice_core` 面，与工具进程内应用作用域的声明不是同一类型）。本 effort 的生产挂载面 = 生成测试 metaprogram 内的 lint 观察者；第三方 hook/transpile 面仍可被注册与合并，但 CLI 命令不消费它们。

## User Stories

1. As a workspace author, I want to declare a plugin package by listing it in `workspace.members` and `dependencies`, so that using a plugin never requires editing a central registry.
2. As a workspace author, I want the tool to scan only the root package's declared member dependencies, in dependency declaration order, so that plugin activation is explicit and order is deterministic.
3. As a workspace author, I want non-member dependencies and members without plugin anchors to be ignored, so that ordinary libraries never become plugins by accident.
4. As a workspace author, I want a duplicate dependency name to resolve once, so that the plugin set is not doubled by declaration mistakes.
5. As a plugin author, I want to define `get_juice_plugin` with an `@juice_plugin` tail note in one module file, so that my package is discoverable without ceremony.
6. As a plugin author, I want my plugin package to be a normal LIB member with a `package.jai` and a `DEP juice_core`, so that it builds and tests like every other package.
7. As a plugin author, I want the directory name, package name and module name to be one identity, so that the dependency shim and the generated `#import` agree byte for byte.
8. As a plugin author, I want a `lint` face on `Juice_Plugin`, so that one plugin value can contribute a lint rule.
9. As a plugin author, I want each collected test procedure to arrive with its typechecked header and flattened subexpressions, so that I can write type-aware rules.
10. As a plugin author, I want to return findings (line, column, message, level) instead of calling `compiler_report` myself, so that my rule does not depend on reporting internals.
11. As a plugin author, I want duplicate lint rule names rejected at merge time, so that two plugins cannot silently double-report.
12. As a test author, I want lint warnings to name the original package-relative file and a 1-based line/column, so that I can jump to the source.
13. As a test author, I want lint warnings to leave the exit code alone in v1, so that lint is advisory while the rule set matures.
14. As a test author, I want lint to inspect all discovered tests even when I filter with a pattern, so that filtering never hides warnings.
15. As a test author, I want lint to ignore imported modules and only inspect the isolated test set, so that library code never floods the report.
16. As a test author, I want the shipped rule "test procedure names must be snake_case", so that test names stay uniform and greppable.
17. As a test author, I want a badly named `@test` procedure to produce one warning naming that procedure, so that the fix is obvious.
18. As a test author, I want the test to still run and be counted normally after a lint warning, so that warnings and failures stay separate.
19. As a user of a workspace with no plugin dependencies, I want the generated test metaprogram to stay byte-identical, so that nothing about my builds changes.
20. As an otter developer, I want a real `packages/juice-plugin-lint` member in the repository, so that the `packages/` layout stops being aspirational.
21. As an otter developer, I want the root package to declare that member and its dependency, so that the real repo exercises the declaration surface on every self-hosted test run.
22. As an otter developer, I want the plugin module to stay test-free and its tests to live under `tests/`, so that the registration-loaded module always compiles without transpile.
23. As an otter developer, I want a workspace-level scan function over the discovery snapshot, so that command wiring and tests share one seam instead of re-implementing member selection.
24. As an otter developer, I want one combined registration file under `target/plugins/`, so that the plugin set is a session artifact cleaned with `target/`.
25. As an otter developer, I want registration order to be dependency order then scan order, so that plugin execution is deterministic and reviewable.
26. As an otter developer, I want cross-package duplicate module names resolved deterministically with a diagnostic, so that the registration never becomes ambiguous.
27. As an otter developer, I want scan, walk, read and write failures to fail `juice test` loudly, so that a broken plugin package never degrades into "no plugins".
28. As an otter developer, I want the test metaprogram to load the registration only when hits exist, so that zero-plugin packages pay no import or compile cost.
29. As an otter developer, I want merge failures (duplicate ids, lint name conflicts) reported as compile errors, so that an invalid plugin set never runs.
30. As an otter developer, I want lint observers invoked at the same collection point as discovery, so that there is one source of truth for "what is a test".
31. As an otter developer, I want the lint face to ride inside the published `juice_core` face, so that no fifth publication artifact is introduced.
32. As an otter developer, I want the member package to run its own tests green as its own root, so that members remain independently buildable and testable.
33. As an otter developer, I want a full-chain E2E that copies the real member into a scratch workspace and drives the real exe, so that the layout, declaration surface, scan, registration, metaprogram and lint report are proven together.
34. As an otter developer, I want a CLI smoke on the real member root, so that the shipped member package is known-good in its real location.
35. As an otter developer, I want the root self-hosted `juice test` run to stay green with the lint plugin loaded, so that the tool's own workflow is the primary acceptance.
36. As an otter developer, I want the design spec folded back to the executed reality at closeout, so that §0/§3/§5/§8 do not describe a world that does not exist.

## Implementation Decisions

1. **成员身份**：`packages/juice-plugin-lint`，目录名 = `Package.name` = 模块名（`module.jai` 根部入口约定）。`type = .LIB`，无 targets；`dependencies` 声明 `{name = "juice_core", source = "../../"}`（spec §3.3 官方成员引根形态）。
2. **声明面 = 既有机制，零协议扩展**：根包 `workspace.members` 列入该成员，`dependencies` 按名声明它。不新增 `Package` 字段、不新增 manifest 记录、不引入 `package.jai` 兄弟常量。扫描根 = 根包 `dependencies` 中能按名对上 `member_packages` 的包，按 DEP 声明序；重复 DEP 名只处理首次出现；非成员 DEP 跳过。
3. **工作区级扫描函数**（`plugin_scan` 库面新增）：输入工作区发现快照，输出合并后的命中列表 + 诊断 + ok。内部对每个扫描根调用既有 `scan_plugin_package`，命中按「DEP 声明序 → 包内词法序」累积；跨包同名模块复用既有落位裁定（低探测序胜，同级先者胜）并产生非致命诊断；任一扫描根不可扫 = `ok = false`（响亮失败通道）。
4. **注册文件**：一份工作区级合并注册文件，落 `<root>/target/plugins/registration.jai`（会话产物：每次 `juice test` 重生、`clean` 随 `target/` 整删、不入库）。复用既有两段 codegen（逐名 import + 钩子装配）；既有按包落点助手保留给合成 fixture E2E，不退役。
5. **lint 面形状**（`plugin` 库面新增；决策密集，原型形状如下）：
   ```
   Lint_Level :: enum { ERROR; WARNING; INFO; }

   Lint_Finding :: struct {
       line:    s64;    // 1-based
       column:  s64;    // 1-based
       message: string;
       level:   Lint_Level = .WARNING;
   }

   Lint_Plugin :: struct {
       name:    string;   // 规则身份，合并期查重
       version: string;
       inspect_test_header: #type (header: *Code_Procedure_Header,
                                   subexpressions: [] *Code_Node) -> [..] Lint_Finding;
   }
   ```
   `Juice_Plugin` 增可空 `lint: *Lint_Plugin = null`；`Merged_Plugins` 增 `lint_plugins: [..] Lint_Plugin`。合并规则：空 `name`、跨插件重名 = 诊断 + `ok=false`；既有 id/钩子/transpile 名查重不变。lint 面引用 `Compiler` 的类型，`plugin` 库面新增 `#import "Compiler"`；`juice_core` 的 `#load` 闭包已含该文件，发布产物数量与文本契约不变。
6. **lint 宿主 = 生成的测试 metaprogram**：`Test_Metaprogram_Options` 增 `plugin_registration: string = ""`。非空时生成文本增补 `#import "juice_core";` + `#load "<绝对路径>"`；`#run` 开头调用注册装配并合并，合并诊断逐条 `compiler_report`（ERROR → 测试编译失败）；在 `.TYPECHECKED` 收集路径上、测试注记判定与隔离判定（`source_path_allowed`，与发现同一谓词）之后，对每个测试 header 依次调用各 lint 观察者，findings 由宿主按 `path_pairs` 映射出的原始包相对路径 + 1 基坐标报告，`.ERROR/.WARNING/.INFO` 映射到 `Report` 三汇。观察者位置 = `.TYPECHECKED` 收集期（runner 注入之前），同一次收集、单一发现源；pattern 过滤不影响 lint。
7. **v1 规则**：`test-name-snake-case`——测试过程名必须只含 `[a-z0-9_]`（非空）；违反 = 一条 WARNING，锚定过程 header，消息含过程名。生成的 `juice_test_N` 与手写 snake_case 名称天然通过；`Testing_` 等非 `@test` 过程不参与。
8. **零插件字节不变**：`plugin_registration == ""` 时 `generate_test_metaprogram` 输出与现文本逐字节相同（新增条件段全部包裹在非空分支内）。既有生成文本锁定测试保持有效。
9. **生产接线点**：测试 COMPILE 阶段、写 metaprogram 之前执行工作区扫描；命中非零 → 建目录、写注册文件、把路径交给 metaprogram 选项；扫描/写盘失败 = 命令失败（HANDLER_FAILED）。扫描产生的非致命诊断以 `[juice WARNING]` 打印。不新增 lifecycle 阶段（阶段枚举只增不改，本特性不需要新阶段）。
10. **成员包内容**：`module.jai` 根部 = 插件实现（`#import "Basic"/"Compiler"/"juice_core"`、snake_case 谓词、`inspect_test_header`、`get_juice_plugin` + `@juice_plugin`）；模块 test-free（注册文件直接编译该模块，test 块不可编译）；自身测试驻成员包 `tests/`，测试 snake_case 谓词，成员包作为自身根跑测试。
11. **进程边界与类型同一性**：lint 代码只在「按名 `#import "juice_core"` 的生成程序」里编译执行（测试 metaprogram 即此形态）。CLI 进程内的 `hook_table` 参数是内置/进程内钩子的挂载面，不是第三方插件值的注入面；本 effort 不尝试把第三方 transpile/hook 面注入 CLI 进程。
12. **依赖解析形态**：成员 `DEP juice_core source="../../"` 在成员根编译时由依赖 shim 兜底；编译期实际优先命中运行 exe 旁的发布 `modules/` 目录（导入路径第一顺位）。根 prep 时成员相对 DEP 按根 CWD 解析（C§3 缺口 3 既有纪律），不会产出可用的错误 shim。
13. **文档折回（closeout）**：`docs/spec.md` §0（概述 + 目录树成员行）、§3.2（成员 = `packages/juice-plugin-lint`；内置 transpile 仍静态驻 src）、§5.1（`Juice_Plugin.lint` 字段）、§5.2（声明面 = dependencies；扫描根；注册落点；lint 经测试 metaprogram 挂载）、§8.2（lint 执行形态：观察面 + findings + 宿主报告；不再描述未落地的 `at_RUNNER_GEN`/`after_COMPILE` 收集步）；`old-juice-exit.md` §5 插件行状态更新。
14. **兼容性**：manifest 协议与 `Package` 字段零变更，存量 `package.jai` 原样可消费；旧 juice 仓零改动。

## Testing Decisions

**好测试的标准**：只测外部行为——给定工作区/发现快照得到确定的命中序与诊断；给定注册路径得到确定的生成文本；给定真实工作区与真实 exe 得到可观察的 lint 输出与退出码。不测私有助手，不按内部调用序断言。

**接缝 1（姊妹测试，进程内）**：
- 工作区扫描：真实 fixture 工作区（根 `package.jai` + `packages/` 成员）经现有发现面得到快照 → 命中序 = DEP 声明序；非成员 DEP 跳过；无锚成员零命中；重复模块名跨包裁定 + 诊断；不可扫根 = ok=false；真实仓库根发现包含该成员且命中恰为lint 插件。
- 生成器：`plugin_registration == ""` 时 `generate_test_metaprogram` 与现文本逐字节相等；非空时含 `#import "juice_core"`、`#load "<路径>"`、合并调用与 lint 观察调用，runner 注入面不变。
- 命令接线：经既有 `spawn` 注入面断言扫描 → 注册写盘 → metaprogram 选项传递；扫描失败 = 命令失败。
- 先例：`tests/plugin_scan_tests.jai`（扫描矩阵 + 裁定）、`tests/test_metaprogram_tests.jai`（生成文本锁定）、`tests/test_command_tests.jai`（测试命令的注入 spawn）。

**接缝 2（全链 CLI E2E，真子进程）**：
- 运行期搭 scratch 工作区：根 `package.jai`（LIB，`workspace.members = ["packages/juice-plugin-lint"]` + 同名 DEP）、从真实成员包逐字节复制出的 `packages/juice-plugin-lint/{package.jai,module.jai}`、`tests/bad_name_tests.jai`（一个 `@test BadName` 过程）。
- 真 `juice.exe test` 于 scratch 根：exit 0；输出含 `[juice lint]`、`BadName`（原始包相对路径 + 坐标）；输出含 `[test] BadName` 与 `0 failed`（警告不阻断执行）。
- 先例：`tests/test_command_tests.jai` 的 exe E2E 与 `tests/e2e_cli_tests.jai` 的真 argv 驱动。

**接缝 3（真实成员包 CLI 冒烟）**：
- 真 `juice.exe test` 于 `packages/juice-plugin-lint` 根：exit 0，成员自身测试全绿（snake_case 谓词用例）。
- 证明真实成员是合法包：发现、依赖准备、测试编译、发布面导入全通。
- 先例：`tests/e2e_cli_tests.jai`（`run_otter_child_at`）。

**验收矩阵**：`jai build.jai` debug/release 各 exit 0；产物副本于根 build/test 全绿（SKIP 0、白名单恰 6 行、无新增失败）；真实成员根 test 全绿；接缝 2 的 lint 警告 + exit 0；接缝 1 矩阵全绿。测试计数不预钉绝对值，按既有约定记录 found/passed/白名单。

## Out of Scope

- 第三方 transpile 面与 lifecycle 钩子在 CLI 进程内的挂载（类型同一性约束；需要新的进程/会话程序架构，独立 effort）。
- `juice build` 的插件扫描与 lint（spec §8.2 只挂 test 编译）。
- lint 规则配置面：选项协议、severity 配置、`--deny-warnings`、规则开关（v1 规则集固定）。
- 非成员插件包（git/本地外部依赖）的扫描；仅工作区成员 + 根 DEP 的组合。
- 第二条及以后的 lint 规则；子表达式规则集（面已携带 subexpressions，供未来规则直接使用）。
- 把内置 transpile 插件迁入 `packages/`；`juice-plugin-test`/`juice-plugin-transpile` 成员的兑现。
- test 显示名恢复（`@test("name")`）、`at` 其余 9 个挂载点、jaix PRESTEP 全链、lint 之外的新插件面。
- 旧 juice 仓任何改动。

## Further Notes

- **风险与 spike 项**：测试 metaprogram 程序内「`juice_core` 模块类型 + 注册文件 + 插件模块」的类型同一性已由 025 的 driver E2E 证明；本轮新增的是同一程序内还加载了发现面源码。若编译期出现作用域歧义，按 025 偏差 3 的结论处理（共享一个按名导入的模块面），不得退化为 `#load` 双实例。
- **坐标**：编译器 AST 位置为 0 基行/字节列；findings 面固定为 1 基，由插件在读取 header/子表达式时换算。宿主不再做二次换算。
- **报告路径**：lint findings 用 `path_pairs` 映射回原始包相对路径（与测试失败打印同一映射），不暴露 `target/transpile/` 视图路径。
- **诊断去重**：lint 观察发生在发现的同一收集点，测试 header 在现实现中每个只出现一次；不引入额外去重层。若未来消息流重复投递，按 header 名 + 路径去重，属实现细节。
- **性能**：零插件工作区零额外导入/编译；有插件命中时测试 metaprogram 多编译一个插件模块（毫秒级）。扫描只读成员包源码，不缓存（会话产物语义优先）。
- **语言与纪律**：交流中文；实现须遵守 `CLAUDE.md`（读全文件、无 `*void` 滥用、`.{}` 字面量、内联单调用助手）；测试组织遵守 0053 规则（库面 test-free、姊妹测试文件）。

## Resolution

**状态：closed（2026-10-21）**

### 交付摘要

真实第三方插件成员包与 lint 全链已落地，声明面保持零协议扩展：

- **真实成员包** `packages/juice-plugin-lint`（仓库首个 `packages/` 成员）：LIB，`package.jai` 声明 `DEP juice_core source="../../"`，根部 `module.jai` 为 test-free 插件实现（v1 规则：测试过程名必须 snake_case），自身测试驻 `tests/` 并作为自身根跑通。根 `package.jai` 以 `workspace.members = ["packages/juice-plugin-lint"]` + 同名 DEP 声明。
- **库面**（`src/plugin.jai`）：`Lint_Level`（WARNING 为零值成员）/`Lint_Finding`（1 基 line/column）/`Lint_Plugin`；`Juice_Plugin.lint` 可空面与 `Merged_Plugins.lint_plugins`；合并期空规则名/跨插件重名 = 诊断 + `ok=false`。
- **扫描与注册**（`src/plugin_scan.jai`）：`scan_workspace_plugins` 按根 DEP 声明序选择工作区成员、逐包扫描并按「DEP 序 → 包内词法序」合并；跨包同名模块按探测序裁定且严格保持 DEP 段序；扫描/读取失败 = `ok=false`。工作区级注册文件落 `<root>/target/plugins/registration.jai`（既有两段 codegen 复用）。
- **宿主**（`src/test_metaprogram.jai`）：`plugin_registration`/`package_root` 选项；有注册时生成文本增补 `#import "juice_core"` + `#load <注册文件>`，`#run` 内合并（失败 = 编译错误）；`.TYPECHECKED` 收集期按序调用 lint 观察者，findings 经 `compiler_report` 三汇、原始包相对路径、1 基坐标。
- **生产接线**（`src/commands/test.jai`、`src/main.jai`）：COMPILE 前端扫描 → 写注册 → 传选项；扫描/写盘失败 = `HANDLER_FAILED`；零命中生成文本逐字节不变。
- **E2E**：scratch 工作区（真 exe + 从真实成员复制的包 + 坏命名 `@test`）断言 `[juice lint]` 警告、测试照常执行、exit 0；真实成员根 CLI 冒烟 3 passed。两条 E2E 驻 `tests/test_command_tests.jai`，随根套件执行。

### 逐决定结果（1-14）

| # | 决定 | 结果 |
| --- | --- | --- |
| 1 | 成员身份 | 兑现：`packages/juice-plugin-lint`，目录名 = 包名 = 模块名，LIB，`DEP juice_core source="../../"` |
| 2 | 声明面零扩展 | 兑现：`workspace.members` + `dependencies`；重复 DEP 名首次处理、非成员 DEP 跳过；无新 manifest 记录/`Package` 字段 |
| 3 | 工作区级扫描 | 兑现：`scan_workspace_plugins`；命中序 DEP 声明序 → 包内词法序；不可扫/不可读 = `ok=false`；跨包裁定按探测序 |
| 4 | 注册文件 | 兑现：`<root>/target/plugins/registration.jai` 会话产物；两段 codegen 复用；按包落点助手保留 |
| 5 | lint 面形状 | 兑现，偏差 1：`Lint_Level` 文序改为 `WARNING; ERROR; INFO;`（WARNING 零值成员）；其余形状同原型 |
| 6 | lint 宿主 | 兑现：生成 metaprogram 加载/合并；`.TYPECHECKED` 收集期观察；pattern 过滤不隐藏 finding；合并失败 = 编译错误 |
| 7 | v1 规则 | 兑现：`test-name-snake-case`，WARNING，消息含过程名，锚 header |
| 8 | 零插件字节不变 | 兑现：空注册生成文本逐字节锁测试 |
| 9 | 生产接线 | 兑现：COMPILE 阶段扫描/写盘/选项传递；失败 = `HANDLER_FAILED`；非致命诊断 `[juice WARNING]`；无新 lifecycle 阶段。偏差 2：spawn 缝增 `import_dirs` |
| 10 | 成员包内容 | 兑现：根部插件实现 test-free，自身测试驻 `tests/`，成员根 test 全绿 |
| 11 | 进程边界/类型同一性 | 兑现：lint 只在按名 `#import "juice_core"` 的生成 metaprogram 内编译执行；CLI 进程不消费第三方 hook/transpile 值 |
| 12 | 依赖解析形态 | 兑现：成员根 shim 指向根 `src/module.jai` 剥离视图；编译期实际命中 `<exe>/modules` 发布面 |
| 13 | 文档折回 | 兑现：`docs/spec.md` §0/§3/§5.1/§5.2/§8.2/§11 + `old-juice-exit.md` §4/§5 |
| 14 | 兼容性 | 兑现：manifest 协议与 `Package` 字段零变更；旧 juice 仓零改动 |

### 验收矩阵（2026-10-21；串行；各根路径前清 `target/transpile`、`target/testing-module`、`target/plugins`）

| 路径 | 命令 | 结果 | 证据 |
| --- | --- | --- | --- |
| debug 自举 | `jai build.jai` | exit 0，产出 `target/juice.exe` | `target/audit-047-bootstrap-debug.txt` |
| debug 直跑 | `target/juice.exe test` | exit 0；SKIP 2（已知自锁环境形态）；480 顶层条目（max `juice_test_475` + 手写 5）；294 passed / 0 failed；白名单恰 6 行；`[juice lint]` 零行 | `target/audit-047-direct-test-debug.txt` |
| release 自举 | `jai build.jai - release` | exit 0 | `target/audit-047-bootstrap-release.txt` |
| release 直跑 | `target/juice.exe test` | exit 0；SKIP 2；480（475 + 5）；294 passed / 0 failed；白名单 6；`[juice lint]` 零行 | `target/audit-047-direct-test-release.txt` |
| 副本跑（权威，SKIP 0） | `cp target/juice.exe target/juice-copy.exe` → `target/juice-copy.exe build` → `target/juice-copy.exe test` | build/test 各 exit 0；SKIP 0；480（475 + 5）；294 passed / 0 failed；白名单恰 6 行；`[juice lint]` 零行 | `target/audit-047-copy-build.txt`、`target/audit-047-copy-test.txt` |
| 成员根冒烟 | `cd packages/juice-plugin-lint && ../../target/juice.exe test` | exit 0；3 passed / 0 failed；`[juice lint]` 零行；无 `target/plugins` | `target/audit-047-member-test.txt` |
| 产物检查 | 副本跑后现场检查 | `target/plugins/registration.jai` 含 `JUICE_PLUGIN_0 :: #import "juice-plugin-lint";`；`target/transpile/first.jai` 含 `#import "juice_core"`、注册 `#load`、`set_working_directory(<root>)`、merge 与 lint 观察调用；E2E 条目 `juice_test_322/323` 已执行；scratch 已清理 | `target/audit-047-artifacts.txt` |

计数口径沿用既有约定：found = max `juice_test_N` + 手写条目（475 + 5 = 480）；终局 `294 passed` 因 Testing 自测段 `finish()` 重置而小于 found；白名单组成自 035/036 起未变。

### 偏差与记录修正

1. **`Lint_Level` 文序零值安全（复查修复 F4）**：最终文序 `WARNING; ERROR; INFO;`（WARNING 零值成员，`Lint_Finding.level` 默认 `.WARNING`），原型与 041 Resolution 的 `ERROR/WARNING/INFO` 表述已作废；面序变更属 pre-release。记录修正不改已关票，以 047 复查修复段与 spec §5.1 为准。
2. **跨包合并位置语义（复查修复 F2）**：043 Resolution 的「跨包复用 `place_scan_hit`（就地替换）」表述已被取代——现为两阶段段合并 + `place_workspace_scan_hit`；低秩胜/同级先者胜/诊断文案不变，胜者保留在其包段位，绝不越过先声明包的幸存命中。
3. **源读取失败响亮化（复查修复 F1）**：`scan_plugin_package` 对不可读源保留诊断并置 `ok=false`，经 `scan_workspace_plugins`/`test_compile_front` 传播为命令失败；Windows 用独占读句柄确定性覆盖，POSIX 分支为空（项目 Windows-first）。
4. **真实仓库根声明面永久回归（复查修复 F3）**：`tests/plugin_scan_tests.jai` 直接经生产 discovery/scan 断言真实根恰 1 命中（`juice-plugin-lint` / `module.jai`）；043/044 的临时驱动不再作为证据面。
5. **生成 metaprogram 的 `package_root` 支撑选项（042 偏差 1）**：收集期 `compiler_report` 需要可打开原始相对路径，故非空注册分支在 `#run` 内先 `set_working_directory(root)`；045 已按对传入。
6. **spawn 缝 `import_dirs`（045 偏差 1）**：顶层 `#import "juice_core"`/`"juice-plugin-lint"` 在子进程初始搜索面解析，故 `spawn_test_compiler` 增 import 目录参数；`-import_dir` 必须位于入口文件之前（`build.jai` 测试程序守卫依赖末参数为 `first.jai`）。
7. **header 坐标实测 1 基（042 偏差 2）**：jai beta 0.2.009 的 `Code_Procedure_Header` 位置字段实测 1 基；换算职责仍在插件，宿主不二次换算，符合「findings 1 基」契约。
8. **lint finding 走 stderr**：`compiler_report` 输出到子进程 stderr，E2E 在 stderr 上断言警告文本与原始路径。

### 未来票

- **安装/打包布局下的第三方插件加载**：`target/modules/juice_core.jai` 以绝对路径 `#load` 开发树 `src/` 闭包；安装布局（exe + `modules/`，无同级 `src/`）无法解析插件面。040 出范围，已登记 spec §11.11。
- **其余插件成员**：`packages/juice-plugin-test` / `juice-plugin-transpile` 未创建（内置 transpile 插件仍静态驻 `src/`）。
- **第三方 hook/transpile 面在 CLI 进程内挂载**：类型同一性约束未变；需新的进程/会话程序架构，独立 effort。
- **lint 规则配置面与后续规则**：选项协议、severity 配置、`--deny-warnings`、规则开关、第二条规则等仍出范围（见本 spec Out of Scope）。
