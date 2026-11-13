---
id: 063
title: Jai tagged union 表达力
labels: [wayfinder:research]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [065]
---

# 063: Jai tagged union 表达力

## Question

Jai 能否表达带异构 payload 的 tagged union（Stage state），并让 lifecycle hook 安全访问？

已知：`Lifecycle_Context` 现在用 `*void` slots（`src/lifecycle.jai:137-168`），因为每个 stage 的 state 是不同类型；用户已拍板 stage state 用 tagged union，但前提是语言能干净表达。

需要事实：

- Jai（beta 0.2.009 / 0.2.9）的 union / any / sum type 语法、运行期 tag 与复制语义。
- 异构 payload（`Build_Transpile_Stage`、`Test_Transpile_Stage`、`Test_Compile_Stage`、`Prestep_Stage`）的存储、访问与生命周期。
- 与 `*void` + cast 的样板量、类型安全、调用点可读性对比。
- 若原生 union 不适合：最小可行替代（tag + `*void` payload；共享 typed records + cast）与推荐。

产出：`docs/research/jai-tagged-union.md`，含至少 2 个候选形状、代码样例与推荐；本票 `## Answer` 记录结论，供 065 消费。不要改生产代码。

## Answer

结论：Jai（beta 0.2.009）**没有原生 sum type / tagged union**。`union` 是 C 式无标签联合（成员全 offset 0，无运行期 active member，`if case` 不匹配 union 分支）；`Any` 是 16 字节的 boxed 非持有引用（`*Type_Info` + `*void`，存值/存指针 tag 不同、寿命无检查），不是 sum type。官方承认的表达方式有两个用户级先例：`modules/Tagged_Union.jai`（`tag: Type` + inline bytes + `set`/`isa`，demo 级、按值拷贝）与 `how_to/008`/`how_to/120` 的 Type tag + `#as using base` 记录层次。

推荐：**共享 typed records + Type tag + `#as using base`**（候选 D）。`Stage_State :: struct { kind: Type; }` 作基记录放共享模块；各 stage 记录首字段 `#as using base: Stage_State;` 并由构造器自盖章 `base.kind = <自身类型>`；context 槽由 `*void` 改为 `*Stage_State`（或单 `state` 槽，由 065 决定），构造点 `lctx.views = *tstage` 与读取点 `cast(*Test_Transpile_Stage) ctx.views` 均零改动。hook 读取契约 = 先 `kind` 比对、再 cast；at hook 的类型检查因此可实现。正常构造不可能 tag/payload desync；残余风险仅为手写 cast 撒谎，故每次读取必须先检查 `kind` 并把不匹配升级为 ERROR 诊断。落选理由：原生 union 无 tag 且误读静默；`Any` 非持有、boxing 与寿命陷阱、误读崩溃；tag+`*void` 两处写可 desync 且违反 `*void` 纪律；官方 `Tagged_Union` 模块是 inline 拷贝的 demo，与 host-owned 记录现状错配。约束：stage 记录禁止 `---` 构造（跳过盖章）；不要按 `Stage_State` 值传递（切片只剩 tag）；payload 记录不必搬进 `src/lifecycle.jai`（会拖 Juice/scan 依赖进 bootstrap 闭包），Type-base 只要求基记录在共享模块。

完整证据、代码样例、探针输出与迁移草图：[docs/research/jai-tagged-union.md](../../research/jai-tagged-union.md)。
