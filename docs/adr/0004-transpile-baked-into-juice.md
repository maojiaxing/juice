# 0004: 转译内建于 juice 编译路径——build 探测剥离 + 进程内库

test block 不是合法 Jai：含内嵌 test 的源文件直接交 jai 必报错，而内嵌测试是已定的合法形态（0003/0004 号票）。转译由此成为 juice 的**编译前置义务**，不是可选工具；构建含测试语法的包不能要求用户手工剥离。

**决定**：

1. **探测后剥离**：build 从 effective target 的入口文件出发，沿**字面量 in-package `#load` 的传递闭包**探测；闭包任一文件含 test block 才转译，生成「剥离视图」（删 test block、in-package `#load` 重写为指向视图的绝对路径），jai 编译视图；test-free 闭包**零转译零缓存、原样直编**。test block 的存在只改变 build 的编译输入选择，不改变产物语义；run 经 build 继承，LIB build 不编译故无转译。
2. **闭包全有全无**：闭包内任一文件含 test，整个闭包视图化（test-free 文件视图 = 原文 + load 重写）；不做混合原文/视图的加载图。
3. **进程内库**：转译器是链进 juice 的单入口纯函数（源文本 + 上下文 → 视图文本 + 测试清单 + 诊断），不独立 CLI（通用语法转译已出范围；子进程开销、版本偏差、额外分发对内置特性是纯成本）。lexer/parser 按局部解析策略（锚点级，非完整 Jai 语法）。
4. **边界**：非字面量 `#load` 与 out-of-package `#load` 的目标不转译、不改写；目标含 test block 由 jai 编译错误自然暴露。test block 保证生效的范围 = 字面量 in-package `#load` 可达（build 闭包）/ 全包发现（test）的文件。
5. **缓存**：`target/transpile/` 内容寻址（键 = hash(package 相对路径 + 源内容 + 模式 build/test + juice 版本)，hash 目录内镜像相对结构防撞名）；build 视图的 load 重写指向目标视图路径，键构成 Merkle 链。driver / first.jai 每次生成写入，不缓存。
6. **seam**：转译是 command 编排层的前置步骤，与 compile seam 平级、形参注入可替换（集成测试用假实现）；build 与 test 各有前置，转译器库本体跨命令共享。

**Considered Options**: (a) 无条件转译（build 永远视图化全闭包）——否决：零测试包常态付转译成本，「编译的是缓存不是你的源文件」心智常态化；(b) 不兜底、透传 jai 报错——否决：实质废掉内嵌测试，与已定决议冲突；(c) 独立子进程 CLI 转译器（syntax-transpiler 研究的建议）——否决：那是通用转译器视角，对 test-only 内置特性是纯成本，将来做通用转译器再抽出。

**Consequences**: 合法 test 语法从此依赖转译存在，删掉转译器即删掉语言特性；产物诊断指向缓存视图路径，位置映射归 0009 号票；视图排版规范与 golden 基线归 0011 号票。

**修订**（2026-10-13，[ADR 0005](0005-view-line-fidelity.md)）：决定 1 的「删 test block」物理形态细化为等行数注释占位——test block 语义删除（不再进入编译）不变，剥离视图与测试视图共享行号保真（1:1）不变量。
