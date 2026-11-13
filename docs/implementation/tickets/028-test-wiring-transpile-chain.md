---
id: 028
title: test 接线（t3/t5-t9/t11 转译全链 + at 挂载）
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [026]
blocks: [029]
---

> 父 spec：`004-spec-plugin-surface-skeleton.md`（决定 2/17/18/20 + US 11/13/14/18-21）。上游规格：`docs/spec.md` §7；参照面：旧 juice commands/test.jai:64-84,105-321。

# 028: test 接线（t3/t5-t9/t11 转译全链 + at 挂载）

**What to build:** test 命令转译全链——t3 逐文件 EXPAND + 全局编号基 1 续号（与手写 `@test` 经同一 note 发现统一）+ t5/t8 内容寻址视图落盘 + t9 Testing 模块编译视图（target/testing-module/ + note 枚举白名单接线——metaprogram 的 testing_view_dir 与 test_metaprogram 的白名单两移交点）+ t11 依赖剥离 + path_mapping（视图行 → 原文行随 driver 生成时嵌入）+ test 的 TRANSPILE/COMPILE at 挂载派发。E2E：含 test 块包全链（EXPAND → `@test` → note 发现 → 编译执行 + 失败报原文 file:line）+ 依赖测试不发现不执行。

**Blocked by:** 026（视图层 + 剥离前端 + 缓存键）

**Status:** closed

- [x] t3 EXPAND + 编号基 1 续号（与手写 `@test` 统一 note 发现）
- [x] t5/t8 内容寻址视图 + t11 依赖剥离
- [x] t9 Testing 模块编译视图 + 白名单接线（两移交点）
- [x] path_mapping 原文行（E2E 失败断言原文 file:line）
- [x] test 的 TRANSPILE/COMPILE at 挂载派发
- [x] 姊妹测试 + 旧 juice build/test 于 otter 根零特判全绿（debug+release）+ 408 存量（376+32）不回归
- [x] 票内 `## Resolution` + status: closed（map Decisions so far 行归主会话）

## Resolution

**实现摘要**（改写 3 个：src/commands/test.jai、src/test_metaprogram.jai、tests/{test_command_tests,test_metaprogram_tests,module_tests,test_support}.jai；新建 2 个：tests/test_transpile_tests.jai + fixture 4 包；main.jai/build 侧零改动）：

- **t3 EXPAND + 全局编号**（`transpile_test_file` + `Test_File_Output`，旧 juice 语义等价重写）：逐文件 EXPAND（pipeline = resolve_transpile_pipeline(根包声明)，空 = 缺省）+ ctx.next_test_number 推进（023 偏差 4 契约——调用方在文件间续号）+ Test_Entry 降级为纯转译簿记（编号续号；发现源仍是 note 枚举——004 决定 18）。
- **t5/t8 内容寻址视图**：transpile_view_key/transpile_view_path 纯契约路径落盘、命中跳过（父目录先建）、失败标签 = 原文件 rel_path；driver.jai/first.jai = 会话产品落 transpile 树根（transpile_cache.jai 注释契约——1b 的 target/test 退役）。
- **t9 Testing 模块编译视图**（testing_module_source/testing_module_view/testing_module_support_block 全族）：in-package = EXPAND + 编号续号 + 自测段截取（#scope_file 包裹 + 自包含 imports）追加 + 白名单（test_metaprogram.jai 的 whitelist_paths 移交点）+ testing_view_dir prepend（Test_Metaprogram_Options 新增字段，"" sentinel = 字节不变——test_metaprogram_tests 字节锁不动）；global = STRIP 视图（<exe>/modules/Testing.jai）；缺模块/无 test 块 = disabled。**spike 钉**：module 作用域 @test 头进 TYPECHECKED 消息流（enclosing_load = 模块文件路径）+ add_build_string 注入代码可直接引用 #scope_export 模块导出——白名单全链实证。
- **t11 依赖剥离**：直接消费 prepare_dependency_strip_views（027 共享面）——TRANSPILE 前端末步。
- **path_mapping**：pairs = {view 视图路径, original rel_path} 每文件 + 模块视图对 {视图, "modules/Testing.jai"}，随 metaprogram 生成嵌入（1b 已嵌静态面，1c 接视图路径源）。
- **at 挂载派发**（027 同款形状）：Test_Transpile_Stage（prepared/files/outputs/view_paths/transpile_dir/testing_module_* 经 views 槽）+ Test_Compile_Stage（+pattern 经 artifact_paths 槽）；test_transpile_front = t3+t5-t9+t11 全前端、test_compile_front = driver/metaprogram/spawn（内部 spawn seam 保留——非挂载点，027 偏差 3 同族）；test_prepared_workspace = before 正序 → at 有则替换无则内置 → after 正序 + fail-fast + 失败 = HANDLER_FAILED；零文件短路先于一切派发（零钩子）。
- **Testing face 跳过**（otter 自身根形态）：face_is_discovered 纯函数（词法归一 + nocase 路径同一）——发现集含 bootstrap face 时 driver 不再显式 #load（双重加载 = 全符号重声明）。
- **test_metaprogram.jai**：Test_Driver_Options.testing_source "" = 跳过发射；Test_Metaprogram_Options.testing_view_dir 新字段 + import_paths 拷贝后 prepend（Compiler_Metaprogram_Options 镜像；"" 字节不变）。
- **test_support.jai**：ensure_bootstrap_modules 种子扩展 Testing.jai（bootstrap 期 global 分支面源；阶段 2 发布退役）。

**测试面**（408 tests = 376 基线 + 32 净增）：

