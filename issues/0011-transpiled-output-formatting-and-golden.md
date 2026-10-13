---
title: 转译产物排版与 golden 基线
status: closed
labels: [wayfinder:grilling]
assignee: maojiaxing
blocked-by: [0008-transpile-integration-and-cache.md]
---

## Question

产物形态已定（[测试构建代码组织](0007-test-build-organization.md)：视图 + driver + first.jai；[转译集成与缓存架构](0008-transpile-integration-and-cache.md) 细化落点为 `target/transpile/` 内容寻址子树——键 = hash(相对路径 + 源内容 + 模式 + juice 版本)，hash 目录内镜像相对结构，driver/first.jai 每次生成写入不缓存），本票定它们的排版规范与测试基线：

- 视图排版：逐字保留区的边界规则；编辑点（`#load` 剥离、test 展开 `juice_test_N` + `@test`、匿名名 `路径:行号` 字符串）的具体排版——空行、缩进、生成物注释头；排版规范的目标（可读性 vs 行号保真度，与 诊断与位置映射 的联动）。
- driver / first.jai 的生成模板：参数化点（视图清单、测试清单、Testing 模块路径、绝对路径注入）与稳定性（golden 可对比）。
- golden 基线：fixture 组织（对齐 syntax-transpiler.md 的 golden + 负例 + 编译运行三矩阵）、基线文件放哪（tests/data 下？）、排版规范演进时基线如何更新。

> 补充输入（2026-10-13，[诊断与位置映射](0009-diagnostics-and-location-mapping.md) 决议后）：排版规范以**行号保真**为硬约束（视图行 = 原文件行；可读性让位）——本票「排版规范的目标（可读性 vs 行号保真度）」子问题已由 0009 决议 1 解答，不再重议。编辑细则见 0009 决议 5（剥离的 `#load` 行 = 等行数单行注释占位、`@test` 附闭括号同行、视图禁头部注释、可选 EOF 尾注标记由本票定夺、列保真仅承诺逐字区）。《视图行号保真》ADR 与排版规范在本票 session 一起成文（0009 决议 6）。driver 内「视图↔原路径」映射表是编译期数据，golden 一并锁定。

## Resolution

（2026-10-13 grilling 两轮 10 问，票主逐条全按推荐拍板；成文产物 [ADR 0005 《视图行号保真》](../docs/adr/0005-view-line-fidelity.md) + [转译产物排版规范](../docs/transpiled-output-formatting.md)）

1. **边界规则 = token 锚定**：编辑点以 token 为界（test 头锚点序列整体替换、`}` 后插 `@test`、`#load` 整语句替换），同行其余内容一律逐字区；一行多测试与一行成块自然成立；**多行 test 头转译期拒绝**（1 行换 1 行不可行）。独占行要求：与他语句同行的 in-package `#load` 转译期拒绝。
2. **`#load` 占位注释带原文**：首行 `// juice: load stripped: <该行原文>`，语句跨 K>1 行余行 `// juice: load stripped (cont)`——原文是人工对照（0009 决议 3）的关键线索。适用范围 = 全部目标均字面量 in-package；混合/非字面量/out-of-package 语句整句不转译（0008 决议 4）。
3. **`@test` 贴闭括号后、尾随 trivia 前**：`}` → `} @test`；`} // c` → `} @test // c`。
4. **生成行保留原行前导空白**（test 头替换行、占位注释行）。
5. **EOF 尾注标记不做**：视图零额外行、严格 1:1，溯源只靠 driver 映射表；将来需要是可加性扩展。
6. **行尾统一 `\n`**：逐字保真的单位 = 行内容逐字节，行尾规范化；golden 字节稳定。
7. **driver 模板四参数化点**：视图清单（字典序 `#load` 全视图，每文件一次）/ 路径映射表 / 测试清单（pattern 过滤后，字典序 + 源码序）/ 执行收口（`if finish() != 0 assert(false)`）。映射表注入 = driver `#run` 块首行给 Testing 全局赋值 `Testing.path_mapping = .[...]`（Testing 增 `path_mapping : [..] Path_Pair` 可变全局，默认空数组——不注入即透传，0009 决议 2 中立性不破）。全部路径绝对、Jai 字符串转义。
8. **golden 基线组织**：`tests/data/transpile/` 三矩阵——`golden/<case>/`（输入 `*.jai` → 期望 `X.view.jai` + `driver.jai` + `first.jai`，逐字节对比）、`negative/<case>/`（→ 期望 `diagnostic.txt` + 非零退出）、`run/<case>/`（包级 fixture 编译运行，对齐 tests/data/bin-package 形态）。绝对路径用 `<abs>` 占位规范化后对比；更新开关 = 环境变量 `JUICE_UPDATE_GOLDEN`（任意非空即重写基线，CI 永不设置）。
9. **成文落点 = ADR + 独立规范**：[ADR 0005](../docs/adr/0005-view-line-fidelity.md) 记决策与原则（行号保真硬约束、逐字区/编辑点划分、build 剥离同保行、golden 为锁定机制），精确排版规则落 [docs/transpiled-output-formatting.md](../docs/transpiled-output-formatting.md)，ADR 链接之。
10. **build 剥离同守行号保真**（跨票张力收口）：0008 决议 1「删 test block」= **语义删除**，物理形态为等行数注释占位（首行 `// juice: test stripped: <该行原文>`、余行 `// juice: test stripped`），剥离视图与测试视图共享 1:1 不变量——0009 决议 1 的全量措辞与其决议 3 的行列承诺在 build 模式同样成立。[转译集成与缓存架构](0008-transpile-integration-and-cache.md) 与 ADR 0004 已附勘误；另 [test block 语言语义](0004-test-block-language-semantics.md) 附签名勘误（`() -> void` → `() -> ()`，0005 勘误与 0009 决议 1 已先行取代，本票成文收口）。

影响：无新票（本票为收口票，遗留实现期验证项已由 0009 决议 2 委托并写入规范 §4.4）；[Juice 自身测试迁移步骤与文件组织](0012-juice-own-test-migration.md) 解阻，成为 frontier。
