# otter 重构研究——juice 兼容面、插件机制泛化、monorepo 布局与自举路径

> 研究问题：新构建工具 otter 作为 juice 的重构/重启，须 (1) 原样接受既有 juice `package.jai` 声明；(2) `build`/`clean` 内置、`test`/`transpile`/`lint` 经插件接入；(3) monorepo 布局支持跨包模块引用；(4) 实现在当前为空的 `otter/` 目录；(5) 先用 juice 定义/构建 otter，最小可执行后自举。
> 全部结论来自一手来源：本仓库 juice/jaix/jaix-cli 源码、ADR、spec/issue 与研究笔记（2026-10-19 工作树；`juice/.claude/worktrees/` 与 `juice/.git/` 下的副本一律忽略）。每条论断标注 `(file:line)` 或 `(docs/… §…)` 引用。Jai 发行版相关事实引自 juice 的两份研究笔记（其本身为一手实验记录，beta 0.2.009）。
> 范围外事实一律写明"未找到"，不猜测。

---

## 1. juice package 声明兼容面

### 1.1 Package 结构体：字段全集

`Package` 定义在 juice 的运行时模块 `juice/modules/Juice.jai:97-118`。这是兼容面的结构层（structural surface）：

| 字段 | 类型 | 默认 | 引用 |
|---|---|---|---|
| `name` | `string` | 无（必填） | `juice/modules/Juice.jai:98`；非空可移植文件名由 `validate_package_identity` 强制（`juice/src/target.jai:50-52`） |
| `version` | `string` | 无（必填非空） | `Juice.jai:99`；`juice/src/target.jai:53-55` |
| `type` | `Package_Type {LIB; BIN; UNSPECIFIED}` | `.UNSPECIFIED` | `Juice.jai:7-11,100` |
| `description` | `string` | `""` | `Juice.jai:101`（装饰性，无消费方） |
| `targets` | `[] Target {name, main_file}` | 空 | `Juice.jai:14-17,103` |
| `dependencies` | `[] Dependency {name, version="", source="", package=""}` | 空 | `Juice.jai:35-40,105` |
| `workspace` | `Workspace_Config {members: [] string, exclude: [] string}` | 空 | `Juice.jai:42-45,106` |
| `build_script` | `string` | `""` | `Juice.jai:107`；**死字段**——协议打印并解析，但 src/ 无任何消费方（唯一引用 = `juice/src/manifest.jai:48,163-165`，grep 证实） |
| `jaix` | `Jaix_Prestep {config, exe=""}` | 空（config 空 = 前置禁用） | `Juice.jai:52-55,110` |
| `transpile` | `Transpile_Pipeline_Declaration {plugins: [] Transpile_Plugin_Declaration {id, version, options: [] Transpile_Plugin_Option {key, value}}}` | 空插件表 = 缺省管线 | `Juice.jai:57-87,114` |
| `dir` | `string` | 由 loader 填入，**不在 package.jai 声明** | `Juice.jai:116-117` |

`workspace.exclude` 与 `build_script` 同属"解析但无消费方"（`exclude` 仅协议打印 + 存储：`juice/src/manifest.jai:69-71,221`）。otter 接受面必须容忍这两个字段，但 juice 今天不赋予其语义。

### 1.2 package.jai 的执行形态（关键机制事实）

`package.jai` 不是数据文件，是**可执行的 Jai 源文件**：`#import "Juice";` 后声明 `PACKAGE :: Package.{...}` 常量（例：`juice/package.jai:1-13`）。juice 以生成的子进程求值器解释它（`juice/src/manifest.jai:23-95`）：

1. 生成求值器源码：`#import "Basic"/"File"/"Juice"/"Compiler"` + `#load <manifest 绝对路径>` + `#run { set_build_options_dc(.{do_output=false}); main(); }`（`manifest.jai:27-40`）；
2. 求值器 `main` 把字段打印成 `KEY=VALUE` 行记录协议写入数据文件（`manifest.jai:42-92`）；写盘失败以退出码 2 报出，父进程重试至多两次（`manifest.jai:77-91,338-346`）；
3. 子进程命令行：`jai <eval_src> -import_dir <exe_dir>/../modules -quiet`（`manifest.jai:340`）——**`#import "Juice"` 经运行中 juice 可执行文件旁的 modules 目录解析**（`juice_modules_dir`，`juice/src/path_safety.jai:40-45`）；
4. 父进程严格解析协议文本（`parse_manifest_data_strict`，`manifest.jai:97-226`）：未知记录键、单值记录重复、形状错（如 `TARGET` 非 `name|main_file`、`DEP` 非四字段、`TRANSPILE_PLUGIN` 非 `id|version`）= 错误 + 行号；
5. 解析后两道纯函数校验门：`validate_jaix_marker`（`JAIX_EXE` 无 `JAIX_CONFIG` = 声明错误，`manifest.jai:244-249`）与 `validate_transpile_pipeline`（未知 id / 重复 id / 非法选项 = 拒绝，`manifest.jai:262-277`）；
6. 每个 manifest 一个 jai 子进程求值（`juice/IMPLEMENTATION.md:72`）。

**协议记录全集**（求值器恒打印，`manifest.jai:44-75`）：`NAME`、`VERSION`、`TYPE`（枚举整数值 0/1/2）、`DESCRIPTION`、`BUILD_SCRIPT`、`JAIX_CONFIG`、`JAIX_EXE`、`TRANSPILE_PLUGIN=<id>|<version>`（可重复、声明序、零声明 = 零记录 = 缺省管线——spec 0060 决定 6，`manifest.jai:52-59`）、`TARGET=<name>|<main_file>`（可重复）、`MEMBER`（可重复）、`EXCLUDE`（可重复）、`DEP=<name>|<version>|<source>|<package>`（可重复）。

