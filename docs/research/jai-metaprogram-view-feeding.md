# Jai metaprogram 加载转译器与喂视图机制研究（票 0028）

> 研究问题（票 0028，父票 0025）：自举剥离（build.jai 内嵌 STRIP 视图）依赖的三个 Jai 机制事实：
> 1. `#load` 在 metaprogram 中的语义——被 load 代码进编译期执行环境还是被构建程序；
> 2. `add_build_string` 是否存在及其语义（虚拟路径、字符串内 `#load`/`#import` 解析）；
> 3. build.jai 现有 Compiler 用法（begin_intercept / add_build_file / 消息循环）与剥离步骤的组合。
>
> 全部结论来自一手来源：Jai 发行版 `C:/Users/maojiaxing/DevTools/jai`（beta 0.2.009，2025-02-06，见文末"发行版版本"）的 modules/Compiler 源码与文档注释、how_to、examples、CHANGELOG，以及本机编译运行实验；本仓库 `build.jai`、`src/transpile.jai`、`src/commands/build.jai`、`docs/transpiled-output-formatting.md`、`docs/adr/0005-view-line-fidelity.md`。
> 每条论断标注来源类型：【实验】= 本机编译运行验证；【源码】= 读发行版/本仓库源码或文档确认；【推断】= 基于事实的推理，非直接证据。
> 实验文件在 `C:/Users/maojiaxing/.claude/jobs/a6938406/tmp/`（e1、e2、e3、e3b），未修改仓库产品代码。

## 结论摘要

1. **`#load` 在 metaprogram 中的语义：可行，且正是设计所需**【实验】。metaprogram 自身就是一个在编译期执行的程序；`#load` 是文本包含，把文件编译进"当前程序"（即 metaprogram 的编译期执行环境），`#run` 块可直接调用被 load 文件的纯函数（含未标 `#compile_time` 的普通过程）。被 load 代码绝不进入被构建程序——目标 workspace 是 `compiler_create_workspace` 创建的独立编译单元，只包含 `add_build_file`/`add_build_string` 喂入的代码（e1c 负例：目标程序引用被 load 符号报 `Undeclared identifier`）。`#load` 写在 `#run` 块内部同样有效（e1b）。
2. **`add_build_string` 存在**【源码/实验】。语义：字符串成为目标 workspace 的一个虚拟源文件，虚拟路径 `<intermediate_path>/.added_strings_w<workspace_id>.jai`，首串内容前有 5 行头（行号偏移恒 +5）；字符串内 `#import` 按 import_path 正常解析，相对 `#load` 以 **add_build_string 调用点文件所在目录**为基准（与 cwd、虚拟文件位置无关），`#load` 目标必须是字符串字面量（常量报错）。替代方案（临时视图文件 + `add_build_file`）同样可行，即现有 `juice build` 前端的做法。
3. **与 build.jai 现有用法的组合成立**【实验】。剥离前端插入点：`set_build_options`（build.jai:66）之后、`compiler_begin_intercept`（:71）之前；消息循环无需改动。e3 用真实 `src/transpile.jai` 端到端验证：入口视图喂字符串 + 闭包内其余视图写盘 + in-package `#load` 重写绝对路径，编译运行成功，#load 树跟随。诊断位置映射成立（ADR 0005）：入口字符串错误报虚拟路径、行号 = 字符串行 +5（常量偏移、列精确）；磁盘视图错误报精确文件+行号。

## 第一部分：`#load` 在 metaprogram 中的语义

### 1.1 `#load` 是文本包含，进入"当前程序"的 file scope

【源码】`C:/Users/maojiaxing/DevTools/jai/how_to/040_import_and_load/main.jai:66-71`，官方说明原文：

> 66-67："This lets us load a file with a known filename, without having to search the import_path."
> 67-69："This is different from #load, because #load puts things into file scopes under your application scope; #import makes a separate module that cannot see your application scope"

即 `#load` 与 `#import` 的根本区别：`#load` 把文件作为 file scope 包含进当前程序（application scope 之下），`#import` 是隔离的模块作用域。

### 1.2 metaprogram 自身是编译期执行的程序，目标程序是独立编译单元

【源码】`how_to/450_basic_metaprogram/first.jai:13-53`：metaprogram 的形态是——本文件先作为普通程序编译，其 `#run build()`（:64）在编译期执行；`build()` 内部 `compiler_create_workspace("Target Program")`（:19）创建**另一个**编译单元，`compiler_begin_intercept`（:41）后 `add_build_file(...)`（:44）喂入目标代码，消息循环观察其编译过程，最后 `set_build_options_dc(.{do_output=false})`（:61）让 metaprogram 自身不产出口。

