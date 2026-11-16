# juice（otter）设计规格

> 本规格 = 全部研究文档的终态综合（2026-10-19 定稿）。决策即规格，不给选项；每条标注证据出处。研究文档缩写：**R** = `docs/research/otter-refactor-research.md`；**A** = `docs/research/plugin-auto-discovery.md`；**L** = `docs/research/plugin-lifecycle-hooks.md`；**N** = `docs/research/note-based-testing.md`；**C** = `docs/research/cargo-style-monorepo.md`。实验标注：`A-E1/E2`（无运行期顶层执行）、`C-mono`（monorepo 端到端）、`C-E1..E7`（混合 lib/bin 与命名碰撞）、`N-exp`（note 枚举）。
> 命名定稿：**工具名 = juice**（重构版以 juice 名义交付）；otter = 开发代号/目录名（研究文档沿用代号，交付面一律 juice）。
> 废弃立场注明格式：「**已废弃**（原出处）」一句话。
>
> **设计修订（2026-10-21，jaix-plugin effort）**：插件声明面从 `jaix` 标记 + `transpile.plugins` 硬切为单一 `Package.plugins`（id + version + options）；声明即可用、激活、配置与排序。jaix 前置改为 PRESTEP `before` 插件：Phase 1 = 静态内置 `juice-plugin-jaix`，Phase 2 = `packages/juice-plugin-jaix/` 成员包 + PRESTEP-only plugin host。`Package.jaix`、`Package.transpile`、`JAIX_CONFIG/JAIX_EXE/TRANSPILE_PLUGIN` 协议记录与两道旧校验门移除；属 breaking change（§2.1/§2.2/§2.3/§11.12）。本修订的执行状态 = **执行级现实（2026-10-21，062 收口）**：`docs/implementation/jaix-plugin-map.md` 的 054-062 票全部交付并关闭——声明/协议硬切（055）、options/registry/resolver（056）、PRESTEP 阶段与源替换表（057）、静态 jaix 插件（058）、Phase 1 守卫（059）、PRESTEP-only plugin host（060）、`packages/juice-plugin-jaix` 成员包 + 安装布局 E2E（061）；`src/` 零 jaix 引用、守卫白名单为空；各节内以「设计修订（2026-10-21）」标记改动点，以「执行级现实（2026-10-21，…）」标记已落地形态。
>
> **设计修订（2026-10-22，testing 迁移 effort，未实施）**：测试库面（Testing 断言模块、两套 test-block 转换、测试发现面）迁入仓库根独立包 `testing/`，juice 只保留集成接口/协议。已定决策（0066/0067）与进行中/待定项（0068/0075）见 `issues/0065-map-test-migration-to-testing-package.md` 与 §13；**实施尚未开始**，落地前各章节仍以当前实现为准。

> **设计修订（2026-11-15，package-declaration-semantics effort）**：包声明面按 `issues/0087-spec-package-declaration-semantics.md` 的 29 条实施决策重写，**§2 整节以新语义为准**。旧字段 `type`、`targets`/`main_file`、依赖 `version`/`package` 搜索、插件成员名猜测/`version`、`build_script` 已从公开面删除并在求值或校验期被拒绝，不保留兼容解析、不自动改写；`workspace` 保留为 `Package` 的普通嵌套字段，并获得 `default_members` 与单层 `*` 成员匹配。本文其余章节中描述旧声明面（互斥 LIB/BIN 角色、`Target` 名单、按包名解析依赖、插件声明 version 门、传递依赖需重复声明）的语句均以 §2 与 `docs/migrations/package-declarations.md` 为准；转译、测试、lifecycle、发布与自举章节未因本 effort 改变。逐字段迁移表、E01–E10 完整人工迁移示例、A01–A16 验收对照与运行证据见 `docs/migrations/package-declarations.md`。

## 0. 方案概要

juice 重构版：cargo 式 monorepo 仓库（根包 + `plugins/` 插件包），四阶段自举。内置命令 = build/clean/run/test/update/version/help（七命令；update 由 0091 加入，其余用户定稿 2026-10-19，§4.1）；test 用 `@test` 注记发现（metaprogram 消息循环枚举 + 生成显式调用表）；插件 = transpile/lint（+ test 五 at 钩子覆盖面），第三方插件经构建工具侧扫描标记 → 生成显式有序注册文件；**设计修订（2026-10-21）**：插件声明面统一为 `Package.plugins`（id + version + options），声明即激活/配置/排序；成员插件 id = 成员包名，根 `dependencies` 不再承担插件激活面；jaix 前置 = `juice-plugin-jaix` 的 PRESTEP 插件（Phase 1 静态内置；执行级现实 2026-10-21，061 起 Phase 2 成员包 + PRESTEP-only host 已交付）；**执行级现实（2026-10-21，040 收尾）**：真实第三方成员 = `packages/juice-plugin-lint`（lint，全链已交付）；内置 transpile 插件仍静态驻 `src/`，`juice-plugin-test`/`juice-plugin-transpile` 成员未创建；lifecycle 挂载 = 阶段枚举 + before/at/after + 声明序确定性 + 显式 ctx；运行期发布 = 三份模块面 `target/modules/Juice/module.jai`（大写目录模块）+ `Testing.jai` 平铺 + `juice_core.jai` 生成模块 + 一份内部发现源件 `target/modules/juice_internal/test_discovery.jai`（`src/test_discovery.jai` 逐字复制；私有目录契约——只被生成的测试 metaprogram 以绝对路径 `#load`，不发布为公开 import 面（编译器导入路径仍可见该目录，非强制不可导入）；执行级订正 2026-10-20，阶段 3 终态）+ 四份插件面闭包副本 `target/modules/juice_internal/plugin_face/{transpile,transpile_plugin,lifecycle,plugin}.jai`（`src/` 同名源逐字复制，`juice_core.jai` 以模块相对路径 `#load`；发布树可整体搬迁；2026-10-21，048 收尾，§9）；安装契约 = 可执行文件 + 相邻 `modules/` 目录（递归含 `juice_internal/`），不要求也不读取同级 `src/`/`target/`；插件引根 = 工具提供的模块面 `juice_core`（由 `<exe>/modules` 在每个编译子进程的导入路径上解析，插件成员不声明该依赖，§3.3）。

```
juice/（开发代号 otter）                 # 工作区根 + 根包（juice 工具）
├── package.jai                         # name="juice"；workspace.members 逐条列举（juice 无 glob）
├── src/module.jai                      # #load 两处发布源 + Testing 面自测（不发布；名字是 §5.2 入口探测约定路径，故不改）
├── packages/juice/module.jai           # 发布源目录：Package 兼容面 + 插件声明（无 package.jai，不是包）
├── packages/juice/testing.jai          # 发布源目录：Testing API 定义面（prefixed 公开名；无 @test）
├── src/main.jai                        # CLI（target juice → juice.exe）
├── plugins/juice-plugin-lint/          # juice 自家的 lint 插件包（零依赖——juice_core 由工具提供；v1 lint 规则）
│                                       # （内置 transpile 插件静态驻 src/；test/transpile 插件成员未创建）
├── plugins/juice-plugin-jaix/          # juice 自家的 PRESTEP 插件包（061 交付；Phase 1 的 src/jaix_plugin.jai 已删除）
├── tests/                              # 根包测试
├── build.jai                           # 阶段 2 自举 metaprogram（ADR 0006 全套 + modules 发布步骤）
└── docs/
（生成件：target/modules/Juice/module.jai + target/modules/Testing.jai + target/modules/juice_core.jai + target/modules/juice_internal/test_discovery.jai + target/modules/juice_internal/plugin_face/{transpile,transpile_plugin,lifecycle,plugin}.jai（四份逐字副本，被 juice_core 以模块相对路径 #load）；modules_dir = <exe>/modules；安装 = exe + 相邻 modules/（无同级 src/ 或 target/））
```

自举四阶段：0 = juice（旧）构建/测试本仓库零特判 → 1 = 实现 build+clean+test 内置 + 插件加载（LNK1104 exe 副本纪律）→ 2 = `build.jai` metaprogram 接管自构建 + modules 发布 → 3 = juice 自构建自测、note-based test 零改写接管、旧 juice 退场。

---

## 1. 目标与设计原则

1. **juice 声明接口不变式**：公共模块名 `"Juice"` 与唯一 `PACKAGE` 入口保持不变——模块名是 load-bearing 的（R§1.2、C§7 E3 双面并存验证）。**字段面按 §2 的 2026-11-15 修订**：旧的互斥 `type`/`targets`/`main_file` 与依赖/插件旧字段被删除并拒绝，属于 breaking change；不保留声明级兼容开关。。**设计修订（2026-10-21）**：字段级兼容例外——`jaix` 与 `transpile` 两个字段硬切为 `plugins`（breaking change，§2.1/§11.12）；其余 Package 字段不变。
2. **确定性**：一切收集/派发/执行的顺序由固定规则给定（扫描 DFS 词法序 C§2/scan_walk；声明序 = 管线序 R§2.2；note 收集排序 N§3.2；阶段序硬编码 L§4.3）。
3. **逐字节/逐行保真**：转译视图「1 行换 1 行 + 以 token 为界」（ADR 0005，R§2.2、A§4.3 转引）；注记/注释在非编辑行原样幸存（N§3.3）。
4. **test-free bootstrap 闭包**：bootstrap `#load` 集必须 test-free 且随仓库分发（R§5.1；L§5.1）——内置骨架静态、第三方插件永不进闭包。
5. **零特判**：juice（旧）对 otter 目录的任何操作不依赖旧工具特判（R§5.3 阶段 0）。
6. **失败即停 + 无部分状态**：任一阶段/钩子失败 → 命令失败 → 退出码；prepare「全部成功才发布」、clean「先全量校验后删除」（L§1.2/§1.5）。
7. **Windows-first**：所有机制在 Windows 已验证（LNK1104 副本、`cmd /c`、子进程 CWD 绝对路径、大小写近匹配拒绝——C§7）。

## 2. 包声明规格（2026-11-15 修订，权威）

本节是 `issues/0087-spec-package-declaration-semantics.md` Implementation Decisions 1–27 的可观察契约。逐字段迁移表、E01–E10 完整人工迁移示例、A01–A16 验收对照及运行证据见 `docs/migrations/package-declarations.md`；本节只陈述最终语义，不重复示例。

### 2.1 公开声明面

唯一入口仍是 `package.jai` 里的 `#import "Juice"` + `PACKAGE :: Package.{...}`。不新增 `Manifest`/`Some`/`Configured_List` 包装、用户 presence 开关或独立 `WORKSPACE` 入口；辅助常量与纯编译期表达式允许，只有 `PACKAGE` 参与声明读取。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `name` / `version` | `string` | 包存在时必填且非空。`name` 语法 `[A-Za-z0-9][A-Za-z0-9._-]*`；`version` 是包元数据，不是依赖版本约束 |
| `description` | `string` | 可选，允许显式空 |
| `modules` | `[] Product` | 公开导入模块清单；`Product {name, entry}` |
| `executables` | `[] Product` | 可执行产物清单；同一 `Product` 类型 |
| `dependencies` | `[] Dependency` | 普通依赖的统一清单，模块/程序/测试共用；`Dependency {name, source, modules}` |
| `plugins` | `[] Plugin_Declaration` | 插件启用/配置/顺序面；`Plugin_Declaration {id, builtin, source, module, options}` |
| `workspace` | `Workspace_Config` | 普通嵌套字段；`{members, exclude, default_members}` |
| `default_run` | `string` | 可选的默认运行程序名 |

