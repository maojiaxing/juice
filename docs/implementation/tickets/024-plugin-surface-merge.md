---
id: 024
title: Juice_Plugin 表面 + 内置注册 + 合并查重
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [021, 023]
blocks: [025, 026]
---

> 父 spec：`004-spec-plugin-surface-skeleton.md`（决定 3/4/8/11 + US 1-3/9/22/23）。上游规格：`docs/spec.md` §5；参照面：jaix src/plugin.jai:10-35,148-157,336-471（get_plugin 契约 + merge_plugins 形状）。

# 024: Juice_Plugin 表面 + 内置注册 + 合并查重

**What to build:** `Juice_Plugin` 全字段（id/version/transpile/hooks/options_schema）+ `get_juice_plugin` 获取契约（派生指针 + `using` 继承 + `as_plugin` 上转，选项类型化编译期检查）+ 内置静态注册表（load/test 块两内置包装为 Juice_Plugin 值——静态数组 + 显式 #load 纪律，自动发现对内置件无收益）+ 合并查重（重复 id/异版本冲突/钩子挂点冲突/transpile claim 冲突 → 全部 ERROR 诊断 + 拒绝继续；合并产物直喂执行器无二次转换）+ 空注册表 = 缺省管线。

**Blocked by:** 021（Lifecycle_Hook 形状——挂点冲突校验面）、023（两内置插件——注册表内容）

**Status:** ready-for-agent

- [x] Juice_Plugin 全字段 + get_juice_plugin 契约形状（决定 3/4）
- [x] 内置静态注册表（两内置包装 + 静态纪律注释）
- [x] 合并矩阵（重复 id/异版本/挂点冲突/claim 冲突 → 全 ERROR 拒绝；合法集通过）
- [x] 合并产物直喂执行器（Merged 形状，无二次转换）
- [x] 空注册表 = 缺省管线（与 023 缺省一致）
- [x] 姊妹测试 + 旧 juice build/test 于 otter 根零特判全绿（debug+release）+ 238 存量不回归
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**：

