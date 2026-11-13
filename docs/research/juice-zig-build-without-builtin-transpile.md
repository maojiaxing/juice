# 内建 transpile 退场后的 juice：Zig build 式架构可行性研究（Zig 0.17.0）

> 前提：juice 内部不再内建 transpile，所有源码转译外移到外部产品（jaix，类比 Zig 的 translate-c）。
>
> 版本钉子：Zig 0.17.0（源码 tarball 读取树 `C:\Users\maojiaxing\AppData\Local\Temp\zigsrc-0170\lib\...`；发布说明 `https://ziglang.org/download/0.17.0/release-notes.html`，2026-10-23 本地抓取核验）。juice 一侧 = 本仓库当前工作树；jaix 一侧 = `C:\Users\maojiaxing\Workspace\projects\jai\jaix`。
>
> 本文所有 `path:line` 均为实际读取位置；Zig 的 `LazyPath.generated`、`GeneratedFileIndex`、configurer/maker、`CachePoison` 等事实已在本轮源码中逐条复核。

## 1. 结论摘要

**判定：有条件可行（黄）。** “移除内建 transpile”作为一个职责外移的工程切口是干净的：哪些是源码转译、哪些是构建编排，边界清楚（§2）。真正的问题不在删除，而在三个前提没有现成承接方：

1. **自举**：juice 自己的套件不是 test-free。`src/module.jai` 有 7 个 test block（`src/module.jai:315-389`），`tests/` 下有 546 个（`grep '^test '` 实测），成员包另有 17 个。`src/main.jai:52` 把 `module.jai` 装进可执行文件闭包，`build.jai:60-66` 又把内建 transpile 装进 bootstrap 闭包。不迁移这些 test block，自举就必须保留内建转译或把外部工具塞进 bootstrap；前者违背前提，后者违背“bootstrap 只依赖 juice 仓库源码、单工具自举”的不变式。
2. **#load 路由与全局测试编号**：jaix 今天只做“语法变换”，不做 `#load` 改写（`fixture/golden/load-preserve/.input.view.jai` 逐字节保留 `#load`），也不跨文件全局编号（`Jaix_Plugin_Test_Block.jai:241-255` 的计数在 `Transform_Context` 内，CLI 每次进程新建上下文，`cli.jai:245` → `config.jai:314-317`）。而 juice 的 build 视图靠 `#load` 重写形成 Merkle 链（`src/transpile_cache.jai:78-102`、`src/transpile_front.jai:205-269`），test 的 EXPAND 靠把 in-package `#load` 注释掉避免驱动重复加载（`src/transpile_plugin.jai:184-185`）。这两个契约没有外部承接方，外移后 build/test 都不完整。
3. **外部 translator 的成本与身份**：当前 jaix 集成逐文件 spawn CLI（`packages/juice-plugin-jaix/module.jai:243-256`），每次 spawn 都要编译一个 driver（`jaix/src/cli.jai:293-294`；jaix spec §8 记录单次 jai 调用约 2.1s）。同时 `src/` 有零 jaix 引用守卫（`tests/jaix_guard_tests.jai:1-20`），接入面必须是通用 translator 插件/registry，不能把 jaix 写进命令核心。

**Zig-build 式架构判定：可行（黄绿）。** 纯 `Build_Plan` IR + 单进程计划驱动执行器 + 一等 `Translate` producer + `Generated_Input` 索引表是正确方向；不要照搬 Zig 0.17 的双进程与序列化配置（其代价见发布说明 “Separate the Maker Process from the Configurer Process” 与 ZLS 断裂）。`.FILE` 后编译输入记录可以为 build 跳过提供可靠输入集，但**不能**用于 test：测试程序的编译期 `#run` 就是测试执行本身。

**三个最大风险**：自举套件的 test-block 依赖；`#load` 路由/全局编号的外部契约缺口；外部 translator 的批量化成本与通用接入身份。

## 2. 内建 transpile 的现状清单

先划清“源码转译”与“构建编排”。转译 = 改变编译输入的文本；编排 = 决定谁编译、何时编译、产物放哪。

