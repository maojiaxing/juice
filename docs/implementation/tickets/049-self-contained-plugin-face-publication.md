---
id: 049
title: 自包含插件面发布：相对 #load + 逐字闭包件
labels: [implementation, ready-for-agent]
status: closed
assignee:
blocked-by: []
blocks: [050, 051]
---

> 父 spec：`048-spec-installed-layout-plugin-loading.md`（决定 1-8、11-14；US 1-4、26-34、38-42）。上游规格：`docs/spec.md` §9.2、§11.11；ADR 0006（test-free bootstrap 闭包）。

# 049: 自包含插件面发布：相对 #load + 逐字闭包件

**What to build:** 每次构建与测试侧发布都产出可整体搬迁的 `modules/` 目录：`juice_core.jai` 只按模块相对路径加载四个插件面闭包件，四个闭包件逐字复制到 `juice_internal/plugin_face/`。发布产物不再携带构建机绝对路径；零插件工作区的测试生成文本逐字节不变。publication smoke 在裸导入下真实编译运行，证明相对加载成立。

**Blocked by:** None（可立即开工）

**Status:** closed

- [x] `juice_core` 生成器输出固定的相对 `#load "juice_internal/plugin_face/<file>"` 四行，不再接受或生成构建机 `src` 绝对路径；头注释改写为相对路径与来源说明；两个内置 plugin id 常量仍从定义源逐字抽取。
- [x] 发布步骤与测试侧发布器共享同一闭包文件清单与落点助手，把四个闭包件从定义源逐字复制到 `<modules>/juice_internal/plugin_face/`；不存在第二份文件清单。
- [x] 发布步骤先读定义源、发现面源与四个闭包件；任一缺失或不可读 = 发布失败 exit 1，且不写任何产物（不落半套）。
- [x] publication 姊妹测试更新：fake/real 生成文本 pin 为相对形态；四个复制件与源逐字节相等；缺源/缺常量响亮失败；publication smoke 写出新布局并在裸导入下真实编译运行。
- [x] bootstrap 姊妹测试的已发布产物逐字节 pin 随新产物集更新并通过。
- [x] 零插件测试 metaprogram 生成文本逐字节不变；既有安装布局（无插件）、真实成员 lint 全链、成员根测试不回归。
- [x] 根自跑套件 debug+release 与副本跑全绿；记录 found/passed/白名单，不预钉绝对值。

## Resolution

**实现摘要**（2026-10-21）：插件面发布自包含。`juice_core.jai` 生成器改为固定的四行模块相对 `#load "juice_internal/plugin_face/<file>"`，不再接受或生成构建机 `src` 目录/绝对路径；四个闭包件（transpile / transpile_plugin / lifecycle / plugin）由构建发布步骤与测试侧 `ensure_published_modules` 从 `src/` 逐字复制到 `<modules>/juice_internal/plugin_face/`。两侧共享既有 `JUICE_CORE_LOAD_FILES` 清单与同一落点助手族（无第二份文件清单）；发布前批量读取定义源、发现面源与四个闭包源共六源，任一缺失 = 构建侧 exit 1 / 测试侧 false，且工具侧零写入（无半套产物）。生成头注释改写为相对路径与逐字复制件来源说明；两个内置 plugin id 常量仍从定义源逐字抽取。零插件 metaprogram 生成文本零改动（`src/test_metaprogram.jai` 未编辑，其字节锁测试全绿）。

**生产面改动**：

- `C:/Users/maojiaxing/Workspace/projects/jai/otter/src/publication.jai`：`publish_juice_core(module_source)` 去掉 `src_dir` 参数，按 `JUICE_CORE_LOAD_FILES` 发射 `juice_plugin_face_relative_dir()` 相对 `#load` 四行；新增 `JUICE_PLUGIN_FACE_SUBDIR :: "plugin_face"`、`juice_plugin_face_relative_dir()`（生成侧引用的相对目录）、`juice_plugin_face_dir(modules_dir)` 与 `juice_plugin_face_file_path(modules_dir, file)`（落点侧）——生成侧与落点侧同源（`JUICE_INTERNAL_DIR` + `JUICE_PLUGIN_FACE_SUBDIR`）；文件头与生成头注释同步（相对路径、复制件、048 决定 5 的 Jai 事实）。
- `C:/Users/maojiaxing/Workspace/projects/jai/otter/build.jai`：发布步骤在写任何文件之前批量读六源（定义源、发现面源、`JUICE_CORE_LOAD_FILES` 四闭包源），缺失/不可读 = exit 1；创建 `juice_internal/plugin_face/` 后逐字写四件复制件；发布步骤注释同步（048 决定 3/4/7）。

**测试面改动**：

