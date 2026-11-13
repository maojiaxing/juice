---
id: 011
title: build 命令 b1-b8 全链
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [009, 010]
blocks: [013, 014]
---

> 父 spec：`002-spec-build-clean-structure.md`（决定 3/7/13/15 + US 17/18/29）。上游规格：`docs/spec.md` §4.6（build 序 b1-b8）；研究 L§1（阶段清单）。

# 011: build 命令 b1-b8 全链

**What to build:** `juice build` 于包根端到端：b1 参数校验 → b2 workspace 准备 → b3 零 plan 短路 → b4 批量重校验 → b5 依赖剥离前端（无依赖 = 恒等面）→ b7 逐 plan 入口选择（**无转译视图直编译**——002 决定 3，转译面归 1c）→ b8 逐 plan 编译（metaprogram 生成 + spawn jai + artifact 存在性检查）→ `target/<name>.exe` 产出。**LNK1104 规避面**（运行中目标检测 → 副本运行毕删除，副本留 target/ 内保 modules 推导面）。b6 jaix marker 前置不接线（002 决定 2）。子进程纪律：全部绝对路径。

**Blocked by:** 009（build 消费产物计划/依赖面）+ 010（build 是 dispatcher 的 handler）

**Status:** closed

- [x] b1-b5：参数校验/准备/零 plan 短路/批量重校验/剥离前端
- [x] b7-b8：入口选择 + 编译 metaprogram 生成 + spawn jai + artifact 检查 → target/<name>.exe
- [x] LNK1104 规避面（检测 + 副本纪律，判定逻辑可测）
- [x] build_tests 姊妹测试
- [x] E2E fixture build-ok（build 产出 exe + artifact 断言 + 零 plan 短路 + 失败路径退出码）
- [x] 旧 juice build/test 于 otter 根零特判全绿（debug + release）
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话，本票不改 map.md）

## Resolution

**实现摘要**（新建文件 5 个：src/metaprogram.jai + tests/build_tests.jai + fixture build-{ok,empty,bad} 8 文件；改写 3 个：src/commands/build.jai 占位 → 真实现、src/main.jai #load 接入、tests/{test_support,e2e_cli_tests}.jai）：

- `src/commands/build.jai`：b1-b8 全链（语义等价重写自旧 juice commands/build.jai:9-112，**无转译面**——009 偏差 4 + 002 决定 3）：
  - **b1** `build_command` 参数守卫（build 无参数，validator 已在 010 落地）→ **b2** `ensure_workspace_prepared(ctx.root_dir, ctx.cache_dir, *ctx.workspace)` 三参调用形状（009 移交面直接可用）→ **b3** 零 plan 短路（LIB → `"Library package '%'; nothing to build."`；否则 `"No executable targets; nothing to build."`——旧 juice 文本逐字节）+ `"Build completed successfully!"`；
  - **b4** `revalidate_build_plans`：包根安全检查 → 每 plan `revalidate_artifact_plan` → 源文件存在/常规检查（三条错误文本逐字节同旧 juice build.jai:44/51/56）；零 plan 时 build_prepared_workspace 早退（不建 target/、不准备依赖）；
  - **b5** 依赖剥离前端 = 恒等/占位（注释标注 1c 接替点 `prepare_dependency_strip_views`）；**b6** jaix marker 不接线（注释标注 PRESTEP 归 1c 后）；
  - **b7** `build_plan_entry` = 恒等入口选择（返回 `plan.target.source_path`，注释标注 1c 换闭包探测 + 视图选择）；
  - **b8** `compile_artifact_plan`：入口存在性检查 → `make_directory_if_it_does_not_exist(target_dir)`（**LNK1104 链接器面**，旧 juice build.jai:73 同款）→ `"[juice Build] Compiling Target '%' (%) -> target/..."` → 组装 `Compiler_Metaprogram_Options`（workspace_name = "Juice Build"、executable_name/output_path/intermediate_path 全绝对正斜杠、import_dirs = `compiler_import_directories(packages_dir(root_dir))`——009 移交面、build_file = 入口）→ `generate_compiler_metaprogram` + `write_entire_file` → spawn jai（无 working_directory，继承包根——juice 永不 chdir；metaprogram 引用的全是绝对路径，子 jai 的 #run cwd 切换无害）→ artifact 存在性检查。错误文本逐条同旧 juice（build.jai:66/75/97/103/108）；
  - **LNK1104 面**：`artifact_is_running`（Windows 探针 = CreateFileW GENERIC_WRITE + share_mode=0 镜像链接器自身的 open——运行中映像使 open 失败于 ERROR_SHARING_VIOLATION(32)（本地常量，Windows.jai 未导出）；只读/缺失 ≠ running；POSIX 恒 false）+ `handoff_copy_path`（**副本留 target/ 内**：`<target_dir>/<name>-build.exe`，modules 推导 `<exe>/modules` 对副本继续成立）+ `running_artifact_handoff`（删旧副本 → copy_file → `cmd /c start /b` 非阻塞 spawn 副本（同 argv）→ 原进程立即 exit(0)——见偏差 1）。`build_prepared_workspace` 三 seam（compile = 旧 juice 三参形状经 `compile_artifact_default` 适配器、is_running、handoff）：b4 之后、任何编译之前逐 plan 探测，running → handoff 接管整建（副本从头重跑）。
