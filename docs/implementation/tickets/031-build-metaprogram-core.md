---
id: 031
title: build.jai metaprogram 核心（ADR 0006 照抄）
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [032]
---

> 父 spec：`005-spec-stage2-build-metaprogram.md`（决定 2/3/10 + US 1-8/23/24）。上游规格：`docs/spec.md` §10 阶段 2；参照面：旧 juice build.jai 全文件（ADR 0006 参照实现）+ juice/docs/adr/0006。

# 031: build.jai metaprogram 核心（ADR 0006 照抄）

**What to build:** `jai build.jai` 与 `jai build.jai - release` 于 otter 根 exit 0 产出 target/juice.exe——`- release` 开关自扫（get_toplevel_command_line）；Default_Metaprogram 抑制（set_build_options_dc + 空 workspace）；test-free #load 闭包（头注释钉名单 = 阶段 2 契约）；剥离前端（探测入口闭包：test-free 直编原文 / 含 test 全有全无 STRIP 视图落 target/transpile/bootstrap/，PLAIN 布局恒写）；Testing 特例（STRIP 视图 + import path 前置——**本票暂用种子源**，发布面接线随 032）；bootstrap 选项组装（绝对 output/intermediate 路径——子进程 CWD 纪律 + very_optimized 移交点兑现）+ 生成编译器 metaprogram + spawn 子进程 jai；失败语义 = exit(1) + 子进程错误输出。

**Blocked by:** None (can start immediately)

**Status:** closed

- [x] `jai build.jai`（debug）exit 0 产 target/juice.exe
- [x] `jai build.jai - release` exit 0 产 release exe（`-` 分隔符消费 = metaprogram 自扫）
- [x] Default_Metaprogram 抑制 + #load 闭包 test-free 名单头注释钉死
- [x] 剥离前端（PLAIN 布局 target/transpile/bootstrap/ 恒写、与命令内容寻址缓存不混用）
- [x] Testing 特例（种子源 STRIP 视图 + import path 前置）
- [x] 选项组装绝对路径 + very_optimized 移交点兑现
- [x] 失败语义（exit 1 + 子进程错误输出透传）
- [x] 姊妹测试/E2E（真 jai 子进程两模式）+ 旧 juice 不变式 debug+release 4/4 + 409 存量不回归
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**（2026-10-20）：

- **`build.jai`**（新建，根级——ADR 0006 全形状语义等价重写，参照面非复制）：
  - **头注释钉 #load 闭包名单**（005 US 24 = 阶段 2 契约）：src/transpile.jai → transpile_plugin.jai → transpile_cache.jai → transpile_front.jai → metaprogram.jai（全部 test-free——测试驻 tests/；#load 代码进 metaprogram 执行环境、不进被构建程序）；另钉**入口锚定 Jai 事实**（偏差 1）与 Testing 种子源形状（偏差 6）。
  - **`- release` 自扫**：get_toplevel_command_line 扫描 `release`/`-release`（含 `debug`/`-debug` 回退）；**first.jai 守卫 = 活的**（偏差 3）。
  - **Default_Metaprogram 抑制**：`set_build_options_dc(.{do_output=false})` + `compiler_create_workspace("Bootstrap Delegation")`——空 workspace = 「构建已自理」信号（创建失败 exit(1)，旧 juice 形状的 return 改响亮失败）。
  - **`bootstrap_build_entry`**：probe_package_closure（error_prefix "[Build System] ❌ "）→ test-free 直编原文（零转译零落盘）/ 含 test 全有全无 STRIP 视图——Strip_View_State + PLAIN 布局落 `target/transpile/bootstrap/`（恒写、与命令内容寻址缓存不混用）+ closure_index/view_of_file 入口视图返回；入口视图经 add_build_file 编译 = 精确 file:line 诊断。
  - **Testing 特例**：`testing_module_strip_view_dir(root, <root>/target/modules/Testing.jai, "[Build System] ❌ ")`——种子源（ensure_bootstrap_modules 产物；依赖既有种子、build.jai 不生成；缺失退化 "" 零变化；032 同路径换发布面）；`testing_view_dir != ""` 时生成器前置 import path。
  - **选项组装 + 子进程**：`bootstrap_compiler_metaprogram_options`（metaprogram.jai 新纯函数）→ 写 target/bootstrap-meta.jai → `make_directory_if_it_does_not_exist("target")`（LNK1104 面）→ `run_command("jai", meta_path)`；退出码 != 0 → exit(1)（子进程输出实时透传，父收集打印被吞 = 已钉事实）。
- **`src/metaprogram.jai`**（011 移交点兑现）：`very_optimized: bool = false` 字段 + 发射 `set_optimization(*options, .VERY_OPTIMIZED);`（import_path 赋值后、set_build_options 前；false 零发射——存量字节锁零影响）+ `bootstrap_compiler_metaprogram_options` 纯函数（root 派生绝对 output/intermediate——子进程 jai #run cwd 切 target/ 后相对路径会落 target/target/ 的 058 偏差 ④ 纪律；import_dirs = src + target/modules + root——偏差 4）；**路径归一化 path_slashes → front_slashes**（偏差 5，头注释钉闭包内引用纪律）。
- **`tests/bootstrap_tests.jai`**（新建，6 块）：单元 3（选项组装绝对路径契约/very_optimized 开关/发射字节形状与序）+ E2E 3（**otter 根真实自构建 debug**——exit 0 + PLAIN 视图落位（bootstrap/src/main.jai + src/module.jai）+ testing-module 视图 + bootstrap-meta + 产物 version 冒烟「juice 0.1.0」；**release**——exit 0 + 产物冒烟；**缺失种子失败路径**——park Juice.jai 种子（file_delete + defer 恢复）→ exit 1 + 子进程错误含 "Juice"——「exit 1 + 子进程错误输出透传」E2E 钉）。
- **main.jai 零改动**；旧 juice 仓零改动；publication.jai 未接线（032 面）；种子生成器未动（030 形态继续）。

