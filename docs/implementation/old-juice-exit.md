# 旧 juice 退场声明

> **生效日期：2026-10-20**。权威验收面 = otter 自举循环（旧 juice 零参与）。父 spec：[006-spec-stage3-bootstrap-closeout.md](tickets/006-spec-stage3-bootstrap-closeout.md)；上游规格：[docs/spec.md](../spec.md) §0-11。证据日志：`otter/target/audit-039-*.txt`（串行执行；各路径先清 `target/transpile`/`target/testing-module`）。

## 1. 退场条件与生效日期

阶段 3 三接缝在旧 juice 零参与的自举循环上全部成立，退场条件（2026-10-20 观测）：

1. **自举循环成立**：`jai build.jai`（debug）与 `jai build.jai - release` 各 exit 0，产出 `target/juice.exe` + 三份模块面 + 一份内部源件；产物副本于根 `build`/`test` 全绿（SKIP 0）。
2. **套件自足**：任何 build/test/E2E 路径不调用旧 juice、不读兄弟仓；机械退场守卫绿（套件内 4 测试 + 独立扫描零命中）。
3. **发布自足**：产物携带运行测试所需的全部源码（第四件内部源件），安装布局（exe + modules，无同级 `src/`）可跑 `test`。
4. **零改写门禁成立**：普通用户包（`#import "Testing"` + 裸 `expect`）失败断言计入汇总、exit 1、坐标指原文行；通过包 exit 0、计数正确。
5. **最终矩阵**（§3）全部观测通过；预期失败白名单恰 6 行。

> **历史口径说明（2026-10-21 补记，053 F3）**：本节记录 2026-10-20（039 收尾）的退场观测——当时发布产物为三份模块面 + 一份内部源件（`juice_core` 12 行）。2026-10-21（048 effort）起，发布产物集为八件：三份模块面 + 一份内部发现源件 + 四份插件面闭包副本，`juice_core` 为 16 行（模块相对 `#load`）。当前口径以 §4/§5 为准；本节历史记录按原观测保留，不回填。

**生效**：自 2026-10-20 起，旧 juice 退出 otter 开发循环；自举循环是唯一权威。旧 juice 仓保持只读历史参照物，不再被调用或读取（§7/§8）。旧仓处置（归档/仓库替换/发布迁移）是独立 effort，不在本声明范围。

## 2. 新开发循环的规范命令

cwd = otter 根，fixture 冒烟注明者除外。

| 目的 | 命令 |
| --- | --- |
| 自举 debug | `jai build.jai` |
| 自举 release | `jai build.jai - release` |
| 构建 | `target/juice.exe build` |
| 测试 | `target/juice.exe test` |
| 权威验收（副本跑，零 SKIP） | `cp target/juice.exe target/juice-copy.exe` → `target/juice-copy.exe build` → `target/juice-copy.exe test` |
| 环境条件形态（直跑，SKIP 2） | `target/juice.exe test`（自构建 E2E 自锁；不作权威数） |
| pattern 过滤 | `target/juice.exe test <pattern>`（子串、大小写敏感） |
| 其余命令 | `target/juice.exe version` / `help` / `run` / `clean` |
| fixture 冒烟 | `cd tests/data/test-blocks && ../../target/juice.exe test` |

执行纪律：各路径先清 `target/transpile` 与 `target/testing-module`；串行执行；证据落 `target/audit-*.txt`；权威计数取 **max `juice_test_N` + 手写 `@test` 条目**（§6），不取字面行数，也不取终局 `M passed`。

## 3. 最终验收矩阵（2026-10-20）

> **历史口径（2026-10-20 观测，2026-10-21 补记 053 F3）**：本矩阵记录 039 收尾时的观测，发布产物为四件（三份模块面 + 一份内部源件，131 / 237 / 12 / 285 行；其中 `juice_core` 现为 16 行）。2026-10-21（048 effort）起发布产物集为八件（另加四份插件面闭包副本，571 / 553 / 243 / 380 行）；当前口径见 §4/§5。本矩阵按历史观测保留，不回填。

### 接缝 1：自举循环（旧 juice 零参与）

