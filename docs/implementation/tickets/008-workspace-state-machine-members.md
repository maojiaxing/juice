---
id: 008
title: workspace 状态机 + 成员校验
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [007]
blocks: [009]
---

> 父 spec：`002-spec-build-clean-structure.md`（决定 10 + US 6/7/15/16）。上游规格：`docs/spec.md` §2.1（workspace 字段）/§4.5；研究 L§1.2（相位机）、C§2/C§3（成员语义）。

# 008: workspace 状态机 + 成员校验

**What to build:** 成员声明（workspace.members 字面路径）→ 发现阶段校验（成员须在包根内、被引用成员须声明依赖、缺失/非法 manifest = 带定位错误）→ `EMPTY → DISCOVERED → PREPARED` 状态机：幂等重跑、**「全部成功才发布」**（失败留在 DISCOVERED 可重试）。三 seam（discover/resolve/prepare_dependencies）形状保留——1c 的 at 挂载点，本票只做内置实现。

**Blocked by:** 007（workspace 消费 manifest 解析出的结构体面）

**Status:** closed

- [x] 成员校验矩阵：root 内/依赖声明/缺失/非法 manifest（错误文本带定位）
- [x] 状态机：EMPTY→DISCOVERED→PREPARED、幂等、全部成功才发布、失败可重试
- [x] 三 seam 形状保留（内置实现）
- [x] workspace_tests 姊妹测试（三态机/幂等/失败不发布/成员矩阵——旧 juice test_monorepo 语义先例）
- [x] E2E fixture workspace 家族（bad-escape/bad-missing-dir/bad-no-manifest——错误逐字节）
- [x] 旧 juice build/test 于 otter 根零特判全绿（debug + release）
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话，本票不改 map.md）

## Resolution

**实现摘要**（新建文件 2 个，改写 3 个，fixture 23 个文件）：

- `src/workspace.jai`：成员路径校验面 + 发现 + 三态机全链（语义等价重写自旧 juice workspace.jai:1-207）。`workspace_relative_path_is_valid`（非空/非绝对含卷标/无 `..` 逃逸；`.` 放行让 `member_lib/.` 走到重复分支）/`workspace_member_path`/`workspace_path_already_seen`（paths_equal 比较）；`discover_workspace`（根双重检查 → 无 package.jai 空态 → 根 manifest → 只迭代根包 members 列表（成员嵌套声明静默忽略）→ 逐成员七分支校验：路径合法性/normalize 存在性/安全真实目录/path_is_within/查重/缺 package.jai/加载成员 manifest——**错误文本逐条同旧 juice**（11 条全量）；发现只加载 manifest 绝不取依赖，成员 manifest 的 DEP 声明随快照（member_packages）流入依赖准备——「被引用成员须声明依赖」面 = 成员只经声明 DEP 被链接（009 按名 link），发现快照逐包携带声明依赖）；`Workspace_Phase`/`Workspace_State`（discovery/prepared 字段经 `Juice.Workspace_Discovery`/`Juice.Prepared_Workspace` 命名空间消费）；`ensure_workspace_discovered`（非 EMPTY 幂等直返、成功打印 `Package '%' (v%) discovered.`）；`prepare_workspace`（PREPARED 幂等、非 DISCOVERED 报错、resolve → 依赖只在 `plans.count > 0 || force_dependencies` 时准备、**全部成功才发布**——失败留 DISCOVERED 可重试，get_prepared_workspace 拿不到半成品）；`get_prepared_workspace`；`ensure_workspace_prepared`（命令侧一站式幂等入口，null = 失败相位已打印具体错误）。
- `src/path_safety.jai` 扩展（007 版 2 函数 → 12 声明）：`Path_Entry_Check`/`paths_equal`（Windows 大小写不敏感）/`path_entry_visitor`/`lexical_absolute_path`/`inspect_path_entry`（visit_files 枚举 + Windows junction GetFileAttributesW 检查）/`path_is_absolute_portable`/`path_has_escape_component`/`path_is_within`/`normalize_existing_path`（近直搬自旧 juice path_safety.jai，002 决定 7；path_is_portable_* 等 target 面留 009）。
- `src/commands/command.jai`：`Command_Context` 加回 `workspace: Workspace_State` 字段（010 偏差 1 移交，单字段追加零删除）。
- `src/main.jai`：#load 闭包接入 `juice_module.jai`（**序最先**——007 链约定）→ xdg → path_safety → manifest → workspace → commands/*（workspace.jai = 007 src 模块的**首个生产消费者**，010 偏差 3 收口）；ctx.workspace 零初始化 EMPTY（旧 juice main.jai 同款）。
- `tests/test_support.jai` 追加：`child_output_contains`（CRLF 归一子串断言，错误行逐字节锁定）；workspace 三 seam 录制 fakes（`test_fake_discover`/`test_fake_resolve`/`test_fake_prepare_dependencies` + attempts/snapshot 录制全局 + `reset_preparation_test`，旧 juice test_support 语义）；`workspace_discovery_driver_code` + `run_workspace_discovery_child`（**生成 driver 子进程 E2E 面**，见偏差 5）。
- `tests/workspace_tests.jai`：20 块——路径门矩阵（9 断言纯函数）+ 三态机 11 块（发布一次/无包留 EMPTY/零计划跳依赖/声明快照流入准备（成员 DEP 声明逐字段钉住）/force_dependencies/解析失败不发布+重试成功/依赖失败不发布/未发现禁准备/ensure 三面）+ 发现矩阵 E2E 8 块（bad-root-manifest/bad-escape/bad-missing-dir/bad-no-manifest/bad-invalid-manifest/bad-duplicate/edge-self/workspace-ok，错误行与快照标记逐字节断言）。
- `tests/data/workspace-*` fixture 家族 8 个（23 文件）：bad-escape（`../outside`）/bad-missing-dir（`ghost_member`）/bad-no-manifest（plain_member 无 package.jai）/bad-root-manifest + bad-invalid-manifest（截断 manifest，求值器子进程编译失败 → 加载失败）/bad-duplicate（`member_lib` + `member_lib/.`）/edge-self（`.`）/workspace-ok（根 DEP 声明两成员 + member_extra 自声明 member_lib DEP——依赖声明面，成员两种 layout：src/module.jai + 根 module.jai，009 复用）。

