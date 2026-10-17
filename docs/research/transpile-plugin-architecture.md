# 转译机制插件化研究——从 test block 转译到可插拔转换管线

> 研究问题：`juice test` 的 test block 转译机制（识别/剥离 → 重写/生成 → 缓存/行号映射）能否插件化——泛化为可插拔的转换管线，作为「类似 Babel 插件」的 Jai 语法扩展转译器（[syntax-transpiler.md](syntax-transpiler.md) 的调研对象）的基础设施？
> 全部结论来自一手来源：本仓库源码（2026-10-14 工作树；`.claude/worktrees/` 下的副本一律忽略）、本仓库 ADR/规范/既有研究笔记；Jai 发行版 `C:/Users/maojiaxing/DevTools/jai`（beta 0.2.009，2025-02-06，见文末"发行版版本"）的 modules/how_to 源码与本机编译运行实验。Babel 要点沿用 syntax-transpiler.md 对官方 Plugin Handbook 的核验，不重复下载。
> 每条论断标注来源类型：【源码】= 读发行版/本仓库源码确认；【实验】= 本机编译运行验证；【官方文档】= 官方文档/官方注释原文；【推断】= 基于事实的推理，非直接证据。
> 实验在 `C:/Users/maojiaxing/AppData/Local/Temp/jai-plugin-research/`（exp1/exp2/exp3），未修改仓库产品代码。

## 结论摘要

1. **当前转译机制已经是「半插件化」的**：通用 source-to-source 基础设施（lexer、Edit 编辑机制、行号保真 helper、字符串工具、内容寻址缓存、闭包探测/视图落盘、seam 形参注入）与 test block 专用逻辑（锚点识别、`juice_test_N` 重写、`@test` 注记、Test_Entry 清单）虽然同处 `transpile_source` 一个函数内，但分层边界清晰、可无损拆分【源码】。
2. **三段分工**：识别/探测 = `source_has_test_block`/`source_load_targets`（`src/transpile.jai:422-470`）+ `probe_package_closure`/`closure_has_tests`（`src/transpile_front.jai:83-132`）；重写/生成 = `transpile_source` 单遍扫描（`src/transpile.jai:617-756`）产出 Edit 列表 → `apply_edits`（`:527-539`）；缓存 = `transpile_view_key` 纯函数（`src/transpile_cache.jai:48-66`）+ `view_of_file` 落盘（`src/transpile_front.jai:192-256`）。**行号映射不是映射表**——ADR 0005 以「1 行换 1 行」编辑形状把行号保真烧进产物（`strip_block_edit`/`load_strip_edit`，`transpile.jai:541-580`），唯一的映射是 driver 注入的「视图绝对路径 → 原包相对路径」路径改写表（`src/commands/test.jai:436-459` + `modules/Testing.jai:45-50`）【源码】。
3. **已有三个 plugin 形状的 seam**：`Strip_View_State.transpile`（`transpile_front.jai:171`）、`build_prepared_workspace` 的 `transpile` 参数（`src/commands/build.jai:186`）、`test_prepared_workspace` 的 `transpile` 参数（`src/commands/test.jai:100`）——转译步骤今天就是形参注入可替换的（集成测试用录制假实现跨同一接口，`test.jai:638-746`）。插件化 = 把「单步可替换」泛化为「有序多步管线可注册」【源码】。
4. **最小改造**：扫描循环抽成管线 runner；test block 转换与 `#load` 处理成为前两个内置插件；探测函数（probe）改为管线聚合；缓存键并入管线描述（插件 id + 版本，泛化 `JUICE_VERSION` 的语义，`transpile_cache.jai:16-19`）；视图落盘、driver/metaprogram 生成、golden/negative 测试矩阵全部原样复用。唯一硬约束：每个插件必须遵守 ADR 0005 的「1 行换 1 行、编辑以 token 为界」契约【推断】。
5. **Jai 编译器有原生 metaprogram 插件系统，且是现实可用的**（syntax-transpiler.md 未发现）：`-plug` CLI flag + `Metaprogram_Plugin` 结构（生命周期钩子 before_intercept/add_source/message/finish/shutdown，`modules/Compiler/Compiler.jai:213-228`）+ `init_plugins` 按名 `#import` 插件模块（`modules/Metaprogram_Plugins.jai:22-77`）；官方 profiler Iprof 用它做 AST 级过程改写（`modules/Iprof/instrument.jai:235-260`，`compiler_modify_procedure` 重提交）。本报告 exp3 端到端验证：`init_plugins(string.["Example_Plugin"])` 注册、插件收到 126 条消息、finish/shutdown 触发、目标程序编译运行【源码+实验】。
6. **但原生插件系统承载不了语法扩展**：exp1 验证 `test "hello" { }` 是解析错误（"Semicolon expected after expression"，`exp1_test_block_syntax.jai:4`）——编译器在解析阶段就拒绝，任何 metaprogram 钩子都看不到它。juice 的文本层转译（视图前置）是语法扩展**唯一可行宿主**；原生插件系统可承载「视图之后」的类型感知 AST 变换（instrumentation、代码生成、自定义检查——how_to/460/470/480 的官方模式）。由此得出**两段式管线**：段一 = juice 进程内文本层管线（语法扩展 + 行号保真），段二 = jai 原生 `-plug` 插件（合法 Jai 的 AST 变换，有完整类型信息）【源码+实验+推断】。
7. **对 syntax-transpiler.md 的修正**：(a) 「Jai 无 parser 库、需手写 lexer」部分过时——发行版自带编译器同款词法器 `modules/Jai_Lexer` 且可独立 `#import` 使用（exp2 编译运行通过），但它是内部地位模块（无稳定性承诺），juice 手写 lexer 因 bootstrap `#load` 自足性与版本稳定仍合理【源码+实验】；(b) 「架构 B（Jai-native）作为后续」现在就是 shipped 机制（第 5 点）；(c) 其未决问题 3（`Program_Print` 是否保留注释与排版）已核验：不保留（`modules/Program_Print/module.jai:1159` "`@Incomplete: notes`"，注释不随 AST 携带）——AST 往返（`compiler_get_nodes`/`compiler_get_code`）保语义不保文本，**行号保真只能靠文本层**【源码】；(d) Babel 借鉴点的 Jai 侧等价物：visitor → 锚点级扫描钩子；`generateUidIdentifier` → `juice_test_N` 编号 + 前缀保留；`retainLines` → ADR 0005（比 retainLines 更强硬）；path/scope 无等价物也不需要（文本层不做整树变换）【推断】。
8. **明确不可行/推迟项**：(a) 用 jai 原生插件系统直接承载 test block/语法扩展——不可行（exp1）；(b) 第三方插件模块进 bootstrap `build.jai` 的 `#load` 闭包——不可行（闭包成员必须 test-free，`tests/transpile_tests.jai:5-15` 的同一约束；第三方插件只能运行时加载或独立进程）；(c) AST 往返替代文本层编辑——不可行（行号保真，第 7c 点）；(d) 动态库插件（Jai 类型跨 DLL 边界需 `#c_call` 字符串 ABI，[dynamic-libraries.md](dynamic-libraries.md) 已有两次调用约定崩溃反例）——可行但摩擦大，推迟【源码+实验】。

