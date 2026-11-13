# otter cargo 式 monorepo 布局研究——juice 对 cargo 目录划分的支持面

> 研究问题：otter 仓库按 cargo 式 workspace 布局组织（根包 + crates/ 成员目录 + path 依赖 + 共享 target），且阶段 0 用 juice 就能构建/测试这一布局——juice 能否实现 cargo 对应的目录结构？
> **命名定稿（2026-10-19 用户决定）：工具名 = juice（重构版以 juice 名义交付）；otter = 开发代号/目录名（本文与姊妹研究文档沿用代号语境，交付面一律用 juice）。**
> 日期：2026-10-19 | 环境：Jai beta 0.2.009，Windows 11 + Git Bash；juice 产物 `C:/Users/maojiaxing/Workspace/projects/jai/juice/target/juice.exe`（仓库产物，PATH 安装版可能滞后）
> 证据标注：【实验】= 本机端到端运行验证 | 【源码】= 一手逐行阅读 | 【官方文档】= cargo book 原文 | 【推断】= 基于事实的推理
> 实验目录 `C:/Users/maojiaxing/AppData/Local/Temp/otter-monorepo-research/`（根 BIN 包 mono + crates/liba LIB + crates/appb BIN DEP liba + 非成员 libb 探针 + 每包 test 块），未修改仓库产品代码。

## 结论摘要

**回答：能。** cargo 式目录结构（根包 + crates/ 成员 + path 依赖）在 juice 阶段 0 即可构建与测试——实验端到端证实（根 build/test 全绿、成员独立 build/test 全绿、成员引用成员 shim 正确）。差异与缺口不阻碍 bootstrap：

| cargo 概念 | juice 机制 | 判定 |
| --- | --- | --- |
| members（glob） | 字面路径列表，无 glob | **部分**：`crates/*` 需逐条列举 |
| path 依赖自动入成员 | 无此机制（成员只来自字面列表） | **无** |
| exclude | 解析+协议打印，零消费方 | **无消费方** |
| 根包 + 成员并存 | 支持（jaix `examples/embed-consumer` 先例） | **支持** |
| 成员间 path 依赖 | 成员按名链接 shim（`find_workspace_member`→`link_workspace_member_dependency`） | **支持**【实验】 |
| 成员引用根包 | embed-consumer 先例（`source = "../../"`） | **支持**【源码】 |
| source 相对路径语义 | 相对声明包目录（成员自身运行时）；**根 prep 期成员的非成员相对 DEP 按根 CWD 静默解析错** | **部分（缺口，无害）**【实验】 |
| 共享 target/ | **无**——每包独立 target/ | **不支持**（cargo 语义不同，非阻碍） |
| 根命令作用于全部成员 | 根 build/test 只作用于根包；成员各自为 root 跑 | **不支持聚合**【实验】 |
| 传递闭包/lockfile | 无（ADR 0001）；成员自备全闭包 DEP | **无** |
| 版本统一/元数据继承 | 无 workspace.package 等价物 | **无** |
| member 必须 root 内 | `path_is_within` 强制（cargo 默认同、可越界指针） | **支持（更严）** |
| 混合 lib/bin：BIN 包 src/module.jai + src/main.jai 并存（§6） | 支持——BIN 包可被依赖（无类型限制），shim 探测命 module.jai 入口 | **支持**【实验 E1】 |
| LIB 根 + CLI 成员包（§6） | 支持——根 LIB 零 target，CLI 独立成员包 DEP 引根 | **支持**【实验 E2】 |
| 命名碰撞：库面 `#import "juice"` vs 模块面 `Juice`（§7） | **硬编译错误**——"Non-matching Windows file case"（编译器近匹配显式拒绝，非静默误绑定）；平铺（E1）与目录模块（E5）两种发布形态同判死 | **判死**；官方形态 = 异名 DEP（`juice_core`）【实验 E1/E2/E5】 |
| 双面并存：`#import "Juice"`（模块面）+ `#import "juice_core"`（库面）（§7） | 同一源码并存编译运行通过 | **支持**【实验 E3】 |

---

## 1. cargo workspace 规范事实（cargo book 原文）

来源：https://doc.rust-lang.org/cargo/reference/workspaces.html （2026-10-19 抓取）【官方文档】：

