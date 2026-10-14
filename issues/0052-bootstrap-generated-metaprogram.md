---
title: 编译骨架收敛：bootstrap 改走「生成 + 子进程」，+5 偏移消失
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: [0050-strip-front-shared-module.md]
---

> 架构体检（improve-codebase-architecture）候选 4 方向 a（2026-10-14 会话，用户拍板）；机制实验已通过（临时目录：metaprogram #run 内 run_command spawn 子进程 jai 编译生成的 metaprogram，退出码与产物验证均成功；`exit(1)` 退出码正确但会吞掉父 metaprogram 的收集打印——票 0015 已证）。

## Problem Statement

bootstrap 手写的 workspace/intercept/消息循环骨架与 Metaprogram generator 产出的文本逐字节同形，对称靠注释承诺（票 0036 明确搁置）；入口经 add_build_string 喂虚拟字符串，诊断行号恒 +5 偏移——runtime 路径不付这笔税（磁盘视图诊断精确，研究 0028 §2.4 已证替代「同样可行」）。机制实验证实 bootstrap 可以生成 metaprogram 文本后 spawn 子进程 jai 编译，与 Build command 同形状。

## Solution

重开 ADR 0006 决定 2（入口 add_build_string、+5 映射）：

1. **生成器 test-free 化**：src/metaprogram.jai 移除 Testing 导入与 3 块内联测试（迁 src/metaprogram_tests.jai），成为 bootstrap 的 #load 目标；`to_forward_slashes` 改 `front_slashes`（自包含，摆脱 manifest.jai 运行时依赖）；新增 `very_optimized: bool = false` 字段——true 时在 set_build_options 前发射 `set_optimization(*options, .VERY_OPTIMIZED);`（默认 false 零发射，字节锁不变量保持，bootstrap 的 release 验证路径得以保留）。
2. **Strip front 收窄**：PLAIN 布局删除「入口进内存」分支与 entry_rel/entry_view 字段——票 0052 起 bootstrap 入口同样落盘，经生成的 metaprogram 以 add_build_file 编译（诊断精确文件+行号）。
3. **bootstrap 重写**：build.jai #run = 早退守卫 → 剥离前端（bootstrap_build_entry 返回入口路径）→ Testing 模块 STRIP 特例 → 组装 Compiler_Metaprogram_Options（import_dirs 绝对化：src/modules/root）→ 写 target/bootstrap-meta.jai → spawn `jai` → 退出码判成败（失败 exit(1) 传递退出码，三路径 seam 保持）。进程内拦截/消息循环/add_build_string 全部消失。
4. **文档**：ADR 0006 决定 2 重写（修订注记，机制实验事实）；CONTEXT.md Bootstrap build / Strip front / Metaprogram generator 词条与 Relationships；docs/spec-src-inline-test-blocks.md 自举剥离机制段；IMPLEMENTATION.md。
5. **探针**：一次性注入编译错误验证磁盘视图诊断精确（无 +5）与失败退出码后撤销（0031 手法）。

## Acceptance criteria

- [ ] 三路径全绿：`jai build.jai`（debug/release）、`juice build` 自构建、`juice test` 0 failed（debug 与 release 产物各一遍、30 GOLDEN PASS）
- [ ] build.jai 无 compiler_create_workspace / begin_intercept / 消息循环 / add_build_string；grep 全仓无 +5 偏移残留（研究文档除外）
- [ ] 探针：注入错误 → `jai build.jai` 退出码非零、诊断精确文件+行号；撤销后复绿
- [ ] metaprogram_tests.jai：迁入 3 块 + 新增 very_optimized 发射直测；PLAIN 入口落盘测试改写
- [ ] 既有测试原样通过；文档对齐

## Out of Scope

- 内容寻址缓存并入 bootstrap（PLAIN 恒写语义不变，票 0031 延后决定维持）
- 父 metaprogram 打印时序（jai 收集打印在正常结束时才刷出：子进程输出先于 🚀/✅ 出现；失败路径 ❌ 行被 exit(1) 吞掉——退出码与子进程错误输出仍完整，接受为已知偏差）

## Further Notes

- 语言：中文交流与文档。
- 验证前清 `target/transpile`（memory 已记）。
- 机制实验文件在 `C:/Users/maojiaxing/AppData/Local/Temp/jai-meta-spawn/`（未进仓库）。

## Resolution

**编译骨架收敛落地（2026-10-14，用户拍板方向 a），三路径全绿，+5 偏移退役。**

1. **实现**（题述方案 1–4 全落地）：
   - `src/metaprogram.jai`：移除 Testing 导入与 3 块内联测试（迁 `src/metaprogram_tests.jai`）→ test-free、bootstrap 可 #load；`to_forward_slashes` ×3 改 `front_slashes`（自包含，摆脱 manifest.jai 运行时依赖）；新增 `very_optimized: bool = false`——true 时在 set_build_options 前发射 `set_optimization(*options, .VERY_OPTIMIZED);`（默认零发射，字节锁不变量保持；既有 3 块测试原样迁入 + 新增发射直测）。
   - `src/transpile_front.jai`：PLAIN 布局删除「入口进内存」分支与 entry_rel/entry_view 字段——入口同样落盘。
   - `src/transpile_front_tests.jai`：PLAIN 入口测试改写为落盘语义。
   - 根 `build.jai`：重写为「探测 → Testing 特例 → 组装 options（import_dirs 绝对化）→ 写 target/bootstrap-meta.jai → spawn `jai` → 退出码判成败（失败 exit(1)）」。进程内拦截/消息循环/add_build_string 全部消失；文件 184 → 131 行。
2. **Jai 机制事实（实施中暴露，实验证实）**：
   - `#run` 未创建任何 workspace 时，jai 回落 Default_Metaprogram 编译命令行文件本身（build.jai 无 main → "No program entry point"、退出码 1）——创建空 workspace（"Bootstrap Delegation"）是「构建已自理」的信号，压制回落（基线 worktree 对比：改造前 exit 0 无此错误）。
   - 父 metaprogram 的打印由 jai 收集、正常结束时才刷出（🚀/✅ 出现在编译输出之后）；exit(1) 吞掉父进程全部打印（票 0015 机制）——退出码与子进程错误输出仍完整，接受为已知偏差。
3. **探针**（0031 手法，注入后撤销）：`src/xdg.jai` 尾部注入未声明调用 → `jai build.jai` 退出码 1、诊断 `target/transpile/bootstrap/src/xdg.jai:63,1: Error: Undeclared identifier 'zap_undeclared_probe'.`——视图 1:1 行号精确、无 +5 偏移；撤销后复绿。
4. **文档**：ADR 0006 决定 2 重写 + 修订注记 + Considered Options 增 (d)；CONTEXT.md Bootstrap build / Strip front / Metaprogram generator 词条与 Relationships；docs/spec-src-inline-test-blocks.md 两处；IMPLEMENTATION.md 构建路径段与模块表。
5. **验证**：`jai build.jai`（debug/release）exit 0；`juice test` exit 0（debug 与 release 产物各一遍、30 处 GOLDEN PASS、latch 5/0）；`juice build` 自构建成功；grep 生产代码无 add_build_string/+5 逻辑残留（仅 6 处退役注释）。

**已知偏差**：父 metaprogram 打印时序（见机制事实 2）与失败路径 ❌ 行被吞——退出码 seam 完整。