## 第一部分：当前转译机制的分层与数据流

### 1.1 三条消费路径与总览

转译机制被三条路径共用，是理解插件化约束的起点【源码】：

| 路径 | 探测 | 转译模式 | 视图落盘 | 缓存 |
|---|---|---|---|---|
| Build command | 入口闭包探测（ADR 0004 决定 1） | STRIP | `target/transpile/<hash>/<rel>` | 内容寻址 + 命中跳过 |
| Test command | 无探测（全包发现，逐文件转译） | EXPAND | `target/transpile/<hash>/<rel>` | 内容寻址 + 命中跳过 |
| Bootstrap build.jai | 入口闭包探测 | STRIP | `target/transpile/bootstrap/<rel>` | 无缓存（PLAIN 恒写） |
| 依赖剥离前端（Build/Test 共用） | 按 shim 探测依赖入口闭包 | STRIP | `target/transpile/deps/<名>/<hash>/<rel>` | 内容寻址 + 命中跳过 |

Build 编排：`build_prepared_workspace`（`src/commands/build.jai:184-213`）→ 依赖剥离前端 `prepare_dependency_strip_views`（`src/dependency.jai:240-282`）→ 逐 plan `build_plan_entry`（`src/commands/build.jai:153-175`）→ `view_of_file` → `compile_artifact_plan`（`:62-110`，生成 metaprogram 后调 jai）。Test 编排：`test_prepared_workspace`（`src/commands/test.jai:96-261`）：逐文件 EXPAND 转译 + 全局编号 → pattern 过滤 → 内容寻址落盘 → Testing 模块特例 → driver/first.jai 生成 → 依赖剥离 → 编译。Bootstrap：`bootstrap_build_entry`（`build.jai:38-61`）复用同一 `Strip_View_State`，仅换 PLAIN 布局与 transpile_dir。两条布局是「一个真实 seam 的两个适配器」（`src/transpile_front.jai:146-160`）。

### 1.2 识别/探测段（front）

- `lex_source`（`src/transpile.jai:102-250`）：全文件词法器，产带 span 的 Token 流。Token 契约（`:74-81`）：`start/end` 字节偏移（含/不含）、`line/column/end_line` 1 基行列（多行字符串带 `end_line`）。Trivia（空白、行注释、嵌套块注释）被消费、只反映在 token 间隙——这是「逐字区」行内容保真的词法基础。
- `source_has_test_block`（`:416-445`）：闭包探测的判定（ADR 0004 决定 1 的「是否需要视图」）。扫描 token 流、维护花括号深度与语句位置，识别「语句位置的文件顶层 test 锚点」；非语句位置的 `test` token（如 `if test {`）免疫（`:419-420` 注释）。
- `source_load_targets`（`:447-470`）：提取字面量 in-package `#load` 边（闭包 DFS 的边来源）；非字面量与 out-of-package 目标缺席（`:449-451` 注释）。
- `probe_package_closure`（`src/transpile_front.jai:83-122`）：从入口出发沿 load 边 DFS，产 `Build_Closure_File` 列表（DFS 前序）。
- `closure_has_tests`（`:124-132`）：全有全无决策（ADR 0004 决定 2）——任一文件含 test，整闭包视图化。

### 1.3 重写/生成段

- `transpile_source`（`src/transpile.jai:617-756`）：**单入口纯函数**（"No IO, no global state"，`:1-3`）。单遍从左到右扫描 token 流，维护花括号深度（`:741-748`）与「前一 token 文本」（语句位置判定 `is_statement_position`，`:598-601`）。两个编辑家族：
  - `#load` 语句（`:636-666`）：EXPAND 模式 → `load_strip_edit` 等行数注释占位（`:566-580`）；STRIP 模式 → 目标字符串 token 改写为视图路径（经 `ctx.load_targets` 查表，`:653-658`）。
  - test 锚点（`:668-739`）：EXPAND → 头行替换 `juice_test_N :: () -> () {`（`:727`）+ 闭括号后插 `@test`（`:728`）+ Test_Entry 入清单（`:717-726`）；STRIP → `strip_block_edit` 等行数注释占位（`:545-560`）。
