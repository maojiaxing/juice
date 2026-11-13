---
id: 039
title: 阶段 3 终态验收 + 退场声明 + spec 收尾 + map 收口
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: [035, 036, 037, 038]
blocks: []
---

> 父 spec：`006-spec-stage3-bootstrap-closeout.md`（决定 10-14；三接缝终态）。上游规格：`docs/spec.md` §0-11。

# 039: 阶段 3 终态验收 + 退场声明 + spec 收尾 + map 收口

**What to build:** 阶段 3 的终态验收在旧 juice 零参与的自举循环上跑通，并留下可审计的退场声明：三接缝矩阵、spec §0-11 逐节覆盖对照、§11 风险逐项处置、残留历史引用政策与旧仓处置边界。spec §9/§10/§7.5/§0 折回执行级事实；map Not yet specified 清空为未来票记录；spec 006 与 map 收口。

**Blocked by:** 035、036、037、038

**Status:** closed

- [x] 接缝 1：`jai build.jai` debug/release 各 exit 0，产出 exe + 三份模块面 + 内部源件；产物副本于根 build/test exit 0、SKIP 0、白名单 6、无其他失败；直跑产物记录 SKIP 2。
- [x] 接缝 2：套件自足（机械退场守卫绿）、手写 `@test` + test 块混跑、基线计数与白名单记录在案。
- [x] 接缝 3：裸名失败用户包 exit 1 且坐标指原文行；test-blocks/test-dep/plugin fixture 族、build-with-tests 与六命令冒烟全绿。
- [x] 退场声明文档：带日期，含退场条件、规范命令、最终矩阵、§0-11 覆盖状态（已交付/订正/未来票/出范围）、§11 处置表、残留历史引用政策、旧仓处置边界。
- [x] spec 折回：§9 发布物 = 三份模块面 + 内部源件；§10 阶段 3 行；§7.5 零改写实证；§0 概述；§11 处置结论。
- [x] map Not yet specified 清空为未来票记录；006 写 `## Resolution` + status: closed；map Decisions 追加最终行并收口。
- [x] 本票改动为文档与验收记录；旧 juice 仓零改动。

## Resolution

**实现摘要**（2026-10-20）：阶段 3 终态验收在旧 juice 零参与的自举循环上全绿，退场声明落地。生产代码零改动（仅 docs 与 `target/audit-039-*.txt` 证据）；旧 juice 仓未调用、未读取、零修改。验收串行执行，各路径先清 `target/transpile`/`target/testing-module`。

**接缝 1（自举循环）**：

| 路径 | 结果 |
| --- | --- |
| `jai build.jai`（debug） | exit 0；四件 = `Juice/module.jai` 131 行 / `Testing.jai` 237 行 / `juice_core.jai` 12 行 / `juice_internal/test_discovery.jai` 285 行（与 `src/test_discovery.jai` 逐字节相等）；平铺 `Juice.jai` 种子零残留 |
| `jai build.jai - release` | exit 0；四件齐备、第四件逐字节相等；平铺种子零残留 |
| 副本 `build`（debug / release 各一次） | 各 exit 0；`[juice] Build completed successfully!`；exe 更新 |
| 副本 `test`（debug） | exit 0；**SKIP 0**；白名单恰 6 行；455 顶层条目（max `juice_test_N` 450 + 手写 5）；269 passed / 0 failed |
| 副本 `test`（release） | exit 0；SKIP 0；白名单 6；455；269 passed / 0 failed |
| 直跑 `target/juice.exe test`（debug / release） | 各 exit 0；**SKIP 2**（自构建 E2E 自锁 = 环境条件形态）；455；269 passed / 0 failed；白名单 6 |

副本跑期间自构建 E2E 真实执行（SKIP 0），套件内 `jai build.jai` 两模式重编译产物并全绿。

**接缝 2（姊妹测试）**：机械退场守卫套件内 4 测试绿；独立扫描 `src/`、`tests/`、`build.jai`、`package.jai` 零旧仓路径命中；`docs/research` 3 文件历史引用保留（豁免活证）。手写 `@test` 5 条（`note_suite_*`，含一条 `@test(custom_name)`）与 450 条 test 块同源发现、同序编号，日志尾部五连即混合序证据。

