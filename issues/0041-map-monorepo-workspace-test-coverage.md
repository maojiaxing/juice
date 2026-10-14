---
title: 地图：monorepo（workspace member）测试覆盖
status: closed
labels: [wayfinder:map]
assignee: maojiaxing
---

## Destination

为 juice 的 monorepo 能力（workspace member 体系：discovery 成员校验、member 依赖 link、clean 跨 root+member、test 的 member 边界）补齐测试覆盖，验证该功能是否正常。本 effort 决策与实施一体：每张票关闭时测试代码已落地且 `juice test` 全绿；测试暴露的真实缺陷以修复票纳入本地图闭环。达成标志：discovery 校验矩阵全分支直测 + build/clean/test 三面 monorepo E2E 就位，[wrap-up](0047-wrap-up.md) 票关闭。

## Notes

- 执行已载入地图（本 effort 的票直接交付测试代码，不做纯决策集）。
- **2026-10-14 用户修订**：monorepo 的 E2E 测试集中至 `tests/test_monorepo.jai`（不内联在 command 文件中）；路径门槛直测留在 `src/workspace.jai`。各票 Resolution 已附勘误。
- 领域词汇权威是 CONTEXT.md（本仓库无 "monorepo" 一词，用 workspace member / workspace discovery）；测试惯例：测试块内联于持有者 src 文件（票 0034 决议），fixture 落 `tests/data/`，共享 helper 进 `tests/test_support.jai`（E2E 子进程 helper `run_juice_child`/`run_juice_test` 已在其中）。
- 环境隐患（沿用既有记忆）：新增含 test block 的 src 文件后必清 `target/transpile` 缓存（EXPAND 缓存键不含测试编号，陈旧视图会编号冲突）；fixture 不提交 `target/`（.gitignore 陷阱，已有 negation 规则勿动）；Windows 下 `target/juice.exe` 运行中不能重链接（bootstrap build 前确认无残留进程）；symlink/junction 用例由测试运行时在 target/ scratch 制造，不进 git。
- 票执行 session 应咨询：grilling + domain-modeling（若遇未决语义）；测试失败诊断参考 diagnosing-bugs。
- 交流语言：中文。

## Decisions so far

- [monorepo 测试 fixture 家族](0042-monorepo-fixture-family.md): 9 个 fixture 落地并冒烟验证——workspace-ok（双 member 双布局）全链路构建+运行通过；6 个 bad fixture 命中预期失败分支；edge-self 命中 duplicate；edge-nested 钉住「嵌套成员声明静默忽略」。实测事实：`member_lib/.` 拼写命中 duplicate 分支；「member 目录不存在」实际命中 not-a-safe-real-directory 分支（normalize_existing_path 不验证存在）。

- [discovery 成员校验矩阵](0043-discovery-validation-matrix.md): 全分支 E2E 矩阵落地（9 条 build.jai E2E + 1 条 workspace.jai 进程内直测钉路径有效性门槛）——直测因 manifest 求值器模块目录从运行中可执行文件推导而不可行，经消息断言区分分支。边界裁断：root 自列 `.` → duplicate 错误；嵌套成员声明静默忽略（非缺陷，建议 wrap-up 补 CONTEXT.md 事实）。两个防御分支（does-not-exist / escapes-root）经 fixture 路径不可达，记录不入矩阵。155 passed, 0 failed。

- [monorepo build E2E：root 依赖 member 构建](0044-monorepo-build-e2e.md): workspace-ok 真实构建 E2E——shim 内容断言 link 非 fetch（两种导入入口布局皆 link）、artifact 运行调用两 member 函数、root 闭包 test-free 零转译。无缺陷。156 passed, 0 failed。

- [monorepo clean E2E：root+member target 递归删除](0045-monorepo-clean-e2e.md): workspace-ok 运行时垃圾 target 的 clean E2E——root+member 整目录删除、源文件保留、无 target 的 member 不失败（delete_directory_full 对不存在路径返回 true）。无缺陷。157 passed, 0 failed。

- [monorepo test E2E 缺口：root 测试程序 import member](0046-monorepo-test-e2e-gap.md): workspace-ok 加 root 测试（helper.jai import member_lib）与 member 自带测试——E2E 断言 root 测试经 shim 跑通、member 测试不执行。**暴露真实缺陷**：test 编译缺 target/packages import 路径（root 测试无法 import 任何依赖）→ 立 [缺陷票 0048](0048-defect-test-compile-missing-packages-import-dir.md) 并修复（compiler_import_directories 移入 dependency.jai，build/test 共用）。158 passed, 0 failed。
- [wrap-up：全量验证与文档同步](0047-wrap-up.md): 最终验证 158 passed, 0 failed；SUMMARY/IMPLEMENTATION 补 monorepo 覆盖章节与依赖表行（含 Clean 陈旧措辞修正）；CONTEXT.md Workspace member 词条补嵌套声明忽略事实；地图索引完整、雾区清空。

## Not yet specified

（无——全部雾项已毕业：[缺陷修复票雾](0048-defect-test-compile-missing-packages-import-dir.md) 由矩阵票暴露并关闭，CONTEXT.md 待办由 wrap-up 执行。）

## Out of scope

- 外部依赖 fetch 的 E2E（测试不碰网络）；外部依赖保持 fake seam 单测水位。
- 嵌套 member 构建语义扩展、run 命令的 monorepo 行为变化（Build/Run 只解析 root effective target 是既有决策）。
- workspace-wide 测试聚合（root 一次跑全部 member 测试）——[地图 0001](0001-map-test-command-and-test-block.md) 已划出。
