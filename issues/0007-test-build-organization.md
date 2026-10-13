---
title: 测试构建代码组织：main 冲突与 runner 形态
status: closed
labels: [wayfinder:prototype]
assignee: maojiaxing
blocked-by: [0002-research-jai-test-collection.md]
---

## Question

含 test block 的源码如何变成可执行的 test runner？以原型回答（做几个含内嵌 / 独立 test 的最小 package，把候选组织方式用 jai 手工跑通，给出对比与推荐）：

- BIN package 的用户 `main` 与 runner 的 `main` 冲突解法：转译期剥离 / 重命名用户 main？runner 不把含 main 的入口编进来？测试构建中用户提供 `#program_export "main"` 覆盖？
- 转译产物形态：原文件生成"测试视图"（test 块 → 函数 + 注册，其余代码原样保留）还是别的组织？
- 独立测试文件（tests/foo_test.jai）如何拿到被测代码：`#load` 相对路径？约定注入？同一被测文件被多个测试文件 `#load` 的重复定义问题。
- runner 生成物放哪：缓存目录（不入 `result/`）还是结果目录？
- 测试收集采用 0002 号研究票验证过的哪条路径（#run 注册 / metaprogram 扫描）？

## Resolution

（2026-10-13 原型验证 + 票主拍板；证据链：[prototype/test-build-organization 分支](../prototype/test-build-organization/README.md)（抛弃式分支 a2c4259），实验 E1–E9）

**模型决定：测试在编译期执行，不在运行期**（票主拍板，推翻原型的运行期 runner 推荐与地图原「运行 MVP」前提）。组织经 E9 端到端验证：

1. **视图规则（E5/E6 定，与执行模型无关）**：进入测试程序的每个 package 文件都是缓存中的「测试视图」，镜像 package 相对目录结构：`#import` 逐字保留；in-package `#load` 剥离（E1：Jai 不做 `#load` 去重，重复收录即歧义重载错误；E2：顶层符号程序级可见且与收录顺序无关；E6 负对照：test-free 文件以原文件进 manifest 会经自身 `#load` 拉进含 test 的非法原文件）；test block → `juice_test_N :: () {...} @test`；test-free 文件也生成视图（恒等 + 剥离 load）；out-of-package `#load` 保留原文并跨视图按解析后绝对路径去重（首个保留）。
2. **main 冲突：消失，不重命名**。workspace `output_type = .NO_OUTPUT` 无入口点要求（Compiler.jai:116-121：非 EXECUTABLE 不定义 `__system_entry_point`），user main 作为无人引用的顶层过程原样留在视图（E9 验证）。票面三个候选解法全部不需要：重命名（E3p，运行期模型的解）、排除含 main 的入口文件（入口可含 test 与被引用代码）、`#program_export "main"` 覆盖（实测为符号导出重命名机制，非入口选择）。
3. **driver（替代 runner）**：无 main 的生成文件 = manifest `#load` 全部视图（字典序，每文件恰一次）+ 顶层 `#run` 执行清单（转译期枚举、字典序；**pattern 过滤 = 生成清单时只列入命中测试**）+ `finish()` 后失败数非零则 `assert` 强制编译错误（E7b 通道）→ jai 退出码 1；全部通过则编译成功退出 0（E8/E9 双形态验证）。
4. **first.jai metaprogram**：juice 生成并调 `jai first.jai`（CLI 无 output_type flag，必须 metaprogram）。形态照抄 how_to/450：`output_type = .NO_OUTPUT`；`import_path` 注入 Testing 模块目录（固定 `[] string`，复制到动态数组追加后回写）；`compiler_begin_intercept` 之后再 `add_build_file` driver；消息循环以 `.COMPLETE` 退出；`set_build_options_dc(.{do_output=false})` 使 metaprogram 自身无 main。
5. **落点：全部生成物在缓存目录**（视图、driver、first.jai），无 exe 产物——「runner 放 result/ 还是缓存」问题消失，result/ 语义不触碰。
6. **收集路径**：0002 决议不变（转译期枚举 + 显式清单 + `@test` 注记），执行载体从 runner main 换为 driver `#run`。

**语义边界（spec 必须写明）**：
- 被测代码在**编译期环境**执行：allocator/context 为编译期实例；线程、子进程等运行期设施不可用；适用域是纯逻辑单测。
- 测试崩溃 = 编译器进程崩溃（jai 非零退出、编译器崩溃报告；无「于测试 X 崩溃」式干净归因行）。
- 测试失败经强制编译错误上报：输出含 assert 行与 stack trace（噪音），编译器 stderr 与测试 stdout 经缓冲交错（E9 观察）。
- 每次 `juice test` 全量编译（jai 无增量）。

**附带机械事实**：Testing 模块 API 与执行模型中立（E5 的 Testing.jai 原样复用于 E9，零改动）；`run` 的 proc 参数须为 `() -> ()` 而非 `() -> void`（0005 草案修正）；beta 0.2.009 入口不得有返回值（运行期模型相关，留档）；`jai` 相对路径 flag（`-import_dir`/`-output_path`）与 first.jai 内路径全部以绝对路径传递；视图路径镜像相对结构防撞名（`src/a/x.jai` vs `src/a_x.jai`）。

**影响**：[test block 语言语义](0004-test-block-language-semantics.md)、[Testing 断言模块 API](0005-testing-assertion-module-api.md)、[test 命令 CLI 语义](0006-test-command-cli-semantics.md) 已附勘误；[转译集成与缓存架构](0008-transpile-integration-and-cache.md) 补充输入；[workspace 模型与词汇修订](0010-workspace-model-and-glossary.md) 的「Test runner 是否 Artifact、放哪」已答（无 runner exe，全缓存）。