| 路径 | 观测 | 证据 |
| --- | --- | --- |
| `jai build.jai`（debug） | exit 0；exe + 四件（131 / 237 / 12 / 285 行）；第四件与 `src/test_discovery.jai` 逐字节相等；平铺 `Juice.jai` 种子零残留 | `audit-039-bootstrap-debug.txt`、`audit-039-artifacts-debug.txt` |
| `jai build.jai - release` | exit 0；四件齐备、第四件逐字节相等；平铺种子零残留 | `audit-039-bootstrap-release.txt`、`audit-039-artifacts-release.txt` |
| 产物副本 `build`（debug / release 各一次） | 各 exit 0；`[juice] Build completed successfully!`；exe 更新 | `audit-039-copy-build-debug.txt`、`audit-039-copy-build-release.txt` |
| 产物副本 `test`（debug） | exit 0；**SKIP 0**；白名单恰 6 行；455 顶层条目（max `juice_test_N` 450 + 手写 5）；269 passed / 0 failed（权威验收） | `audit-039-copy-test-debug.txt` |
| 产物副本 `test`（release） | exit 0；**SKIP 0**；白名单恰 6 行；455；269 passed / 0 failed（权威验收） | `audit-039-copy-test-release.txt` |
| 直跑 `target/juice.exe test`（debug / release） | 各 exit 0；**SKIP 2**（自构建 E2E 自锁 = 环境条件形态）；455；269 passed / 0 failed；白名单 6 | `audit-039-direct-test-debug.txt`、`audit-039-direct-test-release.txt` |

副本跑期间两条自构建 E2E 真实执行（非 SKIP）：套件内 `jai build.jai` 两模式重编译 `target/juice.exe` 并全绿（SKIP 0 即其运行时证据）。

### 接缝 2：姊妹测试（套件自足）

| 项 | 观测 | 证据 |
| --- | --- | --- |
| 机械退场守卫 | 套件内 4 测试全绿（匹配器 / 自零误报 / 全树扫描 / `docs/research` 豁免活证）；独立扫描 `src/`、`tests/`、`build.jai`、`package.jai` 零旧仓路径命中；`docs/research` 3 文件历史引用保留 | 副本跑日志、`audit-039-retirement-scan.txt` |
| 手写 `@test` + test 块混跑 | 顶层条目 455 = max `juice_test_N` 450 + 手写 5；手写条目 `note_suite_*` 排序落在块族之后（日志尾部五连）；顺序确定 | 副本跑日志尾部 |
| 计数约定 | found = max `juice_test_N` + 手写条目；终局 269 passed < 455 因 Testing 自测段内部 `finish()` 重置（既有约定，非回归） | §6 |
| 白名单 | 恰 6 行 `expect failed`（组成见 §6） | 副本跑日志 |
| SKIP | 副本跑 0；直跑 2（自锁）；无其他跳过 | 上述日志 |

### 接缝 3：E2E 真子进程（产物 exe 真跑）

| 场景 | 观测 | 证据 |
| --- | --- | --- |
| 裸名失败用户包 | exit 1；`src/main.jai:5:5: expect failed`；`1 passed, 1 failed`；`[juice ERROR] Test compilation failed.` | `audit-039-bare-name-fail.txt` |
| 裸名通过用户包 | exit 0；`2 passed, 0 failed` | `audit-039-bare-name-pass.txt` |
| test-blocks | exit 0；4 passed / 0 failed（`juice_test_1..4`） | `audit-039-fixtures.txt` |
| test-blocks-fail | exit 1；`src/math.jai:13:5: expect_eq failed: expected 5, got 99`；0 passed / 1 failed | 同上 |
| test-fail | exit 1；`src/failing.jai:16:5: boom`；1 passed / 1 failed | 同上 |
| test-fixture | exit 0；5 passed / 0 failed；`juice_test_2` 先于 `juice_test_10`（数值感知） | 同上 |
| test-dep-root（t11） | exit 0；1 passed / 0 failed；依赖闭包测试零发现零执行 | 同上 |
| test-empty | exit 0；`[juice Test] No tests found.` | 同上 |
| build-with-tests | `build` exit 0；产物运行 `hello from build-with-tests: 2 + 3 = 5` | 同上 |
| plugin fixture 族 | 套件内生产扫描 → 注册文件 → 真 jai 编译 → 合并执行全链绿（好包 `plugin-fixture` / 坏包 `plugin-fixture-bad`） | 副本跑日志（全绿 exit 0） |
| 安装布局 E2E | exe + modules 复制到无同级 `src/` 的布局：`test` exit 0、5 passed；生成 metaprogram `#load <bin>/modules/juice_internal/test_discovery.jai`；`<exe>/../src` 形态零出现 | `audit-039-installed-layout.txt` |
| 六命令冒烟 | `version` / `help` / `build` / `test` / `run` / `clean` 各 exit 0；version = `juice 0.1.0` + `jai 0.2.9`；clean 删除根与两成员 `target/` | `audit-review-fixes-six-command-smoke.txt`（含 exe 绝对路径 + sha256 `4d4d968f…` + version 身份头；原 `audit-039-six-command-smoke.txt`） |

