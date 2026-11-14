---
title: 实施：显式来源、模块可见性与 Git 解析状态
status: closed
labels: [ready-for-agent]
assignee: maojiaxing
parent: "0087"
blocked-by: ["0088", "0089", "0090"]
---

## Goal and contract

父规格 [0087](0087-spec-package-declaration-semantics.md) 是权威，相关已关闭决策为补充；本票必须交付以下可观察行为。

Decisions 9–15、26；A02/A03/A04/A09/A10/A11/A12。按PATH/GIT/WORKSPACE显式取源，不能同名覆盖、版本字段或包名搜索。modules path/name/alias平铺选择；每消费包实际模块和最终导入名去重，禁止覆盖本包/直接/标准模块。提供方自行解析传递依赖、同包模块互用、传递不可向外泄漏；完整环链。Git检出内workspace/path边界和来源身份保留。内容cache与state分离；键区分消费工程/声明包/来源selector，不受alias/reference/modules变化影响；默认分支/branch/tag/rev互斥，已有选择不联网追新，缺内容只补选定commit。完整图成功后原子发布，损坏状态错误，失败保旧且失败，编译失败不回滚。offline完整缓存/选择及完整SHA无记录例外；update全图只更新所选消费context，拒offline。共享源码只读、每消费方私有import准备。普通依赖与插件来源复用typed resolver，不通过全局mutable当前工程传context。

## Ownership

src/dependency.jai、src/metaprogram.jai、新内部解析状态文件、相关main/build加载接线和依赖验收测试；必要内部模型扩展。

## Validation

必须真实临时本地Git repo验证分支移动、普通复用、alias不更新、双工程及双成员隔离、传递更新、失败保旧、清内容后补同commit、离线/损坏状态与环。提供resolve/update/offline及import准备接口给插件和命令；不把函数对象测试代替CLI关键链路。

读 tdd 技能，在此前用户已确认的CLI/现有函数测试边界逐行为red-green，不再请求边界批准。读完整修改文件，避免无约束Any/void。不要删除、降级或整体跳过旧测试掩盖行为缺失。

## Integration

自己的独立worktree/branch从 integration/package-declaration-semantics 最新tip开始；路径与执行纪律见 C:/Users/maojiaxing/DevTools/msys/tmp/juice-package-implementation/README.md。不要写主checkout或其它agent文件。完成前merge最新integration、验证并commit，返回精确命令/exit/计数/限制和接口说明；由merger核对合入并写Resolution关闭。前置票未完成前不要使用假接口声称验证通过。

## Resolution

- 实现分支 `implement/dependency-resolution`（基于 `2097bc0`），提交 `9e6a981`（seam 迁移基线）、`6fc3195`（显式来源/模块选择/可见性/环/WORKSPACE 归属）、`b7d0e3e`（Git 复用/update/offline/隔离/状态边界验收）、`ab60b97`…`099e373`（环境隔离、夹具修正、生成 driver 加载、update 命令契约）、`8f2d728`+`5742200`（内容缓存发布竞态与物化修复）、`9ca2765`（换行归一）。经 `67e37fe`、`ae043ac`、`99e43e1`、`f0f3e5d` 合入 `integration/package-declaration-semantics`。
- 新增 `src/resolution_state.jai`：`Resolution_Mode{NORMAL,UPDATE,OFFLINE}`、`Resolution_Environment`（内容缓存根/状态根/模式）、`Resolved_Selection`、`Resolution_State`、`read/publication_resolution_state`、`resolution_declaring_key_*`、`git_selector_identity`、`git_resolve_selector`、`git_ensure_content`、`git_content_checkout_directory`。内容缓存与工程选择状态分目录，状态按消费上下文整体原子发布；损坏状态报错而非视为缺失。
- 新增 `src/dependency_resolution.jai`：`Dependency_Preparation_Request`、`resolve_dependencies_for_workspace`（workspace 准备 seam 默认实现）、`resolution_resolve_consumer`、`resolution_import_directories`、`resolution_rewrite_imports`、`resolution_create_view`、`resolution_write_shims`。实现显式 PATH/GIT/WORKSPACE 来源、平铺模块 path/name/alias 选择、私有导入重命名与每消费方私有视图、实际模块与最终导入名去重、禁止覆盖本包/直接/标准模块、传递依赖不外泄、完整环链、Git 检出内 workspace/path 边界。
- `src/workspace.jai` 准备 seam 改为显式 request；`src/main.jai` 启动时解析 XDG 内容/状态根（相对值告警回退，不切换 cwd/临时目录）；新增 `src/commands/update.jai`（只刷新解析图、拒绝 `--offline`），build/test 接受 `--offline`。完整命令选包与参数组合留 0093。
- 真实临时本地 Git 仓库验收（`tests/dependency_resolution_tests.jai`、`tests/dependency_resolution_git_tests.jai`）：14 个行为组覆盖 A02/A03/A04/A09/A10/A11/A12，含分支移动后普通复用、别名/引用名/模块清单变化不换 commit、显式 update 全图且拒 offline、两消费工程与两成员隔离、损坏状态报错、失败保旧、编译失败不回滚、清内容后只补选定 commit、offline 完整缓存与完整 SHA 例外、检出内兄弟包与非成员 path、越界拒绝。
- 修复的真实缺陷：解析失败仍置 success 且静默不发布；`#import` 重写丢失分号；已解析提供方重复选择跳过判重；WORKSPACE 归属只查包目录而不上溯工作区且未校验成员资格；Windows 递归删除异步导致内容发布间歇 “Access is denied”（改为原地 clone + 校验 commit，删除有界等待）；Git 内容缓存键过长触发 MAX_PATH（缩短为 24 字符 + 48 位摘要）。
- 门禁证据（Windows，`target/evidence/`）：fresh `jai build.jai` exit 0；聚焦 `test dependency_resolution_` 连续三轮 14/14；`test workspace_` 11/11；完整 `test` 连续两次 346 passed / 0 failed、EXIT 0（`m0091d-full-1.log`、`m0091d-full-2.log`）。合入前 `test dependency_resolution_` 在实现树同样 14/14。
- 全量日志中的 `path:line:col: expect failed` 行是 Testing 模块自测的故意失败夹具（`module_tests` 与发布面自测），数量与基线一致。
- 限制：仅 Windows 验证；POSIX 分支未实测。深度超过 MAX_PATH 的用户路径仍不支持（未实现 `\?\` 长路径）。命令层完整选包/参数组合、插件接线与文档分别留 0092/0093/0094–0096。本票不构成 0087 全部交付。
