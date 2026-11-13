---
id: 062
title: Phase 2 收口
labels: [implementation]
status: closed
assignee: maojiaxing
blocked-by: [061]
blocks: []
---

# 062: Phase 2 收口

> 上游规格：`docs/spec.md` §8.3/§11.12-16；`jaix-plugin-map.md` 的 Destination。

**What to build:** 跑完 Phase 2 验收矩阵，把 spec 的“设计修订”落成“执行级现实”，更新行数/发布树/守卫，关闭 effort map。

## 交付

1. 全矩阵验收
   - `jai build.jai`（debug/release）于根 exit 0；产物副本于根 build/test 全绿（SKIP 0 权威；直跑 SKIP 2 记环境条件）。
   - 真实 jaix build/test E2E；成员根套件；安装布局 E2E；缺插件/坏插件/坏 options 负例。
   - 守卫零白名单；`src/` 零 jaix 引用。
2. spec 执行级现实
   - 把 2026-10-21 设计修订中已实施的部分标为执行级现实；更新 §8.3 的 Phase 2 形态、§9.2 行数与发布树、§10 注记、§11 风险处置。
   - 更新 `CONTEXT.md`（若实现中术语有细化）。
   - 记录计数基线、白名单 6 行口径、发布件数/行数。
3. 收口
   - 票内 `## Resolution`：验收数字、偏差（全有意）、未来票移交。
   - `jaix-plugin-map.md` Decisions so far 追加一行；`status: closed`。
   - 旧 map（`docs/implementation/map.md`）保持 closed，不改。

## 验收

- 全矩阵绿；守卫零白名单；安装布局全链绿；`src/` 零 jaix。
- spec/CONTEXT 与实际代码一致（行数、发布树、插件面四件、host 会话产物）。
- effort map 关闭；未来票（外部插件坐标、通用 host、非插件 devDeps、Candidate 3）登记在 Not yet specified。

## Out of scope

- 新功能（外部插件抓取、通用 host、整文件转译插件面）。
- 旧 juice 仓处置；兄弟项目。

## Resolution

**2026-10-21，Phase 2 收口完成。本票为全矩阵验收 + 文档收口，无生产代码/测试改动。**

实现摘要：

1. 全矩阵验收（证据 `target/audit-062-*.txt`）
   - `jai build.jai`（debug）于根 exit 0（`audit-062-01-build-debug.txt`）；`jai build.jai - release` exit 0（`audit-062-02-build-release.txt`）。
   - release 产物副本（`target/juice-062-copy.exe`）于根 `build` exit 0（`audit-062-04-copy-build.txt`）、`test` exit 0、**SKIP 0**、`329 passed, 0 failed`（`audit-062-05-copy-test.txt`）；debug 产物副本（`target/juice-062-copy-debug.exe`）于根 `build` exit 0（`audit-062-09-copy-build-debug.txt`）、`test` exit 0、**SKIP 0**、`329 passed, 0 failed`（`audit-062-08-copy-test-debug.txt`）。
   - 直跑 `target/juice.exe test` exit 0、SKIP 2（自托管 posture：bootstrap E2E 自锁，环境条件形态；`audit-062-03-test-direct.txt`）。
   - 真实 jaix build/test E2E（`tests/jaix_plugin_tests.jai` 的 `E2E: jaix pre-step build compiles the mirror through the member and host`、`E2E: jaix pre-step test compiles the mirror and keeps the mixed package`、失败/缺 exe/未声明用例）在副本跑中全绿；测试对兄弟仓 `../jaix-cli/target/jaix.exe` 的存在是响亮断言（无静默跳过），CLI 在位。
   - 成员根套件：`packages/juice-plugin-jaix` 根手动复跑 `../../target/juice.exe test` → exit 0、`17 passed, 0 failed`（`audit-062-06-member-root-test.txt`）；根套件内 `E2E: the jaix member package root runs its own suite green` 同绿。
   - 安装布局全链 E2E：`E2E: an installed juice runs the real jaix member through the host`（含缺插件面负例）、`E2E: an installed juice fails loudly when the jaix member is missing`、`E2E: an installed juice fails loudly when the member shim cannot land`；负例另含 `E2E: a member plugin options rejection fails the build through the host`（坏 options）、`E2E: a host merge conflict fails the build before compiling`、`E2E: a host compile crash fails the build with the host error`、`E2E: a jaix transpile failure propagates diagnostics and produces no artifact`（坏插件）、`E2E: a missing jaix executable fails the pre-step with a clear error`（缺 exe）。全部随副本跑 exit 0 覆盖。
   - 守卫零白名单：`tests/jaix_guard_tests.jai`（6 测试）全绿，含 `Jaix guard: src carries no jaix token at all (empty whitelist)`、`Jaix guard: the whitelist is empty after the member move`、`Jaix guard: the scanner turns red on a seeded violation (negative self-test)`；独立复核 `find src -name '*.jai' | wc -l` = 32、`grep -rni jaix src | wc -l` = 0（`audit-062-07-src-zero-jaix.txt`）。
