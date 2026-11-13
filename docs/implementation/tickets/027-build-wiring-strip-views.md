---
id: 027
title: build 接线（b5/b7 剥离视图 + at 挂载）
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [026]
blocks: [029]
---

> 父 spec：`004-spec-plugin-surface-skeleton.md`（决定 2/17/18/20 + US 15/16/30）。上游规格：`docs/spec.md` §6.1-6.3；参照面：旧 juice commands/build.jai:40-60,166-250。

# 027: build 接线（b5/b7 剥离视图 + at 挂载）

**What to build:** build 命令真剥离——b5 依赖剥离前端 + b7 入口选择（test-free 直编 / 含 test 闭包 STRIP 视图，接替 011 恒等占位）+ build 的 TRANSPILE/COMPILE 四挂载点 at 派发（seam #type 形参换钩子集数据形参 + 生产默认 = 内置实现；空钩子集 = 缺省管线；at 替换身份进管线描述 = 换视图键）。E2E：build-with-tests fixture（含 test 块包 build 剥离成功 + artifact 产出运行）+ 假钩子录制（before/at/after 序 + 失败中止 = HANDLER_FAILED）。

**Blocked by:** 026（视图层 + 剥离前端）

**Status:** ready-for-agent

- [x] b5/b7 接替恒等占位（真剥离视图编译路径）
- [x] build 的 TRANSPILE/COMPILE at 挂载派发（空钩子集 = 内置缺省）
- [x] 钩子序 + 失败传播矩阵（before 正序/after 正序/失败 = HANDLER_FAILED）
- [x] E2E：build-with-tests fixture 产 exe + 运行
- [x] 姊妹测试 + 旧 juice build/test 于 otter 根零特判全绿（debug+release）+ 353 存量不回归
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**（新建文件 2 个：src/transpile_config.jai + tests/build_transpile_tests.jai + fixture build-with-tests 3 文件；改写 6 个：src/commands/build.jai、src/dependency.jai、src/metaprogram.jai、src/lifecycle.jai、src/main.jai、tests/{build_tests,lifecycle_tests,test_support}.jai）：

- **b5 依赖剥离前端**（`src/dependency.jai` 追加，旧 juice prepare_dependency_strip_views 语义等价重写，build/test 共享——028 的 t11 直接消费）：`get_filename` + `collect_shim_names`（visit_files 词法序）+ `shim_load_target`（lex 首个 `#load <STRING> ;` 三元组 decode，形状不符 = 手写 shim 留给编译器）+ `prepare_dependency_strip_views(root_dir)`——每 shim 读 → 解析入口 → 探测依赖包闭包（空管线 = 缺省——依赖 manifest 不保留过 prepare，spec 0060 决定 6）→ 含 test 闭包全有全无 STRIP 视图落 `target/transpile/deps/<name>/` + shim 改写为入口视图；test-free/缺入口/手写 shim 零动作零转译。
- **b7 入口选择**（`build_plan_entry` 真实现，接替恒等占位）：`resolve_transpile_pipeline(声明)` → `probe_package_closure(root, main_file, pipeline)` → `closure_has_tests` 否 = 直编原文（零转译零缓存）；是 = CONTENT_ADDRESSED 全有全无 STRIP 视图 + 入口 = 入口文件视图。jaix marker 无分支（PRESTEP defer，004 决定 1）。
- **TRANSPILE/COMPILE at 挂载派发**（`build_prepared_workspace(prepared, hook_table: [] Hook_Registration = .[], is_running, handoff)`——seam #type 形参换钩子集数据形参，004 决定 17 形状）：阶段状态经 Lifecycle_Context 可观测槽（`views` = Build_Transpile_Stage{prepared, entries}、`artifact_paths` = Build_Compile_Stage{prepared, entries}）；派发 = `run_mounted_hooks` before 正序 → `has_mounted_hook` 有 at 则派发（替换内置实现）无则内置缺省 → after 正序；宿主状态 = 单 ctx 跨阶段复用单诊断 sink + 每注册一 null 槽；失败（false 或 ERROR）= 阶段失败 → 命令 false → HANDLER_FAILED → exit 1。内置实现 = `build_transpile_front`（b5+b7）+ `build_compile_loop`（b8 fail-fast 循环）。
- **Testing 模块 STRIP 特例接线**（b8）：`compile_artifact_plan` 每编译前 `testing_module_strip_view_dir(root, <exe>/modules/Testing.jai)` → `Compiler_Metaprogram_Options.testing_view_dir`（"" sentinel = 禁用）→ metaprogram 在 import_paths 拷贝后、import_dirs 前 prepend（旧 juice 逐字节形状，`#import "Testing"` 解析到无 test 视图）。
- **022 偏差 2 退役兑现**：metaprogram.jai 本地 quote/escape/HEX 对删除；test_metaprogram.jai 10 处调用点机械改名 `quote_jai_string`（028 面仅机械改名零特性改动）；main.jai 闭包 #load transpile.jai 先于 metaprogram.jai。
- **`src/transpile_config.jai`**（新建，旧 juice 同名模块语义等价重写，test-free）：`resolve_transpile_pipeline(decls: [] Juice.Transpile_Plugin_Declaration) -> [..] Transpile_Plugin`——声明序 = 管线序、零声明 = 空管线（resolve_pipeline 缺省）、未知 id 防御性跳过（manifest 校验门已拒绝）。
- **main.jai 闭包**：dependency 后接 transpile → transpile_plugin → transpile_cache → transpile_front → lifecycle → module → plugin → transpile_config → metaprogram（旧 juice 序 + module.jai 在 plugin.jai 前——内置 id 单一来源）。
- **`src/lifecycle.jai` 追加 `has_mounted_hook`**（at 替换查询：表上 (stage, position) 有挂载 = 替换内置；空表 = 内置缺省）。

