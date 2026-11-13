---
id: 069
title: S1 lifecycle 精简：typed stage seam 与 TRANSPILE 降为 COMPILE 的 before hook
labels: [wayfinder:grilling]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [070, 071, 068]
---

# 069: S1 lifecycle 精简：typed stage seam 与 TRANSPILE 降为 COMPILE 的 before hook

## Question

S1 的 interface 与边界怎么定？

**已拍板方向（用户 2026-10-22）**：9×3 通用挂载矩阵收成 typed stage seam；**TRANSPILE 降为 COMPILE 的 before hook**（TRANSPILE 不再是独立 stage；active stage seam = PRESTEP + COMPILE）；`at` 是 body，不是第三个 position；context bag 与 `Stage_State` tag 由 typed state 取代。

要定：

- **Active seam 集合**：PRESTEP + COMPILE 两个 seam 是否足够？DISCOVER/PREPARE/VALIDATE/DEP_STRIP/EXECUTE/CLEAN 保持 plain function，还是保留为 vocabulary？9 值 `Lifecycle_Stage` 缩减到 2–3 个 active 值，还是只作报告标签？
- **COMPILE seam 的形态**：before hooks（内置 transpile front + 旧 TRANSPILE before hooks + 旧 COMPILE before hooks）→ body（旧 COMPILE built-in）→ after hooks。内置 transpile front 在 before 列表中的固定位置（首个 / 末个）？旧 TRANSPILE after hooks 映射到 transpile front 之后，还是 COMPILE body 之后？
- **State 合并**：`Transpile_Stage_State` 与 `Compile_Stage_State` 合并成一个 `Compile_Stage_State`（含 `transpile` 子记录），还是保留两个记录由 COMPILE seam 串联？view keys / pipeline description 如何随 state 进入 body？
- **AT 的处置**：AT 作为 body 后，旧 TRANSPILE AT 是“替换 transpile front 的 before action”，还是消失（只允许替换 COMPILE body）？旧 COMPILE AT 直接成为 body override。
- **Hook 表**：per-stage typed hook 列表如何取代 `Hook_Registration` / `Lifecycle_Context` / `plugin_state` / `kind` 检查；registration 的 state 如何跟随 typed hook（与 066 的 registration state 对齐）。
- **失败语义**：before / body / after 的 fail-fast 是否保持；after 是否仍被失败抑制（C4 的失败感知 after 不在本票，除非用户重开）。
- **测试面**：`tests/lifecycle_tests.jai` 的 19 个机制测试中哪些保留 / 迁移 / 删除；build/test 的 stage 顺序测试如何改写；generated host / test_support 的 dispatch 文本如何跟随。
- **发布面**：`lifecycle.jai` 是发布插件面闭包之一；矩阵缩小会改公开面。是否接受？是否需要版本化说明？
- **Spec 冲突**：本票重开 spec §6.1（closed enum / add-only）与 §6.3（14 seam → at）。需要明确哪些文本改写、哪些只作 vocabulary 保留。

相关锚点：`src/lifecycle.jai:47-169,278-364`；`src/commands/build.jai:109-159,484-514`；`src/commands/test.jai:363-496,612-651`；`src/plugin_host.jai:310-318`；`tests/lifecycle_tests.jai`；tickets 064/065/067；复评报告 `architecture-review-20261022-114721.html`。

## Answer

**结论（2026-10-27，grilling 收口）**

### 1. Active seam 集合

- Active seam = **PRESTEP + COMPILE**。DISCOVER / PREPARE / VALIDATE / DEP_STRIP / EXECUTE / CLEAN 保持 plain function，不经 seam。
- `Lifecycle_Stage` 的 9 个值保留为 **vocabulary / 报告标签**，不驱动 dispatch；`stage_name` 保留。spec §6.1 的枚举文本保留并标注 vocabulary only。
- 不新增 lifecycle stage。

### 2. COMPILE seam 形态

```
PRESTEP:  before hooks → body(null) → after hooks
COMPILE:  内置 transpile front → before hooks → body（内置 loop/t12 或 override）→ after hooks
```

- 内置 front 是 COMPILE 的**首个 before 步骤**（固定、不可替换）。
- 旧 TRANSPILE after 与旧 COMPILE before 都成为 COMPILE before hooks（能读到 front 产出的 entries）。
- 旧 TRANSPILE before 失去 front 之前的位置（生产无 hook，只有测试消费）。
- 旧 TRANSPILE AT 消失；只有 COMPILE body 可替换（旧 COMPILE AT）。
- 每个 seam 的 hook 顺序 = 声明序；before/after 都正序。

