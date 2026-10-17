---
title: Package 配置面：TRANSPILE_PLUGIN 协议记录 + 校验门 + 组装接线
status: closed
labels: [ready-for-agent]
assignee: maojiaxing
blocked-by: [0062]
---

> 父 spec：`issues/0060-spec-transpile-pipeline-pluginization.md`（决定 6 + Testing Decisions 接缝 4）。057 先例（manifest jaix 标记协议 + 校验矩阵）。

# 0063: Package 配置面：TRANSPILE_PLUGIN 协议记录 + 校验门 + 组装接线

**What to build:** 包作者在 package.jai 声明自己的转译管线（jaix 风格：插件 id + version + 类型化选项槽）——Package 声明面新增管线字段；manifest 求值器按声明序打印 `TRANSPILE_PLUGIN=<id>|<version>` 可重复协议记录（JAIX_CONFIG 同族先例：恒打印）；严格解析两 case（重复 = Duplicate ... record.）+ 纯函数校验门（validate_jaix_marker 同款拆分：未知 id / 重复 id / 非法选项 = 诊断拒绝；load 路径进程内不可测的测试缝同款）；build/test 组装按声明序建管线（声明序 = 管线序）；**未声明 = 缺省管线**（两内置插件按现状交互契约——现状行为零变化）；显式声明两内置插件（缺省序）== 缺省管线（视图与缓存键同值）。v1 两内置插件选项集为空（选项槽就位、无实际选项行——跨进程协议只带 id+version）。

**Blocked by:** 0062（声明管线变化必须先有缓存键敏感面——否则显式声明包的视图陈旧正确性隐患）

**Status:** ready-for-agent

- [x] Package 声明字段（id + version + 类型化选项槽）+ 求值器 `TRANSPILE_PLUGIN=<id>|<version>` 记录（声明序、可重复、恒打印）
- [x] 严格解析两 case（重复拒绝）+ 校验门矩阵（未知 id / 重复 id / 非法选项 = 诊断拒绝；可测缝拆分）
- [x] build/test 组装接线：声明序 = 管线序；未声明 = 缺省管线（现状行为零变化）
- [x] 单测/矩阵 + E2E：fixture 包显式声明两内置插件（缺省序）→ 视图与缓存键与缺省同值；声明未知 id → 清晰拒绝
- [x] 三路径全绿 + golden 30/30 零重定

## Resolution

### 实现摘要

- **声明面（modules/Juice.jai）**：`Transpile_Plugin_Option`（选项行：key/value）、`Transpile_Plugin_Declaration`（id + version + 类型化选项槽）、`Transpile_Pipeline_Declaration`（plugins 切片——package.jai 作者可写 `.{ plugins = .[ .{...}, .{...} ] }`，定长数组字面量赋值位衰变、Package 家风格）；`Package.transpile` 新字段（空 = 缺省管线）；`TRANSPILE_PLUGIN_LOAD_ID` / `TRANSPILE_PLUGIN_TEST_BLOCK_ID` 常量 = v1 合法声明 id 集（bootstrap 装载序使注册表与声明模块不可互见——同步由 transpile_config.jai 内联测试锁定）
- **求值器协议记录（src/manifest.jai build_eval_code）**：`PACKAGE.transpile.plugins` 循环按声明序打印 `TRANSPILE_PLUGIN=<id>|<version>` 可重复记录（JAIX_CONFIG 同族：恒打印；零声明 = 零记录 = 缺省）；选项不跨进程（id+version only——jaix「选项值不跨进程」同款立场）
- **严格解析两 case + 校验门**：parse_manifest_data_strict 新 case——形状违规 = `TRANSPILE_PLUGIN record must contain id|version.`（jaix PLUGIN 先例措辞）+ 重复 id = `Duplicate TRANSPILE_PLUGIN record.`（JAIX_CONFIG 先例措辞，带行号）；`validate_transpile_pipeline` 纯函数校验门（validate_jaix_marker 同款拆分：未知 id / 重复 id / 非法选项 = 诊断拒绝——重复 id 双检有意重叠：解析层带行号覆盖协议文本、门层为程序化构造 Package 的单一校验函数）；load_package_manifest 接线（`[juice ERROR] Invalid transpile pipeline at %: %`）
- **组装（新 src/transpile_config.jai，main.jai 装载、非 bootstrap #load 目标）**：`resolve_transpile_pipeline(decls)` 声明 → 内置注册表实例，声明序 = 管线序；零声明 = 空管线——「空 = 缺省」解析保持 resolve_pipeline 单一落点（视图与键恒同管线）；未知 id 防御性跳过（生产路径门已拒，程序化构造不崩溃）
- **build/test 接线（seam 增默认空第三形参 `pipeline: [] Transpile_Plugin = .[]`）**：spike 钉住本版 jai 无闭包（「Closures are not supported.」）、缺省参 #type 可省略调用、函数与 #type 参数个数须严格一致——唯一零测试改动注入通道。`transpile_build_file` / `transpile_test_file` 填 `ctx.plugins`（0062 偏差 4 预接位点兑现——键位点零回头改）；`Strip_View_State.pipeline` + `view_of_file` 传递；`probe_package_closure` 增 pipeline 参数（闭包探测聚合配置管线）；build_plan_entry / test_prepared_workspace 按 root package 声明建管线并注入 probe 与 seam；两录制 fake 增参并记录管线摘要（组装接线断言通道）
- **测试（224 → 242）**：manifest 内联 9 块（声明序解析 / 空声明缺省 / 两严格 case / 门矩阵三拒绝 + 合法面 / codegen 协议形状锁）；transpile_config 内联 4 块（声明序组装 / 零声明 = 空管线 + 单一落点 / 未知 id 防御跳过 / 门与注册表 identity 同步锁）；姊妹文件 1 块（显式两内置缺省序 == 缺省：STRIP 与 EXPAND 双 seam 视图+键+诊断同值）；组装接线 2 块（build/test 各一：声明管线以声明序到达 seam、未声明 = 空）；E2E 2 块（fixture `tests/data/pipeline-explicit`：真实 juice.exe build → 视图落在缺省管线纯契约路径、逐字节同值、树内恰两视图文件（键变必多文件）+ 真实 juice.exe test 通过；fixture `tests/data/pipeline-unknown`：未知 id → exit 1 + `Unknown transpile plugin id: mystery-plugin`、零视图落盘）

