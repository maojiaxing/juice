---
title: 实施：本包公开模块按公开名可用
status: open
labels: [ready-for-agent]
assignee: maojiaxing
parent: "0087"
blocked-by: []
---

## Goal and contract

父规格 [0087](0087-spec-package-declaration-semantics.md) 是权威。本票修复 0095 文档过程中暴露的一个真实规格缺口，而不是文档措辞问题。

Story 37「同包公开模块可以相互引用，以便拆分公共接口不改变包的组织单位」、决策 11「最终导入名不得覆盖本包模块」（本包模块占据导入名空间）、验收组 A04「同包模块可用」三者合起来要求：一个包声明在 `modules` 里的公开模块，在本包自己的程序与模块中应当能按公开名引用。

当前实现只对**提供方**做到这一点：消费方解析依赖时把提供方内部的 `#import "<export>"` 重写到私有名并写入消费工程私有 shim 目录。被构建包（根包/所选成员自身）的模块只参与导入名冲突检查（`consumer_exports`），从不进入 shim 集合，因此在根包里：

- `#import "calc"`（`calc` 是本包 `modules` 的一个导出名）失败：
  `Unable to find a module called 'calc' in any of the module search directories.`
- 本包两个公开模块之间按公开名互相引用同样失败。
- 只有 `#load "../module.jai"` 这类文件级加载可用，而它恰好破坏了把公共接口拆成模块的意义（入口路径成为源码契约）。

已用真实安装单元（exe + 相邻 `modules`）在仓库外临时工程复现：单模块时程序 `#import "calc"` exit 1、`#load` exit 0；两模块 `more.jai` 内 `#import "calc"` exit 1。0095 的指南把它写成「当前实现的限制」，本票要求把它变成已交付行为。

## Ownership

`src/dependency_resolution.jai`（导入准备与 shim 规划）、必要的命令接线（`src/commands/`）、`tests/dependency_resolution_tests.jai`、`tests/command_selection_tests.jai`、`tests/test_support.jai`、以及 0095 交付的 `docs/migrations/package-declarations.md` 中受影响段落与 `issues/0095` 已记录的“已知限制”表述（仅改与本缺口相关的行）。

## Validation

- 真实 CLI（仓库外临时工程 + 相邻 `modules` 安装单元，隔离 XDG）：
  - 本包程序 `#import "<本包模块导出名>"` 成功；
  - 本包模块之间按公开名互相引用成功；
  - 根包与工作区成员包两种情形都成功；
  - 与依赖导入名冲突时报错（决策 11 的“不得覆盖本包模块”反向成立）；
  - 传递依赖仍不得泄漏为本包直接导入（A04 否定面保持）；
  - 零程序包、纯工作区、`test` 命令下同样成立。
- 不破坏 0091 的提供方内部重写与 0093 的选包路径；聚焦过滤 `dependency_resolution_`/`workspace_`/`command_selection_`/`plugin_derived_` 全绿。
- 读 tdd 技能，在此前用户已确认的 CLI/现有函数测试边界逐行为 red-green，不再请求边界批准。读完整修改文件，避免无约束 Any/void。不要删除、降级或整体跳过旧测试掩盖行为缺失。

## Integration

自己的独立 worktree/branch 从 integration/package-declaration-semantics 最新 tip 开始；路径与执行纪律见 C:/Users/maojiaxing/DevTools/msys/tmp/juice-package-implementation/README.md。不要写主 checkout 或其它 agent 文件。完成前 merge 最新 integration、验证并 commit，返回精确命令/exit/计数/限制和接口说明；由 merger 核对合入并写 Resolution 关闭。
