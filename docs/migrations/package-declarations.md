# 包声明迁移指南（package-declarations）

本文件是 `issues/0087-spec-package-declaration-semantics.md` Implementation Decision 28–29 要求的人工迁移指南，也是
`src/manifest.jai` 两处诊断指向的文件：

- `src/manifest.jai:276` — `Unknown manifest record: %; see docs/migrations/package-declarations.md`
- `src/manifest.jai:416` — `[juice] Migration: docs/migrations/package-declarations.md; ...`

本文件以声明语义为主；§7 与相关入口说明同步 Testing 标准工作区成员迁移（`docs/spec.md` §13）的实施结果，状态为**已实施并验证（仅 Windows）**，证据见 [Testing 成员迁移验收记录](../implementation/testing-package-migration.md)。这不继承旧 Testing effort（`issues/0065` 及后续票）的外部包、转译/发现迁出或 jaix 范围，也不覆盖兄弟仓库；下文已有 A01–A16 证据仍是历史记录，不作为本次迁移的验收结果，也不因本轮成功改写为重新全量验收通过。

## 0. 结论先行

1. 新工具不保留旧声明的兼容解析，也不猜测迁移意图。旧字段在求值期被 Jai 编译器拒绝（`'type' is not a member of Package.`），
   或在校验期被拒（缺显式来源、空依赖模块清单等）。没有 `--legacy` 开关，没有自动改写。
2. 一个包的公开字段固定为 `name / version / description / modules / executables / dependencies / plugins / workspace / default_run`
   （`src/module.jai:51`）。`PACKAGE` 仍是唯一入口；`workspace` 仍是 `Package` 的普通嵌套字段。
3. 迁移是逐字段替换：`type`/`targets`/`main_file` → `modules`/`executables`/`entry`；依赖的 `version` 与同名包搜索 →
   显式 `source` + 模块选择；插件成员名猜测与 `version` → 显式 `source` + `module`；`build_script` 删除；`workspace` 保留并获得
   `default_members` 与单层 `*` 匹配。
4. 根包与全部成员必须一起迁移。工作区发现先加载并校验每个成员的声明，任一声明失败都会阻止整次操作，即使该成员未被选中
   （`src/workspace.jai:147` 起的 `discover_workspace`，以及 `src/commands/selection.jai` 在选包之前调用 discovery）。

## 1. 逐字段迁移表

### 1.1 `Package` 顶层字段

| 旧写法 | 新写法 | 迁移动作 | 依据 |
| --- | --- | --- | --- |
| `name = "x"` | `name = "x"` | 保留。包存在时必填且非空；语法 `[A-Za-z0-9][A-Za-z0-9._-]*` | Decision 2、6；`src/path_safety.jai:235` |
| `version = "0.1.0"` | `version = "0.1.0"` | 保留。包存在时必填且非空；不是依赖版本范围，也不参与 Git 修订选择 | Decision 2、13 |
| `description = "..."` | 同名字段 | 保留。可显式空字符串 | Decision 5 |
| `type = .BIN` / `.LIB` / `.UNSPECIFIED` | 删除 | 包不再有互斥角色。需要程序就声明 `executables`，需要导入面就声明 `modules`，两者可同时存在 | Decision 4；故事 5–6 |
| `targets = Target.[{name="a", main_file="src/main.jai"}]` | `executables = .[{name = "a", entry = "src/main.jai"}]` | 字段改名 + 元素改名。`main_file` → `entry`，路径语义不变（包内相对 `.jai` 文件） | Decision 4 |
| （旧模型无导入产物清单） | `modules = .[{name = "lib", entry = "module.jai"}]` | 新增。显式模块清单完全替代自动发现 | Decision 4 |
| `build_script = "build.jai"` | 删除 | 不再有自动调度的构建脚本。需要生成流程时用插件（派生视图）或先由独立脚本生成入口，再重新发现声明 | Decision 25 |
| `dir = "..."` | 删除 | `dir` 从来不是用户字段；运行期根路径仍不回填公开声明 | Decision 7 |
| （旧模型无运行默认） | `default_run = "a"` | 新增。省略时 run 按程序数选择；显式值必须匹配某个已声明程序 | Decision 5、19 |
| `jaix = ...` / `transpile = ...` | 已在 2026-10-21 修订删除；本次不变 | 用 `plugins` 表达 | 历史修订（spec §2.1） |

旧字段的拒绝是真实诊断，不是本指南的推断：

| 探针 | 结果 | 证据 |
| --- | --- | --- |
| `type = .BIN` | `Error: 'type' is not a member of Package.`，exit 1 | `target/evidence/probe-legacy-type.log` |
| `targets = Target.[...]` | `Error: 'targets' is not a member of Package.`，exit 1 | `target/evidence/probe-legacy-targets.log` |
| `build_script = "build.jai"` | `Error: 'build_script' is not a member of Package.`，exit 1 | `target/evidence/probe-legacy-build-script.log` |

### 1.2 依赖 `Dependency`

旧字段（`juice/modules/Juice.jai` 时代的形状）：`{name, version = "", source = "", package = ""}`。
新形状（`src/module.jai:31`）：`{name, source: Source, modules: [] Module_Selection}`。

| 旧字段 | 新写法 | 迁移动作 | 依据 |
| --- | --- | --- | --- |
| `name` | `name` | 保留。含义变为“消费包内的引用名”，不是提供方包名，也不自动成为导入名 | Decision 10、31 |
| `version` | 删除 | 不存在依赖版本约束、版本范围或锁文件。修订选择只有 Git `branch`/`tag`/`rev` 一处 | Decision 13；故事 42 |
| `source = ""` / 空来源 + 按包名搜索 | `source = .{kind = .PATH, path = "../lib"}`、`.{kind = .GIT, git = .{url = "..."}}` 或 `.{kind = .WORKSPACE}` | 显式来源。缺类型、多来源、载荷与类型不符都在协议解析期失败 | Decision 9；故事 23、27 |
| `package = "provider"`（按包名搜索 / `module`） | `modules = .[{path = "packages/provider", name = "provider_export", alias = "Import_Name"}]` | 用 `path`（来源根内的包目录）+ `name`（提供方导出名）+ `alias`（可选导入名）替代包名搜索 | Decision 10 |
| （旧模型无平铺多模块选择） | `modules` 可列多项，逐项给出包目录、导出名与别名 | 一条来源引用可平铺选择多个包的模块 | 故事 28 |

拒绝证据：

| 探针 | 结果 | 证据 |
| --- | --- | --- |
| `Dependency.[{name = "other"}]`（无来源，旧“按名搜索”形态） | `Invalid dependency source: choose PATH, GIT or WORKSPACE with matching payload`，exit 1 | `target/evidence/probe-legacy-name-search.log` |
| `Dependency.[{name="other", version="1.0.0", source="", package=""}]` | `Error: 'version' is not a member of Dependency.`，exit 1 | `target/evidence/probe-legacy-dependency.log` |
| 显式空模块清单 `modules = Module_Selection.[]` | `Dependency modules cannot be empty.`，exit 1 | `target/evidence/probe-empty-dependency-modules.log` |

### 1.3 插件 `Plugin_Declaration`

旧形状：`{id, version, options}`，id 直接按“内置名 / 成员包名”解析，成员插件靠成员名猜测定位。
新形状（`src/module.jai:45`）：`{id, builtin, source, module, options}`。

