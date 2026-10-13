---
title: 转译集成与缓存架构
status: closed
labels: [wayfinder:grilling]
assignee: maojiaxing
blocked-by: [0007-test-build-organization.md]
---

## Question

转译器在 juice 管线中的位置与缓存（预期产出 ADR）：

- 所有过 juice 的编译是否先探测"源文件含 test block"再决定转译（build 剥离、test 展开）？直接 `jai` 编译含 test block 的文件会报错，juice 有没有义务兜底？
- 缓存：键（源内容 hash？）、位置（挂 `Build_Driver.cache_dir`？）、失效策略。
- 转译器形态：juice 进程内库，还是独立子进程 CLI（syntax-transpiler.md 建议独立 CLI + juice 前置步骤，但那是通用转译器视角；test-only 内置是否更简）？
- build / run / test 共享同一条转译路径的契约（compile seam 前置步骤的接口形状）。
- 符合 ADR 三条件（难逆、无上下文会困惑、真权衡）则写 docs/adr/。

> 补充输入（2026-10-13，[测试构建代码组织](0007-test-build-organization.md) 决议后）：test 构建的生成物是 视图 + driver（`#run` 清单，失败强制编译错误）+ first.jai（NO_OUTPUT metaprogram，`import_path` 注入 Testing），juice 调 `jai first.jai`；build（剥离 test）仍走 plain CLI。缓存对象与失效键需覆盖两类生成物；非字面量 `#load` 目标与 out-of-package 目标含 test 语法的边界归本票收口。

## Resolution

（2026-10-13 grilling 两轮 12 问，票主逐条拍板；其中缓存位置票主改为 cargo 式统一目录，推翻推荐的用户级方案）

1. **build 兜底 = 探测后剥离**：build 从 effective target 入口沿**字面量 in-package `#load` 的传递闭包**探测；闭包任一文件含 test block 才走转译，jai 编译「剥离视图」（删 test block、in-package `#load` 重写为指向视图的绝对路径）；test-free 闭包**零转译零缓存、原样直编**。test block 只改变 build 的编译输入选择，不改变产物语义；run 经 build 继承；LIB build 不编译、无转译。
2. **视图化单位 = 闭包全有全无**：闭包任一文件含 test，整个闭包视图化（test-free 文件视图 = 原文 + load 重写）；不做混合原文/视图加载图。循环 `#load` 若 jai 接受则转译器报「循环加载无法重写路径」（预期 jai 自身拒绝）。
3. **转译器 = juice 进程内库**：单入口纯函数（源文本 + 上下文 → 视图文本 + 测试清单 + 诊断），链进 juice；不独立 CLI。lexer/parser 按研究文档局部解析策略（锚点级，非完整 Jai 语法）。
4. **非字面量与 out-of-package `#load` 不转译**：语句原文保留、目标不改写；目标含 test block 由 jai 编译错误自然暴露。spec 写明支持边界：**test block 保证生效范围 = 字面量 in-package `#load` 可达（build）/ 全包发现（test）的文件**。
5. **统一 cargo 式 `target/` 目录**（票主修订；[ADR 0003](../docs/adr/0003-unified-target-directory.md)）：
   - `<package_root>/target/` 取代 `result/` 与 `.packages`：artifact 直落 target/ 根（无 profile）；依赖 import shim 落 `target/packages/`（`-import_dir` 指向）；转译生成物落 `target/transpile/`。旧 `result/`、`bin/` 遗留不管。
   - 转译缓存内容寻址：键 = hash(package 相对路径 + 源内容 + 模式 build/test + juice 版本)，hash 目录内镜像相对结构（0007 防撞名）；build 视图 load 重写指向目标视图路径 → 键为 Merkle 链，确定可算。driver / first.jai 每次生成写入本树，**不缓存**。
   - 失效：内容寻址天然失效；无 fingerprint/mtime（jai 无增量，纯负担）；无主动清理。
   - **Clean 改为递归删 root 与 member 的 `target/` 整目录**。
   - 用户级 XDG 缓存只留外部输入：git 源缓存（git_repos）与 manifest 求值临时文件（cargo `~/.cargo/registry` 对应物）。target/ 收容判据 = 可再生自 package 自身内容。
   - 撞词接受：目录名 `target/` 与 Target declaration 同名异义（Rust 同样共存），词条定名「Target directory」并写明区分。
   - 边界：jai 自身中间物（obj）能否随 `-output_path` 入 target/ 未验证；spec 只承诺 juice 管理的三类物，jai 中间物位置实现期一次实验定案。
6. **seam = command 编排层前置步骤**：`build_command` 在 compile seam 之前调可注入的转译前置（默认真实现形参，与 `build_prepared_workspace` 的 compile 参数模式同构）；test_command 有等价前置；转译器库本体跨命令共享。
7. **ADR**：[ADR 0003 统一 target/ 布局](../docs/adr/0003-unified-target-directory.md)、[ADR 0004 转译内建](../docs/adr/0004-transpile-baked-into-juice.md)。

**影响与修订**：

- 勘误（2026-10-13，[转译产物排版与 golden 基线](0011-transpiled-output-formatting-and-golden.md)）：决议 1 的「剥离视图（删 test block）」——「删」为**语义删除**（test block 不再进入编译），物理形态为等行数注释占位（`// juice: test stripped`）；剥离视图与测试视图共享行号保真（1:1）不变量。排版细则见 [docs/transpiled-output-formatting.md](../docs/transpiled-output-formatting.md)。
- [测试发现范围规则](0003-test-discovery-scope.md) 已附勘误：排除集「root 的 `result/`」→「root 的 `target/`」。
- 0007 决议第 5 条「落点：全部生成物在缓存目录」细化为 `target/transpile/`。
- [workspace 模型与词汇修订](0010-workspace-model-and-glossary.md) 范围扩大（Target directory 改名、Local dependency directory、Clean、转译/视图新词条）。
- [转译产物排版与 golden 基线](0011-transpiled-output-formatting-and-golden.md) 落点措辞更新。
- 地图 Not yet specified 的「Juice 自身测试迁移」毕业为 [0012](0012-juice-own-test-migration.md)。
