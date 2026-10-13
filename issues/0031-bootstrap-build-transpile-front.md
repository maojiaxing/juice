---
title: 自举构建转译前置接入（build.jai 内嵌剥离）
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: []
---

> 父票：[实施计划：src 内联迁移与 build.jai 剥离改造](0030-implementation-plan.md)（实施序列第 1 票）；机制事实见 [ADR 0006](../docs/adr/0006-bootstrap-build-strips-inline-test-blocks.md) 与 [研究报告](../docs/research/jai-metaprogram-view-feeding.md)；规格总章见 [docs/spec-src-inline-test-blocks.md](../docs/spec-src-inline-test-blocks.md)。

## Problem Statement

src 原文件即将内联 test block（147 块迁入，贴近实现），而自举构建 `jai build.jai` 目前直编原文件。test block 不是合法 Jai，src 一旦内联，自举构建必编译失败。Build command（`juice build`）已有闭包探测剥离前端，自举构建没有。本改造必须先行：在 src 仍 test-free 时落地并验证直通零回归，后续测试块迁移（第 4 票）才有安全地基。

## Solution

按 ADR 0006：`build.jai` metaprogram 内嵌转译器纯函数（`#load` 复用 src/transpile.jai），与 Build command 共用同一转译器与视图契约。入口沿字面量 in-package `#load` 传递闭包探测：闭包含 test block → 入口视图经 `add_build_string` 喂入（行号恒 +5、列精确），闭包其余视图落盘、in-package `#load` 重写为视图绝对路径；test-free 闭包原样直编、零转译零落盘。改造后两条构建路径剥离语义一致，src 内联迁移可安全开始。

## User Stories

1. As a 仓库作者, I want `jai build.jai` 在 src 内联 test block 后仍构建成功, so that 自举路径不阻塞内联迁移。
2. As a 仓库作者, I want 改造后 src test-free 期 `jai build.jai` 行为与改造前完全一致（零转译直编）, so that 改造本身零回归。
3. As a 仓库作者, I want 自举构建与 Build command 共用同一转译器与视图排版契约, so that 两条路径语义不漂移、行号保真不变量一致。
4. As a 仓库作者, I want 入口文件的剥离视图经 `add_build_string` 喂入且行号偏移恒 +5, so that 诊断可减常量还原原文件坐标。
5. As a 仓库作者, I want 闭包内非入口文件的视图落盘且 in-package `#load` 重写指向视图绝对路径, so that 多文件闭包正确编译且 #load 树跟随。
6. As a 仓库作者, I want 探测范围 = 入口沿字面量 in-package `#load` 的传递闭包（非字面量与 out-of-package 不探测不改写）, so that 与 Build command 语义一致。
7. As a 仓库作者, I want test-free 闭包不产生任何视图文件与缓存, so that target directory 无多余生成物。
8. As a 仓库作者, I want 每 workspace 只喂一个字符串（入口视图）, so that +5 行号映射保持常量（多串偏移会按前序内容累积）。
9. As a 测试运行者, I want `juice test` 在改造后全绿, so that 测试体系不受自举改造影响。
10. As a 仓库作者, I want build.jai 被测试程序作为视图加载时的早退守卫保持, so that 编译期测试不连累构建树。
11. As a 仓库作者, I want 仅 build.jai 被修改（转译器与 Build command 前端零改动）, so that 改造面最小。
12. As a 后续迁移执行者, I want 临时探针验证后 src 回归 test-free, so that 第 4 票的迁移映射表不被提前占用。
13. As a 仓库作者, I want 探针覆盖多文件闭包（入口与子文件都含 test block）, so that 闭包探测、视图落盘与 #load 重写被真实执行。
14. As a 仓库作者, I want 探针注入一次编译错误以验证 +5 诊断映射（虚拟路径报错、行号 = 视图行 +5）后撤销, so that ADR 0006 行号保真不变量有实践证据。
15. As a 使用者, I want 自举产物 target/juice.exe 可运行（烟测 `juice test` 于仓库根跑通）, so that 自举产物仍是可用工具。
16. As a 仓库作者, I want release 与 debug 两模式均剥离正确, so that 优化开关不影响转译前置。

## Implementation Decisions