**接缝 3（E2E 真子进程）**：裸名失败用户包 exit 1、`src/main.jai:5:5: expect failed`、`1 passed, 1 failed`、`[juice ERROR] Test compilation failed.`；裸名通过包 exit 0、2 passed。fixture 族：test-blocks 4/0 exit 0；test-blocks-fail exit 1 + `src/math.jai:13:5`；test-fail exit 1 + `src/failing.jai:16:5`；test-fixture 5/0（`juice_test_2` 先于 `juice_test_10`）；test-dep-root 1/0（依赖测试零发现零执行）；test-empty「No tests found」exit 0；build-with-tests build exit 0 + 产物 `hello from build-with-tests: 2 + 3 = 5`；plugin fixture 族由套件生产扫描全链覆盖（全绿）；安装布局 E2E exit 0、5 passed、生成 metaprogram `#load <bin>/modules/juice_internal/test_discovery.jai`、`<exe>/../src` 形态零出现；六命令冒烟 `version`/`help`/`build`/`test`/`run`/`clean` 各 exit 0（复查修复重跑：exe 绝对路径 + sha256 + version 身份头见 `target/audit-review-fixes-six-command-smoke.txt`）。

**计数约定**：found = max `juice_test_N` 450 + 手写 5 = **455**；字面 `^[test] juice_test_N$` 行数随跑法形状漂移（并行子进程的 stderr 与顶层 `[test]` 行交错），不能作为计数依据——副本跑日志 = 447 条完整行 / 448 处带数字编号（3 个入口受损：`juice_test_87` 缺 `[test] ` 前缀、两条名字被 stderr 交错吞掉；`juice_test_247` 完好），直跑日志 = 449 / 450（`t] juice_test_247`），两种形状 max N 恒为 450；终局 **269 passed** < 455 因 Testing 自测段内部 `finish()` 重置（既有口径，不是回归）。白名单恰 6 行：`src/module.jai` 自测视图路径 :354:9 / :380:9、`tests/module_tests.jai` prefixed 面视图路径 :182:5 / :211:5、裸面原文行 :187:5 / :216:5。

**文档产出**：

- 新增 `docs/implementation/old-juice-exit.md`：退场条件与生效日期（2026-10-20）、规范命令、最终矩阵、spec §0-11 逐节覆盖状态（无未分类节）、§11 十项逐项处置、残留历史引用政策、旧仓处置边界、计数约定与白名单组成。
- `docs/spec.md` 折回：§0（六命令 + 三份模块面 + 内部源件 + 生成件树）、§7.2（单一形态；`face_is_discovered` 退役一致性订正）、§7.5（普通用户包零改写实证）、§9.2/§9.5/§9.6（四件发布物、计数、裸面单一寄存器）、§10（阶段 2 产物表述 + 阶段 3 验收行 + 阶段 0-2 写法约束阶段性退役）、§11（终态处置结论）。
- `docs/implementation/map.md`：Notes 追加链 035-039 闭环行；Not yet specified 转为「未来票记录 + 出范围 remainder」；Decisions so far 追加 039 最终行；status: closed。
- 父 spec `006-spec-stage3-bootstrap-closeout.md`：`## Resolution`（收口摘要、最终矩阵、US 40 分组映射、决定 1-17 直落、链偏差 035-039 汇总、边界）；全部 checkbox 勾选；status: closed。

**偏差/说明**（全有意，无遗留缺陷）：

1. **spec §7.2 一致性订正**：该节仍引用已退役的 `face_is_discovered` 与「prefixed 消费面」；按 035 收口事实改为单一形态（driver 恒 `#import "Testing"`、runner 恒裸名），纳入 §0-11 覆盖对照的交付基础。超出票面点名的 §9/§10/§7.5/§0/§11 折回面，属「保持 spec 内部一致」的必要订正。
2. **计数按 max N + 手写**：otter test 不打印 "Found N tests"（017 起），字面行数受已知 stderr 覆盖噪声影响；权威口径与 037/038 一致。
3. **plugin fixture 族证据 = 套件全链 E2E**：plugin 扫描/合并无 CLI 命令面，其生产全链由套件内 E2E 驱动；副本跑 exit 0 + SKIP 0 即该族通过证据。
4. **直跑副本与模式次序**：每模式先直跑（SKIP 2）后副本跑（SKIP 0）；副本跑会由套件内自构建 E2E 重编译 `target/juice.exe`（两模式），不影响副本权威判据。

