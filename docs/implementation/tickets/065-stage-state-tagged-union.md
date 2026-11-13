---
id: 065
title: Stage state 的 tagged union
labels: [wayfinder:grilling]
status: closed
assignee: maojiaxing
blocked-by: [063]
blocks: [068]
---

# 065: Stage state 的 tagged union

## Question

Stage state 的 tagged union 怎么落？已拍板用 tagged union；若 063 证明 Jai 表达力不足，采用 research 推荐的替代。

要定：

- kind 枚举与 payload 的存放；`Stage_State` 的领域命名。
- hook 如何按 tag 访问 state；at hook 替换 built-in 时的 state 类型检查。
- `Lifecycle_Context` 现有 `*void` slots（`src/lifecycle.jai:137-168`）如何迁移；哪些 slot 保留、哪些由 union 取代。
- command-local 结构（`Build_Transpile_Stage`、`Test_Transpile_Stage`、`Test_Compile_Stage`）的去留与迁移顺序。
- 与 in-process 测试 hook 的兼容：现有 `cast(*Build_Transpile_Stage)` / `cast(*Test_Transpile_Stage)`（`tests/build_transpile_tests.jai:96`、`tests/test_transpile_tests.jai:135,144`）如何更新。
- 生成文本是否受影响（host / test runner 目前不携带这些类型；确认零影响或记录改动）。

输入：063 的 `docs/research/jai-tagged-union.md`。相关锚点：`src/commands/build.jai:116-142`、`src/commands/test.jai:373-383`、`src/test_runner.jai:414-426`。

## Answer

**形状（063 候选 D）**：`src/lifecycle.jai` 声明基记录 `Stage_State :: struct { kind: Type; }`（只依赖 Basic）；每个 stage payload 记录首字段 `#as using base: Stage_State;`，默认构造 / `.{}` 自盖章 `base.kind = <自身类型>`。禁止 `---` 构造（跳过盖章）；不要按值传 `Stage_State`（只剩 tag）；payload 记录留在原文件，不搬进 `lifecycle.jai`（bootstrap 闭包约束）。

**改名（用户拍板）**：

- `Prestep_Stage` → `Prestep_Stage_State`
- `Build_Transpile_Stage` → `Build_Transpile_Stage_State`
- `Test_Transpile_Stage` → `Test_Transpile_Stage_State`
- `Build_Compile_Stage` → `Build_Compile_Stage_State`
- `Test_Compile_Stage` → `Test_Compile_Stage_State`

**Context slots（逐 stage，类型 `*Stage_State`）**：`workspace` / `artifact_plans` / `views` / `artifact_paths` / `prestep` / `paths` 六个指针槽从 `*void` 改为 `*Stage_State`；`exit_code` 保持 `s64`。stage → slot 映射：DISCOVER → `workspace`；PREPARE/VALIDATE → `artifact_plans`；DEP_STRIP/TRANSPILE → `views`；COMPILE → `artifact_paths`；PRESTEP → `prestep`；CLEAN → `paths`；EXECUTE → `exit_code`。`Transpile_Context.plugin_state` 不是 `Stage_State`，保持现状（pipeline 插件的 per-run state，另属机制）。

**Hook 访问契约**：`if slot == null -> ERROR; if slot.kind != Expected -> ERROR; state := cast(*Expected) slot;`。`prestep_add_substitution` / `prestep_add_drop` 改为 kind check + `cast(*Prestep_Stage_State)`。正常构造不会 tag/payload desync；残余风险是手写 cast 撒谎，因此每次读取先查 `kind`。

**At hook 类型检查**：session 在调用 at hook **前与后**都检查 `ctx.<slot>.kind == 期望类型`；不匹配 = ERROR + 阶段失败。at hook 可以改 payload，但不能换 state 类型。

**迁移顺序**：

1. `src/lifecycle.jai`：加 `Stage_State` 基记录；`Prestep_Stage_State` 嵌入并自盖章；`prestep_add_*` 加 kind 检查。
2. 四个 command / test_runner 记录改名 + 嵌入 + 自盖章。
3. `Lifecycle_Context` 六个指针槽改 `*Stage_State`；session 的 `run_stage` 加 stage → slot 映射与 kind 检查。
4. 测试：`cast(*..._Stage_State)` + kind 检查；generated text 目前不携带这些类型，确认零影响（若 host / test runner 文本引用类型名，按 067 更新）。
5. `CONTEXT.md` 的 Stage state 措辞更新：基记录 / 契约由 lifecycle 拥有，payload 记录留各自模块。

**不改变**：`Lifecycle_Stage` 枚举与顺序、hook 表结构、`Transpile_Context.plugin_state`、生成程序文本（除非出现类型名引用）。