- 编辑机制（通用）：`Edit {start,end,text}`（`:476-480`）、`sort_edits`（`:514-525`，编辑乱序记录、按起点排序后应用）、`apply_edits`（`:527-539`，区间不相交由构造保证）。`normalize_view_line_endings`（`:484-508`，CRLF→LF，无 `\r` 时原样返回保证 test-free 文件逐字节往返）。
- 上下文契约：`Transpile_Context`（`:30-41`）——mode、包相对路径（匿名测试命名与 `#load` 解析基准）、`next_test_number`（文件内编号起点，跨文件续号由调用方负责，`:35-37`）、`load_targets` 重写表。输出契约：`Transpile_Result`（`:56-60`）= view 文本 + Test_Entry 清单 + 诊断。

### 1.4 缓存/行号映射段

- `transpile_view_key`（`src/transpile_cache.jai:48-66`）：纯函数键 = hash（包相对路径 + 源内容 + 模式 + juice 版本 + load 重写表），FNV-1a 64 位 16 十六进制（`:31-42`）。STRIP 模式的重写表嵌入目标视图的 hash 目录，父键依赖子键——**Merkle 链**，按依赖序确定性可算（`:1-10` 注释；契约由 `tests/transpile_tests.jai:323-341` 锁定）。
- 落点：`transpile_view_path`（`:73-78`，hash 目录内镜像包相对结构防撞名）、`transpile_dependency_view_path`（`:80-87`）、`transpile_tree_dir`（`:89-96`）。
- `view_of_file`（`src/transpile_front.jai:192-256`）：依赖序（子先父后，Merkle 链成立前提）、循环检测（`:195-199`）、诊断拒绝（`:222-228`）、CONTENT_ADDRESSED 命中跳过写 vs PLAIN 恒写（`:245-251`）。
- 行号映射：**没有位置映射表**。ADR 0005 决定 1 把「视图行数 = 原文件行数」立为硬约束，编辑全部以「1 行换 1 行」为单位展开（`transpile.jai:541-580` 的两个占位 builder 逐行复制前导空白），无法等行数展开的输入形态转译期拒绝（多行 test 头，`tests/transpile_tests.jai:193-200`）。唯一的映射是路径级：driver 注入 `path_mapping`（`src/commands/test.jai:444-453`），Testing 打印失败位置时按精确匹配把视图绝对路径改写回包相对路径（`modules/Testing.jai:26-33,45-50`）。

### 1.5 输入输出契约（代码证据汇总）

| 函数 | 输入 | 输出 | 证据 |
|---|---|---|---|
| `lex_source` | 源文本 | Token 流（span 契约） | `transpile.jai:74-81,102` |
| `transpile_source` | 源文本 + `Transpile_Context` | `Transpile_Result`（view/tests/diagnostics） | `transpile.jai:30-60,617` |
| `transpile_build_file` | `Build_Source_File` + `[]Load_Target` | `Build_File_Output`（view/key/diagnostics） | `transpile_front.jai:61-65,265-281` |
| `transpile_test_file` | `Test_Source_File` + 起始编号 | `Test_File_Output`（view/key/tests/diagnostics） | `test.jai:51-78` |
| `transpile_view_key` | 路径+源+模式+版本+重写表 | 16 hex 键 | `transpile_cache.jai:48-66` |
| `view_of_file` | `Strip_View_State` | 视图绝对路径 | `transpile_front.jai:192-256` |

测试揭示的机制契约【源码】：`tests/transpile_tests.jai` 锁定逐字节输出形态（`:29-99` 展开形态、`:118-167` 剥离形态、`:175-231` 诊断文本、`:233-246` 行号保真、`:248-251` CRLF 规范化）、缓存键成分敏感性与 Merkle 链（`:304-341`）、路径防撞名（`:347-356`）；golden/negative harness 与编译运行矩阵（`:365-434`，fixture 在 `tests/data/transpile/golden|negative|run/`，期望文件逐字节对比、`JUICE_UPDATE_GOLDEN` 重写，见 `docs/transpiled-output-formatting.md` §4-5）；`tests/transpile_front_tests.jai` 锁定 PLAIN 布局语义与生产剥离步骤（`:29-133`）；`tests/metaprogram_tests.jai` 逐字节锁定生成器输出（`:26-36`）。

## 第二部分：test block 专用 vs 通用 source-to-source 部件的边界

| 部件 | 归属 | 位置 |
|---|---|---|
| lexer（span、trivia 消费、嵌套注释、多行字符串） | 通用 | `transpile.jai:102-250` |
| Edit/排序/应用（区间不相交编辑） | 通用 | `transpile.jai:476-539` |
| 行号保真 helper（行尾规范化、行起止、行内容尾、前导空白） | 通用（ADR 0005 全局契约的执行层） | `transpile.jai:256-275,484-508` |
| Jai 字符串 decode/escape/quote | 通用 | `transpile.jai:294-352` |
| `#load` 目标解析（in-package 判定、`..` 边界） | 通用 | `transpile.jai:358-410` |
| 内容寻址键与路径函数 | 通用 | `transpile_cache.jai` 全文件 |
| 闭包探测、全有全无、视图落盘、两种布局 | 通用（`transpile` 形参即插件挂点） | `transpile_front.jai:83-256` |
| 扫描循环骨架（深度 + 语句位置 + 编辑收集） | 通用（管线 runner 候选） | `transpile.jai:617-749` |
| `#load` 处理分支（两模式两行为） | 模式相关但非 test 专用 | `transpile.jai:636-666` |
| test 锚点识别（`is_test_anchor`/`is_statement_position`/`find_matching_close`） | test 专用 | `transpile.jai:582-611` |
| test block 两模式重写（占位/展开）、`juice_test_N`、`@test`、Test_Entry、编号 | test 专用 | `transpile.jai:668-739,43-48` |
| `source_has_test_block` 探测 | test 专用（但探测接口本身是通用形态） | `transpile.jai:416-445` |
| `source_load_targets` 探测 | 通用（load 边） | `transpile.jai:447-470` |

