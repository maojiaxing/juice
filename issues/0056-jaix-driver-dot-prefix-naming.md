---
title: jaix driver 点前缀命名（jaix 侧）
status: closed
labels: [ready-for-agent]
assignee: maojiaxing
blocked-by: []
---

> 父 spec：`issues/0054-spec-jaix-prestep-leftover-cleanup.md`（决定 4 + Testing Decisions 接缝 5）。jaix 侧唯一触碰（v1 其余功能面冻结）。

# 0056: jaix driver 点前缀命名（jaix 侧）

**What to build:** jaix CLI 的 transpile driver 写盘名从 `<hash>.jai` 改为 `.jaix-<hash>.jai`（落点目录不变 = 调用时工作目录，049 决定 12 的面只改命名）。juice 既有「任意深度点条目」扫描排除自动接住新垃圾；054 偏差「driver 哈希文件被扫描」的负向实证翻转为点前缀纪律的正向面。driver 文件名不在任何 golden 中（实现时复核）。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] CLI driver 写盘名点前缀（`.jaix-<hash>.jai`）
- [x] cli_tests 新增写盘名字面断言
- [x] jaix `juice test` 全绿（518 + 新增）、golden 68/68 零重定、embed OK、jaix-cli build 绿
- [x] exe 冒烟：driver 以点前缀名落调用时工作目录

## Resolution

**实现摘要（jaix 侧唯一触碰，零 juice 代码改动）：**

- `jaix/src/cli.jai`：run_cli_capture 的 driver 写盘名 `tprint("%1/%2.jai", env.driver_dir, hash_hex(driver_text))` → `tprint("%1/.jaix-%2.jai", ...)`（点前缀 + hash 保留）；落点目录不变 = 调用时工作目录（049 决定 12 的面只改命名）。文件头 Cli_Env.driver_dir 注释与 run_cli 段注释同步刷新（054 决定 4 引用 + 点条目排除语义一句）。
- `jaix/tests/cli_tests.jai`：新增 1 块 `run_cli E2E ⚙：driver 写盘名 = 点前缀 + hash 保留`——期望名经 `generate_transpile_driver(config_path, .{root_dir = get_working_directory()})` + `hash_hex` 确定性推论（run_cli_capture 内部同参同文本）后盘上在场断言（`.jaix-<hash>.jai` 字面）+ 旧裸哈希名 `<hash>.jai` 不在场断言（只改命名、落点不变）。文件头 E2E 面清单补一行。

**golden 复核结论：** driver 文件名不在任何 golden 基线中——fixture 全量 grep `[0-9a-f]{12,}\.jai` 零命中；本次测试跑 golden 68/68 PASS、0 UPDATE、0 FAIL 佐证（未重定任何 golden）。

**验证结果：**

- jaix 根 `juice test`（先清 target/transpile）：**519 passed, 0 failed**（518 零回退 + 新增 1 块）、exit 0、**GOLDEN 68/68** 零重定（0 FAIL / 0 UPDATE）。
- examples/embed-consumer `juice build` 绿 + `juice run` 输出 "jaix embed OK"。
- jaix-cli `juice build` 绿（产物 target/jaix.exe）。
- src 九 + modules 二 test-free 保持（grep `test "` 零命中）。
- exe 冒烟：自 jaix-cli/target/smoke-0056（调用时工作目录）运行新 jaix.exe transpile → exit 0、view + sidecar 写出、driver 以 `.jaix-383fcc0dc52cd26c.jai` 落该目录（点前缀 + hash 保留、无裸哈希名）。
- juice 顺手验证：jaix-demo fixture 根干净状态下 PATH 前缀注入新 jaix.exe 连续两次 `juice build`——build 1 遗留 driver = `.jaix-e1b014af8c03dfe8.jai`（点前缀名落 fixture 根）；build 2 照常成功（juice 既有「任意深度点条目」排除接住新垃圾）；验证后清理 driver 与 target/，fixture 复原、juice 工作树零新增污染。

**偏差：** 无实现偏差。测试断言形状执行级决定：字面断言 = 期望名确定性推论后「盘上在场 + 旧裸名不在场」双锁定（049 决定 12 落点不变面由旧名缺席锁定）。
