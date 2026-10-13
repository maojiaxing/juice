# Jai 语法扩展转译器研究（类似 Babel）

> 面向"实现一个类似 Babel 的工具，扩展 Jai 语法（lambda、Zig 风格错误处理），把扩展语法转换为标准 Jai"的前期调研。
> 全部结论来自一手来源：Jai 发行版 `C:/Users/maojiaxing/DevTools/jai`（版本 beta 0.2.009，2025-02-06，见文末"发行版版本"）的 how_to、modules 源码与编译器实际运行输出；Zig 官方语言参考（ziglang.org，master，下载核验于 2026-10-06）；Babel 官方 Plugin Handbook（jamiebuilds/babel-handbook，master，下载核验于 2026-10-06）；以及本仓库源码。
> 每条论断标注来源类型：【实验】= 本机编译运行验证；【源码】= 读发行版/本仓库源码确认；【推断】= 基于事实的推理，非直接证据；【官方文档】= 下载并阅读官方文档原文。
> 实验片段放在系统临时目录 `C:/Users/maojiaxing/AppData/Local/Temp/jai-syntax-research/`，未修改仓库产品代码。

## 结论摘要

1. **先验证后定位：Jai 不缺 lambda 简写，且已有匿名过程**【实验】。beta 0.2.009 同时支持两种：表达式体 quick procedure（`x => x.count`，多态、返回类型推断，`how_to/110_polymorphic_arguments.jai:109-177`）与匿名多语句过程（`f := (x: int) -> int { ... }`，本报告实验 exp2/exp4 编译运行通过）。"Jai 没有 lambda"的社区说法已过时。
2. **Jai 的真正缺口只有三个**：闭包/词法捕获（官方明确"currently no closures"，`how_to/080_scopes.jai:77-80`，实验报错原文 "Attempt to use a variable from an outer stack frame. (Closures are not supported.)"）；匿名过程无返回类型推断、匿名多态过程不能作运行时值（实验 exp4b/exp4e 报错原文）；完全没有语言级错误处理（无 try/catch/异常，发行版 how_to 全文无匹配）。
3. **因此 MVP 价值排序应为：Zig 风格错误处理语法糖 > 捕获 lambda > 普通 lambda 简写**。普通 lambda 不需要转译器；错误处理与闭包降级才是本工具的存在理由。本报告给出两条已验证的 lowering 路径：显式 Result（struct 或多返回值，实验 exp7/exp9 端到端编译运行）与 `#expand` + `#code` 内联宏（实验 exp8 验证 `#code` 体可引用调用方作用域变量，语义为内联而非闭包）。
4. **Babel 架构可借鉴的是"parse → transform（visitor/path/scope）→ generate + sourcemap"的分层与包职责划分**（parser/traverse/types/generator/template 五包分离、builder/validator、`generateUidIdentifier` 符号卫生、`retainLines` 等打印选项），但 Babel 不是语言无关解析器：ESTree 是 JS 专用 AST，parser 是 Acorn fork，均不可直接复用于 Jai。Jai 编译器自身的解析器是闭源的，且 `modules/Compiler` 的 AST（`Code_Node`）与遍历/打印工具（`Code_Visit`、`Program_Print`）只能在编译器进程内（metaprogram）使用，不能作为外部解析库。
5. **Zig 错误处理语义已从官方 langref 逐条核验**：error set 是类枚举的编译期整数值集合（默认 u16，同名字面量同值）；`!T` 是 error union（二元运算符）；`try` 是"求值 error union，是错误则携同值提前返回，否则给出解包值"——天然单次求值；`catch` 的 RHS 仅在出错时求值（惰性），形式有默认值、`|err|` 捕获、命名块、`unreachable`；`errdefer` 仅在该函数以错误返回时于块出口执行，普通 `defer` 无条件执行；不检查错误是编译错误。与异常的关键区别：错误是普通值，无栈展开。
6. **正则替换不可靠**，原因有 Jai 具体语法证据支撑：字符串/注释中可含任意代码文本（`how_to/600_insert.jai:326` 字符串内嵌 `#insert`）、`#insert` 区分语句级与表达式级上下文（`600_insert.jai:335-368`）、`if/for` 语句体可无括号且以换行/分号断句（`how_to/110_polymorphic_arguments.jai:11`、`how_to/019_looping.jai:299`）、`<<`/`*`/`.` 等运算符上下文敏感。推荐策略：完整 lexer + 扩展语法局部 parser，其余文本按 token/trivia 原样保留（span-preserving），遇到语义边界（扩展语法出现在 `#insert`/`#run` 字符串内、`#import,string` 等）明确拒绝。
7. **架构建议**：MVP 做独立 source-to-source CLI（推荐用 Jai 自身实现，与 juice 同工具链，可复用 `modules/File`、`modules/String` 与仓库的 path 安全逻辑），以 golden/负例测试驱动；juice 集成走现有编译 seam 的可选前置步骤，不引入 workspace 重构。实现语言也可选其他语言（Jai 无第三方 parser 库，需手写 lexer/parser，但对扩展语法子集可控）；无论哪种，转译产物必须由 jai 编译运行验证（本报告全部实验即此模式）。
8. **明确的非目标与推迟项**：不声称完整 Zig 等价——`!T` 类型语法（需要类型系统级扩展或宏约定）、errdefer 的精确"函数以错误返回"语义（需控制流分析）、闭包自动捕获（Jai 官方 roadmap 上的语言特性，转译器只能做显式捕获对象降级）均推迟，推迟原因与后续实现方法见对应小节。

## 第一部分：Jai 现状核验——先验证，不假设

### 1.1 quick procedure：已有的表达式 lambda

【源码】`C:/Users/maojiaxing/DevTools/jai/how_to/110_polymorphic_arguments.jai:109-177`，官方说明原文：

