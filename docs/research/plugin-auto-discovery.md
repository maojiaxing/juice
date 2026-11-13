# otter 插件自动发现机制研究——linkme 式链接期聚合在 Jai 的可行性

> 研究问题：otter 的插件/命令自动发现能否采用 Rust `linkme` 的机制——每个源文件自我注册、链接器聚合成片、无中央注册表？若不能原样移植，等价的自动发现机制是什么？
> 日期：2026-10-19 | 环境：Jai beta 0.2.009（2025-02-06），Windows 11 + Git Bash，编译器 `C:/Users/maojiaxing/DevTools/jai/bin/jai.exe`
> 证据标注：【实验】= 本机编译运行验证 | 【源码】= 发行版/社区源码逐行阅读 | 【官方文档】= 官方文档/注释原文 | 【推断】= 基于事实的推理
> 实验目录 `C:/Users/maojiaxing/AppData/Local/Temp/otter-discovery-research/`，未修改仓库产品代码。
> linkme 事实均来自 dtolnay/linkme master 分支源码逐文件核验（2026-10-19 抓取，见引用清单），非二手转述。

## 结论摘要

| 候选路径 | 判定 | 证据 |
| --- | --- | --- |
| (a) linkme 式链接期聚合（逐声明命名段 + 链接器边界符号） | **不可行**：Jai 无逐声明命名段属性、无 `link_name` 符号绑定，`#asm` DSL 无段/数据指令；需编译器特性请求 | 【源码】 |
| (b) `#insert` 编译期反射 + 生成注册表 | **技术上可行但枚举不靠 `#insert`**：声明枚举走 metaprogram 消息循环（`Message_Typechecked` + `Code_Declaration.notes`，官方 `@command` 先例）；`#insert` 只负责拼接。比 (c) 重，留作语义级增强 | 【源码】 |
| (c) 构建工具侧扫描（otter 自己的 scan_walk 扫标记声明，生成注册表 + 调用序） | **推荐（第三方插件）**：与 juice 转译期枚举同构、扫描骨架现成、顺序确定、无运行期依赖 | 【源码】 |
| (d) 运行期顶层自注册（load 序） | **判死**：Jai 无运行期顶层执行——顶层裸调用、含调用的顶层初始化器、甚至 `#must` 编译期调用全部是编译错误（本实验）；"load 序运行期注册"不存在 | 【实验】 |

**对 otter 的推荐（两级）**：内置命令/插件保持静态注册表 + 显式 `#load` 列表（juice 已验证底座，自动发现对内置件无收益）；第三方插件走 (c)——扫描插件包找约定入口与 `@otter_plugin` 标记，按扫描序生成确定性注册代码（Metaprogram_Plugins 式逐名 codegen），合并期查重（jaix merge_plugins 形状），身份+版本+源哈希进缓存键。用户侧零中央注册表编辑。

---

## 1. linkme 机制精确描述（一手源码核验）

### 1.1 总体机制

linkme 的 distributed slice 是**纯编译+链接期机制，无任何运行期初始化**。README 原文【官方文档】：

> "The implementation is based on `link_section` attributes and platform-specific linker support. It does not involve life-before-main or any other runtime initialization on any platform. This is a zero-cost safe abstraction that operates entirely during compilation and linking."
> （https://github.com/dtolnay/linkme README, "Distributed slice" 节第 2 段）

> "Slice elements may be defined individually from anywhere in the dependency graph of the final binary."
> （同上，第 1 段——元素可来自依赖图中的任意 crate，**静态链接前提**；README 无任何动态加载路径）

机制骨架【源码】：

