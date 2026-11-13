---
id: 002
title: 阶段 1a spec：build + clean + 结构层
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [001]
blocks: [003]
---

> 父 map：`../map.md`。上游规格：`docs/spec.md` §2（package 兼容面/KEY=VALUE 协议/校验门/bootstrap 扩展纪律）、§3（仓库布局）、§4（命令架构）、§10 阶段 1；研究文档 R（`docs/research/otter-refactor-research.md`）、C（`docs/research/cargo-style-monorepo.md`）。
> 参照面（只读）：juice/src 的 manifest.jai / workspace.jai / target.jai / dependency.jai / commands/* / dispatcher.jai / metaprogram.jai；juice/src 内联测试（语义先例）。

## Problem Statement

阶段 0 之后 otter 只有骨架（package.jai + 占位 main + 1 个测试）——otter exe 干不了任何真事。1a = 阶段 1 的最大块：交付 **结构层**（manifest 求值器与 KEY=VALUE 协议、workspace 状态机、target/依赖面）+ **build/clean/run 三命令** + **内置 version/help**（用户拍板 2026-10-19：version 打印 juice 与 jai 的版本信息、help 打印命令用法——spec §4.1 四命令扩为六命令，修订面随收口折回 spec.md）。验收 = 旧 juice 于 otter 根零特判全绿 + otter exe 在 fixture 包上 build/clean/run 可用。

## Solution

结构层按 spec §2/§3/§4 语义重写（旧 juice 为参照面），命令架构 = 静态注册表 + dispatcher。范围切线（用户拍板 2026-10-19）：**A** run 纳入 1a（注册表四命令骨架 + TEST 占位，1b 只加 TEST_COMMAND）；**B** jaix marker 前置 defer（b6 不接线，协议解析容忍 JAIX_CONFIG/JAIX_EXE/TRANSPILE_PLUGIN 记录）；**C** 转译面归 1c（b7/b8 无转译视图直编译）；**D** src/module.jai 的 1a 面 = Package 结构体面（§2.1 全字段），bootstrap 期内部消费照旧 `#import "Juice"`（旧模块面，load-bearing）。

## User Stories

1. As a package author, I want to declare package.jai with the same Package shape juice consumes, so my existing declarations keep working unchanged.
2. As a package author, I want manifest evaluation to happen in a spawned jai subprocess, so evaluator crashes can't corrupt the parent process.
3. As a package author, I want the manifest protocol to record NAME/VERSION/TYPE/DESCRIPTION/BUILD_SCRIPT/JAIX_CONFIG/JAIX_EXE/TRANSPILE_PLUGIN/TARGET/MEMBER/EXCLUDE/DEP records exactly, so declarations are parsed faithfully.
4. As a package author, I want unknown keys, duplicate single-value records and malformed shapes rejected with errors carrying line numbers, so misdeclarations fail loudly instead of silently.
5. As a package author, I want evaluator write failures retried at most twice (exit code 2), so transient filesystem hiccups don't fail the build.
6. As a workspace author, I want workspace.members as literal paths (no glob), so member sets are explicit and deterministic.
7. As a workspace author, I want members validated (inside the package root; referenced members must declare dependencies), so invalid topology fails at discovery.
8. As a package author, I want UNSPECIFIED type derived as targets → src/main.jai → import entry → BIN, so convention-only declarations resolve like juice does.
9. As a package author, I want LIB packages declaring targets rejected with LIBRARY_TARGET_CONFLICT, so library/executable roles can't be conflated.
10. As a package author, I want duplicate target names (case-insensitive) rejected with DUPLICATE_TARGET_NAME, so artifact paths stay unambiguous.
11. As a package author, I want target artifacts to land at target/<name>.exe, so output locations are predictable.
12. As a package author, I want dependencies consumed only through shims, so the dependency closure stays explicit and inspectable.
13. As a package author, I want no transitive dependency closure — every package declares its full closure explicitly.
14. As a workspace author, I want relative DEPs resolved only against members or the root (root-CWD discipline), so cross-package paths can't silently misresolve.
15. As a command user, I want workspace preparation to be idempotent, so re-running build reuses prepared state.
16. As a command user, I want prepare to publish only when everything succeeds, so a failed prepare leaves a retryable DISCOVERED state.
17. As a command user, I want build to short-circuit on an empty plan, so no-op builds are fast and quiet.
18. As a command user, I want build's phase order (validate args → prepare workspace → zero-plan short-circuit → batch revalidation → dependency strip front → per-plan entry selection → per-plan compile with generated metaprogram + spawned jai + artifact check), so builds behave like juice's b1-b8.
19. As a command user, I want run to depend on build (prerequisite chain), so `juice run` never launches stale artifacts.
20. As a command user, I want clean to discover without preparing, collect paths, validate everything first, then delete, so clean is safe and total.
21. As a command user, I want clean to clear the root target plus every member's target, so workspace cleanup is complete.
22. As a command user, I want a static command registry validated for bad declarations, duplicate names and unknown prerequisites, so command wiring errors fail at startup.
23. As a command user, I want dispatcher DFS planning with cycle detection and diamond dedup (prerequisites always receive empty arguments), so prerequisite graphs execute correctly and exactly once.
24. As a command user, I want failures to stop immediately (PREREQUISITE_FAILED/HANDLER_FAILED) with a failing exit code, so CI sees real failures.
25. As a command user, I want `juice version` printing juice's own version and the jai compiler version, so I can report toolchain provenance.
26. As a command user, I want `juice help` printing the command overview from the registry, so I can discover commands without reading docs.
27. As a command user, I want `juice help <command>` printing that command's usage, so I can resolve per-command flags quickly.
28. As a command user, I want unknown commands rejected with a clear error and non-zero exit, so typos don't silently no-op.
29. As a command user, I want builds that would overwrite a running executable to use the copy-and-delete discipline, so Windows LNK1104 can't break the loop.
30. As an otter developer, I want old juice to keep building and testing the otter root with zero special-casing (debug+release), so the bootstrap invariant holds throughout stage 1.

## Implementation Decisions

1. **范围切线 A（用户拍板 2026-10-19）**：run 纳入 1a——静态注册表骨架 = BUILD/RUN/CLEAN/TEST（占位）+ 新增 VERSION/HELP；run = build 的薄前置客户端（select_artifact_plan → launch，旧 juice run.jai:30-79 参照）；唯一前置关系 = run→build。
2. **范围切线 B（用户拍板）**：b6 jaix marker 前置不接线（otter 接法 = PRESTEP 阶段 at 钩子，1c 之后）；协议解析容忍 JAIX_CONFIG/JAIX_EXE/TRANSPILE_PLUGIN 记录（未知键才报错）；validate_jaix_marker 与 validate_transpile_pipeline 两道校验门照旧实现（未知 id/重复 id/非法选项拒绝——四硬约束 id 集纪律）。
3. **范围切线 C（用户拍板）**：转译面归 1c——1a 的 b7/b8 = 入口选择 + 编译 metaprogram 生成 + spawn jai + artifact 存在性检查，无转译视图直编译（原文进编译）。
4. **范围切线 D（用户拍板）**：src/module.jai 的 1a 面 = Package 结构体面（Package/Package_Type/Target/Dependency/Workspace 结构形状，spec §2.1 全字段）；bootstrap 期内部实现模块消费照旧 `#import "Juice"`（解析到旧 juice 模块面——load-bearing 约束）；姊妹测试 #load 直测结构体面（不 import）。Juice_Plugin 面留 1c、Testing 面留 1b。
5. **version/help（用户拍板 2026-10-19）**：注册表 = 六命令 build/run/clean/test/version/help（spec §4.1 修订面，随收口折回 spec.md）。version = juice 自身版本（Package.version）+ jai 编译器版本——jai 版本机制 = 编译期 `compiler_get_version_info`（Compiler.jai:1509，#compiler 内建，返回 major.minor.micro 版本串）经 `#run` 常量烘入 exe（2026-10-19 查实 jai CLI 无 --version 旗标）；spike 确认可行，回退 = spawn jai 读启动横幅。help = registry 元数据渲染（Command.description/usage 面，command.jai:14-21 形状）；help 零前置零副作用；具体输出文本 = 拆链票 argv 面测试锁定（jaix 惯例：fixture 锁定后即契约）。
6. **求值器子进程**：每 manifest 一个 jai 子进程（#load manifest + #run main 打印行记录）；记录全集 = §2.2 十二种；父进程严格解析（未知键/重复单值/形状错 = 错误 + 行号）；写盘失败退出码 2、父重试至多两次。
7. **实现纪律**：结构层 = 旧 juice 语义等价重写（juice/src 为参照面，非复制）；通用底层（路径安全门、XDG 缓存类）可接近直搬；命令模块按 spec §4 形状重写。
8. **UNSPECIFIED 推导序** = targets → src/main.jai → import entry → BIN（target.jai:118-125 源码面，2026-10-19 已核）。
9. **target 校验面**（2026-10-19 已核源码 + 用户提问实证）：LIB 声明 targets = LIBRARY_TARGET_CONFLICT 硬错误；同名 target（大小写不敏感）= DUPLICATE_TARGET_NAME 硬错误；产物落点 = target/<name>.exe。
10. **workspace 状态机**：EMPTY→DISCOVERED→PREPARED；幂等；「全部成功才发布」；三 seam（discover/resolve/prepare_dependencies）按 spec §4.5 保留形状（1c 的 at 挂载点）——1a 只做内置实现。
11. **dispatcher** = validate_registry（无效声明/重名/未知前置拒绝）→ plan_command DFS（环检测、菱形去重、前置恒收空参数）→ 按序执行；PREREQUISITE_FAILED/HANDLER_FAILED 立即中止。
12. **clean** = 发现（不 prepare）→ 路径收集 → 先全量校验后删除；清根 target + 各成员 target（§3.5）。
13. **LNK1104 规避面**（spec §10 阶段 1 风险行）：build 命令含运行中目标检测 → 副本运行毕删除纪律（副本留 target/ 内保 modules 推导面）；1a 姐妹测试覆盖判定逻辑，E2E 由阶段 2 自构建自然覆盖。
14. **四硬约束全程**：模块名 "Juice" load-bearing（内部消费照旧 `#import "Juice"`）；bootstrap 期 Package 不加字段；TRANSPILE_PLUGIN id 集 ⊆ juice 合法集；lint 零先例（1a 不涉）。
15. **子进程纪律**：全部绝对路径（CWD 切换面）；Windows-first（cmd /c、大小写近匹配拒绝语义照旧）。

## Testing Decisions

- **接缝 1（旧 juice 不变式）**：1a 每步 `juice build`/`juice test` 于 otter 根零特判全绿（debug+release）；开发循环仍用旧 juice（otter exe 由旧 juice 产出，测试程序内 spawn）。
- **接缝 2（姊妹测试）**：tests/*_tests.jai（test 块——阶段 0-2 约束）；实现模块 test-free（bootstrap #load 集纪律）；语义先例 = 旧 juice src 内联测试（同语义迁姊妹文件，非复制）。面清单：manifest_tests（协议矩阵/校验门/重试）、workspace_tests（三态机/幂等/失败不发布）、target_tests（推导/冲突矩阵）、dependency_tests（shim 消费/相对 DEP 纪律）、dispatcher_tests（DFS/环/菱形/前置）、build/clean/run/version/help 命令测试（argv 面 + 输出契约 + 退出码）。
- **接缝 3（E2E 真子进程）**：manifest 求值器 = 真 jai 子进程；命令级 E2E = 测试程序内 spawn otter 自己的 exe（旧 juice run_juice_child 先例，juice tests/test_monorepo.jai 形状）跑 fixture 包。
- **fixture** = tests/data/*（测试发现豁免区——juice 排除集纪律）：build-ok（build 产出 exe + artifact 断言）、clean（先校验后删除断言）、run（run 输出 + 前置 build 断言）、bad-manifest 家族（协议错误逐字节）。
- **好测试标准** = 只测外部行为（命令输出/退出码/盘上产物/错误文本），不测内部实现形状。

## Out of Scope

- test 命令（1b）、插件面与转译管线（1c）、build.jai 自构建 + modules 发布（005）、自举收口（006）；
- jaix pre-step 接线（1c 之后）、jaix 专属层执行面（JAIX marker 只在协议层容忍）；
- glob members、exclude 语义、`--workspace` 聚合、版本继承（map Out of scope）；第三方宿主；linkme；
- 旧 juice 仓任何改动（零特判参照面）。

## Further Notes

- spec §4.1 修订（四命令 → 六命令：+version +help）随收口折回 spec.md。
- version 的 jai 版本烘入机制需 spike（#run 常量 + #compiler 内建调用面）。
- 命名纪律：任何新 import 名不得与 "Juice" 大小写近匹配（§3.4）。
- 本票 = HITL spec 已发布；**已闭环（2026-10-19）**：tracer bullet 链 007-014 全 closed（007 求值器+协议+结构体面 → 008 workspace+成员 → 009 target+依赖 shim → 010 registry+dispatcher+main+help（与 008/009 不连边，只依赖 007）→ {011 build b1-b8 全链，012 clean} 并列 → 013 run+version（blocked-by 011）→ 014 fixture 收口（bad-manifest 家族补缺 + 旧 juice 不变式复核 + 本票收口））。收口映射与偏差汇总见下方 `## Resolution`。

## Resolution

**收口结论（2026-10-19，票 014 落笔）**：US 30 条全兑现、决定 1-15 全部直落（两处 spike 修正见偏差指认：决定 5 的 jai 版本形状、决定 13 的 LNK1104 机械等价）；三接缝全绿；实现链 007-014 全 closed。**1a 闭环 → 下一步 = 1b（003：test 命令 + note 发现）。**

### US 30 条兑现映射

| # | US | 落点 | 兑现证据 |
| --- | --- | --- | --- |
| 1 | package.jai 同形状声明兼容 | 007（src/module.jai 结构体面 + 求值器）+ 全链 | manifest-fixture 协议回环逐字段；"Juice" 模块名 load-bearing（007 偏差 1 命名空间绑定，实质不变） |
| 2 | 求值器 spawn 子进程 | 007 | manifest_tests E2E 真 jai 子进程块 |
| 3 | 十二记录协议逐条 | 007 | FULL_PROTOCOL 逐字段 + E2E 回环 |
| 4 | 未知键/重复/形状错 + 行号 | 007 + 014 | 协议矩阵 11 块（in-process 全分支）+ bad-manifest 家族 E2E 6 块（真链可及面，逐字节） |
| 5 | 写盘失败退出码 2 重试至多两次 | 007 | loader seam 9 块（真写盘失败不可按需制造——007 偏差 2） |
| 6 | members 字面路径无 glob | 008 | 成员七分支校验矩阵（字面路径解析面） |
| 7 | 成员校验 | 008 | 发现矩阵 E2E 8 块（错误文本逐字节） |
| 8 | UNSPECIFIED 推导序四分支 | 009 | target_tests 推导 5 块 |
| 9 | LIBRARY_TARGET_CONFLICT | 009 | LIB 面 4 块（错误逐字节） |
| 10 | DUPLICATE_TARGET_NAME | 009 | 重复名矩阵（大小写不敏感 + 精确重复 + 近似名通过） |
| 11 | 产物 target/<name>.exe | 009 + 011 | build-ok E2E artifact 断言 + 运行断言 |
| 12 | 依赖只经 shim 消费 | 009 | shim 面 7 块（形状逐字节） |
| 13 | 无传递闭包 | 009 | 成员按名 link、每包显式全闭包 |
| 14 | 相对 DEP 纪律 | 009 | rel fetch E2E + 成员相对 source 被 link 忽略 |
| 15 | 准备幂等 | 008 | 三态机幂等块 |
| 16 | 全部成功才发布 | 008 | 解析/依赖失败不发布块 |
| 17 | 零 plan 短路 | 011 | build-empty E2E（target/ 未创建） |
| 18 | b1-b8 序 | 011 | build_tests 23 块（b5/b6 恒等占位 = 决定 2/3 落实） |
| 19 | run→build 前置 | 010 + 013 | 唯一前置链注册表契约 + run E2E 前置 build 断言 |
| 20 | clean 发现不 prepare | 012 | 012 偏差 1（直接 discover_workspace 两参，旧 juice clean.jai:17 精确形状） |
| 21 | clean 清根 + 成员 target | 012 | clean E2E 删除断言（整目录删除、源文件不动） |
| 22 | 静态注册表校验 | 010 | validate_registry 三拒绝面 |
| 23 | dispatcher DFS | 010 | 环/菱形/前置恒空参/计划期查参 |
| 24 | 失败即停 | 010 + 013 | PREREQUISITE_FAILED/HANDLER_FAILED + run-fail E2E 透传 |
| 25 | version 两版本 | 013 | version_tests 契约 + E2E 两行逐字节（jai 形状 = 013 spike 修正，见偏差指认） |
| 26 | help 总览 | 010 | EXPECTED_HELP_OVERVIEW 逐字节 |
| 27 | help <command> | 010 | usage 行 E2E |
| 28 | 未知命令拒绝 | 010 | exit 1 + 总览 E2E |
| 29 | LNK1104 副本纪律 | 011 | 判定逻辑 7 块（011 偏差 1 机械等价成形，见偏差指认） |
| 30 | 旧 juice 零特判不变式 | 全链 + 014 复核 | debug+release 各 build/test 4/4 全绿（2026-10-19） |

### 决定 1-15 直落对照

| # | 决定 | 直落 | 偏差指认 |
| --- | --- | --- | --- |
| 1 | 切线 A：run 纳入 1a + 唯一前置 | 010 注册表 + 013 run 真实现 | 无 |
| 2 | 切线 B：b6 不接线 + JAIX 记录容忍 + 两门照旧 | 011 b6 注释占位 + 007 两门 | 无 |
| 3 | 切线 C：转译归 1c | 011 b7/b8 直编译 + 009 偏差 4 | 无 |
| 4 | 切线 D：module.jai = Package 面 + 内部消费 #import "Juice" | 007 结构体面 + juice_module 绑定 | 消费面形式偏差 = 命名空间绑定（007 偏差 1；模块名 load-bearing 实质不变） |
| 5 | version/help 六命令 | 010 注册表 + 013 version + 010 help | **013 spike 修正 jai 版本机制假设**：compiler_get_version_info 字符串返回 = 全横幅（非 Compiler.jai:1503 注释所称 major.minor.micro）——三元组取 Version_Info 填充（0.2.9），#run 常量烘入实证可用，回退（spawn jai 读横幅）未启用 |
| 6 | 求值器子进程 + 严格解析 + 重试 | 007 | 无（014 补 bad-manifest E2E 家族） |
| 7 | 语义等价重写纪律 | 全链（错误文本逐条同旧 juice） | 各票偏差清单记录等价面偏离，均带理由 |
| 8 | UNSPECIFIED 推导序 | 009 | 无 |
| 9 | target 校验面 | 009 | 无 |
| 10 | workspace 状态机 + 三 seam | 008 | 无（seam 默认值经 008 偏差 2 → 009 收口） |
| 11 | dispatcher | 010 | 无（010 偏差 2：print_usage 显式 12 列填充 = 实现其本意） |
| 12 | clean | 012 | 012 偏差 1：发现走直接两参 discover_workspace（状态机入口语义不符） |
| 13 | LNK1104 规避面 | 011 | **011 机械等价成形**：spawn 副本后立即 exit(0)（等待会撞同一 LNK1104 且无限链）、运行中副本不自删（映像锁）、下次 hand-off 先删旧副本——「运行毕删除」的 Windows 物理等价；E2E 由阶段 2 自构建自然覆盖 |
| 14 | 四硬约束全程 | 007（"Juice" 绑定）+ 全链 | 无违反（id 集 ⊆ juice 合法集经 007 两门 + 014 插件 gate E2E） |
| 15 | 子进程纪律 | 007/008/011 | 全部绝对路径 + 继承 cwd（juice 永不 chdir）；driver 子进程显式 set_working_directory（009 偏差 2，jai 编译期 cwd 锚入口文件目录） |

### 链偏差汇总（007-013，33 项 + 014 补缺面）

| 票 | 偏差数 | 一览 |
| --- | --- | --- |
| 007 | 4 | "Juice" 消费面命名空间绑定（load-bearing 形式偏差）；load_package_manifest 双 seam 参数（modules_dir 注入 + spawn fake）；juice_modules_dir = <exe>/modules（§9.3 有意偏差）；空 key 分支防御性死代码 |
| 008 | 6 | discover_workspace 加 modules_dir 尾参（007 seam 惯例）；resolve/prepare_dependencies 必填无默认（009 接线补默认）；Target_Resolution_Error/Artifact_Plan_Result 前置声明（009 移去 target.jai）；main 闭包不含 module.jai（最小闭包纪律）；成员矩阵 E2E 走生成 driver（exe 路径 011 起接管）；被引用成员 = 只经声明 DEP 链接（旧 juice 无该错误分支） |
| 009 | 5 | GIT 分支零测试（旧 juice 同状）；E2E driver 显式 set_working_directory（jai 编译期 cwd 锚入口文件目录）；ensure_import_shim normalize 失败分支防御性死代码；strip front 归 1c（切线 C）；both-pkg fixture 新增（双布局探针序） |
| 010 | 5 | Command_Context 暂缺 workspace 字段（008 补回）；print_usage 显式 12 列填充（Jai print 无宽度旗标，旧 juice "%-12" 潜在 bug）；007 src 模块不进 main 闭包（011-013 首个生产消费者进入）；TEST_REGISTRY_DIAMOND 补 accept-all validator；main #load 序与旧 juice 有别（version/help 插位） |
| 011 | 7 | LNK1104 hand-off 机械等价（决定 13 偏差指认）；metaprogram 只带可执行形状（no_output→1b、testing_view_dir→1c、very_optimized→阶段 2 移交点注释）；b5/b6 恒等占位（1c 接替点注释）；compile 内部 spawn seam 第四默认参；010 E2E 两测试随真 build 更新；ensure_bootstrap_modules 种子（阶段 2 发布落位后退役）；Jai 事实备忘 ×2（run_command varargs 混排、多返回值转发） |
| 012 | 3 | 发现走直接两参 discover_workspace（旧 juice clean.jai:17 精确形状）；校验失败 E2E 双变体（常规文件占位 + junction）；发现失败 E2E 用 bad-root-manifest（bad-invalid-manifest 的坏 manifest 在成员面） |
| 013 | 3 | jai 版本烘入 spike 修正 spec 假设（决定 5 偏差指认）；run 成功路径零单位测试（旧 juice 同状）；run-fail fixture 新增（退出码透传全链 E2E） |
| 014 | — | **补缺面**：bad-manifest 家族 6 fixture（duplicate-plugin/empty-member/empty-exclude/invalid-type/jaix-exe/plugin-id）+ E2E 6 块（真链逐字节）；盘点结论 = 其余家族（manifest-fixture/workspace-*/target-*/dep-fixture/build-*/clean-fixture/run-*）007-013 已全量落盘，无重复建设 |