## 4. spec §0-11 逐节覆盖对照

状态词：**已交付** / **执行级订正后交付** / **未来票** / **出范围**。无未分类节。

| 节 | 内容 | 状态 | 说明 |
| --- | --- | --- | --- |
| §0 | 方案概要 | 执行级订正后交付 | 六命令（不是四命令）；发布 = 三份模块面 + 内部发现源件 + 四份插件面闭包副本（2026-10-21，048）；`packages/juice-plugin-lint` 成员实体已交付（2026-10-21）；安装布局插件加载已交付（2026-10-21，048）；jaix PRESTEP 见未来票 |
| §1 | 目标与设计原则 | 已交付 | 七原则全部落地：声明兼容、确定性、行号保真、test-free 闭包、零特判、失败即停、Windows-first |
| §2 | package 声明兼容面 | 已交付 | §2.1 全字段（含 `jaix`/`transpile` 容忍面）、§2.2 KEY=VALUE 协议与两道校验门、§2.3 结构层 vs juice 专属层 |
| §3 | 仓库布局规格 | 已交付 | 根 BIN 包、`src/module.jai` 单源、`tests/`、`build.jai`、成员状态机与分发契约（成员包零工具依赖，`juice_core` 由工具提供；2026-10-21，048）均已交付并验证；真实成员 `packages/juice-plugin-lint` 已建并作为自身根测试全绿（2026-10-21）；`packages/juice-plugin-{test,transpile}` 成员未建（未来票） |
| §4 | 命令架构 | 执行级订正后交付 + 未来票（t2） | 六命令 + 静态注册表 + dispatcher + 前置链 + 四挂载点 at 接线（阶段级粒度）；t2 jaix PRESTEP 与其余 9 个生命周期挂载点机械接线（`test dep_transpile` 已被 test TRANSPILE 阶段级 at 替换涵盖）= 未来票 |
| §5 | 插件系统 | 已交付 | Juice_Plugin 全字段（含 lint 面）、扫描 → 注册文件 → 合并查重、内置静态注册表、身份进缓存键；真实第三方成员包 `packages/juice-plugin-lint` + 真实布局全链 lint E2E 已随 040 effort 交付（2026-10-21）；安装布局（exe + `modules/`，无同级 `src/`）插件全链 E2E 与发布产物契约已随 048 effort 交付（2026-10-21） |
| §6 | lifecycle 挂载 | 执行级订正后交付 + 未来票（其余 9 个生命周期挂载点） | 九阶段封闭枚举、before/at/after、注册序确定性、显式 ctx、失败语义；at 子集 = build/test 的 TRANSPILE/COMPILE 四挂载点，派发粒度 = 阶段级 |
| §7 | test 命令 | 执行级订正后交付 + 未来票（显示名） | note 发现、单一发现源、runner 注入、编号/排序/查重、短路/过滤全部交付；显示名 = 过程名，`@test("name")` 显示名恢复 = 未来票；"Found N tests" 不产（§6 计数约定） |
| §7.5 | juice-compat 零改写 | 执行级订正后交付 | 普通用户包裸名门禁修复并 E2E 实证（失败计入汇总、exit 1、原文行）；存量 test 块零改写；fixture 族=真实用户包代表 |
| §8 | 转译与 lint | 已交付 | §8.1 两内置插件、行号保真门、缓存键、扫描/转译全链；§8.2 lint = observer metaprogram 插件已交付（真实成员规则、`.TYPECHECKED` 收集期观察、`compiler_report` 三汇 + 原始路径 + 1 基坐标、全链 E2E，2026-10-21） |
| §9 | 运行期模块发布 | 执行级订正后交付 | 三份模块面（131/237/16 行，三种转换形态）+ 内部发现源件（285 行逐字复制）+ 四份插件面闭包副本（571/553/243/380 行逐字复制，`juice_core` 以模块相对路径 `#load`）；先发布后编译；每跑重生；内部发现源件 = 私有目录契约（生成的测试 metaprogram 以绝对路径 `#load`；非编译器强制不可导入）；发布树可整体搬迁、无构建根路径（2026-10-21，048） |
| §10 | 自举路线 | 执行级订正后交付 | 阶段 0-3 全部验收；阶段 3 = 自举循环 + 副本跑零 SKIP + 旧 juice 退场；阶段 0-2「只写 test 块」约束阶段性退役 |
| §11 | 风险与未决项 | 已交付（逐项处置）+ 出范围/未来票拆分 | 11 项逐项处置见 §5；§11.1/§11.7/§11.8 出范围，§11.3 本 effort 不消费，§11.5 观察类最终形状已随 lint 交付，§11.11 安装布局插件加载已随 048 effort 交付（2026-10-21） |

