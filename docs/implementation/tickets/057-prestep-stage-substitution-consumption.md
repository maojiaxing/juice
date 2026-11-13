---
id: 057
title: PRESTEP 阶段 + 源替换表消费
labels: [implementation]
status: closed
assignee: maojiaxing
blocked-by: [056]
blocks: [058]
---

# 057: PRESTEP 阶段 + 源替换表消费

> 上游规格：`docs/spec.md` §4.6/§6.1/§6.2/§6.3（2026-10-21 设计修订）。本票只做阶段机制与替换表消费；jaix 插件在 058。

**What to build:** 让 PRESTEP 成为 build/test 的真实阶段：`Prestep_Stage` 状态槽、`before` 派发、源替换表/剔除集的冲突规则，以及 build 入口选择与 test 文件转译对替换表的通用消费。

## 交付

1. `src/lifecycle.jai`
   - 新增 `Source_Substitution {original, replacement}`、`Prestep_Stage {root_dir, member_dirs, substitutions, drops}`。
   - `Lifecycle_Context` 增加 `prestep: *void` 槽（构造期 null）。
   - PRESTEP 无内置实现；`run_mounted_hooks(.PRESTEP, .before/.after)` 的失败语义沿用现有规则。
2. `src/commands/build.jai`
   - 在 b4 重校验与 LNK1104 hand-off 之后、TRANSPILE 之前派发 PRESTEP：before → after；填充 `prestep` 的 root_dir/member_dirs。
   - 将解析后的 pipeline 传入 `Build_Transpile_Stage`，避免 `build_plan_entry` 二次解析。
   - `build_plan_entry` 通用消费替换表：入口命中替换 → 直编替换绝对路径并跳过闭包探测/剥离；入口命中剔除 → 失败（诊断）。
   - 零 plan 早退先于 PRESTEP（不派发）。
3. `src/commands/test.jai`
   - 在零文件短路之后、TRANSPILE 之前派发 PRESTEP；填充 prestep 状态。
   - `test_transpile_front` 对每个已收集文件应用替换/剔除：命中替换 → 用替换路径读源码做 EXPAND，`rel_path` 保持原路径；命中剔除 → 不进测试程序；编号与 `path_mapping` 不变。
   - 解析后的 pipeline 传入 `Test_Transpile_Stage`。
4. 冲突规则（阶段级）
   - 替换表 append-only；同一 original 重复出现（不同 replacement）= 阶段失败。
   - 同一 original 同时替换与剔除 = 阶段失败。
   - 未命中的文件保持原路径；不新增文件；仅 root package。
5. 测试
   - `tests/lifecycle_tests.jai`：PRESTEP 派发、before/after 顺序、失败中止。
   - build：入口替换跳过探测、剔除入口失败、零 plan 不派发、替换后编译输入正确。
   - test：文件替换/剔除/未命中三类、编号与 path_mapping、零文件不派发。
   - 记录型假插件跨同一 hook 面；无 jaix 依赖。

## 验收

- `jai build.jai` debug exit 0；根 test 全绿。
- 机制测试不涉及 jaix；用假 PRESTEP 插件即可验证全部替换/剔除/冲突语义。
- PRESTEP 未声明 = no-op，既有 build/test 行为零变化。

## Out of scope

- jaix 插件本体（058）。
- 插件 host（060）。
- 其他 stage 的通用阶段状态序列化。

## Resolution

**2026-10-21，实现完成。**

实现摘要（按交付项）：

1. `src/lifecycle.jai`
   - 新增 `Source_Substitution {original, replacement}`、`Prestep_Stage {root_dir, member_dirs, substitutions, drops}`；`Lifecycle_Context` 新增 `prestep: *void` 槽（构造期 null）。
   - 阶段级表规则落成 API：`prestep_add_substitution(ctx, original, replacement)` / `prestep_add_drop(ctx, original)`——同一 original 同 replacement = no-op；不同 replacement = ERROR 诊断（append-only 冲突）；替换与剔除同键（两方向）= ERROR 诊断；缺 `prestep` 槽 = ERROR 诊断。冲突经 ctx 诊断上报，dispatch 的既有 ERROR 检查直接使阶段失败——hook 即使返回 true 也不能把冲突表带过阶段。查找侧 `prestep_substitution_for(stage, original)` / `prestep_is_dropped(stage, original)`（null stage = 未命中，即未声明插件的 no-op 形状）。
   - PRESTEP 无内置实现；`run_mounted_hooks(.PRESTEP, .before/.after)` 失败语义沿用现有规则；`at` 保留给未来整阶段接管，不派发。
