---
id: 059
title: Phase 1 守卫 + 收口
labels: [implementation]
status: closed
assignee: maojiaxing
blocked-by: [058]
blocks: [060]
---

# 059: Phase 1 守卫 + 收口

> 上游规格：`docs/spec.md` §8.3/§11.12-16；`jaix-plugin-map.md` 的 Phase 1 定义。

**What to build:** 用机械守卫钉住“命令与核心不再认识 jaix”，清理残留注释/引用，跑完 Phase 1 验收矩阵并关闭 Phase 1。

## 交付

1. 守卫测试（`tests/`，架构守卫族）
   - 扫描 `src/` 下所有 `.jai`：出现 `jaix` / `JAIX` 记号（含注释、字符串）即失败；Phase 1 白名单 = `src/jaix_plugin.jai`。
   - 失败信息给出文件与行号；白名单以常量列表形式单源维护（061 清空）。
   - 守卫测试自身不 import jaix 插件实现（只做源文本扫描）。
2. 清理
   - `src/lifecycle.jai` 的 PRESTEP 注释改为通用 pre-step 描述；`src/module.jai` / `src/manifest.jai` / `src/commands/*` / `src/scan_walk.jai` 的 jaix 注释清理。
   - 移除 055-058 留下的临时兼容注释/字段。
3. Phase 1 验收矩阵
   - `jai build.jai`（debug/release）于根 exit 0；产物副本于根 build/test 全绿（SKIP 0 权威）。
   - jaix build/test E2E（058）全绿；无 jaix 声明的包行为零变化。
   - 守卫绿；`src/lifecycle.jai` / `src/plugin.jai` 的插件面发布副本逐字节核（行数更新）。
   - fixture 计数基线记录；白名单 6 行口径核对。
4. 收口
   - 票内 `## Resolution`：验收数字、偏差、Phase 2 移交点。
   - `jaix-plugin-map.md` Decisions so far 追加一行；frontier 推进到 060。

## 验收

- 守卫在 Phase 1 白名单下绿；把白名单临时去掉时守卫红（负向自测）。
- 全矩阵与 058 的 E2E 全绿；无 `Package.jaix` / `JAIX_*` / `TRANSPILE_PLUGIN` 残留。
- `src/jaix_plugin.jai` 是 `src/` 中唯一含 jaix 记号的源文件。

## Out of scope

- Phase 2（060-062）。
- 通用 host / 成员包。

## Resolution

**2026-10-21，实现完成。**

实现摘要（按交付项）：

1. 守卫测试（`tests/jaix_guard_tests.jai`，新增 6 个测试）
   - 扫描 `src/` 下全部 `.jai` 源文本（注释与字符串一并命中，纯文本扫描非 lexer）的 `jaix`/`JAIX` 记号：大小写不敏感、逐行报告全部出现位置；失败信息 = `path:line:column: 行文本`。
   - Phase 1 白名单单源常量 `JAIX_GUARD_WHITELIST`（`Jaix_Guard_Allowance.[]`）恰两项：`src/jaix_plugin.jai`（整文件）+ `src/main.jai` 的 `#load "jaix_plugin.jai";`（装载行，行级白名单——main.jai 其余行仍受守卫）。058 Deviation 3 已把该装载点记录为 Phase 1 的必然结构例外；061 迁包后整表清空。
   - 负向自测：同一真实扫描以空白名单运行即命中（见验收证据，套件 exit 1 实证）；另钉白名单形态（2 项）、装载行恰好一条（陈旧/拼错白名单会红）、移除协议名零残留（`TRANSPILE_PLUGIN=` 协议记录形态 + `Transpile_Plugin_Declaration` / `Transpile_Pipeline_Declaration` / `Transpile_Plugin_Option` / `Jaix_Prestep` / `JAIX_CONFIG` / `JAIX_EXE`）。
   - 守卫自身不 import jaix 插件实现：只用 Basic/File_Utilities/String/Testing，只做源文本扫描。
2. 清理
   - 055-058 的 jaix 注释清理已由 058 Deviation 7 提前落地：`src/lifecycle.jai` 的 PRESTEP 注释是通用 pre-step 描述；`src/module.jai` / `src/manifest.jai` / `src/commands/*` / `src/scan_walk.jai` / `src/plugin_scan.jai` 已无 jaix 记号。059 以守卫机械钉住并记录，生产代码零改动。
   - `src/` 中 jaix 记号只剩白名单两条（插件模块 + 装载行）；`TRANSPILE_PLUGIN*` 只剩 055 明示保留的内置 id 常量 `TRANSPILE_PLUGIN_LOAD_ID` / `TRANSPILE_PLUGIN_TEST_BLOCK_ID`（单源 `src/module.jai`，非协议记录/旧门）。