- **共享物**："All packages share a common Cargo.lock file which resides in the workspace root. All packages share a common output directory, which defaults to a directory named target in the workspace root."（Workspaces 章首段）
- **members 的 glob 语义**："All path dependencies residing in the workspace directory automatically become members. Additional members can be listed with the members key, which should be an array of strings containing directories with Cargo.toml files. The members list also supports globs to match multiple paths, using typical filename glob patterns like `*` and `?`."；官方推荐原文："Keep all member packages in a flat directory (commonly crates/) and use a glob pattern for the members field, e.g. `members = ["crates/*"]`. This minimizes churn in maintaining the members list."
- **exclude**："The exclude key can be used to prevent paths from being included in a workspace... using a glob pattern and you want to remove a directory."
- **根包**："If the [workspace] section is added to a Cargo.toml that already defines a [package], the package is the root package of the workspace. The workspace root is the directory where the workspace's Cargo.toml is located."；虚拟清单（无 [package]）= virtual workspace。
- **包选择**："Package-related Cargo commands... can use the -p / --package or --workspace command-line flags... If neither... is specified, Cargo will use the package in the current working directory. However, if the current directory is a workspace root, the default-members will be used."；"Note: when a root package is present, you can only operate on it using --package and --workspace flags. When unspecified, the root package will be used."
- **成员位置**："When inside a subdirectory within the workspace, Cargo will automatically search the parent directories for a Cargo.toml file with a [workspace] definition... The package.workspace manifest key can be used in member crates to point at a workspace's root to override this automatic search. The manual setting can be useful if the member is not inside a subdirectory of the workspace root."——默认成员在根内，可显式越界。
- **元数据继承**：`workspace.package` 表 + 成员 `{key}.workspace = true`（version/authors/license 等）；`[patch]`/`[replace]`/`[profile.*]` 仅根清单有效。

（cargo 的 path 依赖 = dependencies 表中 `path = "../liba"` 的相对路径条目，属标准 cargo reference 常识面；本文引用已捕获的 workspaces 章原文，path 依赖细节以该章"path dependencies residing in the workspace directory automatically become members"为准。）

## 2. juice 现状能力映射（逐行核验）

| cargo 概念 | juice 机制（file:line） | 判定 |
| --- | --- | --- |
| members 字面 vs glob | `Package.workspace.members: [] string`（`juice/modules/Juice.jai:44-45`）；discovery 逐条校验：`workspace_relative_path_is_valid` 拒绝空/绝对/`..` 逃逸（`workspace.jai:8-12`），逐条 `normalize_existing_path` + `inspect_path_entry` + `path_is_within`（`workspace.jai:63-99`）——**纯字面路径，无 glob 展开** | 部分 |
| path 依赖自动入成员 | 无此机制——成员集 = `workspace.members` 字面列表（实验：非成员 libb 在 crates/ 内但未列入即非成员） | 无 |
| exclude | 协议打印（`manifest.jai:69-71`）与存储（`:221`）之外**零消费方**（refactor 研究 §1.1 已钉，grep 佐证） | 无消费方 |
| 根包 + 成员并存 | jaix 先例【源码】：`jaix/package.jai` = LIB 根包 + `workspace.members = ["examples/embed-consumer"]`；成员自己的 package.jai 独立成文（`jaix/examples/embed-consumer/package.jai`） | 支持 |
| 成员间引用（member DEP member） | `fetch_workspace_dependencies` 逐成员包迭代 DEP，`find_workspace_member` 按名命中成员 → `link_workspace_member_dependency` → 根 `target/packages/<名>.jai` shim（`dependency.jai:393-424,101-106`）；【实验】根 prep 期 appb 的 liba DEP 生成了根 `target/packages/liba.jai` | 支持 |
| 成员引用根包 | embed-consumer 先例【源码】：`DEP jaix source = "../../"`（成员目录相对上两级 = 根包目录）；根 prep 期按名命中成员表（成员表含根包，`workspace.jai:59-61,104`）→ 同样走成员链接 | 支持 |
| source 相对路径语义 | 成员**自身为 root 运行时**：CWD = 成员目录，`ensure_import_shim` 的 `normalize_existing_path(source)` 按 CWD 解析（`dependency.jai:123-142`）——embed-consumer 注释原文 "DEP source 按 CWD=member 目录解析"；【实验】appb 独立运行时 `../liba`、`../libb` 均正确解析 | 支持（成员独立运行） |
| ——根 prep 期的同一语义 | 【实验】缺口：根 prep 期 `fetch_workspace_dependencies` 以根 CWD 处理成员的非成员相对 DEP——appb 的 `../libb` 被解析到 `<root>/../libb`（不存在）→ `ensure_import_shim` 无布局回退 `return true`（`dependency.jai:140-141`）→ **静默跳过**：根 `target/packages/` 无 libb.jai、无报错、根 test 照常通过。成员间引用不受影响（按名匹配短路，不经路径解析） | 缺口（静默，无害） |
| 共享 target/ | **无**：`target_dir = <package_root>/target`（`target.jai:196`）——每包独立 target/；【实验】根产物 `root/target/hello.exe`、appb 产物 `crates/appb/target/appb.exe`，各自独立 `packages/`、`transpile/`、`testing-module/`；根 clean 清根 + 各成员 target/（`clean.jai:47-53`） | 不支持 cargo 语义 |
| 根命令作用于成员 | 根 build 只解析根包的 artifact_plans（`prepare_workspace` 的 `resolve(state.discovery.root_package)`，`workspace.jai:157`）；根 test 发现面剪除成员子树（`test.jai:544-559`，"workspace member subtrees are pruned... members run their tests as their own root"）；【实验】根 `Found 1 tests` 只跑根包测试，appb 独立跑 `Found 1 tests` 通过 | 不支持聚合 |
| 传递闭包/lockfile | 无（ADR 0001）；成员自备全闭包 DEP（embed-consumer 自备 packrat DEP，`jaix/examples/embed-consumer/package.jai` 注释） | 无 |
| 版本统一/继承 | 无 workspace.package 等价物；每包写 version | 无 |
| member 必须 root 内 | `path_is_within(root_abs, member_abs)` 强制（`workspace.jai:80-83`）；cargo 默认同、`package.workspace` 指针可越界 | 支持（更严） |

## 3. 端到端实验（`otter-monorepo-research/`）

工程：根 `package.jai`（BIN "mono"，target hello，`workspace.members = ["crates/liba", "crates/appb"]`）；`crates/liba`（LIB，module.jai 含 `greet()` + test 块）；`crates/appb`（BIN，DEP liba `source="../liba"` + 探针 libb `source="../libb"`，src/main.jai `#import "liba"` + test 块）；`crates/libb`（LIB，非成员）。全部用 juice 仓库产物运行。

**根 build**（输出节选原文）【实验】：

```
[juice] Package 'mono' (v0.1.0) discovered.
[juice] Preparing workspace dependencies...
[juice Build] Compiling Target 'hello' (src/main.jai) -> target/...
[juice] Build completed successfully!
```

产物落点：`root/target/hello.exe`（含 lib/obj/pdb）；`root/target/packages/liba.jai`（成员链接 shim）；**成员目录无 target/ 产生**（根 build 不构建成员）。

**根 test**【实验】：

```
[juice] Package 'mono' (v0.1.0) discovered.
[juice] Preparing workspace dependencies...
Unable to open directory '.../otter-monorepo-research/modules': 3 ...
[juice Test] Found 1 tests; compiling test program...
[test] root hello test
root test block runs: true
1 passed, 0 failed
```

（"Unable to open directory .../modules" = Testing 模块查找先探包内 modules/ 的回退噪音，无碍。）**成员测试未被根 test 聚合**。根 test 后 shim 被依赖剥离前端改写为 STRIP 视图（liba 的 module.jai 含 test 块）：

```
// Generated by juice: import shim for package 'liba'.
#load "C:/Users/maojiaxing/AppData/Local/Temp/otter-monorepo-research/target/transpile/deps/liba/ab7fbe351ae21b14/module.jai";
```

**成员 appb 独立 test**（CWD = crates/appb）【实验】：

```
[juice] Package 'appb' (v0.1.0) discovered.
[juice] Preparing workspace dependencies...
[juice Test] Found 1 tests; compiling test program...
[test] appb test block
appb test block runs: greetings from liba
1 passed, 0 failed
```

appb 自有 `target/` 树（packages/liba.jai + libb.jai 两个 shim、transpile/、testing-module/）——`../liba`、`../libb` 均按成员 CWD 正确解析。

**成员 appb 独立 build + 运行产物**【实验】：

```
[juice Build] Compiling Target 'appb' (src/main.jai) -> target/...
[juice] Build completed successfully!
$ ./target/appb.exe
appb says: greetings from liba
```

**缺口探针**：appb 加入非成员 libb DEP（`../libb`）后根 test 照常通过（`1 passed, 0 failed`），根 `target/packages/` 仍只有 `liba.jai`——根 prep 期该相对 DEP 按根 CWD 解析失败被**静默跳过**（无报错、无 shim），成员独立运行时不受影响。

## 4. otter 仓库 cargo 式布局提案（2026-10-19 用户定稿：packages/ 命名 + src/module.jai）

基于判定结果与 §6 混合形态实验，用户最终定稿的布局：

```
juice/（开发代号 otter）                 # 工作区根 + 根包（BIN: juice 工具，name="juice"，target juice → juice.exe）
├── package.jai                         # workspace.members = [
│                                       #   "packages/juice-plugin-test",
│                                       #   "packages/juice-plugin-transpile",
│                                       #   "packages/juice-plugin-lint" ]  ← 逐条列举（juice 无 glob）
├── src/
│   ├── module.jai                      # 库面入口（E1 证实：他包 DEP 经 shim 探测命中 src/module.jai；
│   │                                   #   插件 API = Juice_Plugin 等——唯一 API 定义源，与原始 juice 的两模块布局一致）
│   └── main.jai                        # CLI 面（target main_file）
├── tests/                              # 根包测试
├── packages/
│   ├── juice-plugin-test/              # LIB 成员（test 插件逻辑；package.jai + module.jai + 内嵌测试）
│   ├── juice-plugin-transpile/         # LIB 成员
│   └── juice-plugin-lint/              # LIB 成员
├── build.jai                           # 阶段 2 自举 metaprogram（含 modules 发布步骤）
└── docs/

（生成件：target/modules/Juice/module.jai + target/modules/Testing.jai ← build 期从 src/module.jai **自动转换**发布；
 **Juice 用大写目录模块形态**（发行版 modules/Basic/module.jai 同款惯例），Testing 平铺（原始 juice 形状）；
 modules_dir 推导 = <exe>/modules；**Otter.jai 概念取消**——插件 API 并入库面 src/module.jai，插件经 DEP shim 引用（§7 异名 DEP 官方形态））
```

- **`src/module.jai` 落位**：探测序 `module.jai` → `src/module.jai` → `<名>.jai`（`dependency.jai:127-137`），§6 E1 实测 `src/module.jai` 命中成立——插件成员 `DEP juice_core source = "../../"` 的 shim 即指向它（**异名 DEP 是官方形态**，§7）；无需根级薄 module.jai。
- **`modules/` 与 `src/module.jai` 的关系（2026-10-19 用户定稿）**：`src/module.jai` 是**唯一定义源**（库面：Package 兼容结构体、Testing API、Juice_Plugin API），发布产物落 **`target/modules/`**——**Juice 以大写目录模块形态 `target/modules/Juice/module.jai` 自动转换生成**（发行版 `modules/Basic/module.jai` 同款惯例；转换 = 从 src 定义抽取最小 Package 兼容面写入目录模块入口），Testing 平铺 `Testing.jai`（原始 juice 形状）。生成件与 target/ 同类（不进版本库、clean 自动覆盖、扫描排除集天然豁免）。**Otter.jai 取消**：插件 API（Juice_Plugin，随工具名更名）并入库面，插件代码经 DEP shim `#import "juice_core"` 引用（§7）——与原始 juice 的"两模块布局"（Juice + Testing）一致。阶段 0-1 由 juice exe 旁 modules 提供（`juice_modules_dir` = 运行 exe 目录推导），otter 自身不发布；阶段 2-3 otter 自举后 `#import "Juice"`/`"Testing"` 由 otter 自己的推导解析。
- **`modules_dir()` 推导偏离（有意）**：otter 推导 = **`<exe>/modules`**（即 `<exe dir>/target/modules`，仓库内开发时），不照抄 juice 的 `<exe>/../modules`（juice 的 `..` 跳级只因 juice 的 modules/ 是仓库根手维护源码；otter 的 modules 是生成件，与 exe 同目录相邻更简、clean 免费、LNK1104 副本纪律不变——副本留 target/ 内即命中）。先例 = jaix-cli 部署布局 `<exe_dir>/modules`（哨兵文件判定优先，`jaix-cli/src/main.jai:79-96`）。发布步骤必须在 build 流程内（求值器子进程 `-import_dir` 指向它）。这一单源设计消除"Juice 模块双份版本偏移"风险（otter-refactor-research.md 风险 4）。
- **发布产物的 API 兼容约束**：`Testing.jai` 必须与 `juice/modules/Testing.jai` API 兼容（assert/记录/run/finish 汇总语义 + path_mapping）——bootstrap 期测试代码是同一套（juice test 跑、阶段 3 otter test 也跑）；`Juice/module.jai` 的 Package 结构体 = juice 兼容面（字段形状同 `juice/modules/Juice.jai:97-118`，otter 扩展字段在自举切换后加入）。
- **共享 target/ 语义**：接受 juice 现实——每包独立 target/（无跨包缓存共享）；内容寻址视图缓存也是每包一棵树。clean 已覆盖根+成员。
- **阶段 0 的构建/测试流程**：`juice build` 于根 = 根包构建；成员测试各自为 root 跑（juice 不聚合）——CI = 根 + 逐成员脚本循环（gs_test 式脚本层聚合先例，`test-collection-mechanisms.md` 的跨文件聚合结论）。
- **与插件发现路径的衔接**：插件包扫描（auto-discovery 的 (c)）的扫描面覆盖 `packages/`——扫描器是构建工具侧 walk，不依赖 workspace 成员语义（成员子树剪除只作用于 test 发现面与 jaix 扫描面；otter 的插件发现面独立配置）。生成注册文件落根 `target/`（bootstrap 闭包外的生成件纪律不变）。
- **与 note-based-testing 的衔接**：阶段 3 otter test 于根包 = 根包测试（成员不被聚合——与 juice 现状一致）；成员测试继续独立跑，note 发现机制在每包内一致。

## 5. juice 缺口清单（对 cargo 式布局）与 bootstrap 阻碍评估

| # | 缺口 | 影响 | 阻碍 bootstrap？ |
| --- | --- | --- | --- |
| 1 | members 无 glob | `crates/*` 需逐条列举 | 否（冗长而已） |
| 2 | exclude 无消费方 | 收不进成员集的目录靠列表精确控制（无 glob 时本就不需要 exclude 场景） | 否 |
| 3 | 根 prep 期成员非成员相对 DEP 按根 CWD 静默解析错 | 纪律：成员相对 DEP 要么指向成员（按名链接、语义正确），要么根包也声明同名 DEP（根的声明在根 CWD 下生成正确 shim） | 否 |
| 4 | 无传递闭包/lockfile | 每包显式全闭包 DEP（jaix-cli 先例） | 否 |
| 5 | 根命令不聚合成员（build/test） | 阶段 0 CI = 逐包脚本循环；otter 未来可做 --workspace 聚合 | 否 |
| 6 | 每包独立 target/ | 与 cargo 共享 target 不同；无跨包缓存共享 | 否 |
| 7 | 无版本继承（workspace.package） | 每包写 version | 否 |

**预期结论成立：无任何缺口阻碍 otter 的 cargo 式布局在阶段 0 用 juice 构建与测试**——布局差异（逐条列举、每包 target/、成员测试各自跑）是既定的 juice 语义，otter 自举后可按需实现 glob/聚合/继承（记录为 otter 的未来特性，非 bootstrap 前置）。

---

## 6. 混合 lib/bin 形态（2026-10-19 追加验证）

用户两问：(1) src/ 下同时有 module.jai 与 main.jai（lib 入口 + bin 入口并存，被依赖走 module.jai、自身构建走 main.jai target）是否支持？(2) root 定义为 LIB 但 CLI 在 src/cli/main.jai 是否可行？

### 6.1 源码面核验

- **LIBRARY_TARGET_CONFLICT = 硬错误**【源码】：`validate_library_package`（`target.jai:129-139`）——LIB 包 `targets.count > 0` → 解析失败，报 "Library package '%' cannot declare executable targets."；LIB 还须提供 `module.jai` 或 `src/module.jai`（`MODULE_ENTRY_NOT_FOUND`，`:134-137`）。Build 对 LIB 只验证导入入口、零 artifact plan（`resolve_effective_targets` 的 LIB 分支，`:150-154`）。
- **UNSPECIFIED 推导序**【源码】（`target.jai:118-125`）：`targets` 声明 → BIN；`src/main.jai` 存在 → BIN；import entry 存在 → LIB；否则 BIN。**UNSPECIFIED 永不因 module.jai 而成 LIB（当 targets 或 src/main.jai 存在时）**——混合形态必须显式 `type = .BIN`（或 UNSPECIFIED 走推导得到 BIN）。
- **无"依赖必须 LIB"检查**【源码】：`dependency.jai` 全文无 `package_type` 判断（grep 仅 `Source_Type` 枚举 :10-13）；BIN 作依赖不受任何限制。import 入口探测 `module.jai` → `src/module.jai` → `<名>.jai`（`dependency.jai:127-137`）与 LIB 校验用的 `library_import_entry`（`target.jai:102-113`）同序同约定——**入口约定与包类型无关**。
- **ADR 0001 决定 1 原文**："LIB 包不声明 executable target、不产生 artifact plan，Build 对它只验证导入入口（package root 的 module.jai，import 名 = package 名）；BIN 包行为不变。LIB 声明显式 target 属于无效声明——先严格，未来放宽（允许库附带 demo executable）不破坏已有 manifest。"——约束只在 LIB 侧，**从未排除 BIN 作导入源**。

### 6.2 实验（`otter-hybrid-research/`）

**E1：混合 BIN 包 X（src/module.jai 导出 `lib_hello` + src/main.jai + target x）作 Y 的依赖**【实验】：

- `juice build` X → `x/target/x.exe` 产出，exit 0。
- `juice test` Y（DEP `{name="x", source="../x"}`，`#import "x"` + test 块）：

```
[juice] Package 'y' (v0.1.0) discovered.
[juice] Preparing workspace dependencies...
[juice Test] Found 1 tests; compiling test program...
[test] y uses x lib
y test: hello from x lib
1 passed, 0 failed
```

- Y 的 shim（x 的 module.jai 含 test 块，被依赖剥离前端改写为 STRIP 视图）：

```
// Generated by juice: import shim for package 'x'.
#load "C:/Users/maojiaxing/AppData/Local/Temp/otter-hybrid-research/y/target/transpile/deps/x/540afe42d352925e/module.jai";
```

- `juice build` Y + 运行产物 → `y main: hello from x lib`。**问题 1 答案：支持。**

**E2：LIB 根 + CLI 成员包**【实验】：

- `juice build` 根（LIB "ottercore"，module.jai 导出 `core_hello`）→ `[juice] Library package 'ottercore'; nothing to build.` + "Build completed successfully!"，exit 0。
- `juice build` cli 成员（以成员为 root，DEP `source="../../"`）→ `crates/cli/target/ottercli.exe` 产出；shim：

```
// Generated by juice: import shim for package 'ottercore'.
#load "C:/Users/maojiaxing/AppData/Local/Temp/otter-hybrid-research/e2root//module.jai";
```

- 运行产物 → `ottercli: hello from ottercore lib`。**问题 2 答案：可行——但 CLI 必须是独立包（成员或兄弟包，jaix-cli 先例）；LIB 根本身带不了任何 CLI target。**

**E3：LIB + targets 硬错误对照**【实验】：

```
[juice] Package 'badlib' (v0.1.0) discovered.
[juice ERROR] Library package 'badlib' cannot declare executable targets.
[juice ERROR] Command 'build' failed while executing 'build'.
exit=1
```

（`src/cli/main.jai` 形态作为 LIB 根包的 target 属同一硬错误面——LIB 禁 targets 是全部禁，与 main_file 路径无关。）

### 6.3 otter 根包选型裁决

**选 (a)：BIN 根 + src/module.jai（或根级 module.jai）+ src/main.jai target。** 理由：

1. E1 证实 BIN 根同时是导入源与构建目标——`cargo-style-monorepo.md` §4 提案（BIN 根）**维持不变，补证成立**；模块入口约定（`module.jai` → `src/module.jai`）与包类型无关（§6.1）。
2. 插件成员 DEP 根包时 shim 探测命中根包的 module.jai（探测序 `dependency.jai:127-137`；E2 已验证根级 module.jai 被命中，BIN 根同序同行为）——成员引用根 API 的路径 = E1 的 Y→X 同款。
3. (b) LIB 根 + CLI 成员可行（E2）但多一层：otter 工具自身成为成员包，阶段 0 的 `juice build` 于 otter 根只产出 "nothing to build"，需进成员目录构建——与 cargo "root package 优先"（workspaces 章 "When unspecified, the root package will be used"）心智相悖，且根包测试面（note-based testing 的 test 命令、scan_walk 的根扫描面）从根包移到成员包。BIN 根让 `juice build`/`juice test` 于 otter 根直接作用于工具本体。
4. E3 反证：LIB 根内任何 CLI target（含 `src/cli/main.jai`）都是硬错误，无放宽空间。

根包 module.jai 的落位建议：根级 `module.jai`（探测第一候选，E2 命中先例）——薄重导出文件（`#load "src/..."`），供插件成员经异名 DEP shim 引用（§7：`#import "juice_core"` 官方形态；**不可** `#import "juice"` 或 `#import "otter"`——前者与模块面 `Juice.jai` 大小写碰撞、后者无对应 shim）【实验+推断】。

---

## 7. 命名碰撞与插件引根形态（2026-10-19 命名定稿验证）

**问题**：根包 name = "juice"（与工具同名）；运行期模块 = "Juice"（大写，package.jai `#import "Juice"` 的 load-bearing 模块面）。插件成员 DEP 根包后 shim 文件名 = DEP name（`target/packages/juice.jai`），插件代码 `#import "juice"`——Windows 大小写不敏感 FS 上，import dirs 顺序 = modules 目录（含 `Juice.jai`）在前、shim 目录在后（`compiler_import_directories`，`dependency.jai:70-81`）——`#import "juice"` 会不会误命中模块面的 `Juice.jai`？

### 7.1 校验面【源码】

**DEP.name 无任何校验**：`dependency.jai` 全文对 `dep.name` 只做两件事——成员名匹配（`:409`）与 shim 文件名（`:432`）；manifest 严格解析器只解析不校验（`manifest.jai:197`）。**DEP name 与依赖包的 package name 无需一致**——异名 DEP（`{name="juice_core", source="../../"}`）机制上完全自由。

### 7.2 实验（`otter-juice-name-research/`）

**E1：`#import "juice"` 引根库（同名 DEP）→ 硬编译错误**【实验】：

```
In Workspace 3 ("Juice Build"):
C:/Users/maojiaxing/AppData/Local/Temp/otter-juice-name-research/crates/p/src/main.jai:2,1: Error: Non-matching Windows file case: This string almost matches a filename, but some characters are the wrong case. Though Windows treats filenames as case-insensitive, on most other operating systems they are case-sensitive, so this would not work portably. Thus we disallow it.

    #import "Basic";
    #import "juice";
    ^^^^^^^

C:/Users/maojiaxing/AppData/Local/Temp/otter-juice-name-research/crates/p/src/main.jai:2,1: Almost-matching filename: 'Juice.jai'.
[juice ERROR] Compilation failed for target 'p'.
```

结论：**Jai 编译器有显式的"近匹配大小写"拒绝**（不是静默误绑定）——modules 目录的 `Juice.jai` 让 `#import "juice"` 直接编译失败；shim 生成了（指向根 `src/module.jai`）但 import 根本走不到它。`#import "Juice"`（大写）则是精确命中模块面（Package 兼容结构），对插件 API 是错误的面。

**E2：异名 DEP `juice_core` + `#import "juice_core"` → 全绿**【实验】：

```
[juice Build] Compiling Target 'p' (src/main.jai) -> target/...
[juice] Build completed successfully!   (exit 0)
$ ./target/p.exe
p uses both faces: marker=42 package_name_field_count_ok=true
```

shim：

```
// Generated by juice: import shim for package 'juice_core'.
#load "C:/Users/maojiaxing/AppData/Local/Temp/otter-juice-name-research//src/module.jai";
```

**E3：双面并存**【实验】——同一成员源码里 `#import "Juice"`（模块面：Package 结构体）+ `#import "juice_core"`（库面：根库 API）并存编译运行通过（E2 的 main.jai 即为双面形态）——两种面互不冲突。

（E4 无需：E1 已表明解析行为 = 编译器的近匹配显式拒绝，非 FS 静默命中。）

### 7.3 官方形态裁决

**插件代码引根库 = 异名 DEP：`DEP juice_core source = "../../"` + `#import "juice_core"`**（E2 已验证）。规则：

1. **库面 import 名不得与模块面 "Juice" 大小写近匹配**——`juice` 直接判死（E1）；任意与 "Juice" 名字不同的名称（如 `juice_core`、`juice_api`）都安全（E2 机制面自由）。
2. 模块面（`Juice`）与库面（异名）**双面并存**是合法且已验证的形态（E3）——package.jai 求值面走模块面，插件 API 走库面。
3. 对 §4 布局的落地：插件成员 package.jai 写 `DEP .{name = "juice_core", version = ..., source = "../../"}`；成员源码 `#import "juice_core"` 使用 `Juice_Plugin` 等 API（API 定义在根 `src/module.jai`）。`Otter.jai` 概念随命名定稿取消（§4 树注释）。

### 7.4 目录模块形态下的碰撞行为（2026-10-19 发布格式定稿后补验）

**发布格式（用户定稿）**：运行期模块用大写目录模块形态——build 期从 `src/module.jai` 自动转换生成 `target/modules/Juice/module.jai`（发行版目录模块惯例；Testing 仍平铺 `Testing.jai`）。入口文件名事实【源码】：发行版目录模块的入口 = **`module.jai`**（`modules/Basic/module.jai` 存在且为 `#load` 聚合入口——ls 佐证）——用户选定的转换目标文件名与发行版惯例一致。

**E5：import 目录只有目录模块 `Juice/module.jai`（无 Juice.jai 文件）**【实验】：

- `#import "Juice"`（大写）→ **命中目录模块**，编译运行通过（`upper-case import hit dir module: 7`）。
- `#import "juice"`（小写）→ **同一硬错误**：

```
Error: Non-matching Windows file case: This string almost matches a filename, but some characters are the wrong case. Though Windows treats filenames as case-insensitive, on most other operating systems they are case-sensitive, so this would not work portably. Thus we disallow it.
Almost-matching filename: 'Juice'.
```

近匹配候选名变为**目录名 'Juice'**（无 .jai 后缀）——编译器的大小写近匹配拒绝覆盖目录候选。**无静默命中**（Windows 大小写不敏感目录解析不会让 `#import "juice"` 悄悄命中 `Juice/module.jai`）。

**E6（可选探针）：目录模块与平铺文件并存**【实验】——同一 import 目录点同时存在 `Juice.jai` 与 `Juice/`：

```
Error: This module exists in both single-file and directory form, at the same point in the modules_path, so we don't know which one to use.
Info: A single-file version of this module exists at: .../e6/dir/Juice.jai
```

**无优先级、显式歧义拒绝**（与 juice 的 shim 目录纪律注释互证：`dependency.jai:116-122` "a directory next to its shim collides as 'both single-file and directory form'"）——发布步骤必须保证 `target/modules/` 里 Juice 只以目录形态存在（生成流程天然保证：只写 `Juice/module.jai`）。

**对照与结论**：E1（平铺形态）与 E5（目录形态）的碰撞行为**一致**——`#import "juice"` 两种发布形态下都判死（编译错误而非静默误绑定）。**§7.3 官方形态结论不变**：异名 DEP（`juice_core`）仍必须且充分（E2/E3 的验证不受发布格式影响——shim 是平铺文件 `juice_core.jai`，与 `Juice/` 目录无近匹配）；`#import "Juice"` 面语义保持唯一 = 目录模块面（Package 兼容结构）。发布格式从平铺改目录形态不改变 §7.3 的任何纪律。

---

## 引用清单

cargo book（2026-10-19 抓取）：

- https://doc.rust-lang.org/cargo/reference/workspaces.html ——共享 lock/target 首段；members/exclude 的 glob 语义与 crates/* 推荐；根包/虚拟清单；-p/--workspace/root package 选择规则；package.workspace 越界指针；workspace.package 继承与 [patch]/[replace]/[profile] 根限定

本仓库（2026-10-19 工作树，逐行核验）：

- `juice/modules/Juice.jai:44-45`（workspace.members 字面列表字段）
- `juice/src/workspace.jai`：8-12（路径校验拒绝空/绝对/..）；29-106（discover：逐条 member 展开与校验，80-83 path_is_within、88-99 manifest 加载）；59-61,104（成员表含根包）；108-177（相位机与 resolve(root_package)、157 根包 plans）；194-207（ensure 入口）
- `juice/src/dependency.jai`：10-34（Source_Type/clean_local_path）；58-60（packages_dir）；96-99（resolve_and_fetch_dependencies）；101-106（link_workspace_member_dependency）；123-142（ensure_import_shim 探测序与无布局回退 140-141）；393-424（fetch_workspace_dependencies：成员按名匹配短路 409-415）
- `juice/src/target.jai:196`（target_dir = 包根/target）；`:102-113`（library_import_entry 探测序）；`:118-125`（UNSPECIFIED 推导序）；`:129-139`（validate_library_package：LIBRARY_TARGET_CONFLICT 硬错误与 MODULE_ENTRY_NOT_FOUND）；`:150-154`（LIB 分支零 target）；`juice/src/commands/clean.jai:47-53`（根+成员 target/ 清理）
- `juice/docs/adr/0001-lib-packages-are-import-sources.md`（决定 1 "LIB 声明显式 target 属于无效声明——先严格，未来放宽"；决定 3 member 须声明为依赖；Consequences 无递归闭包）
- `juice/src/commands/test.jai:544-559`（根测试发现面剪除成员子树）
- `juice/src/manifest.jai:69-71,221`（EXCLUDE 协议打印与存储，零消费方——refactor 研究 §1.1 复核）
- `jaix/package.jai`（LIB 根包 + members 先例）、`jaix/examples/embed-consumer/package.jai`（成员引用根包 `source="../../"` + 全闭包自备 + "DEP source 按 CWD=member 目录解析"注释）
- `otter/docs/research/otter-refactor-research.md` §4.2（旧布局提案，本文 §4 修订）、§4.1（入口探测序）
- `otter/docs/research/plugin-auto-discovery.md`（插件扫描发现面）
- `juice/docs/research/test-collection-mechanisms.md`（gs_test 脚本层聚合先例）

实验（本机，`C:/Users/maojiaxing/AppData/Local/Temp/otter-monorepo-research/`）：

- 工程：根 package.jai/src/main.jai；crates/liba/{package.jai,module.jai}；crates/appb/{package.jai,src/main.jai}；crates/libb/{package.jai,module.jai}（非成员探针）
- 实录：§3 根 build/test、成员 appb test/build、libb 静默缺口探针的全部输出原文

实验（本机，`C:/Users/maojiaxing/AppData/Local/Temp/otter-hybrid-research/`，§6）：

- E1：x（混合 BIN：src/module.jai + src/main.jai + target）/ y（BIN，DEP x，`#import "x"` + test 块）——build/test 全绿、shim 指向 STRIP 视图、产物运行原文
- E2：e2root（LIB "ottercore"，module.jai，workspace member crates/cli）/ crates/cli（BIN "ottercli"，DEP `source="../../"`）——根 build "nothing to build"、成员 build + 运行原文
- E3：badlib（LIB + targets）——硬错误原文（`Library package 'badlib' cannot declare executable targets.`）

实验（本机，`C:/Users/maojiaxing/AppData/Local/Temp/otter-juice-name-research/`，§7）：

- E1：根包 name="juice"（BIN，src/module.jai 含独有类型 Juice_Lib_Only）/ 成员 crates/p（DEP `{name="juice", source="../../"}`，`#import "juice"`）——"Non-matching Windows file case" 硬错误原文（近匹配 'Juice.jai'）
- E2/E3：成员改 DEP `{name="juice_core", source="../../"}` + 双面 `#import "Juice"` + `#import "juice_core"`——build 全绿、产物运行 `p uses both faces: marker=42`、shim 指向根 src/module.jai
- E5（§7.4）：import 目录只有 `Juice/module.jai` 目录模块——`#import "Juice"` 命中（运行 `upper-case import hit dir module: 7`）；`#import "juice"` 同款硬错误（近匹配候选 = 目录名 'Juice'）
- E6（§7.4）：`Juice.jai` 与 `Juice/` 同点并存——"exists in both single-file and directory form" 歧义硬错误原文
- E7（§7.4）：发行版目录模块入口文件名 = `module.jai`（`modules/Basic/module.jai` ls 佐证）
