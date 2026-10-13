---
title: 收尾：三路径终验、文档对齐与提交
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [0031-bootstrap-build-transpile-front.md, 0032-test-support-extraction.md, 0033-testing-self-test-inline.md, 0034-test-block-migration.md]
---

> 父票：[实施计划](0030-implementation-plan.md)（实施序列第 5 票）；验收标准见 [docs/spec-src-inline-test-blocks.md](../docs/spec-src-inline-test-blocks.md) 第五章。

## Problem Statement

全部迁移完成后，做终验与收尾：三条构建路径全绿、文档与实现一致、旧测试文件痕迹清零。

## Solution

1. **三路径终验**：
   - `jai build.jai` 全绿；产物 `target/juice.exe` 烟测（`juice test` 于仓库根跑通）
   - `juice build` 全绿
   - `juice test` 0 failed、退出码 0；147（+Testing 自测 10）块全部执行（输出含全部测试名）
   - release 与 debug 两模式均剥离正确
2. **文档对齐**：CONTEXT.md / IMPLEMENTATION.md 与实际实现一致（Bootstrap build、Test support 词条核对）；spec 第五章验收标准逐条核对。
3. **痕迹清零**：tests/ 仅剩 data/；grep 仓库无旧测试文件（tests/test_*.jai）引用。
4. **提交与关闭**：核对 PR 分支变更集与提交信息完整；关闭 0031–0035（status → closed、resolution 落档）。

## Acceptance criteria

- [ ] 三路径全绿（含烟测与 release/debug 双模式）
- [ ] 文档与实现一致
- [ ] tests/ 仅剩 data/；无旧测试文件引用
- [ ] 0031–0035 status closed、resolution 落档

## Out of Scope

- 新功能与转译器变更
- 常态化错误注入自动化测试（探针一次性验证，见 0031）

## Further Notes

- 语言：中文交流与文档。
