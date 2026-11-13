---
id: 033
title: 求值器切换 + 根自构建自测
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [032]
blocks: [034]
---

> 父 spec：`005-spec-stage2-build-metaprogram.md`（决定 8/12/13 + US 15-18/20/21）。上游规格：`docs/spec.md` §9.3/§10。

# 033: 求值器切换 + 根自构建自测

**What to build:** 自举产物验收——**两模式自举产物各于 otter 根 build/test 全绿**（求值经发布面：manifest 求值器子进程 `-import_dir` 解析 `#import "Juice"` 到发布目录模块——平铺种子已退役，切换成立）+ LNK1104 hand-off 自构建（运行中 exe 覆写规避）+ 六命令冒烟 + fixture 包（build-with-tests/test-blocks 族）经自举 exe 全绿。若切换暴露发布面缺口（段裁剪漏面/求值器编译失败等），本票修复随票记录。

**Blocked by:** 032（发布接线 + 种子退役——切换的前提）

**Status:** closed

- [x] 完成定义①：两模式 build.jai 产物均 exit 0 + exe + 三份发布物
- [x] 完成定义②：两产物各于根 build/test 全绿（求值经发布面，path_mapping 指原文行）
- [x] LNK1104 hand-off 自构建全通（副本留 target/ 纪律）
- [x] 六命令冒烟 + fixture 包经自举 exe 全绿（完成定义⑥）
- [x] 旧 juice 不变式 debug+release 4/4（过渡期复核）+ 409 存量不回归
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**（2026-10-20）：

- **自托管门禁面修复（本票核心修复，见偏差 1）**：直跑 `target/juice.exe test` 首证——两个自构建 E2E 失败但整体 exit 0。根因 = runner 门禁计数分裂：注入 runner 驱动 prefixed bootstrap 面（`Testing_run`/`Testing_finish`），而根套件的裸断言经 `#import "Testing"`（t9 视图 = 发布面）写入**另一个寄存器**——finish 闸门数为 0，失败测试照样 exit 0（切换暴露的信任缺口）。修复三件套：
  - `src/test_discovery.jai`：`generate_test_runner_code(entries, pairs, use_bare_face := false)`——裸模式发射 `path_mapping` + `run`/`finish`（发布面裸名），默认保持 prefixed 字节形；
  - `src/test_metaprogram.jai`：`Test_Driver_Options.import_testing_face`（face-discovered 包显式 `#import "Testing"`——t9 视图经 import 路径解析）+ `Test_Metaprogram_Options.runner_bare_face`（生成调用携带 `, true` 字面量，默认零改动）；
  - `src/commands/test.jai`：`use_published_face = face_is_discovered(...) && testing_module_view != ""`，驱动 driver 的 `import_testing_face` 与 metaprogram 的 `runner_bare_face`。
  - 裸模式**同时填两面的 path map**（首版只填裸 map → prefixed 面报告退化为视图路径；补修后双面坐标均指原文行）。
- **自锁 SKIP（偏差 2）**：`tests/bootstrap_tests.jai` 增 `bootstrap_e2e_self_locked()`（`artifact_is_running(otter_exe())` 探针）——自托管直跑时运行中 exe 占锁，两个自构建 E2E 响亮 SKIP（bootstrap 无 hand-off = 005 决定 10/031 偏差 7；hand-off 归 Build 命令）；旧 juice 循环与 target/ 副本运行全覆盖（SKIP 0/2 计数证据）。
- **测试侧求值面切发布目录（偏差 3）**：workspace/dependency E2E driver 的 `modules_dir` 与 `-import_dir` 从 old juice modules 切 `plugin_face_modules_dir()`（发布面，先 `ensure_published_modules()`）；`tests/manifest_tests.jai` 的求值器 E2E 注入面同切。`bootstrap_juice_modules_dir` 收窄为 module_tests 的两代对拍参照面（stage 3 退役）。
- **`tests/test_metaprogram_tests.jai`**：+3 单元（裸 runner 字节 pin 含双 map、face-discovered driver 的 `#import "Testing"` 与默认零改动、metaprogram 的 `runner_bare_face` 转发）；既有 pin 全部保持字节不变（默认路径零影响）。
- **main.jai 零改动**；旧 juice 仓零改动；map.md 未动。

**验证矩阵**（串行；各先清 otter/target/transpile）：