| 旧字段/行为 | 新写法 | 迁移动作 | 依据 |
| --- | --- | --- | --- |
| `id = "juice-plugin-lint"` 依赖成员名解析 | `id = "juice-plugin-lint"` + `source = .{kind = .PATH, path = "plugins/juice-plugin-lint"}` | `id` 变纯引用名；来源必须显式。外部插件不再要求重复写普通依赖，也不按成员名搜索 | Decision 21；故事 80 |
| `id = "load"` / `"test-block"` | `.{builtin = "load"}` / `.{builtin = "test-block"}` | 内置引用用 `builtin` 字段。`id` 可省略（默认取 `builtin` 值）；显式 `id` 必须等于 `builtin` | Decision 22；`src/manifest.jai` 的 `PLUGIN` 分支 |
| `version = "1.0.0"` | 删除 | 插件声明不再有版本。兼容性由安装单元的 `plugin_abi` 与插件自身 `Juice_Plugin.abi_version` 独立检查 | Decision 21/22；`src/publication.jai:718` |
| （无模块选择） | `module = .{path = "api", name = "example_plugin"}` | 选定提供方包目录与公开模块。该模块必须有且只有一个 `get_juice_plugin` + `@juice_plugin` 尾注入口 | Decision 21；`src/plugin_scan.jai:713` |
| `options = .[{key, value}]` | 保留 | 每个插件的 schema 决定默认值；重复键、未知键、非法值在 hook 之前失败 | Decision 22 |

拒绝证据：

| 探针 | 结果 | 证据 |
| --- | --- | --- |
| `Plugin_Declaration.[{id = "juice-plugin-lint", version = "1.0.0"}]` | `Error: 'version' is not a member of Plugin_Declaration.`，exit 1 | `target/evidence/probe-legacy-plugin.log` |
| `Plugin_Declaration.[{id = "juice-plugin-lint"}]`（旧成员名猜测形态） | `External plugin requires an explicit source.`，exit 1 | `target/evidence/probe-legacy-plugin-guess.log` |
| 同一插件启用两次（不同 id，同一模块） | `the same plugin is enabled twice (...)`，exit 1 | `target/evidence/e09-negative-duplicate-plugin.log` |
| 插件模块同时被普通依赖选择 | `plugin module is already selected by the ordinary dependency '...'`，exit 1 | `target/evidence/e09-negative-plugin-also-dependency.log` |
| 省略 `plugins`（内置 `load` + `test-block`） | 文件内 `test "..." {}` 块被转译，测试通过，exit 0 | `target/evidence/probe-plugins-omitted.log` |
| `plugins = Plugin_Declaration.[]` | test 块不再被转译，编译失败（`Semicolon expected after expression.`），exit 1 | `target/evidence/probe-plugins-empty.log` |

### 1.4 `workspace`：保留并扩展

| 字段 | 旧行为 | 新行为 | 依据 |
| --- | --- | --- | --- |
| `members` | 字面路径，无 glob；`exclude` 零消费方；根包靠 `type` 语义隐式成立 | 工作区内相对目录，支持单层 `*`（仅一个路径分量，前缀/后缀任意）；无匹配、越界、含链接目录都失败；根包（若存在）自动是成员且不能被排除 | Decision 16；`src/workspace.jai:8` |
| `exclude` | 未被消费 | 命中目录及其候选子树被剪除；无匹配的 exclude 合法 | Decision 16 |
| （旧模型无） | — | `default_members` 新增：只接受明确成员目录，无通配；省略用位置默认，空清单表示根调用没有默认选择 | Decision 17 |

`workspace` 仍是 `Package` 内的普通字段，不需要独立 `WORKSPACE` 入口，也允许“只有 workspace、没有包字段”的纯工作区。
显式空工作区可以写成 `workspace = .{}` 或 `workspace = .{members = string.[]}`：它是一个已声明但没有成员的工作区，
根调用时零选包失败（`No package was selected.`）。完全省略 `workspace` 且没有包字段才得到
`PACKAGE must declare a package or workspace.`（`src/manifest.jai:286`，探针 `probe-empty-declaration.log` / `probe-workspace-empty-object.log`）。

### 1.5 被删除的行为（不只是字段）

| 旧行为 | 新行为 | 依据 |
| --- | --- | --- |
| 依赖按包名搜索、找不到再回退 | 不做任何名字搜索：来源必须显式；缺声明、非法包目录、缺导出直接失败 | Decision 9、26 |
| 同名工作区成员覆盖 Git 来源 | 来源是声明事实。同名成员存在也不改变 Git 来源解析 | 故事 24；A02 |
| 相对 path 按命令 CWD 解释 | 普通 `path` 以声明包根为基准；Git 内部相对引用只能留在检出内 | Decision 8、12 |
| 传递依赖自动可导入 | 提供方自行声明依赖；提供方内部模块不会成为消费方的直接导入名 | Decision 11；故事 35–36 |
| 插件 id 按成员名/包名猜测 | 只按声明启用；外部插件给出 source + module | Decision 21 |
| 内置插件自动补入 | 省略 `plugins` = 内置 `load` + `test-block`；显式空 = 全禁用；非空 = 完全替换，不补默认 | Decision 22 |
| `build_script` 自动调度 | 字段删除；生成流程由插件派生视图承担，尚不存在的公开入口要先由独立脚本生成 | Decision 25 |

## 2. 省略 / 显式空 / 非空

省略状态不是“零长度数组”或“空字符串”判据：加载器用内部保留默认标记区分三者，用户仍然只写普通字符串与数组
（Decision 3、5）。下表是代码实际接受的结果（`src/manifest.jai`、`src/target.jai:51`、`src/workspace.jai:486`）。

| 字段 | 省略 | 显式空 | 显式非空 |
| --- | --- | --- | --- |
| `modules` | 自动发现：`module.jai` 或 `src/module.jai`；零候选 = 零模块；两者同时存在 = 歧义失败；唯一候选采用，名称取包名 | `Product.[]` = 零模块 | 完全替换自动发现；逐项 `entry` 必填；单项可省略 `name`（取包名），多项必须逐项命名 |
| `executables` | 自动发现：只有 `src/main.jai`（不扫描 `src/bin`） | `Product.[]` = 零程序 | 同上 |
| `dependencies` | 无依赖 | 无依赖 | 逐条解析；来源与模块选择必须合法 |
| `plugins` | 内置 `load` + `test-block` | `Plugin_Declaration.[]` = 没有任何插件（test block 不再被转译） | 只启用清单项 |
| `members` | 零显式成员 | 零显式成员 | 展开、去重、排除后逐个校验 |
| `exclude` | 无排除 | 无排除 | 命中即剪除 |
| `default_members` | 位置默认（见 §5） | 根调用没有默认选择（零选包 = 失败） | 只接受明确成员目录 |
| `description` | 空 | 空 | 原样保留 |
| `default_run` | 按程序数选择 | 不允许（空字符串是 `default_run` 显式空 = 失败） | 必须匹配已声明程序（ASCII 大小写不敏感比较） |

产品解析的真实失败信息：

| 探针 | 结果 | 证据 |
| --- | --- | --- |
| 省略 `modules` 且 `module.jai`、`src/module.jai` 同时存在 | `Both module.jai and src/module.jai exist; declare modules explicitly.`，exit 1 | `target/evidence/probe-neg-ambiguous-module.log` |
| 多项 `executables` 未逐项命名 | `Every item in a multiple-product list must declare name.`，exit 1 | `target/evidence/probe-neg-unnamed-products.log` |
| `default_run = "missing"` | `default_run must name a declared executable.`，exit 1 | `target/evidence/probe-neg-default-run.log` |
| 含连字符包名 `my-tools` + 省略 `executables`（自动程序名取包名） | `Product name must be a Jai identifier; provide an explicit legal name.`，exit 1 | `target/evidence/probe-auto-product-name-hyphen.log` |
| 同一包显式命名 `my_tools` | 构建并运行成功，exit 0 | `target/evidence/probe-pos-hyphen-name.log` |
| `PACKAGE :: Package.{}`（既无包字段也无 workspace） | `PACKAGE must declare a package or workspace.`，exit 1 | `target/evidence/probe-empty-declaration.log` |
| `workspace = .{}`（已声明空工作区） | 声明合法；根调用选包为 0，`No package was selected.`，exit 1 | `target/evidence/probe-workspace-empty-object.log` |
| `default_run = ""` | `default_run cannot be empty.`，exit 1 | `target/evidence/probe-default-run-empty.log` |

