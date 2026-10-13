---
title: 研究：Jai 测试收集与构建机制
status: closed
labels: [wayfinder:research]
assignee: maojiaxing
blocked-by: []
---

## Question

为「测试构建代码组织：main 冲突与 runner 形态」提供机制事实：test block 转译为函数后，runner 如何发现并执行全部测试？查证并以最小实验验证以下路径：

1. **编译期注册**：转译产物在文件顶层用 `#run` 把 (name, proc) 注册进全局数组，runner 的 main 读取并遍历执行——验证 `#load` 链上多个文件的顶层 `#run` 执行顺序、全局数组跨文件共享、注册数组所需的 allocator/temp 生命周期。
2. **编译器 API / metaprogram 扫描**：Juice 生成 build 脚本，编译期遍历 program（Program_Info / 编译期消息）按名字模式或注记收集测试函数并生成调用——查发行版 `modules/Compiler` 的可用 API 与 how_to 先例（如 `#program_export`、constant 遍历）。
3. **社区与发行版先例**：发行版 how_to/modules 里是否已有测试框架或收集模式；社区库（如 testify）的机制。

事实落点：`docs/research/` 下新增报告，遵循仓库惯例（一手来源 + 【实验】/【源码】/【推断】标注，行号引用）。

## Resolution

三条路径结论（详见 [docs/research/test-collection-mechanisms.md](../docs/research/test-collection-mechanisms.md)）：

- **编译期 `#run` 注册：实验判死**——编译期对可变全局的修改不持久化到运行期（`registered_count` 运行期初值为 0）；且编译期 `#run` 执行顺序为逆 `#load` 序，非源码序。
- **metaprogram 扫描：对 Juice 冗余**——扫描发生在转译之后，只能扫到 Juice 自己生成的函数，信息无增量。
- **先例：gs_test 源码级验证**运行期过程值数组注册 + 文件扫描发现 + 聚合退出码；单 runner 须处理 `#load` 去重。**发行版新发现**：`} @test` 过程尾注记（8 处）是进行中的官方测试约定，框架未 formalize、无消费方——转译产物建议带 `@test` 注记与官方未来方向对齐（零成本）。

**推荐 MVP**：转译期枚举测试 + runner 显式顺序调用 + 失败汇总退出码；运行期过程值数组作后备。