**验证矩阵**：

| 步骤 | 结果 |
| --- | --- |
| `jai build.jai`（旧 juice debug） | 成功 → target/juice.exe |
| 清 target/transpile → `juice.exe build` + `test` 于 otter 根（debug） | exit 0，**82 passed, 0 failed**（含 driver E2E 8 块） |
| `jai build.jai - release`（旧 juice release） | 成功 |
| 清 target/transpile → `juice.exe build` + `test`（release） | exit 0，**82 passed, 0 failed** |
| exe 冒烟：help/未知命令/version | help exit 0、未知命令 exit 1、version 占位 exit 1（010 契约无回归） |

82 = 010 收口的 62 + workspace_tests 20。旧 juice 对无 modules/ 包根的 import dir 探测提示为通用无害行为（map Notes 已记）。

**偏差清单**：

1. **discover_workspace 追加 `modules_dir: string = ""` 尾参**（007 seam 注入惯例——生产形状不可直测的面加默认参数）：bootstrap 期生产推导（`<exe>/modules`，§9.3）不可命中，E2E/测试注入旧 juice modules 目录；生产两参调用形状照旧（默认推导）。连带：discover seam 类型 = `#type (root_dir, cache_dir, modules_dir) -> (Workspace_Discovery, bool)`（旧 juice 两参 + 注入参），内部调用显式传 `""`；测试 fakes 三参（忽略第三参）。
2. **resolve/prepare_dependencies 两 seam 本票无生产默认值**（必填参数）：旧 juice 默认 `resolve_artifact_plans`/`resolve_and_fetch_dependencies`——两函数归 009（target.jai/dependency.jai），本票不存在；缺省接线若落假实现 = 生产假行为（比编译期报错更糟）。009 补 `= 函数` 默认值（跨文件前置引用 = 旧 juice workspace.jai:148 同款先例，Jai 容忍）。seam 名字/类型逐字段保留旧 juice 形状。
3. **`Target_Resolution_Error` + `Artifact_Plan_Result` 前置声明于 workspace.jai**（行内注释标注）：resolve seam 的返回类型归 target 层（旧 juice target.jai:8-39），009 的 target.jai 落位时把两声明**移走**（009 需删除 workspace.jai 中的前置声明再落 target.jai——前置声明是为了 008 内 seam 形状完整，唯一消费方 = workspace.jai 自身）。
4. **main.jai 闭包不含 src/module.jai**：workspace.jai 的依赖面 = juice_module（命名空间绑定）/path_safety/manifest——module.jai（otter 自己的 Package 面）无生产消费方，进闭包徒增死声明（010 最小闭包纪律）；其面经测试扫描与阶段 2 发布路径进入。
5. **成员矩阵 E2E 走生成 driver 子进程而非 otter exe**：build 命令（发现的生产消费方）归 011，008 期 `otter build` 只能打到占位 handler——矩阵经生成 driver（真 jai 子进程 #load src/workspace.jai 闭包 + 注入 bootstrap modules + 真求值器子进程链，007 求值器 child 形状 + 010 支撑助手）跑真 fixture 目录、捕获输出逐字节断言错误行；011 接线后 exe 路径自然接管（014 收口面）。
6. **「被引用成员须声明依赖」的解释面**：旧 juice 发现期**无**该错误分支（error 文本逐条同旧 juice 因此不可新增）——该面 = 成员只经声明 DEP 记录被引用/链接（009 的 fetch_workspace_dependencies 按名 link；workspace-ok 与三态机快照测试钉住声明依赖随发现快照传递）。测试侧以 workspace-ok fixture（根 DEP 声明成员 + member_extra 自声明成员间 DEP）+ 快照逐字段断言落地。

**测试组织**：src 实现模块全部 test-free（bootstrap #load 集纪律）；测试驻 tests/（workspace_tests 姊妹文件 + test_support 共享声明）。Jai 事实备忘：`#type` seam 参数无默认值写法（3 参显式传参）；测试程序跨文件前置字段类型引用 = 旧 juice command.jai→workspace.jai 同款先例（容忍）；driver 生成文本经 append 写入（% 无格式语义）。
