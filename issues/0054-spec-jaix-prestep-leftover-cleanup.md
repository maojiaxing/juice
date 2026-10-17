---
title: "Spec: jaix pre-step 遗留收尾——bootstrap 产物落点 + jaix driver 垃圾扫描排除 + 扫描走查合一"
status: closed
labels: [ready-for-agent]
assignee: maojiaxing
blocked-by: []
---

> 决策来源（合成自，无新增决策）：jaix 实现 map「Not yet specified」记录的 juice 侧三条已知遗留（2026-10-17 十步闭环时归入未来票）——bootstrap 产物落点缺陷（058 偏差 ④）、jaix driver 垃圾扫描误收（060 偏差 ③ + ADR 0007 Consequences）、扫描走查与 test 发现 ~150 行同构复制（双轴复查 Standards 观察 3）。范围与方向已与用户拍板：一张 spec 收三条；driver 垃圾 = juice 扫描侧内容标记排除 + jaix driver 点前缀命名双改；走查合一落点 = 新共享扫描模块（0050 收敛先例方向）。上游权威：ADR 0003（统一 target/）、ADR 0006（bootstrap 剥离）、ADR 0007（jaix 前置转译）；本 spec 与既有决议冲突时以票面决议为准。

## Problem Statement

jaix v1 十步全闭环时留下三条已记录的 juice 侧遗留，各自都让用户付出可观察的代价：

1. **bootstrap 产物落点缺陷**：`jai build.jai` 的产物实际落在 `target/target/juice.exe`，而构建成功消息宣称 `target/juice.exe`。验证循环必须以 cp 晋升来规避（058 偏差 ④），ADR 0003 的统一 target/ 布局在产品自身的自举路径上不成立。根因：生成的编译 metaprogram 带相对 `output_path`/`intermediate_path`，而子进程 jai 的 `#run` 期工作目录切到了 metaprogram 所在目录（target/）——相对路径再解析一层。
2. **jaix driver 垃圾被扫描误收**：带 jaix 标记的包被连续构建时，第一次构建遗留的 jaix CLI driver 文件（哈希命名 .jai，落 spawn 时工作目录 = 包根）会被第二次 build/test 的整包扫描误收为源码——前置转译扫描对 driver 文件 parse error 致 build 失败；test 发现同样会把它拖进测试程序。当前规避 = demo 脚本的步骤间清理 + ADR 0007 Consequences 文档化（060 偏差 ③），产品级排除面缺失。
3. **扫描走查双份复制**：test 发现走查（test 命令）与 jaix 前置扫描走查（jaix front）是 ~150 行近同构复制——同一 DFS 枚举、同一排序、同一排除骨架，只是排除集与记录类型不同（双轴复查 Standards 观察 3）。每条新排除规则都要写两遍，继续演化必然漂移。

## Solution

三条遗留在一个 effort 内收口，用户可见的结果：

1. bootstrap 构建产物直接落 `target/juice.exe`（与 Build 命令同构——绝对路径），验证循环删除 cp 晋升，构建成功消息名副其实。
2. 连续构建不再被 driver 垃圾打断：jaix 侧 driver 文件改为点前缀命名（既有「任意深度点条目」排除自动接住）；juice 侧两处走查新增内容标记排除（文件头 1024 字节窗口内列 0 行 `// jaix transpile driver` 前缀——见决定 5 的窗口语义订正），对旧 jaix 遗留的无点垃圾同样免疫。
3. 两处走查收敛为一个共享扫描模块，排除规则只写一份；test 发现与 jaix 前置扫描的既有行为逐字节不变。

## User Stories

