# juice 与 Zig 构建系统：架构对照与迁移评估（Zig 0.17.0）

> 版本钉子：Zig **0.17.0**（ziglang.org/download 标注为 "Latest Stable Version (0.17.0)"）。官方源码 tarball = `https://ziglang.org/download/0.17.0/zig-0.17.0.tar.xz`（2026-10-23 下载核验）；官方源码仓库已从 GitHub 迁到 Codeberg `https://codeberg.org/ziglang/zig`，tag `0.17.0` = annotated tag `afee4225358129f909e01dfaed265dca0977befe`，peeled commit `7647adab80dd088f4de3610fd245915a912eb6ad`。GitHub 镜像只到 0.15.x，**不能**用它读 0.17；本文所有 Zig `path:line` 均指 0.17.0 tarball 内的源码。实际读取的源码树：Git Bash `/tmp/zigsrc-0170`（Windows `C:\Users\maojiaxing\AppData\Local\Temp\zigsrc-0170`；tarball 以 `--strip-components=1` 解出，文件位于 `lib/...`）。发布说明：`https://ziglang.org/download/0.17.0/release-notes.html`。
>
> 版本变化：0.15 只把 `addStaticLibrary`/`addSharedLibrary` 合并为 `addLibrary`（0.15.1 `Build.zig:841`）；0.16 的 Build System 发布说明只有本地包覆盖、项目内抓取、单测超时、`--error-style`/`--multiline-errors`、临时文件 API，**没有架构重写**；重写发生在 0.17.0（PR #35428，见 §2.0）。
>
> juice 一侧 = 本仓库 `juice/` 当前实现（otter 重构版），引用均为 `path:line`。

## 1. 结论摘要

- **两阶段生命周期：采纳概念，升级为“可序列化计划 + 纯度分类”。** 0.17 已把 configure 和 make 拆成两个进程：configurer 只运行 `build()` 并把 `Configuration` 写到 stdout，maker 读取配置后重建 step 图并执行。juice 的 EMPTY → DISCOVERED → PREPARED 只是同进程的相位机；值得学的是“计划是数据、纯度可判定、纯计划可缓存”，不值得照搬的是双进程 + 二进制配置格式——0.17 自己为此付出了 ZLS 断裂、#36444 等代价。
- **数据流与 lazy path：有限采纳，采用 0.17 的索引表形态。** 0.17 的 `LazyPath.generated` 只存 `GeneratedFileIndex`，make 期才由 producer 填写真实路径；发布说明明确 `LazyPath.basename` 被删除，因为“值在 make 前不可知”。juice 应对四类“生成输入”（transpile 视图、import shim、插件记录、发布模块）引入 producer 索引表；最终 artifact 仍保持固定路径。
- **编译单元与产物解耦：采纳概念。** 0.17 的 `Configuration.Step.Compile` 是纯数据（root_module 索引 + 名称 + flags + 各 `generated_*` 索引），maker 端才执行编译；`InstallArtifact` 只消费这些索引。juice 可拆 `Compile_Unit` 与 `Artifact_Ref`，但不要复制 Zig 的 Module/import table/link 模型或 byte-packed `Storage`。
- **最大风险：** 计划序列化/配置缓存的正确性与纯度纪律；Jai 无增量编译、编译前无法枚举真实输入集，编译跳过仍无可靠基础。0.17 的 configurer/maker 分离本身也带来工具链断裂与回归，说明“解耦”不是免费的。
- **推荐路线：** 纯计划 IR + `Plan_Purity`（低风险）→ 生成输入的索引表（中风险）→ 可选的计划序列化/缓存供 `--dry-run`/IDE（中风险）→ 编译跳过（高风险，单独立项）。

## 2. Zig 0.17 构建系统架构

### 2.0 0.14 → 0.17 的关键变化（只列与本文三点相关的）

| 版本 | 变化 |
| --- | --- |
| 0.14 | configure 与 make 在同一个 build runner 进程内完成，只是逻辑两阶段；`LazyPath` 用内存指针 + `GeneratedFile`。 |
| 0.15 | `addStaticLibrary`/`addSharedLibrary` 合并为 `addLibrary`（0.15.1 `Build.zig:841`）；架构不变。 |
| 0.16 | 无构建系统重写；只有本地包覆盖、项目内抓取、单测超时、错误样式、临时文件 API（0.16.0 发布说明 Build System 节）。 |
| 0.17 | configurer/maker 双进程；`Configuration` 序列化；缓存改二进制并重做；configure cache poisoning；Build Server Protocol；`b.build_root` → `b.root`，`LazyPath.basename` 删除，`add*Arg` → `add*Arg2`。 |

### 2.1 两阶段生命周期

0.17 的 configure 和 make 是**两个可执行文件**。源码里给这层关系下的定义是：`Configuration` = "The serialized output of configure phase ingested by make phase"，`Serialize` = "Logic that transforms `Build` into `Configuration`"（`lib/std/Build.zig:24-27`）。`zig build` 本身先运行 maker（`src/main.zig:352-360` 以 `Maker.zig` 作为 jit 入口）；maker 在纯配置模式下先按 configure 参数查配置缓存（`--cache-poison=poisoned` 时跳过查询），未命中时才编译并运行 `configurer.zig`，把用户的 `build.zig` 作为模块 `@build`、把依赖声明作为 `@dependencies`（`lib/compiler/configurer.zig:20-21`、`lib/compiler/Maker.zig:1149-1180`、`1213-1232`）。