三个关键边界事实【源码】：

1. **探测与转译是同一「插件」的两处挂钩**：build 侧先问 `has_tests`（要不要视图，`transpile_front.jai:107`），再调 `transpile`（怎么改）。插件化时每个插件须成对提供探测钩子与转译钩子，探测聚合决定「闭包是否需要管线」。
2. **插件间存在交互契约**：test 锚点展开后扫描继续进入体（"Scan the body (loads inside it still need stripping)"，`transpile.jai:729-731`）——`#load` 插件在 test 插件占用的区域内部仍然生效（`tests/transpile_tests.jai:73-77`）；而 STRIP 模式下 test 体被整体占位、其内 `#load` 随之消失（`:148-154`）。管线的区域作用域与优先级不能靠「独立 pass 顺序拼接」隐式成立，需要在 runner 层显式定义。
3. **跨文件状态通道已存在**：`next_test_number` 经 `Transpile_Context` 注入、跨文件续号（`test.jai:108-124`），Testing 模块视图延续全局编号（`test.jai:163-172`）。通用插件的跨文件状态（如 lambda 转译的计数器）复用同一通道即可。

## 第三部分：插件化的最小改造

### 3.1 现状：seam 已经是形参

三个注入点今天都是过程参数【源码】：

- `Strip_View_State.transpile: #type (file: Build_Source_File, load_targets: [] Load_Target) -> Build_File_Output`（`transpile_front.jai:171`）——bootstrap 与 Build command 各自注入同一生产步骤 `transpile_build_file`（`build.jai:46`、`commands/build.jai:186`）；
- `test_prepared_workspace` 的 `transpile`/`compile`/`dep_transpile` 三个形参（`test.jai:100-102`）；
- 集成测试以录制假实现跨同一接口（`test.jai:638-746`、`commands/build.jai:224-327`、`tests/test_support.jai` 的 fake 集）。

即：**「单步转译可替换」已落地**。插件化只是把形参从「一个步骤」泛化为「一个有序步骤列表（管线）」，并把管线身份送进缓存键。

### 3.2 建议的注册表/管线抽象位置与形态

【推断】最小改造（不动视图落盘、driver/metaprogram 生成、测试矩阵）：

1. **管线 runner 抽出**：`transpile_source` 的扫描循环（`transpile.jai:617-749`）保留为 runner，两个分支（`#load`、test 锚点）改为向注册插件派发。插件接口的最小形状：
   - 身份：`name`/`version`（进缓存键）；
   - 模式适用性：声明 STRIP/EXPAND 下各提供什么行为（test 插件两模式行为完全不同，`#load` 插件两模式共享识别）；
   - 探测钩子（成对提供）：`has_anchor(source, path)`（喂 `closure_has_tests` 的聚合）、可选 `load_edges(source, path)`（喂闭包 DFS）；
   - 转译钩子：扫描位置上的「识别 → 编辑/清单条目/诊断」回调；
   - 跨文件状态经 `Transpile_Context` 扩展字段传递（现成的通道，1.3/2.3）。
2. **前两个内置插件**：test block 转换（`is_test_anchor` + `:668-739` 分支 + `source_has_test_block`）与 `#load` 处理（`:636-666` + `source_load_targets`）。二者现在的交互契约（loads inside test bodies）在 runner 层显式化为「test 插件声明区域后继续派发 load 插件」。
3. **缓存键并入管线描述**：`transpile_view_key` 增加管线描述分量（插件 id + 版本序列），泛化 `JUICE_VERSION` 的既有语义（"Bump whenever the transpiler's output contract changes"，`transpile_cache.jai:16-19`）为「管线输出契约版本」。Merkle 链性质不变（重写表照旧嵌入）。
4. **新模块落点**：`src/transpile_plugin.jai`（或并入 `transpile.jai`）。**必须 test-free**——它会被 bootstrap `build.jai` `#load`（`build.jai:21-24` 的既有 #load 集），测试驻 `tests/`（同一测试组织规则，`tests/transpile_tests.jai:1-15`）。
5. **可复用而不动的部分**：视图落盘（`view_of_file`）、driver/metaprogram 生成（`generate_test_driver`/`generate_compiler_metaprogram`）、golden/negative/编译运行测试矩阵（`docs/transpiled-output-formatting.md` §4）——它们已经只依赖「每文件一个视图文本 + 键 + 清单」的契约，与管线内部结构无关。每个新插件的 golden 用例按既有 harness 逐个添加。

### 3.3 第三方插件的宿主（三选项与约束）

【推断】juice 是被编译的独立程序，用户包不能重建它，插件宿主有且只有三条路：

- (a) **编译进 juice**：只适合仓库内置插件（bootstrap 约束见 3.2.4）；用户自定义插件不可行。
- (b) **运行时动态库**：`LoadLibraryA`/`GetProcAddress` + `#c_call` 可行（[dynamic-libraries.md](dynamic-libraries.md) 已验证底层 API 与两次调用约定崩溃反例），但 Jai 类型不能干净跨 DLL 边界——插件 ABI 必须退化为字符串协议（源文本进、视图文本+清单出），内存所有权协议需显式定义。摩擦大，推迟。
- (c) **独立进程 filter**：插件 = 独立程序（旧 syntax-transpiler.md 架构 A 的 CLI 形态回归），juice 编排层以子进程调用。进程隔离干净、无 ABI 问题、可用任意语言写，代价是每文件子进程开销与版本偏差风险（ADR 0004 Considered Option (c) 否决独立 CLI 的理由，但对「用户自定义插件」该理由弱化——内置特性走进程内管线，扩展走进程外）。
- 附：**编译期插件**（第四种，Jai 特有）：照 `Metaprogram_Plugins.jai` 的先例，由生成的编译 metaprogram 按 manifest 声明 `#import` 用户插件模块并在编译期执行——插件活在编译器进程内、有消息/AST 权限。它不属于文本层管线（管的是编译期），是下面第四部分两段式架构的段二。

