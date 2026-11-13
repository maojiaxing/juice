---
id: 021
title: lifecycle 骨架（枚举 + 钩子 + 排序 + 失败语义）
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [024]
---

> 父 spec：`004-spec-plugin-surface-skeleton.md`（决定 12-16 + US 26-30）。上游规格：`docs/spec.md` §6；参照面：L§3-4（jaix Hook_Point 关联表 + Transpile_Plugin plugin_state 双先例）。

# 021: lifecycle 骨架（枚举 + 钩子 + 排序 + 失败语义）

**What to build:** lifecycle 挂载机制全立——封闭九阶段枚举（只增不改纪律）+ `Lifecycle_Hook {stage, position, hook}` + `Hook_Position {before, at, after}` + `Lifecycle_Context`（阶段名 + 该阶段可观测状态 + diagnostics 三汇 + plugin_state 槽）+ 钩子表注册/合并 + 确定性排序（阶段序硬编码 + 阶段内注册声明序 + before/after 同为注册序正序）+ 失败语义（钩子 false 或 ERROR 诊断 = 阶段失败 → 命令失败 → 退出码；观察类钩子失败同样中止）+ 未经过阶段静默不触发。本票不接命令编排（at 接线随 027/028），假钩子矩阵测试。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] 九阶段封闭枚举落地（DISCOVER…CLEAN，只增不改注释纪律 + spec 版本化）
- [x] Lifecycle_Hook / Hook_Position / Lifecycle_Context 形状（决定 13）
- [x] 排序矩阵（阶段内声明序、before/after 同正序、未经过阶段静默）
- [x] 失败传播链（false → 阶段失败；ERROR 诊断 → 拒绝；观察类失败同样中止）
- [x] plugin_state 槽对齐注册序 + 宿主持有存储（构造期恒 null）
- [x] 姊妹测试 + 旧 juice build/test 于 otter 根零特判全绿（debug+release）+ 238 存量不回归
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**：

- **`src/lifecycle.jai`**（新建，本票机制面——test-free，链约定 bootstrap #load 集纪律，旧 juice 无对应模块、jaix Hook_Point/Plugin_Grammar_Entry 关联表与 Transpile_Context 槽协议双先例）：
  - **`Lifecycle_Stage` 封闭九阶段枚举**（DISCOVER/PREPARE/VALIDATE/DEP_STRIP/PRESTEP/TRANSPILE/COMPILE/EXECUTE/CLEAN，spec 决定 12 逐字）——声明序 = 硬编码阶段序（编排跑其子序列）；只增不改注释纪律 + spec §6.1 版本化承诺（重命名 = 静默破坏插件面与缓存键，jaix Node_Kind 纪律）；测试钉死 0-8 序数；
  - **`Hook_Position {before, at, after}`**（spec 决定 13 小写字面形状）+ **`Lifecycle_Hook {stage, position, hook}`**（hook = `#type (ctx: *Lifecycle_Context, state: *void) -> bool`——参数个数与函数严格一致）；
  - **`Lifecycle_Context`**：stage（派发入口置位，钩子恒观察到所挂阶段）+ 可观测状态槽族（workspace/artifact_plans/views/artifact_paths/paths `*void` + exit_code s64——§6.1 表列映射）+ **diagnostics 三汇**（`Lifecycle_Diagnostic_Level {ERROR, WARNING, INFO}` compiler_report 形状 + 宿主持有 `*[..]` sink）+ **plugin_state 槽**（`[..] *void`，与钩子注册序对齐、宿主持有存储、构造期恒 null）；
  - **钩子表注册/合并**：`Hook_Registration {hooks}`（一个注册 = 一个插件的 hooks 数组贡献；注册序 = 声明序 = 执行序）+ `register_hooks`（空贡献跳过不占槽）+ `merge_hook_tables`（按序拼接，声明序跨贡献保持）；
  - **`run_mounted_hooks` 单一挂载派发点**：仅触发所请 (stage, position) 挂载（未经过阶段静默不触发——PRESTEP 无 marker 即此语义）；注册声明序正序（before/after 同为注册序正序——逆序方案已否决）；每注册一槽（slot i ↔ 注册 i，缺槽读 null）；
  - **失败语义**（§6.5 逐条）：钩子 false 或产 ERROR 诊断 = 阶段失败（fail-fast——派发立即停止，观察类钩子同款中止，失败继续属测试执行层）；判定只看本次派发新增条目（宿主可跨阶段复用单 sink）；`has_new_error` 助手。
