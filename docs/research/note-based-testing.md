# otter note-based test 内置命令研究——@test 注记发现机制

> 研究问题：otter 将 test 改为内置命令（内置 = build/clean/test），单元测试采用社区/官方 note 方案（`@test` 注记约定），插件经 lifecycle 钩子覆盖默认实现。本文钉住 note 机制的精确事实（实验 + 源码），并给出 otter test 内置命令的端到端设计。
> 日期：2026-10-19 | 环境：Jai beta 0.2.009（2025-02-06），Windows 11 + Git Bash，编译器 `C:/Users/maojiaxing/DevTools/jai/bin/jai.exe`
> 证据标注：【实验】= 本机编译运行验证 | 【源码】= 发行版/本仓库源码逐行阅读 | 【官方文档】= 官方注释原文 | 【推断】= 基于事实的推理
> 实验目录 `C:/Users/maojiaxing/AppData/Local/Temp/otter-note-research/`（build.jai 观察 metaprogram + target.jai/loaded.jai 目标程序），未修改仓库产品代码。

## 结论摘要

| 问题 | 判定 |
| --- | --- |
| note 机制精确事实 | 【实验】证实：`@test` → `note.text='test'`；`@test(x)` → `text='test(x)'`；`note_flags` 恒 0 且全发行版无预定义位；注记同时出现在 `procedure_headers` 与 `declarations`；`#load` 文件声明入消息循环；官方明示不依赖消息序（how_to/460 排序指导） |
| @test 约定现状 | 发行版 8 处零消费方（前研究已钉）；**juice EXPAND 已落实产物注 `@test`**（`transpile_plugin.jai:316` 一手核验） |
| 发现机制推荐 | metaprogram 消息循环枚举 `procedure_headers` 中带 `test` 注记的声明，累积到 `TYPECHECKED_ALL_WE_CAN`，按名排序，文件来源过滤（`enclosing_load.fully_pathed_filename`）隔离依赖 |
| runner | 注入式 `#run` 显式调用表（how_to/460/470 官方模式）+ Testing 模块 run/finish 汇总退出码（juice 语义不变：编译期执行） |
| 插件覆盖面 | test 五阶段 at 钩子（发现/转译/runner 生成/编译/执行）；命令注册表静态 build/clean/test；lint 借 Typechecked 消息（现实挂点） |
| bootstrap 路径 | 阶段 0-2 测试 = juice test 块（juice 只发现块）；EXPAND 产物已带 `@test` → 阶段 3 自举后 note 方案跑存量套件**零重写**；test 块经内置转译插件降为 `juice_test_N` + `@test`，与手写 `@test` 过程统一进单一发现源 |

---

## 1. Jai note 机制精确事实

### 1.1 语法面

- 尾注形态：声明后 `@name`，可带参数 `@name(args)`。**参数须标识符形**——字符串字面量参数实验报错原文 `target.jai:11,1: Error: Newline in string constant!`（`@test("custom name")` 被拒）【实验】。
- 发行版参数化注记实例：`} @selector(windowWillClose:)` 等（`modules/Input/macos.jai:569+`、`modules/Objective_C/module.jai:23,256`、`modules/Gamepad/Gamepad.jai:501,513`）【源码】。
- 注记文本语义（实验钉住）【实验】：

| 源写法 | `Code_Note.text` | `note_flags` |
| --- | --- | --- |
| `} @test` | `'test'` | 0 |
| `} @test(custom_name)` | `'test(custom_name)'` | 0 |
| `flagged_const :: 42; @test_const` | `'test_const'` | 0 |

### 1.2 AST 面（`modules/Compiler/Compiler.jai`）

