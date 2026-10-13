---
title: test block 语言语义
status: closed
labels: [wayfinder:grilling]
assignee: maojiaxing
blocked-by: []
---

## Question

test block 的语言语义边界：

- 位置约束：仅允许文件顶层（函数内出现即转译期拒绝）？
- 块体即过程体：可声明局部、可 `defer`；能 `return` 吗（无返回值语义）？签名是 `() -> void` 还是可携带失败信息（与 Testing 断言模块 API 联动）？
- 可见性：可访问同文件顶层符号与全局（Zig 语义，已定）；跨文件符号通过所在文件已有的 `#import`/`#load` 可见？
- 同名测试：允许共存还是报错？
- 匿名块 `test { ... }` 的报告名（建议 `文件名:行号`）。
- 词法锚点：顶层 `test` 标识符后跟字符串或 `{`；用户已声明名为 `test` 的过程/变量时如何消歧（报错、遮蔽规则、还是诊断提示）？

## Resolution

（2026-10-13 grilling 敲定，七项决议）

1. **位置约束**：仅文件顶层。函数体内与类型声明（struct/enum）体内出现 `test` 锚点即转译期拒绝，给精确位置诊断（"test block 仅允许文件顶层"），不生成代码让 jai 报错。类型内 test 是 Zig 容器语义，Jai 无对应概念，不引入。
2. **签名与块体**：签名锁定 `() -> void`（转译产物 `juice_test_N :: () {...}`，带 `@test` 注记，见研究票 0002）；**失败不走返回值通道，由 Testing 模块全局登记**——为 [Testing 断言模块 API](0005-testing-assertion-module-api.md) 划界：失败传播机制在全局登记基础上设计，不碰测试签名。局部声明与 `defer` 允许（普通过程体，天然支持）。裸 `return` 允许 = 提前结束该测试，已登记失败不丢失（语义同 Zig"提前 return 即通过到当前点"）；带值 `return` 转译期拒绝（诊断：test block 无返回值）。
3. **可见性**：等于**所在文件顶层的可见性**——本文件顶层符号、`#load` 链共享的全局作用域符号、本文件 `#import` 的模块符号；这是"同文件顶层过程"lowering 的自然结果，零额外机制。独立测试文件如何拿到被测代码（相对 `#load` vs 约定注入）归 [测试构建代码组织](0007-test-build-organization.md)。
4. **同名测试**：允许共存，转译期不查重（产物按编号命名无冲突；Zig 同样允许同名）。`juice test <pattern>` 同名全命中；报告仅在撞名时自动附加 package 相对路径消歧，平时保持裸名字。
5. **报告名**：匿名 `test { }` 的报告名 = **package 相对路径:行号**（如 `src/foo.jai:12`，转译期静态生成）；命名测试 = 裸名字。失败详情中的位置定位归 [诊断与位置映射](0009-diagnostics-and-location-mapping.md)。
6. **词法锚点**：仅 token 级两种形态在**顶层语句位置**接管——`test` + 字符串字面量 + `{`，或 `test` + `{`。字符串/注释中的 `test` 文本免疫（完整 lexer，非正则）。其余一切 `test` 用法（`test :: ...`、`test(x)`、`x := test`、`test;`）原样透传，不归 Juice 管。接管形态都不是合法 Jai、透传形态不会命中锚点——两类互斥无歧义，用户声明名为 `test` 的符号不受任何影响，无需遮蔽规则。
7. **崩溃语义**：崩溃式失败（裸 `assert`、空指针、越界）与 Testing 登记式失败是两条通道。MVP 明确接受：**测试体内崩溃即 runner 进程终止**，后续测试不执行，非零退出码，报告说明"runner 于测试 X 崩溃，余下 N 个未执行"。不做子进程隔离/信号捕获；spec 明示该边界，引导用户用 Testing 断言替代裸 `assert` 写测试。

ADR 判断：各项均可逆或可加性扩展（struct 内 test、崩溃隔离都可作为未来增量），不满足三条件，不写 ADR；Test block 词条收口归 [workspace 模型与词汇修订](0010-workspace-model-and-glossary.md)。

勘误（2026-10-13，[test 命令 CLI 语义](0006-test-command-cli-semantics.md) 修订）：第 7 条"报告说明'runner 于测试 X 崩溃，余下 N 个未执行'"的措辞承诺放宽——崩溃点由 Testing 每测试开始行人眼归因，juice 只输出崩溃错误行，不解析 stdout、不承诺精确余下数；崩溃即终止的语义本身不变。

勘误（2026-10-13，[测试构建代码组织](0007-test-build-organization.md)）：第 7 条崩溃语义的载体由「runner 进程」改为「编译器进程」（测试编译期执行）；「崩溃即终止、余下不执行、非零退出码」语义不变，报告形态见 [test 命令 CLI 语义](0006-test-command-cli-semantics.md) 勘误。

勘误（2026-10-13，[转译产物排版与 golden 基线](0011-transpiled-output-formatting-and-golden.md) 成文收口）：第 2 条签名 `() -> void` 与产物 `juice_test_N :: () {...}` 已被 [Testing 断言模块 API](0005-testing-assertion-module-api.md) 勘误（`run` 参数 `() -> ()`）与 [诊断与位置映射](0009-diagnostics-and-location-mapping.md) 决议 1 取代——视图产物签名 `juice_test_N :: () -> () {`，规范见 [docs/transpiled-output-formatting.md](../docs/transpiled-output-formatting.md)。
