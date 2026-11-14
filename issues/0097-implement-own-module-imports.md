---
title: 实施：本包公开模块按公开名可用
status: closed
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

## Resolution

- 实现分支 `implement/own-module-imports`（基于 `4e6b3c5`），提交 `48e2492`（本包自身导出成为该包导入名）、`2d5952f`（被测包自身模块进入 test 程序导入路径）、`71692a3`（文档改为已交付）、`be4aa1e`（合入集成分支）、`9f480d2`（修正 `docs/spec.md` 残留旧表述）。经 `725aac7`（--no-ff）合入 `integration/package-declaration-semantics`。
- 机制：被选包自身的导出按**公开名**规划为 shim，且不重写（与提供方不同）。`Import_Shim` 增加 `directory` 字段，使名字按目录唯一：本包模块写入该包自己的 `target/packages`，依赖导入名与提供方内部私有名仍留在消费根目录（0091 路径不变）。`resolution_write_shims` 整体重建其拥有的每个目录（被删除的模块会丢掉 shim，已验证）。`compiler_import_directories(packages_dir, own_packages_dir := "")` 把被编译包自己的目录排在消费根目录之前；`build` 从 `plan.target_dir` 取、`test` 从新增的 `Test_Compile_Stage.package_root` 取。
- 每包独立目录而非共享目录的原因：共享会让两个声明同名模块的成员冲突，也会让某成员的自身模块被同级成员导入。已否决的替代方案是为根包新建独立 target 区（`target_layout` 是已被测试固定的契约），作为限制登记。
- 真实缺陷：除了本票的目标缺口（改动前用安装单元复现），还发现所选工作区成员的 `test` 程序仍失败——`test_compile_front` 只从消费根推导导入目录，根包此前“碰巧”可用（其自身目录就是消费根目录）；在 `2d5952f` 修复并留下红绿记录。
- 验收（仓库外安装单元 exe + 相邻 `modules`，隔离 XDG，脚本 `acceptance.sh`，exit 0）：A 本包程序 `#import "calc"` build/run 0/0，输出 `calc=41 more=42`；B 既有 `#load` 路径 build/run 0/0，输出 `adder 42`；C 工作区成员 build/run/run 0/0/0（`one helper=5`、`two helper=500`）；D 成员 `test` 0（`1 passed, 0 failed`）；E 传递依赖不泄漏 build/run 0/0，泄漏探针 **1**（`Unable to find a module called 'Cipher'`）；F 本包模块与依赖导入名并存 build 0（`own=1 dep=7`），遮蔽探针 **1**（`shadows a module of the consuming package`）。
- 门禁证据（Windows）：fresh `jai.exe build.jai` exit 0；聚焦 `dependency_resolution_` 17/0、`workspace_` 13/0、`command_selection_` 7/0、`plugin_derived_` 16/0、`declaration_schema_` 11/0、`run_selection_` 12/0、`publication_install` 15/0、`module_` 6/0；完整套件两轮 380 passed / 0 failed、EXIT 0，合入后再次两轮 380/0 EXIT 0（主检出 `target/evidence/verify-0097-full-1.log`、`-2.log`）。新增 3 条测试在两轮日志中按名字确认存在（打印的套件合计不是总数，因 `tests/module_tests.jai` 会调用 `finish()`）。
- 文档同步：`docs/migrations/package-declarations.md` §4.3、已知限制第 3 条、E03 说明与证据行改为“已交付”；`docs/spec.md` §2.5 的旧限制表述一并修正。
- 已知限制：根包自身的 shim 与消费根共享同一目录，因此在 `--workspace` 下一个成员可以导入根包的自身模块名，反向不成立（两个方向都已实测）。依赖导入名在所选包之间仍是共享命名空间（既有行为）。`test` 仍无法使用落在测试扫描集合内的模块入口（既有行为：扫描到的源码再被 `#load` 会重复声明）。仅 Windows 证据，无 Linux 执行。验收留 0096；本票不构成 0087 全部交付。