- `Code_Note :: struct { #as using base: Code_Node; text: string; note_flags: u32; }`（`:964-969`）【源码】。
- `notes: [] *Code_Note` 字段存在于五个声明类型：`Code_Compound_Declaration`（`:670`）、`Code_Declaration`（`:708`）、`Code_Enum`（`:794`）、`Code_Struct`（`:925`）、`Code_Procedure_Header`（`:1098`）【源码】。
- **`note_flags` 无预定义位**：全发行版 grep `NOTE_` 仅命中无关的 macos/kevent 常量与字段本身；实验全部为 0——保留位，beta 内无语义【源码+实验】。
- `compiler_report_errors_for_untyped_declarations_with_these_notes :: (w: Workspace, labels: .. string) #compiler`（`:1536`）：全发行版**零用法**（grep 仅声明行）；语义从命名推断 = 强制"带这些注记但未定型的声明"报错——可作 `@test` 过程签名/类型化的强制手段【推断，未验证】。
- 另一反射面（type_info，非 AST）：`modules/Objective_C/module.jai:317-323` 消费 `Type_Info_Member.notes` 解析 `"selector(...)"` 文本——成员注记走 `#type_info` 反射；与本文的 metaprogram AST 面是两个独立通道（该处整体被 `@FixMe` 注释块包裹，属半成品）【源码】。

### 1.3 消息面（枚举入口）

- `Message_Typechecked`（`:327-366`）：`declarations: [] Typechecked(Code_Declaration)`（`:351`）——"we don't send them all in these messages, just the ones that occur at toplevel"（`:337-339`）；`procedure_headers`/`procedure_bodies`/`structs` "will hold values for these different things, even if they are not defined at toplevel"（`:341-344`）；`all` = 各数组按列出序拼接（`:361-363`）；`Typechecked(T) :: struct { expression: *T; subexpressions: [] *Code_Node; }`（`:369-372`）——访问声明经 `.expression`【源码】。
- 文件来源：`Code_Node.Location.enclosing_load: *Message_File`（`:545-560`）+ `Message_File.fully_pathed_filename: string`（`:253-260`）——**每个节点可定位到源文件**，依赖隔离的编译器级依据【源码】。
- 枚举序：官方明示不保证。how_to/460 原文【官方文档】："Let's sort the entity_type_names alphabetically, which is nice, but also gives us a reproducible build order, since our metaprogram may see these entities in any order"（`how_to/460_code_browsing_and_generation/first.jai:119-123`）——**排序是官方指导的确定性手段**。
- 多批次消息：一个编译发出多条 `.TYPECHECKED`（每模块批次一条，实验实录见下）；官方注入时点 = `.PHASE` 且 `phase == .TYPECHECKED_ALL_WE_CAN`（`first.jai:68-75` 的 `generate_code` 触发模式）【源码】。

### 1.4 端到端实验（`otter-note-research/`）

观察 metaprogram（`build.jai`）编译目标程序（`target.jai` `#load "loaded.jai"`，含 `@test`/`@test(custom_name)` 过程、无注记过程、带注记常量），消息循环打印声明名与注记。目标程序批次实录原文（节选）【实验】：

```
proc_header 'loaded_test' notes=1
proc_header 'test_a' notes=1
proc_header 'test_b' notes=1
proc_header 'not_a_test' notes=0
proc_header 'main' notes=0
decl 'main' raw_flags=1048577 is_constant=true notes=0
decl 'not_a_test' raw_flags=1048577 is_constant=true notes=0
decl 'test_b' raw_flags=1048577 is_constant=true notes=1
decl 'test_a' raw_flags=1048577 is_constant=true notes=1
decl 'loaded_test' raw_flags=1048577 is_constant=true notes=1
```

结论【实验】：
1. **`@test` 过程在两个数组都可见**：`procedure_headers`（注记在 `Code_Procedure_Header.notes`）与 `declarations`（过程名是 `IS_CONSTANT` 声明）——推荐以 `procedure_headers` 为发现面（`name` 字段直取，`:1055`）。
2. **`#load` 文件的声明入消息循环**（`loaded_test` 在列），且本运行中 header 序 = 文本包含后的源序（loaded_test 最前）；`declarations` 序恰为逆序——单次运行的序观察，**设计不得依赖消息序**（§1.3 官方指导）。
3. 编译器自身也使用注记（模块批次出现 `PrintLike`/`NoProfile` 注记文本）——**过滤必须精确匹配 `"test"` 或前缀 `"test("`**，子串匹配会误收。
4. 多批次消息：全部 import 模块（Basic/Compiler/Windows…）各发一批；发现逻辑必须累积全部 `.TYPECHECKED` 直至 `TYPECHECKED_ALL_WE_CAN`。