**测试面**（376 tests = 353 基线 + 23 新）：

- `tests/build_transpile_tests.jai`（新建，22 块，助手全 prefixed `bt_*`——宿主填槽恒 null + Jai 无闭包 ⇒ 每行为一名函数）：声明装配 3（声明序/零声明/未知跳过）；b5 剥离 5（shim 解析形状/无 test 依赖 shim 逐字节不动零转译/含 test 依赖 shim 改写 + deps/<name>/ 视图落盘 + 依赖 test 剥净无 @test/手写 shim 留给编译器/缺入口跳过）；b7 入口 4（无 test 直编原文零转译/含 test 全有全无 + 入口视图嵌子视图 + 闭包外文件零视图/转译诊断拒选/声明管线换视图键——默认序显式声明 == 未声明、反序声明同视图异键）；派发矩阵 9（**全序钉**：两注册 8 钩子 before 正序跨注册 → at → after → 下一阶段 + 钩子填 entries 经状态槽到 COMPILE 捕获；无 at 挂载 = 内置前端跑在 before/after 之间（视图落盘证）；at 替换内置 = 前端跳过零转译树；before 失败 = fail-fast 后钩与内置零触发；ERROR 失败 + WARNING 通过；at 失败中止；after 失败中止；零 plan 零钩子；宿主槽恒 null 钉）；metaprogram testing_view_dir 前置发射 1；**E2E 1**（真 otter exe 于 build-with-tests fixture：build exit 0 + artifact 产出运行 "hello from build-with-tests: 2 + 3 = 5" + 双视图纯契约路径落盘 + math 视图剥净无 @test + main 视图嵌 math 视图路径）。
- `tests/lifecycle_tests.jai` +1：has_mounted_hook 判定矩阵。
- `tests/build_tests.jai` 更新（011 面随 seam 换形）：b4 矩阵与 LNK1104 面换新签名；编排 2 块重写为 `build_compile_loop` 直测（内部 compile 参数逐 plan 转发 + fail-fast）；LNK1104 3 块挂 COMPILE at 录制钩子（零真 spawn + hand-off 先于派发零钩子触发 + 内置前端选原入口达 COMPILE 阶段钉）；b8 metaprogram 期望构造补 testing_view_dir 同源派生。
- `tests/test_support.jai`：`test_compile_at_hook/table`（COMPILE at 录制 + entries 捕获）+ 两个 E2E 生成 driver 闭包补 transpile 族四模块（dependency.jai 剥离前端引用视图层，driver 镜像生产闭包）。

**验证矩阵**（各先清 otter/target/transpile）：

