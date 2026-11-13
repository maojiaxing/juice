---
id: 014
title: fixture E2E 家族 + 收口（关闭 spec 002）
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [011, 012, 013]
blocks: []
---

> 父 spec：`002-spec-build-clean-structure.md`（US 30 条 + 决定 1-15 + Testing Decisions 三接缝 + 完成定义）。上游规格：`docs/spec.md` §2/§3/§4。

# 014: fixture E2E 家族 + 收口（关闭 spec 002）

**What to build:** 零产品代码改动（测试侧重收口票，jaix 043/054/060 同款）——**fixture 全家族落盘 + E2E 矩阵**：bad-manifest 家族（协议错误逐字节）、build-ok（build 产出 + artifact + 零 plan 短路）、clean（先校验后删除 + 校验失败不删）、run（输出 + 前置链）；**旧 juice 不变式复核**（debug+release 4/4）；**spec 002 收口**：US 30 条全兑现映射 + 决定 1-15 直落 + 偏差清单随链记录 + **spec.md §4.1 修订折回**（四命令 → 六命令：+version +help）+ 002 票内写 `## Resolution` + `status: closed` + map Decisions so far 追加一行 → **1a 闭环 → 下一步 = 1b 新 spec（/to-spec）**。

**Blocked by:** 011 + 012 + 013（收口需复核三命令全链）

**Status:** closed

- [x] fixture 全家族落盘（bad-manifest 矩阵/build-ok/clean/run）
- [x] E2E 矩阵全绿（错误逐字节/产物断言/删除断言/前置链断言）
- [x] 旧 juice 不变式复核：debug+release build/test 于 otter 根零特判全绿
- [x] spec 002 收口：US 30 映射 + 决定直落 + 偏差清单 + spec.md §4.1 修订折回
- [x] 002 票 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话，本票不改 map.md）

## Resolution

**实现摘要**（零产品代码改动；新建 fixture 6 文件，改写 3 个文档 + 1 个测试文件）：

- **fixture 全家族盘点**（对照 spec 002 Testing Decisions 的 fixture 清单）：build-ok（build 产出 exe + artifact 断言 + 零 plan 短路 + 失败路径，011）、clean-fixture（先校验后删除 + 校验失败不删，012）、run-fixture/run-fail（run 输出 + 前置 build 链断言 + 退出码透传，013）、manifest-fixture + workspace-* + target-* + dep-fixture（007-009）已全量落盘——**唯一缺口 = bad-manifest 家族（协议错误逐字节 E2E）**：协议错误矩阵此前只有 in-process 覆盖（parse_manifest_data_strict 11 块 + loader 录制 fake），真链面（真 jai 求值器子进程 → 父严格解析/两门 → 错误 + 行号）零覆盖；workspace-bad-* 两 fixture 的坏 manifest = 截断编译失败面，非协议错误面。
- **补缺：bad-manifest 家族 6 fixture**（各 1 个 package.jai，`tests/data/bad-manifest-*`）：duplicate-plugin（重复 TRANSPILE_PLUGIN id → 解析拒绝，数据行 9）、empty-member（空 MEMBER → 行 8）、empty-exclude（空 EXCLUDE → 行 8）、invalid-type（`cast(Package_Type) 7` → 父不信任子数据 → 行 3）、jaix-exe（JAIX_EXE 无 JAIX_CONFIG → 两门之 marker 门）、plugin-id（未知 transpile id → 两门之 pipeline 门）。全部 = 合法 Jai 声明产生协议/门违例——真链可及面。
- **tests/manifest_tests.jai 追加 E2E 6 块**（复用 run_otter_child_at + ensure_bootstrap_modules，011 移交面）：真 otter exe `build` 于 fixture → 求值器子进程真求值 → 父拒绝 → 错误文本逐字节锁定（loader 行 `Invalid manifest protocol at ... (line N): ...` / 两门行）+ `Existing package.jai is invalid.` + HANDLER_FAILED 行 + exit 1 + 负断言（无 discovered/无 Build completed 打印、target/ 未创建）。**不重复已覆盖面**：解析器内部不可经真链到达的分支（未知键/重复单值/裸 malformed 行/TARGET/DEP 形状错——求值器只打印十二种良构记录）保持 in-process 矩阵，节头注释已钉此边界。
- **旧 juice 不变式复核**（验证前清 otter/target/transpile）：debug+release 各 `juice build`/`juice test` 于 otter 根零特判全绿 4/4（旧 juice 对无 modules/ 包根的 import dir 提示 = 无害通用行为）。
- **spec 002 收口**（`002-spec-build-clean-structure.md`）：`## Resolution` 落笔——US 30 条全兑现映射表 + 决定 1-15 直落对照（偏差指认：决定 5 的 jai 版本形状经 013 spike 修正为 Version_Info 三元组；决定 13 的 LNK1104 经 011 机械等价成形）+ 链 007-013 偏差汇总清单（33 项一览 + 归属：全部有意设计决定，无遗留缺陷）+ 完成定义复核（三接缝 + 出范围面）；frontmatter `status: closed`；Further Notes「已拆分」→「已闭环」。下一步 = 1b 新 spec（003，/to-spec）。
- **spec.md §4.1 修订折回**：静态命令注册表四命令 → 六命令（`COMMAND_REGISTRY :: Command.[BUILD_COMMAND, RUN_COMMAND, CLEAN_COMMAND, TEST_COMMAND, VERSION_COMMAND, HELP_COMMAND]`）+ version/help 语义一句（version = juice 自身版本 + jai 编译器版本，编译期 Version_Info 三元组经 #run 常量烘入——spike 实证字符串返回 = 全横幅；help = registry 元数据渲染，零前置零副作用）。§0/§7.4 不涉命令全集枚举（run 保留决定 / R§3.4 历史立场），未动。