### 3. State

每个命令一个扁平 COMPILE state：

```jai
Build_Compile_Stage_State :: struct {
    prepared: *Juice.Prepared_Workspace;
    pipeline: [] Transpile_Plugin;
    prestep:  *Prestep_Stage_State;
    entries:  [..] string;
}

Test_Compile_Stage_State :: struct {
    prepared:            *Juice.Prepared_Workspace;
    files:               [] Scan_File;
    pipeline:            [] Transpile_Plugin;
    prestep:             *Prestep_Stage_State;
    outputs:             [..] Test_File_Output;
    view_paths:          [..] string;
    transpile_dir:       string;
    testing_module_dir:  string;
    testing_module_view: string;
    pattern:             string;
    registration_path:   string;
}
```

`Prestep_Stage_State` 独立保留；无 `Stage_State` 基记录、无 Type tag、无嵌套 `transpile` 子记录。front、hooks、body 读写同一 state；`pipeline` 描述随 state 进入 front，view key 计算不变。

### 4. AT / body

- 两个 seam 共用 `before → body → after`；body 可空（null = no-op）。
- COMPILE body = 内置（`build_compile_loop` / `test_compile_front`）或 override（caller 传入的 body，替代旧 COMPILE AT）。
- PRESTEP body 恒 null。
- 旧 TRANSPILE AT 不保留；front 固定。
- AT 是 in-process 测试 seam，不是成员插件承诺（与 066 一致）。

### 5. Typed hook / registration / diagnostics

```jai
Seam_Hook :: struct($State: Type) {
    run: #type (state: *State, diagnostics: *[..] Lifecycle_Diagnostic, plugin_state: *void) -> bool;
}

Seam_Registration :: struct($State: Type) {
    hooks: [..] Seam_Hook(State);
    state: *void;   // plugin options；caller/test hook 为 null
}

run_seam :: ($State: Type, state: *State,
             before: [] Seam_Registration(State),
             body: #type (state: *State, diagnostics: *[..] Lifecycle_Diagnostic) -> bool,
             after: [] Seam_Registration(State),
             diagnostics: *[..] Lifecycle_Diagnostic) -> bool
```

- 每个 seam 的注册表按声明序执行；空 registration 跳过；每步后 `has_new_error` 检查新增 ERROR。
- 删除 `Lifecycle_Context` / `Hook_Position` / `Lifecycle_Hook` / `Hook_Registration` / `run_mounted_hooks` / `has_mounted_hook`；保留 `has_new_error`。
- 命名用 `Seam_*`（发布面本来就要破坏）。
- PRESTEP 表由 resolver 产出（成员插件 `state = plugin.options`；内置无 hook）；COMPILE 表由 caller（测试）传入。
- diagnostics 显式传入 hook 与 body，不再有 context bag；`plugin_state` 第三参数保留（Jai 无闭包）。

### 6. Session 落点与 API

**落点 = `src/plugin_host.jai`**（内部模块，load 在全部依赖之后；已拥有 prepare + host）。这取代 064 的“并入 lifecycle.jai”：`lifecycle.jai` 在 `JUICE_CORE_LOAD_FILES` 发布闭包里且只依赖 Basic，session 持有 `Prepared_Workspace` / `Resolved_Plugins` 会破坏发布闭包。

```jai
Command_Session :: struct {
    prepared:    *Juice.Prepared_Workspace;
    prepare:     Plugin_Prepare_Result;
    resolved:    Resolved_Plugins;          // pipeline + typed prestep registrations
    prestep:     Prestep_Stage_State;
    diagnostics: [..] Lifecycle_Diagnostic;
}

begin_session :: (prepared: *Juice.Prepared_Workspace,
                  host_spawn: #type (host_path: string, import_dirs: [] string) -> Process_Result = spawn_plugin_host)
               -> (Command_Session, bool)

run_prestep_seam :: (session: *Command_Session,
                     before: [] Seam_Registration(Prestep_Stage_State) = .[],
                     after:  [] Seam_Registration(Prestep_Stage_State) = .[]) -> bool

run_compile_seam :: ($State: Type,
                     session: *Command_Session,
                     state: *State,
                     front: #type (state: *State) -> bool,
                     body:  #type (state: *State, diagnostics: *[..] Lifecycle_Diagnostic) -> bool,
                     before: [] Seam_Registration(State) = .[],
                     after:  [] Seam_Registration(State) = .[]) -> bool
```

