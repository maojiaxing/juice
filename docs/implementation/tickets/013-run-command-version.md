---
id: 013
title: run 命令 + version
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [011]
blocks: [014]
---

> 父 spec：`002-spec-build-clean-structure.md`（决定 1/5 + US 19/25）。上游规格：`docs/spec.md` §4.3（唯一前置链 run→build）/§4.6（run 序）；研究 L§1.5（run.jai:30-79 参照）。

# 013: run 命令 + version

**What to build:** `juice run` 端到端：前置链 run→build（dispatcher 前置面 010 已备；前置失败 = PREREQUISITE_FAILED）→ select_artifact_plan → launch（输出/退出码透传）。`juice version`：juice 自身版本（Package.version）+ jai 编译器版本——编译期 `compiler_get_version_info`（Compiler.jai:1509，#compiler 内建 major.minor.micro）经 `#run` 常量烘入 exe（spike 确认；回退 = spawn jai 读启动横幅）。

**Blocked by:** 011（run 的前置 = build 全链）

**Status:** closed

- [x] run：前置链 + launch + 输出/退出码透传
- [x] version：juice 版本 + jai 版本（#run 常量烘入，spike 确认机制；输出契约 = 两行）
- [x] run_tests + version 输出契约姊妹测试
- [x] E2E fixture run（run 输出断言 + 前置 build 链断言）
- [x] 旧 juice build/test 于 otter 根零特判全绿（debug + release）
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话，本票不改 map.md）

## Resolution

**实现摘要**（新建文件 8 个：tests/run_tests.jai + tests/version_tests.jai + fixture run-{fixture,fail} 各 2 文件 + spike main.jai 残留在 Temp；改写 4 个：src/commands/run.jai 占位 → 真实现、src/commands/version.jai 占位 → 真实现、src/main.jai 头注释、tests/test_support.jai、tests/e2e_cli_tests.jai）：

- `src/commands/run.jai`：run 全链（语义等价重写自旧 juice commands/run.jai:7-79）：
  - `RUN_COMMAND`（prerequisites = `["build"]`，validator ≤1 参）+ `run_command_handler`（守卫 → `ensure_workspace_prepared(ctx.root_dir, ctx.cache_dir, *ctx.workspace)` 三参调用——build 前置跑完相位机已 PREPARED，幂等拿回现成状态 → `run_prepared_workspace`）；
  - `select_artifact_plan`（run.jai:30-45 语义）：0 计划 → false；指定 target → **拼写精确（大小写敏感）**遍历匹配（声明唯一性大小写不敏感、命令行拼写精确）；未指定且恰好 1 计划 → 该计划；未指定多计划 → 名字 == 包名者；否则 false；
  - `run_artifact_plan`：`revalidate_artifact_plan`（build/run 共用大门，009）→ 不安全 `"[juice ERROR] Refusing unsafe artifact path: %"`；`file_exists` → 缺 `"[juice ERROR] Could not find executable to run: %"`；打印 `"[juice Run] Launching % ..."` → `run_command(plan.artifact_path)`（**继承 cwd = 包根**，juice 永不 chdir；输出/退出码自然透传）→ `exit_code == 0`；
  - `run_prepared_workspace`（launch seam 形状逐字段保留旧 juice——1c 的 at_EXECUTE 挂载点）：选择失败三条消息逐字节同旧 juice run.jai:70/72/74（`"Package has no executable target to run."`/`"Multiple targets exist; select one explicitly or define a target named '%'."`/`"Unknown binary target: %"`）。
