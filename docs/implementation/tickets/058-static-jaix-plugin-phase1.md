---
id: 058
title: 静态 jaix 插件（Phase 1）
labels: [implementation]
status: closed
assignee: maojiaxing
blocked-by: [057]
blocks: [059]
---

# 058: 静态 jaix 插件（Phase 1）

> 上游规格：`docs/spec.md` §8.3/§11.14（2026-10-21 设计修订）。Phase 1 的 jaix 插件静态驻 `src/`，但只以 `Juice_Plugin` 的 PRESTEP hook 存在；命令文件零 jaix 知识。

**What to build:** `src/jaix_plugin.jai`：id `juice-plugin-jaix` 的静态内置插件，自带整包扫描、逐文件 spawn jaix、镜像、exe 解析与 litter 处理；通过 PRESTEP before hook 填充源替换表/剔除集。真实 jaix E2E 走 build/test 两条链。

## 交付

1. `src/jaix_plugin.jai`（test-free；测试驻 `tests/`）
   - `get_jaix_plugin() -> *Jaix_Plugin`（派生结构体 `using Juice_Plugin`）；`plugin.id = "juice-plugin-jaix"`；`options` 指向自身；`hooks = [.{stage = .PRESTEP, position = .before, hook = jaix_prestep_hook}]`。
   - options schema：`config`（包相对路径）、`exe`（可选；空 = PATH 查 `jaix`）；`apply` 写入类型化字段；`validate` 拒绝 `exe` 无 `config`。
   - 插件自带扫描：从 root package 递归；排除 dot 条目、非小写 `.jai`、根 `package.jai`、根 `target/`、member 子树、config 文件、含 juice test block 的文件（用插件面的 `pipeline_has_anchors(default_transpile_pipeline(), ...)`）、链接；确定性 DFS 文件先字典序。
   - 逐文件 spawn `jaix transpile <abs> -o <abs> --config <abs>`（全绝对路径、stderr 透传、`working_directory = target/jaix-drivers/`）；失败 = 阶段失败。
   - 镜像 `target/jaix/<rel>`；sidecar `.map` 随 jaix CLI 落；父目录按需创建。
   - 阶段效果：镜像文件 → `substitutions`（original = 原 rel，replacement = 镜像 abs）；config → `drops`；test block 文件不替换；member 子树不扫。
   - 旧 litter 清理：插件识别并清理包根遗留的 jaix driver 文件（内容标记）；新 driver 落 `target/jaix-drivers/`。
2. `src/plugin.jai`
   - 静态内置注册表临时加入 `jaix_plugin`（Phase 2 删除；见 061）。
3. `src/scan_walk.jai` / 扫描消费者
   - 删除 `JAIX_DRIVER_MARKER` / `is_jaix_driver_litter`；`commands/test.jai` 与 `plugin_scan.jai` 的排除集不再引用；相关测试移到 jaix 插件测试。
4. fixtures / E2E
   - jaix demo fixture：`package.jai` 用 `plugins = .[{id="juice-plugin-jaix", version, options=[config]}]`；config 用 jaix try/catch 插件；源含跨文件 `#load` + 一个 juice test block 文件。
   - build E2E：镜像生成、入口直编、artifact 运行 try/catch 降低语义、test block 文件不进镜像、config 不进镜像、`.map` 存在。
   - test E2E：镜像文件 EXPAND、test block 文件原路径、config 剔除、编号/path_mapping 不变。
   - 负例：jaix 语法失败 → stderr 透传 + exit 非零 + 无 artifact；缺 exe → 清晰错误、无 mirror；未声明插件 = 零前置。
5. `src/commands/build.jai` / `test.jai`
   - 除 PRESTEP 派发外无 jaix 分支；本票的验收包括命令文件零 jaix 引用（059 的守卫正式接管）。

## 验收

- 真实 jaix CLI 的 build/test E2E 全绿（PATH 注入的测试助手沿用旧 juice 模式）。
- 未声明插件的包行为零变化。
- `src/` 中 jaix 引用只允许出现在 `src/jaix_plugin.jai`（059 的守卫前身）。
- `jai build.jai` debug exit 0；根 test 全绿。

## Out of scope

- 成员包形态、host（060-061）。
- 守卫测试与收口（059）。

## Resolution

**2026-10-21，实现完成。**

实现摘要（按交付项）：