| # | 职责 | 代码位置 | 分类 | 外移后归属 |
|---|---|---|---|---|
| 1 | 两种模式 `STRIP`/`EXPAND` | `src/transpile.jai:27-32` | 转译框架 | 外部 translator |
| 2 | test block STRIP（等行数注释占位） | `src/transpile_plugin.jai:320-335`、`strip_block_edit` `src/transpile.jai:536-551` | 转译 | 外部 translator |
| 3 | test block EXPAND（`juice_test_N` + `@test` + `Test_Entry`） | `src/transpile_plugin.jai:337-349`、`Test_Entry` `src/transpile.jai:44-49` | 转译 + 簿记 | 外部 translator（编号契约待定） |
| 4 | `#load` STRIP 改写 / EXPAND 注释占位 | `src/transpile_plugin.jai:163-200` | 转译 + 路由 | 外部 translator 或 juice 保留路由（后者违背前提） |
| 5 | 入口闭包探测（字面量 in-package `#load` DFS） | `src/transpile_plugin.jai:137-156`、`src/transpile_front.jai:91-135` | 编排 | juice（但只服务视图决策，外移后可删除） |
| 6 | 行号保真门（1 行换 1 行 + token 边界） | `src/transpile_plugin.jai:455-468`、`487-553` | 转译框架 | 外部 translator 自证 |
| 7 | 插件管线/声明解析（含内置 `load`/`test-block`） | `src/transpile_plugin.jai:75-82`、`392-405`；`src/transpile_config.jai:68-90`；`src/plugin.jai:273-306` | 转译框架 + 编排 | 删除内置 id；外部插件经 PRESTEP 接入 |
| 8 | 内容寻址视图键（含管线描述、Merkle 链） | `src/transpile_cache.jai:43`、`78-123`；`src/transpile_front.jai:205-269` | 编排（缓存） | 外部 translator 输出自己的 key/manifest |
| 9 | Testing 模块 build STRIP 视图 | `src/transpile_front.jai:313-342`；消费 `src/commands/build.jai:248` | 转译 + 特例 | 删除特例（发布面改为 test-free）或外部处理 |
| 10 | Testing 模块 test EXPAND + support block | `src/commands/test.jai:251-314`、`324-351` | 转译 + 特例 | 同上 |
| 11 | 依赖闭包 STRIP 视图 + shim 改写 | `src/dependency.jai:390-429` | 转译 + 编排 | 外部按依赖包翻译；shim 指向视图 |
| 12 | 全局测试编号（跨文件基 1 续号） | `src/commands/test.jai:419-430`；`src/transpile_plugin.jai:337-339` | 转译簿记 + 编排 | 外部 batch 契约，或 juice 分配编号 |
| 13 | 转译诊断 → `file:line,col` | `src/transpile_plugin.jai:176-193`、`236-238`；`src/commands/test.jai:422-426` | 转译 | 外部输出诊断，juice 只透传 |
| 14 | build 入口选择（替换/剔除/闭包） | `src/commands/build.jai:175-209` | 编排 | juice（消费 PRESTEP 替换表） |
| 15 | 编译 metaprogram 生成 + spawn + artifact 检查 | `src/metaprogram.jai:95-165`；`src/commands/build.jai:220-282` | 编排 | juice 保留 |
| 16 | test driver/metaprogram + 注记发现注入 | `src/test_runner.jai:52-74`、`177-405`；`src/test_discovery.jai:193-204`、`237-251` | 编排 | juice（或按 0065 迁 testing） |
| 17 | PRESTEP jaix 插件（镜像 + 源替换表） | `packages/juice-plugin-jaix/module.jai:204-262` | 编排（外部工具） | 已是“外部 translator 的前身” |

两个关键形状：

```jai
// src/transpile.jai:27-32
Transpile_Mode :: enum u8 {
    STRIP;   // build: test blocks -> 等行注释占位，in-package #load 改写为视图路径
    EXPAND;  // test: test blocks -> juice_test_N 过程，in-package #load 注释占位
}
```

```jai
// src/transpile.jai:44-49
Test_Entry :: struct {
    name:   string;  // 显示名；匿名 = "path:line"
    number: s64;     // N in juice_test_N
    line:   s64;     // 原文件行号
}
```

注意：`Test_Entry.line` 在当前 note 发现路径里并不被消费；发现只看编译器的 `@test` 注记（`src/test_discovery.jai:30-44`、`237-251`）。真正被消费的是编号（`commands/test.jai:429`）与过程名（`juice_test_N` 的数值前缀排序，`src/test_discovery.jai:57-107`）。这决定了外部 translator 的最小契约重点在编号，而非行号。

## 3. 移除后的断点分析

