---
title: 剥离前端合一：探测与视图计算入 test-free 共享模块
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: []
---

> 架构体检（improve-codebase-architecture）候选 2（2026-10-14 会话）；Top recommendation。候选 3（Testing 模块 STRIP 特例收口）以此为前提，另立票。

## Problem Statement

闭包探测与视图计算是两条平行实现——不是 seam，是复制：

- build.jai（bootstrap）：`bootstrap_probe_closure` / `bootstrap_view_of` / `bootstrap_strip_front`（23-218 行，约 170 行）
- src/dependency.jai（runtime）：`probe_package_closure` / `view_of_file` / `Build_View_State`（228-384 行），Build command 与依赖剥离前端共用

同一 DFS、同一 0/1/2 状态机、同一「循环加载无法重写路径」诊断文案，各自演化。票 0049 已兑现一次漂移成本：依赖剥离前端只落在 runtime 侧，bootstrap 没跟上。根因：dependency.jai 含内联 test block，bootstrap metaprogram 的 `#load` 是文本包含、不能编译它；而 transpile.jai 能被 `#load` 正因为它 test-free（测试驻 src/transpile_tests.jai）——共享模块的约束与先例都已成立。

## Solution

新增 `src/transpile_front.jai`（test-free 共享剥离前端，测试驻 `src/transpile_front_tests.jai`）：

1. 自 dependency.jai 迁入：`Build_Source_File` / `Build_Closure_File` / `Build_File_Output` / `probe_visited` / `probe_package_closure`；自 commands/build.jai 迁入生产 transpile 步骤 `transpile_build_file`。
2. `Build_View_State` 泛化为 `Strip_View_State`，视图落点与入口处理按 `Strip_View_Layout` 参数化（两个 adapter 成立的真实 seam）：
   - `CONTENT_ADDRESSED`（runtime）：内容寻址视图路径（transpile_cache.jai），缓存命中跳过写入，入口落盘；
   - `PLAIN`（bootstrap）：`<base>/<rel>` 恒写、无缓存，入口视图不落盘、文本存 `entry_view`（喂 add_build_string，行号偏移恒 +5）。
3. `error_prefix` 字段注入报错前缀（runtime 默认 `"[juice ERROR] "`，bootstrap `"[Build System] ❌ "`）；读文件/建目录/写视图三条边角报错模板统一（既有文案未被任何测试钉住）。
4. 新增 `closure_has_tests` 共享判定（三处同体扫描收敛）。
5. bootstrap build.jai：`#load` 共享模块，`bootstrap_*` 机器（探测/视图计算/slashes）整体删除，`bootstrap_strip_front` 缩为策略组装（PLAIN 布局 + entry_rel + 前缀）。

## Acceptance criteria

- [ ] 三路径全绿：`jai build.jai`（debug/release）、`juice build` 自构建（复制 exe 避 LNK1104）、`juice test` 0 failed
- [ ] build.jai 的 bootstrap_* 探测/视图计算副本清零（bootstrap_strip_front 缩为组装）
- [ ] dependency.jai / commands/build.jai 状态设置改 `Strip_View_State`（layout `.CONTENT_ADDRESSED`），has_tests 扫描改用 `closure_has_tests`
- [ ] `transpile_front_tests.jai`：迁入 2 块（transpile 步骤）+ 新增 PLAIN 布局（入口进内存、恒写、路径形状）与探测失败测试
- [ ] 既有测试原样通过（dependency 6 块、build seam 测试、golden 30 处 GOLDEN PASS）
- [ ] IMPLEMENTATION.md / CONTEXT.md 对齐

## Out of Scope

- Testing 模块 STRIP 特例收口（候选 3，另立票）
- 编译骨架收敛（候选 4，触碰 ADR 0006 决定 2，另行用户拍板）
- 内容寻址缓存并入 bootstrap（票 0031 已延后；PLAIN 布局保持恒写、不混用缓存）
- 路径斜杠小工具的全局去重（path_safety / manifest / transpile_cache 各有本地理由；bootstrap_slashes 随副本删除）

