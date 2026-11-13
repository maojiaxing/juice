---
id: 010
title: registry + dispatcher + main 接线 + help
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [007]
blocks: [011, 012]
---

> 父 spec：`002-spec-build-clean-structure.md`（决定 1/5/11 + US 22-28）。上游规格：`docs/spec.md` §4.1/§4.2/§4.3；研究 R§2.1（command.jai:14-21、registry.jai:31、dispatcher.jai:35-121）。

# 010: registry + dispatcher + main 接线 + help

**What to build:** 六命令静态注册表（BUILD/RUN/CLEAN/TEST/VERSION/HELP——**静态是刻意选择**：linkme 式自动发现已判死（A§1/§2.1），内置件自动发现零收益且违反 bootstrap 闭包纪律（A§4.1），勿改为自动发现）→ `validate_registry`（无效声明/重名/未知前置拒绝）→ `plan_command` DFS（环检测、菱形去重、前置恒收空参数）→ main 接线（argv 剥壳：command + arguments → dispatch → exit 码透传）。**help 全实现**（registry 元数据渲染：`juice help` 总览 + `juice help <cmd>` 用法）；未知命令 = 清晰错误 + exit 1；其余命令占位 not-implemented（真 handler 归 011-013）。

**Blocked by:** 007（命令结构体面 + main 接线需要实现模块组织）

**Status:** closed

- [x] 六命令静态注册表 + validate_registry 三拒绝面
- [x] plan_command DFS：环检测/菱形去重/前置恒收空参数
- [x] main 接线：argv 剥壳 → dispatch → exit 码
- [x] help 输出契约（总览 + 单命令用法——registry 元数据渲染）
- [x] 未知命令错误 + exit 1；占位 handler = not-implemented
- [x] dispatcher_tests + help/argv 姊妹测试
- [x] E2E：otter exe `help`/未知命令（测试程序内 spawn 自 exe）
- [x] 旧 juice build/test 于 otter 根零特判全绿（debug + release）
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话，本票不改 map.md）

## Resolution

**实现摘要**（新建文件 11 个，改写 1 个——src/main.jai 占位 → 真接线；test_support.jai 追加 E2E/dispatcher 支撑）：

- `src/xdg.jai`：get_env/get_user_home_directory/get_cache_home（通用底层近直搬，002 决定 7）——main 的 cache_dir 推导源。
- `src/commands/command.jai`：Command_Handler/Command_Argument_Validator 类型面；`Command_Context {root_dir, cache_dir}`（workspace 字段归 008，见偏差 1）；`Command {name, description, usage, prerequisites, handler, validate_arguments}`（旧 juice command.jai:14-21 形状）；command_accepts_no_arguments/command_arguments_are_valid + `command_not_implemented`（五占位 handler 共享体）。
- `src/commands/{build,run,clean,test,version}.jai`：五命令声明（name/description/usage/prerequisites/validator 为注册表契约全量落地：run→build 唯一前置链、run/test validator ≤1 参）+ 占位 handler（参数守卫 → not-implemented 错误 + false → exit 1）。
- `src/commands/registry.jai`：`COMMAND_REGISTRY` 六命令静态数组（声明序 BUILD/RUN/CLEAN/TEST/VERSION/HELP）；头注释钉死「静态 = 刻意，勿改自动发现」。
- `src/commands/help.jai`：help 全实现——零参 = print_usage 总览；单参 = find_command → 该命令 usage 行；未知命令 = `[juice ERROR] Unknown command: '%'` + false；零前置零副作用。
- `src/dispatcher.jai`：Dispatch_Error/Result/State 三态枚举 + find_command + validate_registry 三拒绝面（空名/null handler/null validator → INVALID_COMMAND；重名 → DUPLICATE_COMMAND_NAME；未知前置 → MISSING_PREREQUISITE）+ plan_command DFS（VISITING=环 CYCLE_DETECTED、COMPLETED=菱形去重、计划期查参、前置恒收空参数、后序追加）+ dispatch_command（validate → find → plan → 按序执行；仅目标命令拿用户参数；前置失败 PREREQUISITE_FAILED/目标失败 HANDLER_FAILED 立即中止）+ print_usage（registry 序总览）。错误文本逐条同旧 juice。
- `src/main.jai`：argv 剥壳（args[1] 命令名缺省 "build"、args[2..] 参数）→ ctx（root_dir = cwd、cache_dir = `<XDG 缓存家>/juice`）→ dispatch_command → 失败 exit(1)（旧 juice main.jai:28-47 形状）。
- `tests/test_support.jai` 追加：otter_exe/run_otter_child（spawn 自 exe，cwd = otter_root）、expect_exit/normalize_crlf/output_matches/child_output_equals（CRLF 归一全文比对）、dispatcher 录制系（test_handler_a..d/fail + test_X_arguments 参数录制 + reset_dispatch_counters + TEST_REGISTRY_{SIMPLE,DUPLICATE,MISSING_PREREQ,INVALID_NAME,INVALID_HANDLER,CYCLE,DIAMOND,FAILURE,ARGUMENTS}）。
- `tests/dispatcher_tests.jai`：13 块——生产注册表校验 + 声明形状契约（六命令逐字段 + run→build 唯一前置）+ 三拒绝面 + 未知命令 + 环零执行 + 菱形各一次 + 参数非法先于前置 + 前置失败传播 + handler 失败报告 + **仅目标命令拿用户参数**（a/b/c 零参数、d 收 ["one","two"]）。
- `tests/help_tests.jai`：5 块——零参总览/已知命令/未知命令拒绝/多余参数拒绝/声明形状（零前置、validator 绑定）。
- `tests/e2e_cli_tests.jai`：7 块——`help` 总览**逐字节契约**（`EXPECTED_HELP_OVERVIEW` 全文比对）、`help <cmd>` usage 行、`help` 未知命令 exit 1、`help` 多余参数 exit 1、未知命令 exit 1 + 总览、占位命令 not-implemented + exit 1（build/version/build 参数守卫）、无命令缺省 build。真子进程 spawn otter exe（run_juice_child 先例形状，otter_root/otter_exe 支撑）。

