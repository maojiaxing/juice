# 转译产物排版规范（测试视图 / driver / first.jai）

> 规范对象：juice 转译器（进程内库，ADR 0004）在 test（展开）与 build（剥离）两种模式下生成的全部产物。硬约束：[ADR 0005 《视图行号保真》](adr/0005-view-line-fidelity.md)——任何视图的行数与原文件严格一致，可读性让位。本规范的全部细则由 golden 基线逐字节锁定（§4），演进流程见 §5。
>
> 上游决策：产物形态（0007 号票）、落点与缓存（0008 号票 / ADR 0003/0004）、诊断与坐标（0009 号票）、语言语义（0004 号票）、Testing API（0005 号票）。

## 1. 视图排版

### 1.1 总则

- **行号保真**：视图行数 = 原文件行数，无例外、两种模式同。任何编辑以「1 行换 1 行」为单位；无法等行数展开的输入形态在转译期拒绝并给精确诊断。
- **行尾**：输出统一 `\n`。逐字保真的单位是「行内容逐字节」，行尾规范化不属于逐字承诺。
- **逐字区与编辑点**：除编辑点外的全部文本逐字保留——含注释、空白、token 间 trivia、空行。编辑点以 token 为界：替换/插入只发生在锚点 token 上，同行其余内容一律属于逐字区。
- **无注记**：视图禁止头部/尾部注记；溯源元数据只在 driver 映射表（§2）。
- **生成行保留原行前导空白**：test 头替换行与占位注释行复制原行前导空白，文本自其之后起写。
- **`juice_test_` 前缀保留**：归转译器；用户符号撞前缀由 jai 重定义错误自然暴露，MVP 不规避。

### 1.2 test block 展开（test 模式）

锚点（0004 决议 6）：文件顶层语句位置的 `test` + 字符串字面量 + `{`，或 `test` + `{`。字符串/注释中的 `test` 文本免疫（完整 lexer）。

- **头行替换**：锚点 token 序列整体替换为 `juice_test_N :: () -> () {`（N = 全包测试清单序号：文件按发现字典序、文件内按源码序编号，0007 决议 3）。行内 `{` 之后的其余文本逐字保留（一行成块 `test "x" { body }` 成立）；前导空白保留（1.1）。
- **多行 test 头拒绝**：锚点 token 序列跨行（`test` 与字符串或 `{` 不在同一行）即转译期拒绝，诊断精确指向 `test` 起始位置。
- **体**：逐字区，含缩进与空行。
- **闭括号**：`}` 后插入 ` @test`，紧贴闭括号 token、尾随 trivia 之前：`}` → `} @test`；`} // c` → `} @test // c`。
- **命名测试的 name**：原样复用源 token 文本（已是合法 Jai 字符串字面量）。
- **匿名测试的 name**：转译期静态生成 `package 相对路径:行号`（`/` 分隔，行号为原文件行号，0004 决议 5）；生成的字符串字面量按 Jai 转义规则转义 `\`、`"` 与不可打印字符。
- **`#import` 与 out-of-package `#load`**：原样保留（0008 决议 4）。
- **in-package `#load` 剥离**：见 1.3。

### 1.3 in-package `#load` 剥离（test 模式）

- **适用范围**：全部目标均为字面量 in-package 的 `#load` 语句；含非字面量或 out-of-package 目标的语句整句不转译、原文保留（0008 决议 4）。
- **占位形态**：语句占 K 行 → K 行单行注释占位（0009 决议 5）：
  - 首行：`// juice: load stripped: <该行原文>`
  - 余行（K>1）：`// juice: load stripped (cont)`
  - 保留原行前导空白（1.1）。
- **独占行要求**：被剥离语句必须独占其行（同行首尾无其他 token）；与他语句同行的 `#load` 转译期拒绝（占位注释会吞掉同行其余内容）。

### 1.4 test block 剥离（build 模式）

- **语义删除、物理占位**（ADR 0005 决定 3，修订 0008/ADR 0004 的物理形态）：test block 的每一行替换为等行数注释占位：
  - 首行：`// juice: test stripped: <该行原文>`
  - 余行：`// juice: test stripped`
  - 保留原行前导空白。
- **in-package `#load` 重写**（不剥离）：目标字符串字面量 token 替换为指向目标视图的绝对路径（Merkle 键链，0008 决议 5），按 Jai 字符串转义规则转义；同行其余内容逐字。1 行换 1 行（字符串字面量不跨行）。
- test-free 文件在闭包内也生成视图：原文 + load 重写，无其他编辑（0008 决议 2 闭包全有全无）。

