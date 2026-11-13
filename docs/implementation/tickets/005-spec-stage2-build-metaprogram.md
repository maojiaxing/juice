---
id: 005
title: 阶段 2 spec：build.jai metaprogram + modules 发布
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [004]
blocks: [006]
---

> 父 map：`../map.md`。上游规格：`docs/spec.md` §9（运行期模块发布规格）、§10 阶段 2；juice 仓库 `docs/adr/0006`（Default_Metaprogram 全套——照抄对象）、`build.jai`（自构建 metaprogram 参照实现）；研究文档 R§5（自举策略）。

## Problem Statement

阶段 1 收口后 otter 六命令 + 转译层 + 插件面 + lifecycle 全真实现（409 tests 全绿），但**构建路径仍依赖旧 juice**——otter exe 由旧 juice 产出，开发循环绕旧工具，且运行期模块面（Juice/Testing/juice_core）仍是 bootstrap 种子替身。阶段 2 = 自构建接管：`build.jai` metaprogram（ADR 0006 全形状）+ **modules 发布步骤**（三份发布产物）。发布落成即求值器切换（`<exe>/modules` 推导自动指发布面），自构建产物 = 完整工具。

## Solution

`build.jai` metaprogram 照抄 ADR 0006（旧 juice build.jai 为参照实现：`- release` 开关、Default_Metaprogram 抑制、test-free #load 闭包、PLAIN 布局剥离前端、Testing 模块特例、生成编译器 metaprogram + spawn 子进程 jai）+ 发布步骤扩展（先发布后编译——Testing 特例消费发布面）+ 编译期版本断言。发布产物三份：`target/modules/Juice/module.jai`（Package 段裁剪目录模块）+ `target/modules/Testing.jai`（剥前缀平铺）+ `target/modules/juice_core.jai`（插件库面生成模块）。验收 = 两模式自举产物于根自构建自测全绿（求值经发布面——切换成立）。

范围切线（用户拍板 2026-10-20）：**① 005 含求值器切换**（发布落位即切换；完成定义含 otter exe 于根 build/test 经发布面全绿）；**② 发布产物三份**（025 stand-in 兑现替换）；**③ 版本断言入 005**；**④ 转换形态 = 段裁剪 + 平铺变换**（Juice 目录模块 = 仅 Package 段裁剪生成、Testing.jai = 剥前缀平铺文本变换、juice_core = 生成模块）。

## User Stories