1. **声明端**（`impl/src/declaration.rs`）：`#[distributed_slice] static NAME: [T];` 展开为 `static NAME: DistributedSlice<[T]>`，其初始化器取四个边界指针：段起点 `LINKME_START`、段终点 `LINKME_STOP`、查重起点/终点 `DUPCHECK_START/STOP`，交给 `DistributedSlice::private_new`。
2. **元素端**（`impl/src/element.rs`）：`#[distributed_slice(NAME)] static X: T = const_expr;` 展开为隐藏静态量（含 `#[used]` + `#[link_section]`，经声明端导出的宏 `use _linkme_macro_NAME as NAME;` 应用），初始化器**必须是 const 表达式**；元素类型与切片元素类型不符 = 编译错误。函数速记形态（`#[distributed_slice(NAME)] fn f(...)`）保留原函数并另生成隐藏静态量持函数指针；泛型/where 子句禁止。
3. **运行期读取**（`src/distributed_slice.rs`）：`static_slice()` 计算 `len = (stop - start) / stride` 后 `slice::from_raw_parts`，整个 `DistributedSlice<[T]>` 经 Deref 表现同 `&'static [T]`。

### 1.2 各平台机制（`impl/src/linker.rs` 逐 mod 核验）

**ELF（linux/bsd/illumos；linker.rs `linux`/`bsd`/`illumos` mod）**：
- 段名 `linkme_<ident>`（illumos 为 `set_linkme_<ident>`）。
- 边界符号用链接器合成符号：`extern static LINKME_START/LINKME_STOP: [T; 0]` 带 `#[link_name = "__start_linkme_<ident>"/"__stop_linkme_<ident>"]`（`impl/src/declaration.rs` 的 `link_name` 属性）——GNU ld/lld 对任意输出段自动合成 `__start_/__stop_` 符号。
- 段保活：`#[used] static mut LINKME_PLEASE: [T; 0] = [];` 带 `#[link_section = "linkme_<ident>"]` 锚住段（否则 `--gc-sections` 可整段回收）。

**Mach-O（linker.rs `macho` mod）**：
- 段名 `__DATA,__linkme<hash>,regular,no_dead_strip`（`no_dead_strip` = S_ATTR_NO_DEAD_STRIP，防 dead-strip 回收）；`<hash>` 是 ident 的哈希——Mach-O 段名限长（16 字符）所致。
- 边界符号 `#[link_name = "\x01section$start$__DATA$__linkme<hash>"]` / `\x01section$end$…`——Mach-O 链接器对 `__DATA` 段内命名字段合成 start/end 符号。
- 保活同 ELF 思路：`LINKME_PLEASE` 零长静态量带 `#[used]` 置入该段。

**Windows/COFF（linker.rs `windows` mod，亦用于 UEFI）**：
- **无链接器合成符号**。三个用户自置边界静态量：`LINKME_START: MaybeUninit<T>` 在段 `.linkme_<ident>$a`、`LINKME_STOP: MaybeUninit<T>` 在 `.linkme_<ident>$c`；元素在 `.linkme_<ident>$b`。
- 原理是 COFF 链接器行为：**同名前缀（`$` 之前）的段被拼接成一个段，按 `$` 后缀字母序排列**——`$a` < `$b` < `$c`，于是全部元素连续落在两个边界静态量之间；`start = &LINKME_START (+1)`、`stop = &LINKME_STOP` 即切片边界。
- 边界元素必须非零尺寸：declaration.rs 注释原文【源码】"On Windows/UEFI, use non-ZST boundary elements because some codegen backends emit non-zero bytes for ZST statics in custom PE/COFF sections, which corrupts section boundary and dupcheck arithmetic."
- 查重：独立的 `linkm2_<ident>` 段族（`$a`/`$b`/`$c`），`DUPCHECK: isize = 1` 置入 `$b`；运行期检查 `dupcheck_start + skip + 1 < dupcheck_stop` 则 panic `"duplicate #[distributed_slice] with name …"`（`src/distributed_slice.rs` 的 `static_slice`）——第二个声明会让 `$b` 区多一个元素。

### 1.3 顺序语义

- 同 crate 内可用显式排序键 `#[distributed_slice(NAME, pos)]`：`pos` 上限 9999（`impl/src/args.rs`），四位零填充后缀拼进段名（`element.rs` 的 `format!("{:04}", pos)` + `declaration.rs` 的 `concat!(section, key)`）——靠 COFF/链接器的字典序排序。
- 跨 crate 顺序 = 链接器顺序，**不保证**（README 未承诺）。

### 1.4 平台覆盖与约束