**归属**：全部偏差为有意设计决定（语义等价重写 + bootstrap 窗口绕行），无遗留缺陷——旧 juice 仓改动面不涉（零特判参照面）。

### 完成定义复核

- **验收 1（Problem Statement）**：旧 juice 于 otter 根零特判全绿 ✓（2026-10-19 014 复核：debug+release 各 `juice build`/`juice test` 4/4 exit 0；验证前清 otter/target/transpile）；otter exe 在 fixture 包上 build/clean/run 可用 ✓（build-ok/clean-fixture/run-fixture E2E + exe 冒烟）。
- **接缝 2（姊妹测试）**：181 tests 双路径全绿（014 收口点：stage0 1 + module 6 + manifest 36 + workspace 20 + target 26 + dependency 18 + dispatcher 13 + help 5 + e2e_cli 8 + build 23 + clean 14 + run 9 + version 2）；src 实现模块全 test-free（bootstrap #load 集纪律）。
- **接缝 3（E2E 真子进程）**：manifest 求值器 = 真 jai 子进程 ✓；命令级 E2E = otter exe 自 spawn 跑 fixture 包 ✓（spec 002 fixture 四家族全落盘：build-ok / clean / run / bad-manifest）。
- **出范围面**：test 命令 → 1b（003）；插件面 + 转译管线 → 1c（004）；自构建 + modules 发布 → 005；自举收口 → 006；jaix pre-step → 1c 后；glob/exclude/--workspace/版本继承 → map Out of scope。**下一步 = 1b 新 spec（/to-spec）。**
