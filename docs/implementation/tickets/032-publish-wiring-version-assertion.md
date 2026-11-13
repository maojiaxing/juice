---
id: 032
title: 发布接线 + 版本断言 + 种子退役
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [030, 031]
blocks: [033]
---

> 父 spec：`005-spec-stage2-build-metaprogram.md`（决定 4/9/11 + US 9/10/22）。上游规格：`docs/spec.md` §9.4/§10。

# 032: 发布接线 + 版本断言 + 种子退役

**What to build:** build.jai 发布步骤接线——**先发布后编译**（发布转换模块产出三份落 target/modules/，Testing 特例源从种子切发布面）；**版本断言**（spawn 求值器子进程读 otter/package.jai 的 VERSION 协议记录，对照 JUICE_VERSION 硬编码常量，不等 = 响亮失败 exit 1——执行形状 = mini-driver 或复用求值器面，票内钉）；**种子退役**（ensure_bootstrap_modules 的 Juice.jai/Testing.jai 种子与 juice_core stand-in 退场，发布产物接管——平铺 Juice.jai 退役即目录模块接手，C§7.4 E6 歧义规避）。

**Blocked by:** 030（发布转换面）、031（build.jai 宿主）

**Status:** closed

- [x] 三份发布物随 build.jai 每跑重生（先发布后编译序钉死）
- [x] Testing 特例源切发布面（含自测 test 块 STRIP 消费）
- [x] 版本断言两向（声明 == 常量绿 / 不等 = 响亮失败 exit 1）
- [x] 种子退役（三件退场、无残留、发布产物接管）
- [x] E2E（真 jai 跑 build.jai 两模式 + 发布物逐字节 + 断言触发面）+ 旧 juice 不变式 4/4 + 409 存量不回归
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**（2026-10-20）：

- **`build.jai` 发布接线（先发布后编译）**：#load 名单追加 `src/publication.jai`（头注释契约同步）；#run 新序 = 参数 → workspace → **发布** → **版本断言** → 剥离前端 → Testing 特例 → 编译（步骤注释重编号）。发布步 = 读 `src/module.jai` → `publish_juice_module` / `publish_testing_module` / `publish_juice_core` → 落 `target/modules/{Juice/module.jai, Testing.jai, juice_core.jai}`（每跑重生，失败 print + exit 1）；随后**平铺 `target/modules/Juice.jai` 种子退役**（存在即删，删除失败 exit 1——目录模块接手，无平铺/目录歧义，005 US 14）。Testing 特例源同路径切发布面（`target/modules/Testing.jai` 内容 = 发布平铺面、含自测块，STRIP 特例持续触发；031 的种子消费零代码改动、仅注释换面）。
- **版本断言（编译期 #assert 形状，票内钉）**：`src/metaprogram.jai` 新增纯函数 `generate_version_assertion_driver(package_path, juice_version_line)`——007 求值器 driver 同款形状（`#import Basic/Compiler/Juice` + `#load` 绝对路径 package.jai + `#run { set_build_options_dc(.{do_output=false}); main(); }`）+ **JUICE_VERSION 声明行逐字嵌入**（自 `src/commands/version.jai` 经 030 的 `extract_constant_line` 抽取——单源保真，published juice_core 纪律）+ **`#assert PACKAGE.version == JUICE_VERSION "…versions drifted; update one.";`**（编译期常量比较）。build.jai spawn `jai target/bootstrap-version-check.jai -import_dir target/modules -quiet`；非零退出透传 exit 1。成功路径 main 打印 `[Version Assert] ✅ package.jai VERSION % == JUICE_VERSION.`。
- **种子退役（test_support）**：`ensure_bootstrap_modules`（旧 juice 种子复制）**删除**，替为 `ensure_published_modules`（三发布物经生产生成器落 target/modules + 平铺 Juice.jai 退役）——`run_otter_child_at` 与 `run_plugin_scan_child` 消费（`ensure_plugin_face_modules` 删除，统一入发布步；`plugin_face_modules_dir` 注释改发布家）。`bootstrap_juice_modules_dir` 保留（008/009 期 workspace/dependency 子进程 driver 的 bootstrap 参照面，033 切换面）。
- **发布 Juice 面扩展（内部结构面——本票新增，见偏差 1）**：`src/module.jai` 包段追加 `Effective_Target` / `Artifact_Plan` / `Workspace_Discovery` / `Prepared_Workspace` 四声明（形状照 old juice `modules/Juice.jai` 逐声明）——exe 内部源经 `Juice :: #import "Juice"` 命名空间绑定消费（007 偏差 1 形状），种子退役后发布面必须携带才能编译。
- **publication.jai 闭包化**：`path_slashes` → `front_slashes`（4 处；bootstrap #load 闭包不含 path_safety.jai——031 偏差 5 同款纪律，头注释钉）。
- **`tests/bootstrap_tests.jai`**（6 → 8 块）：新增 1 单元（断言 driver 形状 pin：driver 骨架/#load/常量行逐字/#assert 消息/✅ 行）+ 1 E2E（**版本 drift**：临时改写 package.jai version → 自举 exit 1 + stderr「Compile-time assertion failed.」+「package.jai VERSION must equal JUICE_VERSION」，defer 恢复）；debug E2E 强化（预置平铺种子 → 构建后**零残留** + 三发布物与进程内 `publish_*` 输出**逐字节相等** + Testing 特例视图含裸名 `run :: (` 且无 `Testing_run`）；release E2E 补三产物存在 + 无平铺种子；031 的 missing-seed 测试改写为 **missing definition source**（park src/module.jai → 预子进程失败 exit 1；child 响亮输出面归 drift 测试）。
- **`tests/publication_tests.jai`**：真源面 Juice pin 95 → 131 行（包段扩展同步；Testing 237 行 / juice_core 12 行不变）。
- **main.jai 零改动**；旧 juice 仓零改动（仅构建其 debug/release 产物）；map.md 未动。

