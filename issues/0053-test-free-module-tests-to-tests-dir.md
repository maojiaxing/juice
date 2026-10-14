---
title: test-free 模块的单元测试移驻 tests/（测试组织规则）
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: []
---

> 2026-10-14 用户拍板的测试组织规则：单元测试内联贴实现；集成测试（真实 juice.exe 子进程 E2E）驻 tests/。test-free 模块（bootstrap 的 `#load` 目标：src/transpile.jai / src/transpile_cache.jai / src/transpile_front.jai / src/metaprogram.jai）的单元测试不能字面内联——其测试文件同样驻 tests/（规则一致适用，含既有 src/transpile_tests.jai）。

## Problem Statement

票 0034/0050/0052 把三个 test-free 模块的单元测试放在 src 姊妹文件（src/transpile_tests.jai、src/transpile_front_tests.jai、src/metaprogram_tests.jai）——「贴实现」的形态，但按新规则它们与集成测试一样归 tests/（src/ 只留实现与可内联的测试）。

## Solution

1. `src/transpile_tests.jai` → `tests/transpile_tests.jai`；`src/transpile_front_tests.jai` → `tests/transpile_front_tests.jai`；`src/metaprogram_tests.jai` → `tests/metaprogram_tests.jai`（纯文件迁移，测试块零改动；Test discovery 全包扫描照常收录 tests/*.jai）。
2. 更新三文件头注释（位置描述）与全部引用：CONTEXT.md（Strip front 词条）、IMPLEMENTATION.md（内联测试段 + 规则句）、SUMMARY.md（文件树）、docs/spec-src-inline-test-blocks.md（0034 落地注记补修订）、src/metaprogram.jai / src/transpile_front.jai / src/dependency.jai / src/commands/build.jai 的路径注释。
3. 发现序变化：tests/ 文件排在 src/ 全部文件之后（此前 transpile_front_tests.jai 排在 commands/ 之前）——票 0050 的簿记清零修正保留（显式清零无论顺序都正确，注释措辞随之更新）。

## Acceptance criteria

- [ ] 三路径全绿：`jai build.jai`（debug/release）、`juice build` 自构建、`juice test` 0 failed（debug 与 release 产物各一遍、30 GOLDEN PASS）
- [ ] src/ 无 *_tests.jai 残留；grep 引用全部指向 tests/
- [ ] 测试块零改动（纯迁移）

## Further Notes

- 语言：中文交流与文档。
- 验证前清 `target/transpile`（文件集变化会移测试编号）。

## Resolution

**测试文件迁移落地（2026-10-14），三路径全绿。**

1. **迁移**（题述方案 1–2 全落地）：`src/transpile_tests.jai` → `tests/transpile_tests.jai`（git mv）；`src/transpile_front_tests.jai` → `tests/transpile_front_tests.jai`；`src/metaprogram_tests.jai` → `tests/metaprogram_tests.jai`。测试块零改动（纯迁移）；src/ 无 *_tests.jai 残留。
2. **引用更新**：三文件头注释（位置描述 + 票 0053）；CONTEXT.md Strip front 词条；IMPLEMENTATION.md 内联测试段与规则句（"their unit tests cannot be inlined and live in `tests/*_tests.jai`"）；SUMMARY.md 文件树；docs/spec-src-inline-test-blocks.md 0034 落地注记补修订；src/metaprogram.jai（4 处）、src/transpile_front.jai、src/dependency.jai、src/commands/build.jai（2 处，含簿记清零注释措辞：发现序复原后显式清零保留）。
3. **发现序**：tests/ 文件排在 src/ 全部文件之后（此前 transpile_front_tests.jai 排在 commands/ 之前）——票 0050 的簿记清零修正保留（显式清零不依赖发现序）。
4. **验证**：`jai build.jai`（debug/release）exit 0；`juice test` exit 0（debug 与 release 产物各一遍、30 处 GOLDEN PASS、latch 5/0，输出确认三套测试自 tests/ 收录执行）；`juice build` 自构建成功。