- `C:/Users/maojiaxing/Workspace/projects/jai/otter/tests/test_support.jai`：`ensure_published_modules` 采用同一前置读批 + 闭包逐字复制（同一清单、同一助手族），创建 plugin face 目录并落四件；头注释同步。
- `C:/Users/maojiaxing/Workspace/projects/jai/otter/tests/publication_tests.jai`：fake/real `juice_core` 文本 pin 改为相对形态（并断言无 `C:`、无 `<otter_root>`、无 `/src/`）；landing paths 测试新增相对目录与两落点助手钉；新增「Real source: the plugin face closure copies are byte-identical」（四件逐字节相等 + 生成 `#load` 目标全部落地 + 发布文本无构建根）；新增「Publish: a missing plugin face closure source fails the test-side publication」（临时移走 `src/lifecycle.jai` → `ensure_published_modules()` 返回 false，defer 恢复并复发布）；publication smoke E2E 写新布局（`juice_internal/plugin_face/` 四件，先整删缓存），真 jai 子进程在裸导入下编译运行照旧。
- `C:/Users/maojiaxing/Workspace/projects/jai/otter/tests/bootstrap_tests.jai`：debug 自举 E2E 追加四件复制件逐字节钉；release E2E 追加四件存在性钉；既有 missing discovery source E2E 追加「四件复制件也不落」；新增「E2E: a missing plugin face closure source fails the self-build without a partial publication」（`src/lifecycle.jai` 不在 build.jai 自身的 `#load` 闭包内，故自举仍能编译并到达发布步骤；先整删 `target/modules`，自举 exit 1 后六件零残留；defer 恢复源并复发布，测试隔离）。

**验证矩阵**（2026-10-21，串行；每次 test 前清 `target/transpile` / `target/testing-module` / `target/plugins`；证据 `otter/target/audit-049-*.txt`）：

| 步骤 | 命令 | 结果 |
| --- | --- | --- |
| 1 | `jai build.jai` | exit 0（`audit-049-01-build-debug.txt`） |
| 2 | `target/juice.exe test`（debug） | exit 0；**483 found**（`juice_test_N` 最大编号 478 + 手写 `note_suite_*` 5）；296 passed / 0 failed；`expect failed` 恰 6 行白名单；**SKIP 2**（自锁环境形态，`audit-049-02-test-debug.txt`） |
| 3 | `jai build.jai - release` | exit 0（`audit-049-03-build-release.txt`） |
| 4 | `target/juice.exe test`（release） | exit 0；同步骤 2：483 found、296 passed、白名单 6、SKIP 2（`audit-049-04-test-release.txt`） |
| 5 | `cp target/juice.exe target/juice-copy.exe`；`target/juice-copy.exe build`；`target/juice-copy.exe test` | build exit 0；test exit 0；**483 found**、296 passed / 0 failed、白名单 6、**SKIP 0**（权威，`audit-049-05-copy-build.txt` / `audit-049-05-copy-test.txt`） |
| 6 | `target/modules/juice_core.jai` 检查 | 仅四行相对 `#load`；无 `otter_root` / 盘符 / 反斜杠；四个加载目标全部存在；四复制件 `cmp` 与 `src/` 同名源逐字节相等；发布树 = 三模块面 + 发现源 + 四复制件（`audit-049-06-artifact-inspection.txt`） |
| 7 | 既有安装布局（无插件）E2E、真实成员 lint 全链 E2E、成员根套件 | 均在套件内执行；套件 exit 0 且白名单无新增 = 全绿；插件注册路径的真实子进程（plugin scan / lint 全链）经相对 `#load` 编译 `juice_core` 成功 |

**计数**（基线 480 found = 475 + 5，294 passed）：本轮 **483 found = 478 + 5**（+3 新测试：复制件逐字节钉、测试侧缺闭包源、自举缺闭包源 E2E）。终局 `296 passed` 与基线的 +2（而非 +3）是 Testing 自测 `finish()` 重置计数器的既有约定位移（032/033/037 已记录：终局 M passed 因重置小于 found），不是测试丢失；权威口径按 found 与「白名单恰 6 行 + exit 0」。

**偏差/风险**（无遗留缺陷）：

1. **SKIP 数不变**（直跑 2 / 副本 0）：新增的自举缺闭包源 E2E 无需自锁守卫——缺源在发布步骤即失败于链接之前，直跑环境同样能完整观察；未新增受守卫测试。
2. **终局 passed 位移**：见上「计数」，沿用既有约定不预钉绝对值；本轮 0 failed、exit 0、白名单 6 行不变。
3. **安装布局的插件工作区全链 E2E 不在本票**：本票以 publication smoke（全新缓存目录 = 可搬迁 modules 树）+ 既有插件 E2E（真子进程）证明相对加载；scratch 安装 + 真实成员 + lint 的全链归父 spec 048 的后续票（050/051）。
4. **私有性不变**：`juice_internal/plugin_face/` 与既有 `juice_internal/` 同为约定私有 `#load` 目标，编译器导入路径可见性是既有已接受事实（048 决定 13），未新增公开 import 面。
5. **文档折回未做**：`docs/spec.md` §0/§3.2/§3.3/§9.2/§11.11 与 `old-juice-exit.md` 的折回归 048 决定 15 的收尾票（050-052），本票未改父 spec 048 与 050-052。
