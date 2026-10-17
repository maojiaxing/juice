---
title: 扫描走查合一：新共享扫描模块
status: closed
labels: [ready-for-agent]
assignee: maojiaxing
blocked-by: []
---

> 父 spec：`issues/0054-spec-jaix-prestep-leftover-cleanup.md`（决定 7/8 + Testing Decisions 接缝 2）。0050 收敛先例方向（strip front 合一）。

# 0057: 扫描走查合一：新共享扫描模块

**What to build:** test 发现与 jaix 前置扫描共用一套走查实现——新共享扫描模块承载走查骨架（visit_files 编排、目录/文件排除回调（proc 类型参数——Jai 无闭包，pre-step seam 同款先例）、确定性 DFS 枚举 files-first 字典序、排序、包相对路径助手、扫描失败错误通道）+ 共享记录 `Scan_File {rel_path, abs_path}`。两消费者收敛为薄包装：各自排除集谓词 + 各自错误文案 + 入口名不变（`collect_test_files` / `collect_jaix_files` 命令层契约）；test 发现的记录与 jaix 扫描返回面改用共享记录；闭包探测面的记录不动（探测类型不是扫描类型）。共享模块经 main.jai 装载（非 bootstrap 闭包）→ 可内联测试（jaix front 先例）。**零行为变化不变式**：排除集、枚举序、输出形状、错误文案逐字节不变；既有矩阵与 30 GOLDEN PASS 原样通过。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] 共享扫描模块落地（走查骨架 + `Scan_File` + 排除回调 + 共享助手 + 错误通道）
- [x] `collect_test_files` / `collect_jaix_files` 收敛为薄包装；入口名/返回面/错误文案/枚举序不变
- [x] 共享骨架单测入共享模块；两消费者既有矩阵测试原样通过（零改动 = 零行为变化证据）
- [x] 三路径全绿：bootstrap debug/release + `./target/juice.exe test`（200 零回退）+ `juice build` 自构建

## Resolution

### 实现摘要

- 新共享模块 `src/scan_walk.jai`（经 main.jai 在 jaix_front.jai 与 commands/test.jai 之前 #load，非 bootstrap 闭包 → 内联测试允许）：
  - 共享记录 `Scan_File :: struct { rel_path: string; abs_path: string; }`
  - 走查入口 `collect_scan_files :: (root: string, user_data: $T, dir_excluded: #type (info: *File_Visit_Info, user_data: T) -> bool, file_excluded: #type (info: *File_Visit_Info, user_data: T) -> bool) -> [] Scan_File, bool`——排除回调为 #type proc 参数（Jai 无闭包，pre-step seam 同款先例；含多态变量的内联 proc 类型参数在参数表不可解析，须写 `#type`），失败返回 ok = false（错误通道，文案归消费者）
  - 内部：`Scan_Entry` 原始条目、`Scan_Walk_Context($T)` 多态走查上下文（visit_files 同款姿势）、`scan_collect_visitor`、`enumerate_scan_files`（files-first 字典序确定性 DFS）、`sort_scan_entries`
  - 共享助手：`scan_entry_parent`（去尾分隔符的父目录）、`scan_rel_path`（包相对路径）
  - 内联单测 ×3：注入排除集的走查顺序矩阵、不可扫描根失败通道、路径助手
- `src/commands/test.jai`：`Test_Source_File :: Scan_File`（别名——入口签名 `-> [] Test_Source_File, bool` 逐字节不变，命令层词汇保持）；`collect_test_files` 收敛为薄包装（`Test_Collect_Context {root, member_dirs}` + 谓词 `collect_directory_is_excluded`（自 `collect_directory_is_scanned` 反转改名）/`collect_file_is_excluded` + 原错误文案）；旧骨架（Collect_Context/Scan_Entry/visitor/枚举/排序/rel_path）删除
- `src/jaix_front.jai`：`collect_jaix_files` 返回面 `[] Build_Source_File` → `[] Scan_File`（字段面不变）；收敛为薄包装（`Jaix_Collect_Context {root, config_rel, member_dirs}` + 谓词 `jaix_collect_directory_excluded`/`jaix_collect_file_excluded` + 原错误文案）；文件头扫描契约段更新为共享走查表述
- `tests/test_support.jai`：`scan_entry_parent` 归属注释指向新模块（注释改动，行为零变化）
- 闭包探测面记录（`Build_Source_File`/`Build_Closure_File`）不动（spec 决定 7）

### 验证结果

- 三路径全绿：`jai build.jai`（debug）+ `jai build.jai -release` 构建成功（bootstrap 落点缺陷仍在，验证时 `cp target/target/juice.exe target/juice.exe` 晋升，先清 target/transpile）；`./target/juice.exe test` = **203 passed, 0 failed**（200 零回退 + 新增 3 个共享骨架单测）、**30 GOLDEN PASS** 零重定、exit 0（debug 与 release 产物各验一次，暖缓存复跑同绿）；`juice build` 自构建绿（exe 复制为 juice-build.exe 规避 Windows 锁定）
- 零行为变化证据：test 发现矩阵与 jaix 扫描矩阵既有测试**逐字节未改**、原样通过；错误文案（"Could not scan package root for test sources / jaix sources"）逐字节不变

### 偏差清单

1. 环境偏差（非代码）：worktree 布局下 jaix 系 E2E 经 `../jaix`、`../jaix-cli` 相对路径解析（exe、模块搜索路径），在 worktree 中天然断裂——首轮 5 个 jaix E2E 失败并级联 Testing 模块 latch（模块自测 start-drain 吸收主程序失败计数）。验证时以目录联接（junction）临时挂载两个仓库后全绿，验证毕已移除 junction（`cmd //c rmdir` 只删联接不删目标，已复核 jaix 仓库完好）。主仓库布局不受影响；后续在 worktree 中验证 jaix E2E 需重挂。
2. 共享模块命名 `src/scan_walk.jai`（无既有先例名可循，自定）；排除回调参数写 `#type (info: *File_Visit_Info, user_data: T) -> bool`（Jai 解析约束：参数表中含多态变量的裸 proc 类型不可解析；`$T` 仅在签名首次出现带 `$`，后续用裸 `T`，结构体参数化与 visit_files 同款姿势）。
3. 测试计数 200 → 203（spec 接缝 1「200 + 新增」预期内）。