### 验证结果

- 三路径全绿（先清 target/transpile）：`jai build.jai`（debug）+ `jai build.jai - release` 构建成功；`./target/juice.exe test` debug 与 release 产物各验一遍 = **exit 0** + latch「Testing module register stays clean between tests」**5/0** + **30 GOLDEN PASS** 零重定（无 JUICE_UPDATE_GOLDEN 运行）+ **242 passed, 0 failed**（224 + 新增 18 块）；`juice build` 自构建绿（exe 复制为 target/juice-build.exe 运行，毕后删除——LNK1104 规避）
- 零行为变化证据：既有三测试文件（transpile_tests / transpile_front_tests / metaprogram_tests）逐字节未改、原样通过；golden 零 UPDATE；jaix 系 E2E（pre-step build/test、monorepo、工作树 `../jaix` 自然解析）原样通过

### 偏差清单

1. **依赖视图与 jaix mirror 排除集恒缺省管线**：依赖包 Package 不留存于 Prepared_Workspace（仅 root + members），按依赖自身声明建管线需逐依赖重求值 manifest（子进程面）——超出本票接线范围，留未来票（dependency.jai 注释已立）；jaix_front 镜像排除集同理恒缺省
2. **Testing 模块视图（build STRIP / test EXPAND 两特殊 case）恒缺省管线**：Testing 模块是 juice 自身基础设施（非用户包源码），其视图语义（自测内联、编号续走）与用户管线声明解耦
3. **声明 version 不校验、不进键**：v1 按 id 解析到内置注册表实例，缓存键反映解析后的内置 version；version 选择/校验语义与选项面同留后续（spec 门矩阵只有未知 id / 重复 id / 非法选项）
4. **类型化选项槽执行级形状 = key/value 选项行**：v1 两内置插件选项集为空、任何选项行被门拒（「选项槽就位、无实际选项行」）；story 27 的「编译期成员检查」理想留未来选项面（选项行在 manifest 编译期可写、load 期响亮失败——不静默）
5. **seam #type 增默认空第三形参**：本版 jai（beta 0.2.009）无闭包（spike 钉住），per-package 管线绑定无法以函数值完成——管线改为显式数据参数（默认空 = 现状零变化），两录制 fake 定义机械增参（tests/test_support.jai，非锁定三测试文件）；「编辑以 token 为界」等 0061 语义不受影响
6. **求值器 codegen 测试为形状锁**：求值器子进程循环的完整行为由 E2E 覆盖（真实 juice.exe），进程内以 build_eval_code 输出含 `TRANSPILE_PLUGIN=%1|%2` 记录形状锁定（manifest_hash_hex 注释确立的装载序约束下 codegen 文本是唯一进程内可测面）
