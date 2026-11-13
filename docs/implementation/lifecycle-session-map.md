---
title: Command lifecycle session 与 lifecycle 精简 effort（Candidate 01 + 03 + 04 + S1/S2/S3）
labels: [wayfinder:map]
status: open
---

## Destination

为 Candidate 01（Command lifecycle session）与 S1/S2/S3（lifecycle 精简）产出一组锁定的设计决策与 spec：把 build/test 的命令级 lifecycle 编排收进一个 session 面；把 9×3 通用挂载矩阵收成 typed stage seam，**TRANSPILE 降为 COMPILE 的 before hook**；成员插件面只留 PRESTEP hooks；host 协议单源到发布 runtime；并统一零文件包上的 plugin declaration 校验。后续 `/implement-spec` 据此落地；本 effort 不产出生产代码。

## Notes

- **本 effort = 设计决策/spec**（用户拍板，2026-10-22）。执行由后续 `/implement-spec` 承接，票不切实现。
- **范围 = Candidate 01 + 03 + 04 + S1/S2/S3**（2026-10-22 复评扩展）。Candidate 02（plugin declaration plan）、05（view production）、06（generated bootstrap emitter）、07（publication producer）、08（Workspace_Discovery accessors）出范围；general lifecycle host 出范围（见 Out of scope）。S3 是 host runtime 的行为单源，不是 Candidate 06 的文本 emitter。
- **架构输入**：2026-10-22 架构审查报告（系统临时目录，`architecture-review-20261022-103757.html`）、2026-10-22 lifecycle 精简复评（`architecture-review-20261022-114721.html`，Gradle 对照）与子代理报告；ticket 内以 `file:line` 锚点引用。
- **已拍板（2026-10-22 grilling）**：
  - session 拥有 full protocol：plugin prepare、resolver、context、PRESTEP host、PRESTEP dispatch、before → at | builtin → after 的 stage 执行；命令只给 prelude 与 stage body。**（069 已闭：typed seam + TRANSPILE 为 COMPILE 首个 before 步骤；session 落 `plugin_host.jai`。）**
  - `begin` 含 host；零文件 `juice test` 也走声明校验（与 build 统一）。
  - member hook 只允许 PRESTEP/before；其它声明在 prepare 期响亮失败。AT 明确为 in-process 测试 seam，不是 plugin 承诺。**（070 复评：类型级 `prestep_hooks`，host 不再运行时校验。）**
  - host 在声明了成员插件时 spawn；源码里的词法 `hooks` 探测退役。
  - `Hook_Registration` 携带 state；`slot_options` / `plugin_state` 平行数组退役。**（069 已闭：`Seam_Registration($State)` 携带 state；070 只定公开 `prestep_hooks` 面。）**
  - stage state 用 tagged union；[Jai tagged union 表达力](tickets/063-jai-tagged-union.md) 已确认 Jai 无原生 sum type，推荐 Type-tag base record 形态；设计在 [Stage state 的 tagged union](tickets/065-stage-state-tagged-union.md) 锁定。只有 `Stage_State` 基记录进共享模块，payload 记录留在原处（避免把 Juice/scan/transpile 依赖拖进 bootstrap `#load` 闭包）。**（069 已闭：typed state，每命令一个扁平记录，无 tag / 基记录；065 的 tag 方案作废。）**
  - 模块并入 `src/lifecycle.jai`（不新建文件）；领域术语 = **Command lifecycle session**。
  - 生成文本只改强制项（host / registration）；test runner / build metaprogram / version assertion driver 保持逐字节；行为等价；零文件 test 与零 target build 的 host 级声明校验是有意的行为变化。**（071 复评：host runtime 单源。）**
- **2026-10-22 复评（Gradle 对照 + lifecycle 精简）**：S1/S2/S3 纳入本 effort；新票 [S1 · lifecycle 精简](tickets/069-s1-typed-stage-seam-transpile-before-compile.md) / [S2 · 成员插件面](tickets/070-s2-member-prestep-face.md) / [S3 · host 协议单源](tickets/071-s3-host-runtime-single-source.md)。
  - **S1 · [lifecycle 精简](tickets/069-s1-typed-stage-seam-transpile-before-compile.md)**：9×3 矩阵收成 typed stage seam；**TRANSPILE 降为 COMPILE 的 before hook**（用户拍板方向）；active stage seam = PRESTEP + COMPILE；`at` 是 body，不是第三个 position；context bag / Stage_State tag 由 typed state 取代。
  - **S2 · [成员插件面](tickets/070-s2-member-prestep-face.md)**：成员插件面只留 `prestep_hooks`；host 不再做运行时 stage/position 校验；in-process 测试钩子走独立 seam。
  - **S3 · [host 协议单源](tickets/071-s3-host-runtime-single-source.md)**：host 的 merge / resolve / validate / dispatch / record 单源到发布 runtime；生成文本只留 data + 一次调用。
  - **取代关系**：064 的 session 归属、`begin` 含 host、零文件统一校验保留；065 的 tagged union、066 的 host 运行时校验、067 的 generated-text 策略由 S1/S2/S3 复评。S1 已闭：`CONTEXT.md` 的 Stage state / Stage seam 措辞已更新。
