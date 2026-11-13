---
id: 055
title: Package.plugins 声明面 + manifest 协议 + 硬切
labels: [implementation]
status: closed
assignee: maojiaxing
blocked-by: [054]
blocks: [056]
---

# 055: Package.plugins 声明面 + manifest 协议 + 硬切

> 父 map：`jaix-plugin-map.md`。上游规格：`docs/spec.md` §2.1/§2.2/§2.3/§11.12（2026-10-21 设计修订）。本票只改声明面与协议，不改插件解析语义、不接 PRESTEP、不引入 jaix 插件。

**What to build:** 把 `Package` 的 `jaix` / `transpile` 字段硬切为单一 `plugins` 字段；把 manifest 求值器协议从 `JAIX_*` / `TRANSPILE_PLUGIN` 改为 `PLUGIN` / `PLUGIN_OPTION`；保留现有内置管线与 lint 行为（成员激活暂不变，056 接管）。

## 交付

1. `src/module.jai`
   - 移除 `Jaix_Prestep`、`Package.jaix`、`Transpile_Pipeline_Declaration`、`Transpile_Plugin_Declaration`。
   - 新增 `Plugin_Option {key, value}`、`Plugin_Declaration {id, version, options: [] Plugin_Option}`、`Package.plugins: [] Plugin_Declaration`。
   - 发布段（`[PUBLICATION-SECTION package]`）保持单源；旧字段不保留兼容别名。
2. `src/manifest.jai`
   - 移除 `JAIX_CONFIG` / `JAIX_EXE` / `TRANSPILE_PLUGIN` 的 codegen、解析、`validate_jaix_marker`、`validate_transpile_pipeline`。
   - 新增 `PLUGIN=<id>|<version>` 与 `PLUGIN_OPTION=<id>|<key>|<value>` 记录；codegen 按声明序打印；父进程严格解析。
   - 结构校验：重复 `PLUGIN` id、重复 option key、未知键、形状错、行号；语义校验留给 056 的解析器。
   - 值编码：新增共享 `escape_record_value` / `unescape_record_value`（`%`、`|`、CR、LF → `%XX`），manifest 与后续 host 协议共用。
3. 消费者机械迁移
   - `src/transpile_config.jai`：`resolve_transpile_pipeline` 改读 `Package.plugins`；本票保持“声明 id 只认两个内置 id、空 = 缺省管线”的现有语义（056 泛化）。
   - `src/plugin_scan.jai` / `src/commands/test.jai`：本票保持 DEP 激活面不变；只改类型名/字段引用，测试不回归。
4. fixtures / 测试
   - 所有 `transpile = .{plugins=...}` fixture 改为 `plugins = .[...]`；`tests/data/bad-manifest-jaix-exe` 随 `jaix` 字段移除删除或改为 056/058 的 options 负例。
   - `tests/manifest_tests.jai`：替换 JAIX/TRANSPILE_PLUGIN 协议矩阵为 PLUGIN/PLUGIN_OPTION 矩阵（重复 id、重复 option key、编码往返、行号）。
   - `tests/module_tests.jai` / `tests/plugin_scan_tests.jai` / `tests/transpile_*`：字段引用更新。

## 验收

- `jai build.jai`（debug）exit 0；`target/juice.exe test` 全绿、计数基线随票记录。
- 旧 `jaix` / `transpile` fixture 在 manifest 求值期失败（未知成员）——用真实子进程 E2E 钉住 breaking 行为与错误文本。
- `PLUGIN` / `PLUGIN_OPTION` 编码往返测试（含 `|`、`%`、换行、CRLF）。
- 无残留 `Package.jaix` / `Package.transpile` / `JAIX_*` / `TRANSPILE_PLUGIN` 引用（历史注释除外）。

## Out of scope

- 成员插件的声明驱动扫描/链接（056）。
- `Config_Option.apply` / registry / `resolve_plugin_configs`（056）。
- PRESTEP / jaix 插件（057-058）。
- 根包 lint 从 DEP 迁到声明（056）。

## Resolution

**2026-10-21，实现完成。**

- `src/module.jai`：`Jaix_Prestep` / `Package.jaix` / `Transpile_Pipeline_Declaration` / `Transpile_Plugin_Declaration` / `Transpile_Plugin_Option` 移除；新增 `Plugin_Option {key, value}`、`Plugin_Declaration {id, version, options: [] Plugin_Option}`、`Package.plugins`；`TRANSPILE_PLUGIN_LOAD_ID` / `TRANSPILE_PLUGIN_TEST_BLOCK_ID` 保留为内置 id 常量。发布段单源不变。
- `src/manifest.jai`：记录集改为 `NAME/VERSION/TYPE/DESCRIPTION/BUILD_SCRIPT/PLUGIN/PLUGIN_OPTION/TARGET/MEMBER/EXCLUDE/DEP`（十一条）；`PLUGIN` / `PLUGIN_OPTION` 严格解析（形状、`%XX` 严格解码、重复 id、重复 option key、未声明插件的 option、行号）；父进程新增 `escape_record_value` / `unescape_record_value` 共享编码对，求值子进程生成同一逻辑（`manifest_eval_escape`）。语义校验过渡期留在 `validate_plugin_declarations`（只认两个内置 id、空 options），由 056 的 `resolve_plugin_configs` 接管。
- 消费者：`resolve_transpile_pipeline` 改读 `[] Juice.Plugin_Declaration`；`build` / `test` 调用点改 `root_package.plugins`。
- fixtures / 测试：`manifest-fixture`、重复/未知插件负例改 `plugins`；`bad-manifest-jaix-exe` 保留为 breaking-change fixture（求值期编译失败）；`manifest_tests` 的协议矩阵换成 `PLUGIN` / `PLUGIN_OPTION`（含编码往返），门禁测试换成 `validate_plugin_declarations`，坏 manifest E2E 文本重锁（重复插件行号 7、空 MEMBER/EXCLUDE 行号 6、jaix fixture 走求值失败路径）；`module_tests`、`build_transpile_tests`、`publication_tests` 的字段/类型/发布行 pin 同步。

**Verification**：`jai build.jai`（debug）exit 0；`target/juice.exe test` exit 0，`298 passed, 0 failed`；权威 found = 479（max `juice_test_N`）+ 5（手写 `@test`）= **484**（053 收口基线 485；净 -1 = 删 3 门禁/loader 测试 + PLUGIN/PLUGIN_OPTION 矩阵拆分 +1 + 编码往返 +1）。清 `target/transpile` 后无陈旧视图（测试数变化会移动全局编号）。

**Deviations**：

1. `src/scan_walk.jai` 的 `JAIX_DRIVER_MARKER` / `is_jaix_driver_litter` 及其测试字符串留在原地 — 058 交付项明确移除并迁入 jaix 插件；本票的「无 `JAIX_*` 残留」按协议记录（`JAIX_CONFIG` / `JAIX_EXE` / `TRANSPILE_PLUGIN`）范围执行。
2. `PLUGIN_OPTION` 的 options 槽是发布面的 `[] Plugin_Option` 切片，不能直接 `array_add`；解析器经临时动态数组重建后回写（行数极小）。
3. 求值子进程无法 `#load` `src/manifest.jai`，编码逻辑以生成形式内嵌；父进程的 `escape_record_value` 由往返测试钉住与生成的子进程实现互逆。