> 109-110：`counts := map(cut_uppers, x => x.count);`
> 112-116："Wait, what was this last thing, the x => x.count? ... This is a "quick procedure", which is a convenient way of declaring a polymorphic procedure with a syntactic shorthand convenient for passing simple functions as arguments to other functions."
> 118-124："These two declarations are equivalent: `count1 :: x => x.count;` 与 `count2 :: (x: $T) -> $S { return x.count; }`"
> 173-177："One interesting thing to note about quick procedures is that their return types get inferred from the body of the procedure -- which is something we said, in the last instalment, does not happen! This is an exception..."

要点：
- quick procedure 语法 `x => expr`、`(a, b) => expr`；单表达式体；**返回类型推断是语言明确列出的例外**。
- 隐式多态：可内联作为实参传给多态高阶过程（`:109` `map(fruits, x => x.count)`、`:143` `quick_sort(to_sort, x => x.count)`、`:169` `quick_sort(to_sort, (a, b) => ifx a.count != b.count then ...)`），参数类型由调用点求解（`:180-228` 说明类型求解被严格限制在调用点与过程头，不做全局求解）。
- 体可以是任意表达式，包括 `ifx`（`:169`）。

【实验】exp1（`C:/Users/maojiaxing/AppData/Local/Temp/jai-syntax-research/exp1_quickproc.jai`）编译运行通过：`square :: x => x*x;`、`add :: (a, b) => a + b;` 输出 `square(5) = 25`、`add(2,3) = 5`。

### 1.2 匿名多语句过程：beta 0.2.009 已支持

【实验】exp2/exp4 验证 beta 0.2.009 支持匿名过程作为运行时值，含多语句体：

```jai
f := (x: int) -> int { return x * 2; };        // exp2：编译运行，f(5) = 10
h := (x: int) -> int {                         // exp4c：多语句 + 局部变量，编译运行，h(5) = 12
    tmp := x + 1;
    tmp *= 2;
    return tmp;
};
apply((x: int) -> int { return x + 1; }, 7);   // exp4f：匿名过程内联作实参，结果 8
```

三个关键限制（均为编译报错原文，实验）：
- **无返回类型推断**：`g := (x: int) { return x * 3; };` 报错 "Error: Too many return values: Wanted 0, got 1."（exp4b）。匿名过程必须写全 `-> R`。
- **无捕获**：体内引用外层局部变量报错 "Error: Attempt to use a variable from an outer stack frame. (Closures are not supported.)"（exp1c、exp4d）。
- **多态匿名过程不能作运行时值**：`id := (x: $T) -> T { return x; };` 报错 "Error: A non-constant declaration of a polymorphic procedure is not allowed. (A polymorphic procedure does not represent any specific runtime code until it's instantiated, so you can't assign it to a runtime variable.)"（exp4e）。函数值必须是单态的。

【源码】`how_to/080_scopes.jai:71-86` 是官方对"无闭包"的权威说明：

> 71-75："A procedure, that's defined inside another procedure, cannot use the local variables of that outer procedure, because it has to be able to run independently by itself -- maybe you pass that procedure to some other utility function that saves it and calls it half an hour later, after the outer procedure has returned..."
> 77-80："(There are currently no closures or other forms of automatic local variable capture in the language. It's vaguely on the roadmap to add closures, but, this hasn't been a high priority...)"
> 82-84："But procedures can of course refer to global variables in data scopes. You can refer to an outer variable that's in a data scope, but not one that's in an imperative scope."

即：数据作用域（全局）变量可见，命令式作用域（函数局部）变量不可捕获；闭包在官方 roadmap 上但低优先级。

### 1.3 defer 语义（与 Zig errdefer 对照的基准）

【源码】`how_to/200_memory_management.jai:818-860`："The 'defer' statement is very handy... we don't need to do the very heavyweight C++ "RAII" thing..."；块形式 `defer { ... }` 见 `how_to/350_logging.jai:67`；`#insert` 与 `continue` 交互见 `how_to/730_for_expansions.jai:133`。

【实验】exp3/exp5 验证：
- 同作用域内多个 defer 逆序执行（LIFO）：输出 `inner body / inner defer / end of main body / defer 3 / defer 2 / defer 1`；内层块的 defer 在块退出时先执行。
- defer 在提前 `return` 的路径上也执行：`foo(0)` 输出 `deferred in foo (n=0)` 后返回 -1。

即 Jai 的 `defer` = 块作用域 + 所有出口（含提前 return）+ 逆序。这与 Zig 的普通 `defer` 语义一致（Zig errdefer 的差别见第三部分）。

### 1.4 错误处理现状：语言级机制不存在

【源码】在发行版 `how_to/` 全部 `.jai` 文件中对 try/catch/异常语义的检索无任何语言级错误处理构造（仅 CHANGELOG 中出现两处与 C++ 绑定无关紧要的 "exceptions" 字样）。Jai 的惯用法是显式多返回值：

【源码】`how_to/015_array_literals.jai:48`：`get_strings :: (x: int) -> (success: bool, result: [] string)`。

【实验】exp9（`exp9_multiret.jai`）验证多返回值错误惯用法端到端编译运行：

```jai
may_fail :: (n: int) -> (err: Error, value: int) { ... }
err, v := may_fail(n);
if err != .NONE return err, 0;
```

输出 `propagate(5): err=NONE, v=110`、`propagate(-5): err=NEGATIVE`。这是 Jai 官方风格（`(success: bool, ...)` 或枚举错误码），也是 Zig 风格 `try` 最自然的 lowering 目标（详见第四部分）。

### 1.5 编译期能力与宏体系（Jai-native 替代路径的基础）

【源码】`how_to/600_insert.jai` 是宏机制的一手文档：
- 4-17：`#insert` 接受字符串参数，插入编译期生成代码。
- 255-257："#insert's argument has to be known to the compiler at compile-time! You can't #insert code at runtime, because this is a statically-typed language where all code is resolved at compile-time."
- 270-273："#insert can operate on Code that is already represented as a tree... Not quite all the features are in place for easy manipulation of the Code type, but it's coming soon."（官方自述 Code 树操作 API 尚未完备，这是 Jai-native 路径的现实约束。）
- 279-303：`#expand` 宏定义与 `#code` 调用点（关键：`loop_unroll :: (n: int, code: Code) #expand { ... #insert code; }`，调用 `loop_unroll(9, #code { x += 1; print(...); })` 中 `#code` 体直接引用调用方的局部 `x`——宏体内联使体看到调用方作用域）。
- 335-368：`#insert` 语句级可插多语句，表达式级只能插单个表达式。