- **本 effort tickets**：`docs/implementation/tickets/063-071`（九张；068 为收口 task，S1/S2/S3 为本轮复评新增）。frontier 判定 = `status: open` + `blocked-by` 全部 closed + `assignee` 为空；按编号取最小。
- **领域词汇**：`CONTEXT.md`（Command lifecycle session / Stage state；Stage seam 待 S1 锁定后补）。每个会话开工先读本 map Notes 与相关 ticket。
- **版本库**：otter 无 git repo；research 产物落 `docs/research/`，不建 branch、不开 PR；提交归用户。
- **硬约束**：
  - spec §11.7 第三方宿主（DLL/进程外）出范围；`plugin_host.jai` 保持 PRESTEP/before only。
  - ADR 0008：声明序 = 管线序 / hook 序 / lint 序；ADR 0005：视图行号保真；bootstrap `#load` 集 test-free。
  - 不改变 `Package` / `Package.plugins` 公开声明面；不新增 lifecycle stage。S2 只改 `Juice_Plugin` 的发布面，不改 `Package.plugins`。
  - S1 重开 spec §6.1/§6.3 的矩阵承诺；9 值枚举保留为 vocabulary / 报告标签，不驱动 dispatch；不新增 lifecycle stage；不产出生产代码。
  - 三路径验证继续：自举循环、姊妹测试、E2E 真子进程。
  - 生成文本策略由 S3 复评：S3 后 host 生成文本只留 data + 一次调用；067 的“只改强制项 / 逐字节 pin”在 S3 闭票前仍作基线。
- **技能**：grilling、domain-modeling、codebase-design。每个 ticket 按 `wayfinder:<type>` 标签执行。

## Decisions so far

<!-- 每个 closed ticket 一行：标题链接 + 一句 gist；详情只在 ticket 里。 -->
<!-- 063-067 是复评前的路线；069-071（S1/S2/S3）闭合后在此追加。 -->
- [Jai tagged union 表达力](tickets/063-jai-tagged-union.md): Jai 无原生 sum type；推荐 Type tag + `#as using base` 共享 typed records（union 无 tag、Any 非持有、`*void` 可 desync 均落选），hook 先查 `kind` 再 cast。
- [Command lifecycle session 接口与命令边界](tickets/064-session-interface-command-boundary.md): prelude → begin → zero-work 短路 → stages；begin 含 host，两条命令零工作也校验；`run_stage` 拥有 before → at | builtin → after；`build_prepared_workspace` / `test_prepared_workspace` 保留为薄适配器。**（069 取代 `run_stage` 为 typed seam 入口。）**
- [Stage state 的 tagged union](tickets/065-stage-state-tagged-union.md): `Stage_State` 基记录 + Type tag + 逐 stage `*Stage_State` 槽；记录改名 `*_Stage_State`；hook 先查 `kind` 再 cast，at hook 前后都查。**（069 取代：typed state，无 tag / 基记录。）**
- [Member hook 面与 registration state](tickets/066-hook-face-registration-state.md): host 权威校验 member hook 仅 PRESTEP/before；spawn = `registration_path != ""`；`Hook_Registration` 携带 state，`slot_options` / `plugin_state` 退役；registration 的 hook entries 视图退役。
- [生成文本与测试策略](tickets/067-generated-text-test-strategy.md): 只改 host / registration 生成文本，其余逐字节；pin 保持精确；session 测试用真 fixture + fake host spawn；完成定义 = 三路径 + pre/post 计数记录；C06 不强制。
- [S1 lifecycle 精简](tickets/069-s1-typed-stage-seam-transpile-before-compile.md): PRESTEP + COMPILE 两个 typed seam；COMPILE = front（首位 before 步骤）→ before hooks → body（内置 / 旧 COMPILE AT）→ after；每命令一个扁平 state；`Seam_Hook` / `Seam_Registration` / `run_seam`，删矩阵 / context / tag / `plugin_state`；9 值枚举留 vocabulary；session 落 `plugin_host.jai`（取代 064 的 lifecycle.jai 落点）；发布面破坏不留 shim；测试按行为迁移、删矩阵专属；spec §6.2/6.3/6.5/7.4 改写。

## Not yet specified

- **Session 是否成为 plugin 公开面**：S2 只把成员插件面收到 `prestep_hooks`；session 本身是否成为更大的 plugin 面仍未定，等 S2 锁定后再看。

## Out of scope

- **general lifecycle host / spec §11.7**：用户 2026-10-22 明确收窄回 PRESTEP/before；扩展 host 到全部位置需要 stage state 跨进程传递，作为独立 effort。
- **clean/run 接入 Command lifecycle session**：destination 只覆盖 build/test；S1 锁定 typed seam 后接入成本已降低，留待独立 effort。
- **Candidate 02**（plugin declaration plan + member identity）——架构报告已记录，未选择。
- **Candidate 05**（view production 收成一个接口）——未选择。
- **Candidate 06**（generated bootstrap emitter）——067 确认本次不强制；S3 · host 协议单源是 host runtime 的行为单源，不是文本 emitter，已纳入范围。
- **Candidate 07**（publication producer）/ **Candidate 08**（Workspace_Discovery accessors）——未选择。
- **公开 Package / Package.plugins 声明面变化**；S2 只改 `Juice_Plugin` 的发布面，不改 `Package.plugins`；新 lifecycle stage；Published Juice face 的内部状态分离（仅在报告 “Also noted” 记录）。
- **Stage plan engine / pre-wiring 未来 mount**：2 个固定 seam（PRESTEP/COMPILE）不需要 Gradle 式 task graph；一个 mount 只有在有真实生产实现 + 测试 adapter 时才接线（2026-10-22 精简复评；069 已闭，矩阵删除，YAGNI）。
- **Command-level before/after plugin hooks**：当前没有真实 consumer。命令边界已经是显式 prelude + session 返回，不需要再包一层通用 hook；Gradle 的 `buildStarted` / `buildFinished` 也是框架固定 typed 事件，不是 plugin 声明的通用矩阵。若未来出现真实 observer（lint 汇总、jaix 清理、计时/报告），按 typed session event（`configured` / `finished(outcome)`）加，in-process only；member 面仍只有 PRESTEP hooks，不回到 stage/position 矩阵。
- **旧 juice 仓**（只读参照物）；其处置不在本 map。