## 3. 名称与路径规则

- 包名、依赖引用名、插件 `id`：首字符 ASCII 字母或数字，后续 ASCII 字母、数字、`.`、`_`、`-`（`src/path_safety.jai:235`）。
- 模块名、程序名、导入名/alias、`options` 键：首字符 ASCII 字母或下划线，后续字母、数字、下划线（`src/path_safety.jai:248`）。
- 判重与匹配统一 ASCII 大小写不敏感，但保留原拼写，不修剪、不改写。模块与程序可以跨类别同名；同类重名失败。
- 自动名称仍须合法：含连字符的包名不能自动变成模块名或程序名（见上表），要么显式命名，要么改包名。
- 包内入口必须是包根内的现存普通 `.jai` 文件；不接受绝对路径、`..` 越界、目录、符号链接/junction
  （`src/target.jai:38` 的 `make_effective_target`）。
- 普通 `path` 依赖相对声明包根，可指向兄弟目录，但必须留在“消费包根的父目录”范围内（`src/dependency_resolution.jai`
  的 `resolution_sibling_boundary`）；Git 提供方内部的相对引用只能留在该检出内。
- Unicode 可用于描述、选项值与路径；标识符规则不转写、不折叠 Unicode 路径。

## 4. 依赖语义

### 4.1 三种来源

| `source.kind` | 必填载荷 | 定位基准 | 备注 |
| --- | --- | --- | --- |
| `.PATH` | `path`（非空）；`git` 全空 | 声明包根 | 相对路径；绝对路径也可，但边界规则相同 |
| `.GIT` | `git.url`（非空）；`path` 为空 | 所选提交的检出根 | `branch`/`tag`/`rev` 至多一个；全省略 = 仓库默认分支 |
| `.WORKSPACE` | `path`/`url`/selector 全空 | 声明包实际所属工作区根 | 提供方必须是该工作区成员；模块 `path` 指成员目录 |

### 4.2 模块选择

- `modules` 省略：把来源根当作提供方包目录，采用“唯一导出简写”。根不是包、零导出、多导出都失败。
- `modules` 非空：每项 `path`（来源根内包目录，省略 = `.`）+ `name`（提供方导出名，省略 = 唯一导出）+ `alias`（可选最终导入名）。
- 显式空清单是能力不匹配，协议期即失败。
- 同一实际模块在一个消费包内最多被选择一次；引用名、alias 或路径写法不同不豁免。
- 最终导入名不得覆盖本包模块、其他直接导入或编译器标准模块。
- 依赖图必须无环；环会打印完整链路（例：`app -> app`、`app -> alpha -> beta -> alpha`）。

### 4.3 可见范围

- 提供方包内模块可以互相按公开名引用：解析器把提供方内部的 `#import "<export>"` 重写到私有名，并写入消费工程私有的 shim 目录。
- 包**自己**在 `modules` 里声明的公开模块在本包内按公开名可用：本包程序和本包其他模块都可以写 `#import "<本包导出名>"`。
  这些 shim 落在本包自己的 `target/packages/`（包私有），所以不同包可以声明同名模块，一个包的模块名不会变成另一个包的导入名。
  文件级 `#load` 仍然可用，两种写法不冲突。验收用例：`dependency_resolution_own_module_public_import`（本包程序与本包模块互相引用，`build`/`run`）、
  `dependency_resolution_own_module_workspace_members`（工作区成员，成员间同名模块互不覆盖）、`dependency_resolution_own_module_in_test_source`（`test` 的测试程序）。
- **Testing 成员迁移补充（已实施并验证）**：标准入口 `module.jai` / `src/module.jai` 的测试加载去重计入生成 driver 隐式发出的 `#import "Testing"`，不能只检查手写 import；已通过模块导入的入口不再由扫描清单重复 `#load`。按单名生成的本包 shim 目录置于该次编译导入路径首位，保证 `testing` 成员解析到自己的 `src/module.jai`，而非安装单元的 `Testing.jai`；不以特殊源码 `modules/` 目录规避重入。本轮验证结果见 §7 与 [验收记录](../implementation/testing-package-migration.md)，不由上一条既有用例替代背书。
- 传递依赖不会泄漏为消费方的直接导入名：`#import` 提供方的传递模块仍然失败（`dependency_resolution_transitive_visibility`）。
- 依赖的最终导入名不得覆盖本包模块、其他直接导入或编译器标准模块：该冲突在解析阶段报错（`dependency_resolution_module_identity_and_name_conflicts`）。

### 4.4 Git 修订与工程上下文

- `branch`/`tag`/`rev` 互斥；显式空 selector 失败；没有版本范围、提供方包名断言或锁文件。
- 已解析的选择由普通 `build`/`run`/`test` 复用，不访问远端追新。E07 证明：提供方分支前进后重建仍使用记录提交。
- `juice update` 刷新所选消费包的完整 Git 依赖图；只改引用名/alias/模块清单不换提交。
- `--offline` 只使用已有记录与完整内容；缺记录时只有“完整提交 id + 内容已缓存”可建立选择，浮动/短修订失败。
- 内容缓存与选择状态分目录，遵守 XDG 契约；移动工程根产生新上下文，只改 CWD 不变。
- 状态损坏是错误，不会当成首次解析。

## 5. 工作区与选包

- 命令从 CWD 向上找最近的 `package.jai`（`src/workspace.jai:124`）；最近声明无效时立即失败，不跳到上层。
- 成员展开：明确目录 + 单层 `*`；`**`、`?`、`{}`、`[]` 等模式非法；无匹配失败；成员目录必须是根内真实目录且含 `package.jai`；
  重叠匹配按实际目录去重；嵌套工作区形成边界，外层收录其根或成员且未排除时失败。
- 根包（存在时）自动是成员且不能被 `exclude` 排除；纯工作区没有隐含成员。
- 未被收录或被排除的包仍可独立运行（在它自己的根内）。
- 位置默认（`src/workspace.jai` 的 `select_root_defaults`）：
  - 在某个成员内调用：只选该成员；
  - 在根调用、纯工作区、`default_members` 省略：选全体成员；
  - 在根调用、有根包、`default_members` 省略：只选根包；
  - `default_members` 显式：替换默认，只接受明确成员目录；空清单 = 没有默认选择（失败）。
- 显式选包：`--workspace`（全体成员含根包，与另外两个参数互斥）、`-p/--package <name>`、`--package-path <dir>`；
  显式集合替代默认，按包身份去重，按工作区相对目录稳定排序；未知名字、重名歧义、非成员路径、零选包都在执行前失败。

## 6. 命令行为

| 命令 | 选包 | 行为 |
| --- | --- | --- |
| `juice build` | 共享选包 | 编译所选包的全部程序；零程序仍校验声明与依赖，然后报告没有可执行产物；批量在首个失败停止并报告已完成/失败/未执行 |
| `juice run [program] [-- args...]` | 必须恰好一个包 | 程序选择序：显式名 → `default_run` → 唯一程序；只编译该程序；`--` 之后原样转交；子进程退出码成为命令退出码 |
| `juice test [pattern]` | 共享选包 | 不需要公开产物；过滤条件逐包应用（子串、大小写敏感）；零测试/零命中都成功报告；声明与编译错误不会被过滤隐藏 |
| `juice update` | 共享选包 | 只刷新解析图；拒绝 `--offline`；不编译、不执行测试、不运行插件 hook |
| `juice clean` / `version` / `help` | 无选包面 | 行为未在本次变更范围内改写 |