**验证矩阵**：

| 步骤 | 结果 |
| --- | --- |
| `jai build.jai`（旧 juice debug） | 成功 |
| 清 otter/target/transpile → `juice.exe build` + `test` 于 otter 根（debug） | exit 0，**181 passed, 0 failed**（175 + bad-manifest E2E 6） |
| `jai build.jai - release`（旧 juice release） | 成功 |
| 清 otter/target/transpile → `juice.exe build` + `test`（release） | exit 0，**181 passed, 0 failed** |

181 = 013 收口的 175 + bad-manifest E2E 6。fixture 树零污染（E2E 无 target/ 产出 + defer 清理；bad-manifest fixture 无 src 面——发现期失败，永不触编译）。

**偏差清单**：

1. **bad-manifest E2E 面 = 真链可及子集**：求值器只打印十二种良构记录，解析器的未知键/重复单值/裸 malformed/TARGET/DEP 形状错分支经真链不可到达（除非篡改数据文件）——E2E 家族锁定 6 个声明级可及面（解析拒绝 4 + 两门 2），其余分支保持 in-process 矩阵（007 已全覆盖），节头注释钉边界。行号 = 数据文件记录序（非 manifest 行号），fixture 注释已标。
2. **invalid-type fixture 用显式 enum cast**：`type = cast(Package_Type) 7` 合法编译、求值器忠实打印 TYPE=7——钉「父不信任子数据」防御契约的仅有的真链表达（TYPE=1x 等文本形状不可经真链产生）。
3. **零产品代码改动**：全部工作 = fixture + 测试块 + 文档收口（jaix 043/054/060 同款收口姿态）。

**测试组织**：src 实现模块全部 test-free（bootstrap #load 集纪律，未触碰）；bad-manifest E2E 块驻 tests/manifest_tests.jai（姊妹文件，manifest 面的既有 E2E 节扩展）。移交面：阶段 2 发布步骤落位后 ensure_bootstrap_modules 退役（011 偏差 6 窗口）；1b（003）接手 test 命令占位。