**对 otter 的直接推论**（兼容性硬约束）：既有 package.jai 文件（a）经 `#import "Juice"` 依赖**模块名 "Juice"**——这个模块名是 load-bearing 的（juice/jaix/jaix-cli/packrat 的 package.jai 第一行全是 `#import "Juice"`）；(b) 在 juice 求值器内编译，因此 `PACKAGE :: Package.{...}` 的字面量字段必须严格是 juice `Package` 结构体的字段——**otter 想给 Package 加字段（如 `lint`、`test` 配置），在 bootstrap 期不可行**：加字段的声明会因 juice 的 Package 类型无此成员而在求值器子进程编译失败。otter 扩展声明面在 bootstrap 期只能以 `PACKAGE` 之外的兄弟常量/模块常量形式存在（求值器编译整个文件，多余顶层常量不影响协议）。

### 1.3 既有声明实例（原样）

- `juice/package.jai`：BIN 包，`targets = Target.[.{name = "juice", main_file = "src/main.jai"}]`（`juice/package.jai:6-13`）——otter 自身 package.jai 的 juice 可消费形状正是此形状。
- `juice-demo/package.jai`：`TARGETS :: Target.[...]` 兄弟常量 + `PACKAGE :: Package.{name, version, description, targets}`，无 `type`（UNSPECIFIED → 声明 targets 推导 BIN；`juice-demo/package.jai:3-15`）。
- `jaix/package.jai`：LIB 包；依赖面 = `packrat`（`source = "../packrat"`）+ 两个**无 manifest 的普通 Jai 模块依赖**（`source = "./modules"` 的 `Jaix_Plugin_Test_Block`/`Jaix_Plugin_Try_Catch`——依赖 shim 机制支持无 manifest 模块，`jaix/package.jai:13-26`）；workspace member `examples/embed-consumer`。
- `jaix-cli/package.jai`：BIN 包；deps = `jaix`（`../jaix`）+ `packrat`（`../packrat`）——**juice 无依赖传递闭包**，jaix 源码内的 `#import "packrat"` 需本包自备声明才能编译（`jaix-cli/package.jai:8-29` 注释；ADR 0001 Consequences）。
- `packrat/package.jai`：LIB 包 + workspace members。
- **`testing/package.jai`：未找到**——仓库根 `testing/` 目录为空（与 `otter/` 同为当前空目录）。任务清单中的这一例不存在，兼容面不包含它。

### 1.4 结构层 vs juice 专属层

- **结构层（otter 必须原样实现）**：name/version/type/targets/dependencies/workspace 及全部派生语义——LIB 为导入源不可声明 targets（ADR 0001 决定 1；`juice/src/target.jai:129-139` 的 `LIBRARY_TARGET_CONFLICT`）、UNSPECIFIED 按约定推导（`target.jai:118-125`）、依赖消费只经导入 shim（ADR 0002 决定 1）、统一 `target/` 目录（ADR 0003 决定 1）、workspace member 必须声明为依赖才可引用（ADR 0001 决定 3）。
- **juice 专属层（otter 需决策：实现 / 兼容容忍 / 语义重解释）**：`jaix` 标记（ADR 0007 的可选子进程前置）、`transpile` 管线声明（ADR 0008 的包配置面）、`build_script`（死字段）、`description`（装饰）。
- **兼容判定**：otter 对存量声明的最低要求 = 结构层全量 + 对 juice 专属字段**求值不失败**。注意严格协议解析器拒绝未知记录（`manifest.jai:214-215`），但记录只由求值器打印——求值器不认识的字段根本不会产生记录，因此"容忍"是求值编译层的义务而非协议层。

---

## 2. juice 命令架构现状

### 2.1 注册与派发

- `Command` 结构 = `{name, description, usage, prerequisites: [] string, handler: #type (ctx: *Command_Context, arguments: [] string) -> bool, validate_arguments: #type = command_accepts_no_arguments}`（`juice/src/commands/command.jai:1-21`）。
- `Command_Context` = `{root_dir, cache_dir, workspace: Workspace_State}`（`command.jai:4-12`）——仅两个进程级路径（包根 = 启动时 CWD；juice 缓存 = XDG cache home 下的 `juice/`，`juice/src/main.jai:38-44`）+ workspace 状态机。
- 注册表 = 静态数组 `COMMAND_REGISTRY :: Command.[BUILD_COMMAND, RUN_COMMAND, CLEAN_COMMAND, TEST_COMMAND]`（`juice/src/commands/registry.jai:3-8`）。新增命令 = 新文件进 `main.jai` 的 `#load` 列表 + 注册表数组加一行（`juice/IMPLEMENTATION.md:28`），无自动注册。
- Dispatcher（`juice/src/dispatcher.jai`）：`validate_registry`（无效声明/重名/未知前置，`:35-59`）→ `plan_command`（DFS 全图规划：环检测、菱形去重、前置命令恒收空参数，`:64-92`）→ 按序执行，前置失败 = `PREREQUISITE_FAILED`、目标失败 = `HANDLER_FAILED`（`:94-121`）。
- 唯一前置关系：`run` 依赖 `build`（`registry.jai:31` 测试钉住；CONTEXT.md Command 词条）。workspace 准备不是 command、不参与前置（`juice/src/workspace.jai:108-118,194-207` 的幂等状态机 `EMPTY/DISCOVERED/PREPARED`）。

### 2.2 各命令触及的面（otter 插件化的 seam 图）