- CI（`.github/workflows/ci.yml`）：ubuntu、macOS、Windows(msvc) 全绿；**windows-gnu 已知损坏**（continue-on-error，issue #25）；另有裸机 target（thumbv7m-none-eabi）测试。
- 约束：静态链接专属（元素来自最终二进制的依赖图）；元素初始化器必须 const；仅支持 static/fn 元素；无运行期注册语义。

### 1.5 机制的根本要求（对任意语言的移植清单）

1. **逐项命名段放置**：把单个全局/静态量放进用户命名的段（`link_section` 属性）+ **保活语义**（`#[used]`，防链接器 GC 整段）。
2. **段边界符号的绑定能力**：ELF/Mach-O 路径需要"以任意链接名声明 extern 符号"（`#[link_name]`）；COFF 路径不需要——边界是自置静态量（要求 1 已覆盖）。
3. **链接器行为**：段拼接 + `$` 后缀字母序排序（COFF）；`__start_/__stop_` 合成（ELF）；`section$start$/section$end$` 合成（Mach-O）。
4. **逐声明属性宏/代码生成**：属性在编译期把声明改写为"隐藏静态量 + 段属性"（Rust 的 proc-macro 承担此层）。

---

## 2. Jai 可行性判定

### 2.1 逐声明段放置：**不存在**（移植的第一块砖就缺）

- 全发行版 grep `link_section|@section|#section|no_dead_strip`（how_to/、modules/、examples/，排除第三方 C/C++ 头）：**零命中任何段放置指令**。唯二命中是 C 头文件注释（nghttp2/nghttp3）与 Mach-O 文件格式绑定常量 `ATTR_NO_DEAD_STRIP :: 0x10000000`（`modules/executable_formats/bindings/macho.jai:394`——那是解析/生成 Mach-O 用的格式标志，不是编译器指令）【源码】。
- `modules/Compiler/Compiler.jai` 全文无 `link_name`（grep 零命中）——ELF/Mach-O 路径的"extern 符号绑定任意链接名"同样不存在【源码】。
- 链接器层面的旋钮存在但全是**整构建级**：`Build_Options.use_custom_link_command := false`（`Compiler.jai:180`）、`additional_linker_arguments: [] string`（`:186`，"If you want to override the compiler's arguments and control linking completely, use a custom link command instead of this"）、`append_linker_arguments`（`:208`）；`Llvm_Options.function_sections: bool = false`（`:37-42`，"identical to switches used by clang/LLVM tools (i.e., -ffunction-sections)"——**每函数一段**，非用户命名段）；`output_type` 含 `.OBJECT_FILE(4)/.STATIC_LIBRARY(3)`（`:79-85`）。自定义链接命令能接管链接，但**编译器仍决定每个全局的段名，源码无控制点**【源码】。
- `#foreign`（`how_to/095_static_if.jai:126,140`）只能按名声明外部 C 符号（"声明已有符号"），不能把 Jai 全局放进某段；how_to 中无任何带属性的 `#foreign` 用法【源码】。
- 兜底路径 `#asm`（`how_to/900_inline_assembly.jai`）：Jai 的内联汇编是**指令级 DSL**（Intel 助记符 + 自动寄存器映射，`how_to/900:1-49`），无 `.section`/数据指令、无原始符号定义——不能经 asm 手工合成 `.linkme_x$a` 边界静态量【源码】。

**判定：linkme 的忠实移植在 Jai beta 0.2.009 不可行，且没有任何变通路径**。精确缺失面 = 「逐声明命名段放置 + 保活」（所有平台都需要）与「extern 符号任意链接名绑定」（ELF/Mach-O 路径）。唯一出路是向 jai 编译器提特性请求（`@section` 类注记 + extern link_name）。

### 2.2 `#insert` 反射能力

`#insert` 本身（`how_to/600_insert.jai` 全文核验）：把**编译期已知的字符串或 Code 树**插入语句位/表达式位/结构体定义内/全局作用域（`:82-83` "even inside the global scope"）；短形式 `#insert #run expr`（`:381`）与 `#insert -> string {…}`（`:403`）；"You can't #insert code at runtime"（`:255-257`）；Code 树操作"Not quite all the features are in place for easy manipulation of the Code type, but it's coming soon"（`:270-273`）【官方文档】。