## 2. driver 模板

driver = 无入口点的生成文件（0007 决议 3），每次生成写入 `target/transpile/<hash>/`，不缓存（0008 决议 5）。骨架固定，四个参数化点（视图清单、路径映射表、测试清单、执行收口）：

```jai
// 参数化点 1：视图清单——发现的全部 package 文件恰一次，字典序，绝对路径
#load "<abs>/target/transpile/<hash>/src/foo.jai";
#load "<abs>/target/transpile/<hash>/src/bar.jai";

#import "Testing";

#run {
    // 参数化点 2：路径映射表——执行清单之前注入（0009 决议 2）
    Testing.path_mapping = .[
        .{ view = "<abs>/target/transpile/<hash>/src/foo.jai", original = "src/foo.jai" },
        .{ view = "<abs>/target/transpile/<hash>/src/bar.jai", original = "src/bar.jai" },
    ];
    // 参数化点 3：测试清单——pattern 过滤后的命中集合，字典序 + 源码序（0007 决议 3）
    run("test name", juice_test_1);
    run("src/foo.jai:12", juice_test_2);
    // 参数化点 4：收口——失败数非零强制编译错误（E7b 通道）→ jai 退出码
    if finish() != 0 assert(false);
}
```

- **Testing 全局**：Testing 模块增加可变全局 `path_mapping : [..] Path_Pair`（`Path_Pair :: { view: string; original: string; }`，默认空数组——不注入即透传，0009 决议 2）。Testing 打印失败位置时按表精确匹配改写路径（查无匹配原样输出）。
- **确定性**：清单、映射表、编号全部由字典序派生，生成内容只依赖输入与 juice 版本，golden 可逐字节锁定。
- **路径与转义**：全部路径为绝对路径（E9 验证），`\`、`"` 按 Jai 字符串转义。
- **空清单**：零命中不生成 driver（跳过编译，0006 决议）。

## 3. first.jai 模板

metaprogram 包装（形态照 how_to/450，0007 决议 4），每次生成写入、不缓存：

- `output_type = .NO_OUTPUT`；`set_build_options_dc(.{do_output=false})` 使 metaprogram 自身无入口。
- **参数化点 A**：`import_path` 注入 Testing 模块目录（绝对路径）——复制到动态数组追加后回写。
- **参数化点 B**：`compiler_begin_intercept` 之后 `add_build_file` driver（绝对路径）。
- 消息循环以 `.COMPLETE` 退出。

## 4. golden 基线

对齐 syntax-transpiler.md 8.2 测试矩阵（golden / 负例 / 编译及运行三类；错误处理特性专属的求值次数、errdefer 等行不适用）。

### 4.1 fixture 布局：`tests/data/transpile/`

- `golden/<case>/`：输入 = case 目录内全部 `*.jai`（单文件或多文件）。期望文件：每输入 `X.jai` 的视图 → `X.view.jai`；driver → `driver.jai`；first.jai → `first.jai`。全部逐字节对比。
- `negative/<case>/`：输入 `*.jai` → 期望转译期诊断文本 `diagnostic.txt`（逐字节对比）+ 退出码非零。
- `run/<case>/`：包级 fixture（对齐 tests/data/bin-package 形态的完整 package 目录），编译运行矩阵——jai 编译运行视图/端到端 `juice test`，断言退出码与输出（不做全量输出 golden）。

### 4.2 绝对路径规范化

期望文件中的绝对路径前缀写作占位符 `<abs>`；比对前测试 harness 将实际输出的绝对路径前缀（盘符 + 仓库根）统一替换为 `<abs>` 后逐字节对比。杜绝机器相关漂移。

### 4.3 更新开关

环境变量 `JUICE_UPDATE_GOLDEN` 置任意非空值 → harness 重写期望文件（golden 与 negative）而非比对；未设置时逐字节比对，失败打印 diff、非零退出。CI 永不设置该变量。

### 4.4 实现期验证项（0009 决议 2 委托，spec 写明）

`#caller_location` 的 `file` 串是否与 driver `#load` 传入的路径串逐字符一致；若不一致，路径改写的退化策略 = 前缀 + 后缀匹配。

## 5. 规范演进流程

排版规范变更（有意为之）：先修订本规范与 ADR（如需）→ 以 `JUICE_UPDATE_GOLDEN` 重写受影响基线 → 人工审阅 diff 后连同变更一起入库。golden 基线的变更即为规范变更的证据，禁止仅改基线不改规范。
