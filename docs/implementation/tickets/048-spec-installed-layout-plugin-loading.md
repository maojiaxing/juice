---
id: 048
title: 安装布局下的第三方插件加载 spec：自包含插件面发布 + 分发契约
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: []
blocks: []
---

> 上游规格：`docs/spec.md` §9（运行期模块发布）、§11.11（安装布局插件加载未来票）、§3.2/§3.3（成员与 DEP 纪律）、§5.2/§8.2（插件加载与 lint）；ADR 0006（bootstrap 构建剥离内联 test 块，test-free 闭包纪律）。
> 来源：047 收尾登记的「未来票」第一项；040 的 Out of Scope 与 spec §11.11 的登记。测试接缝经用户确认：两接缝（publication 姊妹测试 + 真安装布局 E2E）。
> 参照面（只读）：`src/publication.jai`、`build.jai` 的发布步骤、`src/test_metaprogram.jai` 的注册分支、`src/commands/test.jai` 的 COMPILE 前端、`src/dependency.jai`、`packages/juice-plugin-lint/`、`tests/publication_tests.jai`、`tests/test_command_tests.jai`、`tests/bootstrap_tests.jai`。

## Problem Statement

工具已经承诺「可执行文件 + 相邻 `modules/` 目录」即可运行（037/039 的安装布局契约：exe 只依赖自己的 modules 目录，不依赖同级 `src/`），无插件工作区也确实如此。但第三方插件加载从未在这个布局下成立：

1. **插件面闭包指向开发树**：发布的 `juice_core.jai` 以绝对路径 `#load` 构建机 `src/` 下的四个文件（transpile / transpile_plugin / lifecycle / plugin）。安装布局没有 `src/`，换机器、移动目录或归档构建树后，一旦工作区有插件注册、生成的测试 metaprogram `#import "juice_core"`，该闭包就无法解析，测试程序编译失败。
2. **现有测试发现不了泄漏**：既有安装布局 E2E 只跑无插件 fixture，`juice_core` 分支从未被编译；在同一台构建机上，绝对路径仍指向存在的开发树，所以即使跑插件工作区也会"碰巧通过"。没有任何断言禁止发布产物携带绝对路径。
3. **分发包携带错误的依赖**：真实成员包 `packages/juice-plugin-lint` 声明 `DEP juice_core source="../../"`。这个相对路径只在 juice 仓库内部成立；包被复制到用户工作区后，该 DEP 指向用户的上级目录，prep 可能写出错误 shim 或依赖 CWD 解析失败。更糟的是，它会指向 `src/module.jai`（定义源），而该文件不携带插件面类型；今天之所以能跑，只是因为 `<exe>/modules` 在导入路径上排在 shim 之前，把错误 shim 遮蔽了。分发契约因此从未被定义：插件包到底依赖什么、工具提供什么，没有权威答案。
4. **成员包的可分发性未被证明**：没有测试证明「把真实成员包源码复制进任意工作区，用安装版 juice 跑根测试与成员自身测试」可行。

具体 trace：把 `target/juice.exe` 与 `target/modules/` 复制到干净目录，准备一个声明该成员的工作区与一个坏命名的 `@test`；`juice test` 写入注册文件，metaprogram `#import "juice_core"`，后者 `#load "C:/…/otter/src/transpile.jai"`——在构建机之外，这四个目标不存在，编译失败，lint 与测试都不发生。

## Solution

把插件面闭包变成**发布产物的一部分**，让 `juice_core` 自包含，并定义成员包源码的分发契约：

- 发布的插件面闭包 = 四个源文件的**逐字复制件**，落在 `<modules>/juice_internal/plugin_face/`；`juice_core.jai` 以模块相对路径 `#load "juice_internal/plugin_face/<file>"` 加载它们。发布产物中不再出现任何构建机绝对路径。
- 受支持的安装 = 可执行文件 + 相邻 `modules/` 目录（递归包含 `juice_internal/`）。不新增安装命令或归档格式；复制这对产物就是契约。零插件工作区行为与生成文本逐字节不变。
- 分发契约 = **`juice_core` 是工具提供的模块面，不是工作区依赖**。插件包是普通的、可复制的源码成员包，按名 `#import "juice_core"`，由已安装工具在 `<exe>/modules` 提供解析。规范成员包删除 `DEP juice_core source="../../"`。
- 新增真安装布局 E2E：复制 exe + modules 到无 `src/` 的 scratch 安装，驱动含真实成员的 scratch 工作区，断言 lint 警告、测试照常运行、exit 0；并用同一安装版 exe 在复制出的成员根跑其自身套件。同时断言发布的 `juice_core` 只含相对 `#load`、每个加载目标都在安装内、无开发树路径。

