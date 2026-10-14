---
title: Testing 模块 STRIP 特例收口：bootstrap 与 Build command 共用一份
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: [0050-strip-front-shared-module.md]
---

> 架构体检（improve-codebase-architecture）候选 3（2026-10-14 会话）；前提票 0050 已落地（test-free 共享剥离前端存在，bootstrap 可 #load 复用）。

## Problem Statement

Testing 模块 STRIP 特例双份同路径、同哨兵，靠注释互相承诺「保持对称」：

- 根 build.jai 内嵌副本（票 0033 对称特例：读 modules/Testing.jai → 含 test block → STRIP 视图写 target/testing-module/Testing.jai → import path 前置）
- src/commands/build.jai 的 `testing_module_strip_view_dir`（同路径同语义；模块来源按 `juice_modules_dir()` 推导，与 bootstrap 的 cwd 相对路径是唯一差异）

「」哨兵约定（"" = 未启用）散在三处注释（metaprogram.jai、test.jai、build.jai）。票 0039 已把 Test 的 EXPAND 变体收敛为 test.jai 内 helper（形态 C），但明确否决共享模块并把 build 侧 STRIP 函数迁移列为 Out of Scope——当时没有 test-free 共享模块、bootstrap 无法复用。票 0050 创造了该前提。

## Solution

1. `testing_module_strip_view_dir` 迁入 src/transpile_front.jai（Strip front 共享模块），签名参数化模块来源与报错前缀：`(package_root: string, module_source: string, error_prefix: string = "[juice ERROR] ") -> string`。bootstrap 传 cwd 相对 `"modules/Testing.jai"` + `"[Build System] ❌ "`，Build command 传 `juice_modules_dir()/Testing.jai`。存在性预检保留（runtime 语义：模块缺失/不可读时零动作零日志），mkdir/write/诊断文案统一（未钉住，与票 0050 同策略）。
2. 根 build.jai 的内嵌副本（约 33 行）替换为一行调用；`testing_view_dir` 哨兵约定随注释更新。
3. commands/build.jai 的本地函数删除，`compile_artifact_plan` 改调共享函数（唯一调用点，不保留包装）。
4. 新增直测 ×2（transpile_front_tests.jai）：test-free 模块零动作、含 test block 模块写 STRIP 视图（真实转译器，断言视图内容与落点）。EXPAND 变体留在 test.jai（测试程序生成的一部分，另两路径不需要，0039 已内聚）。

## Acceptance criteria

- [ ] 三路径全绿：`jai build.jai`（debug/release）、`juice build` 自构建、`juice test` 0 failed
- [ ] grep 无 bootstrap 内嵌特例残留（build.jai 仅调用点）；`testing_module_strip_view_dir` 仅驻 transpile_front.jai
- [ ] 新增直测 ×2 全绿；既有测试原样通过（fixture 计数不变、30 GOLDEN PASS）
- [ ] IMPLEMENTATION.md / CONTEXT.md 对齐（Target directory 词条 0033 特例描述更新）

## Out of Scope

- EXPAND 变体迁移（test.jai 持有，票 0039 形态 C 不变）
- 哨兵约定的结构性消除（候选 4 编译骨架收敛的范畴，另行用户拍板）

## Further Notes

- 语言：中文交流与文档。
- 验证前清 `target/transpile`（memory 已记）。

## Resolution

**Testing 模块 STRIP 特例收口落地（2026-10-14），三路径全绿。**

1. **实现**（题述方案 1–3 全落地）：
   - `testing_module_strip_view_dir(package_root, module_source, error_prefix)` 迁入 src/transpile_front.jai（Strip front 共享模块）——模块来源与报错前缀参数化（bootstrap 传 cwd 相对 `"modules/Testing.jai"` + `"[Build System] ❌ "`，Build command 传 `juice_modules_dir()/Testing.jai`）；存在性预检保留（模块缺失/不可读零动作零日志），mkdir/write/诊断文案统一（与票 0050 同策略，未钉住）。
   - 根 build.jai：内嵌特例副本（约 33 行）替换为一行调用；哨兵注释更新。文件 214 → 184 行。
   - commands/build.jai：本地函数删除（唯一调用点 `compile_artifact_plan` 改调共享函数，模块路径显式传入）。
2. **测试**：transpile_front_tests.jai 新增 2 块——test-free 模块零动作（"" 哨兵、无视图目录）、含 test block 模块写 STRIP 视图（真实转译器、断言视图内容与落点）。
3. **文档**：CONTEXT.md Build / Target directory 词条更新（STRIP 侧自 0051 驻 Strip front，EXPAND 侧驻 test 命令，票 0039）；IMPLEMENTATION.md transpile_front 行补 Testing 特例。
4. **验证**：`jai build.jai`（debug/release）全绿且 bootstrap 经共享函数写 target/testing-module/Testing.jai（实测存在、内容为 STRIP 视图）；`juice test` exit 0（debug 与 release 产物各一遍、30 处 GOLDEN PASS、latch 5/0）；`juice build` 自构建成功。
