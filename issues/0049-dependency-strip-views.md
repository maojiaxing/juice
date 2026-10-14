---
title: 依赖剥离前端：含 test block 的依赖/member 包源码在消费者构建与测试程序中剥离
status: closed
labels: [wayfinder:task]
assignee: maojiaxing
---

## Question

ADR 0004 的剥离保证 = 入口同包字面量 `#load` 闭包；依赖（含 workspace member）源码经 import shim 被消费者直接 `#load`，out-of-package 不转译——依赖 src 内联 test block 会破坏消费者构建（0044 断言 4 / 0046 票注：member 测试不放 `src/module.jai`）。packrat（LIB 库）要把 105 块单元测试内联进 src，其 demo（juice member）构建与测试程序都会以依赖身份编译 packrat 源码——此缺口必须关闭。

方案（本票）：

1. **依赖剥离前端**（`src/dependency.jai`）：import shim 是进入依赖闭包的入口。对 `target/packages/` 下每个 shim：解析 `#load` 目标（依赖导入入口的绝对路径）→ 以依赖包为根探测入口的字面量 in-package `#load` 闭包（`probe_package_closure`，自 build.jai 泛化迁入）→ 闭包含 test block 时整闭包 STRIP 视图（ADR 0004 全有全无语义），视图落 `target/transpile/deps/<依赖名>/<hash>/<rel>`（`transpile_dependency_view_path`），并把 shim 重写指向入口视图。test-free 依赖零转译、shim 原样。
2. **Build 与 Test 共用**：`build_prepared_workspace` 在消费者闭包探测前调用；`test_prepared_workspace` 在 compile seam 前调用（新增 `dep_transpile` seam 参数，默认生产步骤）。依赖中的 test block 不被发现、不执行（Test discovery 不扫依赖包）——两路径只做剥离编译。
3. **探测/视图机制迁移**：`Build_Source_File` / `Build_Closure_File` / `Build_File_Output` / `Build_View_State` / `closure_index` / `view_of_file` / `probe_package_closure` 自 build.jai 迁入 dependency.jai（依赖域持有者，票 0038 内聚方向）；build.jai 的 `probe_build_closure` 变为薄封装。
4. **测试**：dependency.jai 内联单测（shim 解析、test-free 依赖零动作、含 test 闭包视图+shim 改写、`..` 逃逸 #load 保持 verbatim、坏 shim 留编译器）；monorepo E2E 更新——workspace-ok 的 member_lib 入口（src/module.jai）内联 test block + #load 同含 test block 的 extra.jai：root build 经剥离视图编译且 artifact 输出不变、root test 编译通过且 member 测试不执行、member 自为 root 跑自身 3 测试。
5. **文档**：CONTEXT.md（Build / Test driver / Transpile / Local dependency directory 词条）、ADR 0004 修订。

## Acceptance criteria

- [ ] `jai build.jai` + `./target/juice.exe test` 全绿（新增 src 测试块后先清 `target/transpile` 缓存）。
- [ ] 新单测与更新后的 E2E 全部落地且全绿。

## Out of Scope

- 传递依赖（依赖的依赖）的剥离：依赖自身的 `#import` 仍解析不到消费者 packages_dir 之外的 shim，与现状一致。
- 非 shim 路径的 out-of-package `#load`（如相对路径逃逸到依赖包内部）的剥离：保持 verbatim（issue 0008 决议 4 语义不变）。
- GIT_URL 依赖的剥离 E2E（member-link 路径已覆盖机制）。

## Resolution

**依赖剥离前端落地（2026-10-14），`jai build.jai` + `./target/juice.exe test` 175 passed / 0 failed（退出码 0）。**

1. **实现**（题述方案 1–3 全落地）：
   - `src/dependency.jai`：依赖剥离前端——`dependency_shim_content`（shim 格式单一来源）、`shim_load_target`（lexer 解析 shim 入口）、`get_filename`、`collect_shim_names`（确定性枚举）、`probe_package_closure`（自 build.jai 泛化迁入）、`prepare_dependency_strip_views`（闭包含 test → 整闭包视图 + shim 改写；test-free/missing/坏 shim 零动作）。`Build_Source_File` / `Build_Closure_File` / `Build_File_Output` / `Build_View_State` / `closure_index` / `view_of_file` 同迁（`Build_View_State` 增 `dep_name` 字段，视图落 `deps/<名>/...`）。
   - `src/transpile_cache.jai`：`transpile_dependency_view_path`（`<transpile>/deps/<名>/<hash>/<rel>`）。
   - `src/commands/build.jai`：`probe_build_closure` 薄封装；`build_prepared_workspace` 在 revalidate 后调 `prepare_dependency_strip_views`（run 经 build 继承）。
   - `src/commands/test.jai`：`test_prepared_workspace` 增 `dep_transpile` seam 参数（默认 `transpile_build_file`），compile 前调同一前端。
2. **测试**（题述方案 4）：
   - dependency.jai 内联 6 块：shim 解析 / test-free 零动作 / 含 test 闭包视图+改写 / `..` 逃逸 verbatim / 坏 shim 留编译器 / 无 shim 目录 no-op。
   - workspace-ok fixture：member_lib 入口 `src/module.jai` 内联 test block + `#load "extra.jai"`（extra 同含 test block）——此前必破坏消费者构建的形态。
   - E2E 更新（tests/test_monorepo.jai）：build E2E 断言 shim 改写到 `deps/member_lib/.../module.jai` 视图、extra.jai 视图按纯函数契约路径重建且 test 被剥离、artifact 输出不变；root test E2E 断言 member 三类测试均不执行 + deps 子树存在；新增「member 自为 root 跑自身 3 测试」E2E。
3. **文档**（题述方案 5）：CONTEXT.md 四处（Build / Transpile / Local dependency directory / Relationships）+ ADR 0004 修订（决定 4 边界扩大，shim 可达依赖闭包纳入剥离保证）。
4. **验证**：`jai build.jai` 零回归；`./target/juice.exe test` **175 passed / 0 failed**（含 6 块新单测 + 新 member-own E2E；Testing 模块自测 drain 语义不变）。真实验证在 packrat 侧随 C1 内联迁移复验（juice run / member test 路径）。

**Jai 事实**：`return probe_package_closure(...)` 不自动展开多返回值——包装器须显式 `files, ok := ...; return files, ok;`（bootstrap 首编译暴露）。