## User Stories

1. As a tool installer, I want the supported install to be the executable plus its adjacent modules directory, so that I can deploy juice without a source checkout.
2. As a tool installer, I want to copy that pair to any machine and any path, so that build-machine absolute paths never leak into the install.
3. As a tool installer, I want neither `src/` nor `target/` required next to the executable, so that the install stays minimal.
4. As a tool installer, I want a partial install to fail loudly rather than silently disable plugins, so that deployment mistakes are visible.
5. As a workspace author, I want a plugin-using workspace to test green under an installed juice, so that plugin activation does not require the juice repository.
6. As a workspace author, I want zero-plugin workspaces to behave exactly as today, so that the install upgrade changes nothing for them.
7. As a workspace author, I want plugin activation to stay `workspace.members` plus the same-name root dependency, so that no new declaration protocol is introduced.
8. As a workspace author, I want plugin packages to be plain source packages in my workspace, so that I can vendor or copy them.
9. As a workspace author, I want lint findings under an installed juice, so that plugin diagnostics are not a dev-tree-only feature.
10. As a plugin author, I want `#import "juice_core"` to resolve from the installed tool, so that my package needs no path to a juice checkout.
11. As a plugin author, I want my package manifest to declare no `juice_core` dependency, so that my package is portable across workspaces.
12. As a plugin author, I want my package to remain a normal LIB member with a test-free root module, so that it builds and tests like any other package.
13. As a plugin author, I want my package's own tests to run under the installed executable, so that I can validate the plugin independently.
14. As a plugin author, I want `juice_core`'s types to come from one name-imported module inside the test program, so that type identity stays unified.
15. As a plugin author, I want the installed plugin face to be the same code as the dev tree, so that behavior cannot diverge.
16. As a plugin author, I want a stable `juice_core` import name, so that package sources never change for install reasons.
17. As a plugin author, I want no dependency on a specific juice checkout path, so that the same package works in any team's workspace.
18. As a test author, I want lint warnings under an installed juice, so that the shipped rule follows the tool everywhere.
19. As a test author, I want warnings to keep exit code 0, so that advisory lint never breaks CI.
20. As a test author, I want a badly named test to still run and count, so that lint and execution stay separate.
21. As a test author, I want findings to name the original package-relative path and 1-based coordinates, so that I can jump to the source.
22. As a test author, I want pattern filtering to keep hiding nothing from lint, so that filtering never suppresses warnings.
23. As a CI operator, I want an install that works on a clean machine with only the jai compiler and the install pair, so that CI does not need the repository.
24. As a CI operator, I want the installed E2E to drive the real executable, so that the shipped artifact is what gets proven.
25. As a CI operator, I want the no-plugin installed path to stay covered, so that both layouts are exercised by the same contract.
26. As an otter developer, I want the published `juice_core` to load its closure by module-relative paths, so that relocation is safe.
27. As an otter developer, I want the closure files copied verbatim, so that source and install can never drift semantically.
28. As an otter developer, I want one file list to drive both generation and copying, so that a new closure member cannot be added to only one side.
29. As an otter developer, I want a missing closure source to fail the build before any write, so that no partial artifact set lands.
30. As an otter developer, I want the test-side publisher to produce the same artifact set, so that tests exercise the real install shape.
31. As an otter developer, I want byte pins for the copied artifacts, so that an accidental transform fails loudly.
32. As an otter developer, I want the published `juice_core` text contract pinned, so that the relative form cannot regress silently.
33. As an otter developer, I want an assertion that no published artifact contains the build root, so that a dev-tree leak cannot pass on a machine that happens to have the tree.
34. As an otter developer, I want an assertion that every `#load` target exists under the install, so that a partial copy is caught.
35. As an otter developer, I want the installed executable to run the copied member root green, so that the distribution contract is exercised end to end.
36. As an otter developer, I want the canonical member to drop the dev-tree `juice_core` dependency, so that it is copyable unchanged.
37. As an otter developer, I want the member-root suite to keep passing after that removal, so that the tool import path is proven sufficient.
38. As an otter developer, I want the self-host bootstrap to publish the new artifact set, so that dev and installed layouts share one shape.
39. As an otter developer, I want the debug/release build and copy-run matrix green, so that the change does not regress the tool.
40. As an otter developer, I want the zero-plugin metaprogram to stay byte-identical, so that non-plugin packages are untouched.
41. As an otter developer, I want the Jai relative-`#load` fact recorded, so that future publication work does not re-litigate it.
42. As an otter developer, I want the plugin face copies to live under the private internal namespace, so that no new public import API is introduced.
43. As an otter developer, I want spec §9 and §11.11 folded back at closeout, so that the design spec matches executed reality.
44. As an otter developer, I want the old-juice exit declaration updated, so that it no longer lists a stale future ticket.