| 命令 | 入口 | 触达的机制面 |
|---|---|---|
| `build` | `build_command`（`juice/src/commands/build.jai:17-31`）→ `ensure_workspace_prepared` → `build_prepared_workspace` | 批量重校验（`:40-60`）→ 依赖剥离前端 `prepare_dependency_strip_views`（`:225`）→ jaix 前置（`:233-235`）→ 逐 plan 编译入口选择 `build_plan_entry`（jaix 镜像视图 / 闭包探测 + 剥离视图 / 原文，`:166-197`）→ `compile_artifact_plan`（生成 metaprogram + `run_command("jai", metaprogram_path)`，`:62-112`） |
| `run` | `run_command_handler`（`juice/src/commands/run.jai:20-26`） | `select_artifact_plan`（大小写敏感选择，`:30-45`）→ `launch` seam（默认 `run_artifact_plan` 直接启动产物，`:47-79`） |
| `clean` | `clean_command`（`juice/src/commands/clean.jai:14-23`） | 仅 discovery（无 manifest 时清 CWD 的 `target/`）→ `clean_discovered_workspace`：root + 全部已验证 member 的 `target/` 整目录，**先全量校验后删除**（`:35-70`） |
| `test` | `test_command`（`juice/src/commands/test.jai:28-39`） | `force_dependencies = true` 的 workspace 准备（LIB 零 target 也可测）→ 全包发现 `collect_test_files`（排除集见 4.3）→ `test_prepared_workspace`（`:105-321`）：jaix 前置（marker 时）→ 逐文件 EXPAND 转译 + 全局编号 → pattern 过滤 → 内容寻址视图落盘 → Testing 模块编译视图特例 → 生成 `driver.jai` + `first.jai`（metaprogram）→ 依赖剥离 → 编译期执行测试 |
| （bootstrap） | `juice/build.jai` metaprogram | 见 §5 |

### 2.3 seam 纪律（插件接口的现成先例）

所有编排函数以 **`#type` 形参 + 生产默认值** 注入可替换操作，集成测试用录制假实现跨同一接口：

- `build_prepared_workspace` 的 `transpile` / `compile` / `prestep` 三形参（`juice/src/commands/build.jai:208-213`）；
- `test_prepared_workspace` 的 `transpile` / `compile` / `dep_transpile` / `prestep` 四形参（`juice/src/commands/test.jai:105-113`）；
- `clean_discovered_workspace` 的 `validate_path` / `delete_path`（`clean.jai:35-40`）；
- `run_prepared_workspace` 的 `launch`（`run.jai:62-66`）；
- workspace 三函数的 `discover` / `resolve` / `prepare_dependencies`（`workspace.jai:120-125,144-151`）。

研究 B 结论 3 的表述精确成立："插件化 = 把「单步可替换」泛化为「有序多步管线可注册」"（`juice/docs/research/transpile-plugin-architecture.md` 结论 3）。otter 的 build/test/transpile/lint 插件接口应建在这个 seam 形状上，而不是新发明。

---

## 3. 现有插件机制与可泛化点

### 3.1 juice Transpile_Plugin 契约（spec 0060 / 票 0061 / ADR 0008）

接口定义（`juice/src/transpile_plugin.jai:76-83`）：

```jai
Transpile_Plugin :: struct {
    name:       string;
    version:    string;
    modes:      Transpile_Plugin_Modes;   // {strip, expand} 模式适用性声明
    has_anchor: #type (source: string, path: string) -> bool;   // 可空
    load_edges: #type (source: string, path: string) -> [..] string;  // 可空
    transpile:  #type (scan: *Transpile_Scan, ctx: *Transpile_Context, state: *void) -> bool;
}
```

机制要素（全部有代码落点）：

1. **身份进缓存键**：有序 name+version 序列 = 管线描述分量，进视图缓存键；`JUICE_VERSION` 语义泛化为"管线输出契约版本"（spec 0060 决定 5；`juice/src/transpile_plugin.jai:56-58` 注释；0062）。
2. **派发循环**：runner 逐 token 按声明序向插件派发，模式适用性门控；声明者拥有其区域的游标/深度/语句位置簿记与三汇（Edit/清单/诊断）；未声明 token 走 runner 缺省追踪（`transpile_plugin.jai:481-506`）。
3. **区域交互契约在 runner 层显式化**：claim 覆盖恰好其消费的 token——EXPAND 下 test 插件进入块体不消费，体内 `#load` 仍被 load 插件剥离；STRIP 下整体占位、体内 token 永不再派发（`transpile_plugin.jai:447-457`）。
4. **探测钩子成对**：`pipeline_has_anchors`（可空跳过）喂闭包视图判定、`pipeline_load_edges` 喂闭包 DFS（`transpile_plugin.jai:335-353`）；test-free 闭包零转译短路不变（ADR 0004 决定 1）。
5. **跨文件状态通道**：`Transpile_Context.plugin_state` 槽与管线序对齐，调用方持有存储、跨 `transpile_source` 调用续走（`transpile_plugin.jai:71-75,485-487`）——test 编号续号的同款通道。
6. **runner 强制硬约束**：`enforce_line_fidelity`——每条编辑须「1 行换 1 行」且「以 token 为界」，违反编辑丢弃 + 诊断拒绝（`transpile_plugin.jai:425-438`；ADR 0008 决定 2）。坏插件在转译期响亮失败，不静默漂移行号。
7. **空注册表 = 缺省管线**：`resolve_pipeline` 单一落点（`transpile_plugin.jai:374-377`），视图与其键恒反映同一管线。
8. **包作者声明面**：`TRANSPILE_PLUGIN=<id>|<version>` 协议记录 + `validate_transpile_pipeline` 校验门 + `resolve_transpile_pipeline` 组装（`juice/src/transpile_config.jai:21-31`；`manifest.jai:52-59,203-212`）。选项不跨进程（jaix"选项值不跨进程"立场，`manifest.jai:53-56`）。

**v1 偏差（对 otter 泛化有直接影响）**：声明 version 装饰性——不校验、不进键，按 id 解析到内置注册表实例（0063 偏差 3）；两内置插件选项集为空（类型化槽就位、无合法行，0063 偏差 4）；依赖视图与 Testing 模块视图恒走缺省管线（0063 偏差 1/2）。

