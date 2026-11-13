---
title: jaix 插件化 effort（Package.plugins 统一声明面 + PRESTEP 插件 + plugin host）
labels: [wayfinder:map]
status: closed
---

## Destination

把 jaix 前置转译从命令编排与工具本体中移出，并把插件的声明、配置、激活与排序统一到 `Package.plugins`：

- **Phase 1（054-059）**：PRESTEP seam + `Package.plugins` 统一声明/配置面 + 静态内置 `juice-plugin-jaix`。
- **Phase 2（060-062）**：PRESTEP-only plugin host + `packages/juice-plugin-jaix` 成员包。

终态：`src/` 零 jaix 引用（机械守卫，Phase 2 后白名单为空）；`Package.jaix` / `Package.transpile` 硬切为 `Package.plugins`；jaix 只存在于成员插件；命令编排只认识 PRESTEP 阶段与源替换表。

## Notes

- **设计记录** = `docs/spec.md`（2026-10-21 设计修订，各节内标「设计修订（2026-10-21）」）+ `CONTEXT.md`（本 effort 新建的领域词汇）。本 map 只登记执行路线与决定，不复制规格全文。
- **顺序已由用户拍板**：1 → 4 → 2。Phase 1 = Candidate 1（PRESTEP seam）+ Candidate 4（统一声明/配置面）；Phase 2 = Candidate 2（plugin host + 成员包）。Candidate 3（整文件转译插件面并入 Transpile 管线）出范围：与 juice ADR-0008 决定 6 及「pre-step 与 Transpile 两层」直接冲突。
- **硬约束**：
  - 声明 = 可用 + 激活 + 配置 + 顺序；运行时 `dependencies` 永不激活插件；`workspace.members` 提供成员包。
  - 成员插件 id = 成员包名；内置 id `load` / `test-block` 保留；v1 一个插件包只提供一个插件；声明 version 必须等于插件 version。
  - PRESTEP 用 `before` 挂载（可堆叠、声明序），无内置实现；源替换表 append-only、仅 root package、不新增文件；重复键 / 替换与剔除同键 = 阶段失败。
  - Phase 1 的 jaix 插件静态驻 `src/jaix_plugin.jai`；Phase 2 搬进 `packages/juice-plugin-jaix/`，声明 id 不变。
  - 守卫：Phase 1 扫整个 `src/`，允许 `src/jaix_plugin.jai`；Phase 2 后白名单为空。
  - breaking change：`Package.jaix` / `Package.transpile` / `JAIX_*` / `TRANSPILE_PLUGIN` 记录与两道旧校验门移除；旧 package.jai 在 manifest 求值期失败；无兼容 shim。
- **验证骨架**（沿用旧 map 的三接缝形态）：① `jai build.jai`（debug/release）于根 exit 0；产物副本于根 build/test 全绿（SKIP 0 权威）；② 各阶段单元/集成测试驻 `tests/`（库面模块 test-free）；③ E2E 真子进程（真 `jai`、真 `juice.exe`、真 jaix CLI）；Phase 2 加安装布局 E2E。
- **本地 tracker 约定**（沿用旧 map）：map = 本文件；ticket = `tickets/NNN-*.md`（frontmatter 含 id/title/labels/status/assignee/blocked-by/blocks）；认领 = 写 `assignee: maojiaxing`；**frontier** = `status: open` 且 blocked-by 全 closed 且无 assignee 的票，按编号取最小；解决 = 票内 `## Resolution`、置 `status: closed`、本文件 Decisions so far 追加一行；`ready-for-agent` = 已就绪可认领。
- **每会话开工先读**：本 map Notes、`docs/spec.md` 相关章节、`CONTEXT.md`；Jai beta 0.2.009（`C:/Users/maojiaxing/DevTools/jai`）；Windows-first；交流语言中文。
- **旧 effort 的边界**：`docs/implementation/map.md`（阶段 0-3）已 closed；旧 juice 仓只读、零改动；兄弟项目（jaix/jaix-cli 等）不动。

## Ticket chain