**`#insert` 是"从数据生成代码"，不枚举任何既有声明。** 全发行版 grep 到的真实用法无一枚举程序声明：`modules/Bit_Array.jai:95,109,147`、`Bucket_Array.jai:134`、`Hash_Table.jai:165,255`、`Code_Visit/module.jai:20,311-331`、`Bindings_Generator/module.jai:326`、`Print_Vars.jai:106-125`、`Soa.jai:19-71`、`Keymap`、`Metaprogram_Plugins.jai:47,86`——全部是宏/绑定生成的代码拼接【源码】。

**声明枚举的真实宿主是 metaprogram 消息循环，不是 `#insert`**【源码】：

- `Message_Typechecked`（`Compiler.jai:327-341+`）：字段含 `declarations`（"declarations of toplevel variables"）、`procedure_headers`、`procedure_bodies`、`structs`、`others`——注释原文 "There are lots and lots of declarations in a program; we don't send them all in these messages, just the ones that occur at toplevel."
- `Code_Declaration`（`Compiler.jai:674-711`）：`flags.IS_CONSTANT :: 0x1`（`:683`）、`IS_GLOBAL :: 0x100000`（`:702`，"in a file-level or module level scope"）、`notes: [] *Code_Note`（`:708`）、`type_inst`/`expression`（`:679-680`）——**顶层常量（含注记与值树）可由观察 metaprogram 枚举**。
- 官方模式先例 = `how_to/460_code_browsing_and_generation/first.jai:15-18` 注释原文："Registering commands for the interactive console. If you tag a procedure with @command, the metaprogram sees it, then generates a binding that is added to the program. Thus new commands are usable from the command console without you needing to register them manually."（`@command` 注记 → metaprogram 看见 → `add_build_string` 注入绑定）；`how_to/490_browsing_by_module` 演示按模块/文件分组枚举（`Message_File`/`Message_Import`）。
- 流程形状：`compiler_create_workspace`（目标程序工作区）→ `compiler_begin_intercept` → 消息循环收 `.TYPECHECKED` → 枚举+判定 → `add_build_string` 注入生成的注册代码（`how_to/460:26-55,61-81,118-158`）——即"**观察者 metaprogram 编译目标 workspace，边看边生成**"，与 juice 自己的编译 metaprogram（`juice/src/metaprogram.jai` 生成器）同构。
- 附注：先前研究笔记提及的 `Program_Info`/`build_engine_get_info_for_build_index`/`t_load_engine` 在本 beta **零命中**（grep 全发行版无结果）——其原本就是【推断】来源（`juice/docs/research/test-collection-mechanisms.md:44`），此处正式更正：本 beta 的实际反射面是 `Message_*` + `Code_*` API 族【源码】。

### 2.3 运行期顶层执行语义——实验判死

实验（`C:/Users/maojiaxing/AppData/Local/Temp/otter-discovery-research/`：`reg.jai` 全局数组 + `register_name`；`a.jai`/`b.jai` 各尝试一种顶层注册形态；`main.jai` `#load` 后打印数组）：

| # | 形态 | 结果 |
| --- | --- | --- |
| E1 | 顶层裸调用 `print(…); register_name("a");` | 编译错误原文：`a.jai:1,1: Error: Attempt to perform a procedure call outside the body of another procedure. Calls (and many other imperative expressions) can only occur inside procedure bodies.` |
| E2 | 含调用的顶层初始化器 `from_b := register_name("b");` | 同款编译错误（`b.jai:1,11`） |
| E3 | 纯常量表达式 `pure_arithmetic := 1 + 2;` | 编译运行通过，main 内读到 `pure_arithmetic = 3` |
| E4 | 编译期可求值调用 `pure_call := tprint("%", 5);`（`tprint` 带 `#must`，`Basic/Print.jai:340`） | 仍报同款错误（`main.jai:6,14`）——**连 `#must` 编译期调用在顶层初始化器里都被拒** |

E3 运行期完整输出原文（唯一编译通过的形态）：

