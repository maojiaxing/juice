---
id: 018
title: test 命令 handler 全链
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [015, 017]
blocks: [019]
---

> 父 spec：`003-spec-test-note-discovery.md`（决定 9 + US 8-14/17/18）。上游规格：`docs/spec.md` §4.6（test 序 t1-t12 的 1b 子集）/§7.3；参照面：旧 juice commands/test.jai。

# 018: test 命令 handler 全链

**What to build:** `juice test` 端到端（占位 → 真实现）：参数校验（≤1 pattern）→ workspace 准备（ensure_workspace_prepared 三参形状）→ 文件收集（scan_walk + 排除集，015）→ 测试 metaprogram 生成 + spawn jai（017；no_output 形状）→ 退出码透传。零收集短路 `"No tests found"`（旧 juice t4 语义）；pattern 收集后过滤；`juice_test_N` 全局编号续号。E2E 复用 run_otter_child_at + ensure_bootstrap_modules；生成 driver 先 set_working_directory（链约定）。

**Blocked by:** 015（文件收集面）+ 017（metaprogram 生成面）

**Status:** closed

- [x] test 命令 handler：守卫/准备/收集/生成+spawn/退出码透传
- [x] 零收集短路 "No tests found" + pattern 收集后过滤 + 全局编号续号
- [x] test_command_tests 编排面（收集/spawn/短路/过滤 seam 矩阵）
- [x] E2E 起步：otter exe `test` 于 fixture（发现 + 执行 + 计数断言）
- [x] 旧 juice build/test 于 otter 根零特判全绿（debug + release）
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**（2026-10-19）：

- **src/commands/test.jai 占位 → 真实现**（旧 juice test.jai 语义等价重写，minus transpile 层）：`test_command`（守卫 → `ensure_workspace_prepared(root, cache, *workspace, force_dependencies = true)` → pattern 提取 → `test_prepared_workspace`）；**collect_test_files**（015 偏差 1 移交的生产排除谓词全集：`Test_Collect_Context{root, member_dirs}`——member 边界来自 discovery 快照跳 index 0；dir 侧 = dot 任意深度/root 级 target/tests/data/modules/member 列表/symlink+junction inspect；file 侧 = dot/非小写 .jai/根 manifest/jaix driver litter；失败消息 `"Could not scan package root for test sources: %"`）；**test_prepared_workspace**（collect/spawn 双 seam，build compile seam 同款姿态）：零文件短路 `"[juice Test] No tests found."` → `test_program_dir = <root>/target/test/`（session 产品 driver.jai/first.jai，clean 随 target/ 整删）→ driver 生成（testing_source = **exe 相对推导** `../src/module.jai`、package_root、文件 abs 路径列表——bootstrap 源面推导 = `get_path_of_running_executable` 的 bin_dir + `../src`，阶段 2 切 import 发布面注释标注）→ metaprogram 生成（workspace_name/intermediate_path = 包 target/import_dirs = `compiler_import_directories(packages_dir(root))`/build_file/package_view_paths = driver #load 同串/discovery_source = `../src/test_discovery.jai`/numbering_start = 1/pattern/path_pairs = (abs, rel)——017 移交面签名全照）→ 写盘 → `spawn_test_compiler = run_command("jai", "-quiet", metaprogram)` → 非零 = `"[juice ERROR] Test compilation failed."`。
- **src/test_discovery.jai + filter_test_entries**（018 面加法）：收集后子串过滤（大小写敏感、空 pattern 全保留、编号不重排）——纯函数面，generated metaprogram 内接线（`find_index_from_left` 免新 import）。
- **src/test_metaprogram.jai 018 扩展**：`Test_Metaprogram_Options.pattern: string = ""`；生成文本 = `pattern: string = "...";` 嵌入常量 + inject_test_runner 新形状（查重 compiler_report 后 `return` → `matched := filter_test_entries(...)` → `entries.count == 0` → `print("[juice Test] No tests found.\n")`（t4 语义——1b 单编译约束下"短路" = 打印不注入，编译成功退出 0）→ `matched.count == 0` → `print("[juice Test] No tests matched '%'.\n", pattern)` → 否则注入 matched 调用表）。
- **src/main.jai 接线**：scan_walk.jai + test_discovery.jai + test_metaprogram.jai 入 #load 闭包（commands/test.jai 前）；command.jai 删 command_not_implemented（零消费者）；scan_walk/test_discovery 头注释更新（接线完成）。
- **fixture**：tests/data/scan-fixture（16 文件静态镜像旧 juice 布局——dot/嵌套同名/member-a 子树/root 级 target+modules+tests/data）；test-fixture + test-fail 补 package.jai（exe 面 workspace 发现）。
- **tests/test_support.jai**：test command seam 录制 fakes（test_collect_test_files/test_spawn_test_compiler/reset_test_command_seam/test_command_prepared）+ file_contains（旧 juice 同款）。
- **tests/test_command_tests.jai +19 块**：filter 矩阵、声明/守卫契约、收集矩阵（静态 scan-fixture 七文件序 + 缺根 + driver litter 三面 + 链接 SKIP 惯例）、编排 seam 矩阵（零文件短路零 spawn 无目录、collect 失败传播、forward 产物面——driver #load 序 + Testing 面位置 + metaprogram 嵌入 isolation/path_pairs/numbering 1/pattern/intermediate/add_build_file、pattern 穿线、spawn 非零、真实收集组合 + member 剪除断言）、**E2E ×6**（test-fixture 发现执行排序计数、pattern 过滤、零命中、test-fail 失败续跑 + 映射坐标 + exit 1、零文件短路、无 @test 文件 metaprogram 级短路）。
- **tests/test_metaprogram_tests.jai**：EXPECTED_TEST_METAPROGRAM 字节锁更新（pattern 常量 + 新 inject 形状）+ pattern 嵌入面；slash 测试从全文本无反斜杠改为逐 quoted-path 钉死（018 print 行带合法 `\n` 转义）。
- **tests/e2e_cli_tests.jai**：占位块 → 守卫面（scratch 无包根 exit 1 发现错误 + 双参 plan-time 拒绝；真跑在 fixture 面——otter 根会编译全仓）。

