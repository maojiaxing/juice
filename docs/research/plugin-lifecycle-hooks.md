# otter 构建 lifecycle 扩展点挂载机制研究

> 研究问题：otter 的插件除了命令级（build/clean 内置、test/transpile/lint 为插件），还需要挂载到构建过程的各个 lifecycle 阶段。本文精确映射 juice 当前构建过程的阶段序、盘点现成的注入 seam，参考 jaix 挂点与 Transpile_Plugin 成对钩子两个先例，推出 otter 的 lifecycle 挂载面设计。
> 日期：2026-10-19 | 环境：Jai beta 0.2.009，Windows 11 + Git Bash
> 证据标注：【源码】= 本仓库/发行版源码逐行阅读 | 【官方文档】= 官方注释原文 | 【推断】= 基于事实的推理，非直接证据
> 姊妹篇：`plugin-auto-discovery.md`（插件如何被发现并进入注册表）；本文只处理"注册之后的挂载面"。二者共同的结论：注册由工具生成（扫描/静态），挂载由框架的固定编排序 + 显式注册表执行。

## 结论摘要

| 问题 | 判定 |
| --- | --- |
| juice 构建 lifecycle 阶段映射 | 完成。五命令（build/test/run/clean + 命令级 dispatcher）+ workspace 三态状态机，阶段清单见 §1（全部 file:line 一手核验） |
| 现成挂载点盘点 | 14 个 `#type` 形参 seam（§2 清单）——"单步可替换"已是既定形态；lifecycle 挂载 = 把它泛化为"阶段边界上的有序多钩子" |
| 挂载模型先例 | jaix 三挂点（DECL/STMT/EXPR）+ 配置序 passes + Hook_Env 框架注入；Transpile_Plugin 成对探测钩子 + 模式适用性声明 + 声明序派发 + claim 契约 |
| otter 挂载面设计 | 【推断】阶段枚举 + before/at/after 三位置；钩子适用性声明进插件结构；阶段序硬编码、阶段内钩子序 = 声明序；跨阶段状态走显式 ctx（无闭包约束）；失败 = 阶段失败传播 |
| 与命令级插件的关系 | 正交组合：命令 = 顶层编排入口（决定跑哪些阶段），lifecycle 钩子 = 命令实现内部阶段边界的挂载面；两者注册表独立、合并校验同 shape |
| bootstrap 约束 | 内置钩子骨架必须是 bootstrap `#load` 集的 test-free 静态代码；第三方钩子不进入该闭包（与 auto-discovery 两级结论一致） |
| 缓存键 | 钩子集（id+version+适用阶段）进管线描述分量（0062 先例）；无缓存阶段（run/clean）不涉及 |
| 与 Part 4 结论的衔接 | lifecycle 钩子走同一条扫描发现 + 生成显式有序注册文件路径（钩子 = 插件值内的数据，非独立发现实体）；生成文件第二段 = 钩子条目装配（§5.4） |

---

## 1. juice 构建过程 lifecycle 阶段映射（一手逐行）

### 1.1 进程级与命令级（`src/main.jai` + `src/dispatcher.jai`）

| 阶段 | 触发条件 | 可观测状态/产物 | 引用 |
| --- | --- | --- | --- |
| CLI 解析 | 每次启动；缺省命令 = build | `command` 字符串 + `command_arguments` 数组 | `main.jai:28-36` |
| Command_Context 构造 | 每次启动 | `root_dir`（启动 CWD）+ `cache_dir`（XDG cache home 下 `juice/`）+ `workspace` 状态机 | `main.jai:38-45` |
| 注册表校验 | 每次 dispatch | 无效声明/重名/未知前置 → 立即拒绝，不执行任何 handler | `dispatcher.jai:35-59` |
| 命令图规划（DFS） | 每次 dispatch | 环检测、菱形去重、前置命令恒收空参数；全图规划成功才开始执行 | `dispatcher.jai:64-92` |
| 命令逐序执行 | 规划成功 | 前置失败 = `PREREQUISITE_FAILED`、目标失败 = `HANDLER_FAILED`，立即中止 | `dispatcher.jai:112-120` |

命令级前置链现状：唯一前置关系 = `run` 依赖 `build`（`commands/registry.jai:31` 测试钉住 `RUN_COMMAND.prerequisites == ["build"]`；`run.jai:11`）——**命令级"阶段挂载"（前置链）已存在且经 dispatcher 校验**。