```
--- main starts ---
pure_arithmetic = 3
--- main ends ---
```

（`names` 数组为空——无任何注册发生。）

**结论**：Jai beta 0.2.009 **不存在运行期顶层执行**——顶层唯一可执行的是编译期路径（`#run` / `:: #run` 常量），其全局修改不持久化到运行期（先前实验 B，`juice/docs/research/test-collection-mechanisms.md`）。因此"load 序运行期自注册"作为机制**不存在**，顺序问题在运行期无从谈起（编译期 `#run` 的顺序才是逆 `#load` 序——先前实验 A）。候选 (d) 判死，此结论与 beta 版本绑定，语言演进后需复核。

### 2.4 PE 自检（仅备查，对结论无影响）

`modules/executable_formats/` 下有 `pe.jai`/`coff.jai`/`elf.jai`/`macho.jai`/`module.jai`；`GetModuleFileNameW` 绑定在 `modules/Windows.jai:2335`，自身 exe 路径取法见 `modules/System.jai:67`——自定位并解析自身 exe 的段表**可行**。但段无法从 Jai 源码发出（§2.1），故对链接期聚合而言此路径 moot，仅对诊断类功能有意义【源码】。

### 2.5 现有 Jai 原生注册先例

- **`modules/Autorun.jai`**：是 `Metaprogram_Plugin`（**编译期**插件），在编译成功（`.COMPLETE` + `error_code == .NONE`）后于 `shutdown` 钩子 `Process.run_command` 运行产物（`Autorun.jai:17-25,28-63`）。"自动运行已注册过程"的运行期语义**不存在**；插件注册方式是显式名字列表 + codegen（下条）【源码】。
- **`modules/Metaprogram_Plugins.jai`**（注册模型确证）：`init_plugins(names: [] string, …)`（`:22-77`）用 String_Builder 为每个名字生成 `Plugin_%1 :: #import "%2"%3; p_%1 := Plugin_%1.get_plugin();`（codegen 模板 `:41`），经 `add_build_string` + `#placeholder` + `#insert` 落入编译（`:49-87`）。模块契约极简：定义 `get_plugin :: () -> *Metaprogram_Plugin`（`modules/Example_Plugin.jai:1-23`）。**"按名 `#import` + 调 `get_plugin()` 的逐名 codegen"是官方插件加载的唯一形态，名字列表由调用方显式提供，无任何模块枚举/发现**【源码】。
- `#module_parameters`（`Autorun.jai:6`）允许名字带参数（`"Autorun(\".exe\")"`），由 `init_plugins` 的 `my_split_from_left(it, "(")` 切分（`Metaprogram_Plugins.jai:54`）。

---

## 3. 候选机制对比表

| 候选 | 判定 | 证据与理由 |
| --- | --- | --- |
| (a) 链接期聚合忠实移植 | **不可行** | 缺逐声明命名段属性、`link_name`、`#asm` 段指令（§2.1）；需要 jai 编译器特性请求。即使编译器支持，还需评估 MSVC/LLD 的 `$` 段拼接与保活语义在 jai 后端的表现 |
| (b) `#insert` 编译期反射 + 生成注册表 | **技术可行，附条件** | 枚举不靠 `#insert` 而靠 metaprogram 消息循环：`Message_Typechecked.declarations`（含 `IS_CONSTANT`/`notes`）+ `add_build_string` 注入（§2.2；`@command` 官方先例 `how_to/460:15-18`）。条件：otter 需要为"插件包源码"跑一个拦截式 workspace（juice 的编译 metaprogram 已是此形态）。代价比 (c) 重（整 workspace 编译级），收益是语义级枚举（防词法误报）。留作 (c) 的增强/后备 |
| (c) 构建工具侧扫描（scan_walk 扫标记 → 生成注册表 + 调用序） | **推荐（第三方插件）** | otter 已握有确定性目录扫描（`juice/src/scan_walk.jai:70-160`：DFS 词法序、可注入排除谓词）；与 juice 转译期枚举同构（"生成时信息已完备"的同一论证，`test-collection-mechanisms.md` 路径二判定）；产物 = 生成的显式调用文件，无运行期/编译期发现依赖。词法扫描误报风险用标记形态（`@otter_plugin` 注记锚在 `get_otter_plugin` 声明上）+ 合并期校验兜底 |
| (d) 运行期自注册（load 序） | **判死** | Jai 无运行期顶层执行（§2.3 实验 E1/E2/E4）；过程指针数组运行期注册本身可用（先前实验 C / gs_test），但注册调用只能由 main 或生成代码**显式发出**——即 (d) 唯一可行的形态是退化为 (c) 生成的显式调用表 |