配套类型：`Source {kind, path, git}`、`Source_Kind {UNSPECIFIED, PATH, GIT, WORKSPACE}`、`Git_Source {url, branch, tag, rev}`、`Module_Selection {path, name, alias}`、`Plugin_Option {key, value}`。`dir`、物理绝对路径、已解析提交和派生路径都不回填公开声明（Decision 7）。省略状态用不与合法值相交的内部保留默认标记表达，标记只属于实现，用户写普通字符串与数组（Decision 3）。

### 2.2 包存在性与三种状态

- 包身份或能力字段任一显式出现（`name`/`version`/`description`/`default_run`，或任一能力清单显式给出）即视为存在包，此时 `name` 与 `version` 必须同时合法；显式空的能力清单同样算包配置。
- 只有 `workspace` 存在而包字段全部省略 = 纯工作区：不建立根包，不为根自动发现产物，也不启用默认插件。`workspace = .{}` 是已声明的空工作区（合法，但根调用选包为 0 失败）；既无包字段也无 `workspace` 的 `Package.{}` 得到 `PACKAGE must declare a package or workspace.`
- 每个可省略字段区分**省略 / 显式空 / 显式非空**；数组零长度和空字符串都不是省略判据。

| 字段 | 省略 | 显式空 | 显式非空 |
| --- | --- | --- | --- |
| `modules` | 自动发现 `module.jai` 或 `src/module.jai`；零候选 = 零模块，两者并存 = 歧义失败，唯一候选采用且名称取包名 | `Product.[]` = 零模块 | 完全替代自动发现；逐项 `entry` 必填，单项可省略 `name`（取包名），多项必须逐项命名 |
| `executables` | 自动发现且只认 `src/main.jai`（不扫描 `src/bin`） | `Product.[]` = 零程序 | 同上 |
| `dependencies` | 无依赖 | 无依赖 | 逐条解析 |
| `plugins` | 内置 `load` + `test-block` | `Plugin_Declaration.[]` = 无插件（test block 不再被转译） | 完全替代，不补默认 |
| `members` / `exclude` | 零显式成员 / 无排除 | 同省略 | 展开、去重、排除后逐个校验 |
| `default_members` | 位置默认（§2.6、§2.8） | 根调用没有默认选择（零选包 = 失败） | 只接受明确成员目录，无通配 |
| `default_run` | 按程序数选择 | 不允许 | 必须匹配已声明程序（ASCII 大小写不敏感） |

### 2.3 产物

- `modules` 与 `executables` 各自独立，没有包级互斥角色。
- 自动发现只使用固定候选：模块 = 包根 `module.jai` 或 `src/module.jai`；程序 = 仅 `src/main.jai`。
- 显式 item 的 `entry` 是包内现存普通 `.jai` 文件；不存在、是目录、含链接、落到包外都是错误，不回退到自动候选。
- 同类产物名称判重（ASCII 大小写不敏感），同一入口文件重复也失败；模块与程序跨类同名允许。
- `default_run` 始终校验：即使从不调用 `run`，无效值也是声明错误。

### 2.4 名称与路径

- 包名、依赖引用名、插件 `id`：首字符 ASCII 字母或数字，后续 ASCII 字母、数字、`.`、`_`、`-`。
- 模块名、程序名、导入名/alias、`options` 键：首字符 ASCII 字母或下划线，后续字母、数字、下划线。
- 比较键统一 ASCII 大小写不敏感，保留原拼写；不修剪、不自动改名、不做 Unicode 转写。
- 自动名称仍须合法：含连字符的包名不能自动变成模块名或程序名，必须显式命名。
- 包内入口与成员目录拒绝绝对路径、`..` 越界、符号链接/junction；路径链必须无链接。
- 普通 `path` 依赖相对声明包根，可指向兄弟目录（消费包根的父目录范围内）；Git 提供方内部的相对引用只能留在检出内。

### 2.5 依赖

- 来源显式且互斥：`PATH` 需要 `path`，`GIT` 需要 `git.url`，`WORKSPACE` 需要空 `path`/`url`/selector。缺类型、多来源、载荷与类型不符在协议解析期失败（Decision 9）。
- Git 的 `branch` / `tag` / `rev` 至多一个；全部省略 = 仓库默认分支；显式空 selector 失败。没有版本范围、提供方包名断言或锁文件。
- 模块选择：每项 `path`（来源根内包目录，省略 = `.`）+ `name`（提供方导出名，省略 = 唯一导出）+ `alias`（可选导入名）。`modules` 整体省略 = 把来源根当提供方包目录并采用唯一导出简写；根不是包、零导出、多导出都失败。显式空模块清单 = 能力不匹配。WORKSPACE 来源必须显式选择成员模块。
- 同一实际模块在一个消费包内最多被选择一次；引用名、alias 或路径写法不同不豁免。不同来源/修订的同名包可在明确别名下并存。
- 最终导入名不得覆盖本包模块、其他直接导入或编译器标准模块。
- 提供方自行声明其依赖；提供方内部模块不会泄漏为消费方的直接导入名。依赖图必须无环并报告完整链路。
- 已解析的 Git 选择由普通 build/run/test 复用，不追新；`juice update` 刷新所选消费包的完整 Git 图；`--offline` 只用记录与完整内容，缺记录时只有“完整提交 + 内容已缓存”可建立选择。内容缓存与选择状态分目录，遵守 XDG 契约（§11）。
- 相对 `path` 以声明包根为基准，与命令 CWD 无关；移动工程根产生新解析上下文，只改 CWD 不变。
- 提供方包内模块可互相按公开名引用（解析器重写到私有名并生成消费工程私有 shim）。声明包**自己**的 `modules` 导出同样是该包的导入名：包内程序与包内模块按公开名导入时，解析器在本包的私有 shim 目录生成同名 shim（不做重写），每个包各自一份，故两个成员声明同名模块不冲突、也不互相可见。

### 2.6 工作区

- `members`：工作区内相对明确目录，以及不跨路径分隔符的单层 `*`；递归与其他模式语法不支持。明确成员目录无效或模式无匹配失败。
- `exclude` 命中目录及其候选子树；无匹配的 exclude 合法。
- 根包（存在时）自动是成员且不能被排除；纯工作区没有隐含成员。
- 独立内层工作区形成归属边界：外层收录其根或成员且未排除时失败，不静默跳过。一个包至多属于最近合法工作区；未收录或被排除的包作为独立包，不继续向外寻找归属。
- 重叠成员匹配按实际目录去重；成员目录必须是工作区根内的安全真实目录且含 `package.jai`。

### 2.7 插件

- 插件通过已声明的公开模块提供，不是第三类包产物。`id` 是消费包内的引用名；内置引用用 `builtin = "load"` / `"test-block"`（`id` 可省略，显式时必须等于 `builtin`），外部插件必须给出显式 `source` 与 `module` 选择。
- 选中的模块入口必须有且只有一个 `get_juice_plugin` 声明并带 `@juice_plugin` 尾注；零入口 = 能力缺失，多入口 = 歧义。
- 声明不再有 `version`。入口兼容性由插件自身的 `Juice_Plugin.abi_version` 与安装单元的 `plugin_abi` 独立检查，与包版本和 Git selector 无关。
- 同一实际插件不能通过不同名字、来源拼写或配置启用多次；同一插件模块也不能同时被普通依赖选择（同一提供方的**另一个**导出作为普通 API 合法）。零公开模块的包不能作为插件提供方。
- 省略 `plugins` = 内置 `load` + `test-block`；`Plugin_Declaration.[]` = 全禁用；非空清单完全替换且不补默认。
- `options` 由插件 schema 定义默认值、解析与校验；省略/空 options 都使用默认，不等于禁用；重复键、未知键、必填缺失、非法值在 hook 之前失败。
- 插件只在各被选包自身启用：根/工作区配置不继承给成员，依赖包与未选成员的插件不自动获取或执行。一次包操作只准备一次。
- 固定生命周期阶段决定先后，同阶段按声明顺序；没有优先级、插件间排序图或自动重排。
- 派生视图限于消费工程 `target/` 私有派生区，共享检出与包源只读；只消费本轮注册的输出。插件不得修改包身份、产物、依赖、插件清单、工作区成员或命令程序选择。尚不存在的公开入口必须先由独立脚本生成；`build_script` 不再存在。

### 2.8 选包与命令

- 命令从 CWD 向上找最近 `package.jai`（`src/workspace.jai` 的 `locate_declaration_root`）；最近声明无效时立即失败，不跳过到上层。
- 位置默认：成员内调用只选当前成员；根调用、有根包且 `default_members` 省略 = 只选根包；根调用、纯工作区且省略 = 全体成员；`default_members` 显式则替换默认，空清单 = 没有默认选择。
- 显式选包：`--workspace`（全体成员含根包，与 `-p`/`--package-path` 互斥）、`-p/--package`（包名）、`--package-path`（工作区相对目录）。显式集合替代默认，按包身份去重并按相对目录稳定排序；未知/歧义/非成员/零选包都在执行前失败。
- `build` 编译所选包全部程序；零程序仍校验声明与依赖后报告没有可执行产物。`run` 必须恰好一个包，程序选择序为显式名 → `default_run` → 唯一程序，只编译该程序，`--` 之后原样转交，子进程退出码成为命令退出码。
- `test` 不需要公开产物，过滤条件逐包应用（子串、大小写敏感），零测试/零命中成功报告；`update` 只刷新解析图并拒绝 `--offline`。
- 批量操作在首个失败停止，报告已完成/失败/未执行范围；已成功包不回滚。每包测试扫描遇到下级声明即剪除该子树。

### 2.9 求值协议与诊断

- 求值器是生成的 `jai` 子进程：`#load` 声明文件、把 `PACKAGE` 的求值结果打印为记录（`SCHEMA=2`）。记录键为 `SCHEMA/NAME/VERSION/DESCRIPTION/DEFAULT_RUN/WORKSPACE/MEMBERS/EXCLUDE/DEFAULT_MEMBERS/MODULES/MODULE/EXECUTABLES/EXECUTABLE/DEPENDENCIES/DEP/DEP_MODULE/PLUGINS/PLUGIN/PLUGIN_OPTION`；值里的 `%`、`|`、CR、LF 用 `%XX` 编码。
- 列表计数 `-1` 表示省略、`0` 表示显式空、正数表示显式条目数；父进程严格校验计数、重复单值记录、来源变体、selector 互斥与记录形状。
- 校验分阶段：求值（Jai 编译器错误原样保留）→ 协议结构 → 字段/省略状态 → 名称/路径/来源规范化 → 语义 → 入口/文件系统检查。前一阶段失败不继续下游，也不发布部分可执行结果。
- 协议诊断给稳定字段与列表顺序，不伪造源码坐标；可靠时使用编译器给出的源坐标。成员按路径排序报告。
- 求值失败时打印迁移指引，指向 `docs/migrations/package-declarations.md`；未知协议记录同样指向该文件。

### 2.10 迁移与边界

- 首版人工迁移：`type`/`targets`/`main_file`、依赖 `version`/`package` 搜索、插件成员名猜测/`version`、`build_script` 全部删除；`workspace` 保留。不部分接受旧字段，不自动推断来源，不自动追新兼容修订。
- 根包与全部成员声明一起迁移；错误给出引用链，作者显式选择兼容修订或补声明。
- 可执行文件与相邻 `modules/` 构成完整安装单元，缺失或混装失败，没有其他安装目录回退（§9、§11.11）。
- 独立的 Testing 迁移 effort（§13）不在本规格内改写；本规格不改变其已关闭决策。

## 3. 仓库布局规格

最终树 = §0 架构图（C§4 定稿 + 命名定稿修订）。职责与规则：