### 1.2 workspace 状态机（`src/workspace.jai`）

| 阶段 | 触发条件 | 可观测状态/产物 | 现有 seam |
| --- | --- | --- | --- |
| EMPTY | 初始 | 无任何状态 | — |
| → DISCOVERED | `ensure_workspace_discovered`（幂等：非 EMPTY 直接返回） | 根路径安全检查、manifest 求值（子进程协议）、member 校验、`Workspace_Discovery` 发布 | `discover` 形参（`workspace.jai:124`，默认 `discover_workspace`） |
| → PREPARED | `prepare_workspace`（幂等；要求先 DISCOVERED） | artifact plan 解析 + 依赖解析/获取；**失败不发布部分状态**（"Publish a prepared result only after every required step succeeds"，`workspace.jai:138-139`）；0 plan 时跳过依赖准备，`force_dependencies` 变体（test 用） | `resolve`（`:148`，默认 `resolve_artifact_plans`）、`prepare_dependencies`（`:149`，默认 `resolve_and_fetch_dependencies`） |

### 1.3 build 命令（`src/commands/build.jai`）

`build_command`（`build.jai:17-31`）→ `build_prepared_workspace`（`:208-250`）阶段序（代码注释编号 + 逐行核验）：

| # | 阶段 | 触发条件 | 可观测状态/产物 | 现有 seam |
| --- | --- | --- | --- | --- |
| b1 | 参数校验 | 每次 | 拒绝非零参数 | 无（`validate_arguments`） |
| b2 | workspace 准备 | 每次（幂等） | PREPARED 状态 | §1.2 三 seam |
| b3 | 零 plan 短路 | `artifact_plans.count == 0` | LIB/BIN 各自提示，不创建 target/ | 无 |
| b4 | 批量重校验 | plan 数 > 0 | 包根/artifact 路径/源文件安全性全量复核，任一失败即全量拒绝（"an unsafe plan cannot produce a partial build"，`:37-39`） | 无 |
| b5 | 依赖剥离前端 | plan 数 > 0 | 依赖闭包探测 + STRIP 视图落 `target/transpile/deps/` + shim 改写 | 经 `transpile` 形参（`:210`） |
| b6 | jaix 前置 | root package 有 jaix marker | 全包扫描 → 逐文件 spawn jaix → 镜像 `target/jaix/` | `prestep` 形参（`:212`，默认 `run_jaix_prestep`） |
| b7 | 逐 plan 入口选择 | 每 plan | 探测入口闭包：test-free 直编原文；含 test 整闭包 STRIP 视图；jaix marker 直选镜像入口（`:166-197`） | `transpile` 形参（`:169`） |
| b8 | 逐 plan 编译 | 每 plan | 生成 metaprogram（`generate_compiler_metaprogram`）→ 写 `target/build-<name>.jai` → spawn jai → artifact 存在性检查 | `compile` 形参（`:211`，默认 `compile_artifact_plan`，`:62-112`） |

### 1.4 test 命令（`src/commands/test.jai`）

`test_command`（`test.jai:28-39`）→ `test_prepared_workspace`（`:105-321`）阶段序（代码内注释 0-8 编号）：