## Implementation Decisions

1. **安装布局契约**：受支持的安装 = 可执行文件 + 相邻 `modules/` 目录（递归包含 `juice_internal/`）。安装不要求、也不读取同级 `src/` 或 `target/`。不新增 install/package 命令、归档格式或环境变量；复制这对产物即契约。`modules_dir = <exe>/modules` 推导不变（spec §9.3）。
2. **自包含 `juice_core`**：生成的 `juice_core.jai` 以模块相对路径 `#load "juice_internal/plugin_face/<file>"` 加载四个闭包件；文件中不得出现绝对路径、盘符或构建根路径。两个内置 plugin id 常量仍从定义源逐字抽取，不变。
3. **闭包件逐字发布**：四个闭包件从定义源逐字复制到 `<modules>/juice_internal/plugin_face/`，无变换（与内部发现源件同款单源证明）；每次 build 重生，字节相等即契约。缺源或不可读 = 发布失败。
4. **单一文件清单**：既有 `JUICE_CORE_LOAD_FILES` 同时驱动 `juice_core` 的 `#load` 行与四个复制件的落点。生成器与复制步骤共享同一清单与同一相对目录常量，使「新增闭包件只改一边」不可能发生。
5. **Jai 事实（本轮 spike 钉）**：`#load` 在按名导入的模块内部按**包含该指令的文件目录**解析。探针：`mods/sub/M2.jai` 内 `#load "face/deep.jai"` 命中 `mods/sub/face/deep.jai`（值 1），不命中 `mods/face/deep.jai`（值 2）。相对加载形态以此为依据；未来发布工作不得重新引入绝对路径。
6. **落点助手**：新增以 `<modules_dir>` 为参数的插件面目录与文件落点助手（与既有内部源件助手同形）。消费侧只知道 `<exe>/modules`；生产侧先由 `<target>` 推导 `<target>/modules`。生成器不再接受构建机 `src` 目录参数。
7. **读后写纪律**：build 的发布步骤在写任何文件前读取定义源、发现面源与四个闭包件；任一失败 exit 1，不落半套。三份模块面、内部发现源件与四个闭包件在同一批次落位。
8. **测试侧发布器平价**：测试支持中的 `ensure_published_modules` 使用同一生成器、同一文件清单、同一落点助手发布完整产物集（三份模块面 + 内部发现源件 + 四个插件面闭包件）。不得出现第二份文件清单。
9. **分发契约**：插件包 = 工作区内的普通源码包；`juice_core` 是**工具提供的模块面**，由 `<exe>/modules` 在每个编译子进程的导入路径上解析（既有 `compiler_import_directories` 已把它置于首位，不新增解析代码）。插件包不声明 `juice_core` 依赖，也不需要 juice 检出。规范成员 `packages/juice-plugin-lint` 删除 `DEP juice_core source="../../"` 及相应注释；工作区激活面仍是 `workspace.members` + 根同名 DEP，零协议扩展。
10. **成员包形态不变**：LIB、根部 test-free `module.jai`、自身测试驻 `tests/`、成员根可作为自身 root 构建与测试。删除 DEP 后成员根套件仍全绿（工具导入路径已足够），并且可在安装布局下运行。
11. **零插件字节不变**：无插件注册时生成的测试 metaprogram 与今天逐字节相同；插件面复制件只在注册非空时被导入，零插件工作区没有额外导入或编译成本。
12. **失败语义**：安装缺任一插件面闭包件时，有插件的测试程序在编译期响亮失败（jai 原始错误），不得降级为「无插件」；零插件工作区不受影响。构建期缺闭包源则发布失败。
13. **编译面零协议扩展**：manifest 协议、`Package` 字段、命令面、lifecycle 阶段枚举均不变；不新增公开 import 面。`juice_internal/plugin_face/` 是 `#load` 专用私有目录；其导入可见性仍是约定而非强制（与既有 `juice_internal/` 同款）。
14. **旧绝对路径形态退役**：发布器不再生成 `src` 绝对路径形态；`juice_core` 生成文本的头注释改写为相对路径与来源说明。既有文本 pin 随票更新，不保留双形态。
15. **文档折回（closeout）**：`docs/spec.md` §0（生成件清单与目录树）、§3.2/§3.3（成员描述与分发契约）、§9.2（产物集与相对加载）、§11.11（处置）；`old-juice-exit.md` 的 §4/§5 对应行。040/047 为已关票不改，记录修正写入本票 Resolution。
16. **兼容性**：旧 juice 仓零改动；兄弟项目不动；Windows-first（POSIX 安装面不在本轮承诺）。测试只使用会话产物目录，运行后清理。

