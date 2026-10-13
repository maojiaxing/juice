---
title: 研究：Jai metaprogram 内加载转译器并喂视图的机制
status: closed
labels: [wayfinder:research]
assignee: maojiaxing
blocked-by: []
---

> 父票：[Spec: src 内联 test block 与构建剥离](0025-spec-src-inline-test-blocks.md)

## Question

自举剥离（build.jai 内嵌 STRIP 视图）依赖三个 Jai 机制事实，全部待查证：

1. `#load "src/transpile.jai"` 在 metaprogram（`#run` 块）中的语义：被 load 代码编译进 metaprogram 执行环境，还是进入被构建程序？`#run` 块内能否直接调用被 load 文件的纯函数？
2. Compiler 模块喂视图的方式：是否存在 `add_build_string`（虚拟源文本）？其语义（虚拟路径、该字符串内 `#load`/`#import` 如何解析）；若不存在，替代方案是写临时视图文件 + `add_build_file` + STRIP 模式的 in-package `#load` 重写指到视图路径（transpile STRIP 已做该重写，见 docs/transpiled-output-formatting.md 与 src/transpile.jai 的 Load_Target）。
3. 现有 build.jai 的 Compiler 用法（begin_intercept、add_build_file、import path、编译期消息循环，build.jai:15-18,64,72）如何与新增剥离步骤组合：视图替换源文件后，#load 树跟随、诊断位置映射（视图与原文件行号一一对应，ADR 0005）是否成立。

查证来源（primary）：本机 jai 编译器安装目录的 Compiler 模块 module.jai 文档注释（先定位安装路径）；juice build.jai 现有用法；src/transpile.jai 的 STRIP 输出契约。禁止以 LLM 记忆或二手资料下结论。

## Resolution

> 完整研究报告：[docs/research/jai-metaprogram-view-feeding.md](../docs/research/jai-metaprogram-view-feeding.md)。
> 一手来源：本机 jai 发行版 beta 0.2.009（`C:/Users/maojiaxing/DevTools/jai`）的 modules/Compiler 源码、how_to 040/450/470、examples/add_build_string_into_specific_scope、CHANGELOG，加本机编译运行实验（临时目录，未进仓库）。

1. **`#load` 在 metaprogram 中的语义：可行，正是设计所需。** 被 load 代码编译进 **metaprogram 执行环境**（metaprogram 自身就是编译期执行的程序；`#load` 是文本包含进"当前程序"的 file scope，how_to/040:66-71），**不进入**被构建程序——目标 workspace 由 `compiler_create_workspace` 创建，是独立编译单元，只含 `add_build_*` 喂入的代码（how_to/470/first.jai:8-10）。`#run` 块内可直接调用被 load 文件的纯函数（实验：`#load` 顶层与写在 `#run` 内部均可；真实 `src/transpile.jai` 的未标 `#compile_time` 普通过程 `transpile_source` 在 `#run` 中编译期执行成功）；负例实验：目标程序引用被 load 符号报 `Undeclared identifier 'add1'`。
2. **`add_build_string` 存在：可行。** 两个重载（Compiler.jai:1600 `code` 版、:1601 Message 作用域版），无 code/message 时字符串进目标程序 **toplevel 作用域**（入口视图所需）。语义实测：虚拟路径 `<intermediate_path>/.added_strings_w<workspace_id>.jai`，首串前有固定 5 行头 → 行号偏移恒 **+5**、列号精确（多串追加时偏移按前序内容累积）；字符串内 `#import` 走 import_path 正常解析；**相对 `#load` 以 `add_build_string` 调用点文件所在目录为基准**（与 cwd、虚拟文件位置无关）；`#load` 目标必须是字符串字面量（`#load CODE;` 报错），故闭包内其余视图必须落盘、in-package `#load` 重写为绝对视图路径（transpile STRIP 已实现，Load_Target，src/transpile.jai:22-41）。替代方案（临时视图文件 + `add_build_file`）同样可行，即现有 `juice build` 前端（src/commands/build.jai:150）。
3. **与 build.jai 现有用法的组合成立：可行。** 剥离前端插入点：`set_build_options`（build.jai:66）之后、`compiler_begin_intercept`（:71）之前；入口视图用 `add_build_string` 替换现有 `add_build_file("src/main.jai", ...)`（:72），消息循环（:78-90）无需改动。端到端实验（真实 transpile.jai + 双文件闭包 + STRIP）：编译链接运行成功、**#load 树跟随成立**（FILE 消息显示子视图加载）；**诊断位置映射成立（ADR 0005）**——入口字符串错误报虚拟路径、行号 = 字符串行 +5（常量偏移），磁盘视图错误报精确文件+行号，行号一一对应不变。附带推论：因字符串内相对 `#load` 基准变为 build.jai 所在目录，入口视图的 in-package `#load` 重写是必须的（已有机制，无新增需求）。

