---
title: wrap-up：全量验证与文档同步
status: closed
labels: [wayfinder:task]
assignee: maojiaxing
blocked-by:
  - 0043-discovery-validation-matrix
  - 0044-monorepo-build-e2e
  - 0045-monorepo-clean-e2e
  - 0046-monorepo-test-e2e-gap
---

## Question

收口本地图：验证、文档与地图索引三件事。

1. **全量验证**：`jai build.jai` 成功后 `./target/juice.exe test` 全绿（注意 Windows exe 锁：bootstrap build 前确认 `target/juice.exe` 无残留进程；新增过含 test block 的 src 文件，先清 `target/transpile` 缓存再跑）。
2. **文档同步**：SUMMARY.md / IMPLEMENTATION.md 补 monorepo 测试覆盖的条目；若边界用例（root 自列 member、嵌套 member）钉住了 CONTEXT.md 未记载的行为，在 CONTEXT.md 相应词条（Workspace member / Workspace discovery）补一句事实陈述（非语义变更）。
3. **缺陷票收口**：本地图期间立的缺陷修复票全部关闭，或明确结转并说明（结转需在地图 Not yet specified 保留一句话指路）。
4. **地图索引**：Decisions so far 逐票补行（gist + 链接）；Not yet specified 已全部毕业则注明；Out of scope 复核无遗漏。

## Acceptance criteria

- [ ] 全量 `juice test` 绿且失败数为零。
- [ ] SUMMARY.md / IMPLEMENTATION.md 已同步；CONTEXT.md 若需补充边界行为事实则已补充。
- [ ] 地图 Decisions so far 完整、Not yet specified 清空（或仅剩明确结转项）、缺陷票状态如实记录。
- [ ] 地图 status 改 closed。

## Out of Scope

- 本地图之外的新测试面（外部 fetch E2E、嵌套 member 语义扩展等——地图 Out of scope 已列）。

## Resolution

收口完成：

1. **全量验证**：清 `target/transpile` 后 `jai build.jai` + `./target/juice.exe test` → **158 passed, 0 failed**，退出码 0。
2. **文档同步**：
   - `CONTEXT.md`：Workspace member 词条补事实——「Workspace 的成员集合只由 root package 的声明决定：member 自身 manifest 中再声明的 members 不产生 workspace member，嵌套声明被静默忽略（测试钉住的事实，票 0043）」。
   - `IMPLEMENTATION.md`：新增「Monorepo (workspace member) test coverage」章节（矩阵、fixture 家族、缺陷 0048 与直测不可行原因）；依赖表同步（`compiler_import_directories` 归 dependency.jai，build.jai 行移除 import-directory assembly）；顺手修正陈旧 Clean 措辞（`result/`/`.packages` 遗留说法 → 现行为 `target/` 整目录删除，与新 clean E2E 一致，避免文档自相矛盾）。
   - `SUMMARY.md`：新增 monorepo 测试覆盖章节（票 0042-0048 各一行）+ 验证结果行更新（158 passed, 0 failed、矩阵全绿）。
3. **缺陷票收口**：[缺陷票 0048](0048-defect-test-compile-missing-packages-import-dir.md) 已修复并关闭，无结转项。
4. **地图索引**：Decisions so far 七行齐备；Not yet specified 两雾项全部毕业（缺陷雾→0048 已关、CONTEXT 待办→本票已执行）；Out of scope 复核无变化；地图 status 改 closed。**目的地达成**：discovery 校验矩阵全分支 + build/clean/test 三面 monorepo E2E 就位且全绿。

