---
title: driver 垃圾内容标记排除
status: closed
labels: [ready-for-agent]
assignee: maojiaxing
blocked-by: [0057]
---

> 父 spec：`issues/0054-spec-jaix-prestep-leftover-cleanup.md`（决定 5/6 + Testing Decisions 接缝 2/3 前置）。060 偏差 ③ + ADR 0007 Consequences 的产品级排除面。

# 0058: driver 垃圾内容标记排除

**What to build:** 带 jaix 标记的包连续 build/test 不再被 driver 垃圾打断——两处走查的文件排除面各增一条：首行以字面 `// jaix transpile driver` 开头的 .jai 排除（有界前缀读取、容忍 CRLF 行尾；标记前缀不含协议版本号 = 跨 jaix 版本稳定）；无条件适用（不门控 marker 在场）——旧 jaix 遗留的无点哈希垃圾同样免疫；标记不在首行的用户文件不受影响。判定谓词只在共享扫描模块实现一次（决定 6），两走查的文件排除谓词引用之。

**Blocked by:** 0057（扫描走查合一——排除谓词落共享模块，避免双写）

**Status:** ready-for-agent

- [x] driver 垃圾判定谓词在共享扫描模块实现一次；两走查文件排除谓词引用
- [x] 新增测试：首行标记排除 / 标记不在首行不误伤 / 旧哈希命名（无点）垃圾排除 / CRLF 容忍 / 点条目任意深度规则保持
- [x] 三路径全绿 + jaix 扫描矩阵既有测试原样

## Resolution

**实现摘要：**

- `src/scan_walk.jai`：新增判定谓词 `is_jaix_driver_litter(path) -> bool`（决定 6 单一来源，两走查引用之）——读文件头 `DRIVER_HEAD_SCAN_LIMIT = 1024` 字节（有界前缀读取，不整读；`file_open`/`file_read` 段读），逐行 split（`\n`）、行尾 `\r` 剥离（CRLF 容忍），行首列 0 匹配字面 `JAIX_DRIVER_MARKER :: "// jaix transpile driver"`（前缀后内容不参与判定 = 跨 jaix 版本稳定）；打开/读取失败 → false（非垃圾，真实错误留给后续编译/转译面诊断）；无条件适用（不门控 jaix 标记在场）。模块头注与内联测试区注同步。
- `src/commands/test.jai`：`collect_file_is_excluded` 文件排除面增 driver 判定一条（点条目/扩展名/根 manifest 既有排除不动、并列）；collect_test_files 扫描契约注与谓词注同步。
- `src/jaix_front.jai`：`jaix_collect_file_excluded` 同增一条（config 跳过与 test block 跳过既有规则不动；driver 判定置于 test-block 整读探测之前——垃圾文件省一次整读）；文件头扫描契约注同步。
- 新增测试 5 块：scan_walk 内联 3 块（真实 driver 形状——标记不在首行——/首行标记/前缀只判字面；CRLF 容忍；窗口外标记 + 非列 0 标记 + 不可读文件三个不误伤面）；test 命令内联 1 块（旧哈希无点命名垃圾排除 + 窗口外/缩进提及保留）；jaix front 内联 1 块（同面，与 config 跳过并列）。既有 test 发现矩阵与 jaix 扫描矩阵**原样通过**（零断言改动，点条目任意深度排除规则保持由既有矩阵锁定）。

**验证结果：**

- 挂载 junction 前基线轮：206 passed, 5 failed——5 失败恰为 junction 缺失的 5 个 jaix E2E（worktree 布局已知环境坑，非本票改动）；新增 5 块全过。
- 挂载 junction 后 debug 路径（`jai build.jai` + `./target/juice.exe test`）：**211 passed, 0 failed**、exit 0、**GOLDEN 30/30 PASS**（206 零回退 + 新增 5）。
- release 路径（`jai build.jai -release` + test）：**211 passed, 0 failed**、exit 0、30 GOLDEN PASS。
- `juice build` 自构建：exit 0、Build completed successfully（exe 复制为 juice-build.exe 运行规避 Windows 锁定，跑完删副本）。
- 验证后 junction 已移除（`cmd rmdir` 只删联接本身，真实 jaix/jaix-cli 仓未触碰）。

**偏差清单：**

1. **判定窗口从「首行」放宽为「文件头 1024 字节内任意行」**（关键偏差，team-lead 已批准）：规格决定 5 的「首行」前提是未经磁盘验证的写错前提——三处实证：① `jaix/src/cli.jai` generate_transpile_driver 的第一笔输出是 `#import "Basic";`（cli.jai:207）；② 新格式（点前缀）磁盘遗留 driver 实测首行 `#import "Basic";`、标记在第 12 行（`jaix/target/.jaix-1505d56cf073e259.jai` 等，`// jaix transpile driver：JAIX_TRANSPILE_PROTOCOL=2`）；③ 旧格式（无点哈希）磁盘遗留同样首行 `#import "Basic";`（`jaix/target/1505d56cf073e259.jai`、`jaix-cli/target/smoke/24bb73b92ab73b7b.jai`）。只查首行 = 新旧真实垃圾都排不掉、US 10 结构性落空。窗口化是保真规格意图（内容标记排除、列 0 前缀、不误伤现实用户代码）的最小修正——首行匹配是其真子集，真实 driver（标记位于文件头 ~220-400 字节内，1024 字节窗口含长路径裕量）被接住。**规格决定 5 的「首行」措辞需要修订（修订归 0059 收口）。**
2. **US 13 测试面落点**：原票面「标记不在首行不误伤」的意图以两个形状覆盖——标记在窗口外（文件头 1KB 之后）→ 保留；标记行有前导空白（列 0 不匹配）→ 保留（列 0 要求对齐 049 决定 5 锁定的 driver 形态）。两形状均有测试锁定。
3. 环境记录：projects/jai/jaix 与 jaix-cli 目录无 .git 元数据（纯工作副本）——E2E junction 验证不受影响，仅记录。
