---
title: 地图：test command 与 test block 单元测试
status: closed
labels: [wayfinder:map]
assignee: maojiaxing
---

## Destination

为 `juice test`（Zig 风格 test block 单元测试）产出完整设计决策集：语法语义、测试构建机制、Testing 断言模块、CLI 与 workspace 语义、CONTEXT.md 词汇与 ADR、实施顺序（以 Juice 自身测试迁移收尾），可直接开工实施。

**已达成（2026-10-13）：全部 11 张决策票关闭，决策集齐备，可开工实施。**

## Notes

- 领域：Jai 语言构建工具（Juice）。词汇权威是 CONTEXT.md；决策记录用 docs/adr/（仓库惯例）；机制事实基础是 [docs/research/syntax-transpiler.md](../docs/research/syntax-transpiler.md) 与 [docs/research/dynamic-libraries.md](../docs/research/dynamic-libraries.md)。
- 决策票 session 应咨询：grilling + domain-modeling。
- 已定前提（2026-10-12 与用户敲定，后续票以此为基，不再重议）：
  - 目的地是决策集 spec，不含实施；spec 含 Juice 自身测试迁移计划（实施最后一环）。
  - 语法：`test "name" { ... }` 与匿名 `test { ... }`，严格 Zig 形态，必须转译（已验证任何变体都不是合法 Jai；Jai 不支持尾随块调用）。
  - 发现：扫描 package 内所有 `.jai` 文件；内嵌与独立测试文件都支持。
  - test 的 prerequisite 是 prepare-workspace（不依赖 build）；LIB package 可测（修正"无 target 即无事可做"盲区）。
  - 断言库是 Juice 的一级模块，名 Testing（用户代码 `#import "Testing"`）；最小集，支持失败继续 + 汇总。
  - 运行 MVP（2026-10-13 票主修订，见 [测试构建代码组织](0007-test-build-organization.md)）：测试在**编译期**执行（`#run` 驱动 + NO_OUTPUT metaprogram），否决运行期 runner；全跑 + 失败继续 + 汇总 + 非零退出码（失败→强制编译错误→jai 退出码）语义保留；`juice test <pattern>` 过滤（生成清单时过滤）；不做并行。
  - 关系模型（2026-10-13 修订）：被测代码以源码形态直接编译进测试程序（视图），编译期执行；test block 处于所在文件顶层作用域。
- 交流语言：中文。

## Decisions so far

