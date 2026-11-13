---
id: 061
title: jaix 搬入成员包 + 安装布局 E2E
labels: [implementation]
status: closed
assignee: maojiaxing
blocked-by: [060]
blocks: [062]
---

# 061: jaix 搬入成员包 + 安装布局 E2E

> 上游规格：`docs/spec.md` §3.2/§3.3/§5.2/§8.3（2026-10-21 设计修订）。这是“把 jaix 从工具本体赶出去”的落点。

**What to build:** 把 `src/jaix_plugin.jai` 搬成 `packages/juice-plugin-jaix/` 成员包：`package.jai` + 根 `module.jai`（test-free）+ `tests/`；删除静态注册；经命令级 prepare + host 加载；安装布局 E2E；守卫白名单清空。

## 交付

1. `packages/juice-plugin-jaix/`
   - `package.jai`：`name = "juice-plugin-jaix"`、`version = "0.1.0"`、`type = .LIB`、零工具依赖（`juice_core` 由工具提供）、无 targets。
   - `module.jai`：`#import "juice_core"`；`get_jaix_plugin` + `@juice_plugin`；id `juice-plugin-jaix`；PRESTEP hook、options schema（config/exe）、插件自带扫描/spawn/镜像/litter；test-free。
   - `tests/`：插件单元测试（scan 矩阵、options apply/validate、替换表/剔除集、litter 清理）以成员自身为 root。
2. 工具侧清理
   - 删除 `src/jaix_plugin.jai`；`src/plugin.jai` 静态注册表移除 jaix 行。
   - 根 `package.jai`：`workspace.members` 加 `packages/juice-plugin-jaix`；`plugins` 保留 jaix 声明（id 不变）；无同名 DEP（声明即激活）。
   - 守卫白名单清空：`src/` 零 `jaix` / `JAIX`。
3. 接线验证
   - 命令级 prepare 按声明定位 jaix 成员、写 shim/注册；host 应用 options、执行 PRESTEP；build/test 两条链真实 jaix E2E 全绿。
   - 成员根测试（`../../target/juice.exe test` 于成员根）全绿。
   - 安装布局 E2E：scratch 安装（exe + `modules/`）、真实成员包、jaix 声明、host 加载、build/test 全链；缺成员/缺 shim/缺插件面的负例。
4. 发布/分发
   - 成员包是普通可复制源码；不携带 juice 检出路径；`juice_core` 由工具提供。
   - 发布件数量不变；插件面闭包副本与 `src/` 逐字节核（行数更新）。

## 验收

- `src/` 零 jaix 引用（无白名单）；守卫绿。
- 真实 jaix build/test E2E（Phase 1 的用例）在成员包 + host 形态下全绿。
- 安装布局全链 E2E 绿；成员根套件绿；零插件包行为不变。
- `jai build.jai` debug exit 0；根 test 全绿；计数基线记录。

## Out of scope

- 外部插件抓取（非 workspace member）。
- 通用 host / 其他 stage。
- spec 收口（062）。

## Resolution

**2026-10-21，实现完成。**

实现摘要（按交付项）：

1. `packages/juice-plugin-jaix/` 成员包
   - `package.jai`：`name = "juice-plugin-jaix"`、`version = "0.1.0"`、`type = .LIB`、无 targets/依赖；`juice_core` 由工具提供，不声明 DEP、不携带检出路径。
   - `module.jai`：`#import "juice_core"`；`get_juice_plugin` + `@juice_plugin` 尾注；id `juice-plugin-jaix` @0.1.0；PRESTEP `before` hook；options schema `config`/`exe`；插件自带整包扫描（自己的 walk + 排除集，含 test-block 文件探测）、逐文件 spawn、`target/jaix/` 镜像、`target/jaix-drivers/` CWD、litter 识别/清理/剔除；test-free。
   - 插件不能复用工具内部的 `scan_walk` / `path_safety` / `xdg.get_env`（均不在 `juice_core` 发布面）：成员自带等价的确定性 DFS 枚举、路径助手与 Windows/POSIX 环境探测。
   - `tests/jaix_plugin_tests.jai`：17 个单元测试（identity/options、声明版本+options 解析门、scan 矩阵/剔除集、exe 解析、替换表/剔除集、litter 头窗口/CRLF/清理），以成员根为包根运行。
2. 工具侧清理
   - 删除 `src/jaix_plugin.jai` 与 `src/main.jai` 的装载行；`src/transpile_config.jai` 的 `command_plugin_registry` 只返回内置值（`load` / `test-block`），静态 `static_builtin_plugins` seam 消失（058 deviation 记录的是注册落点不在 `src/plugin.jai`，故删除落点在 `transpile_config.jai`）。
   - 根 `package.jai`：`workspace.members` 加 `packages/juice-plugin-jaix`；`plugins` 声明 `juice-plugin-jaix`（id/version 不变、无 options = 定义好的 no-op 前置）；无同名 DEP。
   - 守卫白名单清空（`JAIX_GUARD_WHITELIST :: Jaix_Guard_Allowance.[]`），`src/` 全量文本扫描零命中。
3. 接线验证
   - 命令级 prepare 按声明定位 jaix 成员、写 import shim 与 `target/plugins/registration.jai`；host 应用 options、执行 PRESTEP；build/test 两条链的真实 jaix E2E（Phase 1 的 build/test/失败/缺 exe/未声明用例）在成员 + host 形态下全绿。
   - 成员根 `../../target/juice.exe test`：exit 0、`17 passed, 0 failed`。
   - 安装布局 E2E：scratch 安装（`bin/juice.exe` + 递归 `bin/modules/`，无同级 src/target）、真实成员包整树复制、jaix 声明（exe 走绝对路径，不依赖 PATH），build 产出执行 lowered try/catch 的 artifact、test 跑 3 个测试；负例：缺成员（Unknown plugin id，prepare 失败）、缺 shim（成员无可导入入口布局 → 注册导入无法解析 → host 编译失败）、缺插件面（删安装内一份 plugin_face 闭包副本 → host 编译失败）。零插件包不写注册、不 spawn host。