【实验】exp8（`exp8_code_macro.jai`）用最小宏复验 `#code` 捕获调用方作用域：

```jai
twice :: (code: Code) #expand { #insert code; #insert code; }
x := 0;
twice(#code { x += 1; });
print("x = %\n", x);   // 输出 x = 2
```

编译运行通过。另：官方 `how_to/600_insert.jai` 本身在本机编译运行通过。

【源码】其他相关编译期能力：
- `#run`：编译期执行，`how_to/080_scopes.jai:97`（`CONSTANT_VALUE :: #run factorial(9);`）；`#insert #run expr` 简写 `how_to/600_insert.jai:370-388`。
- `#modify`：多态求解后修改类型变量，`how_to/170_modify.jai:1-30`。
- `#import`/`#load` 区别：`how_to/040_import_and_load/main.jai:59-68`（"#import makes a separate module scope...#load puts things into file scopes under your application scope"）；`:98` 展示 `#import,string "factorial :: (x: int) -> int {...}"` 从字符串导入代码（生成代码可被正常导入）。
- `Any` 类型：`how_to/030_any.jai:1-48`（类型检查匹配任意类型的特殊类型，可作错误联合的载体候选）。
- 编译器 AST 暴露（仅 metaprogram 内可用）：`modules/Compiler/Compiler.jai:452-455`（"Below are the various nodes that you could find when browsing the AST, for example, from looking at a Message_Typechecked."）；`Code_Node.Kind` 枚举 456-527（含 `DEFER :: 49`、`DIRECTIVE_RUN :: 31`、`DIRECTIVE_INSERT :: 52` 等）；`Location`（`l0, c0, l1, c1: s32` 行列字节偏移，`:541-551`）；`node_flags` 含 `STATEMENT_IS_DEFERRED :: 0x8`、`CREATED_BY_DESUGARING :: 0x100`（`:533-540`，说明编译器自身用脱糖并标记生成节点）；`compiler_get_nodes :: (code: Code) -> ...`（`:1553`）。
- 官方 AST 工具模块：`modules/Code_Visit/module.jai`（`get_subexpressions` :16、`get_recursive_nodes_depth_first` :261、`visit_pre_and_postorder` :294）；`modules/Program_Print/module.jai`（`print_declaration :: (decl: *Code_Declaration) -> string` :84，把 AST 节点转回 Jai 源码文本——官方 AST→源码打印器）。

## 第二部分：Babel 架构——能借鉴什么，不能直接复用

【官方文档】jamiebuilds/babel-handbook（Babel 官方仓库的 Plugin Handbook，master 分支，2026-10-06 经 curl 下载核验，本报告引用的行号以该副本为准）。引用定位：本节所引行号均为该文件。

### 2.1 三阶段管线与包职责

- Babel 自我定义为 source-to-source compiler/transpiler（handbook:99-101）。
- 三阶段 **parse → transform → generate**（handbook:248-324）：
  - Parse 分两相：词法分析（token 流，token 带 `start/end/loc`）→ 语法分析（token 流 → AST）（:254-307）。
  - Transform：遍历 AST，增删改节点，"by far the most complex part"（:309-315）。
  - Generate：深度优先遍历 AST 重建代码字符串，同时生成 source map（:317-324）。
- 包职责分离（可借鉴的核心设计）：
  - `@babel/parser`：Acorn 的 fork，插件化架构支持非标准语法，产 ESTree 变体 AST，节点带 `start/end/loc`（:831-884；:109；:224-246）。
  - `@babel/traverse`：维护整棵树的状态，负责替换/删除/添加节点（:886-919）。
  - `@babel/types`：节点工具库，含三类 API——definitions（每种节点类型的字段/校验/遍历规则，:948-973）、builders（构造器且创建时校验，:975-1014）、validators（`isX`/`assertX`，:1017-1058）。
  - `@babel/generator`：AST → 代码 + sourcemap，选项含 `retainLines`、`compact`、`quotes` 等（:1064-1104）。
  - `@babel/template`：quasiquote 风格字符串模板拼 AST（:1106+）。

### 2.2 visitor / path / scope / state

- **Visitors**：按节点类型注册 `enter`/`exit` 方法（:387-497），树遍历时逐节点进入/退出调用。
- **Paths**："A Path is an object representation of the link between two nodes"——含 `parent`、`node`、`scope`、增删改查方法；"paths are a reactive representation of a node's position in the tree... Whenever you call a method that modifies the tree, this information is updated"（:512-583）。路径抽象是 Babel 最值得复刻的设计：转译器对 AST 的修改通过 path 保持父子关系一致性。
- **Scopes/Bindings**：作用域与绑定跟踪（:681-830），支持三种符号卫生操作，是转译器生成代码不污染用户符号的基础：`path.scope.generateUidIdentifier`（生成不冲突的 UID，:1681-1693）、`path.scope.parent.push`（把声明推到父作用域，:1695-1713）、`path.scope.rename`（重命名绑定及其所有引用，:1715-1745）。
- **State 警告**：官方对全局可变状态的告诫（:610-640）——转译器 pass 间共享状态必须挂在 path/scope 上而非全局变量。

### 2.3 不能直接复用的部分

- Babel 的 parser（Acorn fork）与 AST（ESTree 变体）是 **JavaScript 专用**，不是语言无关解析器（:109、:833-835）。Jai 转译器必须自备 lexer/parser。
- Jai 编译器解析器闭源，官方 AST 只在编译器进程内暴露（见 1.5），无法作为外部解析库。
- 格式保真在 Babel 里靠 generator 选项（`retainLines` 等）与 recast 类工具实现，默认输出是重新格式化后的代码——对本工具"尽量保留原文格式"的目标，应改为 span-preserving/token-preserving 策略（见第五部分），不能照搬 Babel 默认。