- `src/commands/version.jai`：`JUICE_VERSION :: "0.1.0"`（硬编码 + package.jai 的 PACKAGE.version 同步注释——version 零前置零 workspace，必须可在包根外运行，不能读 manifest）+ `JAI_COMPILER_VERSION :: #run -> string { info: Version_Info; compiler_get_version_info(*info); return tprint("%1.%2.%3", ...); }`（编译期烘入，见偏差 1）+ `version_command` 输出契约两行 `"juice %\n"`/`"jai %\n"`。
- `tests/test_support.jai` 追加：`test_launch_*` 录制 fakes + `reset_run_seam`（旧 juice test_support.jai:219-228 语义——run_prepared_workspace 的 launch seam 录制面）。
- `tests/run_tests.jai`：9 块——旧 juice run.jai 内联测试 4 名全映射（"Run launches the selected prepared artifact" 多计划包名优先 + 显式精确选择/"Run defaults to the only target" 唯一计划/"Invalid Run selection never launches" 多计划无包名/未知 target/大小写敏感 "Alpha"/零计划 + 零启动计数/"Run propagates launch failure"）+ `run_artifact_plan` 两失败门单位直测（逃逸 artifact 路径拒跑/缺 artifact 报错——成功路径需真 spawn，见偏差 2）+ **E2E 3**（真 otter exe 于 fixture：run-fixture 缺省 run = 前置 build 链断言（`"[juice Build] Compiling Target 'run-fixture' (src/main.jai) -> target/..."` + `"Build completed successfully!"`）+ launch 断言（`"[juice Run] Launching"` + `"hello from run-fixture"`）；显式 `run run-fixture` 精确选择；run-fail exit(3) → juice exit 1 + 输出透传（`"about to fail"` + `"Command 'run' failed while executing 'run'."`））。
- `tests/version_tests.jai`：2 块——常量对照契约（`JUICE_VERSION == "0.1.0"` && `JAI_COMPILER_VERSION == "0.2.9"`——测试程序自身编译烘入同值，编译器升级时该块先响）+ E2E 两行逐字节契约（`child_output_equals` 锁定 `"juice 0.1.0\njai 0.2.9\n"`）。
- `tests/e2e_cli_tests.jai` 修订（012 同款纪律）：占位测试移除 version（真实现；test 占位保持）+ 新增 run/version 多余参数守卫测试（**plan_command 计划期查参 → INVALID_ARGUMENTS，不触发 build**——run 守卫可在 otter 根安全 E2E）。
- fixture 4 文件：`tests/data/run-fixture`（BIN 单隐式 target = 包名——默认选择 + 显式选择面，hello 程序）、`tests/data/run-fail`（artifact exit(3)——退出码透传面）。

**验证矩阵**：

| 步骤 | 结果 |
| --- | --- |
| `jai build.jai`（旧 juice debug） | 成功 → target/juice.exe |
| 清 target/transpile → `juice.exe build` 于 otter 根 + `test`（debug） | exit 0，**175 passed, 0 failed**（163 + run_tests 9 + version_tests 2 + e2e_cli 新块 1） |
| `jai build.jai - release`（旧 juice release） | 成功 |
| 清 target/transpile → `juice.exe build` + `test`（release） | exit 0，**175 passed, 0 failed** |
| exe 冒烟：otter exe `version` 于 otter 根 | exit 0 + `juice 0.1.0` / `jai 0.2.9` 两行（#run 烘入在旧 juice 构建的产物里实测可用——spike 定案，回退未启用）；fixture 树零污染（E2E defer 清理验证） |

旧 juice 对无 modules/ 包根的 import dir 探测提示为通用无害行为（map Notes 已记）。

**偏差清单**：

1. **jai 版本烘入机制 spike 发现（父 spec 假设修正面）**：`compiler_get_version_info` 的字符串返回 = **全横幅**（`"beta 0.2.009, built on 6 February 2025"`），不是 Compiler.jai:1503 注释所称的 major.minor.micro；数值三元组来自 `Version_Info` 填充（major=0 minor=2 micro=9）——version 输出 = 三元组 `"0.2.9"`（父 spec 决定 5 的意图 = 版本串而非日期横幅；契约随编译器大版本升级时更新 version_tests 对照块，该块先在测试程序编译面报警）。`#run` 常量形式实证：表达式形式 `X :: #run expr;` 与块形式 `X :: #run -> T { return ...; }` 均可用（how_to 080/044）；裸块 `#run { return ...; }` 非法（"Too many return values: Wanted 0, got 1"）。spike 在 `AppData/Local/Temp/otter-version-spike/`（不回退 spawn 方案）。
2. **run_artifact_plan 成功路径零单位测试**：真 spawn 需要真 exe（旧 juice 同状先例——成功路径只经 launch seam 与 E2E 覆盖）；两失败门（unsafe/missing）单位级直测。
3. **run-fail fixture 为新增**：旧 juice 无「artifact 非零退出 → juice 退出码映射」E2E（"Run propagates launch failure" 仅 seam 级）；otter 以 fixture + 真 exe 钉住透传全链（输出透传 + HANDLER_FAILED 文本 + exit 1）。

**测试组织**：src 实现模块全部 test-free（bootstrap #load 集纪律）；测试驻 tests/（run_tests/version_tests 姊妹文件 + test_support 共享 launch fakes）。移交面：014 fixture 收口复用 run_otter_child_at + ensure_bootstrap_modules；run 的 launch seam = 1c at_EXECUTE 挂载点（形状已按旧 juice 保留）；test 命令占位 = 1b；version_tests 对照块 = 编译器升级契约哨兵。
