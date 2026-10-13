---
title: 收尾：三路径终验、文档对齐与提交
status: closed
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

- [x] 三路径全绿（含烟测与 release/debug 双模式）
- [x] 文档与实现一致
- [x] tests/ 仅剩 data/；无旧测试文件引用
- [x] 0031–0035 status closed、resolution 落档

## Out of Scope

- 新功能与转译器变更
- 常态化错误注入自动化测试（探针一次性验证，见 0031）

## Further Notes

- 语言：中文交流与文档。

## Resolution

已实施（61080c1/c4d89b1 + review 修复轮 10cb43f/7dadb2e）：① manifest 求值器竞态修复——临时文件按被求值 manifest 绝对路径散列命名（FNV-1a 64 位）、写结果检查（失败退出码 2）、父进程重试至多两次；② 文档对齐——spec 第三章映射表修正、第二章补三路径对称特例，CONTEXT.md/IMPLEMENTATION.md/SUMMARY.md 对齐；③ review 修复轮——testing-module 落点文档化、排版规范行号保真例外演进、test_support helper 去重、切段机器标记、注释与命名修正；④ 三路径终验全绿（debug/release、烟测、副本法自构建、Found 147、10 自测名、0 failed、0 flake）。tests/ 仅剩 data/，代码级无旧测试文件引用。0031–0035 已全部关闭。