1. As a juice developer, I want `jai build.jai` to land the executable directly at target/juice.exe, so that the unified target directory layout (ADR 0003) holds on the bootstrap path and no manual copy step is needed.
2. As a juice developer, I want the release bootstrap build (`jai build.jai - release`) to land at the same place, so that both build configurations behave identically.
3. As a juice developer, I want the bootstrap build to never create a nested target/target/ directory, so that compiler intermediates and the executable stay in the one managed directory.
4. As a juice developer, I want the build's success message to name an artifact path that actually exists, so that following the printed path works.
5. As a juice developer running the verification loop, I want the cp promotion step gone, so that the loop verifies real product behavior instead of papering over a defect.
6. As a juice maintainer, I want the bootstrap metaprogram options assembly extracted as a pure function, so that the absolute-path decision is regression-locked in the test suite rather than only in the manual loop.
7. As a juice developer invoking the bootstrap from a different working directory, I want artifacts to land relative to the repository root (the driver's directory), so that the invocation directory does not shift the result.
8. As a package author with a jaix marker, I want consecutive builds of the same package to succeed, so that the first build's driver litter does not break the second.
9. As a package author, I want `juice test` after a wired build to ignore driver litter, so that test discovery does not drag generated files into the test program.
10. As a package author who ran an older jaix whose hash-named driver files are already on disk, I want the scans to exclude that legacy litter, so that upgrading jaix does not require manual cleanup.
11. As a jaix maintainer, I want driver files written with a dot prefix, so that the existing "dot entries at any depth" scan exclusion catches them with no new rule.
12. As a juice maintainer, I want the driver-litter exclusion to be content-based (head-window column-0 line-prefix marker) rather than name-based, so that any jaix version's litter is excluded and future tooling following the marker convention is covered.
13. As a juice maintainer, I want a user source file that merely mentions the driver marker in passing (indented mention, or past the head window) to stay included, so that the exclusion has no false positives on real code.
14. As a juice maintainer, I want the exclusion to apply unconditionally (not gated on the jaix marker being present), so that litter left behind after a marker is removed is still excluded.
15. As a demo user running the two-step script, I want the script's litter cleanup to keep working under the new naming, so that the fixture root stays clean.
16. As a maintainer of ADR 0007, I want the documented driver-litter consequence amended once the exclusion lands, so that the ADR describes the product as it is.
17. As a juice maintainer, I want one walk implementation shared by test discovery and the jaix pre-step scan, so that each new exclusion rule lands exactly once.
18. As a juice maintainer, I want the two consumers to keep their distinct exclusion sets, so that test discovery keeps excluding tests/data and modules while the pre-step scan does not.
19. As a juice maintainer, I want the convergence to be zero-behavior-change, so that existing golden outputs and E2E expectations stay valid untouched.
20. As a juice maintainer, I want the shared module loadable in the juice program but outside the bootstrap closure, so that its tests can stay inline next to the implementation.
21. As a test author, I want the shared walk skeleton unit-tested once in the shared module, so that the consumers' tests only cover their own exclusion sets.
22. As a juice maintainer, I want a shared scan result record (rel_path/abs_path) consumed by both walks, so that routing code in the test command and the pre-step deals in one type.
23. As a juice maintainer, I want the scan error messages unchanged ("test sources" vs "jaix sources"), so that diagnostics stay stable.
24. As a juice maintainer, I want the deterministic DFS enumeration order preserved, so that test numbering, report order and transpile enumeration remain stable.
25. As a package author, I want nested directories named like excluded roots (e.g. src/target/) to remain scanned user code, so that exclusions stay root-level-only as today.
26. As a package author using the pre-step, I want the test command's mirror routing to keep consuming the scan unchanged, so that mirrored files still route to target/jaix views.
27. As a maintainer of the E2E suite, I want a double-build regression test (two consecutive wired builds), so that the exclusion works against real jaix litter, not just crafted fixtures.
28. As a jaix maintainer, I want the driver naming change to leave all golden baselines untouched, so that fixture output stays stable.
29. As a maintainer of CONTEXT.md and IMPLEMENTATION.md, I want the new shared module and the scan vocabulary documented, so that the codebase stays navigable (0050 precedent).

## Implementation Decisions

1. **bootstrap 落点根治（058 偏差 ④）**：根因 = 子进程 jai 的 `#run` 期工作目录切到生成的 metaprogram 所在目录（target/），相对 `output_path`/`intermediate_path` 再解析一层成 target/target/。修复 = 与 Build 命令同构：bootstrap 以 root（`get_working_directory()` = driver 目录）派生绝对路径传入两个 metaprogram 选项。Build 命令先例：`plan.target_dir` 绝对。成功消息文本不变（修复后名副其实）。
2. **可测缝抽取**：metaprogram 选项组装从 bootstrap 的 `#run` 抽为共享 Metaprogram 生成器模块的纯函数——输入 = (root, entry, testing_view_dir, is_release)，输出 = 既有 `Compiler_Metaprogram_Options`；bootstrap 的 `#run` 改为组装调用点。该模块是 bootstrap 的 `#load` 目标（test-free），其单测驻既有姊妹测试文件（0053 迁移面）。
3. **验证循环简化**：删除 cp 晋升步骤；新增检查项「`target/juice.exe` 直接存在 + `target/target/` 不存在」。
4. **jaix driver 点前缀命名（jaix 侧唯一触碰）**：CLI 的 driver 写盘名从 `<hash>.jai` 改为 `.jaix-<hash>.jai`（落点目录不变 = spawn 时工作目录）。juice 既有「任意深度点条目」排除自动接住新垃圾。driver 文件名不在任何 golden 中（实现时复核）；054 偏差「driver 哈希文件被扫描」的负向实证翻转为点前缀纪律的正向面。
5. **juice 扫描内容标记排除（060 偏差 ③）**：两处走查的文件排除面各增一条——文件头 1024 字节窗口内、列 0 行以字面 `// jaix transpile driver` 开头的 .jai 文件排除（有界前缀读取、容忍 CRLF 行尾）。「首行」订正为窗口语义（0058 票面偏差实证）：新旧 driver 首行均为 `#import "Basic";`——标记行在 imports/#load/#run 前导之后、实测 ~400 字节内，只查首行 = 新旧真实垃圾都排不掉；窗口上界 1024 字节含长路径裕量，首行匹配是其真子集。标记前缀不含协议版本号 = 跨 jaix 版本稳定。无条件适用（不门控 marker 在场）——旧 jaix 遗留的无点垃圾同样免疫。
6. **排除谓词单一来源**：driver 垃圾判定在共享扫描模块实现一次，两走查的文件排除谓词引用之。
7. **扫描走查合一（Standards 观察 3）**：新共享扫描模块（0050 收敛方向）承载走查骨架——visit_files 编排、目录/文件排除回调（proc 类型参数——Jai 无闭包，pre-step seam 同款先例）、确定性 DFS 枚举（files-first 字典序）、排序、包相对路径助手、扫描失败错误通道；共享记录 `Scan_File {rel_path, abs_path}`（test 发现的记录与 jaix 扫描返回面改用之；闭包探测面的记录不动——那是探测类型不是扫描类型）。两消费者收敛为薄包装：各自排除集谓词 + 各自错误文案 + 各自入口名（`collect_test_files` / `collect_jaix_files` 命令层契约不变）。共享模块经 main.jai 装载（非 bootstrap 闭包）→ 可内联测试（jaix front 先例）。
8. **零行为变化不变式**：排除集、枚举序、输出形状、错误文案逐字节不变；test 发现矩阵与 jaix 扫描矩阵既有测试原样通过（30 处 GOLDEN PASS 零重定）。
9. **脚本与测试助手零改动**：two-step.bat 与 `clean_jaix_driver_files` 按「根级 .jai 非两 manifest」名字无关清理——点前缀名仍匹配；注释可刷新。
10. **文档收口**：ADR 0007 Consequences 修订（排除面落地 + jaix 命名的连锁注记）；CONTEXT.md 增扫描共享模块词条；IMPLEMENTATION.md 模块表补行；jaix 实现 map「Not yet specified」行清空（收口时归主会话）。

## Testing Decisions

- **好测试判据**：只测外部行为——扫描结果（包含/排除/顺序）、生成的 metaprogram 选项文本、driver 写盘文件名、E2E 连续构建成功；不测走查内部实现细节。
- **接缝 1（juice 三路径不变式）**：`jai build.jai`（debug）与 `jai build.jai - release` → 产物直接落 target/juice.exe（无 cp、target/target/ 不出现）+ `./target/juice.exe test` 全绿（200 + 新增）+ `juice build` 自构建绿。先清 target/transpile（memory 已记）。
- **接缝 2（走查测试面）**：既有 test 发现矩阵（test 命令内联）与 jaix 扫描矩阵（jaix front 内联）原样通过 = 零行为变化证据；新增 driver 垃圾排除测试——窗口内标记排除 / 缩进提及与窗口外标记不误伤 / 旧哈希命名（无点）垃圾排除 / CRLF 容忍 / 点条目任意深度排除保持。
- **接缝 3（E2E 双构建）**：build 命令内联新 E2E（demo fixture）——接线 build 连续两次；第一次遗留 driver 垃圾、第二次照常成功且 run 输出与第一次同值、镜像视图逐字节同值（幂等面保持；产物 exe 逐字节同值实证不可达——jai 调试构建非比特可复现，链接器与调试信息内嵌每构建数据，0059 票面偏差 1）。修复前该测试红（060 偏差 ③ 复现）。
- **接缝 4（bootstrap options 单测）**：metaprogram_tests 新块——临时 root 下断言 output_path/intermediate_path 为绝对路径（root 派生 target/ 形状）。
- **接缝 5（jaix 仓不变式）**：jaix `juice test`（518 + 新增 driver 命名断言）+ golden 68/68 零重定 + embed OK + jaix-cli build 绿 + exe 冒烟（driver 以点前缀名落调用时工作目录）。
- **先例**：0050（收敛 + 零行为变化 + CONTEXT/IMPLEMENTATION 同步）、test 发现矩阵（test 命令内联）、jaix 扫描矩阵（jaix front 内联）、双路径 E2E（build 命令内联，060）、metaprogram_tests（0053 迁移面）、juice 三路径验证循环（memory）。

## Out of Scope

- jaix driver 写盘位置变化（仍落 spawn 时工作目录；只改命名）。
- 磁盘缓存与 #import 按名插件源码跟踪（⑨⑩ 已 defer 面不变）。
- 其它扫描排除面变化（混合文件两层视图、config 排除、跨界 #load 限制——058/059 偏差面不动）。
- bootstrap 其余相对路径的防御性绝对化（父上下文路径当前正确；只修两个 metaprogram 选项）。
- juice 自身 test-block/#load 转译的插件化改造（既有 out of scope 不变）。
- L2-L4 语法层与 jaix 其余 v1 功能面（driver 命名是唯一触碰）。

## Further Notes

- 引用链：058 偏差 ④（落点缺陷）、060 偏差 ③ + ADR 0007 Consequences（driver 垃圾）、双轴复查 Standards 观察 3（走查复制）、0050（收敛先例——strip front 合一）、049 决定 12（driver 哈希命名落 spawn 时工作目录）。
- 语言：中文交流与文档。
- 每会话开工先读 juice CONTEXT.md 与 jaix map Notes；juice 三路径验证与测试组织规则见既有记忆。
- 收口定义：接缝 1-5 全绿 + ADR/CONTEXT/IMPLEMENTATION 同步 + jaix map「Not yet specified」行清空。

## Resolution

**收口（2026-10-17，票 0059）**：接缝 1-5 全绿 + 文档同步 + jaix map 行清空——收口定义达成。

- **接缝 1（juice 三路径）**：debug 与 release 各 212 passed, 0 failed（211 零回退 + 新 E2E 1）+ 30 GOLDEN PASS + `juice build` 自构建绿（0055 落点根治——target/juice.exe 直落、target/target/ 不出现、cp 晋升已删）。
- **接缝 2（走查测试面）**：既有 test 发现矩阵与 jaix 扫描矩阵原样通过（0057 零行为变化）；driver 垃圾排除 5 块（窗口内标记/首行标记/前缀只判字面/CRLF/三个不误伤面 + 两消费者各 1 块）全绿（0058）。
- **接缝 3（E2E 双构建）**：新 E2E 绿——连续两次接线 build、第一次遗留点前缀垃圾、第二次照常成功 + run 输出逐字节同值 + 镜像逐字节同值。**措辞修订（0059 偏差 1）**：产物 exe「逐字节同值」实证不可达（jai 调试构建非比特可复现——两次同输入构建产物差 ~756k 字节，调试信息内嵌每构建数据），幂等面改锁 run 输出 + 镜像。
- **接缝 4（bootstrap options 单测）**：metaprogram_tests 新块绿——output_path/intermediate_path 绝对路径（0055 可测缝）。
- **接缝 5（jaix 仓不变式）**：jaix 519 passed（518 + 0056 新增 driver 命名断言）、GOLDEN 68/68 零重定、embed OK、jaix-cli build 绿、两步脚本 exit 0（脚本清理照常匹配点前缀名）。

**实施链**：0055（bootstrap 落点根治 + 可测缝）→ 0056（jaix 侧 driver 点前缀命名）→ 0057（共享扫描模块 src/scan_walk.jai）→ 0058（driver 垃圾内容标记排除）→ 0059（本收口票）。US 1-29 全兑现；决定 1-10 直落（决定 5 经窗口语义修订，附 0058 票面实证）。

**文档**：ADR 0007 Consequences 修订（排除面落地 + 点前缀命名连锁注记）；CONTEXT.md 新词条 Scan walk（扫描走查）+ Test discovery/前置转译各补指向；IMPLEMENTATION.md 模块表补 scan_walk.jai 行；two-step.bat 与 clean_jaix_driver_files 零代码改动（注释刷新）；jaix map「Not yet specified」juice 遗留三条清空。

**偏差**：0055/0057（worktree junction 环境——验证面非代码面）、0056（无实现偏差）、0058（「首行」→ 文件头 1024 字节窗口语义——决定 5 措辞修订，本票落档）、0059（exe 逐字节同值不可达——接缝 3 措辞修订）。
