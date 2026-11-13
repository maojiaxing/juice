---
id: 025
title: 插件包扫描 + 注册文件 codegen
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [024]
blocks: [029]
---

> 父 spec：`004-spec-plugin-surface-skeleton.md`（决定 9/10 + US 24/25/31）。上游规格：`docs/spec.md` §5.2；参照面：A§4.2（候选 (c) 机制链）+ Metaprogram_Plugins.jai:41（逐名 codegen）+ 015 扫描骨架。

# 025: 插件包扫描 + 注册文件 codegen

**What to build:** 插件包扫描——scan_walk 确定性 DFS 词法序 + 词法锚点识别 `@juice_plugin` 尾注挂 `get_juice_plugin` 声明（is_test_anchor 同款手法）+ 入口探测序（module.jai → src/module.jai → <name>.jai）+ 注册文件 codegen 两段（`JUICE_PLUGIN_<i>` 逐名 import 调用段 + `JUICE_HOOK_<i>` 钩子装配段）落 target/（会话产物、每跑重生、不进 bootstrap 闭包、不入库）。E2E：合成 fixture 插件包（tests/data/ 下，不进根 package.jai 依赖面）→ 生成注册文件 → 生成 driver 真 jai 编译加载 → 合并注册表执行（钩子触发）。

**Blocked by:** 024（Juice_Plugin 消费面 + 合并——生成件加载即消费）

**Status:** ready-for-agent

- [x] 词法锚点判定矩阵（挂载形状面 + 误报面）
- [x] 扫描序确定性 + 入口探测序（module.jai → src/module.jai → <name>.jai）
- [x] 注册文件两段形状测试（逐名 #import codegen + 钩子装配段，按扫描序）
- [x] E2E：fixture 插件包 → 注册文件 → 真 jai 编译加载 → 合并注册表执行（钩子触发）
- [x] 落点纪律（target/ 下、不入库、会话产物）
- [x] 姊妹测试 + 旧 juice build/test 于 otter 根零特判全绿（debug+release）+ 238 存量不回归
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**：