`--offline` 由 `build`/`run`/`test` 接受。完整选包基数和参数冲突在任何编译之前校验；`run` 不会为了猜测意图而筛掉没有程序的包。

本表同时来自代码与 0091–0094 的测试证据。本指南的 E01–E10 直接执行了 build/run/test/update 的选包、零产物与 Git 复用分支；
**批量“首个失败即停并报告未执行范围”的失败分支没有在示例中执行**（`command_selection_first_failure_cli` 覆盖于 0093 的实现测试）。

## 7. 安装单元

可执行文件与相邻的 `modules/` 目录构成一个完整安装单元（`src/path_safety.jai:37` 的 `juice_modules_dir`）。启动时先检查
`<exe>/modules/juice_internal/install_manifest.txt` 的格式、兼容性 epoch、插件 ABI 与逐件内容摘要
（`src/publication.jai:718`）。缺失、混装、被替换的发布件都会在命令开始前失败；没有其他安装目录回退，也没有用户兼容开关。
因此本指南的所有命令都要求 `juice.exe` 与 `modules/` 相邻；把 `target/juice.exe` 单独复制走不能运行。

**Testing 标准成员迁移（已实施并验证，仅 Windows）**：安装布局保持不变，改变的是定义源与测试归属；本轮证据见 [Testing 成员迁移验收记录](../implementation/testing-package-migration.md)。

- **Juice 声明发布源目录保留**：`packages/juice/module.jai` 仍只承载包声明词汇；该目录无 `package.jai`，不是工作区成员。发布时整文件读取并加标准导入头，生成 `modules/Juice/module.jai`。是否存在 `package.jai` 只影响包身份，并不单独决定发布模块是否可搬迁；可搬迁性由完整安装闭包保证。
- **Testing 改为标准成员**：`packages/testing/package.jai` 声明 `name = "testing"`，显式 `modules = .[.{name = "Testing", entry = "src/module.jai"}]`、`executables = Product.[]`，纳入根工作区。唯一实现是 `packages/testing/src/module.jai`：公开 API 使用裸名、不含 `@test`；不再保留 `packages/juice/testing.jai` 或第二份 prefixed/vendored 实现。
- **发布直接复制**：build 直接读取成员 `src/module.jai`，逐字节复制到 `modules/Testing.jai`；不拼导入头、不剥前缀、不规范化换行。安装后仍可 `#import "Testing"`，普通消费方无需声明 dependency，也不读取仓库内成员路径。自举源码只取自仓库，不依赖兄弟检出、已安装 Testing 或同步步骤。
- **测试归成员，根留集成**：断言、失败状态、`run` / `finish`、`path_mapping` 等行为自测迁到 `packages/testing/tests/`，测试样例位于 `packages/testing/tests/data/`。成员以 **1 个综合子进程行为自测**覆盖 pass/fail、格式文案、defer/return、reset/mapping，故意失败与状态重置不污染外层测试状态。根 `src/module.jai` 只 `#load` Juice 声明源，Testing load、前缀实现与 `strip_testing_prefix` 已删除。根测试只保留与 Testing 有关的发布、安装与命令集成验证。
- **选包使用标准规则**：在 `packages/testing/` 内 `juice test` 独立测试该成员；根 `juice test --workspace` 包含它；根默认 `juice test` 仍只选根包。标准入口去重与单名 shim 的优先级见 §4.3，不创建特殊源码 `modules/` 目录。

段标记协议（`// [PUBLICATION-SECTION …]` / `// [PUBLICATION-CUT …]`、扫描器、段抽取）已退役；本次迁移不恢复段裁剪。Testing 的 test-free 保证来自唯一实现与成员 `tests/` 的结构分离，而不是段尾标记或前缀转换。`src/module.jai` 保留标准入口路径（spec §2.3），不再承担 Testing 自测。

旧 `../testing` 兄弟包、`JUICE_TESTING_ROOT` 与 vendored 同步方案全部废弃；转译、发现与 jaix 迁出不在本次范围。

**本轮验证结果（仅 Windows）**：`jai build.jai`、Testing 成员 `juice test`、根新增 `testing_package_declared` 回归均 exit 0。完整 `target/juice-testing-verify.exe test --workspace` exit 0，耗时 **1412.4s**；root **668 passed / 0 failed**、Testing **1 / 0**、jaix **17 / 0**、lint **3 / 0**。测试包含 debug/release 自举、安装搬迁及负向用例，运行后 `target/recovery` 为空；完整日志为 `target/evidence/testing-package-workspace.log`。

`packages/testing/src/module.jai` 与 `target/modules/Testing.jai` 均为 **2542 字节**、逐字节完全相同，SHA-256 均为 `3ef4ac1c0ca0904869921c6418f1d47ea8b924fbb8aac47902cc1e613ca2162e`。上述结果及范围见 [验收记录](../implementation/testing-package-migration.md)；**Linux 与大小写敏感文件系统未验证**。下文 A01–A16 的历史证据不变，不把本次迁移成功泛化为旧矩阵重新全量验收。

## 8. 证据规则

- 标注 **已执行** 的行为都附 `target/evidence/` 下的日志文件名（工作树未提交的临时证据区）与退出码。
- 标注 **未执行** 的行为本环境没有跑过，不宣称成功。
- 全部示例在 Windows 10/11 + `jai 0.2.9` 上执行；没有 Linux 或大小写敏感文件系统运行。不得把 Windows 结果当作跨平台结论。
- 示例由 `target/evidence/reproduce-examples.sh` 一次性重建并逐个执行；`target/evidence/migration-examples-index.txt`
  记录每次调用的 CWD、参数与退出码。脚本要求 `JUICE_HOME` 指向含 `juice.exe` + `modules/` 的安装目录，`JUICE_SOURCE`
  指向本仓库（E08/E09 复制仓库自带的插件成员包）。脚本使用独立 scratch 根与独立 XDG cache/state，不读写真实用户状态。

---

# 完整人工迁移示例 E01–E10

每个例子给出：目录树、完整 `PACKAGE`、必要源码、调用位置与命令、成功/失败预期、执行证据。
`juice` 指安装目录里的可执行文件；所有例子都在自己的 scratch 目录下运行。

## E01 最小程序

覆盖：最小包、省略 `executables` 时的固定候选、自动程序名。

```
E01-minimal/
├── package.jai
└── src/
    └── main.jai
```

`package.jai`：

```jai
#import "Juice";

PACKAGE :: Package.{
    name    = "hello",
    version = "0.1.0",
};
```

`src/main.jai`：

```jai
#import "Basic";

main :: () {
    print("hello from juice\n");
}
```

- CWD：`E01-minimal`
- 命令与预期：
  - `juice build` → 成功。省略 `executables`，工具只探测 `src/main.jai`，程序名取包名 `hello`，产物为 `target/hello.exe`。
  - `juice run` → 成功，打印 `hello from juice`；唯一程序被选中。
- 证据：`target/evidence/e01-build.log`（exit 0）、`target/evidence/e01-run.log`（exit 0）。

## E02 只有模块

覆盖：`module.jai` 自动模块候选、零程序构建、`run` 的零程序失败。

```
E02-module/
├── package.jai
├── module.jai
└── src/            （空目录：保留包结构，不含程序）
```

`package.jai`：

```jai
#import "Juice";

PACKAGE :: Package.{
    name    = "greeting",
    version = "0.1.0",
};
```

`module.jai`：

```jai
#import "Basic";

greet :: (who: string) -> string {
    return tprint("hello, %", who);
}
```

- CWD：`E02-module`
- 命令与预期：
  - `juice build` → 成功，报告没有可执行程序：`Package '.' has no executable program; declarations and dependencies validated, module sources are not type-checked.`
    声明与依赖已校验，但不承诺对未使用模块做类型检查。
  - `juice run` → 失败（exit 1）：`Package 'greeting' has no executable program to run.`