| 面 | 断点 | 性质 |
|---|---|---|
| build | 含 test block 的编译闭包直接语法错误；juice 自身闭包含 `src/module.jai`（`src/main.jai:52`），其 7 个 test block 使自构建先死 | 架构性 |
| build（Testing） | `testing_module_strip_view_dir` 删除后，任何 `#import "Testing"` 的构建都会遇到已发布模块里的 test block（`publication.jai:221-225` 保留自测块） | 架构性 |
| test | EXPAND 删除后 546 个 test block 全部不可编译；Testing EXPAND/support block、`path_mapping`（`src/commands/test.jai:546-557`、`src/test_runner.jai:552-557`）一并失效 | 架构性 |
| run | 经 build 前置，继承 build 的断点 | 机械 |
| clean | 只删 `target/`（`src/commands/clean.jai:55-90`），不受影响 | 无 |
| publication | `JUICE_CORE_LOAD_FILES` 含 `transpile.jai`/`transpile_plugin.jai`（`src/publication.jai:83-88`），`juice_core` 发布面与 `Juice_Plugin.transpile` 字段（`src/plugin.jai:219`）随之内缩；8 件发布树变化 | 机械 + API 破坏 |
| 依赖 shim | `prepare_dependency_strip_views` 删除后，依赖包里的 test block 无法编译；shim 仍可解析 import，但不再指向视图 | 机械（删代码）+ 架构（依赖翻译归属） |
| 自举 `build.jai` | `#load` 闭包去掉 transpile 四件（`build.jai:60-66`）；strip front（`build.jai:88-111`）、Testing 特例（`build.jai:356`）删除后入口必须是 test-free | 机械 + 架构 |
| testing/ 工作区 | 当前 `testing/` 为空目录；0066 的“vendored prefixed 镜像 + 发布面自测”、0068 的“juice 保留 `Transpile_Plugin`/runner/load 插件”前提全部被新前提推翻 | 决策层面 |
| juice 自有 test blocks | `src/` 7 个 + `tests/` 546 个 + 成员 17 个 | 机械量巨大，但决定自举是否成立 |

两个容易漏掉的机械断点：

- `packages/juice-plugin-jaix/module.jai:426` 用 `pipeline_has_anchors(default_transpile_pipeline(), ...)` 判断“文件是否含 juice test block”以决定跳过；内建管线删除后，这个成员插件连同 `juice_core` 的 `transpile_plugin` 发布面一起编译失败。外部 translator 必须自己识别 test block（启用其 test-block 插件），或 juice 保留一个不叫“转译”的锚点谓词。
- `merge_plugins`/`resolve_plugin_configs` 的内置 id 校验、`Package.plugins` 里的 `load`/`test-block` 声明都会变成未知 id（`src/plugin.jai:273-306`、`src/transpile_config.jai:48-61`）。这是对插件 API 的 breaking change，需要迁移说明。

关于 test 命令，需要把“转译”与“执行”分开看：它的发现/执行骨架不依赖内建转译——`.TYPECHECKED` 消息累积测试过程 header，`.PHASE == .TYPECHECKED_ALL_WE_CAN` 时注入 runner，随后编译期 `#run` 执行测试（`src/test_runner.jai:266-287`、`src/test_discovery.jai:237-251`）。删除 EXPAND 不会删掉这套循环；变化的是循环的**输入**：所有被 `#load` 的文件必须已经是合法 Jai。因此 test 命令可以保留，内建转译删除后它只缺“输入已展开”这一前提。

## 4. jaix 吸收能力评估

