---
id: 067
title: 生成文本与测试策略
labels: [wayfinder:grilling]
status: closed
assignee: maojiaxing
blocked-by: [064, 066]
blocks: [068]
---

# 067: 生成文本与测试策略

## Question

生成文本与测试策略的边界怎么定？

已拍板（2026-10-22）：行为等价；generated text 允许重写；byte pin 可更新；零文件 `juice test` 与零 target `juice build` 的 host 级声明校验是有意的行为变化。

要定：

- 哪些生成文本允许改：`target/plugins/host.jai`、`test_runner.jai`、registration 文件、build metaprogram、version assertion driver；哪些必须保持逐字节。
- 逐字节 pin 的更新策略：保留哪些、改成结构断言哪些；`tests/plugin_host_tests.jai:345-378`、`tests/test_runner_tests.jai:56-121,147-160`、`tests/test_command_tests.jai:724-726` 的处置。
- session 级测试的 fake 形状：stage body fake、host spawn fake、collect/spawn seam；命令 E2E 保留哪些。
- 零工作分歧的测试：build vs test 在零 target / 零文件时对非法 plugin declaration（含 member version/options）的一致失败；零工作 host spawn 的 fake / 断言。
- Member hook 面 / registration state 的测试：非 PRESTEP/before 拒绝（host 权威）、声明成员但无 hook 的 host OK=1、`Hook_Registration.state` 传播、`get_scanned_hook_entries` 退役、`plugin_state` / `slot_options` 平行数组删除、零工作 host spawn。
- 计数基线：当前套件计数/白名单/三路径完成定义；本 effort 后如何记录。
- 是否因 C04 被迫引入共享 bootstrap emitter；C06 仍出范围。

相关锚点：`src/test_runner.jai:177-405`、`src/plugin_host.jai:248-334`、`tests/test_support.jai:129-166,1043-1063,1228-1256`。

## Answer

**1. Generated text = 只改强制项。**

- 改：`target/plugins/host.jai`（删 slot loop、加 member hook validation、删 `HOST_MODE`）与 registration 文件（删 `JUICE_HOOK_<i>` / `get_scanned_hook_entries()`）。
- 不变：`test_runner.jai` 生成文本、build metaprogram、version assertion driver，保持逐字节。`Resolved_Plugins` 的类型变化对 test metaprogram 生成文本透明（它不引用 `slot_options`）。
- C06（共享 bootstrap emitter）**不由本次强制**；保持 out of scope。host 的新 validation loop 是 host 专属逻辑，不构成共享 emitter 的理由。

**2. Pin 策略 = 保留逐字节 pin。**

- host / registration / test runner 继续逐字节 pin；只更新 host 与 registration 的期望字符串。
- 新增一条精确 pin：member hook 拒绝消息（含 stage / position，例如 `member hook not supported: TRANSPILE before (v1 supports PRESTEP/before only)`）。
- build metaprogram / version assertion driver 的现有 pin 不变。

**3. Session 级测试 = 真 fixture + fake host spawn。**

- `begin` 继续接受 host spawn seam（064）；测试用**真实 fixture 包**跑 prepare / scan / resolve，只 fake `host_spawn`；不引入 fake prepare seam。
- 覆盖：
  - 顺序：prelude → begin → zero-work 短路 → stages；begin / stage failure 传播。
  - host spawn：`registration_path != ""` 时才调用；声明成员但无 hook 时 host OK=1；零 target build / 零文件 test 也 spawn。
  - member hook 面：`.TRANSPILE/.before` 与 `.PRESTEP/.after` 被 host 拒绝；`.PRESTEP/.before` 运行（jaix 插件 E2E）。
  - registration state：`Hook_Registration.state` 传播、`run_mounted_hooks` 读取、`plugin_state` / `slot_options` 删除、`get_scanned_hook_entries` 退役。
  - at hook：调用前后 kind 检查；不匹配 = ERROR。
  - 零工作：非法 member declaration（含 version/options）在零 target build / 零文件 test 都失败；合法声明成功。
- 测试落点：`tests/lifecycle_tests.jai`（lifecycle.jai 的姊妹文件）；command wrapper 现有测试保留，E2E 保留。

**4. 完成定义 = 三路径 + 计数记录。**

- 三路径全绿：自举循环、姊妹测试、E2E 真子进程。
- 记录 pre/post：套件 `found` / `passed` 计数、白名单行数、成员套件计数；不设固定数字目标；新增/删除测试的 delta 在收口票说明。
- 记忆里的 545 found / 331 passed / 白名单 6 / 成员 17+3 只作参考；实现开始时以实际输出记录 pre-refactor 基线。

**5. C06 / fog。**

- C06 保持 out of scope；map 的 “Generated program 长期单源” 雾项按“不强制”收口（从 Not yet specified 移除，Out of scope 注明 067 确认）。
