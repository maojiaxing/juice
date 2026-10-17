---
title: E2E 双构建 + 文档收口 + 关闭 spec 0054
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: [0055, 0056, 0057, 0058]
---

> 父 spec：`issues/0054-spec-jaix-prestep-leftover-cleanup.md`（决定 9/10 + Testing Decisions 接缝 3 + 收口定义）。060 同款收口票纪律。

# 0059: E2E 双构建 + 文档收口 + 关闭 spec 0054

**What to build:** demo fixture 接线 build 连续两次全绿——第一次遗留 driver 垃圾、第二次照常成功且产物与第一次逐字节同值（幂等面保持）；修复前该测试红（060 偏差 ③ 复现）。文档收口：ADR 0007 Consequences 修订（排除面落地 + jaix 点前缀命名的连锁注记）；CONTEXT.md 增扫描共享模块词条；IMPLEMENTATION.md 模块表补行；jaix 实现 map「Not yet specified」行清空；spec 0054 收口关闭（票内 `## Resolution` + `status: closed`）。two-step.bat 与 `clean_jaix_driver_files` 名字无关清理零改动（点前缀名仍匹配；注释可刷新）。

**Blocked by:** 0055（bootstrap 落点）+ 0056（jaix 命名）+ 0057（走查合一）+ 0058（内容排除）——收口需四接缝全绿

**Status:** closed

- [x] build 命令内联新 E2E：连续两次接线 build 幂等（run 输出同值 + 镜像逐字节同值；产物 exe 逐字节同值不可达——偏差 1；修复前红）
- [x] ADR 0007 Consequences 修订 + CONTEXT.md 词条 + IMPLEMENTATION.md 模块表
- [x] juice 三路径全绿（含新 E2E）+ jaix 519/golden 68/68 复核 + demo 两步脚本照常
- [x] spec 0054 票内 Resolution + status: closed；jaix map「Not yet specified」行清空

## Resolution

**实现摘要：**

- `src/commands/build.jai`：新增 E2E `"E2E: two consecutive wired builds are the same build despite driver litter"`（双路径 E2E 之后，spec 054 接缝 3）——demo fixture 接线 build 连续两次、步骤间零清理：第一次 build 后断言垃圾在场（根级 .jai 非两 manifest 非空、且全部点前缀 `.jaix-<hash>.jai`——无垃圾测试即空转）；第二次 build 照常 exit 0 + pre-step 仍报 "(2 files)"（垃圾被扫描排除）；幂等面 = 产物 run 输出与第一次逐字节同值 + 第二次 pre-step 后镜像视图逐字节同值（main 视图 == 原文、calc 视图含 lowered `try_0_err, try_0_v := half(n);`）。修复前该测试红（060 偏差 ③：第二次 build 整包扫描把遗留 hash 命名垃圾当源码、jaix parse error 致 build 失败）——红/绿逻辑记录于偏差 4，红面未实际重放（0056/0058 已先合入 master）。
- `docs/adr/0007-jaix-optional-pre-step.md`：Consequences 修订——driver 垃圾排除面已落地：jaix 侧点前缀命名 + juice 侧内容标记排除双机制（非「首行」：实测新旧 driver 首行均 `#import "Basic";`、标记 ~400 字节内）；demo 脚本清理改述为 fixture 根整洁面（不再承担规避职责）。
- `CONTEXT.md`：新增 **Scan walk（扫描走查）** 词条（0050 Strip front 先例风格——承载什么、两消费者薄包装、共享判定谓词、_Avoid_ 双份复制）；Test discovery 与前置转译词条各补一句指向新模块。
- `IMPLEMENTATION.md`：模块表补 `src/scan_walk.jai` 行。
- `issues/0054-spec-jaix-prestep-leftover-cleanup.md`：决定 5「首行」订正为窗口语义（附 0058 票面偏差实证）；Solution 2 / US 12 / US 13 / 接缝 2 措辞同步；接缝 3 产物面改述（偏差 1）；票内 `## Resolution` + `status: closed`。
- `tests/data/jaix-demo/two-step.bat` 与 `tests/test_support.jai` 的 `clean_jaix_driver_files`：**零代码改动**，仅注释刷新（hash 命名 → 点前缀 `.jaix-<hash>.jai` 命名；步骤间清理理由更新——juice 扫描自身已排除垃圾，清理为 fixture 根整洁面）。
- jaix 实现 map（jaix 仓）：「Not yet specified」区原三条 juice 遗留行清空，改注「已收口（2026-10-17 spec 054 闭环）——0055/0057/0058 + 0056 全部落地」。

**验证结果：**

- 挂载 junction 前：jaix E2E 5 例必挂（worktree 布局下兄弟仓推导断裂——0055/0057/0058 同款已知环境坑）；`mklink /J` 建 jaix、jaix-cli 两联接后全绿（偏差 2）。
- debug 路径（`jai build.jai` + `./target/juice.exe test`）：**212 passed, 0 failed**、exit 0、**GOLDEN 30/30 PASS**（211 零回退 + 新增 E2E 1）。
- release 路径（`jai build.jai -release` + test）：**212 passed, 0 failed**、exit 0、30 GOLDEN PASS。
- `juice build` 自构建：exit 0、Build completed successfully（exe 复制为 juice-build.exe 运行规避 Windows 锁定，跑完删副本）。
- jaix 复核（worktree juice）：**519 passed, 0 failed**、exit 0、**GOLDEN 68/68 PASS 零重定**；embed-consumer build 绿 + 运行输出 `jaix embed OK`；jaix-cli build 绿（exit 0）。
- demo 两步脚本：`cmd /c two-step.bat`（全脚本）exit 0——step 1 转译 calc/main、跳过 calc_tests；step 2 juice build + juice run 输出 `double(20): NONE 40` / `double(-6): NEGATIVE 0`；fixture 根清洁（仅两 manifest）。
- 验证后 junction 已移除（`cmd rmdir` 只删联接本身，真实 jaix/jaix-cli 仓未触碰）。

**偏差清单：**

1. **产物 exe「逐字节同值」实证不可达——测试改锁可达幂等面**：jai 调试构建非比特可复现。实证：两次连续 `jai build.jai`（同输入）产物差 ~756k 字节；demo 双构建产物 271872 字节同长、差 ~192k 字节（71%——差异不止 PE TimeDateStamp（字节 249 已不同），调试信息内嵌每构建数据；jai -help 无确定性构建开关）。替代断言（已落地、三路径全绿）：①第二次 build 照常 exit 0 + pre-step "(2 files)"（垃圾排除面）；②产物 run 输出逐字节同值（行为幂等面）；③镜像视图逐字节同值（确定性产物面——双路径 E2E 已锁的镜像幂等面在本场景复锁）。spec 054 接缝 3 措辞同步修订。已通报 team-lead。
2. **worktree junction 环境**（0055/0057/0058 同款）：挂载前 5 个 jaix E2E 挂；`mklink /J` 建 jaix/jaix-cli 两目录联接（.claude/ 被 gitignore）后全绿；验证后 `cmd rmdir` 移除。
3. **jaix map 改动无法提交**：jaix 仓无 .git 元数据（纯工作副本）——改动留 jaix 仓工作树，随仓库流转。
4. **红/绿逻辑记录**（红面未重放）：修复前第二次 build 红在整包扫描误收遗留 hash 命名垃圾（060 偏差 ③ 实测复现面）；0056（点前缀）+ 0058（内容标记）已先合入，本 E2E 以垃圾在场断言 + 双构建成功面锁绿。