| 能力 | jaix 现状 | 缺口 | 结论 |
|---|---|---|---|
| EXPAND / STRIP | `Test_Block_Options.mode`（`modules/Jaix_Plugin_Test_Block.jai:140-158`）；EXPAND lowering `381-452`；STRIP `516-538`；golden 已锁 | juice 的 STRIP 占位首行是 `// juice: test stripped: <原文>`（`src/transpile.jai:540`），jaix 只用 `//`（`Jaix_Plugin_Test_Block.jai:499`）；语义等价、字节不同 | 绿（语义）/ 黄（字节基线） |
| 行保真 | 插件承诺头行 1:1、`@test` 行尾、STRIP 等行数（spec §10.1）；框架不设全局硬约束（spec §6 第 102 行） | 需把“插件自证”变成契约，juice 不能再依赖自己的 `enforce_line_fidelity` | 绿 |
| Test_Entry | `{name, proc_name}`（`576-579`），经 `test_entries(plugin_artifacts)` 取（`601-610`） | 无 `line`、无全局编号；编号是 `Transform_Context` 内的单调计数（`241-255`）；CLI 成功时静默（`cli.jai:283` 注释 / spec §9.1），stdout 不携带 entries | 黄 |
| 全局编号 | `transpile_source_ctx` 可跨调用复用上下文（`config.jai:257-308`）；但 CLI driver 调 `transpile_source`，每次新建上下文（`cli.jai:245` → `config.jai:314-317`） | 逐文件 CLI 进程每个文件都从 1 开始 → `juice_test_1` 跨文件重名（Jai 程序作用域冲突）。juice 今天用 `next_test_number` 跨文件续号（`commands/test.jai:419-430`） | 红（现状）/ 绿（加 batch 契约） |
| `#load` 路由 | 逐字节保留（`fixture/golden/load-preserve/.input.view.jai`）；jaix spec §1 明确把“juice 自身 test-block/#load 转译的插件化”列为非目标（`docs/spec.md:23`） | 没有 STRIP 视图目标改写、没有 EXPAND 注释剥离、没有 Merkle 视图表 | 红 |
| 与 import shim 的组合 | 无包概念，只处理输入文件 | 依赖包的翻译要按包根、按拓扑序独立执行；shim 需指向依赖视图或依赖整包镜像 | 红（需新契约） |
| 混合文件（jaix 扩展语法 + juice test block） | 当前 juice 侧插件直接排除含 test block 的文件（`packages/juice-plugin-jaix/module.jai:418-428`） | 这类文件既不被 jaix 翻译，也不被 juice STRIP；若同时含 try/catch 会编译失败。jaix 已启用 test-block 插件时可覆盖，但需 mode/编号配置 | 黄（可解，需重配） |
| 成本 | 每文件一次 `jaix transpile`，每次编译 driver（`cli.jai:293-294`；spec §8 约 2.1s/次）；配置执行缓存是进程内全局（`config.jai:663`），CLI 每次进程不复用 | N 文件 = N × 编译 driver；juice 根 src+tests 约 195 个 `.jai`（含 fixture），百级文件 × 2.1s = 数分钟 | 红（逐文件）/ 绿（batch） |

**外部契约建议**（translator 无关，jaix 可作为实现方之一；juice 的 `src/` 仍零 jaix 引用）：

```text
Translate_Request  { root, mode: strip|expand|identity, config_path,
                     files: [{rel_path, source_hash}], view_root,
                     dependency_view_roots: [{name, root}] }
Translate_Manifest { protocol, translator_id, translator_version, key,
                     files: [{rel_path, view_rel, source_hash, view_hash,
                              tests: [{name, number, line}]}],
                     load_routes: [{from_rel, to_view_abs}],
                     diagnostics: [{rel_path, line, column, level, message}],
                     ok }
```

硬要求：一次调用处理一个包的全部文件（共享上下文 → 全局编号）；manifest 原子落盘（tmp + rename）；`#load` 策略三态显式（`strip` = test 驱动模式、`rewrite` = build 视图、`preserve` = 普通用户文件）；诊断坐标对原文件。当前 `transpile_source_ctx` 已能提供库级共享上下文，但 juice 不能链接 jaix（会破坏自举自包含，也撞 `src/` 零 jaix 守卫），所以必须是 CLI/子进程形态的 batch，而不是库调用。

组合顺序（外部 translator 侧）：依赖包按拓扑序先翻译（每个包一个 manifest），根包最后翻译；根包的 `-import_dir` 指向依赖视图根（或依赖整包镜像），`target/packages/<name>.jai` 的 shim 改写为依赖入口视图路径。这样“原文件 / shim / 生成视图”三者不混在同一个翻译批次里，shim 只承担 import 解析，不进入 translator 的输入集。

## 5. Zig-build 式架构方案

### 5.1 纯计划 IR + 计划驱动执行器

Zig 0.17 的证据：`Configuration` 是 configure 的序列化输出（`lib/std/Build.zig:24-27`），`Configuration.Step` 是纯数据（`Configuration.zig:477-533`），`Compile` payload 只带 `root_module`、flags 与 `generated_*` 索引（`706-750`），`LazyPath.generated` 只存 `GeneratedFileIndex`（`1494-1585`），make 期才由 producer 填路径（`Maker.zig:2390-2392`、`Maker/Step/Compile.zig:46-78`）。juice 应取“计划是数据、边是索引、执行期兑现”，不取双进程。