| # | 阶段 | 触发条件 | 可观测状态/产物 | 现有 seam |
| --- | --- | --- | --- | --- |
| t0 | workspace 准备 | 每次（幂等，`force_dependencies = true`） | PREPARED（LIB 零 target 也准备依赖） | §1.2 三 seam |
| t1 | 全包发现 | 每次 | 确定性 DFS 扫描（排除集：dot/target/tests/data/modules/manifest/驱动垃圾/member 子树），`Test_Source_File` 列表 | 无（scan_walk 的排除谓词注入） |
| t2 | jaix 前置 + 镜像路由 | 有 marker | prestep 镜像 + 编译输入集改指镜像视图（配置文件剔除，`:132-151`） | `prestep` 形参（`:112`） |
| t3 | 逐文件 EXPAND 转译 + 全局编号 + pattern 过滤 | 每次 | 每文件视图文本 + 缓存键 + Test_Entry 清单；诊断拒绝；编号跨文件续号（`:153-178`） | `transpile` 形参（`:109`，默认 `transpile_test_file`） |
| t4 | 零测试短路 | 无 test 块 | 提示 + 成功退出，不构建 | 无 |
| t5 | 内容寻址视图路径计算 | 每次 | 逐文件键 → hash 目录路径（命中跳过写入） | 无 |
| t6 | Testing 模块特例 | 包内存在 `modules/Testing.jai`（或发行版模块） | EXPAND 视图（含自测段）+ 全局编号续号；用户包 STRIP 视图（`:213-226,349-412`） | 无 |
| t7 | 零匹配短路 | pattern 无命中 | 提示 + 成功退出 | 无 |
| t8 | 视图落盘 | 每次（内容寻址命中跳过） | `target/transpile/<hash>/<rel>` | 无 |
| t9 | Testing 模块编译视图落盘 | t6 enabled | `target/testing-module/Testing.jai`（会话产物，不缓存） | 无 |
| t10 | driver + metaprogram 生成 | 每次（每跑重生，不缓存） | `driver.jai`（视图 #load 表 + path_mapping + 显式 `run(name, juice_test_N)` 调用表，`:496-519`）+ `first.jai`（metaprogram，NO_OUTPUT，`:289-312`） | 无 |
| t11 | 依赖剥离前端 | 每次 | 依赖闭包 STRIP 视图（依赖内测试不发现不执行，仅保编译） | `dep_transpile` 形参（`:111`） |
| t12 | 编译（= 执行） | 每次 | spawn `jai -quiet first.jai`——测试经编译期 `#run` 执行，退出码 = 通过/失败（`:86-96`） | `compile` 形参（`:110`，默认 `compile_test_program`） |

### 1.5 run 与 clean（`src/commands/run.jai` / `clean.jai`）

| # | 阶段 | 触发条件 | 可观测状态/产物 | 现有 seam |
| --- | --- | --- | --- | --- |
| r1 | 参数校验 + workspace 准备 | 每次 | PREPARED | §1.2 |
| r2 | 目标选择 | 每次 | 大小写敏感（`:30-45`）；缺省 = 单目标/同名目标 | 无 |
| r3 | artifact 重校验 + 启动 | 每次 | 路径安全复核 → 存在性 → `run_command` → 退出码 | `launch` 形参（`run.jai:65`，默认 `run_artifact_plan`） |
| c1 | discovery（**不 prepare**） | 每次 | manifest 求值 + member 校验（无依赖获取） | `discover` seam |
| c2 | 路径收集 | discovery 成功 | root + 全部 member 的 `target/` 路径表 | 无 |
| c3 | 先全量校验后删除 | 每次 | **validate 全部通过才开始删除任何路径**（`:55-58`）；逐项删除、失败继续汇总 | `validate_path`/`delete_path` 形参（`clean.jai:38-39`） |

### 1.6 bootstrap 构建（`build.jai`，自举元程序）

`build.jai` `#run` 的注释编号阶段（`build.jai:68-110+`）：1. 读命令行参数（`- release` 开关）→ 2. `set_build_options_dc(.{do_output=false})` + 空 workspace（Default_Metaprogram 回退抑制）→ 3. 剥离前端（入口闭包探测 → test-free 直编 / 全闭包 STRIP 视图落 `target/transpile/bootstrap/`，PLAIN 布局恒写）→ 4. Testing 模块特例 → 5. 生成 metaprogram + spawn 子进程 jai（`bootstrap_build_entry`，`build.jai:43-66`）。**bootstrap 是 Build command 的同一剥离前端 + metaprogram 生成器的复用，只是布局与缓存语义不同**（ADR 0006）。

---

## 2. 现有注入 seam 全集（lifecycle 挂载点的现成证据）

全部是 **`#type` 形参 + 生产默认值 + 集成测试录制假实现跨同一接口**（`build.jai:199-207` 注释原文："production handlers use the defaults; tests cross the same interfaces with recording adapters instead of the real compiler"）：