3. Phase 1 验收矩阵（证据文件 `target/audit-059-*.txt`）
   - `jai build.jai`（debug）exit 0（audit-059-10）；`jai build.jai - release` exit 0（audit-059-11）。
   - release 产物副本 `target/juice-copy.exe`：根 `build` exit 0（audit-059-12）；根 `test` exit 0、**SKIP 0**、6 条 expect-failed 白名单、max `juice_test_N` 533（audit-059-13 / audit-059-32 终态复跑）。
   - 直接 `./target/juice.exe test` exit 0（自托管 posture SKIP 2；audit-059-31）。
   - jaix 真 CLI E2E（手动复跑 `tests/data/jaix-demo`，PATH 注入兄弟仓 `jaix-cli/target/jaix.exe`）：build exit 0、`[juice] Running jaix pre-step (2 files) -> target/jaix/...`、artifact 输出 `double(20): NONE 40` / `double(-6): NEGATIVE 0`（audit-059-20）；test exit 0、`[test] juice_test_1..3`、`3 passed, 0 failed`（audit-059-21）。套件内 058 的 5 条 jaix E2E（build/test/失败/缺 exe/未声明）同跑全绿。
   - 无 jaix 声明零变化：`tests/data/build-ok` build exit 0、输出零 jaix、artifact 生成（audit-059-22）；套件 E2E “an undeclared package runs no pre-step” 同绿。
   - 守卫绿/红两向：临时清空白名单 → `test` exit 1，打印 `[jaix guard] src/jaix_plugin.jai:3:18: ...` 等命中（audit-059-30）；恢复白名单 → exit 0（audit-059-31）。
   - 插件面发布副本逐字节：`target/modules/juice_internal/plugin_face/{transpile,transpile_plugin,lifecycle,plugin}.jai` 与 `src/` 同名源 `cmp` 相等；行数 = **571 / 553 / 364 / 596**（lifecycle 243→364、plugin 380→596，048 基线更新）。同批核到三份模块面 = **112 / 237 / 16**（Juice 模块随 055 字段硬切 131→112）；`docs/spec.md` §9.2 两处行数已就地更新。
   - 白名单 6 行口径：`grep -c "expect failed"` = **6**（src/module.jai 自测 2 + tests/module_tests.jai 4），与 039 以来口径一致。
4. 收口：本 `## Resolution`；`jaix-plugin-map.md` Decisions so far 追加 059 行；frontier 推进到 060。

验证数字：`rm -rf target/transpile && ./target/juice.exe test` exit 0；末行 `311 passed, 0 failed`（Testing 自测 `finish` 重置，非条目数）；权威 found = 最大 `juice_test_N` **533** + 手写 `note_suite_*` @test **5** = **538**（058 基线 532；本票 +6 守卫测试）。

Deviations：

1. Phase 1 白名单 = 文件项 `src/jaix_plugin.jai` + 条目级 `src/main.jai` 装载行，而非单一文件项：`#load "jaix_plugin.jai";` 是编译该模块的唯一手段（058 Deviation 3 记录的必然结构引用）。两项同属一个常量列表单源维护，061 一并清空；验收「`src/jaix_plugin.jai` 是 `src/` 中唯一含 jaix 记号的源文件」按「唯一含 jaix 记号的源文件 + 唯一结构装载行，白名单外零命中」兑现。
2. 「无 `Package.jaix` / `JAIX_*` / `TRANSPILE_PLUGIN` 残留」按已退役协议名判定：`Package.jaix` 字段、旧记录 `JAIX_CONFIG` / `JAIX_EXE`、`TRANSPILE_PLUGIN=` 记录与已退役声明类型名在 `src/` 零命中（守卫测试钉住）；保留的内置 id 常量 `TRANSPILE_PLUGIN_LOAD_ID` / `TRANSPILE_PLUGIN_TEST_BLOCK_ID` 是 055 明示保留的单源常量（`src/module.jai`），`JAIX_PLUGIN_ID` 等是白名单插件模块的内部常量，二者都不是协议残留。
3. 清理无生产代码改动：059 交付 2 的注释清理已由 058 提前完成（058 Deviation 7）；本票以守卫机械验证并记录，不重复改动。

Phase 2 移交点：

- 060：PRESTEP-only plugin host + 命令级 prepare；命令侧静态注册 seam（`src/transpile_config.jai` 的 `static_builtin_plugins` / `is_command_static_plugin_id` 与 `src/plugin_scan.jai` 的共享 skip）是 Phase-1 形态，060 的注册文件/宿主准备复用同一声明解析面。
- 061：`src/jaix_plugin.jai` 迁入 `packages/juice-plugin-jaix/` 后，清空 `JAIX_GUARD_WHITELIST`（含 main.jai 装载行）、删除 `static_builtin_plugins` 与 `#load "jaix_plugin.jai";`；守卫的负向自测与残留检查保留，正向扫描自然转为全 `src/` 零命中。