1. **根包**：`name="juice"`、`executables = .[{name = "juice", entry = "src/main.jai"}]` → `target/juice.exe`。根包同时是导入源：库面 = 两个**发布源目录** `packages/juice/module.jai`（Package 兼容结构体 + 插件声明）与 `packages/juice/testing.jai`（Testing API），两者无 `package.jai`、不是工作区成员、不可被当作包 `#import`；juice 自身编译单元经 `src/module.jai` 的 `#load` 取得裸名（C§4、C§6.3 裁决 (a)；混合形态支持 = C§6.2 E1）。
2. **成员**（执行级现实 2026-10-21，040 收尾；分发契约 048 收尾；设计修订 2026-10-21）= `packages/juice-plugin-lint`（真实第三方插件成员；包：`package.jai` + 根部 `module.jai`（test-free）+ `tests/`；零工具依赖——不声明 `juice_core`，该模块面由工具提供，见 §3.3）；**`packages/juice-plugin-jaix`（PRESTEP 插件；执行级现实 2026-10-21，061：成员包已交付，Phase 1 静态 `src/jaix_plugin.jai` 已删除）**；内置 transpile 插件（`load` / `test 块`）仍静态驻 `src/`，`juice-plugin-test`/`juice-plugin-transpile` 成员未创建。`workspace.members` 逐条列举（juice 无 glob，C§2；glob = 未来特性 C§5 缺口 1）。成员测试各自为 root 跑（juice 不聚合，C§2/C§3；阶段 0 CI = 根 + 逐成员脚本循环，gs_test 式脚本层聚合先例）。
3. **成员 DEP 纪律与分发契约**（执行级订正 2026-10-21，048 收尾；设计修订 2026-10-21，jaix-plugin effort）：插件包 = 工作区内的普通可复制源码成员包；`juice_core` 是**工具提供的模块面**，由 `<exe>/modules` 在每个编译子进程的导入路径上解析（导入路径第一顺位，不新增解析代码），成员包按名 `#import "juice_core"` 但**不声明该依赖**、不携带 juice 检出路径。**激活面 = 各被选包自身的 `Package.plugins` 声明**；声明即激活/配置/排序，插件准备阶段为该声明选中的来源写 import shim，普通 `dependencies` 不承担插件激活（运行时依赖与插件声明分离）。**2026-11-15 修订**：外部插件不再按成员名猜测——声明给出显式 `source`（PATH/GIT/WORKSPACE）与 `module` 选择（§2.7），成员包与普通提供方走同一来源规则；成员间引用同样用显式来源，`path` 相对声明包根。
4. **命名碰撞纪律**（C§7 全部判死面）：库面 import 名不得与 "Juice" 大小写近匹配（`#import "juice"` = 平铺/目录两种发布形态下均为 "Non-matching Windows file case" 硬错误，C§7.2 E1 / C§7.4 E5）；平铺与目录模块同点并存 = 歧义硬错误（C§7.4 E6）——发布流程只写目录形态天然避免；模块面（`Juice`）与库面（`juice_core`）双面并存合法（C§7.2 E3）。
5. **共享 target/ 语义**：每包独立 `target/`（`target_dir = <包根>/target`，C§2）；clean 清根 + 各成员 target/。cargo 单 target 不实现（C§5 缺口 6）。**执行级现实（2026-10-22，架构审查 C3/C5）**：target/ 区根由 `src/target_layout.jai` 单一拥有——`build/`（构建会话区：生成的构建驱动 bootstrap-meta/version-check、build-<target>.jai，以及 build/test 程序的编译中间件 `.obj/.lib/.exp/.pdb/.added_strings_*`；PDB 经链接器 `/PDB:` 重定向，exe 仍留 artifact 根）、`modules/`（发布模块面）、`transpile/`（内容寻址视图树 + `testing-module/` 编译视图 + test_runner）、`plugins/`（注册/host 会话产物）、`packages/`（依赖 shim）、`tests/`（测试 scratch，test 启动整区 prune）、`recovery/`（崩溃恢复备份，prune 排除）、`evidence/`（人工证据日志）；artifact 根与 LNK1104 副本仍在 target/ 顶层（`modules_dir = <exe>/modules` 推导要求）。
6. **依赖闭包**：提供方自行声明其依赖；消费方不需要复述完整传递依赖图，提供方内部模块也不会成为消费方的直接导入名（§2.5；Decision 11、35–37）。
7. **测试组织**：库面模块 test-free（bootstrap #load 集纪律），测试驻 `tests/` 姊妹文件 + 内嵌 test 块（0053 规则，R§5.1）。

## 4. 命令架构规格

1. **静态命令注册表**：`COMMAND_REGISTRY :: Command.[BUILD_COMMAND, RUN_COMMAND, CLEAN_COMMAND, TEST_COMMAND, UPDATE_COMMAND, VERSION_COMMAND, HELP_COMMAND]`（R§2.1 形状；run/test 内置 = 本规格定稿；version/help 内置 = 用户定稿 2026-10-19，随阶段 1a 收口折回；`update` 由 0091 加入——七命令为命令全集）。`Command :: {name, description, usage, prerequisites: [] string, handler: #type (ctx: *Command_Context, arguments: [] string) -> bool, validate_arguments}`（`command.jai:14-21`）。version = juice 自身版本 + jai 编译器版本（编译期 `compiler_get_version_info` 填充 `Version_Info` 三元组经 `#run` 常量烘入 exe——2026-10-19 spike 实证：字符串返回 = 全横幅，三元组才是版本串）；help = registry 元数据渲染（零参总览 + `juice help <命令>` 单命令 usage 行，零前置零副作用）。
2. **dispatcher 语义**（R§2.1，`dispatcher.jai:35-121`）：`validate_registry`（无效声明/重名/未知前置拒绝）→ `plan_command` DFS 全图规划（环检测、菱形去重、前置命令恒收空参数）→ 按序执行（前置失败 = PREREQUISITE_FAILED、目标失败 = HANDLER_FAILED，立即中止）。
3. **前置链**：没有前置命令关系。`run` 不再依赖 `build`：它在所选包内只编译被选中的那一个程序（§2.8；Decision 19、73；ticket 0093）。
4. **Command_Context** = `{root_dir, cache_dir, workspace: Workspace_State}`（`command.jai:4-12`）——两个进程级路径 + workspace 相位机。
5. **workspace 状态机**（L§1.2，`src/workspace.jai`）：`EMPTY → DISCOVERED → PREPARED`；幂等；「全部成功才发布」（失败留在 DISCOVERED 可重试）。`Workspace_State` 另带调用目录、命令的 `Package_Selection` 与 `Resolution_Environment`（内容缓存根、状态根与模式）；选包在 discovery 之后、编译之前完成（§2.8）。
6. **命令级生命周期序**（阶段清单表见 L§1，全部一手核验）：build = b1 参数校验 → b2 workspace 准备 → b3 零 plan 短路 → b4 批量重校验 → b5 依赖剥离前端 → b6 [marker] jaix 前置 → b7 逐 plan 入口选择 → b8 逐 plan 编译（metaprogram 生成 + spawn jai + artifact 存在性检查）；test = 参数校验（≤1 pattern）→ t0 workspace 准备（force_dependencies）→ t1 文件收集（scan_walk + 排除集）→ t4 零文件短路 → t10 driver/metaprogram 生成 → t12 spawn jai（编译 = 执行）→ 退出码透传（t1-t12 的 1b 子集，2026-10-19 执行级订正：1b 无转译层——t2 jaix 前置/t3 EXPAND 转译/t5-t9 视图面/t11 依赖剥离归 1c；t3 编号续号与 t7 零匹配语义收在生成 metaprogram 内，见 §7.3；**2026-10-20 执行级订正（阶段 1c 收口）**：t3 EXPAND 转译 + t5-t9 视图面 + t11 依赖剥离已由 1c 接管落地（004）；**t2 jaix 前置归后续票**——PRESTEP 阶段枚举保留、b6/t2 恒等占位不动（004 决定 1 拍板，2026-10-19 的「归 1c」表述以此为准））；clean = 发现（不 prepare）→ 路径收集 → 先全量校验后删除。

**设计修订（2026-10-21，jaix-plugin effort）**：b6/t2 不再是 jaix marker 分支，而是 PRESTEP 阶段——命令级插件准备（`Package.plugins` 解析 + 成员插件扫描/链接 + 注册文件）→ PRESTEP `before` 钩子（源替换表 + 剔除集）→ TRANSPILE（b5/b7、t3/t5-t9/t11 消费替换表）→ COMPILE（b8/t12）。零 plan / 零文件短路先于 PRESTEP；PRESTEP 无内置实现，未声明 hook 插件 = no-op。旧 t2 表述（「jaix 前置归后续票」）由本条接替。**执行级现实（2026-10-21，057/060）**：命令级插件准备（声明解析 + 成员扫描/链接 + 注册文件）→ PRESTEP `before`（host）→ TRANSPILE 消费替换表/剔除集已在 build/test 两条链落地；零 plan / 零文件短路先于 PRESTEP。

## 5. 插件系统规格

### 5.1 Juice_Plugin 结构（全字段）

```
Juice_Plugin :: struct {
    id:            string;                     // 身份（进管线描述/缓存键）；声明 id 是消费包内的引用名
    version:       string;
    transpile:     *Transpile_Plugin = null;   // 转译管线贡献面（可空；非空则注册进声明序管线，
                                               //   继承行号保真契约与成对探测钩子——R§3.1/L§3.2）
    lint:          *Lint_Plugin = null;        // lint 规则贡献面（可空；非空则进合并 lint 列表，
                                               //   规则名参与跨插件查重——§5.2/§8.2；2026-10-21 折回）
    hooks:         [..] Lifecycle_Hook;        // lifecycle 挂载面（§6）
    options:       *void = null;               // 设计修订 2026-10-21：插件实例/options 指针；插件在
                                               //   get_juice_plugin 里指向自身，框架经基面 apply/validate
    options_schema: [..] Config_Option;        // 选项 schema {default, apply, validate}（设计修订 2026-10-21）
}

// lint 面（执行级形状，2026-10-21；041/047 交付）：
Lint_Level :: enum { WARNING; ERROR; INFO; }   // WARNING = 零值成员
Lint_Finding :: struct {
    line:    s64;                              // 1 基（插件读取编译器 AST 时换算；宿主不二次换算）
    column:  s64;                              // 1 基
    message: string;
    level:   Lint_Level = .WARNING;            // 零值安全：默认/漏写恒为 advisory
}
Lint_Plugin :: struct {
    name:                string;               // 规则身份（合并期查重）
    version:             string;
    inspect_test_header: #type (header: *Code_Procedure_Header, subexpressions: [] *Code_Node) -> [..] Lint_Finding;
}
```

**设计修订（2026-10-21，jaix-plugin effort）**：`Config_Option` 增加 `apply(options: *void, key: string, value: string) -> string`——插件自己把字符串 option 行写进类型化字段，未知 key = 错误；所有行应用后跑 `validate`。hook 通过 `plugin_state` 槽拿到同一 options 指针并 cast。v1 一个插件包只提供一个插件；声明侧不再有 version，兼容性由 `Juice_Plugin.abi_version` 与安装单元的 `plugin_abi` 检查（§2.7）。**执行级现实（2026-10-21，056）**：`Juice_Plugin.options` 指针 + `Config_Option.apply`/`validate` 已在 `resolve_plugin_configs` 单一落点交付；hook 的 `plugin_state` 槽对齐同一 options 指针。