4. 发布/分发
   - 成员包为普通可复制源码（E2E 以整树字节复制为证）；`juice_core` 由工具提供。
   - 发布件数量不变（3 模块面 + 1 发现源 + 4 插件面闭包副本 = 8）；四份闭包副本与 `src/` 逐字节相等，行数 **571 / 553 / 364 / 596**（本次未改这四个源文件——删除的静态 registry 在 `transpile_config.jai`，它不在发布闭包内，故票面预期的“行数更新”不适用）。
   - 安装内 `juice_core` 仅相对 `#load`、安装树无构建根泄漏（沿用 051 的 `scan_published_tree` 门）。

验收证据（可复现）：

- `src/` 零 jaix 引用：`grep -rni jaix src/` 无输出；`Jaix guard: src carries no jaix token at all (empty whitelist)`（外加 scratch 根负向自测 `Jaix guard: the scanner turns red on a seeded violation (negative self-test)`）。
- 真实 jaix build/test E2E（Phase 1 用例）：`E2E: jaix pre-step build compiles the mirror through the member and host`、`E2E: jaix pre-step test compiles the mirror and keeps the mixed package`、`E2E: a jaix transpile failure propagates diagnostics and produces no artifact`、`E2E: a missing jaix executable fails the pre-step with a clear error`、`E2E: an undeclared package runs no pre-step and spawns no host`——全绿；host 记录文件含 `SUBSTITUTE=src/main.jai|…` / `DROP=jaix.config.jai` / `OK=1`。
- 安装布局全链 E2E：`E2E: an installed juice runs the real jaix member through the host`（含缺插件面负例）、`E2E: an installed juice fails loudly when the jaix member is missing`、`E2E: an installed juice fails loudly when the member shim cannot land`——全绿。
- 成员根套件：`E2E: the jaix member package root runs its own suite green`；手工复跑 `cd packages/juice-plugin-jaix && ../../target/juice.exe test` → `17 passed, 0 failed`。
- 零插件包行为不变：`E2E: a package without plugins never spawns the host`、`Test command: zero member plugins never spawn the host`（060 既有测试）保持绿；本票新增的未声明 E2E 断言无 `target/plugins/`。
- `jai build.jai` debug exit 0；`jai build.jai - release` exit 0；根 test exit 0。

验证数字：`rm -rf target/transpile && ./target/juice.exe test` exit 0，末行 `329 passed, 0 failed`（Testing 自测 `finish` 重置，非条目数）；直跑 SKIP 2（自托管 posture）。release 产物副本于根 test exit 0、**SKIP 0**、`329 passed, 0 failed`。权威 found = 最大 `juice_test_N` **537** + 手写 `note_suite_*` @test **5** = **542**（060 基线 556；旧根 jaix 文件 24 个测试（19 单元 + 5 E2E）→ 新根文件 10 个集成/E2E，净 -14；成员根套件另计 17）。成员根套件 17 passed。

Deviations：

1. 静态注册 seam 的实际落点是 `src/transpile_config.jai` 的 `command_plugin_registry`（058 已记录该偏差），不是票面写的 `src/plugin.jai`；删除落点随实现走。`src/plugin.jai` 本身无 jaix 行。
2. 成员插件无法复用工具内部模块：`scan_walk` / `path_safety` / `xdg.get_env` 都不在 `juice_core` 发布面（spec §11.14 明示成员不发布 scan_walk）。成员自带确定性 DFS 枚举、路径助手与 Windows/POSIX 环境探测（`GetEnvironmentVariableA` / `getenv`），行为与 058 等价（scan 矩阵/litter 用例原样迁移）。
3. 根 `package.jai` 以**无 options** 的 jaix 声明激活成员：`config` 空 = 定义好的 no-op 前置，根自身构建不做 jaix 工作，但每次根 build/test 会因声明了携带 hooks 面的成员而多 spawn 一次 host（记录 `OK=1`、零效果）。这是“声明即激活”的直接结果。
4. 发布闭包四件未改（行数 571/553/364/596 不变），票面“行数更新”不适用：被删除的静态 registry 位于 `transpile_config.jai`，不是发布闭包成员。
5. 单元测试从根 `tests/jaix_plugin_tests.jai` 迁入成员 `tests/`（17 个）；根文件保留 10 个集成/E2E 测试（含 registry seam 移除、成员/安装布局/零插件用例）。根 found 基线因此由 556 变为 542。
6. “缺 shim”负例建模为“成员包无任何可导入入口布局（无 module.jai / src/module.jai / \<name\>.jai）”：成员链接按既有语义不写 shim，注册导入 `plugin` 在 host 编译期无法解析并响亮失败。未用“packages 目录不可创建”形态，因为 build 的依赖准备会先于插件 prepare 以别的错误失败，覆盖不到注册/导入链。
7. jaix-demo 静态 fixture 现在声明 `workspace.members`（成员 id 路径 root 相对），但静态树不携带成员源码：E2E 将 fixture 复制到 scratch 并把真实成员整树复制到 `packages/juice-plugin-jaix`（workspace member 必须在 root 内，不能引用检出路径）。