---

## 2. `@test` 约定现状与 juice 的落实

- 发行版现状（沿用前研究，`juice/docs/research/test-collection-mechanisms.md` 91-108【源码】）：8 处 `} @test`（Basic/tests.jai、Math/tests.jai、RadixSort.jai、String/module.jai），编译器零消费方，官方注释 "Once we formalize someplace for tests to go..."（Math/tests.jai:1-9）——**官方框架未 formalize，`@test` 是进行中的约定**。
- **juice EXPAND 已落实产物注 `@test`**（一手核验）【源码】：`juice/src/transpile_plugin.jai:316` `array_add(scan.edits, .{start = close.end, end = close.end, text = " @test"});`——test 块闭括号后插注记；文件头注释 `transpile.jai:13`（"the '@test' tag"）、`:467`（"the '@test' insertion is recorded when the anchor is seen"）、`transpile_plugin.jai:184,238`（"the header rewrite + the @test tag + the Test_Entry manifest"）。即：**juice 生成的 `juice_test_N` 过程今天已经带 `@test` 注记**（装饰性，juice 的 runner 用 manifest 不用注记）。
- 推论：转译产物在 note 语义上与"手写 `@test` 过程"**同形**——otter 若以 note 为单一发现源，test 块与手写过程自动统一，无需双源【推断】。

---

## 3. otter test 内置命令端到端设计（【推断】，逐点锚证据）

### 3.1 命令面与阶段序

`TEST_COMMAND` 进静态注册表（registry = build/clean/test 三内置，§4）；参数校验 `≤1 pattern` 沿用 juice（`test.jai:24-26`）。阶段序沿用 juice t 系列（`test.jai:105-321`），**唯一结构性变更 = 运行清单来源**：

| # | 阶段 | 变更 |
| --- | --- | --- |
| t1 文件发现 | 扫描（scan_walk + juice 排除集，`test.jai:544-559`） | 不变——回答"哪些文件进测试编译" |
| t2 jaix 前置/路由 | 不变 |
| t3 EXPAND 转译 + 编号 | 不变（内置 test 块转译插件——juice 转译管线随 otter 继承） |
| t4-t9 短路/视图/Testing 模块特例 | 不变 |
| t10 driver + metaprogram 生成 | **变更**：driver 的 run 调用表不再由 transpile manifest 生成，改由 metaprogram 注入（下） |
| t11-t12 依赖剥离 + 编译执行 | 不变（编译期 `#run` 执行 + jai 退出码 = 结果，`compile_test_program` 语义） |

### 3.2 发现 = metaprogram note 枚举（单编译完成）