1. `src/jaix_plugin.jai`（新，test-free）
   - `Jaix_Plugin {using base: Juice_Plugin; config; exe}`；`get_jaix_plugin() -> *Jaix_Plugin`：id `juice-plugin-jaix`、version `0.1.0`、`options` 指向自身、`hooks = [.{stage = .PRESTEP, position = .before, hook = jaix_prestep_hook}]`。
   - options schema：`config`（包相对路径）+ `exe`（可选；空 = PATH 探 `jaix`/`jaix.exe`）；`apply` 写类型化字段、未知 key 返回错误；`validate` 拒绝 `exe` 无 `config`（挂在第一个 schema 行上，避免 per-entry 重复诊断）。
   - 自带整包扫描 `collect_jaix_files`（scan_walk 确定性 DFS）：dot 条目、非 `.jai`、根 `package.jai`、根 `target/`、member 子树、config 文件、driver litter（内容标记）与含 juice test block 的文件（`pipeline_has_anchors(default_transpile_pipeline(), ...)`）；链接不跟随。
   - 逐文件 spawn `jaix transpile <abs> -o <abs> --config <abs>`：全绝对路径、stderr 捕获后原样透传、`working_directory = target/jaix-drivers/`（CLI 的会话 driver 不落包内）；非零退出 = 阶段失败。
   - 镜像 `target/jaix/<rel>`（父目录按需创建）；sidecar `.map` 随 CLI 默认落。
   - 阶段效果：每个镜像文件 `prestep_add_substitution(rel, mirror_abs)`；config `prestep_add_drop`；根遗留 litter 按内容标记识别、删除并 `drops`（test 文件收集早于 PRESTEP，已收集的 litter 必须剔除）；test block 文件不替换；member 子树不扫。
   - `static_builtin_plugins()`：命令侧静态注册 seam（Phase 2 随成员包迁移删除，见 061）。
2. 静态注册接入（落点见 Deviations 1）
   - `src/transpile_config.jai`：`command_plugin_registry()` = `builtin_plugins()` + `static_builtin_plugins()`；`resolve_package_plugins` 用它，声明 `juice-plugin-jaix` 在命令进程内解析（options 应用、版本门、hook 表 + slot_options 对齐）。
   - `src/plugin_scan.jai`：workspace scan 的 built-in skip 改 `is_command_static_plugin_id`（同一注册集合），静态 id 不再被当作 member 而报 unknown id。
   - `src/commands/test.jai`：生成测试 metaprogram 的 configs 经 `plugin_configs_from_declarations(decls, member_packages)` 只嵌 member 声明（生成程序的 registry 只有 builtin + scanned member 值；静态内置声明已在命令侧校验）。
3. 核心 litter 清理
   - `src/scan_walk.jai`：删除 `JAIX_DRIVER_MARKER` / `DRIVER_HEAD_SCAN_LIMIT` / `is_jaix_driver_litter` 及注释。
   - `src/commands/test.jai` / `src/plugin_scan.jai`：排除集不再引用；相关测试迁入 `tests/jaix_plugin_tests.jai`（内容标记矩阵 + 清理 + drop）。
   - 顺带把 059 的注释清理提前：`src/` 内除 `jaix_plugin.jai` 外不再有 jaix 记号（唯一结构例外见 Deviations 3）。
4. fixtures / E2E
   - `tests/data/jaix-demo/`：`package.jai` 以 `Package.plugins` 声明 `{id="juice-plugin-jaix", version="0.1.0", options=[config]}`；`jaix.config.jai` 用 try/catch 插件；`src/main.jai` 跨文件 `#load`；`src/calc.jai` 扩展语法；`src/calc_tests.jai` juice test block。
   - `tests/jaix_plugin_tests.jai`：单元矩阵（身份/options、命令注册解析与槽对齐、scan skip、member-only configs、扫描排除、exe 解析、spawn seam、失败/缺 config/缺 state、litter 矩阵与清理）+ 5 条真实链 E2E（真实 `target/juice.exe` + 兄弟仓 `jaix-cli/target/jaix.exe`，PATH 注入沿用旧 juice 模式；CLI 缺失时 `expect(file_exists(...))` 响亮失败，不静默跳过）。
5. `src/commands/build.jai` / `test.jai`：除既有 PRESTEP 派发外零 jaix 分支（仅注释清理）。

验证：