【源码】`how_to/470_running_hooks_in_the_target_workspace/first.jai:8-10`，官方说明原文：

> "Also, any code that runs in the metaprogram's workspace does not affect the target program, so it's very clean."

据此，metaprogram 的编译（含其 `#load` 的文件）与目标 workspace 的编译是两个互不可见的编译单元：**被 `#load` 的代码只能进入 metaprogram 自己的程序**，目标程序只会看到 `add_build_*` 喂入的代码。

### 1.3 实验验证

【实验】e1（`.../tmp/e1/`）：`build.jai` 顶层 `#load "lib.jai"`（纯函数 `add1` + 常量 `VALUE`），`#run` 内 `print("VALUE = %, add1(41) = %\n", VALUE, add1(41))`。编译期输出 `[metaprogram] VALUE = 42, add1(41) = 42`，目标程序 `target.jai` 独立编译运行成功（`target runs`）。**证明：被 load 代码编译进 metaprogram 执行环境，`#run` 可直接调用其纯函数。**

【实验】e1b（`build_inside.jai`）：`#load` 写在 `#run` 块**内部**同样有效，编译期输出 `inside: VALUE = 42, add1(41) = 42`（该次运行的退出码 1 仅因文件自身无 `main` 且未设 `do_output=false`，与 #load 无关）。

【实验】e1c（负例，`build_bad.jai` + `target_bad.jai`）：目标程序试图调用 metaprogram `#load` 的 `add1`，编译错误原文：

> `C:/Users/maojiaxing/.claude/jobs/a6938406/tmp/e1/target_bad.jai:4,18: Error: Undeclared identifier 'add1'.`

**证明：被 load 代码绝不进入被构建程序。**

【实验】e3（见第三部分）：用仓库真实的 `src/transpile.jai`（纯函数、仅 `#import "Basic"`/`"String"`）做同一验证——metaprogram `#load "C:/.../juice/src/transpile.jai"` 后，`#run` 中调用 `transpile_source`（普通过程，**未标 `#compile_time`**）成功编译期执行，产出正确 STRIP 视图。**证明：从 `#run` 调用的普通过程会被编译期执行，无需任何标记。**

### 1.4 结论

**可行**。`#load "src/transpile.jai"` 于 build.jai（metaprogram）中，其代码编译进 metaprogram 执行环境；`#run` 块内可直接调用 `transpile_source` 等纯函数；目标程序（juice 本体）与之完全隔离。附带观察【实验】：transpile.jai 在 beta 0.2.009 下编译会出两条 `%%` print 警告（`src/transpile.jai:339`，print 语义变更的兼容警告，无碍），自举 `#load` 后编译 build.jai 时会出现。

## 第二部分：`add_build_string` 的存在性与语义

### 2.1 存在性：有，且有两个重载

【源码】`C:/Users/maojiaxing/DevTools/jai/modules/Compiler/Compiler.jai:1599-1601`：

> 1599：`add_build_file      :: (filename: string, w: Workspace, loc := #caller_location) #compiler;`
> 1600：`add_build_string    :: (data:     string, w: Workspace, code := #code,null, loc := #caller_location) #compiler;  // If provided, 'code' is a dummy that just indicates the scope at which the string should be added (because Code stores scopes in it). If not provided, the build string goes into the main program's toplevel scope. Note that the 'code' argument only works if it belongs to the target workspace, which probably only happens if you are adding a string to your own workspace.`
> 1601：`add_build_string    :: (data:     string, w: Workspace, message: *Message, loc := #caller_location) #compiler "add_build_string_scoped_by_message";  // In this version, which you would call from a metaprogram, you use a Message to indicate the target scope. If it's a Message_File, we insert into that file scope; if it's a Message_Import, we insert into the module scope of that import. If it's null, we insert into the module scope of your main program. Any other value for the 'message' argument is an error.`

要点：不带 `code`/`message` 时字符串进入**主程序 toplevel 作用域**（这正是视图入口所需——e3 中字符串里的 `main` 直接成为目标程序入口）；`code` 参数只在目标 workspace 内部（目标程序自己的 `#run`）可用；metaprogram 要指定作用域用 Message 重载（`add_build_string_scoped_by_message`，e.g. 插入某 `#import` 的模块作用域）。