- **`src/plugin_scan.jai`**（新建，test-free——链约定 bootstrap #load 集纪律；spec §5.2 候选 (c) 机制链）：
  - **`scan_plugin_package`**：scan_walk 确定性 DFS 词法序（015 骨架 + 注入排除谓词：dot 前缀任意深度/根层 target//链接/jai x driver 垃圾谓词/非 .jai）+ 逐文件词法锚点识别 + 命中查重——**扫描序 = 注册序**；不可扫根 → ok=false（collect_scan_files 失败通道惯例）；读失败 → 诊断跳过；
  - **词法锚点识别 `is_juice_plugin_anchor`**（is_test_anchor 同款手法——词法判定不解析语法）：语句位（前显著 token ∈ {;}{}{，注记组回跳）IDENT `get_juice_plugin` + `::` → 声明尾界定（体括号匹配闭或 ";"）→ 尾注链查 `@juice_plugin`（ident 部分自 **JUICE_PLUGIN_NOTE 常量单一来源派生**，024 面）；防误报面 = 字符串/注释里出现不算（lexer 已消费成零 token）、注记挂别处不附着（尾界定域）、调用位不算（语句位门）；
  - **入口探测序 = 模块名派生 + 同名裁定**：module.jai → 包目录名（C§7.3 成员身份）；src/module.jai → `<dir>/src`；其余 → 包相对路径去 `.jai`（路径作用域——sub/extra.jai → "sub/extra"，根层即 `<name>.jai` 惯例）；同名冲突按探测序裁定（低秩胜；同级 = 扫描序先者胜）+ 落选诊断——探测序的可观测行为面；
  - **注册文件 codegen `generate_plugin_registration`**（决定 10 形状，两段按扫描序）：段 1 = `JUICE_PLUGIN_<i> :: #import "<模块名>";` 逐名 import + 段 2 = `JUICE_HOOK_<i>: [..] Lifecycle_Hook;` 钩子装配条目 + 装配过程 `get_scanned_plugins()`（显式逐名调用 + 条目填充）+ `get_scanned_hook_entries()`（显式序钩子表视图）；**落点 `plugin_registration_path`** = `target/plugins/<包名>/registration.jai`（会话产物、每跑重生、clean 随 target/ 整删、不进 bootstrap 闭包、不入库）。
- **`tests/plugin_scan_tests.jai`**（新建，9 test 块——好测试标准 = 只测外部行为：给定源文本/包路径 → 命中/模块名/生成文本/子进程输出）：锚点矩阵 ×2（命中面：尾注/注记链/无体声明/前注记声明不遮语句位；误报面：无注记/注记挂别处/调用位 ×2/字符串/注释/近失配 ×2/后声明注记不附着）/ 扫描序 + 模块名派生矩阵（词法序逐 hit 钉死 + 排除集四面 + abs_path）/ 同名裁定双形态（module.jai 胜 `<dir>.jai` 探针序 + 单文件双锚同级先者胜）/ 不可扫根失败通道 / codegen 两段逐字节形状 ×2（双命中 + 零命中全形）/ 落点助手 / **E2E 全链**（真 jai 子进程，`C:/Users/maojiaxing/DevTools/jai/bin/jai.exe` 绝对路径）。
- **E2E 合成 fixture 插件包 `tests/data/plugin-fixture/`**（测试发现豁免区，不进根 package.jai 依赖面；静态三文件）：module.jai（约定 1 入口——transpile 面 fixture-mark 改写 FIXTURE_SEEN + before-TRANSPILE 钩子）+ extra.jai（约定 3——after-COMPILE 钩子，钉扫描序）+ decoy.jai（误报面——字符串/注释/错挂注记/调用位，扫描零命中且永不编译）；全链 = 生产扫描 → 生产 codegen 落 target/plugins/plugin-fixture/registration.jai → **juice_core 种子**（target/modules/juice_core.jai，#load src 闭包——bootstrap 期库面替身）→ 生成 driver（#import "juice_core" + #load 注册文件）→ 真 jai 编译执行 → merge_plugins 合并执行：`plugins=2` / `pipeline-name=fixture-mark` / `transpile-view=x := FIXTURE_SEEN;` / 双钩子经 run_mounted_hooks 触发（before-diag=fixture-before-transpile / after-diag=extra-after-compile）/ hook-entries 序钉死。
- **main.jai 零改动**（020-024 先例）：首生产消费者 = 027。

**验证矩阵**（旧 juice 双路径，各先清 otter/target/transpile）：

| 路径 | juice build | otter build | otter test |
| --- | --- | --- | --- |
| debug | exit 0 | exit 0 | exit 0，**Found 335 tests**（326 基线 + 9 新），188 passed, 0 failed |
| release | exit 0 | exit 0 | exit 0，**Found 335 tests**，188 passed, 0 failed |

expect failed 白名单 4 行（module_tests Testing face 自测 :178/:183/:207/:212，debug+release 逐行同状，无新增）；debug test 额外连跑零 stall。

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **顶层调用非法 → 绑定与调用分离**（spike 实证 + research A E1/E2/E4 同款）：决定 10 字面形 `JUICE_PLUGIN_<i> :: (#import "<模块名>").get_juice_plugin();` 顶层 = "Attempt to perform a procedure call outside the body of another procedure"——生成文件把 `#import` 绑定为顶层常量、get_juice_plugin() 显式调用放进生成装配过程（Metaprogram_Plugins 先例同因：其逐名调用在 init_plugins_part_2 过程体内）。
2. **钩子装配段 = 每插件一条显式条目**（`JUICE_HOOK_<i>: [..] Lifecycle_Hook` + 装配填充 + get_scanned_hook_entries 显式序表）：决定 10 的 `.{}` 逐钩子条目生成期不可知——钩子 = 插件值内数据（L§5.4 明定非独立发现实体），扫描是词法面无从得知钩子名/数量；每插件条目 = 「显式序数据声明」的可执行形，序钉死在生成文件（L§5.4 缓存键零歧义目的）。
3. **类型同一性 → juice_core 按名导入种子**（spike 实证）：#load 同一文件进两个作用域 = 互不兼容的重复类型（"Type mismatch: incompatible structs"，同一声明文件两处实例）——fixture 插件模块与 driver 必须共享一个按名 #import 的模块面（Jai 按名去重）；bootstrap 期 E2E 生成 target/modules/juice_core.jai 种子（#load src 闭包、绝对路径生成文本——fixture 静态文件机器无关；真实插件 C§7.3 `#import "juice_core"` 同形，阶段 2 发布面替换）。
4. **模块名派生 = 路径作用域**：斜杠模块名 jai 支持（spike 实证 `#import "alpha/src"` 解析）；`<name>.jai` 惯例 = 根层文件主干（路径作用域的特例）。
5. **插件值 = 运行期构造**（New + array_add，jaix get_plugin 同款）：`::` 常量结构体字面量不能承载 `[..]` 数组字段（spike："All values provided in a non-imperative struct literal must be constant"）。
6. **JUICE_HOOK 装配序依赖**：get_scanned_hook_entries() 读装配过程填充的条目——须先调 get_scanned_plugins()（生成文件注释文档化）。
7. **扫描排除集** = dot/根层 target/链接/垃圾谓词/非 .jai；插件包自身 tests/ 不排除（成员包测试目录无锚无害——生产谓词全集归 027）。
8. **Jai 事实钉 ×3**（编译期实证）：顶层调用非法（偏差 1 依据）；#load 双作用域类型不统一（偏差 3 依据）；`array_add(ctx.diagnostics, …)` 须直传指针字段（前缀 `*` 恒取地址——`*ctx.diagnostics` 取字段地址成双指针，024 偏差 7 同族）。
9. **main.jai 零改动**：扫描面 = 库面（决定 9「1c 扫描不接命令编排面」），fixture E2E 消费；生产接线随 027。