**验证矩阵**（各先清 otter/target/transpile；自构建产物冒烟 = version 输出逐字节「juice 0.1.0 / jai 0.2.9」）：

| 步骤 | 结果 |
| --- | --- |
| 旧 juice debug：`jai build.jai` → otter 根 `juice.exe build` + `test` | build exit 0；test exit 0，**Found 438 tests**（432 + 6）、255 passed, 0 failed |
| 旧 juice release：`jai build.jai - release` → 同两命令 | build exit 0；test exit 0，**Found 438**、255 passed, 0 failed |
| 自举 debug：otter 根 `jai build.jai` | exit 0 + target/juice.exe + version 冒烟 exit 0 |
| 自举 release：otter 根 `jai build.jai - release` | exit 0 + target/juice.exe（583KB vs debug 986KB）+ version 冒烟 exit 0 |
| expect failed 白名单 | 恰 6 行（module_tests :178/:183/:207/:212 + src/module.jai :304/:330），无新增 |
| 加分冒烟：自构建 exe 于 otter 根 `build` | LNK1104 hand-off 真路径全通（副本接管 → 重建 → exit 0） |

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **入口锚定 Jai 事实（E2E 设计根因）**：metaprogram #run 的 cwd/get_working_directory 锚定**入口文件目录**（build.jai 所在 = otter 根）、且**进程级**（run_command 子进程继承）——与调用 shell cwd、working_directory 均无关（首跑实证：`cd fixture && jai <otter>/build.jai` 的产物全落 otter/target）。后果 ① build.jai 恒自构建本包（产品语义）——scratch fixture E2E 从根上不可行（fixture 闭包永不被探测）→ **E2E = otter 根真实自构建**（票内定形；顺序执行安全——产物同源，套件 E2E 家族在自构建产物上全绿 + 自构建 exe 于根 build 的 hand-off 冒烟 = 自举方向实证）；后果 ② 子进程 jai #run cwd 切 target/ = 同族（058 偏差 ④）。已入记忆 jai-child-cwd-anchoring。
2. **探测失败 exit(1)**：旧 juice 形状 = `return`（exit 0 + 收集打印刷出）——005 US 8 CI 可见性改 exit(1)；exit(1) 吞父收集打印 = 已钉 Jai 事实，前子进程失败面窄（不可读源/转译结构诊断/#load 环），编译期语法/语义错误照常经子进程全量输出。
3. **first.jai 守卫是活的（非防御）**：两代测试程序全包扫描都 #load 根级 build.jai（旧 juice 编译入口 target/transpile/first.jai、otter 自家 target/test/first.jai）——两端均名 first.jai，共享 `ends_with "/first.jai"` 后缀检查拦两端；首跑实证（守卫按 otter 形状写时，旧 juice 测试程序编译期执行了构建树——"Could not open file target/transpile/src/main.jai"）。头注释已钉两端。
4. **import dirs = src + target/modules + root**：旧 juice 形状 src + modules + root——otter 无仓内 modules/，种子家 = target/modules（032 发布面同落点）；无条件添加（缺目录仅无害探测提示；缺 Juice 种子 = 子进程响亮 unresolved import）。
5. **metaprogram.jai 路径归一化 path_slashes → front_slashes**：path_safety.jai 不在 bootstrap #load 闭包（首跑编译错误实证）——同语义自包含实现（transpile_front 面）；闭包内引用纪律（quote 对 → transpile.jai、front_slashes → transpile_front.jai、#load 序钉死）入头注释。
6. **Testing 特例源 = 种子 target/modules/Testing.jai**：依赖既有种子、build.jai 不生成（种子生成器留测试侧——票内钉形状）；模块源传绝对路径（otter testing_module_strip_view_dir 契约，旧 juice 传包相对）；032 同路径换发布面（发布面含自测块 = 特例持续触发）。
7. **无 LNK1104 hand-off**（005 决定 10 兑现形 = ADR 0006 形状）：bootstrap 假设产物未运行（首次构建）；运行中 exe = 子进程 LNK1104 响亮失败；自构建 exe 的 build 命令自带 hand-off（011 面，本票冒烟实证）。
8. **无版本断言**（005 决定 9 → 032 面）。
9. **测试文件 run_command 全 splat**：固定参与 splat 混排撞 011 偏差 7 钉（"previous argument already started occupying the varargs slot"）——程序路径进数组整体 splat。

**032 移交面**：build.jai #load 名单现成（发布接线 = #load src/publication.jai + 发布步骤段，Testing 特例源同路径切发布面）；very_optimized/选项组装/两模式 E2E 现成（版本断言 + 种子退役接线后复用）；otter 根自构建 E2E 模式现成（033 自测方向沿用）。