- **`tests/lifecycle_tests.jai`**（新建，13 test 块——单一录制假钩子 `rec_hook` 经 plugin_state 槽携带 (trace 汇 + label + result + 诊断旗标)，槽通道本身即被测试面；好测试标准 = 只测外部行为：给定钩子集 + 挂载 → 触发序/诊断/派发结果，不测内部装配轨迹）：枚举序钉 / before 注册序 / after 同正序 / 仅所请挂载触发（含 at 位）/ 未经过阶段静默（PRESTEP）/ false → 失败 + fail-fast（后钩不跑）/ ERROR → 失败 + WARNING/INFO → 通过 / 派发前存量诊断不计数 / 每注册一槽（trace 形状 ["a","b","a"] 钉死——按钩子对齐会录出 ["a","b","b"]）/ 缺槽读 null / 空贡献不占槽 / merge 拼接序 / ctx.stage 由派发置位。
- **main.jai 零改动**（015/020 先例）：无生产消费者，机制库面待 024（合并查重消费 `Hook_Registration` 表）与 027/028（at 接线调 `run_mounted_hooks`）。

**验证矩阵**（旧 juice 双路径，各先清 otter/target/transpile）：

| 路径 | juice build | otter build | otter test |
| --- | --- | --- | --- |
| debug | exit 0 | exit 0 | exit 0，**Found 263 tests**（250 基线 + 13 新），116 passed, 0 failed（driver 汇总 = 基线 103 + 13；Testing face 自测内部 finish 重置计数所致，debug+release 同状） |
| release | exit 0 | exit 0 | exit 0，**Found 263 tests**，116 passed, 0 failed |

测试连跑 8 次零 stall（嵌套 #run 套件竞态未触发）；仅有的 4 行 expect failed = module_tests「Testing face」失败机制自测的预期输出（:178/:183/:207/:212，debug+release 逐行同状，非回归）。

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **可观测状态槽族 = `*void` 槽 + 注释映射**（workspace/artifact_plans/views/artifact_paths/paths）：各阶段状态类型各异（与 plugin_state 同款异构存储理由——CLAUDE.md *void 规则例外面），027/028 首生产消费者铸型；PRESTEP 状态槽随 jaix_front 票落地（spec §6.1 表该行留注释锚）。
2. **槽对齐 = 每注册一槽**（两级形状 `Hook_Registration` 而非扁平钩子表）：「槽与钩子注册序对齐」（决定 16）的直读 = 一个插件注册其 hooks 数组为一次注册、注册内全部钩子共享 slot i——Transpile_Context 每插件槽的直接泛化保持（多钩子插件共享状态不碎）；024 的合并查重在此表上迭代。
3. **register_hooks 拷贝钩子元素进注册自有数组**（调用方数组可为临时或大数组切片）；merge_hook_tables 共享头（动态数组堆数据寿命独立于表，020 synth 同款姿势）。
4. **diagnostics 三汇 = 级别三通道**（ERROR/WARNING/INFO——`compiler_report` 三汇形状，spec §8.2 锚）+ 失败判定仅看本次派发新增条目（宿主跨阶段复用单 sink 不被存量 ERROR 误杀——机制层防御，编排层正常不会续跑已败阶段）。
5. **fail-fast 派发**：false 或 ERROR 即停后续钩子（「中止」直读；诊断全量累积的报告面归调用方——阶段已败，后续钩子输入一致性无保障）。
6. **Hook_Position 小写成员**（before/at/after——spec 决定 13 字面形状；Lifecycle_Stage 全大写照决定 12；otter 其余枚举大写惯例无冲突）。
7. **Jai 事实钉 ×3**（编译期实证）：前缀 `*` 恒取地址（解引用 = 后缀 `.*`；`*[..]` 指针索引须 `p.*[i]`——`p[i]` 走指针算术）；枚举成员字面量在 cast 上下文须全限定（`cast(s64) Lifecycle_Stage.DISCOVER`）；切片值不能装入 `[..]` 字段（须逐元素拷贝）。