- 生成的 metaprogram（juice `first.jai` 形状的 otter 版）内置 otter 的收集模块：消息循环累积全部 `.TYPECHECKED`，在 `.PHASE == .TYPECHECKED_ALL_WE_CAN`（`first.jai:68-75` 官方时点）一次性处理：遍历 `procedure_headers`，收集 `notes` 含精确 `"test"` 或前缀 `"test("` 且 `name != ""` 者（§1.4 第 3 点的精确过滤）。
- **注入而非预生成**：收集后 `add_build_string` 注入 `#run { run("name", proc); ...; if finish() != 0 assert(false); }` 调用表（juice driver 的 run-list 形状 `test.jai:502-517`，注入通道 = how_to/460 `generate_code`+`add_build_string` 与 how_to/470 `#run` 注入的官方模式）。单编译完成，不需要"先探针编译枚举、再生成 driver、再编译"的两编译方案【推断：两编译方案费时且无先例，注入模式是官方教学形态】。
- **排序确定性**：按名字典序（§1.3 官方指导）；`juice_test_N` 前缀按数值 N 比较（裸字典序会把 test_10 排在 test_2 前——数值感知比较，【推断】需 spec 定）。
- **依赖隔离**：过滤 `enclosing_load.fully_pathed_filename`（§1.3）∈ 包视图文件集（+ Testing 模块编译视图白名单）——juice "Dependency tests are neither discovered nor executed"（`test.jai:315-318`）的编译器级等价物；依赖闭包声明经 shim/剥离视图进入消息流但被文件来源过滤剔除。注意 `add_build_string` 注入代码的 `enclosing_load` 语义（`Message_File:257` 注释 "null if this file is added as a string"）——注入的 run 代码自身不参与发现，无冲突【源码+推断】。
- **测试名去重/零测试/pattern**：收集期按名查重（duplicate 诊断，dispatcher validate 式）；零收集短路 "No tests found"（juice t4 语义）；pattern 过滤在收集后（juice t3 语义）。
- **失败汇总**：`run`/`finish` 汇总退出码沿用 Testing 模块契约（`modules/Testing.jai:95-115`，前研究 citation）——语义不变：编译期执行、失败继续、非零退出。
- **path_mapping**：metaprogram 由 otter 生成，文件清单与视图路径是生成时已知数据——path_mapping 表随 metaprogram 内容嵌入（juice driver 注入段的移动，`test.jai:496-519` 形状不变）。

### 3.3 与转译插件的关系（迁移路径）

- test 块 → 内置转译插件 EXPAND 生成 `juice_test_N` + `@test`（§2）→ note 枚举发现。手写 `@test` 过程不经转译、直接被发现。**同一发现源覆盖两条来源**，Test_Entry manifest 降级为转译簿记（行号保真、path_mapping），不再承载运行清单【推断】。
- 注记在视图中幸存：视图 = 逐行保真的文本变换（ADR 0005「1 行换 1 行 + 逐字区」），`} @test` 行非编辑点即原样保留——手写 `@test` 过程的视图与原文注记一致【源码：transpile_plugin.jai:425-438 行号保真门】。

---

## 4. 插件覆盖面

### 4.1 覆盖机制：at 钩子五面（lifecycle 研究 §4 的落点）

| 挂载点 | 替换契约 | 说明 |
| --- | --- | --- |
| at_DISCOVER | (消息流) -> 测试清单 | 默认 = §3.2 note 枚举；替换 = 自定义收集（如按命名约定） |
| at_TRANSPILE | 既有 Transpile_Plugin 管线 | juice-compat test 块插件 = 内置插件之一，无需新机制 |
| at_RUNNER_GEN | (测试清单) -> 注入代码 | 默认 = run-list 注入器；id+version 身份 |
| at_COMPILE | 既有 compile seam（`test.jai:110` 形状） | spawn 替换 |
| at_EXECUTE | 编译期执行语义 | 观察/改写失败汇总（极少用） |

**整命令替换不必要**：命令注册表保持静态三命令（§4.2），at 钩子已覆盖全部行为面；"test 为插件贡献 Command 值"的旧设想（`otter-refactor-research.md` §3.4）废弃——delta 见 §5.3。

### 4.2 缓存键影响

- 视图缓存键：已含管线描述（`test.jai:80` 传 `ctx.plugins` 进键）——at_TRANSPILE 面已覆盖。
- **runner 生成器不进键**：driver/metaprogram 是会话产物（"regenerated and written on every run, never cached"，`test.jai:289-291`）——注入内容每跑重生，无缓存对象可污染；若未来测试编译产物引入缓存，则 runner 生成器 id+version 进键（lifecycle 研究 §5.2 的同一规则）。

### 4.3 典型覆盖用例