**边界/落盘**：`src/`、`build.jai`、`package.jai` 零改动；旧 juice 仓零改动；证据 `otter/target/audit-039-*.txt`（bootstrap/artifacts/direct-test/copy-build/copy-test × debug+release、fixtures、bare-name-fail/pass、six-command-smoke、installed-layout、retirement-scan）；无残留进程；fixture `target/`、安装布局与临时用户包目录已清。

## 复查修复

**来源**（2026-10-20，独立复查 `target/review-findings-stage3.md`；本票保持 closed）：5 项 minor findings + 4 项 open questions 全部处置。改动面 = docs 与注释；唯一测试运行行为面改动 = `tests/bootstrap_tests.jai` 的 SKIP 诊断字符串/注释（Finding 2，仅诊断文本、无逻辑）；发布文本钉 `tests/publication_tests.jai` 的 `EXPECTED_TESTING_MODULE_LINES` 随 `src/module.jai` Testing 段注释更新（行数不变，发布物仍 237 行）。生产行为零改动；旧 juice 仓未运行、未修改（仅只读核对 Testing API 符号名，非验证依赖）。

**Findings**：

1. **字面计数/噪声口径（fixed）**：本票计数约定、`old-juice-exit.md` §6、记忆 `otter-suite-count-convention` 改为按跑法形状的实证叙事：副本跑 = 447 条 `^[test] juice_test_N$` 完整行 / 448 处带数字编号（3 个入口受损：`juice_test_87` 缺 `[test] ` 前缀、两条名字被 stderr 交错吞掉；`juice_test_247` 完好）；直跑 = 449 / 450（`t] juice_test_247`）；两种形状 max `juice_test_N` 恒为 450；权威 found 只取 max N 450 + 手写 5 = 455（269 passed；白名单 6）。不承诺字面行数。
2. **SKIP 诊断（fixed）**：`tests/bootstrap_tests.jai` 的 `bootstrap_e2e_self_locked` 消息与注释删除已退场的 old-juice 循环；唯一全 coverage 路径 = target/ 副本跑。行为不变（仅字符串/注释）。
3. **剩余接缝计数（fixed）**：spec §6.3、006 决定 11/Out of Scope、退场声明 §4 §6 行、map Not yet specified 当前权威陈述统一为「9 个生命周期挂载点」，并注明 `test dep_transpile` 已被 test TRANSPILE 阶段级 at 替换涵盖。004 历史拍板的 Notes 行不改写。
4. **fixture 迁移簿记（fixed）**：006 决定 3/US 映射、035 复选框/偏差、036 测试面改动统一为「11 文件、24 处调用（15 迁移为裸名 + 9 删除 prefixed 腿；原 26 行 grep 含 2 行注释/定义）」。
5. **陈旧注释（fixed）**：按 finding 清单改为现在时/显式历史：
   - `src/test_discovery.jai`（runner 用裸 `path_mapping`/`Path_Pair`）、`src/publication.jai`（main.jai 已 #load，test 命令消费路径助手）、`src/module.jai`（header + Testing banner：发布面唯一消费路径、prefixed 名 = 定义源内部面、API 列表面）、`src/juice_module.jai`/`src/manifest.jai`/`src/workspace.jai`（解析到发布面，非旧仓 bootstrap）、`src/plugin_scan.jai`（published juice_core，非 stand-in）、`build.jai`（otter test 入口 = target/transpile/first.jai）、`tests/test_support.jai`（`jai build.jai` 构建；四件发布）、`tests/module_tests.jai`、`tests/e2e_cli_tests.jai`、`tests/test_transpile_tests.jai`、plugin fixture 三件。
   - `src/module.jai` Testing 段注释为发布文本，`EXPECTED_TESTING_MODULE_LINES` 同步更新（行数不变）。

**Open questions**：