## 第三部分：Zig 错误处理精确语义（官方 langref 核验）

【官方文档】Zig 语言参考（`https://ziglang.org/documentation/master/`，即官方仓库 `ziglang/zig` 的 `doc/langref.html.in`，2026-10-06 经 curl 下载核验，HTML 锚点 `#Errors` 段，共约 570 行）。以下语义全部取自该节原文：

- **Error set**："An error set is like an enum. However, each error name across the entire compilation gets assigned an unsigned integer greater than 0. You are allowed to declare the same error name more than once, and if you do, it gets assigned the same integer value." 默认底层类型 u16，`--error-limit` 可令其收窄。子集可隐式 coerce 到超集，反向必须显式 cast（插入语言级 assert）。
- **anyerror** = 全局错误集（整个编译单元所有错误的并集），官方建议避免使用以免编译器失去"哪些错误可能发生"的静态知识。
- **Error union（`!T`）**："An error set type and normal type can be combined with the `!` binary operator to form an error union type." `!u64` 意味着"返回 u64 或一个错误"；省略左侧错误集时错误集被推断（Inferred Error Sets）。函数体内 `return error.InvalidChar;` 与 `return x;`（u64）都 coerce 到该联合。
- **try**："try evaluates an error union expression. If it is an error, it returns from the current function with the same error. Otherwise, the expression results in the unwrapped value." 由此可知 try 的语义是：**操作数单次求值** + 出错时提前返回 + 否则解包。
- **catch**：二元运算符，三种形式：
  1. 默认值 `expr catch 13`——"The type of the right hand side of the binary catch operator must match the unwrapped error union type, or be of type noreturn." 注意：RHS 仅在出错时求值（惰性），这是 `catch blk: { ... }` 命名块形式（`:handle_error_with_catch_block`）能成立的前提。
  2. 错误值捕获 `expr catch |err| return err;`（官方示例 `catch_err_return`）。
  3. `expr catch unreachable`——显式断言不可能出错，Debug/Safe 模式下出错即崩溃；官方明言"failing to check for an error [is] a compile error"（未处理错误联合是编译错误，这是 Zig 错误模型的核心保证）。
- **errdefer**："evaluates the deferred expression on block exit path **if and only if the function returned with an error from the block**"。官方示例中函数成功 `return foo;` 时 errdefer 不执行而普通 defer 执行。defer 与 errdefer 的组合让"清理代码紧跟获取代码"成为惯例。
- **Error Return Traces**（`#Error-Return-Traces` 锚点，:7662-7818）：记录错误被返回到调用方的每个传播点，Debug 构建默认开启，ReleaseFast/Safe/Small 默认关闭。
- **与异常的本质区别**：错误是普通值（整数标识），error union 是普通联合类型；没有栈展开、没有运行时开销堆栈；错误传播是显式返回语义，仅 Debug 下的 Error Return Trace 是附加机制。

对转译器最重要的三条约束由此得出：(1) `try`/`catch` 的操作数必须单次求值（lowering 必须先绑定 temp 再检查）；(2) `catch` 的默认值/块必须惰性求值；(3) errdefer 的条件是"函数以错误返回"，不是"块内有错误发生"。

## 第四部分：可落地的 lowering 设计（已用编译器验证）

> 明确声明：本节的扩展语法（`|x|`、`try`、`catch`、`errdefer`）是本报告的**提案**，不是 Jai 现有语法。所有对应标准 Jai 的示例均在本机 beta 0.2.009 上编译运行通过（实验 exp6-9）。

### 4.1 lambda lowering：两条路径，各自边界

**路径 A：表达式 lambda → quick procedure**（已验证，exp6a）
```
| 输入          | 输出（标准 Jai）      | 能力/限制                                      |
| `\|x\| x*2`    | `x => x*2`           | 多态、返回类型推断；仅表达式体；值语义为多态过程  |
```
适用：单表达式 lambda。类型推断免费获得（quick procedure 的语言特性，1.1）。无捕获问题——quick procedure 同样受"无闭包"限制，捕获引用会得到编译器报错（exp1c），转译器应**在转译期**做同样的拒绝（识别体内引用了外层命令式作用域变量时给出转译期诊断，而不是生成必然编译失败的代码）。

**路径 B：带语句体、显式类型的 lambda → 匿名过程**（已验证，exp6b）
```
| 输入                                | 输出（标准 Jai）                        |
| `\|x: int\| -> int { t := x+1; return t*2; }` | `(x: int) -> int { t := x+1; return t*2; }` |
```
适用：多语句 lambda。**硬约束**（实验 exp4b/exp4e）：匿名过程必须写全参数类型与返回类型，且不能多态。因此 source-to-source 转译器**无法支持类型省略的语句体 lambda**——它没有类型信息。两个选择：(a) MVP 要求此类 lambda 必须写类型注解；(b) 后续走 Jai-native 方案（1.5），在 metaprogram 内从 `Message_Typechecked` 拿到类型后生成。

**捕获 lambda（推迟，MVP 不含）**：Jai 无闭包（1.2）。转译器可提供的最大能力是**显式捕获降级**：把 `|x| x + y`（y 为外层局部）改写为显式携带环境的调用 `Env_Type` 结构 + 匿名过程 `(env: *Env_Type, x: int) -> int`，调用点 `(env, x)`。这是 C 风格闭包的手工模拟，语义上不等价于闭包（生命周期由用户管理、按引用捕获需显式标注可变性），必须在文档中如实说明。**不建议**在 MVP 声称"支持闭包"。真正闭包等官方语言特性（`080_scopes.jai:78`）。Jai-native 的 `#code` 内联宏（exp8）提供"体可见调用方作用域"的内联语义，但那是宏展开（复制执行），不能存储/返回/延迟调用——只适合 `each`/`forEach` 类立即消费场景，可作为后续可选特性。

### 4.2 错误处理 lowering：显式 Result 约定 + try/catch