### 3.2 jaix Jaix_Plugin 作为参照系

`jaix/src/plugin.jai:148-157`：

```jai
Jaix_Plugin :: struct {
    id:            string;
    version:       string;
    grammar:       [..] Plugin_Grammar_Entry;  // 挂点→文法片段（DECL/STMT/EXPR 三挂点）
    keywords:      [..] string;                // 关键字 claim（注册期冲突对照全集）
    node_kinds:    [..] Node_Kind;             // 插件节点 kind（范围+保留+独占校验）
    printers:      [..] Plugin_Printer;        // kind → 打印函数
    passes:        [..] Pass;                  // transform pass（配置序 = pass 序）
    config_schema: [..] Config_Option;         // {name, default: *void, validate}
}
```

可泛化点（jaix 先例 → otter）：

- **get_plugin 官方契约 + using 继承**：插件模块导出 `get_plugin()` 返回**派生结构体指针**（基类 Jaix_Plugin 经 `using` 继承 + 类型化 `options` 成员），框架侧一律经 `as_plugin` 显式 cast 上转消费——派生指针保证配置侧 `p := get_plugin(); p.options = .{...}` 的编译期类型检查（`jaix/src/plugin.jai:10-35,185-187`）。这是"选项类型化"的 Jai 执行级形状。
- **注册期合并校验**（`merge_plugins`，`plugin.jai:336-471`）：同 id 重复/异版本冲突、关键字 claim 冲突（对照全版本关键字全集 `jaix_keyword`）、node_kinds 范围 + 内置保留（`plugin_reserved_owner`，`:225-238`）+ claim 独占、grammar/printers 与 node_kinds 一致性——合并失败 = 全 ERROR 诊断 + `ok=false`，调用方拒绝继续。
- **配置执行 = 子进程编译模式**：配置文件定义 `get_config :: () -> Jaix_Config`；`generate_config_driver` 生成 driver（`#load` 配置 + `#run` 调 `get_config()` 打印行记录协议 `JAIX_PROTOCOL/PLUGIN=id|version/SOURCEMAP/ROOT`，`jaix/src/config.jai:378-393`）；`execute_config` 以 `run_command("jai", "-quiet", driver, "-import_dir", ...)` 编译执行（`config.jai:513-548`），内容寻址进程内缓存（`config.jai:551-552,658-663`）。
- **juice manifest 求值器与 jaix config driver 是同构机制**（生成 driver → 子进程 jai → 行记录协议 → 严格解析），otter 的 plugin 配置执行可复用同形状。

juice 与 jaix 并存不替代：juice 管线 = 锚点级文本编辑（行号保真、bootstrap 自足、零依赖），jaix = 整树 AST 变换（ADR 0008 决定 6；CONTEXT.md Transpile 词条）。otter 若同时承载两者需保持这一分工。

### 3.3 Jai 语言对插件 ABI 的约束（全部有代码/实验证据）

1. **无闭包**：0063 偏差 5 钉住——本版 jai（beta 0.2.009）"Closures are not supported."（spike），per-package 管线绑定无法以函数值捕获完成；执行级解法 = seam `#type` 增**默认空第三形参**（`pipeline: [] Transpile_Plugin = .[]`）作显式数据参数，调用方可省略（`juice/issues/0063-package-manifest-pipeline-declaration.md` 偏差 5；`juice/src/commands/build.jai:169,210`、`juice/src/commands/test.jai:64,109`）。**otter 插件上下文必须走显式 ctx 数据传递，不能依赖闭包捕获。**
2. **过程指针结构体 = 接口载体**：`Command_Handler :: #type (...)`（`command.jai:1`）、`Transpile_Plugin` 的回调成员、全部 seam 形参——这是已三路径验证的形态。`#type` 参数个数须与函数严格一致（0063 偏差 5）。
3. **`#import` 按名 / `#load` 按路径**：按名 `#import` 经 import 目录解析（manifest 求值器的 `-import_dir`，`manifest.jai:340`）；按名加载插件模块的官方先例 = 编译器 `Metaprogram_Plugins.jai` 的代码生成 `Plugin_%1 :: #import "%2"`（研究 B §4.1 引用发行版 `Metaprogram_Plugins.jai:41`）——otter 按 id 解析插件模块可照抄此形态；`#load` 是文本包含（`build.jai:25-29` 的 #load 集）。
4. **metaprogram `#run` + `run_command` 子进程是现实可用的插件宿主通道**：bootstrap 在 metaprogram 内 spawn 子进程 jai（`juice/build.jai:168`）；jaix `execute_config` 同款（`config.jai:537`）；juice build 编译同样 spawn（`commands/build.jai:101`）。退出码可判、stderr 可透传（`build.jai:145-150` 注释；`jaix_front.jai:190-194`）。
5. **子进程 CWD 事实**：jai 编译器在 `#run` 期把 CWD 切到 driver/metaprogram 文件所在目录——因此所有 spawn 参数用**绝对路径**（`jaix_front.jai:33-39`；`metaprogram.jai:14-20` 的 058 偏差 ④；`jaix-cli/src/main.jai:22-29` 的 driver_dir = 用户 CWD 推导）。
6. **Windows run_command 事实**：bash 不在 Windows PATH——E2E 脚本经 `cmd /c` 执行（`commands/build.jai:869-874` 的 `"cmd", "/c", script`）；`delete_directory_full` 用 `cmd /c rmdir /S /Q` 且参数必须反斜杠（`dependency.jai:506-517`）。
7. **动态库插件：可行但摩擦大、已推迟**：发行版无 `Dynamic_Library` 模块；`LoadLibraryA/GetProcAddress` 底层可用，但 Jai 类型不能干净跨 DLL 边界——两次调用约定不匹配崩溃反例（研究笔记 `juice/docs/research/dynamic-libraries.md` 结论 5/6 + 失败迭代记录）；DLL 构建必须走 metaprogram（jai CLI 无 output_type flag，同笔记 §"jai 命令行 flag"）。ADR 0008 Considered Option (b) 与 spec 0060 决定 1 明确推迟第三方宿主选择。
8. **第三方插件的四条宿主路**（研究 B §3.3）：(a) 编译进工具（仅仓库内置插件可行——bootstrap `#load` 闭包成员必须 test-free + 随仓库分发，研究 B 结论 8b）；(b) 运行时动态库（第 7 点）；(c) 独立进程 filter（无 ABI 问题、任意语言，代价 = 每文件子进程开销与版本偏差）；(d) 编译期 `-plug` 原生 metaprogram 插件（官方 shipped 机制、实验 exp3 端到端可用，但承载不了语法扩展——解析错误早于任何钩子，研究 B 结论 5/6）。
9. **语法扩展只能文本层前置**：`test "x" { }` 是解析错误（研究 B exp1），任何编译期钩子不可达——otter 的 transpile 类插件若要扩展语法，必须是编译前的文本/源码层管线；类型感知检查（lint 类）可走段二（`-plug` AST 插件）。