```jai
Build_Plan :: struct {
    command:   Plan_Command;   // build | run | test | clean | version | help
    purity:    Plan_Purity;    // .pure | .poisoned（对应 Zig CachePoison，Build.zig:110-135）
    units:     [..] Compile_Unit;
    artifacts: [..] Artifact_Ref;
    producers: [..] Producer;      // Translate | Shim | Publish | Plugin_Host | Compile
    inputs:    [..] Generated_Input; // producer -> output 索引表，path 执行期填
}
Compile_Unit :: struct { target, entry: Input_Ref, import_dirs: [] string,
                         flags: Compile_Flags, output_kind: Output_Kind }
Artifact_Ref :: struct { unit: Unit_Id, path: string }   // 固定路径
Generated_Input :: struct { producer: Producer_Id, output: u16, path: string, resolved: bool }
Producer :: struct { kind: Producer_Kind, deps: [] Producer_Id, outputs: [] Output_Id, key: string }
Plan_Purity :: enum { pure; poisoned }   // git 抓取/plugin host spawn = poisoned
```

与 Zig 一样，**计划期只允许做可追踪的事**：读 manifest、解析路径、算 key 是 pure；`git clone`、spawn plugin host 是 poisoned。区别是 juice 不做序列化配置缓存（至少 v1 不做），纯计划只服务 `--dry-run`、诊断和 IDE 静态图。

命令映射：

| 命令 | 计划 | 执行 |
|---|---|---|
| build | Discover → Prepare（依赖/shim）→ PRESTEP（外部插件）→ Translate（可选）→ Compile | 生产者拓扑执行；artifact 固定落 `target/` |
| run | build 计划 + `Artifact_Ref` | 跑 build 后 launch |
| test | 文件收集 + Translate(EXPAND) + Test_Compile + Execute | 编译即执行；**永不跳过** |
| clean | Discover + 路径表 | 先全量校验后删 `target/`（`clean.jai:55-90`） |
| version/help | 无计划（静态注册表，`commands/help.jai`） | 零副作用渲染 |

### 5.2 一等 Translate producer 与索引表

`Translate` producer 声明输入（包根、文件列表 + 内容 hash、mode、config、依赖视图根）、输出（视图根 + manifest）、key（translator id/version + config 内容 + 有序输入 + mode + 协议版本）。执行器在 producer 完成后读取 manifest，把每个输出填入 `Generated_Input.path`；`Compile_Unit.entry` 持 `Input_Ref`（source 或 generated 索引，等价于 Zig `LazyPath` 的 `source_path`/`generated` 两分支，`Configuration.zig:1494-1506`）。缺 producer 边 = 计划期错误（而不是 Zig make 期的 `.?` panic，`Maker.zig:3691-3693`）。

关键收益：视图、shim、插件注册、发布模块第一次成为计划里的数据；TRANSPILE/DEP_STRIP 阶段（`src/lifecycle.jai:57-71` 的封闭枚举只增不改）不再有内建实现，退化为与 PRESTEP 相同的“无声明 = no-op + 可挂载”阶段；`Lifecycle_Context` 的 `*void` 槽（`134-169`）可以被 typed producer 输出替代。

### 5.3 Compile_Unit / Artifact_Ref / 发布 producer

`Compile_Unit` 是编译描述，`Artifact_Ref` 是消费者句柄。run/install/publication 只消费 `Artifact_Ref`，不依赖“build 命令已经跑过”的隐式前提。最高价值的具体点是 publication：它今天只在自举 `build.jai` 里生产（`build.jai:163-267`），而 build/test 通过 `juice_modules_dir()` 假定它存在（`src/commands/build.jai:248`、`src/commands/test.jai:241`）。把它变成 `Publish` producer + `Publication_Ref`，build/test 显式依赖它，Zig `InstallArtifact` 消费 compile 产物的模式（`Maker/Step/InstallArtifact.zig:26-54`）才有对应物。

### 5.4 `.FILE` 后编译记录与缓存

Jai 编译器在消息循环里对每个加载文件发 `.FILE`（`C:/Users/maojiaxing/DevTools/jai/modules/Compiler/Compiler.jai:236-260`，`Message_File.fully_pathed_filename`；官方 how_to `450_basic_metaprogram/first.jai:85`）。这给出**编译后**的真实输入集，不是编译前枚举；juice 的 ADR 已结论 Jai 无增量编译（`issues/0008-transpile-integration-and-cache.md:32`）。

建议 manifest：