**零值安全决定（2026-10-21，复查修复 F4）**：`Lint_Level` 文序 = `WARNING; ERROR; INFO;`，WARNING 是零值成员（`cast(Lint_Level) 0 == .WARNING`）；`Lint_Finding.level` 默认 `.WARNING`。零初始化或漏写级别的 finding 恒为 advisory、不改变退出码，ERROR 必须显式书写。该面序属 pre-release 变更；041 Resolution 的 `Lint_Level（ERROR/WARNING/INFO）` 文序与 040 决定 5 的原型枚举以本条为准（记录修正不改已关票）。

获取契约：插件模块定义 `get_juice_plugin :: () -> *Juice_Plugin`，**尾注 `@juice_plugin` 标记**（标记名随命名定稿统一；研究文档中 `@otter_plugin` 为代号期写法）。返回派生结构体指针 + 类型化 options 成员（jaix get_plugin 官方契约，R§3.2）。**已废弃**：`Otter_Plugin` 类型名与 `Otter.jai` 模块概念（C§4 命名定稿修订）。

### 5.2 发现两级机制（A§4 推荐 + C§7 官方形态）

- **内置件**（build/clean/run/test 命令 + 内置 transpile 插件 test 块/load）：静态注册表 + 显式 `#load` 列表——自动发现对内置件无收益且违反 bootstrap 纪律（A§4.1；R§2.1 现状）。
- **插件声明面**（2026-11-15 修订）：唯一激活/配置/顺序面 = 被选包自身的 `Package.plugins`（`id` + `builtin` | `source`+`module` + `options`）。`builtin = "load"` / `"test-block"` 解析到静态注册表；外部插件逐项解析自己的 PATH/GIT/WORKSPACE 来源与公开模块选择，不按成员名或包名搜索。未声明来源、模块入口为零或多、同一插件重复启用、插件模块同时被普通依赖选择、options schema 拒绝 = 插件准备期错误（编译前失败）。**face 默认值**：transpile 管线 = 声明的 transpile face；只有 `plugins` 字段整体省略时才取缺省 `[load, test-block]`，显式空清单 = 零 face（test block 不再被转译），非空清单完全替代且不补默认（§2.2）；hooks 与 lint 只对声明插件生效。声明序 = transpile 管线序 = hooks 注册序 = lint 观察序。**执行级现实（2026-10-21，055/056/060）**：声明解析（`PLUGIN`/`PLUGIN_OPTION`）、成员扫描/链接与 `target/plugins/registration.jai` 生成、`resolve_plugin_configs` 的管线/钩子/lint/options 选择均已落地；未声明插件不参与行为面。
- **插件来源解析与入口判定**（2026-11-15 修订）：插件准备阶段按声明序解析每个外部插件自己的来源与模块选择，只在该模块入口文件里做词法锚点判定（`get_juice_plugin` + `@juice_plugin`；lexer 锚点 = juice `is_test_anchor` 同款手法），不扫描其他模块、传递依赖或未选成员。零入口 = 能力缺失，多入口 = 歧义；读取失败 = `ok=false` 响亮失败。解析出的模块写 import shim，供注册文件/测试 metaprogram/host 按名导入；普通 `dependencies` 不参与插件激活。
- **合并 vs 选择**（设计修订 2026-10-21）：`merge_plugins` 负责 registry 合并与查重（重复 id/版本冲突/挂点冲突/transpile 名冲突/lint 名冲突 → ERROR + 拒绝），返回 registry + lint 列表 + 诊断；`resolve_plugin_configs(registry, declarations)` 按声明序过滤并产出 transpile 管线、钩子表（槽对齐）与 options 应用结果。未声明的插件不参与行为面；lint 也由声明驱动（不再以 DEP 作为 lint 激活面）。工作区级合并注册文件落 `<root>/target/plugins/registration.jai`（会话产物：每次命令重生、`clean` 随 `target/` 整删、不进 bootstrap 闭包），内容 = 按声明序的显式调用（两段 codegen：逐名 import + 钩子装配）：
  ```
  JUICE_PLUGIN_<i> :: #import "<模块名>";              // Metaprogram_Plugins 逐名 codegen 形状
  JUICE_HOOK_<i>: [..] Lifecycle_Hook;                 // 钩子条目装配段（L§5.4 收敛）
  get_scanned_plugins() / get_scanned_hook_entries()   // 声明序装配（顶层调用非法，装配在过程体内）
  ```
- **lint 加载点（执行级订正 2026-10-21；设计修订 2026-10-21）**：lint 由生成的测试 metaprogram 加载——生成文本增补 `#import "juice_core"`（与注册文件的插件模块共享同一按名导入类型面）+ `#load "<注册文件>"`，在 `#run` 内 `merge_plugins(get_scanned_plugins())`；合并失败 = 编译错误（不建 workspace、不观察任何 header）。观察点 = `.TYPECHECKED` 收集期（与发现同一时点；观察语义见 §8.2）。**设计修订**：扫描/注册由命令级插件准备完成（声明驱动），测试 metaprogram 只消费同一份注册文件、不二次扫描；Phase 2 的 PRESTEP host 复用同一份注册。**执行级现实（2026-10-21，060/061）**：测试 metaprogram 只消费 prepare 的注册文件（无二次扫描），host 复用同一注册。
- **PRESTEP-only plugin host**（设计修订 2026-10-21，Phase 2）：命令级插件准备写 `target/plugins/registration.jai` 后，若有声明的 hooks 插件，生成 `target/plugins/host.jai` 并 spawn `jai`：输入（root / mode / member dirs / `Plugin_Config`）嵌成常量，子进程加载注册文件、`resolve_plugin_configs`、应用 options、运行 PRESTEP hooks，输出记录文件 `SUBSTITUTE` / `DROP` / `DIAG` / `OK`（`%XX` 编码）；父进程严格解析。非零退出或输出缺失 = 命令失败；零声明 hooks 插件 = 不 spawn。**执行级现实（2026-10-21，060/061）**：host driver（`target/plugins/host.jai`，嵌入 root/mode/member dirs/`Plugin_Config`）、记录文件（`SUBSTITUTE`/`DROP`/`DIAG`/`OK`，`%XX` 编码）与父进程严格解析已在 build/test 落地；Phase 1 的静态注册表已随 061 删除——jaix 只经成员包 + host 解析。
- **合并与查重**（注册期，jaix `merge_plugins` 形状 R§3.2）：重复 id/异版本冲突、钩子挂点冲突、transpile 名冲突、lint 规则名冲突（含空名）→ 全部 ERROR 诊断 + 拒绝继续。**设计修订（2026-10-21）**：`merge_plugins` 返回 registry（保留每个插件的 faces 与 id）供 `resolve_plugin_configs` 选择；linkme 的运行期 dupcheck panic 是兜底，otter 在构建期更早拒绝（A§4.2.4）。
- **顺序确定性**：声明序 → 包内 DFS 词法序 → 注册文件调用序 → 管线/钩子/lint 执行序；显式排序逃生舱 = 声明可选序号（linkme sort-key 先例，A§1.3）。
- **身份进缓存键**：插件 id+version+序 进管线描述/视图键（A§4.2.6；`transpile_view_key` pipeline 分量先例）。
- **引用形态**（执行级订正 2026-10-21，048 收尾）：插件成员按名 `#import "juice_core"`，由工具从 `<exe>/modules` 提供解析；成员不声明 `juice_core` 依赖（原异名 DEP `source="../../"` 形态退役，§3.3；`#import "juice"` 判死 C§7.2/§7.4）。

## 6. lifecycle 挂载规格

### 6.1 阶段枚举（封闭枚举，只增不改——jaix Node_Kind 纪律，L§4.1）

```
Lifecycle_Stage :: enum { DISCOVER; PREPARE; VALIDATE; DEP_STRIP; PRESTEP;
                          TRANSPILE; COMPILE; EXECUTE; CLEAN; }
```

| 阶段 | 适用命令 | 触发条件 | 可观测状态（ctx 内容） | 证据（L§1 阶段清单） |
| --- | --- | --- | --- | --- |
| DISCOVER | build/test/clean | 每次 | 根安全检查、manifest 求值、member 校验、`Workspace_Discovery` | workspace 相位机 |
| PREPARE | build/test | 每次（幂等） | artifact plans + 依赖解析/获取；失败不发布 | workspace 相位机 |
| VALIDATE | build | plan>0 | 包根/artifact/源文件全量复核 | b4 批量重校验 |
| DEP_STRIP | build/test | 每次 | 依赖闭包 STRIP 视图 + shim 改写 | b5/t11 |
| PRESTEP | build/test | 声明了带 hooks face 的插件 | `Prestep_Stage`（root_dir / member_dirs / 源替换表 / 剔除集）；插件执行全包扫描 + spawn + 镜像 | b6/t2（设计修订 2026-10-21：插件驱动，无 jaix marker；执行级现实 057/060：命令级 prepare + host 派发） |
| TRANSPILE | build/test | 每次 | 探测/EXPAND 视图/缓存键/Test_Entry | b7/t3 |
| COMPILE | build/test | 每次 | metaprogram 生成 + spawn jai + 产物检查 | b8/t12 |
| EXECUTE | test/run | 每次 | 编译期 `#run` 执行 + 退出码（test t12）；artifact 启动（run：select_artifact_plan → launch，L§1.5） | t12；run.jai:30-79 |
| CLEAN | clean | 每次 | 路径表 + 先校验后删除 | c2/c3 |

### 6.2 挂载点与钩子形状

- 挂载点 = 阶段 × `{before, at, after}`：`before` = 阶段前观察/变换输入；`at` = 替换阶段实现（14 seam 的插件化，§6.3）；`after` = 阶段后观察产物。
- `Lifecycle_Hook :: {stage: Lifecycle_Stage; position: Hook_Position; hook: #type (ctx: *Lifecycle_Context, state: *void) -> bool;}`——挂点关联表（jaix `Plugin_Grammar_Entry` 形状，L§3.1）。
- `Lifecycle_Context` = 阶段名 + 该阶段可观测状态（§6.1 表列）+ `diagnostics` 三汇 + `plugin_state` 槽（见下）。

**设计修订（2026-10-21，jaix-plugin effort）**：`Lifecycle_Context` 增加 `prestep` 槽（`*void` → `Prestep_Stage`）。`Prestep_Stage { root_dir, member_dirs, substitutions, drops }`；`substitutions` 为 `{original, replacement}`（原包相对路径 → 替换绝对路径），append-only；重复键 / 替换与剔除同键 = 阶段失败；不新增文件；仅 root package。PRESTEP 用 `before` 挂载（可堆叠、声明序），无内置实现（未声明 = no-op）；`at` 保留给未来接管整个阶段。**执行级现实（2026-10-21，057）**：`Prestep_Stage` 与 `prestep_add_*` 阶段级规则已交付（同键异替换 / 替换与剔除同键 = 阶段失败，即使 hook 返回 true）。

### 6.3 14 seam → at 挂载点映射（全部现成先例，L§2 清单）

`discover`（workspace.jai:124）、`resolve`（:148）、`prepare_dependencies`（:149）、build `transpile`/`compile`/`prestep`（build.jai:210-212）、test `transpile`/`compile`/`dep_transpile`/`prestep`（test.jai:109-112）、clean `validate_path`/`delete_path`（clean.jai:38-39）、run `launch`（run.jai:65）、jaix spawn `transpile`（jaix_front.jai:206）。每个 at 钩子 = 对应 seam 的插件化注册版；生产默认 = 内置实现。