【源码】`Compiler.jai:253-260` `Message_File`：

> 256：`fully_pathed_filename: string;`
> 257：`enclosing_import: *Message_Import;  // null if this file is added as a string from a module, because those don't get put into the right scopes yet!`
> 259：`from_a_string: bool;  // This is from a string, not a file on disk.`

【源码】`CHANGELOG.txt:2443`：Message 重载的引入（"When running in a metaprogram, you can now add strings to a target workspace in various different scopes..."）；`:2445` 配套 example `add_build_string_into_specific_scope`；`:3359`：`add_build_file`/`add_build_string` 携带隐式 `#caller_location`，"tells the runtime where the string is being added from. This then gets propagated into error messages"。

【源码】`examples/add_build_string_into_specific_scope/build.jai:73-87`：官方 example——metaprogram 在 `.TYPECHECKED_ALL_WE_CAN` 阶段向模块作用域（Message_Import）与文件作用域（Message_File）注入字符串。

### 2.2 虚拟路径与行号偏移

【实验】e2（`.../tmp/e2/build.jai`）：喂入字符串后收到 `FILE` 消息，`from_a_string=true`，`fully_pathed_filename = C:/.../tmp/e2/.added_strings_w3.jai`（w3 = workspace id）。落盘内容（`cat -n` 原文）：

```
     1	// Workspace: T
     2	
     3	//
     4	// String added via add_build_string() from C:/Users/maojiaxing/.claude/jobs/a6938406/tmp/e2/build.jai:17.
     5	//
     6	// line 1            ← 字符串第 1 行
     7	#import "Basic";
     ...
```

即：**虚拟文件位于 `<intermediate_path>/.added_strings_w<workspace_id>.jai`，字符串内容前有固定 5 行头，字符串第 N 行 = 虚拟文件第 N+5 行**（首串行号偏移恒为 +5，列号精确）。同次运行的错误报告印证：字符串第 3 行第 5 列的 `print` 未声明，报 `.../e2/.added_strings_w3.jai:8,5: Error: Undeclared identifier 'print'.`（3 + 5 = 8）。

【源码】`Compiler.jai:173`：`intermediate_path` 注释 "The place for temporary files, such as .added_strings_*, intermediate object files, etc."；`:92` `write_added_strings` 控制编译结束时是否落盘；`CHANGELOG.txt:1332` 表明即使 `write_added_strings=false`，调试信息仍引用 added_strings 虚拟位置。

【实验】e2f：同一 workspace 多次 `add_build_string`，后续字符串以"空行 + 3 行头（无 Workspace 行）"追加，偏移累积（第二串偏移 = 5 + 首串行数 + 1 + 3，错误行号实测 14 = 第二串第 3 行）。**推论【推断】：每 workspace 只喂一个字符串（入口视图）时映射为常量 +5；若喂多个，需按追加顺序自行累计。**

### 2.3 字符串内 `#load`/`#import` 的解析

【实验】e2c：字符串内含相对 `#load "sub.jai";` **编译成功**，FILE 消息显示解析到 `C:/.../tmp/e2/sub.jai`（metaprogram 所在目录下的 sub.jai）。

【实验】e2d（消歧）：把 `intermediate_path` 指到 `./int`（虚拟文件落于 e2/int/），相对 `#load` 仍解析到 e2/ 下的 sub.jai；再从**另一目录**运行同一 metaprogram（cwd ≠ metaprogram 目录），解析结果不变。**结论：字符串内相对 `#load` 的解析基准 = `add_build_string` 调用点文件所在目录（`#caller_location`），与 cwd、虚拟文件自身位置（intermediate_path）均无关。** 绝对路径照常工作。

【实验】e2b：字符串内含 `#import "Basic";` 正常编译——`#import` 走 import_path 搜索，与字符串位置无关。

【实验】e2e：`#load CODE;`（CODE 为字符串常量）编译错误原文：`load_const.jai:6,7: Error: Value after #load must be a string literal.`——**`#load` 目标必须是字符串字面量**。因此视图字符串之间无法互相引用，in-package `#load` 的重写目标必须指向磁盘上存在的文件（与 transpile STRIP 契约一致，见第三部分）。

### 2.4 结论