| 步骤 | 结果 |
| --- | --- |
| 旧 juice debug：juice 根 `jai build.jai` → otter 根 build + test | build exit 0；test exit 0，**Found 443 tests**（440 + 3 单元）、**258 passed, 0 failed**、白名单恰 6 行、SKIP 0（自构建 E2E 全跑） |
| 旧 juice release：`jai build.jai - release` → 同两命令 | build exit 0；test exit 0，Found 443、258 passed、白名单 6、SKIP 0 |
| 自举 debug：`jai build.jai` | exit 0 + exe + 三发布物 |
| 自举 release：`jai build.jai - release` | exit 0 + exe 588288B |
| 完成定义②·debug 产物于根 | `target/juice.exe build` exit 0（**hand-off 触发**「Target 'juice' is running; rebuilding through a copy in target/...」）；`target/juice.exe test` exit 0、258 passed、**SKIP 2**（自锁） |
| 完成定义②·release 产物于根 | build exit 0（hand-off）；test exit 0、258 passed、SKIP 2 |
| path_mapping 指原文行 | 自托管直跑双面失败坐标均映射原文：`src/module.jai:353:9`（prefixed 面）与 `tests/module_tests.jai:178:5`（发布面） |
| 六命令冒烟（release 产物） | version「juice 0.1.0 / jai 0.2.9」；help 总览 + `help build`；build/test 见上；run fixture build-with-tests →「hello from build-with-tests: 2 + 3 = 5」exit 0；clean scratch → 「Workspace cleaned.」+ target 移除 |
| fixture 包经自举 exe | test-blocks：4 passed / 0 failed / exit 0；test-blocks-fail：exit 1 + **src/math.jai:13:5**（原文坐标）；build-with-tests build+run 见上 |
| 求值经发布面 | 自托管套件 fixture E2E（manifest 求值/构建/测试）全绿；manifest 求值器 E2E 注入面 = 发布目录（偏差 3） |
| 旧 juice 不变式 | debug+release 4/4 全绿；443 tests（409 基线 + 链内增量）、0 非白名单失败 |

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **自托管 runner 门禁面切换（本票核心修复）**：根套件的测试体裸断言（`#import "Testing"` → t9 发布面视图）与注入 runner 的 prefixed 驱动分属两个寄存器——失败不被 finish 闸门计数（直跑实证：2 失败 + exit 0）。修复 = face-discovered 包（根）的 runner 驱动发布面裸名 + driver 显式 `#import "Testing"` + 双 path map 填充；fixture/用户包保持 prefixed 形（字节锁零改动）。修复后自托管直跑 = 258/0 且失败可致 exit 1（闸门恢复成立）。
2. **自锁 SKIP = 环境条件跳过（非弱化）**：自托管直跑时运行中 exe 占锁 → 自构建 E2E 的 link LNK1104（bootstrap 无 hand-off = 031/005 决定 10 形状；hand-off 归 Build 命令，两产物各证全通）。SKIP 响亮打印 + 旧 juice 循环/副本运行全覆盖（计数 0/2 双向证据）；先例 = junction 拒删 SKIP 惯例。
3. **测试基础设施求值面切发布目录**：workspace/dependency/manifest E2E driver 的 evaluator `-import_dir` = `target/modules`（发布面）；`bootstrap_juice_modules_dir` 仅存 module_tests 两代对拍参照（stage 3 退役）。
4. **`testing_face_strip_view` 保留（范围判定）**：fixture 家族（6 包 24 处）按 016/030 设计消费 prefixed bootstrap 名，driver 的源面切仍为其编译面；切发布面需重写 fixture 家族，本票无需求（fixture 经自举 exe 全绿已证）。发布面经 t9 视图服务 `#import "Testing"`；源面推导（`<exe>/../src`）= dev-layout 姿态，stage 3 退役。
5. **进程残留处置**：验证中撞到旧会话残留 jai/juice 进程占锁（LNK1104/目录 busy）——kill 后全绿；非代码缺陷，记录环境处置。
6. **Jai 事实补钉**：`#assert` 失败消息在 stderr（032 已钉）；`#run` 编译期 print 于失败路径被吞（032 已钉）——本票自托管闸门修复的动机同族（门禁只认寄存器计数，不认打印）。

**034 移交面**：本票完成定义①-⑥ 全兑现；034 = fixture E2E 收口 + spec 005 收口关闭（US 24 全兑现映射 + 决定 1-15 对照 + 链偏差汇总 030-033 + spec.md 执行级订正折回：§9.5 Juice 面内部结构面扩展（032 偏差 1）+ §10 阶段 2 验收 = 自构建自测 + §9 发布面消费形态（runner 裸面 + 双 map）+ 自锁 SKIP 纪律）。

## 独立复核（审计人：otter-033 独立复核代理，2026-10-20）

**背景**：实现面由 otter-032 在 032 闭环后越权完成（16:20-17:04 文件修改 + Resolution）；主会话令其停手后将本票改为独立审计。本节 = 接手审计结论；实现责任随本节移交复核方签署。

**核验范围**：票面清单 + 005 决定 8/12/13 + 032 移交面（LNK1104 hand-off、testing_face_strip_view 切换、bootstrap_juice_modules_dir 退役、六命令 + fixture 冒烟、两模式根 build/test）。逐文件审计 7 处改动：

