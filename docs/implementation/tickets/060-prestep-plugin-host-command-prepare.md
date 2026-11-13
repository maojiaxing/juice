---
id: 060
title: PRESTEP-only plugin host + 命令级 prepare
labels: [implementation]
status: closed
assignee: maojiaxing
blocked-by: [059]
blocks: [061]
---

# 060: PRESTEP-only plugin host + 命令级 prepare

> 上游规格：`docs/spec.md` §5.2「PRESTEP-only plugin host」/§11.13（2026-10-21 设计修订）。Phase 2 的第一票：让 build/test 从成员插件包加载 PRESTEP hooks；jaix 仍在静态内置（061 搬走）。

**What to build:** 命令级 plugin prepare（扫描声明的成员插件、写注册文件、写成员 import shim）与 PRESTEP-only host：生成 host driver、嵌入输入、spawn jai、执行 hooks、用记录文件返回源替换/剔除/诊断。test metaprogram 复用同一份注册文件。

## 交付

1. 命令级 prepare（共享模块，build/test 都调用）
   - 输入：`Prepared_Workspace` + `Package.plugins`；输出：注册文件路径、已声明的成员插件 hit、`ok`。
   - 扫描按声明序；写 `target/plugins/registration.jai`；为声明成员写 import shim；零声明成员插件 = 无注册文件、无 host。
   - build/test 在 PRESTEP 之前调用；test 的 `test_compile_front` 不再自行扫描/写注册（复用 prepare 结果）。
2. host driver 生成与协议
   - 生成 `target/plugins/host.jai`：`#import "juice_core"` + `#load "<registration>"`；root / mode / member dirs / `Plugin_Config` 以字面量嵌入；`#run` 内 `main()`。
   - `main()`：`get_scanned_plugins()` → `merge_plugins` → `resolve_plugin_configs`（应用 options）→ 构造 `Lifecycle_Context` + `Prestep_Stage` → `run_mounted_hooks(.PRESTEP, .before)` → 写输出记录文件。
   - 输出记录：`SUBSTITUTE=<rel>|<abs>`、`DROP=<rel>`、`DIAG=<LEVEL>|<message>`、`OK=0|1`；`%XX` 编码；父进程严格解析（共享编码助手）。
   - spawn：`jai -quiet -import_dir <modules> -import_dir <target/packages> host.jai`；非零退出/输出缺失 = 命令失败；stderr 透传。
   - 零声明 hooks 插件 = 不 spawn；注册文件仍可供 test metaprogram 使用。
3. build/test 接线
   - build：prepare →（有 hooks）host → 把 host 返回的替换/剔除并入 `Prestep_Stage` → PRESTEP 的 `before` 阶段效果由 host 结果承载；静态内置 jaix 仍在进程内合并（061 移除）。
   - test：prepare → 注册文件同时喂给 host 与测试 metaprogram；host 结果同样并入 prestep。
   - 错误路径：merge 诊断、未知 id、options 错误、host 崩溃、输出解析失败全部在编译前失败。
4. 测试
   - fixture 插件包（PRESTEP hook + options）通过 host 跑通；零插件包不 spawn；合并/选项/协议负例。
   - test metaprogram 注册复用：只扫描一次、驱动路径一致。
   - 计数基线随票记录。

## 验收

- 真实 `juice.exe` build/test 在有成员 PRESTEP 插件时全绿；无插件时与 059 逐字节/行为一致。
- host 协议单测：编码往返、严格解析、缺失 `OK`、损坏记录、非零退出。
- 命令级 prepare 是唯一扫描/注册落点；test metaprogram 不再二次扫描。
- `jai build.jai` debug exit 0；根 test 全绿。

## Out of scope

- jaix 搬入成员包（061）。
- 其他 stage 的通用 host。
- 安装布局 E2E（061）。

## Resolution

**2026-10-21，实现完成。**

实现摘要（按交付项）：

