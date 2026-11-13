---
id: 036
title: 旧 juice 两代对拍退役 + 机械退场守卫
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [035]
blocks: [037]
---

> 父 spec：`006-spec-stage3-bootstrap-closeout.md`（决定 3/9/13；接缝 2）。上游规格：`docs/spec.md` §7.5/§10。

# 036: 旧 juice 两代对拍退役 + 机械退场守卫

**What to build:** 测试套件不再读取兄弟旧 juice 仓。旧仓两代 Testing 面对拍退役，`testing-face` 场景改为发布裸面单面驱动并保留原行为覆盖（abort/eq/named/mapped 与原文行映射）。新增机械守卫：源码、测试、build 与 package 文件出现旧仓路径引用即失败。

**Blocked by:** 035（裸面终态先成立，单面对拍与守卫才有意义）

**Status:** closed

- [x] `bootstrap_juice_modules_dir` 与两代对拍腿删除；套件内零旧仓路径引用（`../juice` / `juice/modules` 形态）。
- [x] `testing-face` pass/fail/mapped 场景改为发布裸面单面驱动，保留失败/中止/eq/命名失败/映射坐标的行为面。
- [x] 机械退场守卫测试：扫描源码/测试/build/package 文件，命中旧仓路径即失败；`docs/research` 历史引用豁免；守卫自身针字符串不误报。
- [x] 根套件 debug/release 全绿；白名单 6 行不变；旧 juice 仓零改动。

## Resolution

**实现摘要**（2026-10-20）：旧 juice 仓从测试套件彻底退场。`bootstrap_juice_modules_dir` 与两代 Testing 面对拍腿删除（`testing_module_strip_view` / `src_module_strip_view` 两个只服务旧仓读取的切文助手一并退役，无残留消费方）；`testing-face` pass/fail/mapped 三场景改为**发布裸面单面驱动**——生成 driver = `#import "Testing"`（解析到发布面 STRIP 编译视图，生产 t9 助手）+ `#load` fixture + 注入 `path_mapping`，行为面全保留（abort 语义、eq 失败、命名失败、格式化消息、custom eq 消息、映射坐标、原文行映射）。新增机械退场守卫 `tests/retirement_guard_tests.jai`（4 测试）：扫描 `src/` + `tests/` 全部 `.jai` + 根 `build.jai`/`package.jai` 的四形态旧仓路径（正/反斜杠 × `../juice` / `juice/modules`），命中即失败并打印 `path:line:col` 证据；`docs/research` 不在扫描根（历史引用豁免，并有活证测试）；守卫针字符串分段构造，自身零误报。

**测试面改动**：

- `tests/test_support.jai`：删 `bootstrap_juice_modules_dir`（兄弟仓路径唯一来源）与 `src_module_strip_view`（无消费方）。
- `tests/module_tests.jai`：删 `testing_module_strip_view`；`Face_Scenario_Entry` 收敛为 `{name, proc}` 单面形；driver 生成器删双面发射（prefixed #load 腿 + `Testing_*` 调用腿）；`run_testing_face_child` 改 `ensure_published_modules()` + `testing_module_strip_view_dir(cache, 发布 Testing.jai)` + 每跑先整删 cache（旧 harness 遗留文件不可能阴影当前面）；in-process 双面对拍保留但更名 `definition_*` / `imported_*`（配 `g_definition_*` / `g_imported_*`），测试名改「definition source vs imported face」；pass/fail/mapped 期望改为单节输出。
- `tests/data/testing-face/{pass,fail,mapped}/src/scenarios.jai`：删除 prefixed 腿 9 处调用（与 035 的 8 文件 15 处合计 11 文件 24 处调用；原 26 行 grep 含 2 行注释/定义），fixture 只剩裸名 bodies（真实老 juice 用户包形态）。
- `tests/retirement_guard_tests.jai`：新增（匹配器单元 + 自身零误报 + 全树扫描 + `docs/research` 豁免活证）。

**生产面改动**：仅 `src/module.jai` 头注释一处——`juice/modules/Juice.jai:97-118` 字面改为「its Juice.jai declaration block, lines 97-118」，使机械守卫扫描范围内零旧仓路径；生产行为零改动（注释在发布段标记之前，发布产物逐字节不变）。

**白名单处置**（035 偏差 1 的 4 视图路径行）：**决策 = 全部保留视图路径，不恢复映射**。理由三层：