### 3.4 泛化的 otter 插件接口（基于上述证据的推断形态）

证据支撑的最小泛化：

```
Otter_Plugin :: struct {
    id:          string;     // 身份进管线描述/缓存键（Transpile_Plugin.name/version 先例）
    version:     string;
    commands:    Plugin_Command_Applicability;  // 对 build/test/transpile/lint 各自的适用性声明
                                                // （Transpile_Plugin_Modes 的模式适用性声明泛化）
    hooks:       ...;        // 成对探测/执行钩子（has_anchor/load_edges/transpile 的成对先例）
    options:     ...;        // jaix Config_Option 的 {default, validate} 类型化 schema
}
```

落地依据：

- **命令层**：`Command` 结构（name/description/usage/prerequisites/handler/validate_arguments，`command.jai:14-21`）本身已是插件形状——build/clean 内置 = 注册表静态数组；test/transpile/lint 插件 = 各自贡献一个 `Command` 值 + 生命周期钩子。注册表合并后复用 `validate_registry` 的完整性校验（`dispatcher.jai:35-59`）。SUMMARY.md 已把"为插件系统添加运行时命令注册"列为后续方向（`juice/SUMMARY.md:106`）——但 **静态注册是已验证底座**（spec 0060 Considered Option (a)：静态注册表保留为机制底座，配置面叠加其上）。
- **执行层**：插件消费 `Prepared_Workspace`（discovery + artifact plans + package_type，`juice/modules/Juice.jai:131-137`），操作经 seam 形参注入——test 的 `test_prepared_workspace` 四形参（`test.jai:105-113`）就是"test 作为一个可替换编排"的现成接口面；transpile 类插件在 runner 内以 Transpile_Plugin 形状注册；lint 无任何先例（全 juice grep "lint" 零命中），其钩子形状是开放设计空间——若 lint = 源文本检查，可作 transpile 管线的"只读诊断插件"（has_anchor + 只产诊断的 transpile 钩子，不产 Edit）；若 lint = 类型感知检查，须走 `-plug` 段二（研究 B §4）。
- **无闭包约束下**：插件调用上下文全部显式数据传递（pipeline 参数先例，0063 偏差 5）；跨插件状态走 ctx 槽（Transpile_Context.plugin_state 先例）。
- **硬约束由宿主强制**：transpile 类插件继承「1 行换 1 行 + 以 token 为界」runner 门（ADR 0008 决定 2）；命令类插件继承 dispatcher 的注册表校验 + 参数预检。

---

## 4. 模块系统与 monorepo 布局

### 4.1 模块如何跨包解析（今日机制全图）

1. **运行时模块目录**：`juice_modules_dir()` = `<运行 exe 目录>/../modules`（`juice/src/path_safety.jai:40-45`），一处推导三处消费（build/test 编译 import 目录、Testing 模块源查找、manifest 求值器 `-import_dir`）。`juice/modules/` 下仅两文件：`Juice.jai`（Package 结构体，package.jai 作者 `#import "Juice"`）与 `Testing.jai`（断言模块，测试代码 `#import "Testing"`；含 path_mapping 视图→原文路径改写表，`juice/modules/Testing.jai:26-56`；`run`/`finish` 汇总退出码，`:95-115`）。
2. **依赖 shim 目录**：`packages_dir(root)` = `<root>/target/packages`（`juice/src/dependency.jai:58-60`）；编译 import 目录 = modules 目录 + shim 目录（`compiler_import_directories`，`dependency.jai:70-81`，build/test 共用）。
3. **import shim**：每个依赖一个生成文件 `<name>.jai`，内容 = 注释 + 单行 `#load "<被依赖方绝对路径>/<入口>"`（`dependency_shim_content`，`dependency.jai:112-114`）。入口探测序：`module.jai` → `src/module.jai` → `<name>.jai` 单文件（`ensure_import_shim`，`dependency.jai:123-142`）。无 manifest 的普通 Jai 模块同样可作依赖（ADR 0002 决定 2）——jaix 的内置插件模块即此形态（`jaix/package.jai:20-21`）。
4. **本地相对路径 source**：`source = "../jaix"` 按 **CWD = 声明包目录**解析（`jaix-cli/package.jai:8-10` 注释）——跨包引用的核心机制。
5. **workspace member**：必须是 root 包**内部**子目录（`path_is_within` 检查，`juice/src/workspace.jai:80-83`）；member 要被引用必须声明为依赖，preparation 为其注册 shim（`link_workspace_member_dependency`，`dependency.jai:101-106`；ADR 0001 决定 3）。
6. **依赖剥离前端**：含 test block 的依赖闭包整闭包 STRIP 视图落 `target/transpile/deps/<名>/...`，shim `#load` 改写到入口视图（`prepare_dependency_strip_views`，`dependency.jai:244-286`；票 0049）——插件包带内嵌测试也能被消费。
7. **无传递闭包**：消费者自声明完整依赖闭包（ADR 0001 Consequences；jaix-cli 自备 packrat 先例）。
8. **exe 相对布局推导双模式**（jaix-cli 先例，otter 插件分发可抄）：部署布局 = `<exe_dir>/modules`（哨兵文件判定）优先，dev 布局回退 = `<pkg>/../<lib>/target/packages` + `target/testing-module`（`jaix-cli/src/main.jai:79-96`）。