- [研究：Jai 测试收集与构建机制](0002-research-jai-test-collection.md): 编译期 `#run` 注册实验判死（编译期可变全局不持久化 + 逆 `#load` 序）；metaprogram 扫描冗余；推荐转译期枚举 + runner 显式调用 + 失败汇总退出码；gs_test 先例与发行版 `@test` 注记（进行中官方约定，转译产物建议带上）。
- [测试发现范围规则](0003-test-discovery-scope.md): package root 全量递归 + 最小排除集（点开头条目、root 的 `result/`、`package.jai`、不跟符号链接、仅小写 `.jai`）；root 扫描不进 member 子树，member 自为 root 跑测试；依赖不发现不跑（兜底归 0008）；test 扫描消费 discovery 快照但不并入 discovery；确定性字典序遍历派生枚举/调用/报告顺序。
- [test block 语言语义](0004-test-block-language-semantics.md): 仅文件顶层（函数/类型体内转译期拒绝）；签名 `() -> void`，失败走 Testing 全局登记（为 0005 划界）；可见性 = 所在文件顶层可见性；同名允许共存、撞名时报告附路径消歧；匿名报告名 = package 相对路径:行号；词法锚点仅 token 级两形态、其余透传无歧义；崩溃即 runner 终止（不做隔离）。
- [Testing 断言模块 API](0005-testing-assertion-module-api.md): 最小三件 expect/expect_eq/fail（`#expand` 宏；失败=登记+`return` 中止本测试，套件继续）；`$T` 编译期同型与格式化；失败即时逐条 + finish 汇总；runner 接口收口为 run 清单 + exit(finish())；单文件仅依赖 Basic。
- [test 命令 CLI 语义](0006-test-command-cli-semantics.md): pattern=大小写敏感子串、单个可选、匹配最终报告名（含匿名路径名）；registry 与 run 同构；juice 侧 `[juice Test]` 阶段行 + runner stdout 原样透传，Testing 加每测试开始行（修订 0004 崩溃措辞）；退出码 MVP 统一 1；无测试/零命中都成功+说明，零测试跳过 runner 编译。
- [测试构建代码组织：main 冲突与 runner 形态](0007-test-build-organization.md): 票主拍板测试**编译期执行**（否决原型推荐的运行期 runner）：全文件视图（`#import` 保留、in-package `#load` 剥离、test→`juice_test_N`+`@test`）+ user main 不重命名（NO_OUTPUT 无入口点）+ driver（`#run` 清单、pattern 过滤即生成子集、失败→强制编译错误→jai 退出码）+ first.jai metaprogram（import_path 注入 Testing）；生成物全入缓存、无 exe；Testing API 模型中立、`run` 参数 `() -> ()`；0004/0005/0006 已附勘误。
- [转译集成与缓存架构](0008-transpile-integration-and-cache.md): build 探测后剥离（entry 起字面量 in-package `#load` 传递闭包、全有全无视图化；test-free 闭包零转译直编）；转译器进程内库；非字面量/out-of-package `#load` 不转译、jai 报错透传；**统一 cargo 式 `target/` 取代 `result/` 与 `.packages`**（artifact 落 target/ 根、shim 落 `target/packages/`、转译落 `target/transpile/` 内容寻址；XDG 留 git 源缓存；Clean=删 target/）；seam=command 编排层前置；ADR 0003/0004；0003 排除集勘误、0010/0011 范围更新。
- [诊断与位置映射](0009-diagnostics-and-location-mapping.md): 行号保真排版（视图行=原文件行，编辑类全可保行）使 `#caller_location` 行列零映射，6.3「内嵌注释/sidecar」双不需要；路径改写=driver 注入显式映射表→Testing 查表（不注入即透传，中立性不破）；产物编译错误 MVP 人工对照（行:列已一致，剥缓存前缀；juice 侧改写为可加扩展，届时修订 0006）；格式=失败行 `path:line,col: 消息`（无 `Error:` 前缀）、每测试开始行 `[test] 名`、汇总 `N passed, M failed`；编辑细则与《视图行号保真》ADR 归 0011 成文。
- [workspace 模型与词汇修订](0010-workspace-model-and-glossary.md): 复用 prepared workspace（test 消费之但不消费 artifact plan，LIB 无 effective target 仍可测，不造新状态、不拆 artifact plan）；CONTEXT.md 当场落地——新增 8 词条（Test command、Test block、Test discovery、Testing、Test driver、Target directory、Transpile、View）+ 新节「Test language」，修订 7 处、删 Result directory、Relationships 新增 7 行并改写 3 行；定名 Test driver（否决 runner）；LIB 可测不写 ADR。
- [转译产物排版与 golden 基线](0011-transpiled-output-formatting-and-golden.md): token 锚定编辑点（多行 test 头/同行混排 `#load` 拒绝）、占位注释带该行原文、`@test` 贴 `}` 后于尾随 trivia、生成行保前导空白、无 EOF 尾注、输出统一 `\n`；**build 剥离同守 1:1 行号保真**（「删 test block」= 语义删除、等行数注释占位，0008/ADR 0004 附勘误；0004 附签名勘误）；driver 四参数化点 + `#run` 块首行注入 `Testing.path_mapping`；golden 三矩阵落 `tests/data/transpile/` + `<abs>` 占位 + `JUICE_UPDATE_GOLDEN` 重写；[ADR 0005 视图行号保真](../docs/adr/0005-view-line-fidelity.md) + [转译产物排版规范](../docs/transpiled-output-formatting.md) 成文。
- [Juice 自身测试迁移步骤与文件组织](0012-juice-own-test-migration.md): Juice 补 BIN package.jai（target src/main.jai）自测（否决 LIB 伪造入口 / 无 manifest 模式）；discovery 排除集加 root 的 `tests/data/` 与 `modules/`（0003 勘误 + CONTEXT.md 更新）；现有 53 测试 1:1 全迁单轨（seam 适配器天然相容，编译期 fs IO 为验证项）；tests/ 独立文件就地转 test block（删 main/run_test/`#load` 列表）；四步自举（旧 harness 参数化开发转译器 → juice test E2E → 迁移 → 同提交退役）；计划即本票 Resolution。

## Not yet specified

（无——全部已知待决均已建票并关闭，地图完成。原雾项「Testing 失败报告的确切措辞与格式」已由 [诊断与位置映射](0009-diagnostics-and-location-mapping.md) 决议 4 收口。）

## Out of scope

- 并行测试执行。
- 崩溃隔离（子进程/信号捕获使崩溃后继续跑）——崩溃即 runner 终止，余下测试不执行。
- 类型声明体内的 test block（Zig 容器式）——Jai 无容器语义，文件顶层已覆盖。
- workspace-wide 测试模式（root package 一次跑全部 member 的测试）——member 以自身为 root 跑测试，所有权清晰；如需 workspace 聚合是独立 effort。
- 集成测试（链接/启动 artifact 的测试）——与单元测试是两个目的地。
- 参数化/表驱动测试、mock 框架。
- 通用语法扩展框架：转译器只为 test block 服务，不承诺可扩展到 lambda/错误处理等任意语法（那是独立 effort，研究已在 syntax-transpiler.md）。
- 编辑器/LSP 集成。