| # | 标题 | blocked-by | 交付 |
| --- | --- | --- | --- |
| 054 | 设计修订：Package.plugins 统一声明面 + jaix 插件化 | — | spec 修订、CONTEXT.md、本 map 与 054-062 票（已由设计会话关闭） |
| 055 | Package.plugins 声明面 + manifest 协议 + 硬切 | 054 | `Plugin_Declaration` / `Package.plugins`；`PLUGIN` / `PLUGIN_OPTION` 协议；移除 jaix/transpile/JAIX/TRANSPILE_PLUGIN；fixture 迁移 |
| 056 | 插件面：options apply + registry/resolver + 声明驱动 lint | 055 | `Juice_Plugin.options`、`Config_Option.apply`、registry + `resolve_plugin_configs`、face 默认值、lint 声明迁移、成员插件扫描/链接 |
| 057 | PRESTEP 阶段 + 源替换表消费 | 056 | `Prestep_Stage`、`Lifecycle_Context.prestep`、build/test 的 before 派发、入口/文件替换与剔除 |
| 058 | 静态 jaix 插件（Phase 1） | 057 | `src/jaix_plugin.jai`；id `juice-plugin-jaix`；插件自带扫描/spawn/镜像/exe/litter；options `config`/`exe`；真实 jaix E2E |
| 059 | Phase 1 守卫 + 收口 | 058 | 全 `src/` jaix 守卫（允许 `src/jaix_plugin.jai`）；移除核心 litter 谓词；Phase 1 验收矩阵 |
| 060 | PRESTEP-only plugin host + 命令级 prepare | 059 | 命令级扫描/注册/成员链接；生成 host driver（嵌入输入、记录输出）；test metaprogram 复用注册；fixture 插件 E2E |
| 061 | jaix 搬入成员包 + 安装布局 E2E | 060 | `packages/juice-plugin-jaix/`；删静态注册；成员链接；安装布局 E2E；守卫白名单清空 |
| 062 | Phase 2 收口 | 061 | 全矩阵、发布树/行数、spec 执行级现实、CONTEXT/map 收口 |

## Decisions so far