- **`src/plugin.jai`**（新建，test-free——链约定 bootstrap #load 集纪律；jaix src/plugin.jai:10-35,148-157,336-471 语义等价重写）：
  - **`Juice_Plugin` 全字段**（spec 决定 3 逐字）：id/version（身份——进管线描述与缓存键）+ `transpile: *Transpile_Plugin = null`（可空；非空进声明序管线、继承行号保真契约与成对探测钩子）+ `hooks: [..] Lifecycle_Hook` + `options_schema: [..] Config_Option`；
  - **`Config_Option`（jaix 形状 {name, default: *void, validate}）** + `config_option` 类型化构造（default 收任意类型指针编译期多态擦进 *void——异构选项类型承载边界；validate = 组装后校验，options 指针经 using 下转型读类型化成员，"" 通过/非空拒绝/null 跳过）；
  - **`get_juice_plugin` 获取契约**（决定 4）：插件模块定义 `get_juice_plugin :: () -> *Juice_Plugin` + 尾注 `@juice_plugin`（**`JUICE_PLUGIN_NOTE` 常量**落 plugin.jai——025 词法锚点单一来源）；返回派生结构体指针（基类 `using` 继承 + 类型化 options 成员——配置侧编译期类型检查）；框架侧 **`as_plugin` 显式 cast 上转**（using 上转型需显式 cast——jaix spike 先例；非 using 派生结构体在此 cast 编译失败 = 类型门）；
  - **内置静态注册表**：`builtin_plugins`（load → test-block 声明序 = 缺省管线序）+ `builtin_load_plugin`/`builtin_test_block_plugin` 逐件构造器（Juice_Plugin.id 取 module.jai 的 TRANSPILE_PLUGIN_LOAD_ID/TEST_BLOCK_ID 单一来源常量——注册表与 package.jai 管线声明同身份；transpile 面 = 022/023 真内置插件包装）；静态纪律注释落文件头（内置件随工具分发、属 bootstrap #load 集——自动发现无收益，A§4.1，勿改）；
  - **`merge_plugins` 合并查重**（决定 11 + 任务钉定语义）：重复 id（同版本 = "duplicate plugin registration: %" / 异版本 = "plugin version conflict: % (% vs %)"）/空 id（"plugin id must not be empty"）/**at 挂点独占**（同阶段第二 at 钩子——同插件或跨插件——= "at hook mount conflict on stage %: % and %"；before/after 同挂点多钩子合法、声明序执行）/**transpile 面冲突 = 同管线重名 name 拒绝**（"transpile plugin name conflict: % (% vs %)"——otter 的 Transpile_Plugin 无关键字概念，name 即管线身份，jaix 关键字 claim 冲突的等价面）→ 全部诊断累积 + `ok=false` 拒绝继续；**`Merged_Plugins {plugins, hook_table, diagnostics, ok}`** 直喂执行器无二次转换（plugins = Transpile_Context.plugins 管线、hook_table = run_mounted_hooks 钩子表——经 register_hooks 拼接，空贡献不占槽 021 语义）；**空注册表 = 内置注册表**（与 resolve_pipeline 缺省同一约定，视图与键恒同管线）。
- **`src/lifecycle.jai` 追加 `stage_name`**：合并查重的挂点冲突诊断需阶段名报告面——枚举→名字映射是 lifecycle 域知识，落 021 模块（021 Resolution 已预告 024 在其表上迭代）；只增不改纪律延伸到映射。
- **`tests/plugin_tests.jai`**（新建，17 test 块——好测试标准 = 只测外部行为：给定插件值集 → 合并产物/诊断/拒绝面；假插件值 + 内置两真插件混搭，助手 prefixed `plug_` 命名）：派生结构体类型化成员编译期检查 + as_plugin 上转读基面 / config_option 形状与 validate 下转型通道 / 内置注册表形状（真内置面锚：load 有 edges 无 anchor、test-block 反之）/ 空注册表 = 缺省管线（空 == 显式内置注册表同产物钉死）/ 声明序喂管线与钩子表 / 重复 id 同版本 / 异版本冲突 / 空 id / at 跨插件冲突 / at 同插件堆叠冲突 / before-after 合法堆叠 / 重名冲突 / 与内置名相撞冲突 / 无面插件合法 / 多违规累积（序 = 插件序 × 每插件检查序 id→transpile→at）/ **合并产物直喂执行器**（merged.plugins → transpile_source 真 load 插件 EXPAND 占位 + merged.hook_table → run_mounted_hooks 录制钩子槽通道）/ 内置注册表驱动真缺省管线端到端（test 块 EXPAND → juice_test_1 + @test）。
- **main.jai 零改动**（020-023 先例）：首生产消费者 = 027。

**验证矩阵**（旧 juice 双路径，各先清 otter/target/transpile）：

| 路径 | juice build | otter build | otter test |
| --- | --- | --- | --- |
| debug | exit 0 | exit 0 | exit 0，**Found 326 tests**（309 基线 + 17 新），179 passed, 0 failed |
| release | exit 0 | exit 0 | exit 0，**Found 326 tests**，179 passed, 0 failed |

expect failed 白名单 4 行（module_tests Testing face 自测 :178/:183/:207/:212，debug+release 逐行同状，无新增）；debug test 额外连跑 2 次零 stall。

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **合并语义钉定**（任务授权，随票记录）：at 挂点独占（同阶段多 at 钩子 = 冲突，同插件堆叠同判）；before/after 同挂点多钩子合法（声明序执行）；transpile 面冲突 = 同管线重名 name 拒绝（jaix 关键字 claim 冲突的 otter 等价面）。
2. **合并诊断类型 = Transpile_Diagnostic**（无 level 字段——otter 020 形状与 jaix 异）：全部合并诊断即注册期拒绝（ok=false 承载拒绝语义）；line/column 恒 0（无源锚点——merge 只见插件值，jaix position=0 同款）。
3. **stage_name 落 lifecycle.jai**：挂点冲突消息需阶段名——映射属 lifecycle 域，021 模块追加（021 已预告 024 迭代面）；测试经消息文本钉 TRANSPILE/COMPILE 两映射。
4. **内置注册表 = 构造器函数 + New 堆存储**（非模块级静态数组）：transpile 指针须指向稳定存储——jaix get_plugin 的 New 先例（模块级含函数调用初始化器无先例）；每次调用构造新值（插件值无状态，跨测试零污染）；「静态」= 固定成员显式列表非自动发现（静态纪律注释落文件头）。
5. **JUICE_PLUGIN_NOTE 常量**：`@juice_plugin` 尾注文本单一来源落 plugin.jai（025 词法锚点消费面）。
6. **测试助手 prefixed（plug_ 前缀）**：测试程序单命名空间——lifecycle_tests 的 rec_*、transpile 测试的 synth/claim 系列已占裸名（023 偏差 2 同族）。
7. **Jai 事实钉 ×2**（编译期实证）：后缀 `.*` 解引用与 cast 结合须括号（`(cast(*string) p).*`——`cast(*string) p.*` 先 deref 后 cast → 类型不匹配）；真前向引用跨 #load 文件合法（struct 字段 `*T`/`[..] T` 与过程体引用后加载类型——spike 实证，plugin.jai 在测试程序词法序先于 transpile_plugin.jai）。