- `src/metaprogram.jai`（**test-free**——阶段 2 bootstrap #load 纪律）：`Compiler_Metaprogram_Options` + `generate_compiler_metaprogram`（可执行形状与旧 juice metaprogram.jai:63-122 逐字节同构：对齐三行、import 目录发射序、消息循环只消费）；`escape_jai_string`/`quote_jai_string` 近直搬（旧 juice transpile.jai:346-368——quote 助手归转译层，otter 侧本地副本）；路径一律经 `path_slashes` 正斜杠（跨文件引用，main #load 序 path_safety 在前）。头注释标注三处移交点：no_output 测试形状 → 1b、testing_view_dir → 1c、very_optimized → 阶段 2。
- `src/main.jai`：#load 闭包 dependency.jai 之后接入 metaprogram.jai（旧 juice 序 xdg → … → dependency → metaprogram → commands 同款）。
- `tests/test_support.jai` 追加：compile/is_running/handoff 录制 fakes + `reset_build_seam`、compile 子进程 spawn fake（罐装退出码 + 按需写 artifact）+ `reset_compile_seam`、`build_seam_plan/prepared/write`（旧 juice 同款，Juice. 限定面）、`run_otter_child_at`（任意 cwd 的 E2E 真 exe spawn）+ **`ensure_bootstrap_modules`**（bootstrap 窗口模块种子：生产推导 `<exe>/modules` 在阶段 2 发布前不可命中，把旧 juice 的 Juice.jai 复制进 otter/target/modules——真 exe 的求值器子进程 `#import "Juice"` 才可解析；run_otter_child_at 自动执行）。
- `tests/build_tests.jai`：23 块——metaprogram 生成器 2（**可执行形状逐字节锁定** + 路径正斜杠化）、b4 重校验矩阵 3（不安全根/逃逸产物/缺源）、编排 seam 5（零 plan 无编译/逐 plan 转发（root/entry/plan 逐字段）/编译失败 fail-fast/b7 恒等入口）、LNK1104 判定 7（running → handoff 接管零编译（fake 驱动——生产探针真 running 面需真运行进程，阶段 2 自构建自然覆盖）/handoff 失败传播/非 running 正常编译 + 探测面逐 artifact/缺失非 running/在场非 running 真探针负例/副本路径推导/副本失败面——copy 失败在 spawn 前，可直接测）、b8 seam 4（缺入口零 spawn/metaprogram 写盘逐字节 + spawn 路径 + target 目录创建（LNK1104 面）/非零退出/缺 artifact）、**E2E 3**（真 otter exe 于 fixture：build-ok 产出 exe + 运行断言、build-empty 零 plan 短路 + target/ 未创建、build-bad 失败路径 exit 1 + 无 artifact）。
- `tests/e2e_cli_tests.jai` 修订（010 两测试随 build 真实现更新）：占位命令测试改为 clean/test/version（build 已真）；「无命令缺省 build」改跑 scratch 目录（无 package.jai → `"No package.jai found in current directory."` exit 1）——otter 根真 build 会触发自构建 hand-off，进测试套件代价过大。
- fixture 8 文件：`tests/data/build-ok`（BIN 无 test 块——转译面 1c 前的直编译形态，hello 程序）、`build-empty`（零 target 零 main → 零 plan 短路）、`build-bad`（编译错 → 失败路径）。