### 3.4 与既有编排的兼容性

改造后三条路径的探针与 seam 全部保持现状：`probe_package_closure` 调 `source_load_targets` 与 `source_has_test_block`（`transpile_front.jai:105-108`）改为调管线聚合版本；`Strip_View_State.transpile` 形参不变（管线以单个 `#type` 值的身份被注入，或该形参泛化为管线类型）。test-free 闭包零转译（ADR 0004 决定 1）语义不变——管线探测聚合返回「无锚点」时探针直接短路。

## 第四部分：Jai 编译器元编程能力的一手核验（插件化的外部约束）

### 4.1 原生 metaprogram 插件系统（syntax-transpiler.md 未覆盖的新事实）

【源码】`modules/Compiler/Compiler.jai:213-228`：`Metaprogram_Plugin :: struct` 带生命周期钩子 `before_intercept`/`add_source`/`message`/`finish`/`shutdown`/`handle_one_option`/`log_help`；`message` 钩子收到目标 workspace 的每条 `Message`（含 `.TYPECHECKED`，`Compiler.jai:236-251`）。

【源码】`modules/Default_Metaprogram.jai:56-97`：jai CLI 原生 `-plug <模块名>` flag（两遍扫描 + 失配报错，`:339`）；`modules/Metaprogram_Plugins.jai:22-77`：`init_plugins` 以代码生成方式按名 `#import` 插件模块并调其 `get_plugin()`（`:41` `Plugin_%1 :: #import "%2"%3;`——**按名加载插件模块的官方先例**，是 juice 管线注册表可照抄的形态）。插件契约极简：模块只需定义 `get_plugin :: () -> *Metaprogram_Plugin`（`modules/Example_Plugin.jai:1-23`）。

【实验】exp3（`jai-plugin-research/exp3/build.jai`）：metaprogram 内 `init_plugins(string.["Example_Plugin"], *plugins, w)` 注册发行版自带插件，消息循环向插件转发消息。运行实录：`init_plugins registered 1 plugins`、Example_Plugin 收到 126 条消息（PHASE/TYPECHECKED）、`Finishing Example_Plugin, which saw 126 messages.`、`Shutting down Example_Plugin.`、目标程序编译运行输出 `target program runs`。**原生插件路径端到端可用。**

【源码】生产级变换先例：官方 profiler Iprof 的 instrumenter 就是 metaprogram 插件（`modules/Iprof/instrument.jai:346-349` 的 `My_Plugin` 继承 `Metaprogram_Plugin`；`:235-260`：收到过程体后，手工构造 `Code_Directive_Insert` 节点（内含要插入的源文本字符串——**「生成文本再交给编译器解析」的官方惯用法**），拼进 `body.block.statements` 头部，`compiler_modify_procedure(w, body)` 重提交）。`ALREADY_MODIFIED` flag（`Compiler.jai:1133`）佐证重提交循环是设计内语义。CHANGELOG 显示该 API 持续修 bug（`CHANGELOG.txt:2102` "still has issues in several cases"，:1067/:1254/:1931/:1941/:2010/:2858/:3506）——可用但在演进中。

### 4.2 能力边界一：语法扩展进不了原生插件

【实验】exp1（`exp1_test_block_syntax.jai`）：`test "hello" { print("hi\n"); }` 编译报错原文 `exp1_test_block_syntax.jai:4,1: Error: Semicolon expected after expression.`——`test` 被解析为标识符表达式。编译器在解析阶段拒绝，早于任何插件/消息钩子；`#expand` 宏也救不了（宏调用自身必须是合法 Jai 调用，`test "x" { }` 连调用都不是）。**结论：任何新语法（test block、lambda 定界符、try/catch）必须在编译器之前处理；juice 的文本层视图前置是唯一宿主。**

### 4.3 能力边界二：Code ↔ AST 往返（官方文档 + 源码）

【官方文档】`how_to/630_compiler_get_nodes.jai:1-16`："You can take a Code, convert it to the tree, mess around with the tree, and resubmit the changed tree." `compiler_get_nodes`（`Compiler.jai:1553`）/`compiler_get_code`（`:1554`）成对。官方破坏性修改模式（`630:100-135`）：`compiler_get_nodes` 每次给**新鲜用户级副本**，可任意破坏性修改（`:116-122` 注释原文），`compiler_get_code(root)` 转回 Code，`#insert,scope()` 插回。`compiler_modify_procedure`（`:1495`）是目标 workspace 侧的「替换已编译代码」API（4.1 Iprof 用法）。

【源码】消息流：`Message_Typechecked`（`Compiler.jai:327-366`）携带 `declarations/procedure_headers/procedure_bodies/structs/others/all` 与扁平化 `subexpressions`（含类型信息——how_to/480 的 MISRA 检查全程只用 `subexpressions` 遍历，`480_custom_checks/first.jai:240-311`）；自定义诊断经 `compiler_report`（`Compiler.jai:1521-1531`，`.ERROR_CONTINUABLE` 模式）。树遍历工具 `Code_Visit`（`get_subexpressions:16`、`get_recursive_nodes_depth_first:261`、`visit_pre_and_postorder:294`）。

【源码】保真度结论（关闭 syntax-transpiler.md 未决问题 3）：`Program_Print`（`modules/Program_Print/module.jai`）是完整 AST→源码打印器（`print_declaration:84`、`print_expression:445`），但 `:1159` 标注 "`@Incomplete: notes`"、注释不随 AST 节点携带——**重打印不保留注释与原文排版**。AST 往返（get_nodes → 改 → get_code）保语义不保文本，无法满足 ADR 0005 的逐字区行内容保真。行号保真只能由文本层编辑机制提供（juice 现状），AST 层插件与行号保真互斥——这是两段式管线分工的根本原因。

