---
id: 015
title: scan_walk 共享扫描骨架 + 排除集
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [018]
---

> 父 spec：`003-spec-test-note-discovery.md`（决定 3/10 + US 18）。上游规格：`docs/spec.md` §7.1.1（文件收集）；参照面：旧 juice scan_walk.jai（语义等价重写）。

# 015: scan_walk 共享扫描骨架 + 排除集

**What to build:** 确定性文件收集面：scan_walk DFS 词法序 + 排除集（dot 前缀、target/、tests/data、modules/、驱动垃圾谓词、member 子树剪除）——旧 juice scan_walk.jai 语义等价（jaix 0058 的 driver 垃圾排除先例面同款）；1c 插件包扫描同族复用。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] scan_walk DFS 词法序 + 排除集全集（含 driver 垃圾谓词）
- [x] member 子树剪除面
- [x] scan_walk_tests 姊妹测试（扫描序/排除集矩阵/垃圾谓词）
- [x] 旧 juice build/test 于 otter 根零特判全绿（debug + release）
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**：

- **`src/scan_walk.jai`**（新建，旧 juice scan_walk.jai:1-220 语义等价重写——test-free，链约定 bootstrap #load 集纪律；walk 矩阵驻姊妹测试文件）：
  - `Scan_File {rel_path, abs_path}` + `Scan_Entry {short_name, full_name}` + `Scan_Walk_Context($T)`（多态消费方上下文 + 两注入排除谓词，proc 值 + 上下文指针——pre-step seam 姿态）；
  - `collect_scan_files(root, user_data: $T, dir_excluded, file_excluded) -> [] Scan_File, bool`：visit_files 递归（不跟 symlink）、排除目录 `descend_into_directory = false` 剪整棵子树、根不可扫 → ok = false（失败通道，消息归消费方）；
  - `enumerate_scan_files`：确定性 DFS 枚举——每目录文件先（字典序）再子目录（字典序，反序入栈保弹出有序）；`scan_entry_parent`/`scan_rel_path` 路径助手；`sort_scan_entries` 插入排序；
  - **driver 垃圾谓词**：`JAIX_DRIVER_MARKER :: "// jaix transpile driver"` + `DRIVER_HEAD_SCAN_LIMIT :: 1024` + `is_jaix_driver_litter`——头部 1024 字节部分读、逐行行首（列 0）匹配、CRLF 容忍、协议版本不参与匹配、内容判据无条件（legacy 无点前缀 hash 命名 litter 同排除）、不可读文件 = 非 litter。jaix 0058 先例面同款。
- **`tests/scan_walk_tests.jai`**（新建，旧 juice scan_walk.jai 内联测试 6 块语义先例迁入；scratch fixture 走 `otter_root()` + `build_seam_write`）：
  1. 注入排除集扫描序矩阵（非 .jai 扩展、任意深度 dot 前缀、`member-a` 子树剪除；期望序 a_root/b_root/sub/beta/sub/calc 逐 rel_path + abs_path 断言）；
  2. 不可扫根失败通道（ok=false + 零文件）；
  3. 路径助手纯矩阵（scan_entry_parent/scan_rel_path 五面）；
  4-6. driver 垃圾谓词矩阵六面（真实 driver 形状非首行 marker / 首行 / 纯前缀、CRLF 容忍、超窗 / 非列 0 / 不可读三非误杀面）。
- **member 子树剪除面**：测试上下文显式取成员列表形状（`Scan_Test_Context.member_dirs`，018 `Test_Collect_Context` 生产形状同款）——dir_excluded 命中列表成员 → 整棵子树剪除（机制 = 排除目录 descend_into_directory = false）。
- **main.jai 不接线**（010 偏差 5 惯例）：src 模块入 main #load 闭包随首个生产消费者——018 的 collect_test_files 接线（scan_walk.jai 头注释已标）。

**验证矩阵**（旧 juice 双路径，各先清 otter/target/transpile）：

| 路径 | juice build | otter build | otter test |
| --- | --- | --- | --- |
| debug | exit 0 | exit 0 | exit 0，**187 passed, 0 failed**（181 基线 + 6 新），0 处 expect failed |
| release | exit 0 | exit 0 | exit 0，**187 passed, 0 failed**，0 处 expect failed |

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **生产排除谓词归消费方**（循旧 juice 架构）：dot/target/tests/data/modules/member 列表的完整排除集属 018 的 collect_test_files 包装（"scan_walk + 排除集，015" = 015 供 walk、018 供排除谓词）；015 的「排除集全集」以骨架矩阵钉住机制面——注入式排除/子树剪除/扫描序/driver 垃圾谓词六面，语义先例 = 旧 juice scan_walk.jai 内联测试。
2. **test-free 迁移**（链约定）：旧 juice 内联 6 测试块迁 tests/scan_walk_tests.jai（旧 juice src 可内联，otter src 全 test-free——bootstrap #load 集纪律）。
3. **member 剪除测试面以成员列表上下文显式化**：旧 juice 骨架测试用 skip_dir 字面量比较；otter 改用 member_dirs 列表查找（生产 member 边界形状），机制语义相同。
4. **main.jai 零改动**：首个生产消费者（018）接线——闭包纪律，无死代码进发布产物。