### 4.2 提议的 otter monorepo 布局（满足 juice 可消费声明 + 跨包模块引用）

两个约束定布局：(a) juice 的 workspace member 必须在 root 内部（`workspace.jai:80-83`），跨包引用只能靠 DEP + 相对 source（jaix/jaix-cli 型）；(b) `#import "Juice"` 的模块名是 load-bearing（§1.2）。因此：

```
jai/
├── juice/                    # 既有
├── otter/                    # BIN 包根（juice 可消费：与 juice/package.jai 同形状）
│   ├── package.jai           # PACKAGE :: Package.{ name="otter", targets=[{name="otter", main_file="src/main.jai"}] }
│   ├── build.jai             # 自举 metaprogram（最小可执行后启用，见 §5）
│   ├── modules/
│   │   ├── Juice.jai         # Package 兼容面（otter 自有的字段兼容超集/副本；
│   │   │                     #   自举后 otter 求值器以自身 modules 目录解析 "#import "Juice""
│   │   │                     #   ——模块名保持 "Juice" 以接受存量声明）
│   │   └── Otter.jai         # otter 运行时 API（Otter_Plugin 等，插件作者 #import "Otter"）
│   ├── src/
│   │   ├── main.jai          # CLI 壳（dispatcher 先例：args[1] = 命令）
│   │   ├── dispatcher.jai / workspace.jai / target.jai / dependency.jai / manifest.jai
│   │   ├── commands/         # 内置：build、clean
│   │   └── plugins/          # 内置插件注册（test/transpile/lint 的 Command 值 + 钩子）
│   └── tests/                # otter 自身测试（juice test 可跑：Testing 模块经 juice exe 旁 modules 解析）
├── otter-plugin-test/        # test 插件包（LIB；DEP source="../otter" 或 "../otter-core"）
├── otter-plugin-transpile/   # transpile 插件包（LIB）
├── otter-plugin-lint/        # lint 插件包（LIB）
```

要点：

- **bootstrap 期**：`otter/package.jai` 就是 juice/package.jai 的翻版；`juice build` 在 otter/ 内产出 `otter/target/otter.exe`，`juice test` 发现并跑 otter 的测试（Test discovery 排除集对 otter/ 的目录形状完全适用——root 级 `target/`、`modules/`、`tests/data/` 排除，`test.jai:574-583`）。
- **插件包形态**：LIB 包 + `module.jai` 或 `src/module.jai` 导入入口（`target.jai:102-113`）；otter 的插件加载 = 把插件包当依赖准备（shim 机制复用）或以 `-import_dir` 指向其 `target/packages`（jaix-cli dev 布局先例）。插件包可带内嵌测试——依赖剥离前端负责其编译面（§4.1 第 6 点）。
- **`modules/Juice.jai` 双份风险**：juice 与 otter 各持一份 `Juice` 模块（juice 求值器用 juice 的、otter 自举后求值器用 otter 的）。两份的 Package 字段必须兼容（otter 的可扩展字段只能在自举切换后加入，且需保持存量字段形状——§6 风险 4）。
- **替代形态**（juice workspace 型）：把插件作为 otter 的 workspace member 挂在 otter/ 内部——workspace member 需 root 内路径（`workspace.jai:80-83`），member 测试以自身为 root 运行（`test.jai:544-559`），member 引用需 DEP 声明（ADR 0001 决定 3）。两者可混合：紧耦合插件放成员、独立分发插件放兄弟包。当前仓库内 jaix/jaix-cli 是兄弟包先例，juice 自身无成员使用先例（juice/package.jai 无 workspace 字段）。

---

## 5. 自举策略

### 5.1 juice 如何自举（可照抄的机制清单）

`juice/build.jai` metaprogram（ADR 0006）：

1. **`-` 分隔符约定**：`jai build.jai - release`——`-` 后参数编译器忽略、转给用户级 metaprogram（jai -help 原文，`juice/docs/research/dynamic-libraries.md` §"jai 命令行 flag"）；build.jai 用 `get_toplevel_command_line()` 读参数、扫描 `release`/`-release` 开关（`juice/build.jai:72,85-92`）。
2. **Default_Metaprogram 回退抑制**：`set_build_options_dc(.{do_output = false})` + `compiler_create_workspace("Bootstrap Delegation")`——创建空 workspace 即"本 metaprogram 自管构建"信号，否则 jai 回退到默认编译命令行文件本身（build.jai 无 main → "No program entry point"，`build.jai:100-106`）。
3. **#load 复用进程内转译器**：`#load "src/transpile.jai"; #load "src/transpile_plugin.jai"; #load "src/transpile_cache.jai"; #load "src/transpile_front.jai"; #load "src/metaprogram.jai";`（`build.jai:25-29`）——被 load 代码编译进 metaprogram 执行环境、不进被构建程序（ADR 0006 决定 1）。#load 集必须 test-free 且随仓库分发（研究 B 结论 8b；这五个文件正是 juice 的 test-free 五模块，测试驻 tests/ 姊妹文件——0053 测试组织规则）。
4. **剥离前端**：`bootstrap_build_entry` 探测入口闭包——test-free 直编原文；含 test 闭包全有全无 STRIP 视图落 `target/transpile/bootstrap/`（bootstrap 专属 PLAIN 布局，恒写、与 Build command 的内容寻址缓存不混用），入口视图经 `add_build_file` 编译、诊断精确 file:line（`build.jai:43-66`；ADR 0006 决定 2）。
5. **Testing 模块特例**：`modules/Testing.jai` 含 test block 不可直编，STRIP 视图落 `target/testing-module/` 并把目录前置进 import path（`build.jai:121-133`）。
6. **生成 metaprogram + 子进程**：`bootstrap_compiler_metaprogram_options`（root 派生绝对 output/intermediate 路径——子进程 jai 的 `#run` 期 CWD = metaprogram 目录，相对 "target" 会落 target/target/，058 偏差 ④）→ `generate_compiler_metaprogram` → 写 `target/bootstrap-meta.jai` → `run_command("jai", meta_path)`（`build.jai:152-172`；`metaprogram.jai:124-152`）。
7. **失败语义**：`exit(1)` 退出码正确但吞掉父 metaprogram 的收集打印——失败路径靠退出码 + 子进程错误输出（`build.jai:145-150`）。