- 2026-10-21 设计会话（054）：Phase 1 = Candidate 1 + 4；Phase 2 = Candidate 2；Candidate 3 出范围。统一 `Package.plugins`（id + version + options）取代 `Package.jaix` / `Package.transpile`；声明即激活/配置/排序；成员插件 id = 成员包名；不引入 `dev_dependencies`。PRESTEP = `before` 插件阶段 + 源替换表/剔除集；options 由 `Config_Option.apply` 落到类型化字段，hook 经 `plugin_state` 槽取 options；语义校验在 `resolve_plugin_configs` / merge 期；Phase 2 host 为 PRESTEP-only，命令级 prepare 写注册，host driver 嵌入输入、记录文件输出。breaking change 记录在 spec §11.12；领域词汇落 `CONTEXT.md`。
- 2026-10-21（055）：声明面与协议硬切完成 — `Package.plugins` / `PLUGIN` / `PLUGIN_OPTION` 落地，`Package.jaix` / `Package.transpile` / `JAIX_*` 协议记录 / `TRANSPILE_PLUGIN` / 两道旧门移除；`escape_record_value` / `unescape_record_value` 成为共享记录编码对；语义校验过渡期留在 `validate_plugin_declarations`，056 接管。验收基线：build debug exit 0；test `298 passed, 0 failed`；found = 479 + 5 = 484。`src/scan_walk.jai` 的 jaix litter 谓词按 058 交付表移除，不在 055 提前迁移。
- 2026-10-21（056）：插件面解析落地 — `Juice_Plugin.options` + `Config_Option.apply`；`merge_plugins` 保留 registry，`resolve_plugin_configs` 成为管线/钩子/lint/options 单一落点（无 transpile 声明 = 默认 `[load, test-block]`，hook 槽对齐 `slot_options`）；成员扫描改 `Package.plugins` 声明驱动（成员定位 + import shim + v1 一包一插件），lint 从根 DEP 迁到声明；命令侧按 Phase-1 边界只解析内置值，成员 version/options 在生成的测试 metaprogram 中校验；`validate_plugin_declarations` 过渡门移除。偏差记录在 056 Resolution（类型化 options 成员名 `config`、零-plan build 也做插件准备、坏 fixture E2E 不再观察行号保真门）。验收基线：build debug exit 0；test `310 passed, 0 failed`；found = 489 + 5 = 494。
- 2026-10-21（057）：PRESTEP 成为 build/test 真实阶段 — `Prestep_Stage`（root_dir/member_dirs/替换表/剔除集）+ `Lifecycle_Context.prestep`；命令在零 plan/零文件短路与 LNK1104 hand-off 之后、TRANSPILE 之前派发 before→after（无内置实现，未声明 = no-op；`at` 保留）。dispatch 表 = 声明解析出的 hook 表 + 调用方 hook 表（plugin_state 槽对齐 options 指针）。源替换表/剔除集由 `prestep_add_*` API 强制阶段级规则（同键异替换 / 替换与剔除同键 = ERROR 诊断失败，即使 hook 返回 true）。build 入口命中替换直编替换路径并跳过探测/剥离、剔除入口失败；test 逐文件替换（`rel_path`/编号/`path_mapping` 不变）与剔除；test 的 pipeline 解析上移到命令编排（一次解析传入 `Test_Transpile_Stage`）。验收基线：build debug exit 0；test `315 passed, 0 failed`；found = 507 + 5 = 512。
- 2026-10-21（058）：静态 jaix 插件落地 — `src/jaix_plugin.jai`（id `juice-plugin-jaix` @0.1.0：PRESTEP before hook + `config`/`exe` options；自带扫描、逐文件 spawn、`target/jaix/` 镜像 + `.map`、`target/jaix-drivers/` CWD、旧 litter 内容标记清理 + drop）。命令侧静态注册 seam = `static_builtin_plugins` → `command_plugin_registry`（`src/transpile_config.jai`）+ `is_command_static_plugin_id`（workspace scan 共享 skip）；生成测试程序只嵌 member 声明。核心 litter 谓词（`JAIX_DRIVER_MARKER`/`is_jaix_driver_litter`）删除，测试迁入 `tests/jaix_plugin_tests.jai`。偏差：注册落点不在 `plugin.jai`（发布闭包四件不含 jaix 模块，避免破坏 §9.2 数量契约）；`src/main.jai` 的 `#load "jaix_plugin.jai"` 是守卫需按行允许的结构引用。真实 jaix CLI（兄弟仓 `jaix-cli/target/jaix.exe`，PATH 注入）build/test/负例 E2E 全绿。验收基线：build debug exit 0；test `311 passed, 0 failed`；found = 527 + 5 = 532。
- 2026-10-21（059）：Phase 1 守卫 + 收口完成 — `tests/jaix_guard_tests.jai`（6 测试：`src/` 全量 jaix 记号文本扫描（含注释/字符串、逐行全命中、`path:line:column` 证据）+ 单源 Phase 1 白名单（`src/jaix_plugin.jai` 整文件 + `src/main.jai` 的装载行；061 清空）+ 移除协议名零残留 + 空白名单负向自测（实测 exit 1）+ 装载行活性检查）；生产代码零改动（058 已提前完成注释清理），`src/` 白名单外零 jaix 命中。验收：`jai build.jai` debug/release exit 0；release 产物副本于根 build/test exit 0、**SKIP 0**、白名单 6 行；jaix-demo 真 CLI build/test E2E 手动复跑全绿（`Running jaix pre-step (2 files)`、`3 passed, 0 failed`）；无声明包零变化；插件面闭包副本逐字节相等（571/553/364/596 行）。found = 533 + 5 = **538**（058 基线 532；+6 守卫测试）。frontier = 060。
- 2026-10-21（060）：PRESTEP-only plugin host + 命令级 prepare 完成 — 新模块 `src/plugin_host.jai`（main 闭包，非发布面）：`prepare_workspace_plugins` 是唯一扫描/注册落点（声明驱动扫描 + 成员 shim + `target/plugins/registration.jai`；零声明成员插件 = 无注册/无 host，并清理陈旧注册），build/test 在 PRESTEP 前调用；`test_compile_front` 删除二次扫描，只消费 prepare 的 `registration_path`（同注册喂 host 与测试 metaprogram）。host driver `target/plugins/host.jai` 嵌入 root/mode/member dirs/成员 `Plugin_Config`，`#import "juice_core"` + `#load <registration>`，spawn `jai -quiet -import_dir <modules> -import_dir <target/packages>`；`main()` = merge → resolve（options/版本）→ `run_mounted_hooks(.PRESTEP,.before)` → 记录文件 `SUBSTITUTE/DROP/DIAG/OK`（逐字段 `%XX`，host 生成编码器 ↔ 父进程 `unescape_record_value` 互逆），父进程严格解析、经 `prestep_add_*` 并入 `Prestep_Stage`；非零退出/缺记录/坏记录/OK=0/ERROR 全部编译前失败。触发 = 扫描期 `hooks` IDENT 保守探测（`Plugin_Scan_Result.has_hooks`）；静态内置插件仍进程内派发（061 移除）。fixture `tests/data/plugin-prestep-fixture` 真 E2E（build 替换入口、test 丢弃失败文件、options/merge/crash 负例）；+18 测试。验收：`jai build.jai` debug/release exit 0；直跑 test `329 passed, 0 failed`、SKIP 2；release 副本 SKIP 0；found = 551 + 5 = **556**（059 基线 538）。Deviations（host 先于进程内静态 hook、成员 after 不跑、词法触发、test 零文件短路先于 prepare 等）见 060 Resolution。
- 2026-10-21（061）：jaix 搬入成员包 + 安装布局 E2E 完成 — 新成员 `packages/juice-plugin-jaix/`：`package.jai`（LIB、零工具依赖、无 targets）+ 根 `module.jai`（test-free：`#import "juice_core"`、`get_juice_plugin` + `@juice_plugin`、PRESTEP `before` hook、`config`/`exe` options schema、插件自带扫描/spawn/镜像/litter——成员不能复用工具内部的 `scan_walk`/`path_safety`/`xdg.get_env`，故自带 DFS 枚举、路径助手与 Windows/POSIX 环境探测）+ `tests/`（17 单元测试，成员根运行）。删除 `src/jaix_plugin.jai` 与 `src/main.jai` 装载行；`command_plugin_registry` 只剩内置值（058 的静态 seam 实际落在 `src/transpile_config.jai`，非票面 `src/plugin.jai`）；根 `package.jai` 加 `workspace.members` + 无 options 的 `juice-plugin-jaix` 声明（config 空 = 定义好的 no-op，根构建每次多 spawn 一次零效果 host），无同名 DEP；守卫白名单清空、`src/` 零 jaix 命中。接线：命令级 prepare 按声明定位成员写 shim/注册，host 应用 options 执行 PRESTEP；Phase 1 的 build/test/失败/缺 exe/未声明 E2E 在成员 + host 形态全绿（host 记录 `SUBSTITUTE`/`DROP`/`OK=1`）；成员根套件 17 passed；安装布局全链 E2E（真实成员整树复制、绝对 exe option）build/test 全绿 + 缺成员/缺 shim/缺插件面负例；零插件包不写注册、不 spawn host。发布件 8 件不变，四份闭包副本与 `src/` 逐字节相等（571/553/364/596 行；本次未改闭包源，票面“行数更新”不适用）。验收基线：`jai build.jai` debug/release exit 0；根 test exit 0、直跑 SKIP 2、release 副本 SKIP 0；found = **537 + 5 = 542**（060 基线 556；成员套件另计 17）。Deviations 见 061 Resolution。
- 2026-10-21（062）：Phase 2 收口完成 — 全矩阵复核全绿（`jai build.jai` debug/release exit 0；debug/release 产物副本于根 build/test 各 exit 0、SKIP 0、`329 passed, 0 failed`；直跑 SKIP 2；found = max `juice_test_N` 537 + 手写 5 = **542**，与 061 基线一致，本票无测试增删；预期失败白名单恰 6 行，白名单外零失败）；真实 jaix build/test E2E、成员根套件（17 passed）、安装布局全链 E2E 与缺成员/缺 shim/缺插件面/坏插件/坏 options 负例随副本跑全绿；守卫白名单为空、`src/` 32 文件零 jaix；发布树 8 件复核（112/237/16 + 285 + 571/553/364/596，四份闭包逐字节相等）。spec 折回执行级现实（顶部状态、§0/§2/§3/§4/§5/§6/§7 注记、§8.3 Phase 2 形态、§9.2 发布树/行数、§10 收口矩阵、§11.12-16 终态处置），CONTEXT 增补 registration file / host record。effort 关闭；未来项留在 Not yet specified（外部插件坐标、通用 host、非插件 devDeps、Candidate 3、lint/`.map` 扩展）。本票未改生产代码/测试。

## Not yet specified

- 外部插件包（非 workspace member）的 `source` / `package` 坐标与抓取：v1 只支持成员包；未来在 plugin entry 上扩展，不引入 devDependencies。
- 通用 lifecycle host（PRESTEP 之外的 stage/position）：本 effort 只交付 PRESTEP-only；接口按可加宽设计。
- 非插件测试库的 devDependencies 分类：本 effort 不需要；若未来出现再独立设计。
- 整文件外部转译器作为 Transpile 管线插件面（Candidate 3）：与 ADR-0008 决定 6 冲突，未排期。
- lint 规则/面进一步扩展、插件选项类型化展示、`.map` 消费方：随未来票。

## Out of scope

- 旧 juice 仓任何改动；旧 ADR 体系迁移；兄弟项目改动。
- linkme/动态库等通用第三方宿主（spec §11.7 立场不变）。
- 整文件转译插件面（Candidate 3）。
- 外部插件抓取、workspace glob members、`--workspace` 聚合等 spec §11.8 未来特性。