- `jai build.jai`（debug）exit 0。
- `rm -rf target/transpile && ./target/juice.exe test` exit 0；末行 `311 passed, 0 failed`（Testing 自测 finish 重置，非条目数）。
- 权威 found = 最大 `juice_test_N` **527** + 手写 `note_suite_*` @test **5** = **532**（057 基线 512；本票 +24 新测试 −3 scan_walk litter 测试 −1 test 收集 litter 测试 = +20）。
- E2E 证据（测试名 = 源内 test 块描述）：
  - `E2E: jaix pre-step build compiles the mirror and the lowering runs`：`juice build` exit 0；输出 `[juice] Running jaix pre-step (2 files) -> target/jaix/...`；build metaprogram 引用 `target/jaix/src/main.jai`（入口直编）；artifact 输出 `double(20): NONE 40` / `double(-6): NEGATIVE 0`；`target/jaix/src/calc.jai` 含 `try_0_err, try_0_v := half(n);`；`src/main.jai` 镜像逐字节一致；test block 文件与 config 不进镜像；两份 `.map` 存在；`target/jaix-drivers/` 存在；包根无 litter。
  - `E2E: jaix pre-step test compiles the mirror and keeps the mixed package`：exit 0，`3 passed, 0 failed`，`[test] juice_test_1..3`；metaprogram `original = "src/calc.jai"/"src/calc_tests.jai"/"src/main.jai"` 且无 `jaix.config.jai` pair；calc view 来自镜像（含 lowering，无 `x := try` 语句）；test block view 由原路径 EXPAND（`juice_test_1/3 :: ...`）。
  - `E2E: a jaix transpile failure propagates diagnostics and produces no artifact`：exit 1；stderr 含 `src/main.jai` 与 `Error:`；stdout `[juice ERROR] jaix pre-step failed for src/main.jai`；无 artifact。
  - `E2E: a missing jaix executable fails the pre-step with a clear error`：exit 1；`[juice ERROR] jaix executable not found: `；无 artifact、无 `target/jaix`、无 `target/jaix-drivers`。
  - `E2E: an undeclared package runs no pre-step`：exit 0；无 `[juice] Running jaix pre-step`；无 `target/jaix*`。

Deviations：

1. 静态注册落点：票据交付 2 写「`src/plugin.jai` 静态内置注册表临时加入」，实际落点为命令侧适配器 `src/transpile_config.jai` 的 `command_plugin_registry()`（`builtin_plugins()` + `static_builtin_plugins()`），`plugin_scan` 共享同一 skip 集合。原因：`src/plugin.jai` 是发布插件面闭包四件之一（spec §9.2 发布件数量不变），而 `src/jaix_plugin.jai` 依赖 `scan_walk` / `path_safety` 等非发布闭包模块——在 `plugin.jai` 内直接引用会让发布 `juice_core` 无法编译；发布闭包扩为五件会破坏 §9.2 数量契约。Phase 2（061）删除 `static_builtin_plugins` 与 `command_plugin_registry` 的 extension 段即可。
2. 生成测试程序的 configs 过滤（`plugin_configs_from_declarations` 只嵌 member 声明）：生成程序的 registry 只有 builtin + scanned member 值，静态内置声明在其中必然 unknown；命令侧 `resolve_package_plugins` 已在生成前校验（版本/options），语义不丢。
3. `src/main.jai` 的 `#load "jaix_plugin.jai";` 是 `src/` 中唯一另一处 jaix 记号（文件装载点，编译该文件的唯一手段）。059 守卫需实现为「文件白名单 `src/jaix_plugin.jai` + 该装载行」；把装载点纳入机械白名单是 Phase 1 的必然形态。
4. 插件 version 定为 `0.1.0`（票据/spec 未钉版本；与成员插件 `juice-plugin-lint` 及根包一致）。
5. 空 `config` 的 jaix 声明 = no-op（true、零效果、零 spawn）；`validate` 只拒绝 `exe` 无 `config`（票面唯一校验要求）。
6. 失败诊断双通道：stdout `[juice ERROR]` 用户行 + `ctx` ERROR 诊断（后者按 057 的 dispatch 规则使阶段失败，hook 返回值无法绕过）。
7. 实现提前完成了 059 交付 2 的注释清理（`src/module.jai` / `src/plugin.jai` / `src/lifecycle.jai` / `src/commands/*` / `src/scan_walk.jai` / `src/plugin_scan.jai`），`tests/publication_tests.jai` 的 Juice 模块行 pin 同步更新。