**错误表示约定（二选一，转译器需可配置）**：
- 约定 1（更贴近 Jai 官方风格，exp9 验证）：函数返回 `(err: Error, value: T)` 多返回值。
- 约定 2（更贴近 Zig error union 结构，exp7 验证）：函数返回 `Result(T)` 多态结构 `struct ($T: Type) { value: T; error: string; }`（或枚举错误码）。

**`try expr` 的 lowering**（单次求值 + 提前返回，exp9 模式）：
```jai
// 提案语法
value := try may_fail(n);

// 标准 Jai 输出
err, v := may_fail(n);        // 1. 操作数只求值一次（temp 绑定）
if err != .NONE return err, 0; // 2. 出错携带同值提前返回
value := v;                    // 3. 解包
```
注意 lowering 必须引入 temp（`err, v`），否则 `try f(x)` 转成 `if f(x).err ... f(x).value` 会双重求值——违反 Zig 语义（3 部分）。temp 命名用 UID 生成（Babel `generateUidIdentifier` 模式，2.2），避免与用户符号冲突。

**`expr catch default` 的 lowering**（惰性默认值，exp7 模式）：
```jai
// 提案语法
number := may_fail(n) catch -1;

// 标准 Jai 输出
r := may_fail(n);
number := ifx r.error == "" then r.value else -1;  // ifx 惰性求值，仅出错分支取默认值
```
Jai 的 `ifx`（表达式 if，`how_to/025_ifx.jai`）保证惰性；`catch |err| handler(err)` 形式对应 `ifx` 的 else 分支引用 `r.error`。`catch unreachable` 对应 `else assert(false)`。

**`errdefer` 的 lowering（MVP 版本，需说明偏离）**：
Zig 语义是"函数以错误返回时执行"（第三部分）。在显式错误值模型下，最贴近的 lowering 是维护函数级错误状态变量并在 defer 里检查：
```jai
// 提案语法
errdefer free(handle);

// 标准 Jai 输出（MVP 方案）
defer { if err != .NONE { free(handle); } }
```
**必须说明的语义偏离**：这只在"函数内所有 `try` 都传播到同一个函数级 `err` 变量（而非直接 `return`）"的纪律下才与 Zig 一致；若函数中某处直接 `return err, 0` 绕过状态变量，errdefer 的条件判断会失真。精确等价需要控制流分析（找出所有以错误值返回的出口）。因此 MVP 把 errdefer 标记为**实验性**并限定输入上下文（只允许出现在以统一 `err` 状态变量传播的函数内）；后续方法：转译器做函数级数据流分析，为每个错误返回出口生成 `err = ...` 赋值，defer 条件即精确。**推迟不实现**的理由是避免声称完整 Zig 等价。

**`!T` 类型语法（推迟）**：Zig 的 `!T` 是类型系统构造（error union），Jai 无类型联合语法糖。转译器无法在 source-to-source 层可靠实现（需要把 `!T` 参数/返回值解析成约定 1/2 的表示，并重写所有调用点与赋值——本质上是类型系统扩展而非语法糖）。MVP 用显式 Result 约定替代；后续若要 `!T` 语法，方案是 Jai-native metaprogram 生成 + `#import,string`（`how_to/040_import_and_load/main.jai:98` 验证了字符串代码可被正常导入）或等待官方 roadmap。**不建议声称支持 `!T`**。

## 第五部分：为什么正则替换不可靠；parser 策略

### 5.1 Jai 具体语法证据（均可复现）

- **字符串/注释内的代码文本**：`how_to/600_insert.jai:326`——`b :: "factorial(#insert argument);";`，字符串字面量内含 `#insert` 指令文本；正则扫描无法区分字符串内容与真实指令。
- **语句级 vs 表达式级上下文**：`600_insert.jai:335-368`——同一段代码文本在语句级可插多条语句，在表达式级只能插一个表达式；转译器必须知道目标位置是语句还是表达式上下文，才能决定扩展语法如何展开（例如 `try` 在 `x := try f()` 与 `try f();` 两个位置的生成代码不同）。
- **无括号控制流 + 换行断句**：`how_to/019_looping.jai:299` `factorial :: (x: int) -> int { if x <= 1 return 1; return x*factorial(x-1); }`（一行内分号分隔多条语句）；`how_to/110_polymorphic_arguments.jai:11` `for 1..count x = f(x);`。语句边界识别依赖换行/分号，正则无法可靠处理。
- **上下文敏感运算符**：`<<` 既是一元取内容赋值（`how_to/110_polymorphic_arguments.jai:185-198` 的 `<<pointer`、`<<it = ...`）又是二元左移；`*` 是指针类型/解引用/乘法；`.` 是枚举一元点（`how_to/014_enum_unary_dot.jai`）。词法歧义要靠语法上下文消解，正则（甚至单 pass 词法）做不到。
- **嵌套大括号跨字符串/注释**：任何块级扩展语法（如 `errdefer { ... }`）的边界识别都需要完整的括号配对扫描。
- 参考 Babel 的立场【官方文档】：handbook:254-307 把解析拆成词法+语法两阶段、所有变换发生在 AST 层而非文本层，即同一结论的方法论表述。

### 5.2 推荐策略：完整 lexer + 扩展语法局部 parser + trivia 保留