- **A（fixed）**：`juice_internal/` 的表述改为私有目录契约——只被生成的测试 metaprogram 以绝对路径 `#load`，不发布为公开 import 面；编译器导入路径仍可见该目录，不声称编译器强制不可导入。spec §0/§9.2、006 决定 4（+Resolution）、退场声明 §4 §9 行更新；既有 `#load` 钉（安装布局 E2E/生成 metaprogram 文本）保留。
- **B（fixed）**：六命令冒烟带显式身份头重跑（exe 绝对路径 + sha256 + 字节数 + version），新证据 `target/audit-review-fixes-six-command-smoke.txt`；本票矩阵与退场声明 §3 证据引用更新。
- **C（fixed）**：006 决定 15 与 Testing Decisions 的执行纪律改为交付口径（max `juice_test_N` + 手写条目；"Found N tests" 不产；终局 M passed 因 finish 重置小于 found），与 037/038/039/退场声明一致。
- **D（fixed）**：spec §9.5 与 `src/module.jai` Testing banner 的 API 列表改为 `expect`/`expect_eq`/`fail`/`run`/`finish`/`path_mapping`（旧稿 `assert` 标注为概念名，实际面无同名符号）；`tests/module_tests.jai` 同处注释同步。

**复查验证矩阵**（2026-10-20/21，串行；各路径先清 `target/transpile`/`target/testing-module`）：

| 项 | 结果 | 证据 |
| --- | --- | --- |
| `jai build.jai`（debug） | exit 0；`[Version Assert] ✅`；四件 131/237/12/285 行；第四件与 `src/test_discovery.jai` 逐字节相等；平铺种子零残留 | `target/audit-review-fixes-bootstrap-debug.txt`、`target/audit-review-fixes-artifacts-debug.txt` |
| 副本 `target/juice-copy.exe test` | exit 0；**SKIP 0**；455 顶层条目（max `juice_test_N` 450 + 手写 5）；**269 passed / 0 failed**；白名单恰 6 行且坐标不变（`src/module.jai:354/380`、`tests/module_tests.jai:182/187/211/216`）；字面 447/448（副本跑形状，符合修正后叙事） | `target/audit-review-fixes-copy-test.txt`、`target/audit-review-fixes-copy-test-analysis.txt` |
| `jai build.jai - release` | exit 0；`Release build succeeded!`；四件 131/237/12/285 行；第四件与 `src/test_discovery.jai` 逐字节相等；平铺种子零残留；exe sha256 `573bc0e57b9b06ea842684d7e1d585f43c4f839377b7f31645a5724c42d8141b`（590848 bytes） | `target/audit-review-fixes-release-bootstrap.txt`、`target/audit-review-fixes-release-artifacts.txt` |
| 副本 `target/juice-copy.exe test`（release 产物） | exit 0；**SKIP 0**；455 顶层条目（max `juice_test_N` 450 + 手写 5）；**269 passed / 0 failed**；白名单恰 6 行且坐标不变（`src/module.jai:354/380`、`tests/module_tests.jai:182/187/211/216`）；字面 447/448 | `target/audit-review-fixes-release-copy-test.txt`、`target/audit-review-fixes-release-copy-test-analysis.txt` |
| 六命令冒烟（带身份头） | `version`/`help`/`build`/`test`/`run`/`clean` 各 exit 0；version = `juice 0.1.0` + `jai 0.2.9`；test-blocks 4 passed；run 输出 `hello from run-fixture`；clean 删除根与两成员 `target/`；exe = `<otter>/target/juice.exe`，sha256 `4d4d968fee63add120931683cbc6a2b02f74aae409a62b23dda01bed37af96d6`，590848 bytes | `target/audit-review-fixes-six-command-smoke.txt` |

**有意变更/钉**：

1. `tests/bootstrap_tests.jai` SKIP 字符串与注释（Finding 2；唯一测试运行行为面改动，仅诊断文本）。
2. `tests/publication_tests.jai` `EXPECTED_TESTING_MODULE_LINES` 的 Testing banner 文本（随 `src/module.jai` 注释更新；行数不变，发布物仍 237 行）。
3. `tests/module_tests.jai` 两处注释同步（现在时 + API 列表）；注释重排保持文件行数 509 不变，白名单视图坐标保持 182/187/211/216。
4. docs/记忆面：spec §0/§6.3/§9.2/§9.5；006 决定 3/4/11/15、Testing Decisions、Out of Scope、Resolution；039 计数约定+矩阵；退场声明 §3/§4/§6；map Not yet specified；035/036 簿记；记忆 `otter-suite-count-convention`。

**边界**：生产行为零改动（`src/` 改动仅注释，`build.jai` 仅注释；`package.jai` 零改动）；旧 juice 仓未运行、未修改（仅只读核对 Testing API 符号名，非验证依赖）；本票状态保持 closed；006/map 状态未改。