| # | seam | 签名位置 | 生产默认 |
| --- | --- | --- | --- |
| 1 | `discover` | `workspace.jai:124` | `discover_workspace` |
| 2 | `resolve` | `workspace.jai:148` | `resolve_artifact_plans` |
| 3 | `prepare_dependencies` | `workspace.jai:149` | `resolve_and_fetch_dependencies` |
| 4 | build `transpile` | `build.jai:210` | `transpile_build_file` |
| 5 | build `compile` | `build.jai:211` | `compile_artifact_plan` |
| 6 | build `prestep` | `build.jai:212` | `run_jaix_prestep` |
| 7 | test `transpile` | `test.jai:109` | `transpile_test_file` |
| 8 | test `compile` | `test.jai:110` | `compile_test_program` |
| 9 | test `dep_transpile` | `test.jai:111` | `transpile_build_file` |
| 10 | test `prestep` | `test.jai:112` | `run_jaix_prestep` |
| 11 | clean `validate_path` | `clean.jai:38` | `clean_path_is_safe` |
| 12 | clean `delete_path` | `clean.jai:39` | `delete_directory_full` |
| 13 | run `launch` | `run.jai:65` | `run_artifact_plan` |
| 14 | jaix spawn `transpile` | `jaix_front.jai:206` | `spawn_jaix_transpile` |

关键形态事实【源码】：seam 全部是**单步替换**（一个形参换一个阶段实现），不是"阶段边界上的多钩子列表"。插件化 = 把"单步可替换"泛化为"有序多步管线/钩子列表可注册"（`transpile-plugin-architecture.md` 结论 3 的同一表述——lifecycle 挂载面就是这条路的第二落点，第一落点（transpile 管线）已落地为 `transpile_plugin.jai`）。

---

## 3. 挂载模型先例（两个一手形状）

### 3.1 jaix：挂点声明 + 有序 pass + 框架注入 env

- **挂点枚举 + 关联表**：`Hook_Point :: enum { DECL; STMT; EXPR; }`（`jaix/src/plugin.jai:93-97`，007 决议 4 三挂点）；`Plugin_Grammar_Entry { hook, kind, fragment }`（`:104-108`）——**"挂点 × 片段"的关联表数组**，插件声明自己适用哪些挂点。
- **框架注入**：片段运行期 `state` = 框架注入的 `*Hook_Env`（构造期恒 null、不得独立直跑，必须经 merge 装配后走 `parse_tokens`/`program` 通路——`:69-73`）；`env.b` = parse builder、`env.block` = 完整块 parser（递归统一，009 决议 5）。**"插件状态由框架注入、插件不得自造上下文"**是显式 ctx 通道的强形式。
- **有序管线**：`passes: [..] Pass`，**配置序 = pass 序**（`:65`，009 决议 6）。
- **合并期校验**（`merge_plugins`，`:51-80`）：同挂点文法片段按声明序拼 choice（PEG ordered choice 先者赢）；关键字 claim 冲突 = 硬诊断；同 id 重复/异版本 = 注册期诊断；node_kinds 范围 + claim 独占 + 保留 kind 独占通道（内置插件专属）；**合并失败 = 全 ERROR 诊断 + `ok=false`，调用方拒绝继续**。合并产物 `Merged_Pipeline {hook_slots, passes, registry, plugins, diagnostics, ok}` 直接喂执行器，无二次转换（`:52-55`）。

### 3.2 Transpile_Plugin：成对探测钩子 + 模式适用性 + 声明序派发 + claim 契约

- **成对钩子**（`juice/src/transpile_plugin.jai:56-83`）：`has_anchor`（闭包视图决策的探测，可空跳过）与 `load_edges`（闭包 DFS 边源，可空）配对 `transpile`（逐 token 派发钩子）——**探测钩子回答"我在哪里生效"，执行钩子回答"我做什么"**。这是"插件声明适用阶段"的最接近先例。
- **模式适用性声明**：`Transpile_Plugin_Modes {strip, expand}`（`:28-36`）——声明性门控，runner 派发前检查（`:484`）。
- **派发序 = 声明序**（`:483-491`）；默认注册表 = 两个内置插件按旧分支序（`:359-367`）；空注册表 = 缺省管线（`resolve_pipeline`，`:374-377`，spec 0060 决定 3）。
- **claim 区域契约显式化**：插件 claim 覆盖恰好其消费的 token；未消费区域继续派发（`:447-457`）——lifecycle 钩子的"阶段所有权"需同款显式定义。
- **跨文件状态通道**：`Transpile_Context.plugin_state` 槽与管线序对齐，调用方持有存储、跨 `transpile_source` 调用续走（`:71-75,486-487`）——**无闭包约束下显式 ctx 传递的既定形态**（0063 偏差 5 钉住无闭包）。
- **硬约束由 runner 强制**：`enforce_line_fidelity`——每条编辑「1 行换 1 行 + 以 token 为界」，违反丢弃 + 诊断（`:425-438`）——lifecycle 钩子需要同款"宿主强制硬约束"设计。