**验证矩阵**（串行全跑，验证前清 target/transpile）：

| 步骤 | 命令 | 结果 |
| --- | --- | --- |
| 1 | juice `jai build.jai`（debug） | exit 0 |
| 2 | otter `juice build` + `juice test`（debug juice） | exit 0，**Found 236 tests**（216 基线 + 20 新）全绿 |
| 3 | juice `jai build.jai - release` | exit 0 |
| 4 | otter `juice build` + `juice test`（release juice） | exit 0，236 全绿 |
| 5 | 追加 3 次重复全跑（确定性复核，release juice） | exit 0 ×3，零 stall |
| 6 | exe 冒烟：otter exe `test` 于 test-fixture（含 pattern） | exit 0，"3 passed, 0 failed"/pattern "1 passed, 0 failed"，排序正确 |

（输出中旧 juice 对无 modules/ 包根的 import dir 探测提示 = 通用无害，忽略；末行 "102 passed, 0 failed" = 旧 juice Testing 模块自测 start-drain 重置计数器的既有行为，绿信号 = exit 0 + "Found 236 tests"。）

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **零入口短路落 generated metaprogram 内**：1b 单编译约束（003 决定 6）下发现 = 编译，test 列表命令期不可知——零文件在命令层短路（真跳过编译，t4 语义）；文件在但零 @test 入口由 metaprogram 打印 "No tests found" 后不注入（编译成功退出 0 = "短路"的 1b 等价形）。pattern 零命中同层（"No tests matched '%'."）。"Found N tests" 消息 1b 不产（N 编译期才知）——1c 可再议。
2. **driver/metaprogram 落 `<root>/target/test/`**（旧 juice 的 target/transpile 树无对应物——无转译层）；session 产品每次重生成，clean 随 target/ 整删。
3. **bootstrap 源面推导 = exe 相对 `../src`**：testing_face_source/discovery_face_source = `get_path_of_running_executable` bin_dir + "../src"（bootstrap 期 exe 恒在仓 target/；tests' bootstrap_juice_modules_dir 同款 dev-layout 姿态）——阶段 2 发布落位后切 import 发布面（005 复核面）。
4. **command_not_implemented 删除**（test 占位 = 最后消费者；零引用死代码）。
5. **otter 自身根 `otter exe test` 于 1b 撞 test 块语法错误**（"Semicolon expected after expression"）：otter tests/ 全是 test 块、无 EXPAND 转译不可编译——切线 A 的预期状态（1b 期间 otter 自身测试仍由旧 juice 跑；1c 内置 transpile 插件接管后自跑成立）。命令面行为正确（"[juice ERROR] Test compilation failed." + exit 1）。**发现修正 ×2**：generated 零命中 print 格式串 `'%.'` 错序（jai `%` 泛型说明符吞参数打印——输出缺句点；改旧 juice 原序 `'%'.`）；slash 测试全文本无反斜杠断言失效（018 print 行合法 `\n` 转义）——改逐 quoted-path 钉死。
6. **015 移交零改动**：生产排除谓词/`Test_Collect_Context.member_dirs` 列表形状照 015 偏差 1/3 直落；scan_walk.jai 只更新头注释（main.jai 接线完成）。

**019 移交面**：

- 命令面全链已真实现（fixture 面 6 块 E2E 起步）；019 = 003 的 fixture 收口：test-empty 静态 fixture 化（现为零文件 scratch）、pattern/编号面的 E2E 深化、spec 003 收口（US 20 全兑现核对 + 决定 1-10 直落 + spec.md §4.6/§7 折回）。
- 1b 语义锚点：零文件/零入口双短路（命令层 + metaprogram 层）、pattern 子串大小写敏感、排序 = 名词典 + juice_test_N 数值感知（016）、编号基 1（metaprogram 内 collect_test_entries 第四参）、退出码 = 编译失败/finish 断言 → exit 1。
- 测试纪律持续：新测试进程内零引 #run 常量（016 偏差 2 终局）——本票 20 新块零引用。