## Testing Decisions

**好测试的标准**：只钉外部行为——给定源文本得到确定的发布文本；给定发布目录得到确定的文件集合与逐字节内容；给定真实安装与真实工作区得到可观察的输出、stderr 与退出码。不测私有助手，不按内部调用序断言。测试计数不预钉绝对值，按既有约定记录 found/passed/白名单。

**接缝 1（姊妹测试，进程内；既有文件 `tests/publication_tests.jai`）**：
- 生成器文本：fake 源得到固定的相对 `#load` 行与更新后的头注释；缺失 id 常量仍响亮失败。真实源的 `juice_core` 文本 pin 更新为相对形态。
- 单源复制件：经 `ensure_published_modules` 发布后，四个闭包件与 `src/` 同名源逐字节相等；任一缺源时发布失败。
- 既有 publication smoke E2E 更新：在缓存目录写出新的 `juice_core` 布局（含 `juice_internal/plugin_face/` 四件），由真实 jai 子进程在裸导入下编译并跑通。它同时证明相对加载的真实解析。
- 先例：既有 publication 的 fake/real 文本 pin、内部发现源件的逐字节 pin、publication smoke E2E。

**接缝 2（全链安装布局 E2E，真子进程；既有文件 `tests/test_command_tests.jai`）**：
- 搭建 scratch 安装：复制真实 exe 与 `target/modules` 整棵树（递归包含插件面复制件），断言安装内没有 `src/`。
- 安装产物契约：`<install>/modules/juice_core.jai` 只含相对 `#load`；不出现构建根/盘符/绝对路径；每个 `#load` 目标都存在于安装内；四个闭包件齐全。
- scratch 工作区：根清单（`workspace.members` + 同名 DEP）、从真实成员包逐字节复制出的完整包树（含 `tests/`）、一个坏命名的 `@test`。安装版 exe 在根跑 `test`：exit 0；stdout 含两个测试照常执行与 `0 failed`；stderr 含 `[juice lint]` 警告、原始包相对路径与坐标。
- 同一安装版 exe 在复制出的成员根跑 `test`：exit 0，成员自身测试全绿。
- 既有「无插件安装布局」E2E 保持全绿，证明两条路径共享同一布局。
- 先例：037 的安装布局 E2E、046 的真实成员 lint 全链 E2E、047 的成员根冒烟。

**接缝 3（验收矩阵，非新测试文件）**：`jai build.jai` debug/release 各 exit 0；产物副本于根 build/test 全绿（SKIP 0、白名单恰 6 行、无新增失败）；真实成员根 test 全绿；接缝 2 的安装布局全链全绿。`tests/bootstrap_tests.jai` 的已发布产物逐字节 pin 随新产物集更新（既有测试）。