- **juice-compat**：test 块转译插件内置即可（juice 转译管线随 otter 继承），存量 juice 测试套件零改写（§5.2）。
- **lint**：测试编译的 `.TYPECHECKED` 消息流是**类型感知检查的现实挂点**——生成 metaprogram 经 `init_plugins`（`Metaprogram_Plugins.jai:41` 逐名 codegen）加载 lint 插件模块（`-plug` 形态，`transpile-plugin-architecture.md` exp3 已验证端到端），lint 在消息循环观察声明/子表达式并产诊断。弥补 lint 零先例的缺口：lint = 观察类 metaprogram 插件挂在测试编译的消息面上，不产编辑、只产诊断（`compiler_report` 三汇，`Compiler.jai:1514-1521`）【推断】。

---

## 5. bootstrap 影响与结论 delta

### 5.1 关键事实（已证）

juice EXPAND 产物带 `@test`（§2，`transpile_plugin.jai:316` 一手核验）——bootstrap 路径的枢纽事实成立。

### 5.2 bootstrap 路径（推荐）

| 阶段 | otter 测试形态 | 机制 |
| --- | --- | --- |
| 0-2（juice build/test otter） | **juice test 块** | juice 只发现 test 块；手写 `@test` 过程对 juice 不可见——bootstrap 期测试全部写 test 块（`@test` 注记此时仅装饰） |
| 3（otter 自构建自测） | 存量 test 块 + 新增手写 `@test` 过程 | otter test 内置命令：转译插件照旧生成 `juice_test_N` + `@test` → note 发现统一覆盖——**存量套件零重写**；手写 `@test` 过程开始可用 |

依据：juice EXPAND 已注 `@test`（§2）+ note 发现对"转译生成"与"手写"同形（§3.3）【推断，锚 §2 源码】。

### 5.3 与前文结论的 delta

1. **`otter-refactor-research.md` §3.4 修正**：test 不再"作为插件贡献 Command 值"——落定 test 内置；第三方插件位缩减为 transpile/lint + lifecycle at 钩子覆盖。
2. **`plugin-auto-discovery.md` 衔接**：内置件集合从 build/clean 扩为 build/clean/test（静态注册表 + 显式 `#load` 列表，同一两级结论）；第三方插件仍走扫描 + 生成注册文件；测试发现（note 枚举）**不**走"生成显式有序注册文件"路线——发现内嵌于 otter 生成的测试 metaprogram（它是构建期生成的、随每跑重生，身份固定无需注册文件）【推断：与 lifecycle 研究 §5.4 的区分——命令/钩子注册是 otter 进程自身的，note 发现是子进程编译会话内的，机制不同】。
3. **`test-collection-mechanisms.md` 的推荐延续**：其"转译产物带 `@test` 与官方未来对齐"（结论 2）在 otter 升格为**发现机制本身**——官方 framework 落地时 otter 的 note 发现天然兼容【推断】。

---

## 风险与未决

1. **枚举完备性 spike**：多消息累积到 `TYPECHECKED_ALL_WE_CAN` 后是否无遗漏（本实验单文件已验证；多文件/多模块/视图编译的大样本完备性未验）——需 spike。
2. **note 文本格式无文档化承诺**：`'test'`/`'test(custom_name)'` 是本 beta 实验事实；参数化注记的文本拼接格式跨版本风险——过滤面建议同时接受 `"test"` 精确与 `"test("` 前缀，并记录 beta 绑定。
3. **`compiler_report_errors_for_untyped_declarations_with_these_notes`**（`Compiler.jai:1536`）零用法、语义未验证——若用于强制 `@test` 过程签名/类型化，先 spike。
4. **`PrintLike`/`NoProfile` 编译器内注记**证明注记命名空间被编译器使用——`@test` 被官方框架未来消费的风险已在前研究评估（对齐是零成本）；精确过滤防误收。
5. **注入代码的 `enclosing_load` 语义**（`Message_File:257`）：`add_build_string` 文件的来源标注与文件过滤的交互需 spike（注入 run 代码不得被当作依赖声明误收）。
6. **数值感知排序**（`juice_test_2` vs `juice_test_10`）需 spec 定死（建议：前缀剥离 + 数值比较 + 名字余部字典序）。

---