**执行级订正（2026-10-20，阶段 1c 收口）**：1c 接线的 at 子集 = 代表性子集（004 决定 17）——build 的 TRANSPILE（b5/b7 的 transpile 形参面）与 COMPILE（b8 compile 形参面）、test 的 TRANSPILE（t3/t11）与 COMPILE（t12）四挂载点已改钩子表派发；**派发粒度 = 阶段级**——一个 at 钩子替换该阶段整个实现面（build TRANSPILE at 替换 b5+b7 前端整体、COMPILE at 替换 b8 循环整体；test TRANSPILE at 替换 t3+t5-t9+t11 前端整体、COMPILE at 替换 t12 整体）；`at` 替换身份进管线描述（换实现 = 换视图键，语义文档化）；其余生命周期挂载点（discover/resolve/prepare_dependencies、clean 两、run launch；build/test 的 prestep 由 PRESTEP 阶段接替；jaix spawn 归插件内部，不再是 lifecycle mount；`test dep_transpile` 已被 test TRANSPILE 阶段级 at 替换涵盖）留 `#type` 形参，机械接线留后续票。

### 6.4 确定性排序

1. 阶段序 = 命令编排硬编码序（§6.1 表）；未经过的阶段其钩子静默不触发（jaix soft_fail 语义，L§3.1）。
2. **阶段内钩子序 = 注册声明序**（spec 0060 决定 6 双先例）；`after` 钩子与 `before` **同为注册序正序**——逆序对称方案考虑后否决（单一规则、与声明序心智一致；L§4.3 的未决项在此裁决）。
3. 跨包序 = 插件声明序 → 包内 DFS 词法序（§5.2）。

### 6.5 跨阶段状态与失败语义

- **显式 ctx 通道**（无闭包，0063 偏差 5）：`Lifecycle_Context.plugin_state` 槽与钩子注册序对齐、宿主持有存储、跨阶段续走——`Transpile_Context.plugin_state` 的直接泛化（L§4.4）。选用**槽协议**而非 jaix 的强注入（构造期恒 null）——juice 先例已生产验证且 bootstrap 闭包自足（L§风险 6 裁决）。
- **失败语义**：钩子返回 `false` 或产 ERROR 诊断 = 阶段失败 → 命令失败 → 退出码（`HANDLER_FAILED` 传播）；观察类钩子（只产诊断）失败同样中止——失败继续语义属测试执行层，不属于钩子层（L§4.5）。
- 部分状态防护不豁免钩子：钩子失败发生在发布/删除之前（L§4.5）。

### 6.6 与命令的正交组合

命令 = 顶层编排入口（决定跑哪些阶段）；lifecycle 钩子 = 阶段边界挂载面；注册表独立、校验同 shape；一个插件可同时贡献 transpile 面 + hooks 面（§5.1）。**已废弃**：整命令替换/test-as-plugin（R§3.4 曾拟 test 为插件贡献 Command 值——N§5.3 delta 1）。

## 7. test 命令规格

### 7.1 发现 = metaprogram note 枚举（N§3.2 推荐，N-exp 端到端证实）

1. **文件收集**（juice t1 语义不变）：`scan_walk` DFS 词法序 + 排除集（dot/target/tests/data/modules/member 子树剪除）——回答"哪些文件进测试编译"。**设计修订（2026-10-21）**：核心不再内置 jaix 驱动垃圾判定；jaix 插件把 CLI 的 CWD 设到 `target/jaix-drivers/`，新 driver 落 target/；旧 litter 由插件清理（迁移说明见 §8.3）。**执行级现实（2026-10-21，058/059）**：核心 litter 谓词已删除，清理与 CWD 固定随插件（061 起在成员包）。
2. **note 枚举**：生成的测试 metaprogram（test_runner.jai 形状）内置收集模块——消息循环累积全部 `.TYPECHECKED`，在 `.PHASE == .TYPECHECKED_ALL_WE_CAN`（how_to/460:68-75 官方时点）一次性处理：
   - 遍历 `procedure_headers`（注记落在 `Code_Procedure_Header.notes`，N§1.4 实验）；
   - 匹配 = note 文本**精确 `"test"` 或前缀 `"test("`**（编译器自用注记 PrintLike/NoProfile 佐证子串匹配会误收，N§1.4 第 3 点）；`name != ""`；
   - **文件来源隔离**：`enclosing_load.fully_pathed_filename` ∈ 包视图文件集（+ Testing 模块编译视图白名单）——依赖闭包声明经 shim 进入消息流被剔除（juice "Dependency tests are neither discovered nor executed" 的编译器级等价物，N§3.2）；
   - **排序**：按名排序（官方指导 how_to/460:119-123 "may see these entities in any order"）；`juice_test_N` 前缀按数值 N 比较（N§风险 6 裁决：前缀剥离 + 数值 + 余部字典序）；
   - **查重**：收集期按名查重 → 诊断拒绝。
3. **单一发现源**：转译产物 `juice_test_N` 已带 `@test`（juice EXPAND 落实，`transpile_plugin.jai:316` 一手核验）——test 块与手写 `@test` 过程经同一枚举统一，Test_Entry manifest 降级为转译簿记（行号保真/path_mapping）（N§3.3）。

### 7.2 runner = 生成显式调用表（Jai 无运行期顶层执行，A-E1/E2 判死）

- 注入而非预生成：收集后 `add_build_string` 注入 `#run { run("name", proc); …; if finish() != 0 assert(false); }`（juice driver run-list 形状 test.jai:502-517；注入通道 = how_to/460/470 官方模式）——**单编译完成**，无两编译探针方案（N§3.2）。
- 执行语义不变：编译期 `#run` 执行、失败继续、`run`/`finish` 汇总退出码（Testing 模块契约）。
- path_mapping 表随 metaprogram 生成时嵌入（otter 生成 metaprogram 时已知文件清单与视图路径）。
- **执行级订正（2026-10-19；2026-10-22 更新）**：会话产品 = 单一 `test_runner.jai` 落 `<root>/target/transpile/`（1c 转译层落地后自 1b 的 target/test 迁移，落视图树根，transpile_cache 注释契约；每跑重生，clean 随 target/ 整删；名字常量 `TEST_RUNNER_FILE_NAME` 在 `src/metaprogram.jai`）；**C4/C5（2026-10-22）**：测试程序的 intermediate_path = `<root>/target/build`（编译中间件与 build 共用该区），包根不再从 intermediate_path 剥离——生成的 test driver 顶层声明 `JUICE_TEST_PACKAGE_ROOT` 常量，测试助手（otter_root / 成员 jp_member_root）直接消费；driver 源（工作目录锚定 + Testing 面 import + 视图 `#load` 表）由 `generate_test_driver` 生成后以 `add_build_string` 嵌入 runner，**`driver.jai` 不再落盘**（2026-10-22 由两文件折入；改名史 first.jai → test_runner.jai）；Testing 面 = 编译视图面（1c t9 接替 1b 的「#load 源面 = exe 相对推导」执行形状）——in-package `modules/Testing.jai` = EXPAND + 编号续号 + 自测段截取编译视图 + 白名单（`target/transpile/testing-module/`）；global = STRIP 视图（`<exe>/modules/Testing.jai`）；**单一形态（2026-10-20，035 收口）**：嵌入 driver 恒发射 `#import "Testing"`（发布面；t9 编译视图在 import 路径解析），注入 runner 恒驱动裸名 `run`/`finish`/`path_mapping`；`testing_source` 显式源面加载与 `face_is_discovered` 面选择已退役；发布落位后统一消费 `target/modules/Testing.jai`（005 切换点，§9.5）。

### 7.3 短路/过滤/编号

**执行级订正（2026-10-19）**：零入口**双短路**——命令层零文件 = 真跳过编译（juice t4 语义）；文件在但零 `@test` 入口 = 生成的 metaprogram 打印 "No tests found" 后不注入（编译成功退出 0 = 1b 单编译约束下的等价形——发现 = 编译，测试清单命令期不可知）；pattern 过滤在收集后（≤1 参数，**子串、大小写敏感**，零命中 "No tests matched '%'."）；`juice_test_N` 全局编号**基 1** 续号沿用（juice t3，1c 续 Testing 模块自测号）。

**执行级订正（2026-10-20，阶段 1c 收口）**：test 块经 EXPAND 生成 `juice_test_N` + 裸 `@test` 注记，与手写 `@test` 经同一 note 枚举统一（§7.1 单一发现源）；EXPAND 编号与 Testing 模块自测号共享全局续号（基 1，跨文件续号）；**显示名 = 过程名**——命名 test 块的显示名与匿名块的 path:line 显示名恢复留后续票（`@test("name")` 参数化发射 + 解析）；**"Found N tests" 打印不产**（发现源在 metaprogram，命令层不知计数——1b 起即此状）；零测试判定 = 收集期零条目（旧 juice t2 的 next_number==1 判定在手写 @test 下不等价，不沿用）。

### 7.4 at 钩子覆盖面（L§4 落点，N§4）

| 挂载点 | 替换契约 | 默认 |
| --- | --- | --- |
| at_DISCOVER | (消息流) → 测试清单 | note 枚举 |
| at_TRANSPILE | Transpile_Plugin 管线 | 内置 test 块 + load 插件 |
| at_RUNNER_GEN | (测试清单) → 注入代码 | run-list 注入器 |
| at_COMPILE | spawn 替换 | compile seam |
| at_EXECUTE | 执行/汇总观察 | 编译期 #run |

**整命令替换不必要**（§4.1 静态三命令）——已废弃 R§3.4 立场（N§5.3）。

### 7.5 与转译插件的关系（迁移路径）

test 块 → 内置 test 块转译插件 EXPAND 生成 `juice_test_N` + `@test` → note 枚举发现（N§3.3）。注记在视图中幸存：视图 = 逐行保真文本变换，非编辑行原样保留（ADR 0005）。**juice-compat 即此内置插件**——存量 juice 测试套件零改写。

**执行级订正（2026-10-20，阶段 3 终态）**：零改写对**普通用户包**成立——旧 juice 写法（`#import "Testing"` + 裸 `expect`）经产物 exe `test`，失败断言计入汇总、exit 1、坐标指原文行；通过包 exit 0、计数正确（035 门禁修复 + 039 终态复核，见 `docs/implementation/old-juice-exit.md` §3 接缝 3）。全部测试程序（根包、fixture、用户包）统一消费发布 Testing 面，注入 runner 恒驱动裸名 `run`/`finish`/`path_mapping`（单一断言寄存器）；fixture 族迁移为裸名，成为真实用户包的形态代表（§9.5）。

## 8. 转译与 lint 规格

### 8.1 内置 transpile 管线（juice 继承，R§3.1/L§3.2 全部契约照搬）

- 两内置插件：`load`（#load 处理：EXPAND 等行数占位 / STRIP 目标改写；`load_edges` 喂闭包 DFS；无 anchor）与 `test 块`（两模式重写 + `@test` 注记 + Test_Entry 清单；`has_anchor` 喂闭包视图决策）。
- 插件接口：`Transpile_Plugin :: {name, version, modes{strip,expand}, has_anchor, load_edges, transpile}`（成对探测钩子 = 适用性声明先例）。
- 派发：声明序；claim 契约（claim 覆盖恰好消费的 token，未消费继续派发）；模式门控。
- **行号保真门**（runner 强制，每条编辑「1 行换 1 行 + 以 token 为界」违反丢弃 + 诊断——坏插件转译期响亮失败）。
- 跨文件状态：`Transpile_Context.plugin_state` 槽。
- 缓存键：管线描述（id+version+序）进 `transpile_view_key`（0062 先例）。

### 8.2 lint = observer metaprogram 插件（N§4.3；执行级订正 2026-10-21，040 收尾）