**验证矩阵**（串行；各先清 otter/target/transpile）：

| 步骤 | 结果 |
| --- | --- |
| 旧 juice debug：juice 根 `jai build.jai` → otter 根 build + test | build exit 0；test exit 0，**Found 440 tests**（438 + 2）、**255 passed, 0 failed**、白名单恰 6 行 |
| 旧 juice release：juice 根 `jai build.jai - release` → 同两命令 | build exit 0；test exit 0，**Found 440**、255 passed、0 failed、白名单 6 行 |
| 自举 debug：otter 根 `jai build.jai`（预置陈旧平铺种子） | exit 0；三发布物落位（131/237/12 行）；**平铺 Juice.jai 被退役**；version 冒烟「juice 0.1.0 / jai 0.2.9」 |
| 自举 release：`jai build.jai - release` | exit 0；exe 581120B（debug 986KB 级）；三发布物重生 |
| 断言两向 | 绿 = 两模式自举（✅ 行）；红 = drift 手工 + E2E（exit 1 + stderr 编译期断言消息） |
| 发布物逐字节 | bootstrap_tests debug E2E：三份 == 进程内 `publish_*` 输出（字节相等断言） |
| expect failed 白名单 | 恰 6 行（module_tests :178/:183/:207/:212 + src/module.jai :353/:379——030 自测行号因包段插入漂移，仍 2 行） |
| **加分冒烟：自托管根自测** | `target/juice-copy.exe test`（target/ 内副本规避运行中 exe 占锁）→ exit 0、Found 440、255 passed、0 failed、白名单 6——**求值器切换实质成立**（test 程序编译与 manifest 求值均经发布面 `target/modules`）；直跑 `target/juice.exe test` = 仅两个自构建 E2E 块 LNK1104（运行中 exe 占锁；005 决定 10 无 hand-off = 031 形状，**hand-off 归 033**） |

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **发布 Juice 面扩展 = 内部结构面（本票新增形状）**：种子退役首跑暴露发布面缺口——自举编译子进程报 `'Workspace_Discovery' is not a member of #import Juice`。根因：exe 内部源（workspace/target/dependency/commands/tests）经 `Juice :: #import "Juice"` 命名空间绑定消费 `Effective_Target` / `Artifact_Plan` / `Workspace_Discovery` / `Prepared_Workspace`（007 偏差 1 的消费面），旧种子面携带这四类型而 005 决定 5 的 Package 兼容面段不含。修复 = `src/module.jai` 包段按 old juice `modules/Juice.jai` 逐声明补四类型（单源保持；发布面自动携带）+ 030 真源面 pin 95 → 131 行。这是自举产物与自托管测试程序编译的前提，也补全 spec §9.5「Package 兼容面」在自举期的实际消费面（Package 作者 API 不受影响，属超集）。
2. **版本断言 = 编译期 #assert（非运行时打印 + exit）**：spike 钉——`#run { main(); }` 编译期执行的程序其 print 只在**正常退出**时冲刷；失败路径 `exit(1)` 吞消息（031 已钉事实的运行时同族：drift 初版 driver 运行时打印 + exit(1) → stdout 全空）。改 `#assert PACKAGE.version == JUICE_VERSION "…"`：jai 编译错误（**stderr**、file:line + 消息文本）+ 非零退出，响亮面成立；✅ 成功打印保留。drift E2E 断言因此检 **stderr**（`errors` 流）。
3. **生成器字面 % 转写 = `\%`**：jai beta 0.2.009 spike——格式串 `\%` = 字面 %（不消费参数）；`%%` 当前等效但带「将改义」告警。生成 driver 的 ✅ 行按 `\%` 发射。
4. **jai 默认 import 路径含 `<cwd>/modules`（解析源实证）**：metaprogram 子进程 cwd 锚 target/（入口锚定事实）→ `target/modules` **自动**在搜索面（旧 juice build 子进程亦然）——旧种子正是因此生效，发布面接管后同路径生效。本票首跑实证：陈旧/截断的发布面令**旧 juice build（otter exe 重编）也失败**；发布面扩展 + 完整后旧 juice build/test 全绿（bootstrap options 的显式 import_dir 仍保留——不依赖默认面）。
5. **missing-seed E2E 前提退役 → 重写**：031 的「缺 Juice 种子 → child 输出含 Juice」前提随平铺种子退役消失（发布面由发布步自产，无法从测试侧抽走）。改写为 missing definition source（park `src/module.jai` → 发布步读失败 → exit 1，预子进程失败面 = 仅退出码）；child 的响亮输出面由 drift 测试（stderr 断言）覆盖——两 seam 各有 pin。
6. **测试面纪律发现（记录，无需修复）**：旧 juice runner 不在测试块间 drain 寄存器——`bootstrap_tests` 中失败的裸 `expect` 会残留并被 `module_tests` 的块首 drain 捕获、经 closing latch 放大为第二个失败。drift 初版失败时实证（顺带定位机制）；drift 修复后 latch 恢复。latch 语义本身正确（跨文件泄漏检测）。
7. **030 自测失败行号漂移**：module.jai 包段插入使 Testing 段自测失败行 :304/:330 → :353/:379（白名单总数仍 6）。
8. **测试侧发布助手 = 生产生成器复用**：`ensure_published_modules` 与 build.jai 发布步同源（publish_* 纯函数），无第二实现；平铺种子退役在两侧同款执行（无残留）。

**033 移交面**：求值器切换实质已随发布落位成立（加分冒烟：副本自测 255/0 经发布面）；033 剩 LNK1104 hand-off（自举 build.jai 无 hand-off = 本票保持 031/005 决定 10 形状；根自测直跑的两个自构建 E2E 块即该 seam）、commands/test.jai 的 testing_face_strip_view 切 import 发布面（030 偏差 4 形态退役）、bootstrap_juice_modules_dir 参照面退役（workspace/dependency 子进程 driver）、六命令 + fixture 冒烟、最终 2 模式根 build/test 全绿收口。