## 引用清单

实验（本机，`C:/Users/maojiaxing/AppData/Local/Temp/otter-note-research/`）：

- `build.jai`（观察 metaprogram：workspace + intercept + 消息循环打印 `declarations`/`procedure_headers` 的名字、IS_CONSTANT 位、notes 文本与 flags）
- `target.jai`（`@test`/`@test(custom_name)`/无注记过程/带注记常量 + `#load "loaded.jai"` + main）
- `loaded.jai`（`#load` 文件的 `@test` 过程）
- 实录输出：§1.4 节选原文；注记文本表 §1.1；`@test("custom name")` 字符串参数报错原文 §1.1

Jai 发行版（`C:/Users/maojiaxing/DevTools/jai`，beta 0.2.009）：

- `modules/Compiler/Compiler.jai`：`Message_File` 253-260；`Message_Typechecked` 327-366（toplevel 限定 337-339、非顶层覆盖 341-344、all 拼接 361-363）；`Typechecked(T)` 369-372；`Code_Node.Kind` 456-481；`Code_Node.Location.enclosing_load` 545-560；`Code_Scope_Entry.name` 658-662；`Code_Compound_Declaration.notes` 670；`Code_Declaration`（IS_CONSTANT 683、notes 708）674-711；`Code_Enum.notes` 794；`Code_Struct.notes` 925；`Code_Note` 964-969；`Code_Procedure_Header`（name 1055、notes 1098）1045-1099；`Report`/`compiler_report` 1514-1532；`compiler_report_errors_for_untyped_declarations_with_these_notes` 1536（全发行版零用法，grep 佐证）；`make_location` 1806-1813
- `how_to/460_code_browsing_and_generation/first.jai`：@command 注记先例 15-18；排序指导原文 119-123；TYPECHECKED_ALL_WE_CAN 注入时点 68-75；workspace/intercept/add_build_string 流程 26-55
- `how_to/460_code_browsing_and_generation/target.jai` + `other_entities.jai`（#load 文件声明被 metaprogram 发现的官方示例）
- `how_to/470_running_hooks_in_the_target_workspace`（#run 注入官方模式，前研究 citation 93-128）
- `modules/Metaprogram_Plugins.jai:22-77`（init_plugins 逐名 codegen，模板 :41——lint 插件加载通道）
- `modules/Input/macos.jai:569+`、`modules/Objective_C/module.jai:23,256,317-323`、`modules/Gamepad/Gamepad.jai:501,513`（`@selector(...)` 参数化注记实例与 type_info 面消费）
- 全发行版 grep：`NOTE_` 仅 kqueue 无关常量（note_flags 无预定义位）；`@command` 仅 460 注释（零消费方）

本仓库：

- `juice/src/transpile_plugin.jai:316`（EXPAND 产物注 `@test` 一手核验）；`:184,238`（注释）；`:425-438`（行号保真门——注记在视图幸存依据）
- `juice/src/transpile.jai:13,467`（`@test` 插入注释）
- `juice/src/commands/test.jai`：参数校验 24-26；阶段序 105-321；依赖测试不执行 315-318；driver 会话产物 289-291；driver run-list 形状 502-517；发现扫描 544-559；视图键含管线 80
- `juice/modules/Testing.jai:95-115`（run/finish 汇总退出码，前研究 citation）
- `juice/docs/research/test-collection-mechanisms.md` 91-108（`@test` 发行版现状 + 官方注释原文 + "转译产物带 @test" 推荐）
- `otter/docs/research/plugin-auto-discovery.md`（两级注册结论、E1/E2 无运行期顶层执行）
- `otter/docs/research/plugin-lifecycle-hooks.md`（§4 at 钩子面、§5.2 缓存键规则、§5.4 注册文件衔接）
- `otter/docs/research/otter-refactor-research.md` §3.4（test-as-plugin 旧设想——本文 §5.3 修正）
- `juice/docs/research/transpile-plugin-architecture.md`（exp3 `-plug` 端到端验证、段二管线）
