---
title: Metaprogram 生成器收敛：Build/Test 共用编译 harness
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: []
---

> 架构体检（improve-codebase-architecture）候选 2；文档对齐见 IMPLEMENTATION.md 与 CONTEXT.md「Metaprogram generator」词条。

## Problem Statement

同一个「一次性 workspace + intercept + 消息循环」编译 metaprogram 骨架在进程内存在两份生成器（`generate_build_metaprogram` / `generate_test_metaprogram`）加一份 bootstrap 手写版（build.jai，ADR 0006 内嵌复制）。两个 adapter 已经成立，seam 却是隐形的——哨兵约定（testing_view_dir "" = 未启用）与「生成输出与特例前逐字节一致」靠注释互相承诺。辅助重复：`build_transpile_dir` ≡ `test_transpile_dir`（逐字同体）、modules 目录推导 ×3（build.jai 内联、test.jai `juice_modules_dir`、manifest.jai 内联）。

## Solution

1. 新增 `src/metaprogram.jai`：单一生成器 `generate_compiler_metaprogram(Compiler_Metaprogram_Options)`，吸收消息循环骨架与 "" 哨兵约定；Build 形状（executable name/path + 对齐行）与 Test 形状（NO_OUTPUT）的输出与重构前逐字节一致。
2. 删除 `generate_build_metaprogram` / `generate_test_metaprogram`；两个 command 各自组装 options 调用（build 的 `compiler_import_directories` 留在 build.jai）。
3. `juice_modules_dir` 移入 `src/path_safety.jai`，三处调用点收敛（含 manifest 求值器 `-import_dir`）。
4. transpile 目录根移入 `src/transpile_cache.jai` 为 `transpile_dir(package_root)`，删除 `build_transpile_dir` / `test_transpile_dir` 两个包装。
5. bootstrap build.jai 不动（ADR 0006 对称复制），仅更新指向旧函数名的过时注释。

## Acceptance criteria

- [x] `jai build.jai`（debug + release）全绿；产物 target/juice.exe 烟测（`juice test` 于仓库根跑通）
- [x] `juice test` 0 failed；golden 夹具（tests/data/transpile/golden/*/first.jai）不更新内容、原样通过——字节一致不变量成立
- [x] harness 内联测试覆盖：executable 形状逐字节锁定、test 形状 NO_OUTPUT 与 import 行序、哨兵开/关
- [x] IMPLEMENTATION.md 文件表与 load 列表、CONTEXT.md「Metaprogram generator」词条对齐

## Out of Scope

- bootstrap build.jai 的内嵌骨架共享（ADR 0006：不 #load 运行时源码）
- Testing 模块视图特例收口（架构体检候选 3）
- Build_Driver 拆解（架构体检候选 1）

## Further Notes

- 语言：中文交流与文档。
- 字节一致是硬验收线：重构前后 test 形状（golden 三参调用）输出逐字节一致，golden 夹具只许更新调用点、不许更新内容。

## Resolution

已实施：新增 `src/metaprogram.jai` 共享生成器（`Compiler_Metaprogram_Options` + `generate_compiler_metaprogram`），删除 `generate_build_metaprogram`/`generate_test_metaprogram` 与 `build_transpile_dir`/`test_transpile_dir`；`juice_modules_dir` 移入 path_safety.jai（三处调用点收敛，含 manifest 求值器）；transpile 树根以 `transpile_tree_dir` 入 transpile_cache.jai（初名 transpile_dir 与局部变量同名遮蔽不合法，改名避让）。字节一致不变量成立：golden first.jai 内容零更新、30 处 GOLDEN PASS。三路径全绿：`jai build.jai`（debug/release）、`juice build` 自构建（复制 exe 避 LNK1104）、`juice test` 152 块 0 failed（debug 与 release 产物各跑一遍）。文档对齐：IMPLEMENTATION.md 模块表新增 metaprogram/transpile_cache/test 行并更新 build/path_safety 描述；CONTEXT.md 新增「Metaprogram generator」词条与 Relationships 行。注意：验证前清过 target/transpile——EXPAND 缓存键不含 next_test_number 的既有缺陷在新增测试文件后导致陈旧视图编号冲突（memory 已记录，根治另立票）。