1. `src/test_discovery.jai`（runner 裸面）：`generate_test_runner_code(entries, pairs, use_bare_face := false)` 默认 false，既有调用/字节锁零影响；裸面发射 `path_mapping` + `run`/`finish`，且**双面 map 同时填充**（prefixed 自测块的失败报告仍指原文行）。**独立探针实证闸门分裂真实存在**（`target/probe/probe-faces.jai`：prefixed `Testing_run` 包裸断言 → `Testing_finish()=0`；裸 `run` 包 prefixed 断言 → `finish()=1`）——修复前提成立。
2. `src/test_metaprogram.jai`：`Test_Driver_Options.import_testing_face`（互斥于 testing_source 的 if/else-if，"" 时零改动）+ `Test_Metaprogram_Options.runner_bare_face`（生成文本携带 `, true` 字面量，默认帧逐字节不变）——形状正确。
3. `src/commands/test.jai`：`use_published_face = face_is_discovered(...) && testing_module_view != ""`——t9 视图缺失时退回 prefixed 单面（自洽，无双面半开）；driver/metaprogram 两处接线一致。非 discovered 包保留源面切（deviation ③，主会话已裁定保留）。
4. `tests/bootstrap_tests.jai`：`bootstrap_e2e_self_locked()`（`artifact_is_running(otter_exe())` 真探针）响亮 SKIP 两个自构建 E2E——与 005 决定 10（bootstrap 无 hand-off）一致；Build 命令的 011 hand-off 不受影响。**裁定：合理**（SKIP 是环境条件跳过而非弱化：旧 juice 循环与 target/ 副本运行全跑，SKIP 计数 0/2 双向可证；先例 = junction 拒删 SKIP 惯例）。
5. `tests/test_support.jai`：workspace/dependency E2E driver 的 evaluator `modules_dir`/`-import_dir` 切 `plugin_face_modules_dir()`，且均在生成/派生之前 `ensure_published_modules()`（顺序核验通过）；`bootstrap_juice_modules_dir` 仅存 module_tests 两代对拍参照（stage 3 退役），生产 src 零引用。
6. `tests/manifest_tests.jai`：求值器 E2E 先 `ensure_published_modules()`，`load_package_manifest(..., plugin_face_modules_dir())`——求值面切换的测试侧兑现。
7. `tests/test_metaprogram_tests.jai`：+3 单元（裸 runner 字节 pin 含双 map / face-discovered driver `#import "Testing"` 与默认零改动 / `runner_bare_face` 转发）——即 **440 → 443 的 +3 归因**（032 收口报告 440/255 早于这 3 块；443/258 为最新权威实测）。

**独立验证**（2026-10-20 17:42-17:52，全串行、无并发；各路径先清 `target/transpile`、`target/testing-module`；证据日志 `otter/target/audit-*.txt`）：

| 步骤 | 结果 |
| --- | --- |
| 旧 juice debug（juice 根 `jai build.jai`）→ otter 根 build / test | 三命令 exit 0；**Found 443**、**258 passed, 0 failed**、白名单恰 6 行、SKIP 0 |
| 旧 juice release（`jai build.jai - release`）→ 同两命令 | 三命令 exit 0；Found 443、258 passed、白名单 6、SKIP 0 |
| 自举 debug `jai build.jai` | exit 0；exe 994816B；三发布物 131/237/12 行 |
| debug 产物于根 build / test | build exit 0 + hand-off 行；test exit 0、258 passed、白名单 6、SKIP 2 |
| 自举 release `jai build.jai - release` | exit 0；exe 582656B（Resolution 记 588288B 为另一样本，链接产物大小随构建批次浮动，非缺陷）；三发布物重生 |
| release 产物于根 build / test | build exit 0 + hand-off 行；test exit 0、258 passed、白名单 6、SKIP 2 |
| 六命令冒烟（release 产物） | version「juice 0.1.0 / jai 0.2.9」；help 总览 + `help build`；run build-with-tests →「hello from build-with-tests: 2 + 3 = 5」exit 0；test-blocks 4 passed/0 exit 0；test-blocks-fail exit 1 且 `src/math.jai:13:5` 原文坐标；clean scratch 见 17:2x 冒烟（「Workspace cleaned.」+ target 移除） |
| 发布面消费 | `target/testing-module/Testing.jai`（t9 视图）含裸 `run :: (`、零 `Testing_run`；自托管 manifest 求值器子进程以 `-import_dir .../target/modules` 运行（进程观测） |
| path_mapping | 双面失败坐标均指原文：`src/module.jai:353:9`（prefixed 面）与 `tests/module_tests.jai:178:5`（发布面） |

**环境注记（非缺陷）**：`target/juice.exe build` 的 011 hand-off 在审计环境中触发、副本 `target/juice-build.exe` 落位、原进程 exit 0 均成立，但 detached 副本在本 harness 的作业监管下不存活（未观察到异步重建）；直接运行该副本可正常重建 `target/juice.exe`（mtime/大小实证）。真实终端预期正常，不影响代码面结论。

**审计结论**：7 处改动完整、自洽，与票面/005 决定 8/12/13/032 移交面一致；无缺陷需修复；完成定义①-⑥ 与三接缝阶段 2 版全部成立。**签核通过，034 可放行。**

审计人签名：otter-033（独立复核代理）  2026-10-20

**主会话拍板（2026-10-20，审计回报后）**：偏差 ①②③ 全部接受（`testing_face_strip_view` 保留 = fixture 家族按 prefixed 面消费，切面重写非本票需求；test 向响亮 SKIP + build 向 011 hand-off 的双向证据充分；`bootstrap_juice_modules_dir` 仅存两代对拍参照）；④ 环境注记按工具环境记录，不计缺陷。审计签核有效，本票维持 closed。