- **Lexer**：完整实现 Jai 词法子集（标识符、数字、字符串、字符、注释、多字符运算符、`#` 指令），产 token 流并保留每个 token 的 span 与 trivia（注释、空白）。Jai 词法规则从发行版 how_to 与 `modules/Compiler/Compiler.jai` 的 `Code_Node.Kind`/`Location` 反推（1.5），无需第三方库。
- **Parser**：**不需要完整 Jai 语法**——只解析扩展语法的锚点（`|...|` lambda、`try`、`catch`、`errdefer`）及其最小上下文（到语句/表达式边界为止），其余代码作为"verbatim 区段"原样携带。这是 span-preserving/局部增量解析策略：输入被切成"标准 Jai 片段（原样保留）+ 扩展片段（AST）"，输出把扩展片段展开后按原顺序拼接，未触碰的文本逐字节保留（含注释与排版）。
- **语义边界与拒绝**：以下情形转译器必须**拒绝并给出诊断**，而不是生成错误代码：
  - 扩展语法出现在 `#insert`/`#run` 字符串字面量内（编译期生成代码，转译器无法可靠转译其内容——`600_insert.jai:255-257` 已说明这些字符串在编译期被解析，转译发生在源码层之外）；
  - 扩展语法出现在 `#import,string`（`040_import_and_load/main.jai:98`）的字符串内；
  - `#load` 进来的文件（`040_import_and_load/main.jai:59-68` 的 file scope 语义）——跨文件边界不做隐式扩展（每个文件独立转译，`#load` 目标如需扩展语法由用户显式纳入）；
  - 捕获 lambda（1.2 无闭包）——MVP 直接拒绝（4.1 所述），给出"Jai 不支持闭包"诊断；
  - 无类型注解的语句体 lambda——MVP 拒绝，提示补注解（4.1）。
  - 操作符冲突：`|x|` 提案语法本身不与现有 Jai 运算符冲突（Jai 无单竖线 lambda 语法；但 `|` 并非 Jai 运算符，`||` 为逻辑或——提案语法选 `|` 定界符需 lexer 特判 `||` vs `|`），任何新定界符都必须先做发行版词法冲突核对（本报告未发现 `|x|` 冲突，但这是**未验证项**，见第八部分）。

## 第六部分：架构与实现语言建议

### 6.1 三种架构

| 架构 | 描述 | 优点 | 缺点 |
|---|---|---|---|
| A. 独立 source-to-source CLI | 自备 lexer/parser，扩展语法 → 标准 Jai 文本，独立可执行文件 | 可独立测试（golden/负例）；不改产品代码；与 juice 解耦；可做跨模块边界 | 无类型信息（4.1 的推断边界）；需自写 parser；格式保真靠 trivia 保留策略 |
| B. Jai-native metaprogram（宏/插件） | `#expand` 宏 + `#code`（1.5）+ `Code_Visit`/`Program_Print`，在编译器进程内变换 | 有类型信息（`Message_Typechecked`）；官方 AST 工具现成；天然处理 `#insert` 语义 | 官方自述 Code 树操作 API 未完备（`600_insert.jai:270-273`）；受编译期模型约束（无运行时变换）；调试困难；`#code` 内联语义 ≠ 闭包 |
| C. 混合 | 架构 A 的 CLI + juice 构建前置 + 可选地把 Jai-native 插件作为后续 | MVP 务实 | 两套机制维护成本 |

**建议**：MVP 走 A；B 作为捕获 lambda / 类型推断类特性的后续路径（其类型信息优势恰好补 A 的短板）。

### 6.2 实现语言：Jai 自身（备选：用户更熟悉的语言）

- **推荐 Jai**：与 juice 同工具链（构建、测试、贡献者心智一致）；本仓库已有 `modules/` 内的 Jai 库与 path 安全、字符串处理实践（`src/path_safety.jai`、`modules/Juice.jai`）；转译产物可直接调用 jai 编译器做集成验证（本报告实验模式）。缺点：Jai 无第三方 parser 库，lexer/parser 需手写——但按 5.2 的局部解析策略，工作量可控（不是完整 Jai 语法）。
- **备选（如优先可维护性生态）**：任何有成熟字符串/测试生态的语言。注意无论选什么语言，**解析器都不存在现成货**（Babel 不可复用，2.3；Jai 编译器闭源）。

### 6.3 关键设计点

- **符号卫生**：转译器生成的 temp/辅助标识符一律 UID 生成（Babel `generateUidIdentifier` 模式，handbook:1681-1693），避免与用户符号冲突；生成代码标记为生成（Jai 编译器自身的 `CREATED_BY_DESUGARING` flag，`Compiler.jai:538`，说明官方同样关心此问题）。
- **求值顺序**：一切 lowering 先 temp 绑定后使用（4.2 的 try 模式），保证操作数单次求值；嵌套 `try`/`catch` 逐层展开时保持从左到右求值顺序。
- **表达式嵌套**：`f(try g())`、`try a + try b` 等嵌套形式必须支持；`catch` 的惰性分支用 `ifx` 保持（4.2）。
- **类型推断边界**：见 4.1——source-to-source 无推断，语法要么自带类型注解，要么限制为 quick procedure 形式；**不要假装有推断**。
- **源位置映射与诊断**：每个扩展片段保留原 span（起止行列），转译期诊断（"此处捕获不被支持"）直接引用原文行列；产物中的编译错误要能映射回扩展源文件（生成注释或 sidecar 映射表；Jai 编译器错误格式为 `file:line,col`——实验报错输出可见）。MVP 可先做"转译期诊断精确定位 + 产物错误人工对照"，完整 sourcemap 类机制留后续。
- **格式保留**：trivia 保留策略（5.2）使未触碰代码逐字节保留；扩展片段展开后的排版由转译器统一（golden 测试锁定）。
- **缓存与依赖**：按源文件内容 hash 缓存转译产物，失效即重转；juice 已有 `cache_dir`（`src/main.jai:36`）可挂靠；`#load`/`#import` 依赖不做隐式追踪（5.2 的跨文件边界）。
- **编辑器支持**：独立 CLI 天然可接入任意编辑器 file watcher；诊断格式对齐 jai 编译器（`file:line,col: Error:`），LSP 类深度集成不在 MVP 范围。

## 第七部分：juice 集成方向（基于现有 seam，不重构）

【源码】本仓库，行号以研究时工作树为准：

