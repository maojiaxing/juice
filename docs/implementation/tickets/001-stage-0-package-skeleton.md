---
id: 001
title: 阶段 0：包骨架 + 最小 CLI + juice 零特判全绿
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [002]
---

> 父 map：`../map.md`。上游规格：`docs/spec.md` §10 阶段 0（输入 = 空 otter 目录 + 本规格；输出 = package.jai + 最小 src/main.jai + 测试；验收 = juice build/test 于根零特判全绿）+ §3 仓库布局（根包 BIN shape）+ §1 原则 5（零特判）。

# 001: 阶段 0：包骨架 + 最小 CLI + juice 零特判全绿

**What to build:** spec §10 阶段 0 输出直落（最小面——结构层/命令/插件全归后续票）：

- `package.jai`：juice 同形状（`name="juice"`、`targets=[{name="juice", main_file="src/main.jai"}]`）——`workspace.members` 等字段随 1a（002）引入；
- `src/main.jai`：可编译的 CLI 占位（真 dispatcher 归 002）；
- `tests/` 首测试：test 块（阶段 0-2 测试写法约束——旧 juice 只发现 test 块，spec §10）；
- 验收：`juice build` / `juice test` 于 otter 根零特判全绿（debug + release 三路径）。

**Blocked by:** 无

**Status:** ready-for-agent

- [x] package.jai 落盘（juice 同形状最小面）
- [x] src/main.jai 最小 CLI 占位（可编译）
- [x] tests/ 首测试（test 块）
- [x] `juice build` 于 otter 根零特判全绿（debug + release）
- [x] `juice test` 于 otter 根零特判全绿（debug + release）
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行

## Resolution

**落盘三件套（2026-10-19）**：

- `package.jai`：juice 同形状（`#import "Juice"` + `PACKAGE :: Package.{name="juice", version="0.1.0", type=.BIN, targets=Target.[.{name="juice", main_file="src/main.jai"}]}`）——命名定稿照实：重构版以 juice 名义交付，包名即 juice；
- `src/main.jai`：阶段 0 占位 CLI（`print("juice (otter) stage 0 placeholder")`，真 dispatcher 归 002）；
- `tests/stage0_tests.jai`：1 个 test 块（阶段 0-2 测试写法约束——旧 juice 只发现 test 块；断言体故意平凡，测试跑通本身即零特判断言）。

**验证（旧 juice debug + release 双路径，全部 exit 0）**：

| 路径 | build | test |
| --- | --- | --- |
| debug（`jai build.jai` 产物） | ✓ Build completed successfully，otter/target/juice.exe 产出 | ✓ Found 1 tests；1 passed, 0 failed |
| release（`jai build.jai - release` 产物） | ✓ Build completed successfully | ✓ 1 passed, 0 failed |

- 产物冒烟：`otter/target/juice.exe` 打印占位行、exit 0。
- 观察（无害）：旧 juice 对任何无 `modules/` 的包根打印 `Unable to open directory <root>/modules`（import dir 探测的通用行为，非 otter 特判）；阶段 2 前预期持续存在。
- 观察（旧 juice 通用布局，非 otter 设计面）：juice test 后 `otter/target/` 出现 `testing-module/Testing.jai`（Testing 模块 STRIP 视图，测试程序编译面）+ `transpile/`（转译缓存）+ `build-juice.jai`（生成 metaprogram）+ `packages/`（成员 staging）——juice 仓库自身 target/ 同款。otter 自己的 Testing staging 形态 = 003 拍板面（候选：收敛到 `target/modules/Testing.jai`）。