1. 4 行中 `tests/module_tests.jai` prefixed 面 2 行（现行 :182/:211）与 `src/module.jai` 自测 2 行（现行 :354/:380）都属定义源内部面（prefixed 公开名）。父 spec 006 决定 3 明确「prefixed 名...其单元测试保留」，决定 2 明确该内部面不参与外层 runner 门禁——保留即白名单现状。
2. 恢复映射要求外层 runner 向 prefixed 内部表 `Testing_path_mapping` 注入条目，而该声明只存在于定义源所在包（普通用户包没有）；035 正是因普通用户包无此声明而退役双表填充 / face-discovery 双形态。重引入 = 回退单一寄存器决定。
3. 单面裸面 2 行（:187/:216）继续经发布面 `path_mapping` 映射原文行（`tests/module_tests.jai:L:C`）。白名单计数恰 6 行不变。

**验证矩阵**（2026-10-20，串行；各先清 `target/transpile`/`target/testing-module`；证据 `otter/target/audit-036-*.txt`）：

| 路径 | 结果 |
| --- | --- |
| 旧 juice debug（juice 根 `jai build.jai` → otter 根 build/test） | 3 命令 exit 0；**Found 447**、262 passed / 0 failed、白名单恰 6 行、0 SKIP |
| 旧 juice release（`jai build.jai - release` → 同两命令） | 3 命令 exit 0；Found 447、262 passed / 0 failed、白名单 6 |
| 自托管 debug（`jai build.jai` → 产物 `build`/`test`） | bootstrap exit 0；产物 build exit 0（LNK1104 hand-off）；test exit 0、262 passed、白名单 6、**SKIP 2**（自锁 = 环境条件形态） |
| 自托管 release（`jai build.jai - release` → 同两命令） | bootstrap exit 0；产物 build exit 0（hand-off）；test exit 0、262 passed、白名单 6、SKIP 2 |
| 副本跑（`target/juice-copy.exe test`） | exit 0、262 passed、白名单 6、**SKIP 0**（权威验收） |
| 守卫负向探针（`tests/data/` 临时植入含旧仓路径的文件 → 直跑 test） | **exit 1**；`[retirement guard] …/retirement-guard-probe.jai:1:32: ../juice`；探针删除后复跑全绿 |
| 子场景直跑（`target/testing-face-e2e-cache/{fail,mapped}/driver.exe`） | fail：5 失败逐条映射 `src/scenarios.jai:L:C`（abort/eq/named/格式化/custom eq）+ `0 passed, 5 failed`；mapped：`src/scenarios.jai:9:5`、视图路径零泄漏 |

**计数**：443 found / 258 passed 基线 → **+4 守卫测试 = 447 found / 262 passed**；in-process 对拍与子场景测试数量不变（更名/单面化不动计数）；白名单 6 行不变。032 起的白名单行号漂移属编辑位移（6 行组成不变）。

**偏差清单**（全有意，无遗留缺陷）：

1. **in-process 双面对拍保留（仅更名）**：父 spec 006 决定 3「prefixed 名的单元测试保留」；本票退役面 = 兄弟仓文件读取 + 子场景双面对拍。这也是白名单 6 行的直接前提（删 prefixed 腿会降到 4 行）。
2. **子场景 driver 的 `finish()` 返回值不触发 exit 1**（与旧 harness 同形）：父测试断言输出契约（起行/坐标/汇总）；实包退出码门禁由 035 裸名 E2E 承担。
3. **子场景 cache 每跑整删**：旧 harness 遗留的 `Testing.jai`/`module.jai` 不再可能阴影当前 import 面（实证：删除遗留文件后仅视图目录在 import 面仍编译绿）。
4. **`src/module.jai` 头注释改写**：机械守卫扫描范围内零旧仓路径字面；历史锚点语义（声明块行号）保留，生产行为零改动。
5. **守卫四形态超出票面两形**（正/反斜杠 × 两路径形）：覆盖 Windows 字面/注释现实形态；near-miss（`../other`、`juice/core`）负向单元测试钉不误报。

**边界/落盘**：`main.jai`、`build.jai`、`package.jai` 零改动；生产代码除 `src/module.jai` 注释外零改动；旧 juice 仓源零改动（仅不变式循环 `jai build.jai` 产物 `target/` 更新）；`docs/research` 历史引用保留（豁免活证：research 文件命中 > 0 且不在扫描根）。map.md 与父 spec 006 不动（map 行归主会话，006 由 039 收口）。**037 移交**：发现面第四件发布 + `<exe>/../src` 退役（不受本票影响）。