## Further Notes

- 语言：中文交流与文档。
- 验证前清 `target/transpile`（文件集变化会移测试编号，陈旧视图编号冲突——memory 已记）。
- 边角报错文案变化（未钉住）：runtime 的 "Could not read source file for build / Could not create view directory / Could not write view" 三条统一为中文模板（行为不变）；bootstrap 读失败路径由 rel 变 abs。

## Resolution

**剥离前端合一落地（2026-10-14），三路径全绿。**

1. **实现**（题述方案 1–5 全落地）：
   - 新增 `src/transpile_front.jai`（test-free 共享剥离前端）：`Build_Source_File` / `Build_Closure_File` / `Build_File_Output` / `probe_visited` / `probe_package_closure` 自 dependency.jai 迁入（读失败文案统一、`error_prefix` 参数注入）；`transpile_build_file` 自 commands/build.jai 迁入；`Build_View_State` 泛化为 `Strip_View_State`——`Strip_View_Layout`（CONTENT_ADDRESSED / PLAIN）参数化视图落点、缓存跳过与入口进内存，`error_prefix` 字段（默认 `"[juice ERROR] "`，bootstrap 传 `"[Build System] ❌ "`）；新增 `closure_has_tests` 共享判定；`front_slashes` 与 `front_view_exists` 为模块自包含的本地实现（bootstrap 不能依赖 path_safety/manifest 运行时代码——实施中经 `path_exists_as_regular_file` 未声明暴露，改本地谓词）。
   - `src/dependency.jai`：迁出机器处留指针注释；`prepare_dependency_strip_views` 状态改 `Strip_View_State`（layout `.CONTENT_ADDRESSED` + dep_name），has_tests 扫描改 `closure_has_tests`。
   - `src/commands/build.jai`：`transpile_build_file` 与其 2 块直测迁出；`build_plan_entry` 状态改 `Strip_View_State`（layout `.CONTENT_ADDRESSED`）。
   - `src/main.jai`：`#load "transpile_front.jai";` 于 transpile_cache 之后。
   - 根 `build.jai`：`#load` transpile_cache/transpile_front；`bootstrap_slashes` / `Bootstrap_*` 机器（约 170 行）整体删除，`bootstrap_strip_front` 缩为策略组装（PLAIN 布局 + entry_rel + 前缀）；文件 366 → 214 行。
2. **测试**（题述方案）：新增 `src/transpile_front_tests.jai`——迁入 2 块（transpile 步骤直测）+ 新增 4 块（PLAIN 入口进内存、PLAIN 恒写重写陈旧视图、closure_has_tests、探测失败）。
3. **既有测试簿记修正**：「Build forwards each prepared plan to compilation」读 `test_build_transpiled_*` 数组断言计数、此前依赖「前一个 fake 使用者恰好清空」的隐式不变量——transpile_front_tests.jai 按发现序排在 commands/ 之前后该不变量被打破（套件首跑 1 失败、latch 兜住）。补齐数组清零，断言零改动。
4. **文档**：CONTEXT.md 新增「Strip front」词条、Bootstrap build / Metaprogram generator 词条与 Relationships 补 0050 事实；IMPLEMENTATION.md 模块表新增 transpile_front 行、dependency 行补依赖剥离前端、内联测试段补 transpile_front_tests。
5. **验证**：`jai build.jai`（debug）与 `jai build.jai - release` 全绿（release 须经 `-` 分隔传参——`jai build.jai release` 的第二个位置参数会被 jai CLI 当作待构建文件）；`juice test` exit 0（debug 与 release 产物各一遍、30 处 GOLDEN PASS 原样、latch 5/0）；`juice build` 自构建成功（exe 复制进 target/ 后运行，juice_modules_dir 按运行 exe 位置推导）。

**边角文案变化（未钉住，行为不变）**：runtime 的 "Could not read source file for build / Could not create view directory / Could not write view" 三条统一为中文模板 + error_prefix；bootstrap 读失败路径由 rel 变 abs。