## Out of Scope

- 安装/打包命令或归档格式（install、zip、发布流水线）；本轮只定义布局契约与测试。
- 非成员插件包（git/本地外部依赖）的扫描与分发；激活面仍限工作区成员 + 根 DEP。
- 第三方 hook/transpile 面在 CLI 进程内挂载（类型同一性约束未变，需新的进程/会话架构）。
- 其余插件成员（`juice-plugin-test`/`juice-plugin-transpile`）与内置 transpile 迁移。
- lint 规则配置面：severity、`--deny-warnings`、规则开关、后续规则。
- test 显示名恢复（`@test("name")`）、`at` 其余 9 个挂载点、jaix PRESTEP 全链。
- 插件面 API 的版本兼容承诺、插件面复制的缓存/增量优化。
- POSIX 安装布局（项目 Windows-first）；旧 juice 仓任何改动；兄弟项目不动。

## Further Notes

- **为什么用逐字复制而非拼接**：把四个文件拼成单文件需要去重 `#import`、处理文件作用域与来源行号，破坏单源与行号保真；逐字复制沿用内部发现源件的既有形态，且四个文件本就 test-free（bootstrap 闭包纪律，ADR 0006），无需转译。
- **为什么不用「安装时携带 src/」**：那会把开发树变成发布面，违背 037/039 的安装布局契约，并让插件加载依赖源代码目录结构。
- **相对加载的边界**：相对路径以 `juice_core.jai` 自身所在目录为基准；消费侧必须经 `#import "juice_core"` 从 `<exe>/modules` 解析，不能把该模块复制到其他目录单独使用。E2E 同时钉住模块位于安装 modules 根、四个目标位于其邻接子目录。
- **陈旧产物风险**：build 每次重生全部发布件；测试侧发布器同样重生。E2E 在运行前删除 scratch 安装与工作区，避免旧副本掩盖缺失的复制逻辑。
- **根工作区不会重复收集成员测试**：根发现排除成员目录；复制进工作区的成员 `tests/` 只在该成员根运行时被收集。
- **闭包件私有性**：`juice_internal/plugin_face/` 与 `juice_internal/` 同为约定私有的 `#load` 目标；编译器导入路径仍可见该目录，这是既有且被接受的事实。
- **语言与纪律**：交流中文；实现遵守 `CLAUDE.md`（读全文件、无 `*void` 滥用、`.{}` 字面量、内联单调用助手）；测试组织遵守既有规则（库面 test-free、姊妹测试文件）。

## Resolution

**交付摘要**（2026-10-21）：安装布局下的第三方插件加载已全部交付。发布的 `juice_core.jai` 自包含——四行模块相对 `#load "juice_internal/plugin_face/<file>"`，四个闭包件由 `src/` 逐字复制到 `<modules>/juice_internal/plugin_face/`，发布树不含任何构建机路径、可整体搬迁；`juice_core` 定义为工具提供的模块面（`<exe>/modules` 在每个编译子进程导入路径第一顺位解析），规范成员包 `packages/juice-plugin-lint` 删除 `DEP juice_core source="../../"`，成为零依赖、可原样复制的源码成员；受支持安装 = 可执行文件 + 相邻 `modules/`（递归含 `juice_internal/`），不要求也不读取同级 `src/`/`target/`。真安装布局全链 E2E 用真实 exe + 完整 `modules/` 树驱动含真实成员的 scratch 工作区（lint 警告、测试照常执行、exit 0），同一安装版 exe 在复制出的成员根跑其自身套件全绿；既有零插件安装布局 E2E 保持全绿。子票 049（自包含发布）、050（成员分发契约）、051（安装布局 E2E）、052（文档折回 + 验收矩阵）全部关闭。

**逐决定结果（1-16）**：