### 4.4 能力边界三：发行版自带 lexer（syntax-transpiler.md 的修正）

【源码+实验】`modules/Jai_Lexer/module.jai`：编译器同款词法器，`set_input_from_string`/`set_input_from_file`/`peek_next_token`/`eat_token`（`:1891/:1907/:207/:1391`），Token 带 `l0,c0,l1,c1` 与语义值（`:159-174`），自带 example 程序（`examples/example.jai`、`examples/lex_all_files.jai`）。exp2 编译运行通过：对 `#load "x.jai";`/`test "t" { }`/`foo :: (x: int) -> int { return x << 2; }` 正确切出 IDENT/STRING/KEYWORD_RETURN/RIGHT_ARROW/`POINTER_DEREFERENCE_OR_SHIFT_LEFT` 及带正确行列的 token。**「Jai 无 parser 库、需手写 lexer」部分过时**——官方 lexer 存在且可独立使用。

【推断】但 `Jai_Lexer` 是内部地位模块：依赖 `Pool`/`Unicode`、源码满布 `@Cleanup` 内部注记、无 API 稳定性承诺，且 juice 的 bootstrap `build.jai` 通过 `#load` 复用转译器（`build.jai:21-24`）要求其依赖自足（现 transpile.jai 仅依赖 Basic/String，`transpile.jai:12-13`）。**juice 手写 lexer 保留理由成立**（bootstrap 自足性 + 跨版本稳定 + 已有 golden 锁定），但插件作者若在 juice 外自建管线，官方 lexer 是合法选项。

### 4.5 宏路径的既有边界（沿用 syntax-transpiler.md 核验）

【官方文档】`how_to/600_insert.jai:255-273`：`#insert` 仅编译期；Code 树操作"Not quite all the features are in place for easy manipulation of the Code type, but it's coming soon"（`:270-273` 原文）；语句级 vs 表达式级插入的不同规则（`:335-368`）。`#code` 体可见调用方作用域（内联语义，syntax-transpiler.md exp8 已核验，本报告未重复实验）。

## 第五部分：与 syntax-transpiler.md 架构建议的对比

| 旧建议（2026-10 调研） | 今天的事实 | 判定 |
|---|---|---|
| 架构 A：独立 source-to-source CLI | juice 进程内管线已存在且三路径共享（ADR 0004 已裁决否决独立 CLI 于内置特性）；CLI 形态可作为「用户自定义插件的独立进程宿主」回归（3.3c） | **修正**：内建管线为主，CLI 降级为插件宿主候选 |
| 「Jai 无第三方 parser 库，lexer/parser 需手写」 | 发行版自带编译器同款 lexer（4.4，exp2）；手写 lexer 因 bootstrap/稳定性仍合理 | **部分修正** |
| 5.2 span-preserving 策略：完整 lexer + 局部 parser + trivia 保留 | 已在 juice 落地为 lexer + Edit 机制 + 逐字区（`transpile.jai:102-250,476-539` + ADR 0005） | **维持并已落地** |
| juice 集成 = 编译 seam 的可选前置步骤 | 已是编译前置义务（ADR 0004 决定 3）+ 三路径 + 依赖剥离前端 + seam 形参注入 | **升级**：可选 → 义务 |
| 架构 B（Jai-native metaprogram）作为后续路径 | 原生 `-plug` 插件系统 + `compiler_modify_procedure` + Iprof 生产先例 + 官方 AST 工具（4.1-4.3，exp3） | **修正**：不是「后续」，是 shipped 机制；但其边界（4.2）决定它只能做段二 |
| 缓存挂 `cache_dir` | 内容寻址视图缓存 + Merkle 键链 + 命中跳过（`transpile_cache.jai`） | **升级** |
| 6.3 符号卫生（generateUidIdentifier 模式） | `juice_test_` 前缀保留 + 编号（`transpile.jai:15-20,727`；撞名由 jai 重定义错误暴露，ADR 0005 Consequences） | **维持** |
| 6.3 格式保留（trivia 保留策略） | ADR 0005「1 行换 1 行 + 逐字区」+ golden 逐字节锁定 | **维持并更强** |
| 未决问题 3：`Program_Print` 保真度 | 已核验：不保留注释/排版（4.3）——AST 往返与行号保真互斥 | **关闭** |
| 8.2 测试矩阵（golden/负例/编译运行） | juice 已按同一矩阵落地（`docs/transpiled-output-formatting.md` §4，`tests/data/transpile/*`） | **维持并已落地** |

**插件化后的路径是否更优**：是。syntax-transpiler.md 建议的「独立 CLI + 手写 lexer/parser + juice 前置」在今天等价于「从零再建一套与 juice 已有基础设施平行的管线」——而 juice 的 lexer/Edit/缓存/落盘/测试矩阵已是经过三路径验证的 span-preserving 基础设施。插件化让语法扩展转译器直接复用这些部件，只新增「插件注册 + 锚点派发 + 管线键」三小块。Babel 的 parse→transform→generate 分层在 juice 侧的映射：parse = lex_source（span 保真）；transform = 插件钩子产 Edit（不建整树，锚点级）；generate = apply_edits（逐字区 + 编辑点拼接）。Babel 的 visitor/path/scope 整树机制在文本层不需要（锚点级变换无父子一致性维护负担）；需要整树与类型信息的变换归段二（jai 原生插件），其 path/scope 等价物由编译器的 `Message_Typechecked` + `Code_Visit` + `compiler_modify_procedure` 承担。

## 第六部分：不可行点与推迟项