1. 命令级 prepare（`src/plugin_host.jai` 的 `prepare_workspace_plugins`；共享模块，build/test 都调用）
   - 输入 `Prepared_Workspace`：跑声明驱动的 `scan_workspace_plugins`（声明序、成员 import shim、id/版本形状校验），`hits` 非零时写 `<root>/target/plugins/registration.jai`；零声明成员插件不写注册文件（并清理前次会话遗留的注册文件）。输出 `Plugin_Prepare_Result {registration_path, hits, member_hooks, ok, diagnostics}`。
   - build 在 `build_prepared_workspace` 的零 plan 短路之前调用（056 偏差保持：零 plan 包仍做插件准备）；test 在零文件短路之后、PRESTEP 之前调用。
   - test 的 `test_compile_front` 删除全部扫描/写注册代码，只消费 `Test_Compile_Stage.registration_path`（prepare 结果）——命令级 prepare 是唯一扫描/注册落点。
2. Host driver 生成与协议
   - `generate_plugin_host` 生成 `<root>/target/plugins/host.jai`：`#import "juice_core"` + `#load "<registration>"`；`HOST_ROOT` / `HOST_MODE` / `HOST_MEMBER_DIRS` / `plugin_configs`（成员声明转 `Plugin_Config`）以字面量嵌入；`#run { main(); }`。
   - `main()`：`get_scanned_plugins()` → `merge_plugins`（失败 = 全 ERROR DIAG + OK=0）→ `resolve_plugin_configs`（options apply/validate、版本；失败同）→ 构造 `Lifecycle_Context` + `Prestep_Stage`（槽对齐 `slot_options`）→ `run_mounted_hooks(.PRESTEP, .before)` → 记录文件。
   - 记录文件 `<root>/target/plugins/host-records.txt`：`SUBSTITUTE=<rel>|<abs>` / `DROP=<rel>` / `DIAG=<LEVEL>|<message>` / `OK=0|1`，逐字段 `%XX` 编码（host 侧生成的编码器与父进程 `unescape_record_value` 互逆；值里的 `|`/`%`/CR/LF 由 round-trip 测试钉住）。
   - `run_plugin_host`：生成 driver → 删除陈旧记录文件（崩溃不得被旧成功掩盖）→ `jai -quiet -import_dir <modules> -import_dir <target/packages> host.jai`（stderr 继承透传）→ 读记录 → `parse_plugin_host_records` 严格解析（未知键、字段缺失、坏 `%XX`、空必填字段、重复/OK 之后记录、内部空行、缺 `OK` 全部报错）。非零退出 / 无记录文件 / 解析失败 = 命令失败。
   - `apply_plugin_host_effects`：DIAG 映射到 `[juice ERROR]/[juice WARNING]/[juice]` 并写入 lifecycle 汇；OK=0 或 ERROR 诊断 = 失败；替换/剔除行经 `prestep_add_*` 阶段级规则并入命令的 `Prestep_Stage`（冲突 = 阶段失败）。
   - 触发条件：`member_hooks` = 声明的成员插件包扫描源里出现 `hooks` IDENT（`Plugin_Scan_Result.has_hooks`，保守过近似：假阳性只多 spawn 一个报告零 hook 的 host；静态内建插件不需要 host）。零声明 hooks 插件 = 不 spawn。
3. build/test 接线
   - build：prepare →（member_hooks 时）host → host 替换/剔除并入 `Prestep_Stage` → 进程内静态内置 hook 照旧派发（061 移除）→ TRANSPILE/COMPILE。
   - test：prepare → 同一注册文件喂 host 与生成的测试 metaprogram（成员 configs 仍由 `plugin_configs_from_declarations` 同源嵌入）→ host 结果同样并入 prestep。
   - 错误路径全部在编译前失败：merge 诊断、未知 id（prepare 扫描）、options/版本（host 解析）、host 崩溃、记录解析失败。