- 证据：`target/evidence/e02-build.log`（exit 0）、`target/evidence/e02-run.log`（exit 1）。

## E03 模块 + 多个程序

覆盖：`modules` 与 `executables` 同时存在、逐项命名、`default_run`、只编译被选程序、未知程序失败、本包模块的可用方式。

```
E03-multi/
├── package.jai
├── module.jai
└── src/
    ├── adder.jai
    └── echoer.jai
```

`package.jai`：

```jai
#import "Juice";

PACKAGE :: Package.{
    name    = "toolbox",
    version = "0.1.0",

    modules = .[
        .{name = "calc", entry = "module.jai"},
    ],
    executables = .[
        .{name = "adder", entry = "src/adder.jai"},
        .{name = "echoer", entry = "src/echoer.jai"},
    ],
    default_run = "echoer",
};
```

`module.jai`：

```jai
#import "Basic";

add :: (left: s64, right: s64) -> s64 {
    return left + right;
}
```

`src/adder.jai`（本包模块也可按公开名导入，见 §4.3；此处保留文件级加载）：

```jai
#import "Basic";
#load "../module.jai";

main :: () {
    print("adder %\n", add(19, 23));
}
```

`src/echoer.jai`：

```jai
#import "Basic";

main :: () {
    print("echoer\n");
}
```

- CWD：`E03-multi`
- 命令与预期：
  - `juice build` → 成功，两个程序都编译。
  - `juice run` → 成功，`default_run = "echoer"` 生效，打印 `echoer`；不会编译 `adder`。
  - `juice run adder` → 成功，打印 `adder 42`。
  - `juice run nosuch` → 失败（exit 1）：`Package 'toolbox' has no program named 'nosuch'.`
- 证据：`target/evidence/e03-build.log`（exit 0）、`e03-run-default.log`（exit 0）、`e03-run-adder.log`（exit 0）、
  `e03-run-unknown.log`（exit 1）。

## E04 纯工作区

覆盖：只有 `workspace` 的声明、单层 `*` 成员、纯工作区根默认选全体、`--workspace`、`run` 的基数校验。

```
E04-pure-workspace/
├── package.jai
└── apps/
    ├── one/
    │   ├── package.jai
    │   └── src/main.jai
    └── two/
        ├── package.jai
        └── src/main.jai
```

`package.jai`（没有 `name`/`version`，纯工作区不建立根包）：

```jai
#import "Juice";

PACKAGE :: Package.{
    workspace = .{
        members = string.["apps/*"],
    },
};
```

两个成员各自声明 `name = "one"` / `name = "two"`、`version = "0.1.0"`，程序源码分别打印 `one` 与 `two`。

- CWD：`E04-pure-workspace`
- 命令与预期：
  - `juice build` → 成功。纯工作区根、`default_members` 省略，默认选全体成员，两个程序都编译。
  - `juice build --workspace` → 成功，同样覆盖两个成员。
  - `juice run --workspace` → 失败（exit 1）：`run requires exactly one selected package; 2 selected: apps/one, apps/two.`
- 证据：`target/evidence/e04-build-default.log`（exit 0）、`e04-build-workspace.log`（exit 0）、
  `e04-probe-run-workspace.log`（exit 1）。

## E05 根包 + 工作区

覆盖：根包本身是工作区成员、`default_members`、`--workspace`、成员内调用默认选当前包、`-p`、`--package-path`、未知名字。

```
E05-root-workspace/
├── package.jai
├── src/main.jai
└── libs/
    └── api/
        ├── package.jai
        └── src/main.jai
```

`package.jai`：

```jai
#import "Juice";

PACKAGE :: Package.{
    name    = "rootapp",
    version = "0.1.0",

    executables = .[
        .{name = "rootapp", entry = "src/main.jai"},
    ],
    workspace = .{
        members         = string.["libs/*"],
        default_members = string.["libs/api"],
    },
};
```

`libs/api/package.jai` 声明 `name = "api"`、`version = "0.1.0"`、省略 `executables`，`src/main.jai` 自动成为程序 `api`。

- CWD 与命令：
  - CWD `E05-root-workspace`，`juice build` → 成功，只构建 `default_members` 里的 `api`（根包不在默认集合内）。
  - CWD `E05-root-workspace`，`juice build --workspace` → 成功，构建 `rootapp` 与 `api`。
  - CWD `E05-root-workspace/libs/api`，`juice build` → 成功，成员内调用只选当前成员 `api`。
  - 同一棵树删掉 `default_members` 后在根调用 `juice build` → 成功，只构建根包 `rootapp`（有根包且默认省略时选根包）。
  - `juice build -p rootapp`、`juice build --package-path libs/api` → 成功。
  - `juice build -p nosuch` → 失败（exit 1）：`Unknown package name: nosuch`。
- 证据：`target/evidence/e05-build-default.log`、`e05-build-workspace.log`、`e05-build-inside-member.log`（均 exit 0）；
  `e05-probe-root-default.log`、`e05-probe-by-name.log`、`e05-probe-by-path.log`（exit 0）；
  `e05-probe-unknown-name.log`（exit 1）。

## E06 PATH + WORKSPACE 依赖

覆盖：两种显式本地来源、模块平铺选择、传递依赖边界、WORKSPACE 路径必须指成员目录。

```
E06-dependencies/
├── app/
│   ├── package.jai
│   ├── src/main.jai
│   └── libs/
│       └── units/
│           ├── package.jai
│           └── module.jai
└── sibling-lib/
    ├── package.jai
    └── module.jai
```

`app/package.jai`：

```jai
#import "Juice";

PACKAGE :: Package.{
    name    = "app",
    version = "0.1.0",

    dependencies = Dependency.[
        .{
            name    = "units",
            source  = .{kind = .WORKSPACE},
            modules = .[.{path = "libs/units", name = "units"}],
        },
        .{
            name   = "sibling",
            source = .{kind = .PATH, path = "../sibling-lib"},
        },
    ],
    workspace = .{
        members = string.["libs/units"],
    },
};
```

`app/src/main.jai`：

```jai
#import "Basic";
#import "units";
#import "sibling";

main :: () {
    print("units=% sibling=%\n", unit_name(), sibling_name());
}
```

两个提供方各有 `package.jai`（`name = "units"` / `name = "sibling"`）与根部 `module.jai`，导出 `unit_name` / `sibling_name`。
WORKSPACE 依赖的模块 `path` 是工作区根相对的成员目录；PATH 依赖是相对 `app/` 包根的兄弟目录。

- CWD：`E06-dependencies/app`
- 命令与预期：
  - `juice run` → 成功，打印 `units=member sibling=sibling`。两个模块按各自导出名导入；`sibling` 未写 `modules`，走唯一导出简写。
  - 若把 WORKSPACE 依赖的模块 `path` 省略（只写 `name = "units"`），来源根成为工作区根，提供方变成根包自己 → 失败（exit 1）：
    `Dependency package cycle: app -> app`。这是真实的声明错误，不是工具猜测修复的对象。
- 证据：`target/evidence/e06-run.log`（exit 0）、`e06-probe-cycle.log`（exit 1）。

## E07 Git 上下文

覆盖：显式 Git 来源、默认分支、选择记录复用、`update` 刷新、离线运行。

```
E07-git-context/
├── provider/                 （本地 Git 仓库，提供方包 greeter）
│   ├── package.jai
│   └── module.jai
└── consumer/
    ├── package.jai
    └── src/main.jai
```

`consumer/package.jai`（`url` 指向本次验收使用的本地仓库；远端 URL 的写法完全相同）：