1. **用 jai 原生插件系统承载 test block/语法扩展——不可行**。exp1：`test "hello" { }` 是解析错误，任何编译期钩子不可达。语法扩展永远需要编译器之前的文本层处理【实验】。
2. **第三方插件模块进 bootstrap `#load` 闭包——不可行**。bootstrap 消费的一切模块必须 test-free 且随仓库分发（`tests/transpile_tests.jai:5-15` 的同一约束逻辑；`build.jai:21-24` 的 #load 集）。用户自定义插件只能走 3.3 的 (b)/(c)/(d)【源码+推断】。
3. **AST 往返替代文本层编辑——不可行**。`Program_Print` 不保留注释/排版（`Program_Print/module.jai:1159`），无法满足 ADR 0005 行号保真；两者只能分工（两段式）不能互替【源码】。
4. **动态库插件——推迟**。底层可行（dynamic-libraries.md 已验证 LoadLibraryA/GetProcAddress 与产物形态），但 Jai 类型跨 DLL 边界无干净方案（该笔记两次崩溃反例），字符串 ABI + 内存所有权协议属新设计面【源码】。
5. **插件管线的硬约束——非不可行但必须立规**：每个插件遵守 ADR 0005「1 行换 1 行、编辑以 token 为界、同行其余内容属逐字区」，无法等行数展开的输入转译期拒绝（现有多行 test 头先例，`tests/transpile_tests.jai:193-200`）；插件交互（loads inside test bodies，2.2）由 runner 显式定义；管线描述进缓存键（3.2.3）。违反行号保真的插件形态（重排版、头部注记）一律拒绝【源码+推断】。
6. **`compiler_modify_procedure` 的稳定性**：官方 CHANGELOG 显示该 API 持续修 bug（`CHANGELOG.txt:2102` 原文 "still has issues in several cases"）——段二管线若依赖它，需锁定编译器版本并接受跟进成本【源码】。

## 实验记录

实验环境：Windows 11 + Git Bash；Jai 编译器 `C:/Users/maojiaxing/DevTools/jai/bin/jai.exe`（版本见下）；实验文件在 `C:/Users/maojiaxing/AppData/Local/Temp/jai-plugin-research/`。

| 实验 | 内容 | 结果 |
|---|---|---|
| exp1 | `test "hello" { ... }` 是否合法 Jai | 编译错误原文：`exp1_test_block_syntax.jai:4,1: Error: Semicolon expected after expression.`——transpiler 存在前提成立 |
| exp2 | 发行版 `Jai_Lexer` 模块独立使用 | 编译运行通过；token 流带行列（`2,1: IDENT 'test'`、`3,17: RIGHT_ARROW`、`3,35: POINTER_DEREFERENCE_OR_SHIFT_LEFT` 等），无 lexer 报错 |
| exp3 | 原生 metaprogram 插件端到端（`init_plugins` + Example_Plugin + 消息转发） | `init_plugins registered 1 plugins`；插件收到 126 条消息（PHASE/TYPECHECKED）；`Finishing Example_Plugin`/`Shutting down Example_Plugin`；目标程序编译运行输出 `target program runs` |

## 发行版版本

Jai 发行版 `C:/Users/maojiaxing/DevTools/jai`，beta 0.2.009（2025-02-06，`CHANGELOG.txt:1`；`jai -version` 无输出，惯例同 syntax-transpiler.md）。Babel Plugin Handbook 要点沿用 syntax-transpiler.md 的 2026-10-06 核验副本，本报告未重新下载。

## 引用清单

本仓库（2026-10-14 工作树，`.claude/worktrees/` 忽略）：

