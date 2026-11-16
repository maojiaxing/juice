---
title: 实施：独立产物与工作区发现选包
status: closed
labels: [ready-for-agent]
assignee: maojiaxing
parent: "0087"
blocked-by: ["0088", "0089"]
---

## Goal and contract

父规格 [0087](0087-spec-package-declaration-semantics.md) 是权威，相关已关闭决策为补充；本票必须交付以下可观察行为。

Decisions 4–8、16–18、20；A01/A13/A14/A15。模块/程序独立零/一/多项与固定候选、默认名称/entry/重复与default_run严格校验。工作区members明确目录和单层*、exclude子树、根自动成员、重叠去重、嵌套工作区边界、同名包允许。cwd向上最近声明、无效不跳过，归属只最近合法workspace、未收录/排除独立。实现共享选包结果：默认成员与位置规则，--workspace/-p/--package-path的冲突/歧义/去重/完整基数预校验和目录排序；命令票消费结果。全成员声明先校验但仅选包图获取。test扫描在任何下级package.jai处剪枝。

## Ownership

src/target.jai、src/workspace.jai、src/scan_walk.jai、src/test_discovery.jai 及对应测试；必要的内部模型字段与schema owner完成后协调。

## Validation

CLI临时根包/纯workspace/独立包/被排除包/嵌套workspace/同名包，cwd子目录、零默认、显式集合与子包test不泄漏；提供给commands的准确选包接口。

读 tdd 技能，在此前用户已确认的CLI/现有函数测试边界逐行为red-green，不再请求边界批准。读完整修改文件，避免无约束Any/void。不要删除、降级或整体跳过旧测试掩盖行为缺失。

## Integration

自己的独立worktree/branch从 integration/package-declaration-semantics 最新tip开始；路径与执行纪律见 C:/Users/maojiaxing/DevTools/msys/tmp/juice-package-implementation/README.md。不要写主checkout或其它agent文件。完成前merge最新integration、验证并commit，返回精确命令/exit/计数/限制和接口说明；由merger核对合入并写Resolution关闭。前置票未完成前不要使用假接口声称验证通过。

## Resolution

- 实现提交 `d41d71b`，经 `b8f8847`（`--no-ff`）合入 `integration/package-declaration-semantics`；分支 `implement/workspace-products`，基于 `3de250b`。
- 新增 `locate_declaration_root`：从 cwd 向上取最近 `package.jai`，遇无效声明即失败，不跳跃到上层包；准备阶段的发现根与依赖准备根统一使用该结果。
- 工作区成员展开保留明确目录与单层 `*`，应用 `exclude` 子树，根包自动成员且不可排除，重叠匹配按真实目录去重；内层工作区在其根或成员被外层命中且未排除时失败，排除后接受。
- `src/scan_walk.jai` 的共享遍历在任意含 `package.jai` 的子目录剪枝，测试与插件扫描都不会进入下级包；未登记或被排除的包仍可独立构建与清理。
- 新增命令侧唯一选包结果 `Package_Selection_Request` / `Package_Selection` 与 `select_workspace_packages`、`selection_selects_one_package`：成员内默认当前包，根位置用 `default_members`（省略为根包或纯工作区全体，空清单为零选包失败），`--workspace` 与按名/按路径显式集合、冲突/未知/歧义诊断、按包身份去重、按工作区相对目录稳定排序、run 基数门禁。命令参数解析与接线留给 0093。
- 严格产物矩阵在 CLI 边界由真实临时包固定：多项未命名、重复入口、非法 `default_run`、两个自动模块候选歧义均失败；`default_run` 见 `src/target.jai` 既有实现。
- 证据全部位于实现 worktree 的 `target/evidence/`：`nearest-red.json`（0/1）→`nearest-green.json`（3/0）、`scan-boundary-red.json`（0/1）→`scan-boundary-green.json`（4/0）；`workspace_products_` 7/0、`workspace_` 10/0、`declaration_schema_` 11/0。最终完整套件 `full-suite-final.log` 为 346 passed / 0 failed，exit 0。
- 合入后独立验证：fresh `jai build.jai` exit 0；`workspace_products_` 7/0、`workspace_` 10/0、`declaration_schema_` 11/0；完整 `test` 346 passed / 0 failed，exit 0（`target/evidence/integration-0090-full.log`）。
- 旧断言按 0087 决定迁移并说明原因：下级 `package.jai` 子树不再收集（决定 20）；重叠成员去重而非报错（决定 16）；`..` 规范化后仍在工作区内的路径合法（决定 8）；无声明临时目录的运行用例移到包外临时根，避免向上解析到仓库自身。
- 限制：仅在 Windows 验证，未在大小写敏感文件系统运行；Lua/插件、依赖、发布与迁移文档仍由 0091–0096 完成。本票不构成 0087 全部交付。