§12 为引用清单（历史来源锚点），按 §7 残留历史引用政策保留，不是运行依赖，无交付状态。

## 5. §11 风险逐项处置

| # | 风险 | 处置 |
| --- | --- | --- |
| 1 | linkme 式链接期聚合 | **出范围**（jai 编译器特性请求素材；交付形态 = 静态内置注册表 + 构建期扫描注册） |
| 2 | note 机制 beta 绑定 | **保留并记录**：note 文本与消息面绑定 beta 0.2.009；精确匹配 `"test"` / 前缀 `"test("` 策略保留（子串会误收 PrintLike/NoProfile）；官方 test framework 落地后复核 |
| 3 | `compiler_report_errors_for_untyped_declarations_with_these_notes` | **零使用**：语义 spike 未做（006 出范围清单）；若未来用于强制 `@test` 签名，先 spike 再开票 |
| 4 | at 替换钩子的缓存键语义 | **已文档化**：替换实现 = 换视图键；driver/metaprogram 是每跑重生的会话产物，不进键 |
| 5 | 观察类钩子诊断形状 | **已交付**：三汇诊断 + 钩子失败中止语义已交付；观察类（lint）最终诊断形状经 `Juice_Plugin.lint` 面交付——findings `WARNING/ERROR/INFO` → `compiler_report` 三汇、原始包相对路径、1 基坐标，全链 E2E 实证（2026-10-21） |
| 6 | 阶段枚举稳定性承诺 | **已兑现**：封闭枚举只增不改 + spec 版本化注释 |
| 7 | 第三方宿主（DLL/进程外） | **出范围**；字符串 ABI 属新设计面 |
| 8 | 未来特性清单（glob members / exclude / --workspace / 版本继承） | **出范围**（全部非 bootstrap 前置） |
| 9 | 增量构建缓存键契约 | **已交付**：键 = hash（路径+源+模式+版本+load 重写表+管线描述）；otter 独立版本分量，与旧 juice 键不共享 |
| 10 | Windows 现实约束 | **已按既有解法交付**：LNK1104 hand-off 副本纪律、`cmd /c`、子进程 CWD 绝对路径、大小写近匹配拒绝；自举无 hand-off（直跑 SKIP 2）为已记录形态 |
| 11 | 安装/打包布局下的第三方插件加载 | **已交付**（2026-10-21，048 effort）：插件面闭包四件逐字复制到 `<modules>/juice_internal/plugin_face/`，`juice_core.jai` 以模块相对路径 `#load`；`juice_core` = 工具提供的模块面（成员包零依赖）；安装 = exe + 相邻 `modules/`（无同级 `src/`/`target/`）；发布产物契约断言与真安装布局插件全链 E2E 全绿（049/051） |