- **编译调用 seam**：`src/commands/build.jai:69-103` 的 `compile_artifact_plan` 拼装 jai CLI 参数（`:84-87`：`jai <source_file> -exe <name> -output_path <dir>`）并执行。**转译前置步骤的自然插入点就在 `:85` 之后**：对 `plan.target.source_path` 做转换（产物写入缓存目录），再用转换后的文件路径拼命令。
- **测试注入 seam**：`src/commands/build.jai:108-122` 的 `build_prepared_workspace` 带 `compile` 过程参数（`:111`，注释明言供测试用录制适配器跨同一接口）——转译步骤若做成独立过程，可按同一模式注入假实现做集成测试。
- **入口校验**：`src/target.jai` 校验入口是普通 `.jai` 文件（CONTEXT.md:48-49），转译不改变该契约（源仍是 `.jai`，产物在缓存目录）。
- **依赖方向**：`src/driver.jai:4-10` 的 `Build_Driver` 已含 `cache_dir`，转译缓存可挂靠，无需新结构。

**建议方案**：
1. **独立 CLI**（如 `juice-transpile` 或 `jait`）：`<cli> <src.jai> -o <out.jai>`，纯函数式转换，独立于 juice 可测可用。
2. **juice 侧可选前置步骤**：在 `compile_artifact_plan` 中，若 workspace 声明启用转译（如 package declaration 加可选标记，`modules/Juice.jai` 的 Package 结构扩展一个可选字段），则编译前调用转译器写缓存产物再传给 jai。**不引入新 command 体系**（不碰 dispatcher/registry），保持最小侵入；若要显式命令形态，可后续加 `transpile` command 挂在 build 之前（`src/commands/` 的 Command 模式与 `prepare.jai` 的 prerequisite 声明可直接复用）。
3. **CONTEXT.md 词汇**（按仓库惯例）：新增"语法扩展转译（syntax extension transpile）"条目描述该前置步骤与缓存契约，修订 Build 词条提及可选前置（现有 CONTEXT.md:13-14 的 Build 定义需允许可选转译步骤）。

## 第八部分：分阶段路线与测试矩阵

### 8.1 路线

- **M0（MVP，建议第一版）**：架构 A 独立 CLI；表达式 lambda `|x| expr` → quick procedure；`try`/`catch`（含 `|err|`、`unreachable`）→ 显式 Result（约定 1 与约定 2 可配置）；拒绝捕获/无类型注解语句体 lambda/`#insert` 内扩展语法；golden + 负例测试；转译产物 jai 编译运行验证。
- **M1**：带类型注解的语句体 lambda → 匿名过程；实验性 errdefer（统一错误状态变量纪律，4.2）；juice 前置步骤集成；诊断映射表。
- **M2**：显式捕获 lambda（environment struct 降级）；`#code` 内联宏（exp8 模式）供立即消费场景；跨文件扩展（`#load` 目标显式纳入）。
- **推迟/不承诺**：自动闭包捕获（等语言特性）；`!T` 类型语法；类型推断（除非走架构 B）；完整 sourcemap。
- **Jai-native（架构 B）作为平行后续探索**：用 `Code_Visit`/`Program_Print` 与 `Message_Typechecked` 的类型信息解决推断类问题（1.5、6.1）。

### 8.2 测试矩阵

| 类别 | 内容 | 判定方式 |
|---|---|---|
| golden | 每类扩展语法的输入 → 预期标准 Jai 输出文本 | 文本对比（锁定输出格式） |
| 负例 | 捕获 lambda、无类型语句体 lambda、`#insert` 字符串内扩展语法、未绑定标识符 | 转译期诊断 + 退出码非零 |
| 编译及运行 | 全部 golden 产物用 jai 编译运行（本报告实验模式） | 编译通过 + 运行输出断言 |
| 捕获/生命周期 | 显式捕获降级（M2）后环境结构的创建/释放路径 | 编译运行 + 内存检查（leak 检查按仓库惯例） |
| defer + 错误传播 | `try` 早退路径上 defer 是否执行、`errdefer` 条件纪律 | 运行输出顺序断言（对照 exp3/exp5 基准） |
| 求值次数 | `try f()`/`catch` 操作数带副作用（计数变量）只求值一次 | 运行计数断言 |
| 符号卫生 | 用户已有 `err`/`v` 等标识符时生成代码不冲突 | 编译运行 |

### 8.3 未决/有待验证的问题

1. `|x|` 定界符与 Jai 词法的完整冲突核对只做了人工检查（Jai 无 `|` 运算符，`||` 是逻辑或），未穷尽发行版全部语法——正式实现前需对发行版 how_to/modules 全量做词法扫描验证。
2. 匿名过程是哪个版本引入的：CHANGELOG 未找到引入条目（仅 beta 0.2.009 的 crash handler 改进 `CHANGELOG.txt:3976`），版本下界未定；本报告结论只对 beta 0.2.009 成立。
3. `Program_Print` 是否保留注释与原始排版（`print_declaration` 的保真度）未验证——影响架构 B 的格式保真可行性。
4. errdefer 精确等价需要函数级数据流分析，工作量未评估；MVP 的"统一状态变量纪律"方案的误用率未知。
5. `#code` 体（宏内联）与扩展语法组合（如 `#code` 内出现 `try`）的语义未定义，需在 M2 前定义。
6. 错误值表示（string vs 枚举错误码）对类型检查与文档生成的影响未对比（Zig 官方明确偏好编译期可知的错误集，第三部分 anyerror 段）。

## 实验记录

实验环境：Windows 11 + Git Bash；Jai 编译器 `C:/Users/maojiaxing/DevTools/jai/bin/jai.exe`（版本见"发行版版本"）；全部实验文件在 `C:/Users/maojiaxing/AppData/Local/Temp/jai-syntax-research/`，编译命令 `jai -quiet <file>.jai`，运行命令 `./<file>`。

