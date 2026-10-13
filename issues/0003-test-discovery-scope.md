---
title: 测试发现范围规则
status: closed
labels: [wayfinder:grilling]
assignee: maojiaxing
blocked-by: []
---

## Question

「扫描 package 内所有 `.jai`」的精确规则：

- 扫描递归吗？从 package root 全量递归？
- 排除哪些路径：`result/`、`.packages/`、`.build/`、`bin/`、点开头目录、约定测试目录之外的约定？
- member package 的 `.jai` 文件是否被 root package 的 test 扫描（member 边界）？member 是否通过以它为 root 跑自己的测试？
- 被依赖方（`.packages/` 中非 Juice package 的普通模块）里的 test block 算谁的、要不要跑？
- 扫描发现与 workspace discovery 的关系：复用同一份 member/member-declaration 快照，还是独立扫描？

## Resolution

（2026-10-13 grilling 敲定，六项决议）

1. **递归范围**：从 package root 全量递归，无源码目录白名单——`src/`、`tests/`、`examples/`、根下 `module.jai` 等自动覆盖；可预测性由排除规则承担。
2. **排除规则（最小集）**：
   - 点开头条目（目录与文件）一概不进——天然覆盖 `.git`、`.packages`、`.claude` 及未来 Juice 缓存目录。
   - 仅排除 package root 的 `result/`；不排除任意深度同名目录（用户的 `src/result/` 是用户代码）。
   - `package.jai` 不作为测试源（仅指各 package root 的 manifest；子目录中碰巧同名的源文件仍被扫描）。
   - 不跟随任何符号链接（目录与文件）：防环、防逃逸 package root，与 path_safety 姿态一致。
   - 仅小写 `.jai` 扩展名。
   - 不特判 `bin/` 与其他业务目录（bin 不是 Juice 管理目录，CONTEXT.md 既有语义）。
3. **member 边界**：root 扫描不进 member 子树；member 以自身为 package root 跑自己的测试（`cd member && juice test`，现有"工作目录即 package root"规则天然支持，无新 flag）。workspace-wide 模式（cargo `--workspace` 式）为未来选项，不进 MVP。
4. **依赖中的 test block**：不发现、不跑——`juice test` 测当前 package 不测依赖（cargo/zig 同语义），`.packages` 已被点开头规则排除。依赖源含 test block 未经转译直接编译报错的兜底问题归 [转译集成与缓存架构](0008-transpile-integration-and-cache.md)。
5. **与 workspace discovery 的关系**：分层——discovery 快照提供 member 清单与路径（管"哪些 package 存在"），test 扫描消费该快照决定排除哪些子树（管"哪些文件是测试源"）；文件遍历是 test 特有扫描，**不并入** workspace discovery（其语义是 manifest 执行，Clean 也消费）。
6. **扫描顺序**：确定性——目录内条目按名称字典序，先当前目录文件、再递归子目录；转译期枚举顺序、runner 调用顺序与报告顺序均由扫描顺序派生（利于 diff 输出与转译产物 golden 基线）。

ADR 判断：各项均可逆（排除集可扩、member 边界可加 flag），不满足"难逆 + 无上下文会困惑 + 真权衡"三条件，不写 ADR；模型层词汇（Test discovery 等）与 CONTEXT.md 修订统一在 [workspace 模型与词汇修订](0010-workspace-model-and-glossary.md) 收口。

## 勘误

（2026-10-13，[转译集成与缓存架构](0008-transpile-integration-and-cache.md) 定案后）排除规则第 2 条修订：「仅排除 package root 的 `result/`」→「仅排除 package root 的 `target/`」——`target/` 是 Juice 管理的生成物目录（[ADR 0003](../docs/adr/0003-unified-target-directory.md)），内含转译视图等生成 `.jai`，不排除会把生成物当测试源。`result/` 不再特判（遗留目录，沿 `bin/` 先例不管）。点开头条目规则不变（`.packages` 已随目录迁入 `target/packages/`，天然被覆盖）。

（2026-10-13，[Juice 自身测试迁移步骤与文件组织](0012-juice-own-test-migration.md) 定案后）排除规则第 2 条再修订：增加「仅排除 package root 的 `tests/data/` 与 `modules/`」——`tests/data/` 是测试 fixture 约定目录（含转译负例等非法测试语法文件，进测试程序会破坏转译），`modules/` 是模块目录（`#import` 源而非测试源，入扫描只是冗余视图）。与 `target/` 同先例：仅 root 一级，不排除任意深度同名目录。