```text
unit_key = hash(compiler_id/version, target, flags, entry_rel,
                import_dir_set, sorted[(origin_rel, content_hash)] from last .FILE set,
                translate_keys)
manifest { unit_key, compiler_version,
           files: [{original_rel, content_hash, view_abs?}],
           artifact_hash, written_at }
```

规则：编译成功后原子写 `target/build/<unit>.manifest.tmp` → rename；下一次 build 只在 manifest 存在、所有记录文件内容 hash 相同、translate key 相同、编译器/flags 相同时跳过编译。`.FILE` 里的视图路径经 translate manifest 映射回原文件；未能映射的路径（编译器/标准库文件）**也必须记录**——用绝对路径 + 内容 hash，否则工具链或 stdlib 变化会被漏掉；编译器版本作为主键分量兜底。**test 不能用**：测试程序的编译期 `#run` 就是执行（`test_runner.jai:197-287` 注入的 runner 在编译期跑 `run()`/`finish()`），跳过编译等于跳过测试。测试结果缓存是另一个特性，需要显式语义，不能混进编译跳过。

### 5.5 固定目标布局

保留固定：artifact 根 `target/<name>.exe`、`modules/`（安装契约 `<exe>/modules`）、`build/`、`plugins/`、`packages/`、`tests/`、`recovery/`、`evidence/`（`src/target_layout.jai:56-143`）。可惰性/索引化：translate 视图树（内容寻址 + manifest）、shim、插件注册、发布模块（作为 producer 输出但落点固定）。最终 artifact 不惰性化——LNK1104 hand-off 与路径安全都依赖可预测路径（`src/commands/build.jai:284-365`）。

### 5.6 与最小方案的对比

| 方案 | 内容 | 成本 | 风险 | 收益 |
|---|---|---|---|---|
| 最小 | 保留现有 PRESTEP + 管线，只加 `Compile_Unit`/`Artifact_Ref` 记录与后编译 manifest；外部 translator 仍以插件形式替换源 | 低 | 低 | 编译跳过、publication 显式化；不解决 `*void` 槽与静态图 |
| 完整 | 纯计划 IR + producer 图 + `Generated_Input` 索引表 + 外部 Translate producer | 中 | 中 | 计划可打印/`--dry-run`/IDE、插件产物可组合、阶段顺序数据化 |
| 照搬 Zig | 再加双进程 + 序列化配置 + 配置缓存 | 高 | 高（纯度纪律、格式漂移、工具链断裂） | 对 juice 规模收益不足 |

**建议**：先做最小方案（前提变更本身已经很大），把外部 Translate 契约跑通；契约稳定后再升级到完整计划 IR。不要双进程。

## 6. 自举可行性

事实基线：`build.jai:60-66` 的 bootstrap 闭包 = `{transpile, transpile_plugin, transpile_cache, transpile_front, target_layout, metaprogram, publication}`，其中前四件全部服务于内建转译；`src/main.jai:52` 把 `src/module.jai`（含 7 个 test block）装进 exe 闭包；`tests/` 有 546 个 test block，成员包 17 个；`tests/` 没有顶层 `#load` 指令（实测），因此把 test block 一次性改成顶层 `@test` 过程后，生成的 test driver 直接 `#load` 原文件即可，不需要 EXPAND。

| 选项 | 做法 | 保留的不变式 | 打破的不变式 | 判定 |
|---|---|---|---|---|
| 1. 套件去 test-block 化 | 一次性 codemod：546+7+17 个块改为 `juice_test_N :: () -> () { ... } @test`；Testing 自测移到 `tests/`（它们引用 `tests/test_support.jai` 的 `self_testing_failures`/`g_self_*`，留在 `src/module.jai` 会让发布模块引用测试专用全局） | `jai build.jai` 只从 juice 仓库源码构建；bootstrap #load 集 test-free；无外部工具 | 无（相对前提）；代价是 0066 的 vendored 镜像决策需改写 | **推荐（黄）** |
| 2. 保留最小 strip/expand fallback | test 命令内保留 test-block 转换 | 存量套件零改写 | 直接违背“无内建 transpile”；且为支持 EXPAND 仍需 lexer/edit/编号/#load 剥离，实际不是“最小” | 红（诚实结论：等于没删） |
| 3. 发布期生成 test-free 树 | 外部 translator 预翻译整树，bootstrap 编译生成树 | 单工具 bootstrap | 单一事实源（生成树与源漂移），且 `juice test` 仍需预展开树 | 黄 |
| 4. 外部 translator 进 bootstrap | 把 jaix 或 vendored 版本加入构建链 | 无 | “bootstrap 只依赖仓库内源码 / 单工具自举” | 红 |