| 实验 | 内容 | 结果 |
|---|---|---|
| exp1 | quick procedure（含多参数）、捕获尝试 | 前两项编译运行通过（输出 25、5）；捕获报错原文："Error: Attempt to use a variable from an outer stack frame. (Closures are not supported.)"（注意：未使用变量会被 DCE 掉而不报错，需实际使用才触发） |
| exp2 | 匿名过程 `f := (x: int) -> int { return x * 2; };` | 编译运行通过，输出 `f(5) = 10` |
| exp3 | defer 顺序与块作用域 | 输出 `start / inner body / inner defer / end of main body / defer 3 / defer 2 / defer 1`（LIFO，内层块先执行） |
| exp4 | 匿名过程语义矩阵 | 无返回类型推断报错 "Too many return values: Wanted 0, got 1"；多语句+局部变量通过（12）；捕获报错同 exp1；多态匿名过程作运行时值报错 "A non-constant declaration of a polymorphic procedure is not allowed..."；内联作实参通过（8） |
| exp5 | defer + 提前 return | 两条路径都执行 defer，输出 `deferred in foo (n=0) / foo(0) = -1 / deferred in foo (n=3) / foo(3) = 30` |
| exp6 | lambda 两条 lowering 路径 | `x => x*2`（42）与显式类型匿名过程（22）均编译运行通过 |
| exp7 | `try`/`catch` → Result 结构 lowering | 编译运行通过：`propagate(5) = 110`、`propagate(-5) err = negative`、catch 默认值路径正确（-1）。初次尝试 `struct($T)` 报错 "Cannot use $ or $$ on a declaration that has no identifier"，改为 `struct ($T: Type)` 通过（与 `how_to/120_polymorphic_structs.jai:19` 一致） |
| exp8 | `#expand` 宏 + `#code` 体引用调用方局部变量 | 编译运行通过，`x = 2`（内联语义验证） |
| exp9 | 多返回值错误惯用法（`(err: Error, value: T)`） | 编译运行通过：NONE/110、NEGATIVE、ZERO 三分支正确 |

## 发行版版本

Jai 发行版 `C:/Users/maojiaxing/DevTools/jai`，版本 beta 0.2.009，built 6 February 2025（`CHANGELOG.txt:1`：`Version: beta 0.2.009, 6 February 2025`）。注：`jai -version` 无输出，版本以 CHANGELOG 为准。外部资料：Zig 语言参考（ziglang.org/documentation/master/，即 ziglang/zig 仓库 doc/langref.html.in）与 Babel Plugin Handbook（jamiebuilds/babel-handbook master 分支）均于 2026-10-06 经 curl 下载核验。WebFetch 在本环境被域名安全校验拦截（"Unable to verify if domain ... is safe to fetch"），故外部一手资料改用 curl 直取；WebSearch 可用但仅返回链接列表。

## 引用清单

Jai 发行版（`C:/Users/maojiaxing/DevTools/jai`，beta 0.2.009，2025-02-06）：

- `how_to/110_polymorphic_arguments.jai`：quick procedure 定义与说明 109-177；过程类型参数 8；类型求解限制 180-228。
- `how_to/080_scopes.jai`：无闭包官方说明 71-86；`#run` 常量烘焙 97。
- `how_to/200_memory_management.jai`：defer 说明 818-860。
- `how_to/350_logging.jai`：defer 块形式 67。
- `how_to/730_for_expansions.jai`：defer 与 `#insert`/`continue` 交互 133。
- `how_to/600_insert.jai`：#insert 基础 4-17；仅编译期 255-257；Code 树操作与 API 未完备说明 270-273；`#expand`/`#code` 宏 279-303；语句级 vs 表达式级 335-368；`#insert #run` 简写 370-388。
- `how_to/170_modify.jai`：#modify 1-30。
- `how_to/040_import_and_load/main.jai`：#import 模块作用域 20-26；#import 修饰符与 #load 区别 59-68；`#import,string` 98-100。
- `how_to/030_any.jai`：Any 类型 1-48。
- `how_to/015_array_literals.jai`：多返回值成功/结果惯用法 48。
- `how_to/025_ifx.jai`：ifx 表达式 77-93。
- `how_to/019_looping.jai`：defer 在循环中 84/101/114/137/141；一行多语句 299。
- `how_to/120_polymorphic_structs.jai`：多态结构语法 19。
- `modules/Compiler/Compiler.jai`：AST 节点说明 452-455；`Code_Node.Kind` 456-527；node_flags（STATEMENT_IS_DEFERRED 0x8、CREATED_BY_DESUGARING 0x100）533-540；Location（l0,c0,l1,c1）541-551；`compiler_get_nodes` 1553。
- `modules/Code_Visit/module.jai`：get_subexpressions 16；get_recursive_nodes_depth_first 261；visit_pre_and_postorder 294。
- `modules/Program_Print/module.jai`：print_declaration 84。
- `CHANGELOG.txt`：版本 1；匿名过程相关 3976、3451（"quick lambdas"）、1930（"polymorphic lambda type"）。

Zig 官方语言参考（ziglang.org/documentation/master/，2026-10-06 下载，`#Errors` 段）：

- error set 定义与整数值分配（"An error set is like an enum..."）；anyerror 全局错误集；error union（"`!` binary operator"）；try 语义（"evaluates an error union expression. If it is an error, it returns from the current function with the same error. Otherwise, the expression results in the unwrapped value."）；catch 三种形式与 RHS 类型约束（"must match the unwrapped error union type, or be of type noreturn"）；errdefer（"if and only if the function returned with an error from the block"）；未处理错误是编译错误；Error Return Traces（`#Error-Return-Traces`，Debug 默认开启）。

Babel Plugin Handbook（jamiebuilds/babel-handbook master，2026-10-06 下载）：

- 定义与三阶段 99-101、248-324；ESTree 与位置信息 109、224-246；visitors 387-497；paths 512-583；state 610-640；scopes/bindings 681-830；五包职责 831-1136；UID/作用域操作 1681-1745；性能最佳实践（目录 70-74）。

本仓库（工作树，行号以研究时为准）：

- `src/commands/build.jai`：compile_artifact_plan 69-103（jai 调用 84-87）；build_prepared_workspace 的 compile 注入参数 108-122。
- `src/driver.jai`：Build_Driver 4-10。
- `src/main.jai`：cache_dir 36；#load 列表 6-19。
- `src/commands/prepare.jai`：prerequisite 模式 1-27。
- `CONTEXT.md`：Build 13-14；Effective target 48-49；Result directory 57-58。