2. `src/commands/build.jai`
   - b4 重校验与 LNK1104 hand-off 之后、TRANSPILE 之前派发 PRESTEP（before → after）；命令填 `root_dir` 与 `member_dirs`（`member_packages` 跳过首位 root，沿用 test 文件收集的约定）。
   - dispatch 表 = `resolved.hook_table`（声明解析的 hook 表，`plugin_state` 槽对齐 `resolved.slot_options` 的 options 指针）+ 调用方 hook 表；PRESTEP/TRANSPILE/COMPILE 共用同一张表与同一槽对齐。
   - `Build_Transpile_Stage` 增 `prestep: *Prestep_Stage`（pipeline 仍是命令级单次解析结果，`build_plan_entry` 不二次解析）；`build_plan_entry` 增可选 `prestep` 形参：入口命中替换 → 直编替换绝对路径并跳过闭包探测/剥离；入口命中剔除 → `[juice ERROR] The pre-step dropped the build entry: <rel>` + false；未命中照旧（探测/STRIP 视图）。零 plan 早退先于 PRESTEP（不派发）。
3. `src/commands/test.jai`
   - 零文件短路之后、TRANSPILE 之前派发 PRESTEP；同一 dispatch 表与槽对齐。
   - pipeline 解析上移到 `test_prepared_workspace`（一次解析，存入 `Test_Transpile_Stage.pipeline`；front 不再解析），与 build 同形。
   - `test_transpile_front` 逐文件消费替换表/剔除集：命中替换 → 用替换绝对路径读源码做 EXPAND，`rel_path` 保持原路径（view 路径、编号、`path_mapping` 都以原路径为键）；命中剔除 → 过滤出测试程序（`stage.files` 同源过滤，COMPILE 的 driver/`path_mapping` 自动对齐）；未命中 → 原路径原源码。
4. 冲突规则（阶段级）：见 1 的 API；append-only、仅 root package、不新增文件（只消费 root 的 plans / 收集文件）。

测试（18 个新增条目）：

- `tests/lifecycle_tests.jai`：PRESTEP 填充与 before/after 顺序、false 失败中止、冲突诊断失败（hook 返回 true 仍失败）、表规则矩阵（同 replacement 幂等、不同 replacement 拒绝、双向替换/剔除冲突、重复 drop 幂等）、缺槽失败、null 查找 no-op。
- `tests/build_transpile_tests.jai`：入口替换跳过探测（无 transpile 树）、剔除入口失败、非入口命中不影响入口、替换后编译 metaprogram 的 `add_build_file` 指替换路径；零 plan（带 PRESTEP hook）不派发；dispatch 级：表随 stage 进入入口选择（root/member dirs + COMPILE 收到替换路径）、剔除入口命令失败、冲突行（hook 返回 true）命令失败、PRESTEP 失败中止于 TRANSPILE 前。
- `tests/test_transpile_tests.jai`：文件替换（view 内容来自替换源、`rel_path`/编号/`path_mapping` 保持原路径、driver/metaprogram 无镜像路径）、剔除（无 view、无 path pair、幸存文件编号从 1、COMPILE 收到过滤后的文件/视图）、未命中（原源码键）、零文件不派发、PRESTEP 先于 TRANSPILE 且 stage 带 root/member dirs、冲突表命令失败。
- 全部用记录型假 PRESTEP 插件跨同一 hook 面；无 jaix 引用/依赖。

验收证据：

- `jai build.jai`（debug）exit 0。
- `rm -rf target/transpile && ./target/juice.exe test` exit 0；末行 `315 passed, 0 failed`（Testing 自测 finish 重置，非条目数）。
- 权威 found = 最大 `juice_test_N` 507 + 手写 `note_suite_*` @test 5 = **512**（056 基线 494，本票 +18）。
- PRESTEP 未声明 = no-op：既有 build/test 全套（含 E2E fixture 族与安装布局）保持全绿；空 hook 表的两个 PRESTEP 派发是纯 no-op。

Deviations：

1. test 命令的管线解析从 `test_transpile_front` 上移到 `test_prepared_workspace`（交付项 3「解析后的 pipeline 传入 `Test_Transpile_Stage`」的落点）。副作用：坏的内置声明即使 TRANSPILE 被 at hook 替换也会在编译前失败（与 build 的单次解析姿态一致）。
2. `build_plan_entry` 的 `prestep` 形参带默认值 null，既有直接调用点（b7 矩阵测试）无需改动；生产入口始终传 stage 的表。
3. 冲突规则经「带 ctx 的 mutation API + ERROR 诊断」强制：hook 返回 true 也会因诊断失败阶段（比「hook 必须返回 false」更强，插件作者漏传返回值无法绕过）。
4. PRESTEP 的 `at` 位置不派发（spec §6.2 保留给未来整阶段接管；本票只要求 before/after）。
5. dispatch 表 = 解析出的 hook 表 + 调用方 hook 表：Phase 1 的内置 hook 插件（058 的静态 jaix 插件）因此在命令进程内参与 PRESTEP；成员插件值仍只存在于测试 metaprogram / Phase-2 host（056 的边界不变）。