**推荐选项 1。** 它精确保持的不变式是：`jai build.jai` 在没有任何外部工具、只读 juice 仓库源码的情况下构建 juice；juice 的 `src/` 闭包 test-free；发布树不引用仓库外源码。它带来的语义变化是：test block 从“juice 自己的测试语言”降级为“用户包可选的外部语法扩展”，juice 自身不再使用。若用户坚持 juice 自己的测试继续写 test block，则前提不可行——只能在选项 4 下成立，而那会改写自举不变式。

## 7. 迁移顺序与待拍板决策

**分部判定**：

| 部分 | 判定 | 依据 |
|---|---|---|
| A 内建 transpile 清单 | 绿 | 职责可逐项枚举，转译/编排边界清楚（§2） |
| B 移除后断点 | 绿（分析）/ 红（现状） | build/test/bootstrap 三处架构性断点已定位（§3） |
| C jaix 吸收 | 黄绿（语法变换）/ 红（#load 路由、全局编号、依赖组合、逐文件成本） | §4 表；需新 batch 契约 |
| D Zig-build 式架构 | 黄绿 | 计划 IR + 索引表可行；`.FILE` 缓存 build 绿、test 红（§5） |
| E 自举 | 黄（选项 1）/ 红（选项 2/4） | 570 个 test block 的一次性迁移是唯一不破不变式的路径（§6） |

**最小可行顺序**：

1. 冻结基线；把 `tests/`、`src/module.jai` 与成员包测试的 test block 一次性 codemod 为 `@test` 过程（用当前内建 EXPAND 产物做迁移工具，产物直接回写源文件）；Testing 自测移入 `tests/testing_face_tests.jai`。验证 `juice test` 在“无视图、直接 #load 原文件”的 identity 模式下全绿。
2. 删除内建管线：TRANSPILE/DEP_STRIP 退化为无内建实现的挂载阶段；build/test 只消费 PRESTEP 替换表（有替换用替换，无替换用原文件）；删除 Testing 特例与 dependency strip front（含 test block 的依赖在外部契约落地前明确报错，不静默降级）。
3. 缩发布面：`JUICE_CORE_LOAD_FILES` 去掉 transpile 两件，删除 `Juice_Plugin.transpile` 与内置 `load`/`test-block` id（breaking change，写迁移说明）。
4. 落地外部 Translate 契约（§4 的 batch + manifest + 全局编号 + `#load` 三态），以一个通用 translator 成员插件接入（jaix 是实现之一，juice 核心零引用）。
5. 升级到完整计划 IR + `Generated_Input` 索引表；publication 成为一等 producer。
6. 最后接 `.FILE` manifest 与 build 编译跳过；test 永不跳过。

**必须拍板的决策**：

- **D1**：“无内建 transpile”是否包含 juice 自己的 test block？推荐是；否则自举前提不成立。
- **D2**：是否接受一次性改写 570 个 test block（546 + 7 + 17，含成员包）？谁拥有 codemod 与基线重定（`juice_test_N` 计数不变可做到零重定）。
- **D3**：全局测试编号归谁？推荐外部 translator 的 batch 契约；juice 只透传/校验。
- **D4**：`#load` 路由归谁？推荐外部 translator 的 `strip|rewrite|preserve` 三态；juice 保留路由就等于保留源码转译，违背前提。
- **D5**：依赖包里的 test block 如何处理？推荐外部按依赖包独立翻译，shim 指向依赖视图；或明确禁止依赖含 test block。
- **D6**：发布面 `Testing.jai` 是否保持自测块？推荐移出自测，使发布面 test-free，删除 build/test 两个 Testing 特例。
- **D7**：先最小方案还是直接完整计划 IR？推荐先最小方案，契约稳定后再 IR。

## 8. 参考来源

### Zig 0.17.0 源码（本地 tarball）