### 5.2 juice 如何消费 jaix（otter bootstrap 的反向精确模板）

Package.jaix 标记 = {config 路径 + 可选 exe}（`juice/modules/Juice.jai:52-55`），协议记录 `JAIX_CONFIG`/`JAIX_EXE`（`manifest.jai:49-50,167-175`），校验门（`manifest.jai:244-249`）。消费面：

- build/test 的 pre-step seam（`build.jai:233-235`；`test.jai:133-151`）：marker 在 → 整包扫描（test 发现同族排除集 + config 跳过 + juice test block 文件跳过，`jaix_front.jai:60-128`）→ 逐文件 spawn `jaix transpile <abs in> -o <abs out> --config <abs cfg>`（全绝对路径、stderr 透传、任一非 0 = 前置失败，`jaix_front.jai:33-39,190-233`）→ 镜像 `target/jaix/` → 编译入口选择面切到镜像视图（`build_plan_entry`，`build.jai:171-173`；test 的镜像文件 abs_path 改指，`test.jai:138-148`）——`compile_artifact_plan` 零改动（ADR 0007 决定 3）。
- exe 解析：marker.exe 非空优先（包相对/绝对），否则 PATH 查 "jaix"（`jaix_front.jai:152-181`）。

**otter bootstrap 的同一形状**：juice 消费 otter/package.jai 不需要任何标记——workspace discovery + 目标解析 + test 发现对任何 Package 通用（`workspace.jai:29-106`、`target.jai:141-189`、`test.jai:544-559`）。"juice 消费 otter" 比 "juice 消费 jaix" 简单：不是 pre-step，而是把 otter 当作普通 BIN 包 build+test。

### 5.3 具体 otter 自举路径

- **阶段 0（当前）**：`otter/` 内放 juice 同形状的 `package.jai`（BIN、target `src/main.jai`）+ 最小 `src/main.jai` + 测试。`juice build`/`juice test` 在 otter/ 内全绿——juice 的 manifest 求值器、workspace 准备、test 发现/EXPAND/报告/path_mapping 对 otter 零特判即成立（§1.2、§2.2 的机制对任意包通用）。产物 `otter/target/otter.exe`。
- **阶段 1（最小可执行）**：实现 build + clean + 插件加载（Otter_Plugin 注册/合并 + test/transpile/lint 的命令值）。开发循环仍用 juice：`juice test` 跑 otter 自身测试；`juice build` 产出 exe。**Windows LNK1104 事实**：运行中的 exe 不可被链接器覆写（`juice/IMPLEMENTATION.md:103`；0063 Resolution 的"exe 复制为 target/juice-build.exe 运行、毕后删除"规避法）——otter 自构建/自测循环沿用此规。复制件必须留在 `otter/target/` 内，`../modules` 推导才成立（`path_safety.jai:40-45`——memory 已记的三路径验证约束）。
- **阶段 2（自举切换）**：`otter/build.jai` metaprogram（ADR 0006 全形状：#load test-free 五模块、剥离前端、Testing 模块 STRIP 特例、生成 metaprogram + 子进程 jai、`- release` 开关、Default_Metaprogram 抑制）。此时 otter 用 `jai build.jai` 构建自己；`otter/package.jai` 转由 otter 自身求值器消费（`#import "Juice"` 解析到 otter/modules/）。
- **阶段 3（完全自举）**：`otter build`/`otter test` 在 otter/ 内自构建自测；juice 退场。otter 的插件化 test 跑 otter 自身测试套件——这是"test 插件"的第一个真实消费者。

---

## 6. 风险与未决问题