---

## 4. otter 推荐设计

### 4.1 第一级：内置命令/插件——保持静态注册表

沿用 juice 现状：`COMMAND_REGISTRY` 静态数组（`juice/src/commands/registry.jai:3-8`）+ `main.jai` 显式 `#load` 列表（`juice/IMPLEMENTATION.md:28` 的新增命令流程）。理由：

1. **bootstrap 硬约束**：`build.jai` 的 `#load` 闭包必须 test-free 且随仓库分发（`otter-refactor-research.md` §5.1；研究 B 结论 8b）——内置件的发现面必须是静态、封闭、可审计的；任何"扫描发现"对内置件引入非确定性且无收益（内置件数量有限、每次增删都走完整测试套件）。
2. **确定性**：源码序 = 注册序 = 派发序，dispatcher 的 `validate_registry`（`juice/src/dispatcher.jai:35-59`）继续承担完整性校验。
3. "编辑中央注册表"痛点**不适用于内置件**——痛点属于第三方作者（他们无法编辑 otter 的注册表文件），这正是第二级解决的问题。

### 4.2 第二级：第三方插件包——构建工具侧扫描 + 生成注册表（候选 (c)）

机制链（全部有现成先例）：

1. **发现**：插件包 = LIB 包 + 约定入口（`module.jai`/`src/module.jai`，`otter-refactor-research.md` §4.1 的入口探测序）+ 标记。otter 以 `collect_scan_files` 同款确定性 walk（`scan_walk.jai:70-160`）扫插件包，识别标记声明——推荐标记 = `@otter_plugin` 注记挂在 `get_otter_plugin :: () -> *Otter_Plugin` 上（词法扫描可用 juice lexer 的锚点判定同款手法，`transpile.jai` 的 `is_test_anchor` 先例）。
2. **声明面**：消费者 `package.jai` 的 `dependencies` 声明插件包（现有机制）；**bootstrap 期内** otter 专属字段（如插件选项）只能以 `PACKAGE` 之外的兄弟常量存在（juice 求值器对未知顶层常量零感知、严格解析器不受影响——`otter-refactor-research.md` §1.2 的兼容硬约束），自举切换后随 `modules/Juice.jai` 双份方案演进。
3. **注册代码生成**：按扫描序（DFS 词法）为每个插件生成 `OTTER_PLUGIN_<i> :: (#import "<模块名>").get_otter_plugin();` 式显式调用——Metaprogram_Plugins `init_plugins` 的逐名 codegen 形状（`Metaprogram_Plugins.jai:41`），`#import` 经依赖 shim/import 目录解析（`otter-refactor-research.md` §4.1）。生成文件落 `target/`（不进 bootstrap 闭包、不入库）。**显式调用表 = 候选 (d) 唯一可行的形态**：Jai 没有"加载即注册"运行期语义（§2.3），运行期注册动作必须由生成的代码在 main 里发出（过程指针数组已被实验 C 验证可用）。
4. **合并与查重**：`merge_plugins` 形状的注册期校验（`jaix/src/plugin.jai:336-471` 先例）——重复 id/异版本冲突、命令名冲突、适用范围声明冲突，失败 = 响亮拒绝。linkme 的"第二个声明 panic"是运行期兜底，otter 的合并校验是构建期兜底（更早、可报文件行号）。
5. **顺序确定性**：扫描序（词法 DFS）→ 生成文件调用序 → 管线执行序；需要显式排序时借鉴 linkme 的 sort-key 思想（声明上的可选序号字段，`impl/src/args.rs` 的 `pos` 上限 9999 先例）。
6. **缓存键**：插件身份 + 版本 + 解析到的源哈希进入管线/视图缓存键（`juice/src/transpile_cache.jai:48-66` 的键成分先例；`JUICE_VERSION` 语义泛化为管线输出契约版本，`transpile-plugin-architecture.md` 结论 3.2.3）。
7. **ergonomics 对比 juice 现状**：第三方作者写一个文件（`get_otter_plugin` + `@otter_plugin`），消费者声明一个依赖——两侧都**不碰任何中央注册表**；otter 侧也不存在手维护的 `#load` 列表（生成）。
8. **Windows-first**：全链路（扫描、codegen、shim、子进程 jai 编译）都是 juice 已三路径验证的 Windows 机制；不依赖任何链接器行为；DLL 宿主路径维持推迟（`dynamic-libraries.md` 的调用约定崩溃反例）。