- **转译器复用**：build.jai 顶层 `#load "src/transpile.jai"`（被 load 代码编译进 metaprogram 执行环境、不进入被构建程序；0028 研究已证）。转译器与 Build command 前端零改动，无新增转译规则。
- **探测与剥离**：复用转译器现有闭包探测与 STRIP 模式；闭包含 test block 即全有全无视图化（入口视图亦剥离，即便入口自身 test-free）。
- **test-free 直通**：闭包无 test block → 零转译、零落盘、原样 `add_build_file`，与现行为一致。
- **喂入方式**：入口视图 `add_build_string`（toplevel 作用域、每 workspace 单串）；闭包其余视图落盘，in-package `#load` 重写为视图绝对路径（STRIP 已有机制）。
- **插入点**：`set_build_options` 之后、`compiler_begin_intercept` 之前；消息循环与构建选项配置不变。
- **视图落盘位置**：target directory 转译子树下自举构建专属子目录，不与 Build command 内容寻址缓存混用（缓存复用留待后续优化）；Clean 随 target directory 整目录清理。
- **闭包含转译器自身**：src/main.jai 入口闭包含 src/transpile.jai 与 src/transpile_cache.jai（既成事实）——目标程序以剥离视图编译、metaprogram 以原文件 `#load`，两者是独立编译单元，互不影响。
- **早退守卫保留**：build.jai 被 `juice test` 作为视图加载时（末参数为 first.jai）跳过构建；其测试视图中的 in-package `#load` 被剥离、符号经程序级可见性共享。
- **诊断映射**：入口字符串错误报虚拟路径、行号 = 视图行 +5（列精确）；磁盘视图错误报精确文件:行号（e3b 实验事实）。实施时以探针覆盖。
- **探针设计**：临时在闭包内联 test block（入口 + 一个经字面量 in-package `#load` 的子文件），验证两构建路径剥离成功、`juice test` 展开执行（输出含探针测试名）；注入一次编译错误验证 +5 映射后撤销；验证完成后移除全部探针，src 回归 test-free。

## Testing Decisions

- **什么算好测试**：只验证外部行为——三条命令的退出码与输出（构建成功、`juice test` 输出含探针测试名、0 failed），不测试 build.jai 内部实现（调用顺序等由端到端行为覆盖）。
- **seam 层级**（与用户确认）：三路径端到端命令（`jai build.jai`、`juice build`、`juice test`）为最高且唯一常驻 seam，不新增常驻测试设施；转译器行为由既有 tests/test_transpiler.jai（45 块）与 tests/test_test_command.jai（27 块）覆盖，本票不新增转译器测试；临时探针是本票唯一新增 seam，验证后移除。
- **判据**：0 failed + 退出码 0（passed 汇总数不做硬判据——Testing.finish 重置语义，0030 决议）。
- **Prior art**：0028 研究的 e1–e3b 实验（临时目录、未进仓库）；0021 票的 fixture 包验收模式；0030 计划的三路径判据。

## Acceptance criteria

- [x] `jai build.jai` 全绿（src test-free 期直通零回归；探针期剥离成功）
- [x] `juice build` 全绿（探针期剥离成功，产物可运行）
- [x] `juice test` 全绿且探针测试块被执行（输出含探针名）
- [x] 探针注入编译错误：入口错误报虚拟路径、行号 = 视图行 +5；磁盘视图错误报精确文件:行号
- [x] 探针移除后 src 回归 test-free，三路径复验全绿
- [x] 自举产物 target/juice.exe 烟测（`juice test` 于仓库根跑通）
- [x] 仅修改 build.jai；转译器与 Build command 前端零改动

## Out of Scope

- 测试块迁入 src（第 4 票）、test_support.jai 抽取（第 2 票）、Testing 自测内联（第 3 票）
- 转译器新增规则或接口变更（STRIP 已有机制全复用）
- Build command 前端改造（已有闭包探测剥离）
- 诊断映射常驻自动化测试（探针一次性验证；常态化错误注入不进仓库）
- 发布视图树（ADR 0006 已排除）
- modules/ 内联 test block（保持 test-free 纪律）

## Further Notes

- 语言：中文交流与文档。
- beta 0.2.009 下 `#load` 转译器会出现两条 `%%` print 兼容警告（无碍；勿"修复"，避免触碰转译器）。
- **已知风险（第 4 票前置留意）**：build.jai 的 `#load` 目标 src/transpile.jai 在测试块迁入后不得含 test block（metaprogram 编译期文本包含，test block 非法 Jai）——第 4 票执行时需保证该 `#load` 目标 test-free（如转译器测试块落独立 src 文件或拆分 test-free 核心），本票不处理。
- 后续票 2–5 依赖本票；本票完成后方可开始迁移。

## Resolution

已按 ADR 0006 实施（提交 95d415d，仅修改 build.jai，+328/-101）：顶层 `#load "src/transpile.jai"` 内嵌转译器纯函数；入口沿字面量 in-package `#load` 的 DFS 闭包探测；test-free 闭包直通（零转译零落盘）；含 test block 时入口视图 `add_build_string`（每 workspace 单串、行号偏移恒 +5）、闭包其余视图落盘 `target/transpile/bootstrap/`、in-package `#load` 重写为视图绝对路径；插入点 set_build_options 之后、begin_intercept 之前；早退守卫与消息循环零改动。

探针实测：入口注入错误报虚拟路径 `target/.added_strings_w3.jai:29,1`（29=24+5，+5 映射成立）；磁盘视图注入错误报精确 `target/transpile/bootstrap/src/xdg.jai:85,1`。探针期 17 个视图落盘、`juice test` 展开执行探针块（Found 149）；探针移除后 src 回归 test-free、Found 147。三路径 + debug/release + 自举产物烟测全绿。

已知偏差（探针期固有）："Build forwards each prepared plan to compilation" fixture 以真实 src 闭包为 test-free 前提，与探针注入冲突——探针期唯一失败，移除后全绿。后续合并（a31a915）按 0033 对称特例为 bootstrap 增加 Testing 模块 STRIP 视图替代（见 0033 Resolution）。