- `src/transpile.jai`：单入口纯函数契约 1-3；Transpile_Mode 15-20；Load_Target 22-28；Transpile_Context 30-41；Test_Entry 43-48；Transpile_Diagnostic 50-54；Transpile_Result 56-60；Token_Kind/Token 66-81；lex_source 102-250；token_text 252-254；compute_line_starts 256-263；line_content_end 266-269；first_non_whitespace 271-275；decode_jai_string 294-324；escape_jai_string 330-348；quote_jai_string 350-352；is_absolute_load_target 358-365；resolve_load_target 371-403；find_load_target 405-410；source_has_test_block 416-445；source_load_targets 447-470；Edit 476-480；normalize_view_line_endings 484-508；sort_edits 514-525；apply_edits 527-539；strip_block_edit 541-560；load_strip_edit 562-580；find_matching_close 582-596；is_statement_position 598-601；is_test_anchor 603-611；transpile_source 617-756（#load 分支 636-666、test 锚点分支 668-739、体扫描注释 729-731、深度维护 741-748）。
- `src/transpile_front.jai`：两适配器说明 14-20；front_slashes 27-38；Build_Source_File/Build_Closure_File/Build_File_Output 40-65；probe_package_closure 83-122；closure_has_tests 124-132；front_view_exists 134-144；Strip_View_Layout 146-160；Strip_View_State（transpile 形参 171）162-179；view_of_file 192-256；transpile_build_file 258-281；testing_module_strip_view_dir 283-329。
- `src/transpile_cache.jai`：JUICE_VERSION 语义 16-19；hash_hex 31-42；transpile_view_key 44-66；transpile_hash_dir 68-71；transpile_view_path 73-78；transpile_dependency_view_path 80-87；transpile_tree_dir 89-96。
- `src/commands/test.jai`：transpile_test_file 61-78；compile_test_program 80-90；test_prepared_workspace 96-261（seam 形参 100-102、编号 108-124、视图落盘 181-200、Testing 模块特例 149-172/202-227、driver+metaprogram 229-252、依赖剥离+编译 254-260）；testing_module_view 289-352；testing_module_support_block 390-417；generate_test_driver 419-459；collect_test_files 480-496；inline seam 测试 638-746；缓存 E2E 1056-1177。
- `src/commands/build.jai`：compile_artifact_plan 62-110；probe_build_closure 143-146；build_plan_entry 148-175；build_prepared_workspace（transpile 形参 186）177-213；inline 测试 224-541。
- `src/dependency.jai`：dependency_shim_content 112-114；ensure_import_shim 123-142；shim_load_target 163-180；prepare_dependency_strip_views 240-282。
- `src/metaprogram.jai`：Compiler_Metaprogram_Options 43-53；generate_compiler_metaprogram 55-114。
- `src/main.jai`：#load 顺序 6-22。
- `build.jai`：#load 集 21-24；bootstrap_build_entry 38-61；#run 63-176。
- `modules/Testing.jai`：Path_Pair/path_mapping 26-33；mapped_path 45-50；report_failure 52-56；expect/expect_eq/fail 62-90；run 95-102；finish 107-115。
- `tests/transpile_tests.jai`：test-free 约束 1-15；展开/剥离形态锁定 29-167；诊断 175-231；行号保真 233-246；CRLF 248-251；缓存键 304-341；路径防撞 347-356；golden/negative/run 矩阵 365-434。
- `tests/transpile_front_tests.jai`：生产剥离步骤 29-60；PLAIN 布局 70-133；探测 141-162；Testing 模块 STRIP 171-199。
- `tests/metaprogram_tests.jai`：生成器字节锁定 26-102。
- `docs/adr/0004-transpile-baked-into-juice.md`：决定 1-6；Considered Option (c)。
- `docs/adr/0005-view-line-fidelity.md`：决定 1-5。
- `docs/adr/0006-bootstrap-build-strips-inline-test-blocks.md`：决定 1-4。
- `docs/transpiled-output-formatting.md`：§1.1-1.4 视图排版；§2 driver；§3 first.jai；§4 golden；§5 演进流程。
- `docs/spec-src-inline-test-blocks.md`：§3 测试组织规范（test-free 模块与 tests/ 驻留）。
- `docs/research/syntax-transpiler.md`：结论摘要 4/6/7；6.1 三种架构；6.2-6.3 实现语言与关键设计点；8.1 路线；8.3 未决问题 3。
- `docs/research/jai-metaprogram-view-feeding.md`：#load 语义与 add_build_string 偏移（本报告未重复实验，沿用其 e1-e3）。
- `docs/research/dynamic-libraries.md`：无 Dynamic_Library 模块；LoadLibraryA/GetProcAddress；两次调用约定崩溃。
- `docs/research/test-collection-mechanisms.md`：`@test` 注记的官方进行中约定（本仓库 test-collection 笔记 91-108）。
- `CONTEXT.md`：Transpile 词条 76-77；Strip front 81；View 84-86；Test block 97；Driver 111；Metaprogram generator 123；全局规则 142-151。

Jai 发行版（`C:/Users/maojiaxing/DevTools/jai`，beta 0.2.009）：

- `modules/Compiler/Compiler.jai`：Metaprogram_Plugin 213-228；Message kinds 236-251；Message_Typechecked 327-366；Code_Node/Kind/node_flags/Location 456-563（CREATED_BY_DESUGARING 540）；Code_Procedure_Body.ALREADY_MODIFIED 1125-1135；compiler_create_workspace 1485；compiler_begin_intercept 1488；compiler_wait_for_message 1491；compiler_modify_procedure 1495；Report 1514-1519；compiler_report 1521-1531；compiler_get_nodes/compiler_get_code 1553-1554；add_build_file/add_build_string 1599-1601；remap_import/provide_import 1618-1627。
- `modules/Metaprogram_Plugins.jai`：用途 1-13；init_plugins 22-77（按名 #import 41）；placeholder 机制 79-87。
- `modules/Example_Plugin.jai`：get_plugin 契约 1-23；各钩子 25-99。
- `modules/Default_Metaprogram.jai`：-plug 两遍扫描 56-97、224-225、339。
- `modules/Iprof/instrument.jai`：AST 变换与 compiler_modify_procedure 220-261；插件结构 264-270、346-349。
- `modules/Jai_Lexer/module.jai`：Token_Type 17-137；Token 159-174；peek_next_token 207-218；eat_token 1391；set_input_from_string 1891；set_input_from_file 1907；examples/example.jai 11-36、examples/lex_all_files.jai 13-58。
- `modules/Code_Visit/module.jai`：get_subexpressions 16；get_recursive_nodes_depth_first 261；visit_pre_and_postorder 294。
- `modules/Program_Print/module.jai`：print_declaration 84-89；print_expression 445；@Incomplete: notes 1159。
- `how_to/630_compiler_get_nodes.jai`：往返说明 1-16；破坏性修改合法化 116-122；宏路径 100-135。
- `how_to/460_code_browsing_and_generation/first.jai`：用途 1-24；消息循环与 add_build_string 生成 56-159。
- `how_to/470_running_hooks_in_the_target_workspace/first.jai`：两种风格 1-36；SKIP_EXPRESSIONS_WITHOUT_NOTES 66；#run 注入 93-128。
- `how_to/480_custom_checks/first.jai`：subexpressions 遍历 240-311；compiler_report 430-446。
- `how_to/600_insert.jai`：#insert 仅编译期 255-257；Code 树操作未完备 270-273；语句级 vs 表达式级 335-368。
- `CHANGELOG.txt`：compiler_modify_procedure 相关 1067、1254、1931、1941、2010、2101-2102（"still has issues"）、2858、3506。

实验（本机，`C:/Users/maojiaxing/AppData/Local/Temp/jai-plugin-research/`）：exp1（test block 解析错误原文）、exp2（Jai_Lexer 独立运行 token 输出）、exp3（原生插件端到端输出原文），见"实验记录"。
