---
id: 035
title: 裸名门禁修复 + 全面裸面
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [036]
---

> 父 spec：`006-spec-stage3-bootstrap-closeout.md`（决定 2/3/14；接缝 2/3）。上游规格：`docs/spec.md` §7.1/§7.2/§7.5。

# 035: 裸名门禁修复 + 全面裸面

**What to build:** 一个按老 juice 写法写的普通用户包（`#import "Testing"` + 裸 `expect`）经产物 exe `juice test`：失败断言进入汇总、报告、exit 1；通过包 exit 0。所有测试程序（根包、fixture、用户包）统一消费发布 Testing 面，注入 runner 一律驱动裸名；prefixed 源面加载路径与 test 命令消费的 fixture 族 prefixed 调用退役。

**Blocked by:** None (can start immediately)

**Status:** closed

- [x] 裸名失败用户包 E2E：`expect failed` 计入汇总（不再是 0 failed）、exit 1、失败坐标指原文行；裸名通过包 exit 0、计数正确。
- [x] 测试 driver 对所有包一律 `#import "Testing"`（t9 发布编译视图）；注入 runner 一律裸名 `run`/`finish`/`path_mapping`。
- [x] `testing_source` 显式源面加载、`face_is_discovered` 面选择、`import_testing_face`/`runner_bare_face` 双形态收敛为单一形态。
- [x] `testing_face_source` 与 `testing_face_strip_view` 从生产面删除；Testing 面不再依赖 `<exe>/../src`。
- [x] test 命令消费的 fixture 族（test-blocks / test-blocks-fail / test-fail / test-fixture / test-dep 族等，11 文件 24 处调用——15 处迁移为裸名 + 9 处删除 prefixed 腿；原 26 行 grep 含 2 行注释/定义）迁移为裸名；fixture 经产物 exe 全绿。
- [x] in-package Testing 模块自测（EXPAND 编译视图）继续工作；预期失败白名单保持 6 行。
- [x] 根套件 debug/release 全绿；driver/metaprogram 字节锁按单一形态有意更新并随票记录。

## Resolution

**实现摘要**（2026-10-20）：单一断言寄存器落地——发布 Testing 面成为所有测试程序的唯一消费面：driver 一律 `#import "Testing"`（t9 编译视图在 import 路径上解析），注入 runner 一律裸名 `run`/`finish`/`path_mapping`；prefixed 源面加载路径（`testing_face_source` / `testing_face_strip_view` / `face_is_discovered`）与 `testing_source` / `import_testing_face` / `runner_bare_face` 双形态全部退役；test 命令消费的 fixture 族迁移为裸名。裸名失败用户包门禁修复实证：`expect failed` 计入汇总、exit 1、坐标指原文行。

**生产面改动**：

- `src/commands/test.jai`：删除 `testing_face_source` / `testing_face_strip_view` / `face_is_discovered`；`test_compile_front` 只生成单一 driver/metaprogram 形态；`bootstrap_src_dir` 仅剩 `discovery_face_source` 一个消费方（票 037 按决定 4 退役 `<exe>/../src` 推导）。
- `src/test_metaprogram.jai`：`Test_Driver_Options` 删 `testing_source` / `import_testing_face`，driver 恒发射 `#import "Testing";`；`Test_Metaprogram_Options` 删 `runner_bare_face`。
- `src/test_discovery.jai`：`generate_test_runner_code` 删 `use_bare_face`，恒发射裸名单面 runner（只填 `path_mapping`）。

**测试面改动**：

- `tests/test_metaprogram_tests.jai`：driver 字节锁更新（`#load` 源面 → `#import "Testing"`）；runner 字节锁更新为裸名单面形；033 的三个双形态测试收敛为单一形态测试。
- `tests/test_transpile_tests.jai`：driver 面断言改 `#import "Testing"`；`face_is_discovered` 测试改写为「driver 恒导入发布面」；scratch 包体裸名化；in-package 模块 E2E 的 scratch `modules/Testing.jai` 补齐裸面 API（driver 现在导入包内模块作为唯一面）。
- `tests/test_support.jai`：`run_test_program_child` 改用发布面 + 生产 STRIP 视图助手（`testing_module_strip_view_dir`）。
- `tests/test_command_tests.jai`：+2 E2E（裸名失败包 / 裸名通过包）。
- fixture（8 文件）：test-blocks（greet/math）、test-blocks-fail/math、test-fail/failing、test-fixture（tests_a/tests_b）、test-dep-root/main、test-dep-lib/extra 迁移为裸名 `expect`/`expect_eq`/`fail`（15 处调用 + 注释同步；与 036 的 testing-face 3 文件 9 处合计 11 文件 24 处调用——原 26 行 grep 含 2 行注释/定义）。