- **加载与合并**：命令级插件准备按声明驱动扫描并写注册文件后，生成的测试 metaprogram 增补 `#import "juice_core"` + `#load "<root>/target/plugins/registration.jai"`（§5.2），在 `#run` 内 `merge_plugins(get_scanned_plugins())`；合并失败（重复 id、lint 规则名冲突、at 挂点冲突）= 编译期 ERROR，测试编译失败（不建 workspace、不观察任何 header）。
- **观察面**：`Juice_Plugin.lint`（`Lint_Plugin.inspect_test_header`）。每个被收集的测试过程收到其已类型检查的 header + 扁平化子表达式（`[] *Code_Node`），观察者返回 `[..] Lint_Finding`（1 基 line/column），不直接依赖 `compiler_report` 内部。
- **宿主报告**：生成的 metaprogram 在 `.TYPECHECKED` 收集期、测试注记判定与 `source_path_allowed` 隔离判定（与发现同一谓词）之后，按合并序调用各 lint 观察者；findings 由宿主把 `WARNING/ERROR/INFO` 映射到 `compiler_report` 三汇，路径经嵌入的 `path_pairs` 映射回原始包相对路径（不暴露 `target/transpile/` 视图路径），坐标取 findings 原值（插件负责换算，宿主不二次换算）。隔离集之外的导入模块不会被观察。
- **时点与退出码**：lint 与发现共用同一收集点（runner 注入之前），pattern 过滤发生在收集之后，因此过滤不可能隐藏 finding。v1 lint 为 advisory：WARNING 不改变退出码（`Lint_Level` 零值安全，见 §5.1）；只有显式 ERROR finding 导致编译失败。
- **v1 规则（真实成员包 `packages/juice-plugin-lint`）**：测试过程名必须 snake_case（非空、`[a-z0-9_]`）；违反 = 一条 WARNING，消息含过程名并锚定过程 header。生成的 `juice_test_N` 与手写 snake_case 名天然通过。**设计修订（2026-11-15）**：lint 插件的声明 id 为 `juice-plugin-lint`，来源显式指向提供方包目录；根包在 `Package.plugins` 声明它（不再以根 DEP 激活）。
- **已废弃**：原稿「lint 的 lifecycle 面 = `at_RUNNER_GEN` 邻接（决定注入哪些观察逻辑）与 `after_COMPILE`（收集诊断转成报告）」为未落地的设计草案；实际形态 = 上述 `.TYPECHECKED` 收集期观察 + 宿主 `compiler_report`，不新增 at 挂载点。

### 8.3 jaix pre-step 插件（设计修订 2026-10-21，jaix-plugin effort；执行级现实 2026-10-21，061/062）

- **身份与形态**：`juice-plugin-jaix`，一个 `Juice_Plugin`，只贡献 PRESTEP `before` hook 与 options schema（`config`、`exe`）；声明 = `Package.plugins` 里 `{id="juice-plugin-jaix", source=..., options=[config, exe?]}`（声明侧无 `version`；2026-11-15 修订）；未声明 = 无前置。**执行级现实（2026-10-21，061）**：实现 = 成员包 `packages/juice-plugin-jaix/`——`package.jai`（零工具依赖）+ 根部 test-free `module.jai`（`#import "juice_core"`、`get_juice_plugin` + `@juice_plugin`、PRESTEP hook、options schema、插件自带扫描/spawn/镜像/litter）+ `tests/`（17 个单元测试，以成员根为包根）；Phase 1 的 `src/jaix_plugin.jai` 与其装载行已删除。
- **职责**：插件自带整包扫描（自己的排除规则：dot/target/非 .jai/根 package.jai/member 子树/config 文件/含 juice test block 的文件）、逐文件 spawn `jaix transpile`（全绝对路径、stderr 透传、CWD = `target/jaix-drivers/`）、镜像 `target/jaix/`（sidecar `.map` 随落）、exe 解析（options.exe 或 PATH）。失败 = PRESTEP 失败 = command 失败。**执行级现实（2026-10-21，061）**：成员自带确定性 DFS 枚举、路径助手与 Windows/POSIX 环境探测——`scan_walk` / `path_safety` / `xdg.get_env` 不在 `juice_core` 发布面，成员不复用工具内部模块。
- **阶段效果**：镜像内的 test-free 文件填 `substitutions`（原相对路径 → `target/jaix/<rel>`）；config 文件填 `drops`；test block 文件不替换（juice 原路径 EXPAND）；member 子树不扫。build 入口命中替换则直编镜像入口并跳过闭包探测；test 已收集文件命中替换则 EXPAND 于镜像视图，`rel_path` / 编号 / `path_mapping` 不变。**执行级现实（2026-10-21，061）**：命令级 prepare 按声明定位成员（`workspace.members`）、写 import shim 与 `target/plugins/registration.jai`；host 应用 options、执行 PRESTEP，记录 `SUBSTITUTE` / `DROP` / `OK=1`；build/test 两条链与安装布局全链 E2E 全绿（真实 jaix CLI，绝对 exe option 不依赖 PATH）。
- **核心零 jaix 知识**：无 `Package.jaix`、无 `JAIX_*` 记录、无 jaix mirror 路径、无 `is_jaix_driver_litter`、无命令分支；jaix 的 litter 与旧文件清理归插件。**执行级现实（2026-10-21，061）**：`src/` 守卫白名单为空（059 的 Phase 1 白名单曾为 `src/jaix_plugin.jai` 整文件 + `src/main.jai` 装载行；061 清空），`tests/jaix_guard_tests.jai` 全量文本扫描零命中并保留空白名单负向自测。
- **根包声明**：根 `package.jai` 声明 `juice-plugin-jaix` 且无 options = 定义好的 no-op 前置；根自身 build/test 不做 jaix 工作，但每次因声明了携带 hooks 面的成员而多 spawn 一次零效果 host（记录 `OK=1`）——「声明即激活」的直接结果（061 偏差 3）。
- **缓存**：镜像不是缓存（每次重跑全覆写）；test 视图键仍以镜像源内容为输入（内容寻址）；build 直编镜像不做视图缓存。

## 9. 运行期模块发布规格

1. **定义源 = 两个发布源目录**：`packages/juice/module.jai`（Package 兼容结构体 + 插件声明）与 `packages/juice/testing.jai`（Testing API 定义面）。两者都是**发布源目录**：有 `.jai` 源、无 `package.jai`，因此不是工作区成员、没有 `Package.name`、不可被当作包 `#import`。juice 自己的编译单元经 `src/module.jai` 的两行 `#load` 取得裸名；`src/module.jai` 自身只保留 Testing 面的自测过程，不发布。**转换形态 = 整文件读取**（不再按段标记裁剪）。插件引用面 = 发布生成的 `juice_core` 模块面，由工具从 `<exe>/modules` 提供（2026-10-21，048；原「库面经 DEP shim 供插件引用」形态退役，§3.3）（C§4 定稿）。
2. **发布产物 = 三份模块面 + 一份内部发现源件 + 四份插件面闭包副本**（build 期自动生成，不进版本库；**执行级订正（2026-10-20，005 决定 1/4/5-7；039 阶段 3 终态；2026-10-21，048 决定 1-4/7-8 增补插件面闭包副本）**：三份模块面与转换形态直落，内部发现源件与四份插件面闭包副本逐字复制）：
   - `target/modules/Juice/module.jai`——大写**目录模块**形态（发行版惯例：入口 = `module.jai`，`modules/Basic/module.jai` ls 佐证 C§7.4 E7）；**转换形态 = 整文件复制**——读 `packages/juice/module.jai` 全文，前置标准导入头；源为空则发布失败；
   - `target/modules/Testing.jai`——平铺（与原始 juice 布局一致）；**转换形态 = 剥前缀平铺**——读 `packages/juice/testing.jai` 全文，lex IDENT token 级剥掉 `Testing_`、行号保真（注释/字符串不碰）；源不含 `@test`，发布面因此零测试过程；
   - `target/modules/juice_core.jai`——**生成模块**——插件库面：两个内置 plugin id 常量声明行逐字抽取（单源保真）+ 四行模块相对 `#load "juice_internal/plugin_face/<file>"`（`#load` 在按名导入的模块内按包含该指令的文件目录解析——048 决定 5 spike 事实）——文件不含绝对路径、盘符或构建根，整个 `modules/` 树可搬迁（025 stand-in 兑现替换；2026-10-21，049）；
   - `target/modules/juice_internal/plugin_face/{transpile,transpile_plugin,lifecycle,plugin}.jai`——**插件面闭包副本**（不是模块面）：`src/` 同名源逐字复制（无变换；571 / 553 / 364 / 596 行随源文件，2026-10-21 059 核——lifecycle/plugin 随 056/057 的 options/PRESTEP 面增长），由生成的 `juice_core.jai` 以模块相对路径 `#load`；生成行与复制落点共享同一 `JUICE_CORE_LOAD_FILES` 清单与同一 `juice_internal/plugin_face/` 目录常量（无第二份清单）；发布前批量读六源（定义源、发现源、四闭包源），任一缺失/不可读 = 先于任何写入的 exit 1；`juice_internal/` 同为私有 `#load` 目录契约；
   - `target/modules/juice_internal/test_discovery.jai`——**内部发现源件**（不是模块面）：`src/test_discovery.jai` 的逐字复制（无变换，285 行随源文件）；生成的测试 metaprogram 以绝对路径 `#load` 它，`juice_internal/` 是私有目录契约（不发布为公开 import 面；编译器导入路径仍可见该目录，非强制不可导入）；源缺失/不可读 = 发布失败（先于任何写入的 exit 1，不落半套）；落地助手以 `<modules_dir>` 为参数（消费侧唯一已知根是 `<exe>/modules`）；
   - 发布序 = **先发布后编译**（bootstrap 的 Testing 特例源即发布面）；每次 build 重生。**执行级现实（2026-10-21，062 复核）**：发布树共 **8 件**——三份模块面 112 / 237 / 16 行，内部发现源件 285 行，插件面闭包副本 571 / 553 / 364 / 596 行（各与 `src/` 同名源逐字节相等；061 的成员搬移未改这四个源文件）。

   **设计修订（2026-10-21，jaix-plugin effort）**：发布件数量不变（三模块面 + 发现源 + 四插件面闭包副本）；`lifecycle.jai`/`plugin.jai` 增加 `Prestep_Stage`、`options`、`apply` 等类型/字段（056/057 落地，行数 364/596）。**执行级现实（2026-10-21，062）**：发布树就是上列 8 件；PRESTEP host driver（`target/plugins/host.jai`）与注册文件（`target/plugins/registration.jai`）是会话产物，不是模块面、不发布。