---

## 4. otter lifecycle 挂载面设计（【推断】，全部锚定 §1-§3 先例）

### 4.1 阶段枚举与挂载点

从 §1 阶段清单表提取 otter 阶段表（稳定命名、spec 级文档、**只增不改**——jaix Node_Kind 的封闭枚举纪律，`plugin.jai:74-76` 注释）：

```
DISCOVER / PREPARE / VALIDATE / DEP_STRIP / PRESTEP / TRANSPILE / COMPILE / EXECUTE / CLEAN
```

挂载点 = 阶段 × 三位置：

- **`before`**：阶段开始前（观察/变换输入；如 before_COMPILE 注入额外 import 目录）。
- **`after`**：阶段结束后（观察产物/变换输出；如 after_TRANSPILE 检查视图、after_COMPILE 记录产物哈希）。
- **`at`**：替换阶段实现（seam 形参语义的插件化——§2 的 14 个 seam 就是"at 挂载点"的现成清单；生产默认 = 内置实现，第三方替换 = 注入）。

证据锚：jaix 挂点关联表（§3.1）+ Transpile_Plugin 探测/执行成对（§3.2）的合体——钩子声明 `{stage, position, hook}` 三元，探测面由声明本身承担（无需单独 has_anchor：阶段触发由编排固定）。

### 4.2 插件结构增量

`Otter_Plugin`（auto-discovery 文档 §4.2 的形状）增加：

```
hooks: [..] Lifecycle_Hook;   // { stage, position, hook } 关联表（Plugin_Grammar_Entry 形状）
```

`hook` 签名建议：`(ctx: *Lifecycle_Context, state: *void) -> bool` + 诊断三汇——`Lifecycle_Context` 携带阶段名、`Prepared_Workspace`/命令参数/输出路径等**该阶段可观测状态**（§1 表格的"可观测状态"列 = 每阶段 ctx 的内容清单）。`state` = 框架注入的跨阶段槽（§4.4）。

### 4.3 确定性排序规则

1. **阶段序 = 编排硬编码序**（§1 各命令的阶段编号顺序；b1→b8、t1→t12 等）。hook 只能挂到编排真实经过的阶段；未经过的阶段（如 marker 缺省时的 PRESTEP）其钩子静默不触发——与 jaix "挂点全部 resolve（默认无插件 = soft_fail，013 槽）"一致（`plugin.jai:57`）。
2. **阶段内钩子序 = 注册声明序**：spec 0060 决定 6 的"声明序 = 管线序"（`test.jai:155-158` 注释）与 jaix "同挂点声明序拼 choice 先者赢"（`plugin.jai:56`）双先例；before 钩子按注册序正序、after 钩子按注册序逆序（进入/退出对称——【推断】未钉，需 spec 决策）。
3. **跨包序 = 依赖闭包扫描序**（auto-discovery 文档的 (c) 机制产物）。
4. 需要显式排序逃生舱时借用 auto-discovery 文档的 sort-key 思想（linkme `pos` 先例）。

### 4.4 跨阶段状态通道（无闭包硬约束）

显式 ctx 传递：`Lifecycle_Context.plugin_state` 槽与钩子注册序对齐、由宿主（命令实现）持有存储、跨阶段续走——`Transpile_Context.plugin_state` 的直接泛化（`transpile_plugin.jai:71-75`）。已有先例佐证形状正确：`Command_Context.workspace`（`command.jai:4-12`）就是命令级的共享状态通道——**状态承载面已在生产代码里存在两处**。

### 4.5 失败语义

- 钩子返回 `false` 或产 ERROR 诊断 = **阶段失败 → 命令失败 → 退出码**（juice 现状：`build_prepared_workspace` 任一阶段 false 即整命令失败，`build.jai:217-249` 的每阶段 `if !... return false` 模式；dispatcher 的 `HANDLER_FAILED` 传播，`dispatcher.jai:114-118`）。
- `before`/`after` 观察类钩子失败 = 中止（juice 语义，无"继续"模式——test 的失败继续语义是**测试执行**层的，不是钩子层的，二者不混淆）。
- 部分状态纪律：prepare 的"全部成功才发布"（`workspace.jai:138-139`）与 clean 的"先全量校验后删除"（`clean.jai:55-58`）是两个既定的部分失败防护——lifecycle 钩子不豁免它们：钩子失败发生在发布/删除之前。