1. As an otter developer, I want `jai build.jai` to produce target/juice.exe without juice's involvement, so the dev loop stops depending on the old tool for building.
2. As an otter developer, I want `jai build.jai - release` (single `-` separator) to produce a release build, so both modes exist like the old bootstrap.
3. As an otter developer, I want Default_Metaprogram suppression (set_build_options_dc + empty workspace), so jai doesn't try to compile build.jai itself.
4. As an otter developer, I want the bootstrap #load closure strictly test-free, so the metaprogram compiles without test machinery.
5. As an otter developer, I want closure probing with PLAIN layout views under target/transpile/bootstrap/, so test-bearing closures strip correctly in bootstrap and never mix with the command's content-addressed cache.
6. As an otter developer, I want the Testing module special case (STRIP view + import path prepend), so the Testing face compiles despite its test blocks.
7. As an otter developer, I want a generated compiler metaprogram + spawned jai child with absolute paths, so diagnostics carry exact file:line.
8. As an otter developer, I want bootstrap failure semantics via exit code + child stderr, so CI sees failures.
9. As an otter developer, I want a compile-time version assertion (JUICE_VERSION == package.jai version), so version drift fails loudly.
10. As an otter developer, I want the publication step inside the build flow (publish before compile), so target/modules/* regenerate every build and the compile step consumes the published Testing face.
11. As an otter developer, I want Juice/module.jai published as a directory module carrying the Package compatibility face, so existing package.jai files keep working unchanged.
12. As an otter developer, I want Testing.jai published flat with the bare-name API (run/finish/path_mapping/expect), prefix-stripped from the prefixed bootstrap face, so existing test code keeps compiling unchanged.
13. As an otter developer, I want juice_core.jai published as the plugin library face, so plugin packages import the plugin API from the published module (the bootstrap stand-in retires).
14. As an otter developer, I want the flat Juice.jai seed retired when the directory module lands, so no flat/directory ambiguity exists at the modules dir.
15. As a package author, I want the manifest evaluator subprocess to resolve `#import "Juice"` from the published modules dir, so otter's own manifest evaluation uses otter's face (switch point).
16. As an otter developer, I want modules_dir derived as `<exe>/modules`, so the LNK1104 copy discipline keeps working (copies stay under target/).
17. As an otter developer, I want the bootstrap-built exe to build and test the otter root green, so self-build + self-test prove the product is complete.
18. As an otter developer, I want old juice invariants to stay green through stage 2 until the switch point, so the bootstrap window never regresses.
19. As an otter developer, I want published artifact shapes pinned byte-for-byte in tests, so publication drift fails loudly.
20. As a juice user, I want the bootstrapped exe to run all six commands, so stage 2 doesn't lose command surface.
21. As a juice user, I want build/test on fixture packages with the bootstrap-built exe, so transpile views and note discovery work in the self-built artifact.
22. As an otter developer, I want the seed modules gone from the publication path, so only generated artifacts live under target/modules.
23. As an otter developer, I want debug and release bootstraps both verified, so neither mode regresses.
24. As an otter developer, I want the bootstrap metaprogram's #load list documented as the stage-2 contract, so future module changes respect the closure discipline.

## Implementation Decisions

1. **范围切线（用户拍板 2026-10-20）**：① 005 含求值器切换——发布落位即切换（R§5.3 阶段 2 字面 + map 三接缝「自构建自测」）；② 发布产物三份；③ 版本断言入 005；④ 转换形态 = 段裁剪 + 平铺变换（Juice 目录模块 = 仅 Package 段裁剪生成、Testing.jai = 剥前缀平铺文本变换、juice_core = 生成模块）。
2. **build.jai = ADR 0006 全形状**（旧 juice build.jai 语义等价重写，参照面非复制）：`-` 分隔符参数约定（`get_toplevel_command_line` 自扫 `release`/`-release` 开关）；Default_Metaprogram 抑制（`set_build_options_dc(.{do_output=false})` + `compiler_create_workspace("Bootstrap Delegation")`）；test-free #load 闭包（#load 代码进 metaprogram 执行环境、不进被构建程序）；剥离前端（探测入口闭包——test-free 直编原文 / 含 test 全有全无 STRIP 视图落 `target/transpile/bootstrap/`，PLAIN 布局恒写、与命令内容寻址缓存不混用——026 已落地 PLAIN）；Testing 模块特例（STRIP 视图 + import path 前置——026/027 已落地库面）；生成编译器 metaprogram（绝对 output/intermediate 路径——子进程 CWD 切换纪律）+ spawn 子进程 jai；失败语义 = exit(1) + 子进程错误输出（收集打印被吞的事实不变）。
3. **#load 闭包 = 阶段 2 契约**（test-free + 随仓库分发）：旧 juice 五模块同构面（transpile/transpile_plugin/transpile_cache/transpile_front/metaprogram）+ otter 增面（transpile_config——缺省管线解析、发布转换模块——§9 步骤）。（具体名单 = 拆链票定；纪律 = 全 test-free、头注释钉名单。）
4. **发布步骤序 = 先发布后编译**：bootstrap 的 Testing 特例源 = `target/modules/Testing.jai`（发布面——含自测 test 块，正是特例消费面）；发布落成于编译前，编译产物 `#import "Testing"` 解析到发布平铺面。
5. **Juice 目录模块 = Package 段裁剪生成**（用户拍板）：从 src/module.jai 抽 Package 兼容面段（Package_Type/Target/Dependency/Workspace_Config/Jaix_Prestep/Transpile_* 声明族，Testing 面除外）→ `target/modules/Juice/module.jai`；裁剪机制 = 段边界标记 + 文本抽取（段边界注释是单源契约）；字段形状与旧 juice `modules/Juice.jai:97-118` 声明兼容；扩展字段在自举切换后加入（bootstrap 期纪律不变）。
6. **Testing.jai = 剥前缀平铺文本变换**：公开块 `Testing_run`→`run`、`Testing_finish`→`finish`、`Testing_path_mapping`→`path_mapping`、`Testing_expect`→`expect` 等裸名（016 spike 钉的形状）；`#scope_file` 内部态随变换调整（016 设计兑现面）；行号保真同款纪律（文本变换逐行可对）；产物含自测 test 块（Testing 特例消费面）；裸名 API 兼容由 import 发布面承接。
7. **juice_core.jai = 生成模块**：`#load` src/plugin.jai（+其依赖闭包）的发布形态——025 stand-in 替换（025 偏差 3「阶段 2 发布面替换」兑现）；插件包 `#import "juice_core"` 解析到发布面；类型同一性纪律不变（按名 import 共享单一模块面）。
8. **求值器切换 = 发布落位自动**：`juice_modules_dir` = `<exe>/modules`（007 已钉）；发布后 target/modules 由种子换发布面 → otter 自身命令的 manifest 求值自动走发布面（`#import "Juice"` 解析到发布目录模块）；平铺 Juice.jai 种子退场（目录模块接手——C§7.4 E6 平铺/目录并存歧义规避）。
9. **版本断言**：build.jai #run 内 spawn 求值器子进程读 otter/package.jai 的 VERSION 协议记录（manifest 求值机制同款 driver），对照 `JUICE_VERSION` 硬编码常量，不等 = 响亮失败 + exit 1（用户 2026-10-19 提的面；自构建成为唯一稳定编译入口后条件满足）。（执行形状 = 拆链票定：独立 mini-driver 或复用求值器面。）
10. **LNK1104 纪律延续**：自构建撞运行中 exe 时同款 hand-off（副本留 target/ 内保 modules 推导）；bootstrap 产物通常无人运行（首次构建），形状 = 拆链票定。
11. **种子退役**：ensure_bootstrap_modules 的 Juice.jai/Testing.jai 种子与 juice_core stand-in 在发布步骤落成后退场（发布产物接管；退役时机 = 发布落成后、编译前——Testing 特例源即发布面）。
12. **三接缝（阶段 2 版）**：接缝 1 = 自举三路径——`jai build.jai`（debug）与 `jai build.jai - release` 于 otter 根各 exit 0、产出 exe + 三份发布物，**两产物各于根自构建自测全绿**（含 LNK1104 hand-off）；旧 juice 不变式在 005 期间保持全绿直至切换点（过渡纪律，随收口退役）；接缝 2 = 姊妹测试（#load 闭包 test-free + 发布转换纯函数面测试驻 tests/）；接缝 3 = E2E 真子进程（真 jai 跑 build.jai 两模式 + 产物 exe 真跑 fixture 包与根自测 + 发布产物逐字节钉）。
13. **完成定义**：① `jai build.jai`（debug）与 `jai build.jai - release` 于 otter 根均 exit 0、产出 `target/juice.exe` + `target/modules/{Juice/module.jai, Testing.jai, juice_core.jai}`；② 两产物各于根 build/test 全绿（求值经发布面——求值器切换成立，path_mapping 指原文行）；③ 旧 juice 不变式全绿（过渡期复核）；④ 409 存量测试 + 新增全绿（双路径）；⑤ 版本断言触发面测试（声明版本 ≠ 常量 = 响亮失败 exit 1）；⑥ fixture 包 build/test 经自构建 exe 全绿。
14. **阶段 3 边界（归 006）**：旧 juice 退场声明（退出开发循环）、旧仓处置（归档/仓库替换）、note-based test 接管自身套件的最终形态——006 面。
15. **出范围继承（004 拍板延续）**：jaix PRESTEP 全链、at 其余 10 seam 机械接线、lint、真实第三方成员插件包（packages/ 布局 + 插件声明面）、test 显示名恢复——后续票，005 不涉。

## Testing Decisions

- **三接缝（阶段 2 版）**见决定 12——接缝 1 从「旧 juice 不变式」换「自举三路径」（map 全局骨架的既定演进），旧 juice 不变式为过渡期复核面。
- **好测试标准** = 只测外部行为：build.jai 退出码/产物存在与形状/发布产物逐字节/断言失败响亮/产物 exe 真跑输出；不测 metaprogram 内部轨迹。
- **模块面**：发布转换纯函数（段抽取边界/剥前缀矩阵/生成模块形状/种子退役）、bootstrap 选项组装（绝对路径派生、release 开关扫描）、版本断言对照面（等/不等两向）。
- **先例**：027 E2E build-with-tests（真 exe 面 + 双视图纯契约路径）、025 插件 E2E（真 jai 子进程 + 产物逐字节）、026 PLAIN 布局库面测试（bootstrap 消费面已钉）、013 version 契约测试（逐字节输出）、014/019 fixture 家族（静态 fixture 化）。
- 旧 juice 不变式复核延续（debug+release 4/4）直至切换点退役。

## Out of Scope

- **阶段 3（006）**：旧 juice 退场声明、退出开发循环、旧仓处置（归档/仓库替换/发布迁移）。
- jaix PRESTEP 全链、at 其余 10 seam、lint、真实第三方成员插件包、test 显示名恢复——004 出范围延续（map Not yet specified 已记）。
- 第三方宿主（DLL/进程外 §11.7）、linkme 特性请求（§11.1）、未来特性（glob members/exclude/--workspace 聚合/版本继承 §11.8）。
- 旧 juice 仓任何改动（零特判原则——只读参照物）。

## Further Notes

- **文档折回**：收口后 spec.md 执行级订正折回（1a/1b/1c 惯例）——§9 三份产物 + 段裁剪形态 + 求值器切换拍板（R§5.3 与 §10 的划分冲突以本票拍板为准）；§10 阶段 2 行验收 = 自构建自测。
- **拆链参考（/to-tickets 用）**：发布转换模块（段裁剪 + 剥前缀 + juice_core 生成 + 种子退役）→ build.jai metaprogram（ADR 0006 照抄 + 发布步骤接线 + 版本断言）→ 求值器切换验证 + 根自构建自测 → fixture 收口（关闭本票）。约 4-5 票，文件面互不重叠处可并列。
- 发布步骤顺序（先发布后编译）与版本断言执行形状 = 拆链票定（约束已列决定 4/9）。
- 409 存量测试是 005 的基线（029 终态双路径计数），每票递增。

---

- [x] 主会话与用户拍板：三接缝 + 完成定义 + 范围边界 + 关键执行决策（2026-10-20 四条切线：005 含切换 / 三份 / 断言入 / 段裁剪+平铺变换）
- [x] 拆 tracer bullet 实现链（/to-tickets）
- [x] 链全关后本票写 `## Resolution` + status: closed + map Decisions so far 追加一行

## Resolution

**实现摘要**（2026-10-20；链 030-033 逐票实施 + 034 收口复核）：

- **030 发布转换模块**：`src/publication.jai`（段裁剪——双标记契约/漏标-重复-改名-乱序响亮失败；剥前缀平铺——lex IDENT token 级、行号保真、注释/字符串不碰、自测 test 块保留；juice_core 生成——内置 id 常量声明行逐字抽取 + 四文件 absolute #load 闭包；落点助手四件）+ `src/module.jai` 两处段标记 + Testing 段尾 7 自测块。
- **031 build.jai metaprogram 核心**：根级 `build.jai`（ADR 0006 全形状：`- release` 自扫、Default_Metaprogram 抑制、test-free #load 闭包、PLAIN 剥离视图落 `target/transpile/bootstrap/`、Testing 特例、生成 metaprogram + 子进程 jai、失败 exit 1）+ `src/metaprogram.jai` 的 `bootstrap_compiler_metaprogram_options`。
- **032 发布接线 + 版本断言 + 种子退役**：`build.jai` 新序 = 参数 → workspace → 发布 → 版本断言 → 剥离前端 → Testing 特例 → 编译；三发布物落 `target/modules/`（Juice/module.jai 131 行 / Testing.jai 237 行 / juice_core.jai 12 行，与进程内 `publish_*` 逐字节相等）；编译期 `#assert` 版本断言；平铺 Juice.jai + 种子 + stand-in 退役。
- **033 求值器切换 + 根自构建自测**：自托管 runner 裸面注入三件套（修复「2 个 E2E 失败但 exit 0」的闸门信任缺口：注入 runner 驱动 prefixed 面而测试体裸断言写发布面寄存器）；自托管直跑的自构建 E2E 响亮 SKIP（bootstrap 无 hand-off = 决定 10）；测试基础设施求值面（workspace/dependency/manifest driver）切发布目录；完整 4/4 + 两模式产物根 build/test 全绿（含主会话指定的独立审计签核）。
- **034 收口**：完成定义①-⑥ 逐条复核 + fixture 家族复核 + 本节。`main.jai` 零改动；旧 juice 仓零改动。

**US 24 兑现映射**：

| US | 兑现证据 |
| --- | --- |
| 1 `jai build.jai` → target/juice.exe（无 juice 参与） | 031/032；034 复核两模式 exit 0 + exe |
| 2 `- release` 单 `-` 分隔符 | 031/032；034 两模式 |
| 3 Default_Metaprogram 抑制 | 031（`set_build_options_dc` + `compiler_create_workspace`） |
| 4 闭包严格 test-free | 六模块全 test-free（测试驻 `tests/`，031 头注释契约） |
| 5 PLAIN 布局视图落 `target/transpile/bootstrap/` | 031（与命令内容寻址缓存不混用） |
| 6 Testing 模块特例（STRIP + import 前置） | 027 共享 `testing_module_strip_view_dir`；032 消费发布面；033 E2E 钉 |
| 7 生成 metaprogram + 子进程 jai（绝对路径） | 031（`bootstrap_compiler_metaprogram_options`；058 偏差 ④ 纪律） |
| 8 失败语义 = 退出码 + 子进程 stderr | 031（探测 exit 1）；032（drift stderr 断言） |
| 9 编译期版本断言 | 032（`generate_version_assertion_driver` + `#assert`；drift E2E exit 1） |
| 10 发布步骤在 build 流程内（先发布后编译） | 032 #run 新序 |
| 11 Juice/module.jai 目录模块（Package 兼容面） | 030/032（131 行；+ 内部结构面扩展，见决定 5） |
| 12 Testing.jai 平铺裸名 API | 030（237 行；剥前缀） |
| 13 juice_core.jai 插件库面 | 030（12 行；stand-in 替换） |
| 14 平铺 Juice.jai 种子退役 | 032（零残留 + 无平铺/目录歧义） |
| 15 求值器子进程解析 `#import "Juice"` 到发布面 | 032/033（生产默认 `<exe>/modules`；测试 driver 同切 + 独立复核） |
| 16 modules_dir = `<exe>/modules`（副本纪律） | 007/011/033（LNK1104 副本留 target/ 命中推导） |
| 17 自举产物于根 build/test 全绿 | 033/034（两模式 258 passed / 0 failed） |
| 18 旧 juice 不变式过渡期全绿 | 033/034（debug+release 4/4） |
| 19 发布产物逐字节钉 | 030（真源面 pin）/032（bootstrap E2E == 进程内输出） |
| 20 自举 exe 六命令 | 033/034（version/help/build/test/run/clean 冒烟） |
| 21 fixture 包经自举 exe | 033/034（build-with-tests / test-blocks 族 / test-dep 族 / plugin-fixture 良构+坏） |
| 22 种子自发布路径消失 | 032（仅生成件） |
| 23 debug + release 双模式验证 | 031/033/034 |
| 24 #load 名单 = 阶段 2 契约 | `build.jai` 头注释钉六模块名单 + 纪律 |

**决定 1-15 直落对照**（spike/执行级修正指认加粗）：

1. **范围切线**：直落——005 含切换（033 实证）、三份产物（030/032）、断言入（032）、段裁剪+平铺变换（030）。
2. **build.jai = ADR 0006 全形状**：直落；**spike 修正**：入口锚定（metaprogram #run cwd 锚入口文件目录 → E2E = otter 根真实自构建）、`first.jai` 双代守卫是活的、import dirs = `{src, target/modules, root}`、`front_slashes` 替代 path_safety、探测/发布失败 exit(1)、bootstrap 无 hand-off。
3. **#load 闭包 = 阶段 2 契约**：实落**六模块**（旧 juice 五模块 + `publication`），全 test-free，`build.jai` 头注释钉名单。
4. **先发布后编译**：032 直落；Testing 特例源 = 发布面。
5. **Juice 目录模块 = Package 段裁剪生成**：直落；**spike 修正**：发布面 = Package 兼容段 **+ 内部结构面四类型**（`Effective_Target`/`Artifact_Plan`/`Workspace_Discovery`/`Prepared_Workspace`——种子退役首跑暴露 `'Workspace_Discovery' is not a member`；032 偏差 1，见 §9.5 折回）。
6. **Testing = 剥前缀平铺**：直落；**执行修正**：自测 test 块保留（Testing 特例消费面）+ 段尾 `#scope_export;`（带分号）+ 语句位缺口修正（030 偏差 1/2）。
7. **juice_core = 生成模块**：直落；**形状修正**：常量声明行逐字抽取（非文件复制）+ 四文件绝对路径闭包（`transpile`/`transpile_plugin`/`lifecycle`/`plugin`）。
8. **求值器切换 = 发布落位自动**：直落；033 自托管实证（manifest 求值 `-import_dir target/modules`）。
9. **版本断言**：直落；**形状钉 = 编译期 `#assert`**（运行时 print 被失败路径 exit 吞——032 偏差 2）。
10. **LNK1104 纪律延续**：直落——Build 命令 011 hand-off 全通（副本留 target/）；bootstrap 无 hand-off（031 偏差 7）；自托管直跑的自构建 E2E 响亮 SKIP（033 偏差 2）。
11. **种子退役**：032 直落（平铺 Juice.jai / Testing 种子 / juice_core stand-in 三件退场）。
12. **三接缝（阶段 2 版）**：直落并复核——接缝 1 自举三路径全绿；接缝 2 闭包 test-free + 发布转换纯函数测试驻 `tests/`；接缝 3 真子进程 E2E（build.jai 两模式 + 产物跑 fixture/根自测 + 发布物逐字节）。
13. **完成定义 ①-⑥**：034 逐条复核全绿（见 034 Resolution）。
14. **阶段 3 边界**：归 006，本 spec 未涉。
15. **出范围继承**：未涉（jaix PRESTEP / at 其余 seam / lint / 真实成员插件包 / 测试显示名恢复）。

**链偏差汇总（030-033，共 29 项；全有意设计决定，无遗留缺陷）**：

- 030（6）：自测块落位 = 段尾 + `#scope_export;` 带分号；语句位缺口修正（两代扫描器同缺口）；juice_core 闭包演化；显式 face 切文面（033 收窄为 fixture 消费面）；build_tests 期望更新；Jai 事实钉 ×2。
- 031（9）：入口锚定（E2E 于 otter 根）；探测失败 exit(1)；first.jai 守卫；import dirs 三面；`front_slashes`；Testing 特例源（032 切发布面）；无 hand-off（决定 10）；无版本断言（032 补）；run_command 全 splat。
- 032（8）：发布 Juice 面扩展内部结构面；断言 = 编译期 `#assert`；格式串 `\%`；jai 默认 import 路径含 `<cwd>/modules`；missing-seed 改写；旧 juice runner 块间不 drain；自测失败行号漂移 :353/:379；测试侧发布助手 = 生产生成器复用。
- 033（6）：自托管 runner 门禁面切换（核心修复）；自锁 SKIP；测试基础设施求值面切发布目录；`testing_face_strip_view` 保留（fixture 家族 = prefixed 消费面，主会话拍板接受）；进程残留环境处置；Jai 事实补钉。

**最终验证矩阵**（2026-10-20，串行；各先清 `target/transpile`/`target/testing-module`；证据日志 `otter/target/audit-*.txt`）：

| 路径 | 结果 |
| --- | --- |
| 旧 juice debug 4/4（juice build → otter build → otter test） | 全 exit 0；**Found 443**、**258 passed, 0 failed**、白名单恰 6 行 |
| 旧 juice release 4/4 | 同上 |
| 自举 debug / release（`jai build.jai` / `- release`） | 各 exit 0；exe 994816B / 582656B；三发布物 131/237/12 行 |
| 两产物各于根 build/test（完成定义②） | build exit 0（011 hand-off 行）+ test exit 0、258 passed、白名单 6、自锁 SKIP 2 |
| fixture 家族（自举 exe） | build-with-tests run「hello from build-with-tests: 2 + 3 = 5」；test-blocks 4 passed/0；test-blocks-fail exit 1 + `src/math.jai:13:5`；test-dep-root 1 passed/0（依赖测试零发现）；plugin-fixture 良构+坏全链 E2E（套件内） |
| 六命令冒烟 | version「juice 0.1.0 / jai 0.2.9」、help、build、test、run、clean 全 exit 0 |

**收口**：005 完成定义 ①-⑥ 与三接缝阶段 2 版全部成立，本 spec 关闭；阶段 3 归 006。spec.md 执行级订正已折回（§9 三份产物/转换形态/求值器切换/发布 Juice 面内部结构面；§10 阶段 2 验收 = 自构建自测 + 三接缝；§0 生成件同步）。