```jai
#import "Juice";

PACKAGE :: Package.{
    name    = "consumer",
    version = "0.1.0",

    dependencies = Dependency.[
        .{
            name   = "greeter",
            source = .{kind = .GIT, git = .{url = "<absolute path to provider>"}},
        },
    ],
};
```

`consumer/src/main.jai`：

```jai
#import "Basic";
#import "greeter";

main :: () {
    print("greeting=%\n", greeting());
}
```

提供方第一个提交的 `greeting()` 返回 `from-commit-one`，第二个提交返回 `from-commit-two`，之后又移动到第三个提交
`from-commit-three`。

- CWD：`E07-git-context/consumer`，使用独立的 `XDG_CACHE_HOME` / `XDG_STATE_HOME`。
- 命令与预期：
  - 首次 `juice run` → 成功，`greeting=from-commit-two`（默认分支当时的提交被记录）。
  - 提供方分支前进后再次 `juice run` → 成功，仍是 `greeting=from-commit-two`：普通构建复用记录，不追新。
  - `juice update` → 成功，`Dependency resolution graph updated.`；不编译。
  - `juice run` → 成功，`greeting=from-commit-three`。
  - `juice run --offline` → 成功，仍为 `from-commit-three`：记录与内容都齐全。
- 证据：`target/evidence/e07-run-first.log`、`e07-run-reuse.log`、`e07-update.log`、`e07-run-after-update.log`、
  `e07-run-offline.log`（全部 exit 0）。

## E08 lint 插件

覆盖：外部插件显式 PATH 来源、模块入口约定、lint 观察结果与退出码。

```
E08-lint/
├── package.jai
├── tests/example_tests.jai
└── plugins/
    └── juice-plugin-lint/    （仓库自带的 lint 插件成员包，原样复制）
        ├── package.jai
        └── module.jai
```

`package.jai`：

```jai
#import "Juice";

PACKAGE :: Package.{
    name    = "linted",
    version = "0.1.0",

    plugins = Plugin_Declaration.[
        .{builtin = "load"},
        .{builtin = "test-block"},
        .{
            id     = "juice-plugin-lint",
            source = .{kind = .PATH, path = "plugins/juice-plugin-lint"},
        },
    ],
};
```

`tests/example_tests.jai`：

```jai
#import "Testing";

camelCaseTestName :: () {
    expect(1 + 1 == 2);
} @test
```

- CWD：`E08-lint`
- 命令与预期：`juice test` → 成功（exit 0）。测试通过（`1 passed, 0 failed`），同时输出一条 WARNING：
  `tests/example_tests.jai:3,22: Warning: [juice lint] test procedure name must be snake_case: camelCaseTestName`。
  v1 lint 是 advisory，WARNING 不改变退出码。路径是原始包相对路径，不是视图路径。
- 证据：`target/evidence/e08-test.log`（exit 0）。

## E09 jaix 插件 + 普通 API

覆盖：外部插件与普通依赖并存、同一提供方的“插件模块 + API 模块”双角色、内置插件显式声明、jaix 的声明即可用、两类负例。

```
E09-jaix-and-api/
├── package.jai
├── src/main.jai
├── api/
│   ├── package.jai
│   ├── api.jai          （普通 API 模块）
│   └── plugin.jai       （插件模块）
└── plugins/
    └── juice-plugin-jaix/   （仓库自带的 jaix 插件成员包，原样复制）
```

`package.jai`：

```jai
#import "Juice";

PACKAGE :: Package.{
    name    = "app",
    version = "0.1.0",

    executables = .[
        .{name = "app", entry = "src/main.jai"},
    ],
    dependencies = Dependency.[
        .{
            name    = "api",
            source  = .{kind = .WORKSPACE},
            modules = .[.{path = "api", name = "api"}],
        },
    ],
    plugins = Plugin_Declaration.[
        .{builtin = "load"},
        .{builtin = "test-block"},
        .{
            id     = "example-plugin",
            source = .{kind = .WORKSPACE},
            module = .{path = "api", name = "example_plugin"},
        },
        .{
            id     = "juice-plugin-jaix",
            source = .{kind = .PATH, path = "plugins/juice-plugin-jaix"},
        },
    ],
    workspace = .{
        members = string.["api"],
    },
};
```

`api/package.jai`：

```jai
#import "Juice";

PACKAGE :: Package.{
    name    = "api",
    version = "0.1.0",

    modules = .[
        .{name = "api", entry = "api.jai"},
        .{name = "example_plugin", entry = "plugin.jai"},
    ],
};
```

`api/api.jai`：

```jai
#import "Basic";
api_value :: () -> s64 { return 42; }
```

`api/plugin.jai`：

```jai
#import "juice_core";

Example_Plugin :: struct {
    using base: Juice_Plugin;
}

EXAMPLE_PLUGIN_VALUE : Example_Plugin = .{
    base = .{id = "example-plugin", version = "1.0.0"},
};

get_juice_plugin :: () -> *Juice_Plugin {
    return as_plugin(*EXAMPLE_PLUGIN_VALUE);
} @juice_plugin
```

`src/main.jai`：

```jai
#import "Basic";
#import "api";

main :: () {
    print("api value=%\n", api_value());
}
```

- CWD：`E09-jaix-and-api`
- 命令与预期：
  - `juice build` → 成功。插件准备解析两个外部插件：`example-plugin` 来自同一提供方的另一个导出，
    `juice-plugin-jaix` 是仓库自带的成员插件包；jaix 未写 `config` option，是已定义的 no-op 前置。普通依赖 `api` 与插件模块互不替代。
  - `juice run` → 成功，打印 `api value=42`。
  - 负例 1：把 `example_plugin` 也加进普通依赖的 `modules` → 失败（exit 1）：
    `plugin module is already selected by the ordinary dependency 'api': example-plugin`。同一实际模块不能兼任两种角色。
  - 负例 2：用第二个 `id` 再启用同一个插件模块 → 失败（exit 1）：
    `the same plugin is enabled twice ('example-plugin' and 'example-plugin-copy' select example_plugin)`。
- 证据：`target/evidence/e09-build.log`（exit 0）、`e09-run.log`（exit 0）、
  `e09-negative-plugin-also-dependency.log`（exit 1）、`e09-negative-duplicate-plugin.log`（exit 1）。

## E10 零产物

覆盖：显式空模块与程序清单、零产物构建、零产物测试、`run` 失败。

```
E10-zero-products/
├── package.jai
└── tests/check.jai
```

`package.jai`：

```jai
#import "Juice";

PACKAGE :: Package.{
    name        = "internal-only",
    version     = "0.1.0",
    modules     = Product.[],
    executables = Product.[],
};
```

`tests/check.jai`：

```jai
#import "Testing";

check_internal_rule :: () {
    expect(2 + 2 == 4);
} @test
```

- CWD：`E10-zero-products`
- 命令与预期：
  - `juice build` → 成功（exit 0），报告没有可执行程序；显式空清单关闭了一切自动发现。
  - `juice run` → 失败（exit 1）：`Package 'internal-only' has no executable program to run.`
  - `juice test` → 成功（exit 0），`1 passed, 0 failed`。测试用途不依赖公开产物。
- 证据：`target/evidence/e10-build.log`（exit 0）、`e10-run.log`（exit 1）、`e10-test.log`（exit 0）。

---

# A01–A16 验收对照

“示例”列是本指南中实际执行的例子；“状态”区分 **已执行** 与 **未执行**（本指南未跑，不宣称通过）。
验收票 0096 负责在发布模块上做完整验收，其结果记录在
[`docs/implementation/package-declaration-acceptance.md`](../implementation/package-declaration-acceptance.md)
（A01–A16 与 E01–E10 映射、三条发布路径、新补的真实 CLI 用例名与红证据、明确未验证项）。
本表只说明迁移文档覆盖到哪里；“0096 验收”列指明该组由哪个测试或哪条记录背书。