- `begin_session`：prepare + report + resolve + 填 `Prestep_Stage_State` root/member dirs + host effects；不派发 seam；失败打印并返回 false。
- `run_prestep_seam`：resolved prestep registrations 在前，caller before/after 在后；body null。
- `run_compile_seam`：先跑 `front`（失败即返回），再 `run_seam`（before → body → after）。
- 命令 wrapper 保留非 lifecycle seam（`is_running` / `handoff` / `collect` / `spawn` / `host_spawn`），untyped `hook_table` 换成每命令 typed hooks 结构 + 可空 body override：

```jai
Build_Command_Hooks :: struct {
    prestep_before: [..] Seam_Registration(Prestep_Stage_State);
    prestep_after:  [..] Seam_Registration(Prestep_Stage_State);
    compile_before: [..] Seam_Registration(Build_Compile_Stage_State);
    compile_after:  [..] Seam_Registration(Build_Compile_Stage_State);
}
// Test_Command_Hooks 同形，用 Test_Compile_Stage_State。
```

- 顺序按 064：prelude → begin → zero-work 短路 → PRESTEP → COMPILE；零工作仍 spawn host（有意行为变化）。
- `stage_name` / 9 值枚举不进入 session API（vocabulary only）。

### 7. 失败语义

保持 fail-fast：hook 返回 false 或新增 ERROR 诊断 = seam 失败；before/body 失败抑制后续 body/after；after 不做失败感知；C4 仍出范围。

### 8. 测试迁移

- `tests/lifecycle_tests.jai`（19 块）：保留 enum 顺序、注册序、失败、诊断计数、registration state、merge、PRESTEP 表规则（约 5 保留 + 8 改写）；删除矩阵专属（only-requested-mount、never-dispatched、ctx.stage、has_mounted_hook、prestep-without-slot 等约 6）。
- `tests/build_transpile_tests.jai` / `tests/test_transpile_tests.jai`：顺序 trace 改为 `t-before* → t-after* → c-before* → body(c-at) → c-after*`；旧 `t-at` 取消，改测 body override；fake front 测试改为真实 front + body fake。
- `tests/test_support.jai`：`Build_Compile_Stage` cast 与 scan driver 的 `Lifecycle_Context` 改 typed state / `run_seam`。
- `tests/plugin_host_tests.jai`：generated host 的 dispatch pin 改为 typed prestep 调用；registration pin 在 S2/S3 前保持。
- `tests/test_runner_tests.jai`：byte pin 不变（067）。
- 验收 = 三路径全绿 + pre/post 计数（found / passed / 白名单 / 成员）记录；不设固定数字。

### 9. 发布面与 spec 改写

- 发布面破坏性收缩接受：删 `Lifecycle_Hook` / `Hook_Position` / `Lifecycle_Context` / `run_mounted_hooks` / `Hook_Registration` / `has_mounted_hook`；保留 `Prestep_Stage_State` / `prestep_add_*` / `Lifecycle_Diagnostic` / `run_seam` / `Seam_*`；无兼容 shim；版本仍 0.0.1；在 spec/ADR 记录。
- spec §6.1：枚举保留为 vocabulary，表格只把 PRESTEP/COMPILE 标为 seam，其余标 plain function；加 S1 修订 callout。
- §6.2：改写为 `before → body → after` + typed hook/registration + 显式 diagnostics；删除 stage×position。
- §6.3：改写为 COMPILE before phase（front 首位 + hooks）→ body → after；旧 14 seam 映射保留为 superseded note。
- §6.4：顺序 = 声明序；front 固定首位；before/after 正序。
- §6.5：删除 `plugin_state` 槽协议；registration state typed；diagnostics 显式；失败语义不变。
- §7.4：at 覆盖表改为 COMPILE body；at_TRANSPILE 消失；其余行标 plain seam（非 lifecycle mount）。
- §5.1 `hooks` → `prestep_hooks` 属 070；069 只加交叉引用。

### 10. 迁移顺序（交 068）

1. `src/lifecycle.jai`：`Seam_Hook` / `Seam_Registration` / `run_seam`；typed prestep helpers；删矩阵类型。
2. `src/plugin.jai` / `src/transpile_config.jai`：resolver 产出 typed prestep registrations；删 `slot_options`；`Juice_Plugin.hooks` 保持到 070 的 `prestep_hooks` 落地。
3. `src/commands/build.jai` / `src/commands/test.jai`：合并 state；wrapper 构造 session 并调用 seam。
4. `src/plugin_host.jai`：`Command_Session` + begin + seam 入口；generated host 用 typed prestep 调用。
5. 测试按 §8 迁移；三路径；记录计数。
6. 068：收口 spec / CONTEXT / ADR 措辞。