| # | 决定 | 结果 |
| --- | --- | --- |
| 1 | 安装布局契约（exe + 相邻 `modules/`，无同级 `src/`/`target/`；无 install 命令/归档/环境变量） | 兑现。E2E `juice_test_328` 断言 scratch 安装内及 exe 邻接层无 `src/`/`target/`；既有零插件 `juice_test_320` 同布局全绿（三次套件跑均出现）。 |
| 2 | 自包含 `juice_core`（四行相对 `#load`，无绝对路径/盘符/构建根；常量逐字抽取） | 兑现。`target/modules/juice_core.jai` = 16 行，仅四行相对加载，禁形扫描零命中（`audit-052-07`）；文本 pin 驻 `tests/publication_tests.jai`。 |
| 3 | 闭包件逐字发布（四件从 `src/` 无变换复制；缺源 = 发布失败） | 兑现。052 复核四件与 `src/` 逐字节相等（571/553/243/380 行）；构建侧缺源 exit 1 零残留、测试侧 `ensure_published_modules()` 返回 false（049 姊妹/自举测试）。 |
| 4 | 单一文件清单（`JUICE_CORE_LOAD_FILES` 同时驱动 `#load` 行与落点） | 兑现。生成行与复制落点共享清单及 `juice_internal/plugin_face/` 目录常量（`src/publication.jai`；无第二份清单）。 |
| 5 | Jai 事实：`#load` 在按名导入模块内按包含文件目录解析 | 兑现并记录。spec §9.2 写入该事实；publication smoke 在裸导入下真实编译相对加载；E2E 328 在安装内解析四目标。 |
| 6 | 落点助手以 `<modules_dir>` 为参数；生成器不再接受 `src` 参数 | 兑现。`juice_plugin_face_dir` / `juice_plugin_face_file_path` 同族；`publish_juice_core(module_source)` 无 `src_dir` 实参。 |
| 7 | 读后写纪律（先读六源，任一失败 exit 1，不落半套） | 兑现。`build.jai` 发布步骤读定义源、发现源、四闭包源后才写；缺源自举 E2E 断言零残留（049）。 |
| 8 | 测试侧发布器平价（同生成器/清单/落点助手，发布完整产物集） | 兑现。`tests/test_support.jai` 的 `ensure_published_modules` 发布三模块面 + 发现源 + 四闭包副本；052 每次 build/test 后产物集恒为八件。 |
| 9 | 分发契约（插件包普通源码；`juice_core` 工具提供；成员零依赖；激活面不变） | 兑现。`packages/juice-plugin-lint/package.jai` 零依赖；`juice_test_199` 钉住依赖集为空；根激活面仍 `workspace.members` + 同名 DEP。 |
| 10 | 成员包形态不变（LIB、test-free 根、`tests/`、成员根可自跑） | 兑现。052 成员根冒烟 exit 0、3 passed / 0 failed（`audit-052-06`）。 |
| 11 | 零插件字节不变（metaprogram 生成文本不变） | 兑现。049 未编辑 `src/test_metaprogram.jai`，其字节锁测试全绿；052 全矩阵绿。 |
| 12 | 失败语义（缺闭包件 = 有插件测试程序编译期响亮失败，不降级） | 兑现。发布缺件走 jai 原始编译错误路径；构建/测试侧发布缺源独立失败（049 测试），无「无插件」降级分支。 |
| 13 | 编译面零协议扩展（manifest/Package/命令/lifecycle 不变；无新公开 import 面） | 兑现。049-051 未改协议面；`juice_internal/plugin_face/` 为约定私有 `#load` 目录。 |
| 14 | 旧绝对路径形态退役（生成器不再生成；文本 pin 更新） | 兑现。生成器无绝对路径分支；052 产物扫描零构建根；旧形态无残留。 |
| 15 | 文档折回（spec §0/§3.2/§3.3/§9.2/§11.11；old-juice-exit §4/§5） | 兑现（052）。spec §0 生成件/目录树/安装契约、§3.2/§3.3 成员与分发契约、§5.2 引用形态、§9.2 产物集与相对加载与行数、§9.6、§10 阶段 2/3 与接缝 1、§11.11 与终态处置、old-juice-exit §4 覆盖表与 §5 风险表均已折回；040/047 已关票正文未改。 |
| 16 | 兼容性（旧 juice 仓与兄弟项目零改动；Windows-first；测试只使用会话产物目录） | 兑现。本 effort 未触碰旧 juice 仓/兄弟项目；E2E scratch 均在 `target/` 下并在运行前后清理；成员根 `target/` 冒烟后清理。 |