**验证矩阵**：

| 步骤 | 结果 |
| --- | --- |
| `jai build.jai`（旧 juice debug） | 成功 → target/juice.exe |
| 清 target/transpile → `juice.exe build` 于 otter 根 + `test`（debug） | exit 0，**149 passed, 0 failed**（126 + build_tests 23） |
| `jai build.jai - release`（旧 juice release） | 成功 |
| 清 target/transpile → `juice.exe build` + `test`（release） | exit 0，**149 passed, 0 failed** |
| exe 冒烟：otter exe `build` 于 build-ok fixture 根 | exit 0 + `target/build-ok.exe` 产出（中间产物/会话 metaprogram 落 target/）+ 产物运行 "hello from build-ok" exit 0；fixture 树零污染（E2E defer 清理验证） |

旧 juice 对无 modules/ 包根的 import dir 探测提示为通用无害行为（map Notes 已记）。冒烟不经 otter 根自构建（触发 hand-off 异步重编译 + 覆盖会话中的 exe——阶段 2 自构建自然覆盖该路径，见偏差 1）。

**偏差清单**：

1. **LNK1104 hand-off 机制按 Windows 物理约束成形**：原进程 spawn 副本后**立即 exit(0)**（不能等待——等待期间原进程的映像锁仍压着 artifact，副本的编译会撞同一个 LNK1104，且副本自身检测到 running 会再 hand-off 无限链）；运行中的副本**不能删除自己**（映像锁），spec 的「运行毕删除」实现为**下次 hand-off 先删旧副本**（稳态最多留一个，clean 随 target/ 整删）。副本的退出码经其自身输出传达（原进程恒 0）。头注释已钉死全部约束；真路径由阶段 2 自构建自然覆盖。
2. **metaprogram 生成器只带可执行形状**：no_output（测试形状）→ 1b、testing_view_dir（Testing 模块编译视图特例）→ 1c、very_optimized → 阶段 2 bootstrap——头注释标注移交点；生成文本与旧 juice 可执行形状逐字节同构（build_tests 字节锁）。
3. **b5/b6 占位形态**：依赖剥离前端与 jaix pre-step 均为恒等/不接线 + 注释标注接替点（009 偏差 4 + 002 决定 2 的票内落实）。
4. **compile_artifact_plan 追加内部 spawn seam（第四默认参数）**：直接测 metaprogram 写盘/失败分支/artifact 检查面；编排 seam 保持旧 juice 三参形状（`compile_artifact_default` 适配器 = seam 默认值）。
5. **010 的 E2E 占位/缺省命令测试随真 build 更新**：占位面改 clean/test/version；缺省命令测试改 scratch 目录（otter 根真 build = 全量自编译 + hand-off，不进套件）。
6. **bootstrap 模块种子（ensure_bootstrap_modules）**：真 exe E2E 的求值器子进程需要 `#import "Juice"` 可解析，生产推导 `<exe>/modules` 在阶段 2 发布前不可命中——测试支持把旧 juice 的 Juice.jai 复制进 otter/target/modules/（run_otter_child_at 自动执行；阶段 2 发布步骤落位后退役，007 偏差 3 同款窗口）。
7. **Jai 事实备忘**：run_command 的 varargs 不能混排固定参与 splat（"previous argument already started occupying the varargs slot"）——hand-off 的 cmd 命令行整条装数组后单 splat；多返回值不能经 `return f()` 直接转发（需解构重排）。

**测试组织**：src 实现模块全部 test-free（bootstrap #load 集纪律——metaprogram.jai 同旧 juice 同款）；测试驻 tests/（build_tests 姊妹文件 + test_support 共享声明）。移交面：013 run 的 `select_artifact_plan`/launch 消费 `revalidate_artifact_plan` 与 build 前置链；014 fixture 收口复用 run_otter_child_at + ensure_bootstrap_modules；1c 接替点 = build_plan_entry 主体、b5/b6 占位注释、metaprogram 的 testing_view_dir。012 clean 无交集（文件面不相交），但 E2E 同享 bootstrap 模块种子。