3. **modules_dir 推导 = `<exe>/modules`**（有意偏离 juice 的 `<exe>/../modules`——modules 是生成件与 exe 相邻；LNK1104 副本纪律不变：副本留 `target/` 内即命中推导；jaix-cli 部署布局 `<exe_dir>/modules` 先例）（C§4 定稿）。
4. **发布步骤在 build 流程内 + 求值器切换**：求值器子进程 `-import_dir` 指向发布目录（C§4）。**执行级订正（2026-10-20，用户拍板 + 005 决定 1/8）：求值器切换 = 发布落位即切换**——`modules_dir = <exe>/modules` 推导使 otter 自身命令的 manifest 求值自动解析 `#import "Juice"` 到发布目录模块（R§5.3 与 §10 的划分冲突以本拍板为准：切换属阶段 2）；平铺 `Juice.jai` 种子退役、仅目录模块存在（C§7.4 E6 歧义规避）；**阶段 2 验收 = 自构建自测**（两模式 `jai build.jai` 产物各于根 build/test 全绿，见 §10）。
5. **API 兼容约束**：`Testing.jai` 与 `juice/modules/Testing.jai` API 兼容（`expect`/`expect_eq`/`fail`/`run`/`finish`/`path_mapping`；旧稿的 `assert` 为概念名，实际面无同名符号）；`Juice` 模块面 = Package 兼容面（字段形状同 `juice/modules/Juice.jai:97-118`，扩展字段在自举切换后加入）（C§4）。**执行级订正（2026-10-19，016 spike 定形）**：bootstrap 期 Testing 面（src/module.jai）= **prefixed 公开名**（`Testing_run`/`Testing_finish`/`Testing_path_mapping`/`Testing_expect`/…）+ `#scope_file` 裸内部态——裸顶层过程与测试程序自身 `#import "Testing"` 撞重载判死（Jai 无命名空间包裹构造）；005 发布转换 = 公开块剥前缀 → 平铺 Testing.jai，裸名 API 兼容由 import 发布面承接。**执行级订正（2026-10-20，032/033 收口折回）**：发布 Juice 目录模块 = Package 兼容段 **+ 内部结构面**（`Effective_Target`/`Artifact_Plan`/`Workspace_Discovery`/`Prepared_Workspace`——exe 内部源经 `Juice :: #import "Juice"` 命名空间绑定消费，是自举产物与自托管测试程序编译的前提；Package 作者 API 不变，属超集）；**执行级订正（2026-10-20，035 单一寄存器）**：所有测试程序（根包、fixture、用户包）消费发布面裸名 `run`/`finish`/`path_mapping`；prefixed 名仅为定义源内部公开名（发布转换输入），其自测块报告视图路径（白名单内）；fixture 族已迁移为裸名。**设计修订（2026-10-21，jaix-plugin effort）**：`Juice` 发布面移除 `Jaix_Prestep`/`jaix`/`transpile`/`Transpile_Plugin_Declaration`，新增 `Plugin_Declaration` 与 `Package.plugins`；`Juice_Plugin` 增加 `options`，`Config_Option` 增加 `apply`。属 breaking change（§11.12）；成员插件与测试 metaprogram 的消费面不变（仍按名 `#import "juice_core"` / `"Juice"`）。
6. **单源消除双份风险**（R§6 风险 4 的解法）：定义源一份、发布生成三份模块面形态 + 一份内部发现源件（§9.2，执行级订正 2026-10-20 阶段 3）+ 四份插件面闭包副本（同源逐字复制，2026-10-21）；求值器切换已完成——自举期与自举后统一消费发布面，旧 juice 已退场（`docs/implementation/old-juice-exit.md`）。

## 10. 自举路线规格

| 阶段 | 输入 | 输出 | 验收标准 | 风险与规避 |
| --- | --- | --- | --- | --- |
| 0 | 空 otter 目录 + 本规格 | `package.jai`（juice 同形状）+ 最小 `src/main.jai` + 测试 | `juice build`/`juice test` 于根零特判全绿（R§5.3） | 无 |
| 1 | 阶段 0 产物 | build + clean + test 内置（note 方案初始实现）+ 插件加载面（扫描发现 + Juice_Plugin 合并 + lifecycle 骨架） | 三命令三路径验证；开发循环仍用旧 juice | **LNK1104**：运行中 exe 不可覆写——复制为 `target/juice-build.exe` 运行毕删除，副本留 `target/` 内保 modules 推导（R§5.3 阶段 1） |
| 2 | 阶段 1 产物 | `build.jai` metaprogram（ADR 0006 全形状：`- release` 开关、Default_Metaprogram 抑制、test-free #load 六模块 `{transpile, transpile_plugin, transpile_cache, transpile_front, metaprogram, publication}`、剥离前端、生成 metaprogram + 子进程 jai）+ **modules 发布步骤**（§9 三份模块面 + 内部发现源件 + 四份插件面闭包副本；先发布后编译） | `jai build.jai`（debug）与 `jai build.jai - release` 于根各 exit 0，产出 `target/juice.exe` + `target/modules/{Juice/module.jai, Testing.jai, juice_core.jai}`，另有 `juice_internal/test_discovery.jai` 与 `juice_internal/plugin_face/` 四件；**两产物各于根自构建自测全绿（求值经发布面——切换成立）** | 子进程 CWD 切换（全部绝对路径）；bootstrap #load 集 test-free 纪律；bootstrap 无 hand-off（005 决定 10：自托管直跑的自构建 E2E 响亮 SKIP；Build 命令保留 011 hand-off） |
| 3 | 阶段 2 产物 | juice 自构建自测；note-based test 接管自身套件；旧 juice 退场 | 自举循环全绿：`jai build.jai`（debug/release）各 exit 0 且产出 exe + 三份模块面 + 内部发现源件 + 四份插件面闭包副本；产物副本于根 build/test exit 0、**SKIP 0**、白名单 6、455 顶层条目（直跑 SKIP 2 = 环境条件形态）；机械退场守卫绿；旧 juice 退场声明落地（`docs/implementation/old-juice-exit.md`） | **零改写枢轴**：juice EXPAND 产物已带 `@test`（`transpile_plugin.jai:316`）——存量 test 块套件经内置转译插件照旧生成 `juice_test_N` + `@test` → note 发现统一覆盖（N§5.2） |

阶段 2 三接缝（005 决定 12，执行级订正 2026-10-20）：接缝 1 = 自举三路径——`jai build.jai`（debug）与 `jai build.jai - release` 于根各 exit 0、产出 exe + 三份模块面（阶段 3 起 + 内部发现源件与四份插件面闭包副本），**两产物各于根 build/test 自构建自测全绿**（求值经发布面），旧 juice 不变式为过渡期复核面（阶段 3 已退场）；接缝 2 = 姊妹测试（bootstrap #load 闭包 test-free + 发布转换纯函数面测试驻 `tests/`）；接缝 3 = E2E 真子进程（真 `jai` 跑 build.jai 两模式 + 产物 exe 真跑 fixture/根自测 + 发布产物逐字节钉）。

阶段 0-2 的测试写法约束：全部用 test 块（旧 juice 只发现 test 块；手写 `@test` 过程对旧 juice 不可见）（N§5.2）。**阶段 3 起该约束退役**——note 发现接管，手写 `@test` 与 test 块同源发现、同序编号（038/039）。已知边角纪律：根 prep 期成员相对 DEP 的 CWD 语义（§3.3）、manifest 求值器重试、Testing 模块 STRIP 特例。

**设计修订（2026-10-21，jaix-plugin effort）**：本 effort 在阶段 3 之后，自举路径不变；根包 `package.jai` 的 lint 激活从 `dependencies` 迁到 `Package.plugins`；manifest 求值器协议新增 `PLUGIN`/`PLUGIN_OPTION`；bootstrap 六模块闭包不变（`plugin.jai`/`lifecycle.jai` 仍不在 bootstrap 闭包；新类型只进发布插件面）。

**执行级现实（2026-10-21，062 收口）**：本 effort 已交付并关闭，自举路径不变。根 `package.jai` 的插件声明（`juice-plugin-lint` + `juice-plugin-jaix`）与 `PLUGIN`/`PLUGIN_OPTION` 协议已是自举路径的一部分；bootstrap 六模块闭包未变。收口矩阵：`jai build.jai`（debug/release）于根各 exit 0；debug/release 产物副本于根 build/test 各 exit 0、**SKIP 0**、`329 passed, 0 failed`；权威 found = max `juice_test_N` **537** + 手写 `note_suite_*` @test **5** = **542**（061 基线；本票无测试增删）；直跑 SKIP 2（自托管 posture，环境条件形态）；预期失败白名单恰 **6 行**（定义源 Testing 自测 2 + `tests/module_tests.jai` 视图/原文各 2；组成自 035/036 未变），白名单外零 `expect failed`；jaix 守卫白名单为空（0 条），`src/` 零 jaix 引用；发布件 8 件（行数见 §9.2）；真实 jaix build/test E2E、成员根套件（`17 passed, 0 failed`）、安装布局全链 E2E 与缺成员/坏插件/坏 options/缺插件面负例全绿；未来项登记在 effort map 的 Not yet specified。

## 11. 风险与未决项

1. **linkme 式链接期聚合**：需 jai 编译器特性请求（逐声明命名段 + link_name 缺失，A§2.1）——记录为特性请求素材，不进路线（A§5 风险 1）。
2. **note 机制 beta 绑定**：note 文本格式（`'test'`/`'test(custom_name)'`）与消息面（枚举完备性多文件 spike）绑定 beta 0.2.009；官方 test framework 落地后复核（N§风险 1/2；与官方对齐零成本——N§5.3 delta 3）。
3. **`compiler_report_errors_for_untyped_declarations_with_these_notes`**（Compiler.jai:1536）：零用法、语义未验证——若用于强制 `@test` 过程签名，先 spike（N§风险 3）。
4. **at 替换钩子的缓存键语义**：替换实现 = 换视图键（正确但需文档化；runner 生成器是会话产物不进键——driver/metaprogram 每跑重生，N§4.2）。
5. **观察类钩子诊断形状**：只产诊断钩子（lint 式）与变换类钩子的三汇分开立规（L§风险 4 已部分裁决于 §8.2）。
6. **阶段枚举稳定性承诺**：封闭枚举只增不改 + spec 版本化（jaix Node_Kind 纪律，L§风险 1）。
7. **第三方宿主**：DLL/进程外宿主维持推迟（动态库调用约定崩溃反例；字符串 ABI 属新设计面）（R§3.3.7、A§5）。
8. **未来特性清单**（juice 缺口，全部非 bootstrap 前置）：glob members、exclude 语义、根命令聚合成员（--workspace）、版本继承（workspace.package）（C§5）。
9. **增量构建缓存键契约**：视图键 = hash（路径+源+模式+版本+load 重写表+管线描述）（R§7 风险 7）；otter 键带自身版本分量，与旧 juice 键不共享（有意选择）。
10. **Windows 现实约束**：LNK1104、`cmd /c`、子进程 CWD、大小写近匹配拒绝——全部照既有解法（R§6 风险 8；C§7）。
11. **安装/打包布局下的第三方插件加载**（2026-10-21 登记；**已交付**，2026-10-21，048 effort）：原风险 = 发布的 `target/modules/juice_core.jai` 以绝对路径 `#load` 开发树 `src/` 的插件面闭包（`transpile.jai`/`transpile_plugin.jai`/`lifecycle.jai`/`plugin.jai`），安装布局（exe + `modules/`，无同级 `src/`）一旦有插件注册、生成的 metaprogram `#import "juice_core"`，该闭包无法解析。处置 = 插件面闭包成为发布产物的一部分：四个闭包件逐字复制到 `<modules>/juice_internal/plugin_face/`，`juice_core.jai` 以模块相对路径 `#load` 它们（048 决定 5 spike：`#load` 在按名导入的模块内按包含该指令的文件目录解析）；`juice_core` 定义为工具提供的模块面、非工作区依赖，规范成员包删除 `DEP juice_core source="../../"`；受支持安装 = exe + 相邻 `modules/`（递归含 `juice_internal/`），不读同级 `src/`/`target/`（§9.2、§3.3）。证据 = 发布产物契约断言（仅相对 `#load`、每个目标在安装内、无构建根、四件与 `src/` 逐字节相等）+ 真安装布局全链 E2E（scratch 安装、真实成员包、lint 警告照常、测试执行、成员根套件全绿）+ 既有零插件安装布局 E2E 保持全绿（049/051，父 spec 048；2026-10-21 验收矩阵）。
12. **Package 面硬切（breaking change）**：`jaix`/`transpile` 移除后，旧 package.jai 在 manifest 求值期以未知成员失败；迁移 = `plugins` + `juice-plugin-jaix` options。无兼容 shim（用户拍板 2026-10-21）；迁移说明写入 spec 与 CONTEXT。
13. **PRESTEP host 的额外 spawn 与协议**：Phase 2 在有声明 hooks 插件时每个 build/test 多 spawn 一次 `jai`（生成 host driver，嵌入输入、记录文件输出）；零声明 hooks = 不 spawn。协议值用 `%XX` 编码；非零退出/输出缺失 = 命令失败；host 只跑 PRESTEP，不承担通用第三方宿主。
14. **成员插件工具面与 litter**：成员插件不发布 `scan_walk`，jaix 插件自带扫描；jaix CLI 的 CWD 固定到 `target/jaix-drivers/`，核心删除 `is_jaix_driver_litter`；旧包遗留 litter 由插件清理，未启用插件的包可能把遗留 litter 当源码扫描（迁移说明）。
15. **声明驱动的 lint 迁移**：lint 不再以根 DEP 激活，根包与 fixture 需在 `Package.plugins` 声明 `juice-plugin-lint`；成员仍由 `workspace.members` 提供，插件准备写 import shim。未声明的插件不参与行为面。
16. **插件 id 与一包一插件**：~~成员插件 id = 成员包名；v1 一个插件包只提供一个插件；声明 version 必须等于插件 version~~ **已被 2026-11-15 修订取代**：声明 `id` 是消费包内的引用名，外部插件用显式 `source` + `module` 定位，声明侧没有 `version`；一个插件模块只提供一个入口。不新增 devDependencies 分类。