**验收矩阵**（052，2026-10-21，串行；每次 test 前清 `target/transpile` / `target/testing-module` / `target/plugins`；证据 `otter/target/audit-052-*.txt`）：

| 步骤 | 命令 | 结果 |
| --- | --- | --- |
| 1 | `jai build.jai` | exit 0（`audit-052-01-build-debug.txt`） |
| 2 | `target/juice.exe test`（debug） | exit 0；**485 found**（`juice_test_N` 最大编号 480 + 手写 `note_suite_*` 5）；298 passed / 0 failed；`expect failed` 恰 6 行白名单；**SKIP 2**（bootstrap 自锁；`audit-052-02-test-debug.txt`） |
| 3 | `jai build.jai - release` | exit 0（`audit-052-03-build-release.txt`） |
| 4 | `target/juice.exe test`（release） | exit 0；同步骤 2：485 found、298 passed、白名单 6、SKIP 2（`audit-052-04-test-release.txt`） |
| 5 | `cp target/juice.exe target/juice-copy.exe`；`target/juice-copy.exe build`；`target/juice-copy.exe test` | build exit 0；test exit 0；**485 found**、298 passed / 0 failed、白名单 6（与直跑逐行相同）、**SKIP 0**（权威，`audit-052-05-copy-build.txt` / `audit-052-05-copy-test.txt`） |
| 6 | 成员根冒烟：清 `packages/juice-plugin-lint/target`；成员根 `../../target/juice.exe test`；事后清理 | exit 0；成员自身 **3 passed / 0 failed**（`audit-052-06-member-root-smoke.txt`） |
| 7 | 安装产物检查：`target/modules/juice_core.jai` 仅相对 `#load`；四件存在且与 `src/` 逐字节相等；无构建根/盘符/反斜杠；每个目标在发布树内 | 全部通过；产物集 = 三模块面 + 发现源 + 四闭包副本共八件；行数 131 / 237 / 16 / 285 / 571 / 553 / 243 / 380（`audit-052-07-artifact-inspection.txt`） |
| 8 | 套件内 E2E 证据：`juice_test_328`（安装布局插件全链）与 `juice_test_320`（无插件安装布局） | debug / release / copy 三次跑各出现一次，套件终局均 0 failed；直跑 SKIP 仅 bootstrap 两行（`audit-052-08-suite-e2e-evidence.txt`） |

**偏差与记录修正**（无遗留缺陷）：

1. **行数订正**：`juice_core.jai` 由旧绝对路径形态的 12 行变为相对加载形态的 **16 行**；spec §9.2 与 old-juice-exit §4 的「131 / 237 / 12」已就地订正为「131 / 237 / 16」，并补记四闭包副本行数。049 Resolution 未记录绝对行数，无冲突。
2. **旧文档措辞订正**：spec §0 的成员 DEP 与发布清单、§3.3 的「成员引根 = 异名 DEP」、§5.2 的引用形态、§9.6 与 §10 阶段 2/3 验收行的产物集表述均在 052 按 048 决定 15 折回；§11.11 由未来票改为已交付。040/047 已关票正文未改，记录修正留在本 Resolution 与 052 Resolution。
3. **计数口径**：found = max `juice_test_N`（480）+ 手写 `note_suite_*`（5）= **485**；终局 `298 passed` 是 Testing 自测 `finish()` 重置后的计数，不等于 found（既有约定）。白名单 6 行与 051 逐行相同，无新增失败。
4. **SKIP 口径**：直跑 2（bootstrap 自锁 = 环境条件形态）、副本跑 0（权威）；无其他跳过。
5. **成员根噪音**：冒烟输出 `Unable to open directory .../packages/juice-plugin-lint/modules` 是 `visit_files` 对不存在目录的既有噪音（051 偏差 4 同款），与结果无关（exit 0、3 passed）。
6. **未新增安装命令**：契约仍为复制 exe + `modules/` 这对产物（决定 1）；归档/安装器/发布流水线保持出范围。

**生产代码与测试**：相对 051 终态零改动（本票只改文档与验收记录）；049-051 票面未改；父 spec 正文除本 Resolution 与 frontmatter 状态外未改。