### 4.3 与 juice 转译期枚举的对照

juice test 收集 = 转译期枚举（转译器已解析全部源文件，生成时信息完备，`test-collection-mechanisms.md` 结论）；otter 插件发现 = 同一哲学的构建工具侧枚举（otter 的扫描器已遍历插件包）。二者共同的论证：**发现发生在工具已经遍历全部源文件/文件的环节，注册表由工具生成，不需要语言层或链接层魔法**。候选 (b)（metaprogram 消息循环枚举）是同一结论的"语义级版本"，仅当词法标记扫描被证明有歧义时启用。

---

## 5. 风险与未决

1. **编译器特性请求未提**：linkme 式机制需要 jai 支持「逐声明命名段 + 保活」与「extern link_name」（§2.1 的精确缺失面）。若未来 otter 需要零开销链接期聚合（如生成程序的内置插件表），这是唯一通路；建议记录为特性请求素材，不进近期路线。
2. **(b) 路径的 spike 项**：`Message_Typechecked.declarations` 对**顶层常量**（`IS_CONSTANT`）连同 `notes` 与值树的完整枚举 + 注记读取未做端到端实验（`how_to/460` 只演示了 structs；字段存在性已核验，消费路径未验证）。若启用 (b) 作为 (c) 的增强，先做 spike。
3. **标记形态未定**：`@otter_plugin` 注记 vs 文件名约定（`*.plugin.jai`）vs 协议字段——注记形态与官方 `@test`/`@command` 注记约定对齐（`test-collection-mechanisms.md` 91-108），文件名约定对词法扫描更廉价。需 spec 级决策。
4. **跨包顺序语义**：依赖闭包内的插件相对顺序（DFS 前序 vs 词法序 vs 声明序）需 spec 定死；linkme 的跨 crate 顺序不保证是前车之鉴——otter 必须在生成层保证（扫描序天然保证）。
5. **版本语义**：juice v1 的插件声明 version 是装饰性的（0063 偏差 3）——otter 的插件版本是否进缓存键/是否校验，需独立决策（§4.2.6 建议进键）。
6. **beta 版本绑定**：§2.3 的"无运行期顶层执行"与 §2.2 的反射 API 面均绑定 beta 0.2.009；语言演进（顶层初始化器放行、Code 树操作完备化）后需复核 (b)/(d) 判定。

---

## 引用清单

linkme（master @ 2026-10-19，GitHub API + raw 抓取）：

- README（机制总述、平台表、静态链接前提、const 初始化器）：https://github.com/dtolnay/linkme/blob/master/README.md
- `src/lib.rs`（crate 文档，重复 README 机制段落）
- `src/distributed_slice.rs`（`DistributedSlice` 结构、`static_slice` 边界计算与查重 panic、Windows skip 注释）
- `src/private.rs`（`Slice` trait、`BoundaryElement<T> = MaybeUninit<T>`）
- `impl/src/linker.rs`（`linux`/`bsd`/`macho`/`windows`/`illumos` 五 mod 的段名与边界符号）
- `impl/src/declaration.rs`（声明端展开：ELF/Mach-O extern link_name 边界、COFF `$a/$c` 自置边界、`LINKME_PLEASE` 保活、`linkm2` 查重族、导出宏）
- `impl/src/element.rs`（元素端展开：隐藏静态量、函数速记、泛型禁止、sort key 四位零填充）
- `impl/src/args.rs`（`#[distributed_slice(NAME, pos)]` 参数解析，pos ≤ 9999）
- `.github/workflows/ci.yml`（平台矩阵；windows-gnu continue-on-error + issue #25）