| 路径 | juice build | otter build | otter test |
| --- | --- | --- | --- |
| debug | exit 0 | exit 0 | exit 0，**Found 376 tests**（353 基线 + 23 新），206 passed, 0 failed |
| release | exit 0 | exit 0 | exit 0，**Found 376 tests**，206 passed, 0 failed |

expect failed 白名单 4 行（module_tests :178/:183/:207/:212，debug+release 逐行同状，无新增）；debug 套件 3 连跑零 stall。加分冒烟：otter exe 于 otter 根自构建 = 真 LNK1104 hand-off 生产路径（running 检测 → 副本接管 → 副本编译完成 → exe 更新 → `juice.exe version` 正常）。

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **at 派发粒度 = 阶段级**（spec §6.1「每次」直读）：TRANSPILE at 替换整个 b5+b7 前端（含其视图与缓存键的所有权）、COMPILE at 替换整个 b8 循环——非逐文件/逐 plan 派发；每调用数据经 Lifecycle_Context 可观测槽（021 槽族铸型消费面）；内置前端内部逐文件步骤 = 硬编码 transpile_build_file（seam 形参已换钩子集，004 决定 17「seam #type 形参换钩子集数据形参」直落）。
2. **at 替换身份进管线描述 = 文档化语义**：Lifecycle_Hook 无身份字段（021 已闭形状）——build 层文档钉定：at 钩子拥有其视图与键，替换身份经钩子传给 transpile_view_key 的管线进入键（换实现 = 换视图键）；内置键恒载内置管线描述，替换与内置视图不共键（除非钩子逐字复用内置步骤 = 同一实现）。语义落 build_prepared_workspace 头注释。
3. **build_compile_loop 保留内部 compile 参数（非 lifecycle 挂载）**：逐 plan 转发/fail-fast 的进程内测试面（011 偏差 4 同族）；默认值 = 三参 compile_artifact_default 适配器（**Jai 事实钉**：#type 形参 arity 须与函数严格一致——4 参 compile_artifact_plan 含内部 spawn seam 不能直作 3 参默认，compile_artifact_default 恢复）。
4. **resolve_transpile_pipeline 落新模块 src/transpile_config.jai**（旧 juice 同名模块位置）：输入类型 = `Juice.Transpile_Plugin_Declaration`（发现快照所载旧 juice 模块面——bootstrap 生产消费面）；plugin.jai 不得引用 Juice.*（025 juice_core stand-in 闭包不含 juice_module.jai——类型同一性 spike 约束），故解析器不进 plugin.jai；otter module.jai 声明类型归阶段 2 发布面。
5. **main.jai 闭包新增 module.jai**（008 偏差 6「main 闭包不含 module.jai」的 1c 迭代）：plugin.jai 内置 id 单一来源于 src/module.jai（024 决定）→ 生产闭包须带；裸 Package 与 Juice.Package 命名空间不撞（007 先例，测试程序已实证同程序共存）。
6. **E2E 生成 driver 闭包扩展**：workspace_discovery/dependency_prep 两 driver 的生成 #load 列表补 transpile 族四模块（dependency.jai 剥离前端引用视图层——driver 镜像生产闭包纪律）。
7. **LNK1104 is_running/handoff 仍为普通 seam**（§6.3 十四 seam 清单不含——非 lifecycle 阶段）；hand-off 先于任何阶段派发（零钩子触发，测试钉）；零 plan 短路同样先于一切阶段（无阶段 = 无钩子，测试钉）。
8. **Jai 事实钉 ×2**（编译期实证）：expect 宏的裸 `` `return `` 不能用于返回值函数（bt_prepared 助手去掉 expect，夹具写失败经下游断言呈现）；#type arity 严格一致（见偏差 3）。

**移交面**：028 test 接线——t11 依赖剥离直接消费 `prepare_dependency_strip_views(root_dir)`（dependency.jai 共享面）+ `resolve_transpile_pipeline`（transpile_config.jai）；main.jai 闭包已含全部转译族（028 零闭包改动）；test_metaprogram.jai 已走规范 quote 对（022 退役完成）。第三方插件全链路（扫描→merge→hook_table 进 build_command）留后续票——机制已立（hook_table 参数 = 现成挂口）。

