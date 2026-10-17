---
title: bootstrap 产物落点根治 + options 可测缝抽取
status: closed
labels: [ready-for-agent]
assignee: maojiaxing
blocked-by: []
---

> 父 spec：`issues/0054-spec-jaix-prestep-leftover-cleanup.md`（决定 1/2/3 + Testing Decisions 接缝 1/4）。

# 0055: bootstrap 产物落点根治 + options 可测缝抽取

**What to build:** `jai build.jai`（debug 与 `- release`）的产物直接落 target/juice.exe，target/target/ 不再出现；构建成功消息所指路径真实存在；验证循环不再需要 cp 晋升（058 偏差 ④ 根治）。实现面 = 与 Build 命令同构的绝对 output_path/intermediate_path（root 派生——子进程 jai 的 `#run` 期工作目录切到 metaprogram 所在目录，相对路径再解析一层是根因）；options 组装从 bootstrap 的 `#run` 抽为 Metaprogram 生成器模块的纯函数（bootstrap `#load` 目标、test-free；输入 = root/entry/testing_view_dir/is_release，输出 = 既有 options 类型），bootstrap 改为组装调用点。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] `jai build.jai` 产物落 target/juice.exe、target/target/ 不存在（debug 与 release 两遍）
- [x] options 组装纯函数入 Metaprogram 生成器模块；bootstrap `#run` 改为调用
- [x] metaprogram_tests 新块：临时 root 下 output_path/intermediate_path 绝对（root 派生 target/ 形状）
- [x] `./target/juice.exe test` 全绿（200 + 新增）、30 GOLDEN PASS 零重定
- [x] 验证循环清单删除 cp 晋升、新增直接落点检查

## Resolution

**bootstrap 产物落点根治 + options 可测缝抽取落地（2026-10-17），三路径全绿。**

### 实现摘要

1. **落点根治（058 偏差 ④）**：`src/metaprogram.jai` 新增纯函数 `bootstrap_compiler_metaprogram_options(root, entry, testing_view_dir, is_release) -> Compiler_Metaprogram_Options`——output_path 与 intermediate_path 以 `front_slashes(root) + "/target"` 派生为绝对路径（与 Build command 的 `plan.target_dir` 绝对先例同构），根治子进程 jai `#run` 期工作目录切到 metaprogram 所在目录（target/）导致的相对路径再解析一层（target/target/）。`front_slashes` 保证分隔符形状不依赖调用方风格（测试面以反斜杠 root 锁住）。其余字段与既有组装逐值同构（workspace_name "Juice Build"、executable_name "juice"、import_dirs = root/src, root/modules, root、build_file = entry、testing_view_dir 与 very_optimized 透传）。
2. **bootstrap 改为组装调用点**：`build.jai` 第 5 步的 options 逐字段组装替换为 `meta := bootstrap_compiler_metaprogram_options(root, entry, testing_view_dir, is_release);`——`make_directory`、meta_path、spawn 与成功消息文本（"Binary -> target/juice.exe"）全部不变（修复后消息名副其实）；头部注释与第 5 步注释同步。src/metaprogram.jai 仍为 bootstrap `#load` 目标、test-free。
3. **可测缝单测（tests/metaprogram_tests.jai 新 3 块）**：临时 root 下断言 output_path/intermediate_path 为 root 派生的绝对 target/ 形状（纯函数零文件系统访问，root 为路径字符串）；反斜杠 root 归一为前斜杠；release 标志与 testing_view_dir 透传、哨兵默认 "" 保持。测试计数 210 → 213（Found 计数口径——含 10 个 Testing 模块自测块；与 0057 的 suite 汇总 passed 数口径在链上并存）。
4. **文档保真**：CONTEXT.md Metaprogram generator 词条补组装纯函数一句；IMPLEMENTATION.md 开发环段落的 intermediate_path 描述由「target/」改为「target directory（bootstrap 为 root 派生绝对路径，票 0055）」。

### 验证结果

- `jai build.jai`（debug）：exit 0，链接器 `/OUT` 直接指向 `<worktree>/target/juice.exe`，`target/juice.exe` 存在、`target/target/` 不存在。
- `jai build.jai -release`：exit 0，同上（成功消息 "✅ Release build succeeded! Binary -> target/juice.exe" 与产物一致）。
- `./target/juice.exe test`（先清 `target/transpile`）：exit 0，Found 213 tests（210 + 新增 3），30 处 GOLDEN PASS / 0 处 GOLDEN FAIL 零重定，全绿。
- `juice build` 自构建（exe 锁定纪律：复制为 `target/juice-build.exe` 再运行，cwd = 仓库根）：exit 0 绿，验证后删除副本。

### 验证循环更新（替换 cp 晋升）

新循环（落点直接检查，cp 晋升删除）：
1. `jai build.jai`（debug）与 `jai build.jai -release` 各一遍——检查 `target/juice.exe` 直接存在 + `target/target/` 不存在。
2. 清 `target/transpile` 后 `./target/juice.exe test` 全绿（213 tests、30 GOLDEN PASS 零重定）。
3. `juice build` 自构建经 `target/juice-build.exe` 复制运行绿。

（cp 晋升步骤的原记录位于 jaix 实现 map「Not yet specified」行——归票 0059 清空；主会话记忆的验证循环更新归主会话。本票不触碰这两处。）

### 偏差清单

1. **验证环境偏差（非代码偏差）**：worktree 布局下 5 个 jaix E2E 全挂——`juice_root()/../jaix-cli`（测试支撑面 jaix_exe 推导）与 jaix CLI 自身的兄弟仓推导在 `.claude/worktrees/` 下解析不到真实 `jaix-cli`/`jaix` 仓（主树布局下 `../` 是真实兄弟）。以两个临时 junction（`.claude/worktrees/jaix-cli`、`.claude/worktrees/jaix` → 真实仓，位于 gitignore 的 `.claude/` 下、git 不可见）复现 dev 布局后定案 run 全绿，跑完即删、环境复原。首轮 run 的 5 失败及 Testing 模块自测段的连锁失败（自测段首排空把既有 5 失败计入 `testing_module_failures` 触发 latch 测试）均为同一环境面，非本票改动引入。
2. **文档微调**：CONTEXT.md 与 IMPLEMENTATION.md 各一处保真修订（0055 改变的事实写准）；ADR 0007 修订、扫描共享模块词条与 IMPLEMENTATION.md 模块表归票 0059 收口，本票不触碰。