configurer 的核心工作就是跑 `build()` 并序列化（其余是 CLI 解析与选项校验）：

```zig
// lib/compiler/configurer.zig:138-164（节选）
builder.runPackageScript(root);
...
try Serialize.packageOptions(builder, &graph.wip_configuration);
try Serialize.systemIntegrationOptions(&graph, &graph.wip_configuration);
builder.serializeConfigurationExiting();
```

`runPackageScript` 调用 `build_zig.build(b)`（`lib/std/Build.zig:2143-2160`）；`serializeConfigurationExiting` 把 `graph.wip_configuration` 写到 stdout 后 `process.exit(0)`（`Build.zig:2710-2737`）。所以 configure 的产物是一个**完整的、可缓存的 `Configuration`**，而不是"在内存里改了些什么"。

maker 侧：`configure()`（`Maker.zig:1097`）先对 configure 参数做缓存查询（`Maker.zig:1213-1232`）；未命中则运行 configurer、`Configuration.loadFile`（`Maker.zig:1527`）、处理 lazy deps 与 path deps、把未污染的配置重命名进 `c/<digest>` 缓存（`Maker.zig:1569-1590`）。随后 `Maker.prepare` 按配置分配可变 step 状态与 `generated_files` 表（`Maker.zig:2375-2400`），`makeSteps`（`Maker.zig:2464`）调度，`makeStep`（`Maker.zig:2759`）执行。

CLI 侧的早期退出也属于这套设计：`--fetch` 在抓取后、创建 `@dependencies` 和运行 configurer 之前直接退出（`Maker.zig:1338-1341`）；`--help`/`--list-steps`/`--print-configuration`/`--print-configuration-path` 进入 `early_exit_mode`（`Maker.zig:596`），不做 server/watch 设置，但仍需一份配置来打印内容（可命中配置缓存）。`--print-configuration` 把配置渲染成 `.zon`（`Maker.zig:784-790`），`--print-configuration-path` 只打印缓存路径（`Maker.zig:1612-1622`）。发布说明对此的表述是 "build.zig logic can be skipped sometimes depending on what CLI flags are used"，并说明 maker 只需在安装 Zig 后构建一次（"first time setup"），且以优化模式构建——这也是 `--watch`/`--fuzz` 变得更快的原因。

纯度被做成了显式概念。`Graph.CachePoison` 的注释把"configure 逻辑有副作用"和"step 在 make 期有副作用"分开，并说明纯配置可以直接命中缓存、绕过 configurer 进程（`Build.zig:110-135`）；`poisonCache()` 把状态从 `.pure` 推到 `.poisoned`，`.disallowed` 直接 panic，`.ignored` 允许带毒缓存（`Build.zig:216-222`）。例如 configure 期调用 `b.findProgram` 会主动污染缓存（`Build.zig:1621-1626`）。