**验证矩阵**：

| 步骤 | 结果 |
| --- | --- |
| `jai build.jai`（旧 juice debug） | 成功 → target/juice.exe |
| 清 target/transpile → `juice.exe build` + `test` 于 otter 根（debug） | exit 0，**62 passed, 0 failed**（含 E2E 自 exe spawn 7 块） |
| `jai build.jai - release`（旧 juice release） | 成功 |
| 清 target/transpile → `juice.exe build` + `test`（release） | exit 0，**62 passed, 0 failed** |
| exe 冒烟：`help`/`help run`/`help nope`/`frobnicate`/`version`/`build`/`clean`/`test`/`run`/无参 | help exit 0 总览/usage；未知命令 exit 1；占位 exit 1 not-implemented；run = build 前置失败 PREREQUISITE_FAILED exit 1；无参缺省 build |

62 = stage0 1 + module_tests 6 + manifest_tests 30 + dispatcher_tests 13 + help_tests 5 + e2e_cli_tests 7。旧 juice 对无 modules/ 包根的 import dir 探测提示为通用无害行为（map Notes 已记）。

**偏差清单**：

1. **Command_Context 暂缺 workspace 字段**：spec §4.1.4 形状含 `workspace: Workspace_State`，但该类型归 008（src/workspace.jai 尚不存在，010 与 008 无阻塞边）。010 落 `{root_dir, cache_dir}` + 行内注释，**008 加回 `workspace: Workspace_State` 字段**（单字段追加，无删除面）。
2. **print_usage 名称列显式填充（旧 juice 输出面偏差，实质 = 实现其本意）**：Jai print 格式语言无最小宽度旗标（查实模块 Basic/Print.jai 仅支持 `%`/`%N`/`%%`）——旧 juice 的 `"  %-12  %"` 会把字面 `-12` 漏进输出（其 unknown-command 路径从未被测试锁定，潜在 bug 未爆）。otter 以显式空格循环实现 12 列左对齐布局；输出文本由 E2E `EXPECTED_HELP_OVERVIEW` 逐字节锁定。
3. **007 的 src 模块不进 main.jai #load 闭包**：010 接线不消费 juice_module/manifest/path_safety/module（占位 handler 与 help 零消费面），最小闭包 = xdg → commands/* → dispatcher；007 模块随 011-013 第一个生产消费者进入（juice_module.jai 序最先，007 链约定）。
4. **TEST_REGISTRY_DIAMOND 的 d 命令加 accept-all validator**（旧 juice 测试支持无此）：「仅目标命令拿用户参数」需要目标命令接受参数——旧 juice 该语义无直测（dispatcher.jai:113 代码有、测试无）；otter 测试支持补 `test_arguments_accept_all` + 参数录制全局（test_X_arguments），钉住前置恒空参数。
5. **main.jai #load 序与旧 juice 有别**：version 插 test 之后、help 在 dispatcher 之后（旧 juice 无 version/help）；测试程序全包扫描序为词法序（help.jai 早于 registry/dispatcher），跨文件前置引用 = Jai 声明可见性容忍面（旧 juice 同状先例：registry.jai 词法先于 run/test.jai、dispatcher.jai 词法先于 manifest.jai）。

**Jai 事实备忘**：动态数组 out-param 惯例 = `param: *[..] T` + 调用点 `*global`，体内把指针**直接**传 array_reset/array_add（不 deref）——`[..] T` 值形参绑定数组头副本，callee 突变不影响 caller 全局（本票测试支持调试实录：d 参数录制零捕获）；`*recorded` 在 `*[..] string` 上会成 `**` 类型错。