**验证矩阵**（2026-10-20，串行；各先清 `target/transpile`/`target/testing-module`；证据 `otter/target/audit-035-*.txt`）：

| 路径 | 结果 |
| --- | --- |
| 旧 juice debug（juice 根 `jai build.jai` → otter 根 build/test） | 3 命令 exit 0；**Found 443**、258 passed / 0 failed、白名单恰 6 行、SKIP 0；两个新 E2E 逐名可见 |
| 旧 juice release（`jai build.jai - release` → 同两命令） | 3 命令 exit 0；Found 443、258 passed / 0 failed、白名单 6、SKIP 0 |
| 自托管 debug（`jai build.jai` → 产物 `build`/`test`） | bootstrap exit 0；产物 build exit 0（011 hand-off 副本接管）；test exit 0、258 passed、白名单 6、自锁 SKIP 2 |
| 自托管 release（`jai build.jai - release` → 同两命令） | bootstrap exit 0；产物 build exit 0（hand-off）；test exit 0、258 passed、白名单 6、SKIP 2 |
| 副本跑（`target/juice-copy.exe test`） | exit 0、258 passed、白名单 6、**SKIP 0** |
| fixture CLI 冒烟（产物 exe 直跑） | test-blocks 4/0 exit 0；test-blocks-fail exit 1 + `src/math.jai:13:5`；test-fail exit 1 + `src/failing.jai:16:5`；test-fixture 5/0 exit 0；test-dep-root 1/0 exit 0；test-empty「No tests found」exit 0 |
| 裸名门禁 E2E（套件内 + 直跑复现） | 失败包：`src/main.jai:5:5: expect failed`、`1 passed, 1 failed`、exit 1；通过包：`2 passed, 0 failed`、exit 0 |

**字节锁**（有意更新）：driver 锁改为 `#import "Testing"`；runner 锁改为裸名单面形（`run`/`finish`/`path_mapping`）；metaprogram 锁**不变**——被删的 `runner_bare_face` 默认值即旧发射文本，单一形态后文本逐字节相同。

**偏差清单**（全有意，无遗留缺陷）：

1. **白名单坐标 4 行改为视图路径**：单一形态 runner 不再填充 prefixed 面的 `Testing_path_mapping`（普通用户包没有该声明），根包 `src/module.jai` 自测 2 行与 `tests/module_tests.jai` prefixed 面 2 行改打印视图路径；bare 面 2 行仍映射原文行。白名单**计数**仍恰 6 行（决定 2「prefixed 自测块属定义源内部面，不参与外层 runner 门禁」的直接后果）。
2. **套件计数持平 443**：+2 新 E2E 与 -2 双形态退役单测（3 删 1 并）相抵；字节契约覆盖以单一形态保留。
3. **fixture 迁移面 = 8 文件（15 处调用）**：spec 006 决定 3 的「11 文件、24 处调用（15 处迁移为裸名 + 9 处删除 prefixed 腿；原 26 行 grep 含 2 行注释/定义）」含 `testing-face/*` 三文件（9 处 prefixed 调用）；它们是 `module_tests` 的两代对拍 harness，归票 036「旧 juice 两代对拍退役」处置，本票不动、套件保持绿。
4. **in-package 模块 E2E fixture 补齐裸面 API**：driver 现在导入包内 `modules/Testing.jai` 作为唯一面，scratch 模块补 `run`/`finish`/`path_mapping`/`expect_eq`（旧 fixture 仅声明 `module_decl`，靠被退役的 prefixed 源面补其余声明）。
5. **`bootstrap_src_dir` 保留一个消费方**：仅 `discovery_face_source` 使用（票 037 按决定 4 切 `<modules_dir>/juice_internal/` 并删除）；Testing 面已零引用 `<exe>/../src`。
6. **门禁 E2E 用临时包而非静态 fixture**：按 spec 006 Testing Decisions 的「临时 BIN 包」形态，scratch 根落 `target/`，E2E 自带清理。

**边界/落盘**：`main.jai`、`package.jai` 零改动；旧 juice 源零改动（仅不变式循环的 `jai build.jai` 构建产物 `target/` 更新，`git status` 干净）；`testing-face/*` fixture 与 `bootstrap_juice_modules_dir` 按拆分留票 036；`<exe>/../src` 的发现面推导留票 037。map.md 与父 spec 006 不动（map 行归主会话，006 由 039 收口）。