- `tests/test_transpile_tests.jai`（新建，34 块，助手全 prefixed tt_）：t3 直测 4（EXPAND 形状+key/跨文件续号/缺文件诊断/声明管线换键）；t9 族 6（源查找 in-package 优先/缺模块 disabled/test-free disabled/in-package EXPAND+支持块+编号续号/缺标记失败/支持块截取形状）；编排 seam 10（视图落盘+编号/缓存命中跳过/诊断先于编译失败/产品嵌隔离+映射+白名单空/pattern 透传/face 检测纯函数+编排/模块接线白名单+目录+对/前端 t11 shim 改写/spawn 失败/真 collect 组合成员剪除）；派发矩阵 9（**全序钉** 两注册 8 钩子 before 正序跨注册 → at → after → 下一阶段 + 钩子填 view_paths 经状态槽到 COMPILE 捕获含 pattern/无 at 挂载 = 内置前端跑在 before-after 之间（视图落盘证）/at 替换 = 零转译树零 spawn/before 失败 fail-fast/ERROR 败 WARNING 过/at 失败中止/after 失败中止/零文件零钩子/宿主槽恒 null）；E2E 5（test-blocks 全链 4 块展开+发现+执行+视图纯契约+driver 只引视图/test-blocks-fail 原文 file:line 映射+exit 1/pattern 过滤 juice_test_N/依赖测试不发现不执行+shim 改写+剥净/in-package 模块自测经编译视图跑）。
- `tests/test_metaprogram_tests.jai` +2：driver 空 face 跳过形状 / metaprogram testing_view_dir prepend（字节锁不动）。
- `tests/test_command_tests.jai` −4（1b 编排四块退役，语义由 test_transpile_tests 接替）+ 零文件/collect 失败保留（换新签名）+ E2E pin 路径更新。
- `tests/module_tests.jai` 1 块改：path_mapping 测试「构造即空」→「reset 即空」（两 driver 填相反面——旧 juice driver 填 bare 面、otter driver 填 prefixed 面）。

**验证矩阵**（各先清 otter/target/transpile）：debug 4/4 exit 0（juice debug build → otter build → otter test ×3 连跑零 stall）；release 4/4 exit 0；**Found 408 tests**（376+32）；expect failed 白名单 4 行（module_tests :178/:183/:207/:212）双路径逐行同状；**完成定义①**：otter exe 于 otter 根自跑套件 exit 0（test 块 → EXPAND → juice_test_N + @test → note 发现统一，018 切线 A 解除），失败断言指原文 file:line（prefixed 面经映射；bare 面行号保真 + 视图路径——见偏差 7）。

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **显示名 = 过程名 juice_test_N**（017 偏差 5 的 1c 延续）：EXPAND 发射裸 `@test`（023 形状不动），note 枚举收集过程名——命名 test 块的旧 juice 显示名（"addition"）与匿名块的 path:line 显示名丢失，pattern 过滤作用于 juice_test_N 名；Test_Entry.name 仅簿记。恢复显示名 = 后续票（@test("name") 参数化发射 + 解析）。
2. **"Found N tests; compiling..." 不产**（018 偏差延续）：发现源在 metaprogram，命令层不知计数。
3. **零测试包不短路**：视图照写、metaprogram 零条目短路（1b 语义延续）——旧 juice t2 的 next_number==1 判定在 otter 失效（手写 @test 存在时不等价零测试，1b 新增能力）。
4. **产品落 target/transpile/**（driver.jai/first.jai，transpile_cache 注释契约）——1b 的 target/test 退役。
5. **at 派发粒度 = 阶段级**（027 偏差 1 同款）：TRANSPILE at 替换整个 t3+t5-t9+t11 前端（含视图与键所有权）、COMPILE at 替换整个 t12（driver/metaprogram/spawn）；内置前端内部逐文件步骤 = 硬编码 transpile_test_file（seam 形参已换钩子集，004 决定 17 直落）。
6. **face 跳过 = face_is_discovered 纯函数**（词法归一路径同一）：进程内测试面——测试程序编译期 testing_face_source() 解析到 jai 编译器目录（get_path_of_running_executable），真 face 不可读；端到端 = 完成定义①（otter 根跳过成立，无重声明编译错误）。
7. **双面并存的结构代价**：otter driver 的 finish 门只守 prefixed 面——bare 面（juice Testing STRIP 视图）的失败注册逃逸退出门（旧 juice driver 对称反向：其 bare 门不守 prefixed 面）——两 driver 互补覆盖 + 验证面白名单 grep 兜底；module_tests path_mapping 测试改「reset 即空」随附。
8. **ensure_bootstrap_modules 种子扩展 Testing.jai**：bootstrap 期 global 分支的面源（阶段 2 发布退役）。
9. **t9 白名单机制 spike 钉**（编译期实证）：module 作用域 @test 头进入 TYPECHECKED 消息流（enclosing_load = 模块文件路径）+ add_build_string 注入代码可直接引用 #scope_export 模块导出（旧 juice 无 note 枚举故无此面；白名单机制 016 设计、本票首实证）。
10. **Jai 事实钉**：运行期值的 `Type.[..]` 字面量落栈帧——跨返回作 slice = 悬垂（tt_scratch_files 首版实撞，堆数组修复）。
11. **手写 juice_test_N 与 EXPAND 生成名可撞**：统一枚举（US 14）的直接后果——编译期 duplicate test name 报错（旧 juice 手写名不可见故无此面）。

**移交面**：029 fixture 收口——E2E 家族已就位（test-blocks/test-blocks-fail/test-dep-root+test-dep-lib/tt-e2e-module scratch）；第三方插件全链路（扫描→merge→hook_table 进 test_command）留后续票——机制已立（hook_table 参数现成挂口）。