### 4.6 与命令级插件的正交组合

- **命令 = 顶层编排入口**：每个命令贡献一个 `Command` 值（`command.jai:14-21` 本身已是插件形状），经 dispatcher 的 plan/execute 序执行；命令决定**跑哪些阶段**（§1 各命令的阶段表）。
- **lifecycle 钩子 = 阶段边界的挂载面**：命令实现的内部阶段边界上，从钩子注册表合并 applicable 钩子执行。
- **组合规则**：命令级注册表与 lifecycle 钩子注册表**独立**、校验同 shape（`validate_registry` 的完整性校验 + `merge_plugins` 的冲突对照）；一个插件可以同时贡献命令值 + 钩子（同一 `Otter_Plugin` 结构的两张面）。
- test/transpile/lint 作为插件命令时，其 handler 内部就是 §1.4 式编排 + 钩子挂载面——refactor 研究风险 2 的"test 插件接口必须覆盖发现→转译→driver→编译四步"与此兼容：四步 = 命令插件的固定阶段序，钩子在四步边界挂载。

---

## 5. 约束复查

1. **bootstrap test-free**：内置 lifecycle 钩子的注册表、编排骨架、执行器必须是 bootstrap `build.jai` `#load` 集（`build.jai:25-29`）成员 = test-free 静态代码（`transpile_plugin.jai:11-15` 的既有纪律——bootstrap #load 目标、测试驻 tests/）。第三方钩子不进入该闭包（auto-discovery 文档两级结论：内置 = 静态注册，第三方 = 扫描生成 + 生成件落 `target/`）。
2. **缓存键**：钩子集（id+version+适用阶段+顺序）进管线描述分量——`transpile_view_key` 的 pipeline 分量先例（`test.jai:80` 传 `ctx.plugins` 进键；`transpile_plugin.jai:56-58` 注释 "Identity (name + version) is part of the pipeline description (it feeds the cache key's pipeline component, 0062)"）。视图/驱动是钩子输出的，必须带钩子集键；run/clean 类无缓存阶段不涉及。`at` 替换钩子的身份替换语义 = 管线描述里"阶段实现版本"（`JUICE_VERSION` 语义的泛化，`transpile_cache.jai:16-19`）。
3. **幂等与部分状态**：钩子不得绕过 workspace 相位机的幂等语义（§1.2）——before_DISCOVER 类钩子失败必须留在 EMPTY/DISCOVERED 可重试状态（现有失败路径已保证）。
4. **与 Part 4 结论的衔接（lifecycle 钩子是否走扫描发现的注册文件）**：**是——钩子不建第二套发现机制**。钩子是 `Otter_Plugin` 值里的数据（`hooks` 字段，§4.2），不是独立可发现实体；发现面唯一（`plugin-auto-discovery.md` 的候选 (c)：扫描插件包 → 找 `@otter_plugin` 标记的 `get_otter_plugin` → 生成的注册文件按扫描序显式调用）。挂载面唯一（本文 §4）：框架合并每个插件值时提取其 `hooks` 条目，按注册声明序装配阶段钩子表（§4.3）。生成文件因此有两段内容：插件/命令注册段（Part 4 设计）+ 钩子条目装配段——后者是显式序的数据声明（`OTTER_HOOK_<i> :: .{stage = …, position = …, hook = …}`），因为 Jai 无运行期顶层执行（Part 4 实验 E1/E2：顶层调用与含调用初始化器都是编译错误），"加载即入表"的唯一可行形态就是**生成代码显式执行入表**——Part 4 对命令注册的同一结论直接适用于钩子注册。缓存键随之零歧义：钩子集（阶段/位置/序）在生成文件里即确定，随插件集一起进管线描述（§5.2 上条）。

---

## 风险与未决