- `lib/std/Build.zig:24-27`（`Configuration`/`Serialize` 定义）、`99-135`（`Graph.cache_poison`/`CachePoison`）、`137-140`（`addGeneratedFile`）、`2599-2632`（`dependOnFileContents/Metadata`）。
- `lib/compiler/configurer.zig:138-164`（runPackageScript + 序列化退出）。
- `lib/std/Build/Configuration.zig:477-533`（`Step` 纯数据 + Tag）、`706-750`（`Compile` payload + `generated_*`）、`1494-1585`（`LazyPath` union + `GeneratedFileIndex`）。
- `lib/compiler/Maker.zig:2390-2392`（make 期分配 `generated_files` 表）。
- `lib/compiler/Maker/Step/Compile.zig:46-78`（lower argv、`evalZigProcess`、填生成路径）。
- `lib/compiler/Maker/Step/InstallArtifact.zig:26-54`（消费 compile step 的 `generated_bin`）。
- `lib/std/Build/Module.zig:9-52`（Module/import table）。
- 0.17.0 发布说明：`https://ziglang.org/download/0.17.0/release-notes.html`，“C Translation Moving to External Package”（`@cImport` removed；`std.Build.Step.TranslateC` deprecated in favor of `codeberg.org/ziglang/translate-c`）、“Separate the Maker Process from the Configurer Process”（PR #35428）、“Cache System Reworked”、“Introduce the Concept of Configure Cache Poisoning”、“Build Server Protocol”。源码侧复核：`src/` 与 `lib/std` 已无 `@cImport` 引用（grep 零命中）；`lib/std/Build.zig:949-950` 仍保留 `addTranslateC` 过渡入口。

### juice

- `src/transpile.jai:27-61`；`src/transpile_plugin.jai:75-109`、`137-200`、`214-356`、`366-405`、`455-553`；`src/transpile_cache.jai:43`、`78-132`；`src/transpile_front.jai:91-146`、`205-298`、`313-342`；`src/transpile_config.jai:48-90`。
- `src/commands/build.jai:126-135`、`175-282`、`397-516`；`src/commands/test.jai:100-115`、`173-193`、`251-314`、`324-351`、`389-496`、`519-653`；`src/commands/clean.jai:55-90`。
- `src/metaprogram.jai:66-211`；`src/test_runner.jai:52-74`、`177-405`、`484-587`；`src/test_discovery.jai:30-107`、`193-251`。
- `src/dependency.jai:143-162`、`390-429`；`src/publication.jai:83-88`、`191-280`；`src/plugin.jai:214-306`；`src/lifecycle.jai:57-71`、`134-169`；`src/workspace.jai:130-158`；`src/target_layout.jai:56-143`；`src/main.jai:36-86`；`src/module.jai:157-389`。
- `build.jai:60-66`、`88-111`、`113-134`、`163-267`、`288-312`、`325-401`。
- `packages/juice-plugin-jaix/module.jai:204-262`、`313-318`、`418-428`。
- `tests/jaix_guard_tests.jai:1-20`；`issues/0008-transpile-integration-and-cache.md:32`；`issues/0065-map-test-migration-to-testing-package.md:19-33`；`issues/0066-decision-testing-dependency-cut.md` Resolution 1-4；`issues/0067-decision-testing-package-location.md` Resolution 1/4/5；`issues/0068-decision-text-test-block-api.md` Progress；`issues/0073-jaix-test-block-plugin-migration.md`；`issues/0075-decision-test-discovery-migration-seam.md` Q3。
- `docs/spec.md:253-278`（§8.1/§8.3）、`280-295`（§9）、`297-312`（§10）、`324`（增量缓存键契约）、`361-368`（§13）。

### jaix

- `docs/spec.md:23`（非目标：juice 自身 test-block/#load 转译的插件化）、`138-142`（§9.2 库 API）、`202-208`（§10.1 test block）、`227-232`（§12 juice 集成 seam）。
- `src/config.jai:141-144`（`Jaix_Config`）、`257-308`（`transpile_source_ctx`）、`314-317`（`transpile_source` 每次新建 ctx）、`501-548`（`execute_config`）、`663`（进程内缓存全局）。
- `src/cli.jai:203-266`（driver 生成）、`284-315`（`run_cli_capture`；每次写 driver）。
- `modules/Jaix_Plugin_Test_Block.jai:140-158`（mode/prefix）、`241-255`（计数）、`381-452`（EXPAND）、`516-538`（STRIP）、`576-610`（`Test_Entry`/访问器）。
- `fixture/golden/load-preserve/.input.view.jai`（`#load` 逐字节保留）；`fixture/golden/test-expand/.input.view.jai`、`test-strip` 等 golden。
- `C:/Users/maojiaxing/DevTools/jai/modules/Compiler/Compiler.jai:236-260`（`.FILE` 消息）；`450_basic_metaprogram/first.jai:85`（官方用法）。