4. 测试（`tests/plugin_host_tests.jai`，18 个测试 + 1 个 fixture 包）
   - unit：prepare 声明序/零插件/hooks-face 触发；编码 round-trip；严格解析 13 种损坏形状；非零退出/缺失记录/陈旧记录掩盖；阶段效果合并与冲突；生成的 host 文本形状。
   - 接线：compile front 只消费 prepare 注册（用“成员目录不存在”证明不二次扫描）；零插件不 spawn host；成员 hooks host 效果进入 test 视图；host 失败在编译前中止。
   - E2E（真 `juice.exe` + 真 `jai`）：`tests/data/plugin-prestep-fixture`（成员 `prestep-plugin`：PRESTEP hook + `entry`/`replacement`/`drop`/`message` options）build 编译替换入口、artifact 打印替换内容、记录文件 `SUBSTITUTE`/`DROP`/`OK=1`；test 丢弃失败文件、保留测试 1 passed；options 拒绝、merge 冲突、host 编译崩溃三条负例；零插件包无 host/注册目录。

验收证据：

- 真实 `juice.exe` 有成员 PRESTEP 插件 build/test 全绿：`E2E: the member PRESTEP plugin runs through the host and substitutes the build entry` / `E2E: the member PRESTEP plugin's host effects drive the test program`（fixture build exit 0 + artifact 输出 `prestep replacement entry`；test exit 0 + `1 passed, 0 failed`）。
- 无插件与 059 行为一致：新增测试前根套件 found 复跑 = 538（533 + 5，未变）；`E2E: a package without plugins never spawns the host`（无 `target/plugins/`）；`Test command: zero member plugins never spawn the host`（生成的 metaprogram 无 `juice_core`/`merged_plugins`/`set_working_directory`）。
- host 协议单测：`Plugin host protocol: encoded records round-trip through the shared pair`、`Plugin host protocol: strict parsing rejects malformed record files`、`Plugin host run: a nonzero exit, a missing record file and a stale record fail`。
- 唯一扫描/注册落点：`Test command: the prepare registration drives the metaprogram without a second scan`；`grep` 核 `src/` 中 `scan_workspace_plugins` / `workspace_plugin_registration_path` / `generate_plugin_registration` 只出现在 `plugin_host.jai`（与 `plugin_scan.jai` 定义处）。
- `jai build.jai` debug exit 0；`jai build.jai - release` exit 0；根 test 全绿（见验证数字）。

验证数字：`rm -rf target/transpile && ./target/juice.exe test` exit 0；末行 `329 passed, 0 failed`（Testing 自测 `finish` 重置，非条目数）；直跑 SKIP 2（自托管 posture）；release 产物副本于根 test exit 0、**SKIP 0**。权威 found = 最大 `juice_test_N` **551** + 手写 `note_suite_*` @test **5** = **556**（059 基线 538；本票 +18 测试）。

Deviations：

1. host 触发用扫描期的保守词法探测（`hooks` IDENT），而非“加载值后判断”：父进程无法在不 spawn 的前提下得知成员插件的 face。过近似只导致多 spawn 一个零 hook 的 host（记录 `OK=1`、零效果），不影响正确性；`Plugin_Scan_Result.has_hooks` 的单源注释说明了该契约。
2. host（成员 hooks）先于进程内静态内置 hook 派发：跨进程边界无法与声明序交错。Phase 1 仅静态 pre-step 插件在进程内（061 移入成员包后两者同由 host 按声明序执行）；两路写同一替换/剔除键仍由 `prestep_add_*` 阶段规则判冲突失败。
3. host 只跑 PRESTEP `before`（票面 prompt 明确）；成员插件的 `after` 钩子本票不执行（Phase 2 限制，通用 host 出范围）。
4. test 的零文件短路先于 prepare：零文件包不写注册、不 spawn host（无测试程序可消费）；满足“PRESTEP 之前调用”的边界含义。
5. 成员 `Plugin_Config` 仍在 COMPILE front 由 `plugin_configs_from_declarations` 计算（与 host 同一函数、同一声明源），prepare 结果只携带注册路径——保持注册文件与 configs 同源，不新增第二份快照。
6. build 对声明成员插件的包现在也会写注册文件（prepare 共享落点；此前 build 从不写）。这是票面“共享 prepare”的直接结果，零插件包不受影响。
7. 零声明成员插件时 prepare 额外删除陈旧 `target/plugins/registration.jai`（会话产物契约硬化：无声明 = 无注册文件）。