| 验收组 | 对应示例/章节 | 本指南状态 | 0096 验收 |
| --- | --- | --- | --- |
| A01 声明与旧字段 | §1 逐字段表、E01–E05、E10；旧字段探针 `probe-legacy-*.log` | 已执行（声明形状与拒绝）；`workspace` 保留见 E04/E05 | `declaration_schema_` 11/0、`declaration_loader_` 3/0；`acceptance_a13_unselected_invalid_member_blocks` 在真实 CLI 上复现旧字段拒绝 |
| A02 工作区与 Git 同名 | E06、E07；§4.4、§5 | 部分：来源显式与 Git 复用已执行；同名成员不覆盖 Git 来源未构造专门示例 | `dependency_resolution_workspace_source_membership`；新增 `acceptance_a02_member_does_not_override_git_source` |
| A03 来源资格与去重 | E06（PATH/WORKSPACE）、E09（插件模块去重）、§4.2 | 已执行（来源资格、重复模块失败）；不同来源/修订同名包并存未单独执行 | `dependency_resolution_module_selection_rules`、`_module_identity_and_name_conflicts`；新增 `acceptance_a03_same_name_sources_coexist`、`_same_name_revisions_coexist` |
| A04 传递可见性 | §4.3；提供方内部导入探针 `probe-provider-internal-module-import.log`；环探针 `e06-probe-cycle.log` | 部分：提供方内部模块与环已执行；完整多跳环链路未单独执行 | `dependency_resolution_package_cycle_reports_chain`（`app -> alpha -> beta -> alpha`）、`_transitive_visibility`、`_own_module_*` 三个用例 |
| A05 普通引用与插件 | E09 两个负例 | 已执行 | `plugin_derived_duplicate_enablement_cli`、`plugin_derived_ordinary_dependency_roles_cli` |
| A06 插件默认与配置 | §2 三态表；E08/E09；探针 `probe-plugins-omitted.log`（省略 = 内置）、`probe-plugins-empty.log`（空 = 全禁用） | 部分：三态已执行；坏 options 在 hook 前失败的迁移示例未执行 | `plugin_derived_options_errors_cli`（未知/必填缺失/重复键，hook 前失败）、`plugin_derived_builtin_triad_cli`/`_resolver`/`_test_cli`、`plugin_host_tests.jai` options 拒绝 E2E |
| A07 多程序与批量插件 | E03、E04、E05 | 已执行（只编译被选程序、批量选包）；包级准备一次未在示例中直接观察 | `plugin_derived_prepare_once`（同包 `prepare_count == 1`、各包私有派生区）、`plugin_derived_unselected_member_isolation_cli`、`run_selection_only_selected_program_cli` |
| A08 派生输出 | §1.5、§4.3 | 未执行（需要插件派生视图用例） | `plugin_derived_view_rules`（substitute/drop/generated 冲突矩阵、本轮注册表即视图、保留源码不可覆盖）、`plugin_host_tests.jai` 替换/drop/逻辑路径 E2E、`plugin_derived_git_source_read_only_cli` |
| A09 离线解析 | E07 `--offline`；§4.4 | 部分：有记录时离线成功已执行；无记录/浮动/短修订拒绝未执行 | `dependency_resolution_offline_matrix`（浮动/短修订/缺内容拒绝、完整提交且内容已缓存例外）、`_git_content_restore` |
| A10 更新与失败 | E07 `update`；§4.4 | 部分：全图刷新已执行；失败保旧状态、成员隔离、`update --offline` 冲突未执行 | `dependency_resolution_git_reuse_and_update`（含 `update --offline`）、`_context_isolation`、`_failure_preserves_old_state`、`command_selection_update_scope_cli` |
| A11 内容与状态 | §4.4、§7 | 未执行（清缓存不清选择、损坏状态、移根新上下文、XDG 回退） | `dependency_resolution_git_content_restore`、`_corrupt_state_fails`；新增 `acceptance_a11_moved_root_is_new_context`、`_xdg_relative_falls_back` |
| A12 提供方内部来源 | §4.3；Git 内部相对引用未构造 | 未执行 | `dependency_resolution_git_checkout_boundary`（检出内兄弟包、越界拒绝、检出只读）；新增 `acceptance_a12_git_provider_workspace_boundary`（检出内工作区不借消费者成员） |
| A13 成员校验与扫描 | §0 结论 4、§5 | 部分：未选中成员的声明错误会阻止操作来自代码路径；下级包测试不混入未执行 | `workspace_products_child_scan_boundary_cli`；新增 `acceptance_a13_unselected_invalid_member_blocks`（`build`/`run`/`test` 三命令） |
| A14 命令选择与零集合 | E02、E04、E05、E10；§5、§6 | 已执行（默认/显式集合、`run` 基数、零程序/零测试、未知名字） | `command_selection_` 7/0、`run_selection_` 12/0 |
| A15 跨文件系统路径 | §3；连字符包名探针 | 部分：Windows 下名称/路径规则已执行；链接拒绝与大小写敏感文件系统未执行 | `declaration_paths_tests.jai` 名称/链接/XDG 用例；新增 `acceptance_a15_entry_through_link_is_rejected`、`_case_identity_and_cross_category_names`；大小写敏感文件系统仍未验证 |
| A16 完整安装 | §7 | 未执行（安装单元校验由 0094 证据覆盖，本指南只引用其契约） | `publication_install` 15/0、`bootstrap_publication_unit_marker`，以及 0096 的仓库外安装单元路径（`version`/`build`/`run`/`test`/`update`/`offline` 全 0，缺件与无回退负例为 1） |

# 决策追溯

| 决策 | 体现章节 | 代码锚点 |
| --- | --- | --- |
| 1 公开声明接口 | §0、§1.1 | `src/module.jai:51` `Package` 结构 |
| 2 包存在性 | §1.1、§1.4 | `src/manifest.jai:286`、`287` |
| 3 省略状态 | §2 | `src/manifest.jai` 的 `manifest_eval_*_omitted` |
| 4 模块与程序 | §2、E01–E03 | `src/target.jai:51` `resolve_product_list` |
| 5 字段默认矩阵 | §2、§5 | `src/manifest.jai` 的 `PLUGINS` 默认分支；`src/workspace.jai` 的 `select_root_defaults` |
| 6 名称语法与作用域 | §3 | `src/path_safety.jai:235`、`248`、`265` |
| 7 原始输入与内部状态 | §1.1（`dir` 删除） | `src/package_model.jai` 的 `Normalized_Package` |
| 8 路径规则 | §3 | `src/target.jai:38`；`src/path_safety.jai:180` |
| 9 显式来源类型 | §1.2、§4.1 | `src/manifest.jai` 的 `manifest_source` |
| 10 模块选择接口 | §1.2、§4.2 | `src/dependency_resolution.jai:378` `resolution_select_export` |
| 11 身份与可见性 | §4.2、§4.3 | `src/dependency_resolution.jai:318` `resolution_add_consumer_module` |
| 12 Git 提供方边界 | §3、§4.1 | `resolution_sibling_boundary`、`resolution_path_within` |
| 13 Git 修订与工程上下文 | §4.4 | `src/dependency_resolution.jai:392` `resolution_resolve_git` |
| 14 上下文隔离与离线 | §4.4 | `src/resolution_state.jai` |
| 15 缓存与状态原子性 | §4.4、§7 | `resolution_publish_state`、`src/publication.jai:718` |
| 16 工作区发现 | §1.4、§5 | `src/workspace.jai:147` `discover_workspace` |
| 17 命令定位与默认对象 | §5 | `src/workspace.jai:124`、`select_root_defaults` |
| 18 显式选包 | §5 | `src/workspace.jai:486` `select_workspace_packages` |
| 19 命令行为 | §6、E02/E03/E10 | `src/commands/run.jai:73`、`src/commands/build.jai` |
| 20 批量与测试包边界 | §5、§6 | `src/commands/selection.jai` `Package_Batch` |
| 21 插件接口与选择 | §1.3、E09 | `src/plugin_scan.jai:337`、`534` |
| 22 插件默认、配置和阶段 | §1.3、§2、E08/E09 | `src/manifest.jai` 的 `PLUGIN`/`PLUGIN_OPTION` 分支 |
| 23 插件执行范围 | §1.3 | `src/plugin_host.jai:124` `prepare_plugins_once` |
| 24 派生视图接口 | §1.5 | `src/lifecycle.jai` 的 `Prestep_Stage` |
| 25 插件能力边界 | §1.5、E08/E09 | `src/plugin_scan.jai:713`（只能选已存在的模块入口） |
| 26 校验与诊断 | §8、各探针表 | `src/manifest.jai:276`、`416` |
| 27 现有模块职责 | §4–§7 | `src/commands/selection.jai`、`src/workspace.jai`、`src/dependency_resolution.jai` |
| 28 迁移与交付 | §0、§1 | 本文件；`src/manifest.jai:416` |
| 29 文档与关联 effort | 全文 | 本文件；`docs/spec.md` §2 |