1. **阶段枚举的稳定性承诺**：阶段表一旦发布为插件面，重命名/增删即破坏面（jaix Node_Kind 封闭枚举纪律是既定答案，但 otter 的阶段表比 AST 节点表更可能演进——需要 spec 级版本化承诺）。
2. **after 钩子逆序未钉**：§4.3.2 的逆序对称是【推断】；或采用"after 也正序"（简单、与声明序心智一致）——spec 决策项。
3. **`at` 替换钩子的身份**：替换实现进缓存键（§5.2）意味着"换实现 = 换视图键"——正确但需文档化（替换钩子作者承担缓存失效）。
4. **观察类钩子的诊断形状**：只产诊断的钩子（lint 式）与变换类钩子的三汇形状需分开立规（`Transpile_Scan` 的 edits/tests/diagnostics 三汇泛化，`transpile_plugin.jai:43-54`）。
5. **与 test-as-plugin 的接口覆盖**：refactor 研究风险 2（收集→转译→driver→编译四步覆盖）在本设计下 = test 命令插件的固定阶段序 + 钩子挂载面——但"收集"（t1 发现）是否开放为钩子可替换点需独立决策（发现机制已被 auto-discovery 文档判为工具侧生成，替换它 = 替换发现语义，风险高于收益）。
6. **Hook_Env 强注入的取舍**：jaix 的"插件不得自造上下文"（构造期 state 恒 null）比 juice 的"调用方持有存储"更严格；otter 选哪种（强注入 vs 槽协议）需 spec 决策——推荐槽协议（juice 先例已在生产验证，且 bootstrap 闭包自足）。

---

## 引用清单

本仓库（2026-10-19 工作树）：

- `juice/src/main.jai`：CLI 解析 28-36；Command_Context 构造 38-45
- `juice/src/dispatcher.jai`：validate_registry 35-59；plan_command DFS 64-92；执行与失败语义 112-120
- `juice/src/commands/command.jai`：Command 结构 14-21；Command_Context 4-12
- `juice/src/workspace.jai`：Workspace_Phase 108-112；Workspace_State 114-118；ensure_workspace_discovered 120-136；prepare_workspace（失败不发布 138-139）144-177；ensure_workspace_prepared 194-207
- `juice/src/commands/build.jai`：build_command 17-31；revalidate_build_plans 40-60；compile_artifact_plan 62-112；build_plan_entry 166-197；build_prepared_workspace（阶段序 b3-b8）208-250
- `juice/src/commands/test.jai`：test_command 28-39；transpile_test_file 64-84；compile_test_program 86-96；test_prepared_workspace（阶段序 t0-t12）105-321；testing_module_view 349-412；generate_test_driver 496-519；collect_test_files 544-559
- `juice/src/commands/run.jai`：select_artifact_plan 30-45；run_artifact_plan 47-60；run_prepared_workspace（launch seam）62-79
- `juice/src/commands/clean.jai`：clean_command 14-23；clean_discovered_workspace（先校验后删除 55-58）35-70
- `juice/src/commands/registry.jai`：COMMAND_REGISTRY 3-8；run→build 前置钉 31
- `juice/src/jaix_front.jai`：spawn_jaix_transpile 190-194；run_jaix_prestep 204-233；resolve_jaix_exe 152-181
- `juice/src/transpile_plugin.jai`：插件结构 + 成对钩子 56-83；模式适用性 28-36；默认注册表 359-367；resolve_pipeline 374-377；探测聚合 335-353；runner 派发与 claim 458-506；行号保真门 425-438；plugin_state 通道 71-75,486-487
- `juice/src/transpile_cache.jai`：JUICE_VERSION 语义 16-19（经 `transpile-plugin-architecture.md` 引用清单复核）
- `juice/build.jai`：#load 集 25-29；bootstrap_build_entry 43-66；#run 阶段注释 68-110
- `juice/docs/research/plugin-auto-discovery.md`（姊妹篇：两级注册结论、sort-key 先例）
- `juice/docs/research/transpile-plugin-architecture.md`（结论 3 插件化表述、0063 偏差 5 无闭包、测试组织规则）
- `otter/docs/research/otter-refactor-research.md`（§2.2 seam 表、§3.4 Otter_Plugin 形状、§5 自举、风险 2）
- `jaix/src/plugin.jai`：Hook_Point 93-97；Plugin_Grammar_Entry 104-108；Jaix_Plugin 148-157；merge 语义 51-80；Hook_Env 注入契约 69-73；pass 序 = 配置序 65；Node_Kind 封闭枚举纪律 74-76