**jaix-plugin effort 终态处置（2026-10-21，062）**：12 已交付（055 硬切——`Package.plugins` / `PLUGIN` / `PLUGIN_OPTION` 落地，旧字段/记录/两道门移除；旧 package.jai 在 manifest 求值期失败，无兼容 shim；迁移说明见 §2.1/§8.3）；13 已交付（060 host + 061 成员链——声明 hooks 插件时每次 build/test 多 spawn 一次 `jai`，零声明 hooks = 不 spawn；记录协议 `%XX` 编码 + 父进程严格解析 + 非零退出/缺失即失败；根包无 options 的 jaix 声明 = 每次多一次零效果 host spawn）；14 已交付（058/059 核心 litter 谓词删除；061 成员自带扫描与 litter 清理；jaix CLI CWD 固定 `target/jaix-drivers/`）；15 已交付（056 声明驱动 lint；根包与 lint fixture 在 `Package.plugins` 声明 `juice-plugin-lint`，成员由 `workspace.members` 提供）；16 已交付（056 一包一插件；成员插件 id 当时取成员包名）。该条目的声明 version 门与成员名/id 绑定已由 2026-11-15 修订移除（见 §2.7）。本 effort 的未来项登记在 `docs/implementation/jaix-plugin-map.md` 的 Not yet specified（外部插件坐标/抓取、通用 lifecycle host、非插件 devDependencies、Candidate 3、lint/插件面扩展、`.map` 消费方），不在本 effort 交付。

**阶段 3 终态处置（2026-10-20，039）**：1 出范围（特性请求素材，交付形态 = 静态内置注册表）；2 保留并记录（note 文本与消息面绑定 beta 0.2.009；精确匹配策略保留，官方 framework 落地后复核）；3 零使用（语义 spike 未做，本 effort 不消费；未来启用前先 spike）；4 已文档化（替换实现 = 换视图键；driver/metaprogram 会话产物不进键）；5 三汇与钩子失败中止语义已交付；观察类（lint）最终诊断形状已随 040 effort 交付（§8.2：findings 三汇 + 原始包相对路径 + 1 基坐标）；6 已兑现（封闭枚举只增不改 + 版本化注释）；7 出范围（第三方宿主）；8 出范围（未来特性）；9 已交付（键成分 + otter 独立版本分量）；10 已按既有解法交付（LNK1104 副本 hand-off、`cmd /c`、子进程 CWD 绝对路径、大小写近匹配拒绝）；11 已交付（2026-10-21，048 effort：插件面闭包随发布、成员零工具依赖、安装布局插件全链 E2E）。逐项处置表与证据见 `docs/implementation/old-juice-exit.md` §5。

## 12. 引用清单

研究文档（本目录）：

- `otter-refactor-research.md`：§1 package 兼容面/求值器/协议/校验门；§2 命令架构/seam 表；§3 插件接口泛化/宿主四路/Jai 约束；§4 模块系统/monorepo 布局/自举；§6 风险
- `plugin-auto-discovery.md`：§1 linkme 机制；§2 Jai 可行性判定（无段属性/无 link_name/无运行期顶层执行 E1/E2）；§2.2 #insert 反射边界；§4 两级推荐；§5 风险
- `plugin-lifecycle-hooks.md`：§1 阶段全映射（workspace/build/test/run/clean/bootstrap）；§2 十四 seam 清单；§3 挂载先例（jaix 三挂点/Transpile_Plugin 成对钩子）；§4 设计面；§5 约束与收敛
- `note-based-testing.md`：§1 note 机制实验（文本格式/枚举面/排序指导/文件来源隔离）；§2 juice EXPAND 已注 @test；§3 端到端设计；§4 覆盖面；§5 bootstrap 与 delta
- `cargo-style-monorepo.md`：§1-2 cargo 映射判定；§3 monorepo 实验；§4 布局定稿；§5 缺口清单；§6 混合 lib/bin（E1-E3）；§7 命名碰撞（E1-E7）

关键源码锚点（juice 仓库 2026-10-19 工作树）：`juice/modules/Juice.jai:97-118`；`juice/src/manifest.jai:23-95,97-226,244-277,338-346`；`juice/src/workspace.jai:8-207`；`juice/src/target.jai:102-196`；`juice/src/dependency.jai:58-142,393-424`；`juice/src/commands/{command,registry,build,test,clean}.jai`；`juice/src/dispatcher.jai:35-121`；`juice/src/transpile_plugin.jai:56-83,316,425-506`；`juice/build.jai:25-110`；`juice/docs/adr/0001/0004/0005/0006`；`jaix/src/plugin.jai:51-157`；`jaix/examples/embed-consumer/package.jai`

**jaix-plugin effort 设计锚点（2026-10-21，otter 工作树）**：`src/lifecycle.jai`（PRESTEP/阶段状态）、`src/plugin.jai`（Juice_Plugin/options/merge）、`src/plugin_scan.jai`（声明驱动扫描/注册）、`src/manifest.jai`（PLUGIN/PLUGIN_OPTION 协议）、`src/module.jai`（Package.plugins 定义源）、`src/commands/build.jai`、`src/commands/test.jai`（阶段编排）、`src/scan_walk.jai`（扫描骨架；litter 谓词移除）、`src/test_runner.jai`（driver/metaprogram 生成与 COMPILE front；注册消费）、`src/publication.jai`（插件面闭包发布）；`docs/implementation/jaix-plugin-map.md`（effort map + 054-062 票）；`CONTEXT.md`（领域词汇）。

**package-declaration-semantics effort 锚点（2026-11-15）**：`src/module.jai`（`Package`/`Product`/`Source`/`Dependency`/`Plugin_Declaration`/`Workspace_Config` 定义源）；`src/package_model.jai`（运行期归一化类型）；`src/manifest.jai`（`SCHEMA=2` 求值协议、`parse_manifest_data_strict`、迁移指引）；`src/target.jai`（产物发现与 `default_run`）；`src/workspace.jai`（最近声明、成员展开/排除、`select_workspace_packages`）；`src/dependency_resolution.jai`（来源、模块选择、可见性、环、Git 复用/离线）；`src/resolution_state.jai`（内容缓存/状态/XDG）；`src/plugin_scan.jai` + `src/plugin_host.jai`（插件来源、入口锚点、按包准备）；`src/commands/selection.jai`（共享选包与批量）；`src/publication.jai`（安装单元与兼容标记）；`docs/migrations/package-declarations.md`（迁移指南、E01–E10、A01–A16、证据索引）；`docs/design/package-declaration-presence-check.md`（省略状态实验）。

Jai 发行版（`C:/Users/maojiaxing/DevTools/jai`，beta 0.2.009）：`modules/Compiler/Compiler.jai`（Message_Typechecked 327-372、Code_Note 964-969、Code_Declaration 674-711、Code_Procedure_Header 1045-1099、Location.enclosing_load 545-560、compiler_report_errors_for_untyped_declarations_with_these_notes 1536）；`how_to/460`（@command 先例/排序指导/TYPECHECKED_ALL_WE_CAN 注入）；`modules/Metaprogram_Plugins.jai:22-87`；`modules/Autorun.jai`；`modules/Basic/module.jai`（目录模块入口惯例）

实验目录（本机，全部输出原文已录进研究文档）：

- `C:/Users/maojiaxing/AppData/Local/Temp/otter-discovery-research/`（A-E1/E2 无运行期顶层执行）
- `C:/Users/maojiaxing/AppData/Local/Temp/otter-note-research/`（note 枚举端到端）
- `C:/Users/maojiaxing/AppData/Local/Temp/otter-monorepo-research/`（cargo 式布局端到端 + libb 静默缺口）
- `C:/Users/maojiaxing/AppData/Local/Temp/otter-hybrid-research/`（混合 lib/bin E1-E3）
- `C:/Users/maojiaxing/AppData/Local/Temp/otter-juice-name-research/`（命名碰撞 E1-E7）

## 13. Testing 迁移（设计修订，2026-10-22，未实施）

本 effort（地图 `juice/issues/0065-map-test-migration-to-testing-package.md`）把测试库面迁入仓库根独立包 `jai/testing/`。**实施尚未开始**；本节只记录已定决策与对既有章节的影响面。落地前 §3/§7/§8/§9/§10 的现状描述仍以当前实现为准；落地后由收口票 0074 回写对应章节。

1. **Testing 定义源（0066 已定；2026-11 修订）**：Testing API 面住 `packages/juice/testing.jai`（发布源目录，prefixed 公开名，**不含 `@test`**）；juice 自己的 Testing 面自测过程留在 `src/module.jai`，永不进发布面——所以消费面天然零测试过程，不再需要段尾裁剪标记；testing 的裸名 `Testing.jai` 为权威面；juice `tests/` 新增整文件逐字节同步测试（testing 缺席 SKIP，漂移失败）。bootstrap/Build/Test 的 Testing 特例与发布树 8 件不变。
2. **testing 包布局（0067 已定）**：`testing/` = root 包；Testing 权威面 `testing/modules/Testing.jai`；包入口根 `testing/module.jai`（不提供 `#import "testing"` 面）；jaix AST 插件 = `testing/packages/Jaix_Plugin_Test_Block/` 成员包（`PACKAGE.name` 不变，零依赖，不作为独立 test root）。runtime 定位零改动（`testing_module_source` 的 in-package/global 两分支）；testing 源不随 juice 发布树携带。dev-time 定位 = `src/testing_location.jai`（`JUICE_TESTING_ROOT` > 兄弟 `../testing`）。
3. **文本 test-block 转换（0068 进行中）**：API 形状未定；推荐 host-neutral hook + 共享内核（testing 拥有转换与所需中立类型/lexer；juice 保留 `Transpile_Plugin` / runner / load 插件 / 保真门，薄适配；vendored 副本逐字节同步）。落位（root `modules/` vs `packages/` 成员）与发布树件数待定。
4. **测试发现（0075/0076 待决策）**：发现面迁入 testing 的切面、接口/协议、自包含与发布形态未定；文件扫描与 test 命令编排留在 juice。

详细决策与票链见地图；本节不替代票。