`--help` / `--list-steps` 仍然在 configure 成功之后由 maker 打印（`Maker.zig:770-780`；`ScannedConfig.printSteps/printUsage`，`Maker/ScannedConfig.zig:226-241`），因此冷缓存下 `build.zig` 编译失败时帮助也失败（[#19996](https://github.com/ziglang/zig/issues/19996)、[#15154](https://github.com/ziglang/zig/issues/15154)，均仍 open）。0.17 的补偿是 **Build Server Protocol**：`--listen=-` 时 maker 向客户端暴露"静态的、configure 之后的完整构建图"、step 开始/完成事件与生成文件列表（`Maker.zig:841-930`；0.17.0 发布说明 "Build Server Protocol" 节）。内省问题从"必须执行 build.zig"变成"执行一次 configure 后走协议"，但没有消失。

### 2.2 数据流与 `LazyPath`

0.17 的 step 是纯数据：`Configuration.Step` 只有 `name / owner / deps / max_rss / extended`，没有任何 `makeFn`（`Build/Configuration.zig:477-533`）；`extended` 是按 `Tag` 区分的序列化 payload。真正的执行状态在 maker 进程里重建（`Maker/Step.zig:1-30`、`60-90`）。

`LazyPath` 也变成了可序列化的 union（`Configuration.zig:1494-1596`）：

```zig
pub const LazyPath = union(@This().Tag) {
    source_path: SourcePath,
    relative: Relative,          // cwd / cache / zig_lib / install_* 等基准
    generated: Generated,        // { index: GeneratedFileIndex, up, sub_path }
};
pub const GeneratedFileIndex = enum(u32) { _ };
```

`generated` 分支只记录 **producer 在 generated-file 表里的索引**、上跳层数与子路径，不记录路径字符串。configure 期 `Graph.addGeneratedFile` 分配索引（`Build.zig:137-140`）；builder 侧 `Compile.getEmittedFileGeneric` 在首次调用时分配索引并返回 `LazyPath.generated`（`Build/Step/Compile.zig:680-686`）。make 期 `Maker.prepare` 按配置长度分配 `generated_files` 表（`Maker.zig:2391-2392`），producer 通过 `setGeneratedPath` 填表（`Maker.zig:3695`），consumer 通过 `generatedPath` 读取——后者对 `toPath` 的结果直接 `.?`（`Maker.zig:3691-3693`），所以漏连依赖仍然是 make 期 panic，而不是 configure 期诊断。

0.17 发布说明把这条语义讲得最直白：`LazyPath.basename` **被删除**，因为 "the value is not known until make phase"。同时 `Build.validateConfigureDependency` 禁止 configure 依赖 `generated` / `install_*` / `libc_runtimes` 路径（`Build.zig:2691-2706`），从规则上保证 configure 只能看到 configure 期可知的输入。这两条合起来就是"路径承诺"的完整定义。

configure 期的惰性查询：`findProgram` 在 configure 期立即查找并污染配置缓存（`Build.zig:1621-1626`）；`findProgramLazy` 返回一个 `LazyPath`，只有依赖它的 step 真正使用时才查找，因此不污染缓存（`Build.zig:1597-1599`）。这是 lazy path 从 make 期产物扩展到 configure 期决策的直接例子。

配置缓存的输入也可以显式声明：`dependOnFileContents` / `dependOnFileMetadata` / `dependOnDirectoryContents` / `dependOnDirectoryMetadata`（`Build.zig:2599`、`2625`、`2653`、`2681`）把 configure 逻辑依赖的文件/目录内容或元数据加进配置 manifest，避免 `poisonCache` 的一刀切。被污染的配置在 maker 正常退出时由 `removePoisonedConfiguration` 删除（`Maker.zig:4015-4021`）；源码注释的原话是 "This configuration file was good for only 1 invocation of the maker process."

缓存系统本身新增目录支持（目录项增删改名触发 miss）、metadata 模式（size/inode/mtime 变化触发 miss）、`zig cache-cat` 和 miss 原因解释；manifest 改为二进制格式（体积约小 25%，命中快 5-10%）。编译的命中仍由 Zig 编译器负责：`Maker/Step/Compile.zig:50` 调 `Step.evalZigProcess`，用返回的 cache digest 设置 `o/<digest>` 下的生成路径（`Maker/Step/Compile.zig:67-70`）。配置缓存与 step 缓存是两套 manifest：前者在 `Maker.zig:1213-1232` 哈希 configure 参数，并在 `1558-1565` 加入显式声明的 path deps；后者由各 step 实现。

### 2.3 编译单元与产物解耦

0.17 把这层解耦做成了数据格式。`Configuration.Step.Compile` 保存的是**编译描述**：`root_module: Module.Index`、`root_name`、`flags/flags2..4`、`installed_headers`、各种 LazyPath 索引，以及 `generated_bin / generated_implib / generated_pdb / generated_h / emit_directory` 等 `GeneratedFileIndex`（`Configuration.zig:706-760`）。它不包含"怎么执行编译"的代码。

- builder 侧：`Build.Step.Compile` 负责收集参数并创建 step（`Build/Step/Compile.zig:244-252`、`370`）；`addExecutable` / `addObject` / `addLibrary` / `addTest` 只是 `kind` 与 `linkage` 的组合（`Build.zig:579`、`603`、`637`、`676`）。
- maker 侧：`Maker/Step/Compile.zig:26-70` 把配置 lower 成 argv，调用编译器，按 cache digest 填写各 `generated_*` 路径。
- 安装侧：`Configuration.Step.InstallArtifact` 的第一个依赖约定为 compile step（`Configuration.zig:547-549` 的注释；maker 读 `deps.steps.slice[0]`，`Maker/Step/InstallArtifact.zig:27`），然后按 `generated_bin/implib/pdb/h` 复制（`Maker/Step/InstallArtifact.zig:11-84`）。安装者不知道编译怎么发生，只知道索引。

0.17 的 `ExecutableOptions`/`LibraryOptions` 都要求 `root_module: *Module`（`Build.zig:559-561`、`615-618`）；`Module.CreateOptions.root_source_file` 才是源文件入口（`Build/Module.zig:191-196`），`addImport` 在 `Module.zig:306`。0.17 不再提供 0.14 时代 `addExecutable(.{ .root_source_file = ... })` 的直传形态，`root_module` 是唯一入口。

0.17 的 API 变动也反映了这次重构：`addArtifactArg`/`addOutputFileArg`/`addFileArg`/`addOutputDirectoryArg` 等统一改为 `*Arg2`（`Build/Step/Run.zig:280`、`323`、`375`、`465`；发布说明逐条列出），`b.build_root` 改为 `b.root`，`LazyPath.getDisplayName` 改为 `format`。发布说明对 `LazyPath.basename` 的删除给出了明确理由：值在 make 前不可知；其余改名至少与"路径值可能延迟到 make 期"这一重构同步发生。

`Run.addPassthruArgs` 追加 `zig build run -- ...` 的透传参数；它把 step 视为有副作用并禁用缓存（`Build/Step/Run.zig:585-597`），而且这些参数在 configure 期不可见——这是 configure/make 边界在 API 上的另一个体现。

边界仍然存在：`LazyPath` 只表达路径，不表达任意构建值；非路径数据要靠 `WriteFile`/`Step.Options` 落成文件。`GeneratedFileIndex` 是纯路径索引，不携带类型；漏连 producer 是 make 期 panic。配置格式本身（string table、extra、byte-packed `Storage`）与工具链版本强耦合，`--build-runner` 覆盖能力被移除，也说明这层解耦的维护成本。

### 2.4 已知问题与批判

- **configurer/maker 分离是 breaking change。** 0.17.0 发布说明明确说它使 ZLS 无法工作；已知回归 [#36444](https://codeberg.org/ziglang/zig/issues/36444) 指出分离破坏了 `std.Build.Step.Run` 的 response file 用例；"Removed Ability to Override Build Runner" 一节的原话是 "There is no concept of a 'build runner' any more; it has been split into: configurer and maker"，替代品是仍在演进的 Build Server Protocol（[#36497](https://codeberg.org/ziglang/zig/issues/36497)）。
- **首次使用与迁移成本。** maker 在安装 Zig 后构建一次（"first time setup"，优化模式）；`build.zig` 改动会使 configure 缓存失效，configurer 需要重新编译/运行。`--watch`/`--fuzz` 正是 maker 以优化模式构建的动机之一；watch 在配置失效时通过 `error.MustReconfigure` 回到 configure 循环（`Maker.zig:923-925`）。`add*Arg` → `add*Arg2`、`b.build_root` → `b.root`、`getDisplayName` → `format` 是一批需要改现有 `build.zig` 的 breaking rename。
- **帮助仍依赖一份成功的配置（冷缓存下必须成功运行 configure）。** `--help`/`--list-steps` 在 configure 之后打印（`Maker.zig:770-780`），#19996/#15154 仍 open；Build Server Protocol 改善了 IDE 内省，但没有让 `--help` 脱离对一份成功的 `build.zig` 配置的依赖。
- **配置缓存纯度是新的正确性面。** configure 期任何不可追踪的副作用都要 `poisonCache`；`.ignored` 明确允许"带毒缓存命中"（可能拿到过期配置），`.disallowed` 直接 panic。`findProgram` 这类看似无害的查询会污染缓存（`Build.zig:1621-1626`）。这是 0.17 新增的复杂度。
- **缓存重做是公共 API 的破坏性变更。** 0.17 发布说明说 `std.Build.Cache` 有大量 breaking changes；二进制格式虽然更快更小，但版本耦合更强。
- **configure 仍是原生任意代码。** 进程拆分不是沙箱；[#14286](https://github.com/ziglang/zig/issues/14286)（WASI 沙箱）仍 open。configurer 可以读环境、跑子进程（`build.zig` 仍是任意原生代码）。
- **`-D` 选项仍是执行路径的副产品。** `b.option()` 在 configure 期间注册 schema（`Build.zig:966-990`），没走到的分支不会出现在帮助里；未知选项仍在 configure 后校验。

## 3. juice 现状

### 3.1 架构总览

juice 是六命令的静态注册表：`build/run/clean/test/version/help`（`src/commands/command.jai:2-9`）。`main.jai` 取 argv、默认 `build`、构造 `Command_Context {root_dir, cache_dir, workspace}` 后交给 dispatcher（`src/main.jai:88-108`）。dispatcher 对命令前置图做 DFS 规划、查环、按拓扑序执行（`src/dispatcher.jai:63-120`）；整个命令 DAG 只有一条边：`run` 依赖 `build`（`src/commands/run.jai:18-25`），其余命令无前置。

workspace 是相位机：`EMPTY → DISCOVERED → PREPARED`（`src/workspace.jai:130-158`）。`prepare_workspace` 解析 artifact plan 并**立即**准备依赖——创建 `target/packages`、解析 git 源、写 import shim（`src/workspace.jai:174-207`、`src/dependency.jai:115-118`、`143-162`）。这是 juice 最接近 configure 的东西，但它同时写盘，而且产物不是可序列化的配置。

构件计划是纯数据：

```jai
// src/module.jai:71-75
Artifact_Plan :: struct {
    target:        Effective_Target;
    target_dir:    string;
    artifact_path: string;
}
```

`make_artifact_plan` 直接推导 `<pkg>/target/<name>.exe`（`src/target.jai:210-223`），编译前就已知；`revalidate_artifact_plan` 在编译前做路径安全复核（`src/target.jai:245-257`）。编译则是：生成 metaprogram（`Compiler_Metaprogram_Options`：output path、intermediate path、import dirs、build file、testing view dir，`src/metaprogram.jai:66-93`）→ 写 `target/build/build-<name>.jai` → `spawn jai` → 检查 `plan.artifact_path` 存在（`src/commands/build.jai:220-282`）。**没有任何跳过逻辑：每次 build 都重新编译每个 target。**

build 的编排是硬编码的三段：PRESTEP → TRANSPILE → COMPILE（`src/commands/build.jai:397-516`）。阶段之间通过固定的 `Lifecycle_Context` 槽传状态，槽是 `*void`（`src/lifecycle.jai:134-169`）；stage 枚举是封闭的九阶段（`src/lifecycle.jai:57-71`），挂载点是 before/at/after，at 钩子替换**整个阶段**（`src/lifecycle.jai:326-339`）。这是管线，不是图。

唯一的惰性化近似是转译视图缓存：key = hash(相对路径 + 源内容 + 模式 + 契约版本 + pipeline 描述 + load 重写表)，因 load 重写嵌入子视图路径而形成 Merkle 链（`src/transpile_cache.jai:78-102`），视图落在 `<transpile_dir>/<hash>/<rel_path>`（`src/transpile_cache.jai:104-123`）。但视图仍然是编译前急切生成并写盘的，不是 make 期兑现的 `LazyPath`。

仓库自己的 `build.jai` 是 `#run` 命令式脚本：发布 modules 树、版本断言子进程、strip 前端、生成编译 metaprogram、spawn `jai`（`build.jai:113-405`）。它和 0.17 的 configurer 只是"构建逻辑是程序"这一点形似；它不输出可序列化配置，而是直接执行，而且必须在不依赖 juice 的前提下自足。

### 3.2 与 Zig 0.17 三点的逐项对照

| Zig 0.17 | juice | 差距 |
| --- | --- | --- |
| configurer 进程只跑 `build()` 并序列化 `Configuration`；maker 进程消费配置 | `prepare_workspace` 产出 `Artifact_Plan` + 依赖 shim，但有写盘/抓取；执行顺序在命令代码里 | 有“计划数据”，没有“计划驱动的执行”；计划不含视图/shim/插件/发布，也不可序列化 |
| `Configuration.Step`（纯数据，无 makeFn）+ `deps` 索引 | build 的 PRESTEP/TRANSPILE/COMPILE 硬编码；compile 串行 for 循环 | 无通用 step 类型、无依赖边、无调度器 |
| `LazyPath.generated` = `GeneratedFileIndex`，make 期填表 | 输出路径编译前固定；状态靠 `*void` ctx 槽与阶段顺序传递 | 无索引表、无 producer/consumer 边 |
| `Configuration.Step.Compile` = 编译描述；`generated_*` = 产物索引 | `Artifact_Plan` 把 target、target_dir、artifact_path 绑死；`compile_artifact_plan` 同时编译与检查 | 编译单元不可复用，产物与编译过程耦合 |
| `InstallArtifact` 只消费 compile step 的产物索引 | publication 只在 `build.jai` 中生产（`build.jai:164-267`），build/test 命令消费 `juice_modules_dir()` 的隐式假设 | 没有一等 producer/consumer 关系 |

## 4. 迁移评估

### 4.1 两阶段生命周期

**可迁移性：高（概念），低（照搬双进程）。**

0.17 基本验证了“纯计划 IR + 计划驱动执行器”的方向：配置是序列化的、可缓存的，纯度可判定，纯配置可绕过 configurer，BSP 直接消费配置。juice 应采用这个方向的轻量版，而不是 0.17 的双进程实现。

建议把 `prepare_workspace` 的“解析”部分抽成纯函数，产出一个可序列化的 `Build_Plan`：workspace discovery 快照、artifact plans、view plan、dependency shim plan、plugin prepare plan、publication plan、test plan。计划带一个 `Plan_Purity {pure, poisoned}`：读 manifest、解析路径、计算 key 算 pure；抓取 git 依赖、spawn plugin host、写 shim/视图算 effectful（计划被污染，执行前必须重新规划或直接执行）。执行阶段只消费计划，不再在命令处理器里临时决定顺序。附带 `juice build --dry-run` / `--list-steps`，以及“计划期报错、执行期不写半截”。

juice 的 poisoning analogue 很直接：`prepare_workspace` 里的 git 抓取、plugin host spawn、shim/视图写盘都应标记 `Plan_Purity.poisoned`；纯的 manifest 读取、路径解析、key 计算保持 pure。纯计划可以按 `package.jai` + workspace 成员 + 插件声明 + 选项缓存；被污染的计划不进缓存。0.17 的 `dependOnFile*` 则对应 juice 的 manifest/`package.jai`/插件声明/源文件依赖声明：把“计划依赖了哪些文件”显式记录，而不是靠 mtime 猜测。`findProgramLazy` 对应 juice 的 `jai`/工具查找：不要在 prepare 期执行 `where jai` 并污染计划，而应把查找变成执行期 producer，只有真正需要编译时才解析。

收益：计划在任何写盘之前完成安全校验与冲突诊断；build/test/run/clean 共享同一份计划语义；纯计划可以缓存（对应 0.17 的 configure cache）；插件 effect 从 `*void` 槽变成计划输入，可测试；为 IDE/工具暴露静态图。

成本：中等。主要工作不是写图库，而是**把散在命令代码里的顺序与隐式状态显式化**，并回答“哪些操作是 configure-pure”。当前 at 钩子可以替换整个阶段并自行做 I/O，这与“纯计划”冲突；需要规定 at 钩子要么返回计划补丁，要么被标记为 effectful，不能两者兼有。

**不采纳**：用户 `build.jai` 作为任意 configure 程序、双进程拆分、二进制配置格式。理由：`package.jai` 已经是声明面，再来一个可编程层就是双源真相；juice 的计划规模远小于 Zig，双进程带来的序列化格式漂移、configurer/maker 版本耦合和工具链断裂（ZLS/#36444）不值得；juice 的 `help` 现在是零副作用的静态注册表渲染（`src/commands/help.jai:18-31`），一旦选项来自用户代码，就会继承 `--help` 失败模式。自举 `build.jai` 必须 test-free 且不依赖被构建的工具，也无法成为通用 configure 宿主。

### 4.2 数据流与 lazy path

**可迁移性：中（仅生成输入），低（最终产物）。**

建议引入 0.17 形态的索引表：`Generated_Input { producer: Producer_Id, output: u16, path: string }`，计划持有表，producer 完成后填写 `path`。只覆盖四类当前“提前写、后面按约定读”的东西——transpile 视图、import shim、插件注册/host 记录、publication 的 modules 树。consumer 在计划里持有 `(producer, output)`，执行器在 producer 完成后解析。最终 artifact（`target/<name>.exe`）继续走固定路径，不惰性化。

收益：阶段之间的隐式顺序和 `*void` 槽可以退场；同层生成物可以并行；为“输入未变则跳过”提供 producer 边界；插件产物第一次成为可组合的数据，而不是约定。索引表而不是指针，使计划可以被打印、比较、缓存——这是 0.17 用 `GeneratedFileIndex` 换来的东西。

成本：中高。需要 typed step（Jai 无闭包，异构 step 只能用 tagged union 或 `*void` + tag）、依赖注册、环检测和一个调度器。juice 目前只有少量 step，抽象可能短期过度设计；建议先在计划 IR 内部用 producer id 表达边，等出现第二个真实消费者再引入调度器。

**不采纳**：Zig 式全量 `LazyPath`、cache-dir 输出路径、跨进程生成的路径解析。理由：`target_layout.jai` 的固定布局是 spec 契约（artifact 根、modules 邻接 exe、transpile 树、tests/recovery 分区，`src/target_layout.jai:56-143`）；输出路径既然已知，惰性化没有收益；路径安全与 LNK1104 hand-off 都依赖“路径可预测且都在 target/ 内”（`src/commands/build.jai:284-365`）。把产物挪进内容寻址目录会同时破坏安装契约与 clean 语义。0.17 删除 `LazyPath.basename` 的代价也说明：一旦允许 make 期才知道路径，所有消费者都必须改成 make 期解析。

### 4.3 编译单元与产物解耦

**可迁移性：高（概念），中（范围）。**

建议拆两个记录：`Compile_Unit { target, entry, import_dirs, view_inputs, flags, output_kind }` 与 `Artifact_Ref { path, producer }`。`compile` 只负责把 unit 变成 artifact；`run` 依赖 artifact 的 producer，而不是通过命令前置依赖整个 `build`；`test` 的 runner 与 `publication` 的 modules 树也都成为带 producer 的 artifact。最高价值的具体点是 publication：它现在只发生在 `build.jai`（`build.jai:164-267`），而 build/test 命令通过 `juice_modules_dir()` 假定它已经存在（`src/commands/build.jai:248`、`src/commands/test.jai:241`）。把它变成一等 producer + 显式 consumer，可以消除这条跨命令的隐式假设。

收益：删掉 `run → build` 的命令级 hack（`src/commands/run.jai:18-25`）；产物存在性从“约定 + 事后检查”变成“producer 已跑”；未来 install/package/资产管线有统一接口；`Compiler_Metaprogram_Options` 可以原样作为 `Compile_Unit` 的编译描述（`src/metaprogram.jai:66-93`）。

**不采纳**：Zig 的 Module / import table / link 模型、byte-packed `Storage`、`GeneratedFileIndex` 的序列化格式。Jai 的 `#import` / `#load` 是源码级解析，编译器自己处理传递闭包；juice 的“模块”边界是发布树与 import shim，不是对象/库边界。硬造 Module 图会与编译器重复，而且无法表达 Jai 的真实解析规则（字面量与包外 `#load` 甚至不被 juice 的 probe 跟随，`src/transpile_front.jai:82-91`）。静态库/动态库/对象文件的 artifact 分类对 juice 当前模型没有对应物。

### 4.4 最大风险与推荐顺序

0.17 让“纯计划 IR”从概念上合理变成有生产实现背书：序列化配置、纯度分类、配置缓存、BSP 都在 0.17 落地；但 0.17 的代价（双进程、ZLS 断裂、#36444）也说明 juice 应取轻量版。最大风险是**把 0.17 的双进程/序列化实现当成目的**。juice 的竞争力来自三个约束：固定且可校验的 target 布局、失败即停且无部分状态、可自举的 test-free 闭包。一个通用 DAG + 调度器 + 配置缓存会把这三条都变成需要重新论证的性质；而 Jai 没有增量编译（juice 自己的 ADR 结论：`issues/0008-transpile-integration-and-cache.md:32`：“jai 无增量，fingerprint/mtime 纯负担”），编译前无法枚举 target 的真实输入集（probe 只跟随字面量 in-package `#load`，`#import` 由编译器解析），所以 Zig 式内容寻址编译缓存在 juice 里**目前没有可靠基础**。

推荐顺序：

1. **纯计划 IR + 纯度分类**（低风险、可逆）：把 build/test 的准备逻辑抽成 `plan_*`，用测试钉住“pure 计划零写盘”；先服务 `--dry-run` 与计划期诊断。纯度分类直接借鉴 0.17 的 `CachePoison`，但只做二态或三态，不做 `.ignored`。
2. **生成输入的索引表**（中风险）：视图、shim、插件记录、publication 四类先接入 `Generated_Input`；仍用现有阶段顺序执行，只是把边数据化。
3. **计划序列化/缓存**（中风险，可选）：为 `--dry-run`、IDE 或重复构建输出一份只读计划；不采用 Zig 的二进制格式，先用可打印的 Jai 数据或 ZON 风格文本，避免格式漂移。
4. **编译跳过**（高风险，单独立项）：只有当第 2 步稳定后，才考虑在编译后记录真实输入集（可复用 test discovery 的编译器注记机制），下一次构建做保守比较。不要在没有输入集的情况下做 mtime/fingerprint 缓存。

这个顺序保留了 Zig 0.17 架构最有价值的部分——**计划与执行分离、生产者与消费者用索引连接、编译描述与产物分离、纯度可判定**——同时不把 juice 变成一个它没有能力正确实现的通用动态构建系统。

## 5. 参考来源清单

### Zig 0.17.0 源码（官方 tarball；Codeberg tag `0.17.0`，commit `7647adab80dd088f4de3610fd245915a912eb6ad`）

- `lib/compiler/configurer.zig`：20-21（`@build`/`@dependencies`）、34-50（configurer 的短生命周期与序列化职责）、138（`runPackageScript`）、150-164（`-D` 校验与 `serializeConfigurationExiting`）。
- `lib/compiler/Maker.zig`：380-383（`--print-configuration`/`--print-configuration-path` 解析）、596（`early_exit_mode`）、737-760（configure 循环）、770-780（help/steps 在 configure 之后）、784-790（`.zon` 打印）、841-930（Build Server Protocol 消息）、923-925（watch 的 `MustReconfigure`）、1097（`configure`）、1149-1180（configurer 的 `-Mroot=configurer.zig` 组装）、1213-1232（configure cache manifest）、1338-1341（`--fetch` 跳过 configurer）、1486-1520（spawn configurer）、1527（`Configuration.loadFile`）、1569-1590（poisoned 配置不缓存 / 纯配置进 `c/<digest>`）、1612-1622（`.path` 打印）、2375-2400（`prepare` 分配 step 与 `generated_files`）、2464（`makeSteps`）、2759（`makeStep`）、3691-3693（`generatedPath` 的 `.?`）、3695（`setGeneratedPath`）、4015-4021（`removePoisonedConfiguration`）。
- `lib/compiler/Maker/Step.zig`：1-30（maker 侧可变 step 状态）、60-90（`Extended` union）。
- `lib/compiler/Maker/Step/Compile.zig`：26-70（lower argv、`evalZigProcess`、按 cache digest 填生成路径）。
- `lib/compiler/Maker/Step/InstallArtifact.zig`：11-84（按 `generated_bin/implib/pdb/h` 安装；27 取 `deps.steps.slice[0]` 为 compile step）。
- `lib/compiler/Maker/ScannedConfig.zig`：226-241（`printSteps`/`printUsage`）。
- `lib/std/Build.zig`：22-27（`Configuration` = configure 的序列化输出；`Serialize` = Build → Configuration）、30-100（Build/Graph 字段，含 `wip_configuration`、`cache_poison`）、110-135（`CachePoison` 语义）、137-140（`addGeneratedFile`）、216-222（`poisonCache`）、360-401（`create`；`default_step` = install）、579/603/637/676（addExecutable/addObject/addLibrary/addTest）、953（getInstallStep）、966-990（option 注册 schema）、1168（step）、1459（installArtifact）、2018-2023（lazy dependency 触发 `serializeConfigurationExiting`）、2143-2160（`runPackageScript`）、2192-2260（builder 侧 `LazyPath`，含 `generated.index`）、559-561/615-618（ExecutableOptions/LibraryOptions 的 `root_module`）、1597-1599（`findProgramLazy`）、1621-1626（`findProgram` 污染缓存）、2599/2625/2653/2681（`dependOnFileContents`/`dependOnFileMetadata`/`dependOnDirectoryContents`/`dependOnDirectoryMetadata`）、2691-2706（`validateConfigureDependency` 禁止 configure 依赖 make 期产物）、2710-2737（`serializeConfigurationExiting`）。
- `lib/std/Build/Configuration.zig`：40-70（序列化 Header）、434（`Wip.addGeneratedFile`）、477-533（`Step` 纯数据 + `Tag`）、547-566（`InstallArtifact` payload）、706-760（`Compile` payload：root_module/root_name/flags/generated_*）、1494-1596（`LazyPath` union）、1583（`GeneratedFileIndex`）、3122（`loadFile`）。
- `lib/std/Build/Module.zig`：191-196（`CreateOptions.root_source_file`）、297（`create`）、306（`addImport`）。
- `lib/std/Build/Cache.zig`：1739-1810（`addDiscoveredPath` 的目录/文件输入与 `metadata_only` 选项）；缓存二进制格式、目录支持、metadata 模式、`zig cache-cat`、miss 解释见 0.17.0 发布说明 "Cache System Reworked" 节。
- `lib/std/Build/Serialize.zig`：17（`write`）、20-56（path deps 序列化）、59-180（step 图遍历与 step payload 序列化）。
- `lib/std/Build/Step/Compile.zig`：244-252（`generated_*` 索引字段）、370（`create`）、680-686（`getEmittedFileGeneric` 分配 `GeneratedFileIndex`）、689-725（`getEmittedBin/Implib/H/Pdb/Docs`）。
- `lib/std/Build/Step/Run.zig`：280（`addArtifactArg2`）、323（`addOutputFileArg2`）、375（`addFileArg2`）、465（`addOutputDirectoryArg2`）、593-597（`addPassthruArgs`：有副作用、禁用缓存，configure 期不可见）。
- `src/main.zig`：352-360（`zig build` 以 `Maker.zig` 作为 jit 入口）。

### Zig 发布说明与 issue/PR

- Zig 0.17.0 发布说明：https://ziglang.org/download/0.17.0/release-notes.html
  - "Separate the Maker Process from the Configurer Process"（PR #35428：https://codeberg.org/ziglang/zig/pulls/35428）：maker 首次安装后构建一次、优化模式；build.zig 逻辑可按 CLI flag 跳过；配置序列化为紧凑二进制；`--print-configuration` 输出 .zon。
  - "Cache System Reworked"：目录支持（目录项增删改名触发 miss）、metadata 模式（size/inode/mtime）、二进制 manifest（约 25% 体积、5-10% 命中提升）、`zig cache-cat`、miss 原因解释。
  - "Introduce the Concept of Configure Cache Poisoning"：`dependOnFileContents` / `dependOnFileMetadata` / `dependOnDirectoryContents` / `dependOnDirectoryMetadata`；`--cache-poison[=pure|poisoned|disallowed|ignored]`；poisoned 配置在 ingest 后删除。
  - "findProgram" / "findProgramLazy"：configure 期查找 vs 返回 `LazyPath`、只在被 step 使用时查找、不污染缓存。
  - "Run Step: Passthru Args"：`addPassthruArgs()` 透传 `zig build run -- ...`，step 视为有副作用。
  - "Removed Ability to Override Build Runner"（configurer + maker 取代 build runner）
  - "Build Server Protocol"（静态图/step 事件/请求 step；ZLS 在 0.17.0 中断裂）
  - "Package Management"：包管理从编译器移入构建系统，`zig build/fetch/init/libc/cache-cat` 均为构建系统子命令。
  - API 变动清单：`b.build_root` → `b.root`、`LazyPath.basename` 删除、`getDisplayName` → `format`、`add*Arg` → `add*Arg2`
  - 已知回归 #36444：https://codeberg.org/ziglang/zig/issues/36444
  - BSP 后续 #36497：https://codeberg.org/ziglang/zig/issues/36497
- Zig 0.16.0 发布说明（Build System 节无架构重写）：https://ziglang.org/download/0.16.0/release-notes.html
- Zig 0.15.1 发布说明（`addLibrary` 合并）：https://ziglang.org/download/0.15.1/release-notes.html
- Zig 官方文档：https://ziglang.org/learn/build-system/
- 历史 issue（GitHub；均仍 open，0.17 的帮助流程未变）：#19996 https://github.com/ziglang/zig/issues/19996、#15154 https://github.com/ziglang/zig/issues/15154、#15635 https://github.com/ziglang/zig/issues/15635、#14286 https://github.com/ziglang/zig/issues/14286

### juice 源码与文档

- `src/main.jai:88-108`（入口与命令分发）、`src/commands/command.jai:2-34`（注册表/Command 形状）、`src/dispatcher.jai:63-120`（命令 DAG 规划与执行）。
- `src/workspace.jai:130-158`（相位机）、`174-207`（prepare 与依赖准备）、`224-237`（ensure 入口）。
- `src/target.jai:210-238`（artifact plan 生成）、`245-257`（编译前安全复核）。
- `src/module.jai:62-75`（Effective_Target/Artifact_Plan）、`149-155`（Prepared_Workspace）。
- `src/commands/build.jai:59-73`（build 入口）、`126-135`（TRANSPILE 内置前端）、`150-159`（COMPILE 串行循环）、`175-209`（入口选择）、`220-282`（compile_artifact_plan）、`284-365`（LNK1104 hand-off）、`397-516`（三段编排）。
- `src/commands/run.jai:18-25`（唯一前置边）、`58-71`（launch）、`76-93`（选择与启动）。
- `src/commands/test.jai:1-30`（test 编排总览）、`241`（Testing 模块路径）。
- `src/lifecycle.jai:57-71`（九阶段枚举）、`134-169`（ctx 槽）、`326-339`（挂载派发）。
- `src/transpile_cache.jai:43`（契约版本）、`78-102`（视图 key/Merkle 链）、`104-123`（视图路径）。
- `src/dependency.jai:115-118`（依赖准备）、`143-162`（import shim）、`390-429`（依赖 strip front）。
- `src/metaprogram.jai:66-93`（Compiler_Metaprogram_Options）、`95-146`（生成器）。
- `src/target_layout.jai:56-143`（target 布局契约）。
- `src/transpile_front.jai:82-91`（probe 只跟随字面量 in-package `#load`）。
- `src/commands/help.jai:18-31`（零副作用静态帮助）。
- `build.jai:113-405`（自举 `#run`：publication、版本断言、strip、生成 metaprogram、spawn jai）。
- `issues/0008-transpile-integration-and-cache.md:32`（“jai 无增量，fingerprint/mtime 纯负担”）。
- `docs/spec.md:324`（增量构建缓存键契约）、§0/§4.6（命令编排与 b1-b8；文件内无行号的章节引用）。