1. **lint 无任何先例**（全 juice grep "lint" 零命中）。lint 的钩子形状是开放设计面：源文本级检查可复用 transpile 管线形状（has_anchor + 只产诊断的钩子，`Transpile_Scan.diagnostics` 三汇之一，`transpile_plugin.jai:43-54`）；类型感知检查须走 `-plug` 段二（研究 B §4.2-4.3：语法扩展进不了原生插件、AST 往返不保注释与排版）。两者契约不同，otter 需自行立 ADR 级决策。
2. **test-as-plugin 改变收集机制的风险**：juice 的 test 收集 = 转译期枚举（EXPAND 时生成 Test_Entry 清单）+ 生成 driver 显式顺序调用（`test.jai:163-178,496-519`）。既有研究已判死编译期注册（可变全局不持久化、`#run` 逆 #load 序）、判定 metaprogram 扫描冗余（`juice/docs/research/test-collection-mechanisms.md` 结论）。test 插件若接管整个命令，其接口必须覆盖发现→转译→driver 生成→编译四步（`test_prepared_workspace` 的 seam 正是这四步的注入面）——把 test 降为"仅 transpile 管线里的一个插件"不够：收集、编号、path_mapping、Testing 模块特例（`test.jai:349-412`）都是 test 命令自有编排。
3. **Package 字段重解释清单**：`build_script`（juice 死字段——otter 可赋予语义或保持容忍）；`description`（装饰）；`jaix` 标记（juice 专属：otter 可作 pre-step 兼容实现、或声明"求值通过但不执行"——后者会改变标记包的构建语义，须明示）；`transpile` 声明（id+version+选项槽：v1 合法 id 集 = 两个内置插件，`manifest.jai:262-277` 的门对未知 id 是**拒绝**——otter 若扩展第三方插件 id，存量 juice 会响亮拒绝这些声明；otter 自身可放宽，但 bootstrap 期内 otter 声明的 id 集必须 ⊆ juice 合法集，否则 `juice build` 在 manifest 加载即失败）。
4. **`Juice` 模块双份与版本偏移**：bootstrap 期 otter 的 package.jai 由 juice 的模块编译；自举后由 otter 的模块编译。两份 `Package` 的字段形状必须兼容，且 otter 扩展字段的时机必须晚于自举切换。`TRANSPILE_PLUGIN`/`JAIX_*` 协议记录形状是跨进程契约（`manifest.jai:52-59`），otter 求值器应原样复刻协议形状以保持互操作。
5. **插件宿主选择仍未决**（spec 0060 决定 1 明确"机制先行、宿主选择留后续"；研究 B §3.3 四选项）。otter 的进程内插件（编译进 otter 或经 `#load`）受 bootstrap test-free 约束（研究 B 结论 8b）；第三方运行时插件需要动态库或独立进程宿主的全新设计面（`dynamic-libraries.md` 的调用约定崩溃反例是现成警示）。
6. **依赖/Testing 模块视图恒走缺省管线**（0063 偏差 1/2）：otter 若扩展管线声明面，需重新决策依赖包与 Testing 模块视图的管线语义（juice 今日解耦是"依赖 Package 不留存于 Prepared_Workspace"的实现事实所致，`dependency.jai:240-243` 注释）。
7. **缓存键契约**：视图键 = hash(路径+源+模式+版本+load 重写表+管线描述)（`juice/src/transpile_cache.jai` 语义，0062）；`JUICE_VERSION` 语义 = "管线输出契约版本"——otter 的缓存键必须带自己的版本分量，且与 juice 的键不共享（或有意共享以复用存量视图树，属设计选择）。
8. **Windows 现实约束**：LNK1104（自构建不能覆写运行中 exe，`IMPLEMENTATION.md:103`）、`cmd /c` 删除与脚本执行（`dependency.jai:506-517`、`commands/build.jai:869-874`）、子进程 CWD 切换（绝对路径纪律，`metaprogram.jai:14-20`）——otter 的 Windows 面全部照抄既有解法，无新研究面。
9. **monorepo 跨包引用的既有边界**：无传递闭包（ADR 0001）、workspace member 必须 root 内（`workspace.jai:80-83`）、member 被引用须声明为依赖（ADR 0001 决定 3）——otter 的插件包布局须按 §4.2 二形态之一落位；"跨包模块引用 + 单一声明面"的 lockfile 式闭包解析是 juice 未做的未来面（ADR 0001 Consequences），otter 若需要须自研。

---

## 引用清单（本报告引用的文件）

- `juice/modules/Juice.jai`（Package/Target/Dependency/Workspace_Config/Jaix_Prestep/Transpile_Plugin_Declaration 全结构体）
- `juice/modules/Testing.jai`（断言模块 + path_mapping）
- `juice/src/manifest.jai`（求值器 codegen + 协议 + 严格解析 + 校验门）
- `juice/src/path_safety.jai`（juice_modules_dir 推导）
- `juice/src/workspace.jai`（discovery / 状态机 / member 校验）
- `juice/src/target.jai`（类型推导 / 目标解析 / artifact plan）
- `juice/src/dependency.jai`（shim / packages_dir / import dirs / 依赖剥离前端 / cmd /c）
- `juice/src/commands/{command,registry,build,run,clean,test}.jai`
- `juice/src/dispatcher.jai`、`juice/src/main.jai`
- `juice/src/transpile_plugin.jai`（插件接口 + runner + 行号保真门）
- `juice/src/transpile_config.jai`（声明→注册表组装）
- `juice/src/jaix_front.jai`（jaix 前置：扫描/spawn/镜像/exe 解析）
- `juice/src/metaprogram.jai`（生成器 + bootstrap options）
- `juice/build.jai`（自举 metaprogram 全流程）
- `juice/CONTEXT.md`、`juice/IMPLEMENTATION.md`、`juice/SUMMARY.md`
- `juice/docs/adr/0001-0008`（包模型 / shim / target 目录 / 义务转译 / 行号保真 / 自举剥离 / jaix 前置 / 管线契约）
- `juice/docs/research/{transpile-plugin-architecture,dynamic-libraries,test-collection-mechanisms}.md`
- `juice/issues/0060`（spec）+ `0061`（管线核心）+ `0063`（配置面 + 六偏差）
- `juice/package.jai`、`juice-demo/package.jai`、`jaix/package.jai`、`jaix-cli/package.jai`、`packrat/package.jai`
- `jaix/src/plugin.jai`（Jaix_Plugin + get_plugin + merge_plugins）
- `jaix/src/config.jai`（Jaix_Config + 配置执行 + 协议）
- `jaix-cli/src/main.jai`（exe 相对布局推导 + driver_dir）

未找到并如实记录：`testing/package.jai`（`testing/` 目录为空）；juice 源码/文档/issue 中任何 "lint" 先例（零命中）；`build_script` 与 `workspace.exclude` 的任何消费方（仅解析与协议打印）。
