# Juice CLI 架构改进总结

## 实现的功能

基于 Rust `linkme` 库的分布式注册理念，为 Juice CLI 实现了静态命令注册与调度系统。

### 核心改进

1. **静态命令注册表**
   - 所有命令在 `src/commands/registry.jai` 中显式声明
   - 每个命令定义名称、描述、用法、前置依赖和处理函数
   - 使用 Jai 的静态数组字面量语法：`Command.[...]`

2. **智能命令调度**
   - 启动时验证注册表（重复名称、缺失前置、循环依赖）
   - 前置依赖图自动遍历
   - 单次调度内每个命令最多执行一次（缓存成功结果）
   - 前置失败立即终止执行链

3. **命令特定准备逻辑**
   - `clean` 不再加载 manifest 或解析依赖
   - `build`、`run` 和 `test` 经 workspace 模块的一次幂等调用（`ensure_workspace_prepared`）消费 prepared workspace
   - 未知命令在 workspace 准备前被拒绝

### 执行依赖图

```
run → build
build / run / test → ensure_workspace_prepared（幂等，不作为 command 注册）
clean → 自身 handler 内 discovery
```

### 关键设计选择

- **显式注册 vs 链接器魔法**：使用 Jai 的 `#load` 和静态数组，而非平台相关的链接器段机制
- **workspace 准备不作为 command**：registry 只收录可执行 command；准备是 workspace 模块的一次幂等调用（票 0040）
- **职责分离**：handler 返回 `bool`，main 负责 `exit(1)`
- **参数所有权**：每个命令只解析命令名后的参数

## 文件结构

```
src/
├── commands/
│   ├── command.jai      # 共享类型定义
│   ├── registry.jai     # 静态命令注册表（仅可执行 command）
│   ├── build.jai        # 构建所有 target
│   ├── run.jai          # 构建并运行 target
│   ├── clean.jai        # 清理输出（无 manifest 依赖）
│   └── test.jai         # 测试命令（test block 发现、转译与测试程序生成）
├── dispatcher.jai       # 注册表验证、查找和图遍历
└── main.jai            # 简化为驱动器初始化和调度调用

tests/
├── data/               # fixture 包与 golden 基线（测试块已内联 src 实现旁）
├── test_monorepo.jai   # monorepo E2E（2026-10-14 用户修订）
├── transpile_tests.jai / transpile_front_tests.jai / metaprogram_tests.jai
│                       # test-free 模块的单元测试（测试组织规则，票 0053）
└── test_support.jai    # 测试共享声明（组织决议 0027）

CONTEXT.md              # 领域术语定义
IMPLEMENTATION.md       # 实现细节文档
```

## monorepo（workspace member）测试覆盖（地图 0041）

为 workspace member 体系补齐测试矩阵（`tests/data/workspace-*` fixture 家族，票 0042-0048；E2E 测试集中 `tests/test_monorepo.jai`，2026-10-14 用户修订）：

- **discovery 校验矩阵**（票 0043）：全部可达失败分支经真实 `juice.exe` E2E 断言具体错误消息；路径有效性门槛进程内直测；junction 用例运行时制造。两个防御分支经声明路径不可达，记录不测。
- **build E2E**（票 0044）：root 依赖两 member → shim link（非 fetch）指向两种布局的导入入口 → 构建 → artifact 运行调用两 member 函数；root 闭包 test-free 零转译。
- **clean E2E**（票 0045）：root+member 的 `target/` 整目录递归删除、源文件保留、无 target 的 member 不失败。
- **test E2E**（票 0046）：root 测试程序经 shim import member 并断言成员函数；member 自带测试不随 root 运行。
- **缺陷修复**（票 0048）：测试暴露 test 编译缺 `target/packages` import 路径——root 测试程序此前无法 `#import` 任何依赖。`compiler_import_directories` 移入 `src/dependency.jai`，build 与 test 共用。
- **边界行为钉住**：root 自列 `.` 为 member → duplicate 错误；member 再声明 members → 静默忽略（CONTEXT.md Workspace member 词条已补事实）。

## 验证结果

✅ 编译成功  
✅ 所有单元测试通过（158 passed, 0 failed）  
✅ `clean` 在没有 `package.jai` 的目录中正常工作  
✅ 未知命令在准备前被正确拒绝  
✅ 用法消息从注册表自动生成  
✅ monorepo 矩阵全绿（discovery 校验、build/clean/test E2E）  

## Jai 特定约束

- `context` 是保留关键字，所有参数使用 `ctx`
- 空类型数组语法：`string.[]`
- 函数指针类型：`Handler :: #type (ctx: *T, args: [] string) -> bool;`
- 静态结构体数组：`REGISTRY :: Command.[.{...}, .{...}];`

## 与 Rust linkme 的对比

| 特性 | Rust linkme | Juice 实现 |
|------|-------------|-----------|
| 注册机制 | 链接器段 + 宏 | 静态数组字面量 |
| 分布式声明 | ✓ 跨 crate | ✓ 跨文件（通过 #load） |
| 运行时开销 | 段迭代 | 数组迭代 |
| 平台依赖 | 高（需处理多种目标格式） | 低（纯语言特性） |
| 顺序保证 | 依赖链接器 | 显式数组顺序 |

## 后续可能改进

- 添加与真实 Jai package 的集成测试
- 修复帮助输出中的格式宽度问题（`-12` 后缀）
- 考虑为插件系统添加运行时命令注册
- 为命令添加更丰富的参数解析支持

分支：`feat/command-registry`  
提交：`35771f3`