# 已知限制与未执行项

1. 本指南全部运行证据来自 Windows + `jai 0.2.9`。Linux 或大小写敏感文件系统未运行，不能据此声明跨平台通过。
2. `target/evidence/` 是易失证据区（`clean` 会删除）。需要长期保留的验收记录应复制到 `docs/implementation/` 或由 0096 收进其 Resolution。
3. **标准模块入口的测试重入修订（已实施并验证）**：`test` 扫描仍排除根级 `target/`、`modules/`、`tests/data/` 等目录，但本包标准入口 `module.jai` / `src/module.jai` 的去重计入生成 driver 隐式 `#import "Testing"`，已导入入口不再重复 `#load`（§4.3）。旧“必须放入源码 `modules/` 目录”的规避办法不再作为 Testing 成员方案；其他入口或主动混用 `#load` / `#import` 不在本项扩张承诺内。本轮结果见 §7（仅 Windows），`build` / `run` 的入口规则不变。
4. 本指南只在 §7 及相关入口说明同步 Testing 标准成员迁移，不展开旧 effort 的外部包、转译/发现或 jaix 迁出；兄弟仓库、静态/动态库产物、包注册中心、版本范围求解仍不覆盖。
5. 以下行为在本指南的示例中没有执行：同名成员与 Git 来源冲突（A02）、不同来源同名包并存（A03）、完整多跳环链路（A04）、插件坏 options 与派生视图冲突（A06/A08）、无记录离线/短修订拒绝（A09）、失败保旧状态与成员隔离（A10）、缓存清理与状态损坏与移根新上下文与 XDG 回退（A11）、Git 内部相对引用与检出内工作区（A12）、未选中成员阻止操作与下级包测试扫描剪除（A13）、链接拒绝（A15）、安装单元缺失/混装（A16）。
   这些行为已由 0096 用真实 CLI 用例补齐并执行，逐条映射与用例名见
   [`docs/implementation/package-declaration-acceptance.md`](../implementation/package-declaration-acceptance.md) §2、§5；
   **大小写敏感文件系统契约与 Linux 仍为未验证**，不得把 Windows 结果当跨平台结论。
6. ~~仓库内 `packages/juice-plugin-lint/package.jai`、`packages/juice-plugin-jaix/package.jai` 的注释仍写着旧词（“LIB with no targets”、声明 version 必须重复）。~~ **已解决（`035a163`）**：两包已移到 `plugins/`，注释中的 “LIB with no targets” 与旧成员说法一并清除；根 `package.jai` 中“插件 id = 成员包名”这句错误陈述也删除了（id 始终来自声明，多个测试依赖二者可以不同）。
7. 首次构建时可能出现 `Unable to open directory '<包根>/target'` 一类目录探测噪声（目标目录尚未创建）。它不影响退出码与产物，属于既有输出，不是声明语义。

# 证据索引

| 文件 | 内容 | 退出码 |
| --- | --- | --- |
| `target/evidence/migration-examples-index.txt` | 全部示例调用的 CWD、参数与退出码 | — |
| `target/evidence/reproduce-examples.sh` | 重建 E01–E10 并逐个执行的脚本 | — |
| `target/evidence/e01-build.log`、`e01-run.log` | E01 构建、运行 | 0 / 0 |
| `target/evidence/e02-build.log`、`e02-run.log` | E02 零程序构建、运行失败 | 0 / 1 |
| `target/evidence/e03-build.log`、`e03-run-default.log`、`e03-run-adder.log`、`e03-run-unknown.log` | E03 构建与三种程序选择 | 0 / 0 / 0 / 1 |
| `target/evidence/e04-build-default.log`、`e04-build-workspace.log`、`e04-probe-run-workspace.log` | E04 纯工作区 | 0 / 0 / 1 |
| `target/evidence/e05-build-default.log`、`e05-build-workspace.log`、`e05-build-inside-member.log` | E05 根工作区 | 0 / 0 / 0 |
| `target/evidence/e05-probe-root-default.log`、`e05-probe-by-name.log`、`e05-probe-by-path.log`、`e05-probe-unknown-name.log` | E05 默认与显式选包 | 0 / 0 / 0 / 1 |
| `target/evidence/e06-run.log`、`e06-probe-cycle.log` | E06 本地依赖、WORKSPACE 路径错误 | 0 / 1 |
| `target/evidence/e07-run-first.log`、`e07-run-reuse.log`、`e07-update.log`、`e07-run-after-update.log`、`e07-run-offline.log` | E07 Git 复用、更新、离线 | 全部 0 |
| `target/evidence/e08-test.log` | E08 lint 警告与测试通过 | 0 |
| `target/evidence/e09-build.log`、`e09-run.log` | E09 插件 + 普通 API | 0 / 0 |
| `target/evidence/e09-negative-plugin-also-dependency.log`、`e09-negative-duplicate-plugin.log` | E09 角色冲突与重复启用 | 1 / 1 |
| `target/evidence/e10-build.log`、`e10-run.log`、`e10-test.log` | E10 零产物 | 0 / 1 / 0 |
| `target/evidence/probe-legacy-type.log`、`-targets.log`、`-build-script.log`、`-dependency.log`、`-plugin.log` | 旧字段拒绝 | 全部 1 |
| `target/evidence/probe-legacy-name-search.log`、`probe-legacy-plugin-guess.log` | 删除的按名搜索与插件名猜测 | 1 / 1 |
| `target/evidence/probe-neg-default-run.log`、`probe-neg-ambiguous-module.log`、`probe-neg-unnamed-products.log` | 产品解析失败 | 全部 1 |
| `target/evidence/probe-auto-product-name-hyphen.log`、`probe-pos-hyphen-name.log` | 自动名称合法性 | 1 / 0 |
| `target/evidence/probe-empty-workspace.log`、`probe-workspace-empty-object.log` | 空工作区的零选包 | 1 / 1 |
| `target/evidence/probe-empty-declaration.log`、`probe-default-run-empty.log` | 空声明、`default_run` 显式空 | 1 / 1 |
| `target/evidence/probe-plugins-omitted.log`、`probe-plugins-empty.log` | 插件省略 = 内置、空 = 全禁用 | 0 / 1 |
| `target/evidence/probe-empty-dependency-modules.log` | 显式空依赖模块清单 | 1 |
| `target/evidence/own-module-acceptance.log` | 本包公开名导入（根包、本包模块互引、工作区成员、`test` 的测试程序）、传递依赖不泄漏、依赖导入名不得覆盖本包模块 | 导入 0；泄漏与覆盖 1 |
