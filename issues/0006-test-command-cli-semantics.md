---
title: test 命令 CLI 语义
status: closed
labels: [wayfinder:grilling]
assignee: maojiaxing
blocked-by: []
---

## Question

`juice test` 的 CLI 语义：

- 参数规则：`<pattern>` 是子串还是 glob？允许多个 pattern？与现有 command 参数验证框架如何整合（Command.validate_arguments）。
- usage 文案与 registry 形态：prerequisites = `["prepare-workspace"]`，visible = true？
- 输出样式：逐测试一行？失败详情块？汇总（通过/失败计数、总时长）？对齐现有 `[juice ...]` 输出前缀惯例。
- 退出码约定：测试失败非零；编译失败与测试失败是否区分退出码？
- 无测试时的行为：成功 + 明确说明（对齐 Build 的"没有可构建目标仍成功"惯例）？

## Resolution

（2026-10-13 grilling 敲定，五项决议）

1. **pattern 语义**：大小写敏感**子串**匹配；单个可选 pattern；匹配对象 = **最终报告名**（命名测试裸名 / 匿名测试 `package相对路径:行号`，0004 已定），子串作用于完整报告名字符串，可命中路径片段（如 `juice test utils` 命中 `src/utils_test.jai:12`）。大小写敏感对齐 target 命令行选择惯例（`run.jai:31` 注释）。glob/正则/多 pattern 为可加扩展，不进 MVP。
2. **registry 形态**：与 run 完全同构——`usage = "juice test [pattern]"`、`validate_arguments = count <= 1`（复用 `command.jai` 的 `[juice ERROR] Usage:` 行惯例）、`prerequisites = ["prepare-workspace"]`（既有内部命令）、`visible = true`。
3. **juice 侧输出**：编译期 `[juice Test]` 阶段行（对齐 `[juice Build]/[juice Run]/[juice Clean]` 前缀惯例），报告"发现 N 个测试 → 编译 runner"；运行期 runner 子进程 stdout **原样透传**（逐条失败行 + 汇总归 Testing，0005），juice 不加前缀、不解析、不在汇总后重复。**Testing 输出格式的结构约束：每个测试开始时打一行**（崩溃点人眼可从 stdout 尾部归因；具体措辞与格式仍留雾，等 [诊断与位置映射](0009-diagnostics-and-location-mapping.md) 合流）。崩溃时 juice 打 `[juice ERROR] Test runner crashed.` 类错误行，不解析 stdout、不承诺精确余下数——修订 [test block 语言语义](0004-test-block-language-semantics.md) 第 7 条的措辞承诺（崩溃语义不变，报告形态放宽）。
4. **退出码**：MVP 统一 `exit(1)`（编译失败与测试失败同码，对齐 `main.jai:43` 现状与全部既有命令）；区分码（如编译=1/测试失败=2）写进 spec 作为可加扩展，新增码不破坏现有契约。
5. **空语义**：package 无任何 test block → **成功** + `[juice Test] No tests found.`，且**跳过 runner 编译**（转译期枚举已知测试数为 0，不生成不编译 runner）；pattern 零命中 → **成功** + `[juice Test] No tests matched 'x'.`。对齐 Build"无可构建目标仍成功"惯例。

ADR 判断：均可逆或可加性扩展（pattern 方言、区分退出码、输出格式演进），不写 ADR。Test command 词条收口归 [workspace 模型与词汇修订](0010-workspace-model-and-glossary.md)。

勘误（2026-10-13，[测试构建代码组织](0007-test-build-organization.md) 决议测试编译期执行）：第 3 条「runner 子进程 stdout 原样透传」改为「**jai 编译输出**原样透传」——无 runner 子进程，测试输出即编译期输出（与编译器 stderr 经缓冲交错，spec 写明；崩溃时 juice 打编译器崩溃的错误行）。第 4 条退出码通道改为 jai 退出码：编译失败与测试失败（经 driver 强制编译错误）仍统一 1，语义不变。第 5 条「跳过 runner 编译」改为「跳过测试编译」。pattern 语义、registry 形态、`[juice Test]` 阶段行、空语义、每测试开始行约束全部不变。