**可行，且替代方案同样可行。** `add_build_string` 存在：入口视图可作虚拟源直接喂入（toplevel 作用域、行号常量 +5 偏移）；闭包内其余视图必须落盘（`#load` 需字面量路径）。若偏好全文件方案，现有 `juice build` 前端（`src/commands/build.jai:150`，`add_build_file` 磁盘视图）即为已验证的替代路径——e3b 同时验证了磁盘视图的诊断是精确文件+行号。

## 第三部分：与 build.jai 现有用法的组合

### 3.1 build.jai 现状（本仓库）

【源码】`build.jai:6-18`：入口守卫——末参数以 `/first.jai` 结尾时跳过构建（本文件被 `juice test` 作为视图加载进测试程序时）。`:32` `set_build_options_dc(.{do_output = false})`；`:33-53` 建 workspace、配 output/intermediate/import 路径；`:66` `set_build_options(options, workspace)`（注释：必须在 begin_intercept 和 add_build_file 之前）；`:71-72` `compiler_begin_intercept(workspace); add_build_file("src/main.jai", workspace);`；`:78-90` 消息循环（`.ERROR` 计数、`.COMPLETE` 退出）；`:92` `compiler_end_intercept`。

### 3.2 剥离步骤的组合（端到端实验）

【实验】e3（`.../tmp/e3/`）：metaprogram `#load` 仓库真实 `src/transpile.jai`；用 `transpile_source` STRIP 模式转译两个含 test block 的文件（a.jai 入口含 `#load "b.jai"`，b.jai 子文件）；子视图写盘 `target/transpile/b.view.jai`，入口视图的 in-package `#load` 重写为子视图绝对路径（`Load_Target`，`src/transpile.jai:22-41` 契约）；然后按 build.jai 相同形状组合：`set_build_options` → `compiler_begin_intercept` → **`add_build_string(入口视图)`** → 消息循环 → `compiler_end_intercept`。结果：

- 转译正确：test block 全部变为等行数注释占位，入口视图内 `#load` 变为绝对路径；
- FILE 消息两条：`out/.added_strings_w3.jai from_a_string=true`（入口字符串）+ `target/transpile/b.view.jai from_a_string=false`（**#load 树跟随成立**）；
- 编译链接成功（exit 0），产物运行输出 `a+b: 5`。

【实验】e3b（诊断映射）：入口视图第 9 行注入未声明标识符 `zap()`，磁盘子视图第 3 行注入 `zap2`。错误报告原文：

> `C:/.../tmp/e3b/out/.added_strings_w3.jai:14,5: Error: Undeclared identifier 'zap'.`（字符串第 9 行 + 5 = 14，列精确）
> `C:/.../tmp/e3/target/transpile/b.view.jai:3,1: Error: Undeclared identifier 'zap2'.`（精确文件+行号）

**诊断位置映射成立：视图与原文件行号一一对应（ADR 0005）在两种喂入模式下都保持**——字符串模式是常量偏移 +5（虚拟路径文件名），磁盘模式是精确路径+行号。

### 3.3 组合方式结论

【推断】剥离前端插入点：`set_build_options`（build.jai:66）之后、`compiler_begin_intercept`（:71）之前——探测闭包（`source_has_test_block`/`source_load_targets`，`src/transpile.jai:422-470`）、按依赖序 STRIP 转译、非入口视图写盘、入口视图 `add_build_string` 替换现有 `add_build_file("src/main.jai", ...)`（:72）。消息循环（:78-90）无需改动：编译错误仍经 `.ERROR` 消息与编译输出双通道呈现。begin_intercept 需在喂入任何源之前（build.jai:64 注释与 how_to/450:39-41 一致，现有顺序已满足）。

【推断】重要推论：字符串内相对 `#load` 的基准从"原文件目录"变为"build.jai 所在目录"（2.3 节），因此入口视图的 in-package `#load` **必须**重写为绝对视图路径——transpile STRIP 已实现该重写（`docs/transpiled-output-formatting.md` §1.4、`src/transpile.jai:647-658`），无需新机制。

## 发行版版本

- 发行版目录 `C:/Users/maojiaxing/DevTools/jai`；`jai -version` 无输出、退出码 0，`--version` 为未知参数（Windows 发行版行为）；版本以 `CHANGELOG.txt` 头为准：**beta 0.2.009, 6 February 2025**。
- 实验目录：`C:/Users/maojiaxing/.claude/jobs/a6938406/tmp/e1`（#load 语义三实验）、`e2`（虚拟路径/解析/多串/常量 #load）、`e3`（端到端组合）、`e3b`（诊断映射）。全部实验未触碰仓库产品代码。