2. spec 执行级现实
   - `docs/spec.md`：顶部设计修订块标注 054-062 全部交付；§0/§2.1/§2.2/§3.2/§4.6/§5.1/§5.2/§6.1/§6.2/§7.1 补「执行级现实」注记；§8.3 改写为 Phase 2 成员包形态（成员自足面、prepare/shim/注册、host 记录、根包 no-op 声明、空白名单守卫）；§9.2 发布树复核为 8 件并记录行数；§10 追加收口矩阵注记；§11 追加「jaix-plugin effort 终态处置」对 12-16 逐项处置。
   - `CONTEXT.md`：细化 Plugin host（PRESTEP-only + host 记录），新增 Plugin registration file 与 Plugin host record 两条。
3. 收口
   - 本票 `## Resolution`；`jaix-plugin-map.md` Decisions so far 追加 062 行并置 `status: closed`；旧 map `docs/implementation/map.md` 保持 closed、未改。

验证数字：

- 权威 found = max `juice_test_N` **537** + 手写 `note_suite_*` @test **5** = **542**（061 基线；本票无测试增删）。
- 终局末行 `329 passed, 0 failed` 因 Testing 自测 `finish` 重置，不是条目数。
- 预期失败白名单恰 **6 行**（定义源 Testing 自测 2 + `tests/module_tests.jai` 视图/原文各 2；组成自 035/036 未变；当前坐标 `src/module.jai:338/364`（视图）、`tests/module_tests.jai:177/206`（视图）、`tests/module_tests.jai:182/211`（原文映射））；白名单外零 `expect failed`。
- 发布件 8 件：`Juice/module.jai` 112、`Testing.jai` 237、`juice_core.jai` 16、`juice_internal/test_discovery.jai` 285、`plugin_face/{transpile 571, transpile_plugin 553, lifecycle 364, plugin 596}`；四份闭包副本与 `src/` 逐字节相等（`cmp` 全 identical）。
- 守卫：`JAIX_GUARD_WHITELIST` 为空（0 条），`src/` 32 个 `.jai` 文件零 jaix 记号。

Deviations（全有意）：

1. 本票未改生产代码/测试：055-061 已交付实现，062 只做全矩阵复核与文档收口；found 因此与 061 基线相同（542）。
2. §9.2 的闭包行数没有“更新”而只是复核：061 搬移的是 `src/jaix_plugin.jai`（不在发布闭包）与 `src/transpile_config.jai`（不在闭包），四份闭包源（571/553/364/596）未动；发布树 8 件与三模块面 112/237/16、发现源 285 亦未变。
3. 预期失败白名单的坐标随源文件行号漂移（`src/module.jai` 视图行 354/380 → 338/364；`tests/module_tests.jai` 视图行 182/211 → 177/206、原文映射行 187/216 → 182/211），组成仍是 6 行、来源不变；`old-juice-exit.md` §6 记的是 039 时点坐标，本票不改历史文档。
4. jaix E2E / 安装布局 E2E 依赖兄弟仓 jaix-cli 构建（`C:/Users/maojiaxing/Workspace/projects/jai/jaix-cli/target/jaix.exe`，已确认在位）；tests 对该路径做响亮断言，环境缺失会失败而非静默跳过。
5. release 构建覆盖 `target/juice.exe`（既有语义），故产物副本矩阵先跑 release 副本，再以 debug 构建产物副本补 debug 路径；两者都在 `target/` 内（`<exe>/modules` 推导不变）。

未来票移交（已在 effort map 的 Not yet specified 登记，不在本票范围）：外部插件包（非 workspace member）的 source/package 坐标与抓取；通用 lifecycle host（PRESTEP 之外）；非插件测试库的 devDependencies 分类；整文件外部转译器插件面（Candidate 3）；lint 规则/面扩展、插件选项类型化展示、`.map` 消费方。