**残留风险（2026-10-21 复查补记，053 F5）**：可执行文件内嵌构建机的 caller-location 路径——`#caller_location` 的 `fully_pathed_filename` 指向构建机源码，测试失败诊断可能打印构建机路径。这不影响模块/插件解析（发布树仍无构建根；安装契约仍为 exe + 相邻 `modules/`），但「整棵安装树无构建根」的自动断言必须排除 exe，只扫描发布的 `modules/` 树（053 的安装 E2E 即如此；见 053 F4/F5）。

## 6. 计数约定与白名单组成

**found（顶层条目）** = max `juice_test_N` + 手写 `@test` 条目 = **450 + 5 = 455**。

- 不取字面 `^[test] juice_test_N$` 行数：并行子进程的 stderr 会与顶层 `[test]` 行交错，字面计数随跑法形状漂移——副本跑日志 = 447 条完整行 / 448 处带数字编号（3 个入口受损：`juice_test_87` 缺 `[test] ` 前缀、两条名字被 stderr 交错吞掉；`juice_test_247` 完好）；直跑日志 = 449 / 450（`t] juice_test_247`）；两种形状 max `juice_test_N` 恒为 450，编号连续性不受影响。权威 found 只取 max N + 手写条目。
- 不取终局 `M passed` 作为 found：Testing 自测段内部多次 `finish()` 会重置计数器，终局只计最后一次 reset 之后；本轮 **269 passed / 0 failed**。绿色判据 = exit 0 + max N + 手写条目 + 无白名单外 `expect failed`，不是 `M == found`。
- otter `test` 不打印 "Found N tests"（017 起的既有形态，发现发生在 metaprogram 内）。

**预期失败白名单（恰 6 行，组成自 035/036 起未变）**：

| 行 | 来源 |
| --- | --- |
| `src/module.jai:354:9`（视图路径） | 定义源 Testing 自测块（prefixed 内部面） |
| `src/module.jai:380:9`（视图路径） | 同上 |
| `tests/module_tests.jai:182:5`（视图路径） | Testing face 自测（prefixed 面） |
| `tests/module_tests.jai:211:5`（视图路径） | 同上 |
| `tests/module_tests.jai:187:5`（原文行映射） | Testing face 自测（裸面） |
| `tests/module_tests.jai:216:5`（原文行映射） | 同上 |

白名单外出现任何 `expect failed` = 新失败；新增预期失败必须显式记录，不得靠汇总掩盖。

**SKIP 约定**：副本跑 = 0（权威）；直跑 = 2（`bootstrap E2E` 自锁，环境条件形态，不作权威）。

## 7. 残留历史引用政策

- **参考来源，不是运行依赖**：`docs/research/` 保留旧 juice 源码锚点与研究期路径引用（当前 3 个文件命中历史路径形态：`cargo-style-monorepo.md`、`note-based-testing.md`、`otter-refactor-research.md`），用于 provenance 与规格溯源。
- **扫描范围**：机械退场守卫只扫 `src/`、`tests/`、`build.jai`、`package.jai`；`docs/` 不在扫描根（历史引用豁免）。守卫自身针字符串分段构造，零自命中。
- **活证**：套件内「`docs/research` 历史引用保留为豁免」测试要求 research 文件命中 > 0 且不在扫描根，防止豁免被误删成假绿。
- **纪律**：新增源码/测试/build/package 文件不得再引入兄弟仓路径；docs 中的历史引用不得被任何 build/test/E2E 路径读取。

## 8. 旧仓处置边界

- 旧 juice 仓（兄弟目录 `C:\Users\maojiaxing\Workspace\projects\jai\juice`）在本 effort 全程**只读**：未调用、未读取作为验证依赖、零修改。
- **本声明只宣布退场，不执行处置**。归档、仓库替换、发布迁移（含版本号/发布渠道/旧包用户迁移）是独立 effort，归后续决定；本 map 不含该工作。
- 旧仓继续作为历史参照物存在；不得以任何形式回到 otter 的 build/test/E2E 循环。