Jai 发行版（`C:/Users/maojiaxing/DevTools/jai`，beta 0.2.009）：

- `modules/Compiler/Compiler.jai`：`Llvm_Options.function_sections` 37-42；`Build_Options.output_type` 79-85；`use_custom_link_command` 180；`additional_linker_arguments` 186；`append_linker_arguments` 208；`Message_Typechecked` 327-341+；`Code_Declaration`（`IS_CONSTANT` 683、`IS_GLOBAL` 702、`notes` 708）674-711；全文无 `link_name`/`Information`（grep 佐证）
- `modules/executable_formats/bindings/macho.jai:394`（`ATTR_NO_DEAD_STRIP` 格式常量——非编译器指令）
- `how_to/600_insert.jai`（`#insert` 全能力：作用域 82-83、编译期约束 255-257、Code 树未完备 270-273、短形式 373-410）
- `how_to/460_code_browsing_and_generation/first.jai`（`@command` 注记先例 15-18；workspace 拦截 + `add_build_string` 流程 26-55、61-81、118-158）
- `how_to/490_browsing_by_module/first.jai`（按模块/文件枚举 1-100）
- `how_to/095_static_if.jai:126,140`（`#foreign` 形态，无属性）
- `how_to/900_inline_assembly.jai:1-49`（`#asm` 指令级 DSL，无段/数据指令）
- `modules/Autorun.jai`（编译期插件运行产物全文件）
- `modules/Metaprogram_Plugins.jai`（`init_plugins` 逐名 codegen 22-77，模板 41，`#placeholder`/`#insert` 81-87）
- `modules/Example_Plugin.jai`（`get_plugin` 契约 1-23）
- `modules/Windows.jai:2335`（`GetModuleFileNameW` 绑定）、`modules/System.jai:67`（自身 exe 路径用法）
- `modules/Basic/Print.jai:340`（`tprint` 带 `#must`）
- 全发行版 grep 证据：`link_section|@section|#section|no_dead_strip` 仅 C 头 + macho 绑定常量；`#insert` 真实用法清单（Bit_Array/Bucket_Array/Hash_Table/Code_Visit/Bindings_Generator/Print_Vars/Soa/Keymap/Metaprogram_Plugins）；`Program_Info|build_engine_get_info_for_build_index` 零命中

本仓库：

- `juice/docs/research/test-collection-mechanisms.md`（实验 A/B/C：编译期注册判死、逆 #load 序、gs_test 运行期注册、metaprogram 扫描冗余判定）
- `otter/docs/research/otter-refactor-research.md`（§1.2 求值器兼容硬约束、§2.1 静态注册表现状、§4.1 入口探测/依赖 shim、§5 自举 test-free #load 集）
- `juice/docs/research/transpile-plugin-architecture.md`（插件宿主四路、`init_plugins` 先例、缓存键并入管线描述）
- `juice/src/scan_walk.jai`（确定性 DFS 词法序 walk 70-160；排除谓词注入）
- `juice/src/manifest.jai`（求值器 codegen 23-95；严格协议解析）
- `juice/src/commands/registry.jai:3-8`（`COMMAND_REGISTRY` 静态数组）；`juice/IMPLEMENTATION.md:28`（新增命令流程）
- `juice/src/dispatcher.jai:35-59`（`validate_registry`）
- `juice/src/transpile_cache.jai:48-66`（视图键成分）；`juice/src/transpile.jai`（`is_test_anchor` 锚点判定先例）
- `jaix/src/plugin.jai:336-471`（`merge_plugins` 合并校验先例）

实验（本机，`C:/Users/maojiaxing/AppData/Local/Temp/otter-discovery-research/`）：E1-E4 见 §2.3 表格与运行原文（`reg.jai`/`a.jai`/`b.jai`/`main.jai`）。
