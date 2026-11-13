---
id: 009
title: target 解析 + 依赖 shim 面
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [008]
blocks: [011, 012]
---

> 父 spec：`002-spec-build-clean-structure.md`（决定 8/9 + US 8-14）。上游规格：`docs/spec.md` §2.1/§3.3/§3.6；研究 C§2/C§3/C§6/C§7。

# 009: target 解析 + 依赖 shim 面

**What to build:** targets/依赖声明 → 产物计划与 shim 消费面：UNSPECIFIED 推导序（targets → src/main.jai → import entry → BIN）；LIB 声明 targets = `LIBRARY_TARGET_CONFLICT` 硬错误；同名 target（大小写不敏感）= `DUPLICATE_TARGET_NAME` 硬错误；产物落点 = `target/<name>.exe`。依赖只经 shim 消费（shim 生成/接线）、DEP.name 无校验（异名 DEP 官方形态）、相对 DEP 只指向成员或根（根 CWD 纪律）、无传递闭包（每包显式全闭包）。

**Blocked by:** 008（target 解析消费 workspace/成员发现面）

**Status:** closed

- [x] UNSPECIFIED 推导序四分支
- [x] LIB 声明 targets / 同名 target 两硬错误（错误文本契约）
- [x] 产物计划：target/<name>.exe
- [x] 依赖 shim 生成/消费 + 相对 DEP 纪律 + 无传递闭包
- [x] target_tests + dependency_tests 姊妹测试（推导/冲突矩阵/shim 形状）
- [x] 旧 juice build/test 于 otter 根零特判全绿（debug + release）
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话，本票不改 map.md）

## Resolution

**实现摘要**（新建文件 2 个 src + 2 个测试 + 9 个 fixture 文件，改写 3 个）：

- `src/target.jai`：target 层全链（语义等价重写自旧 juice target.jai:8-238）。`Target_Resolution_Error`（12 成员）/`Target_Resolution_Result`/`Artifact_Plan_Result` 正式落位（**008 偏差 3 收口**：workspace.jai 的前置声明已删，Target_Resolution_Result 随旧 juice 形状一并落位）；`make_resolution_failure`/`make_artifact_failure`；`validate_package_identity`（name 便携文件名/version 非空/dir 真实目录）；`make_effective_target`（name/main_file 便携门 → 源存在 → 非常规拒绝 → 包根内）；`library_import_entry`（先根 module.jai 再 src/module.jai）；`derive_package_type`（**推导序四分支**：targets → src/main.jai → import entry → BIN）；`validate_library_package`（targets → `LIBRARY_TARGET_CONFLICT` "Library package '%' cannot declare executable targets."；无入口 → `MODULE_ENTRY_NOT_FOUND`）；`resolve_effective_targets`（显式 targets 逐个校验 + **equal_nocase 撞名 → `DUPLICATE_TARGET_NAME`** "Target name collides with another target: %1"）；`make_artifact_plan`（**产物统一 `<包根>/target/<name>.exe`**）；`resolve_artifact_plans`；`revalidate_artifact_plan`（build/run 共用大门：根安全 + 路径在根内 + target_dir/artifact 形状门）。错误文本逐条同旧 juice。
- `src/dependency.jai`：依赖层全链（语义等价重写自旧 juice dependency.jai，**不含 strip front——转译面归 1c**）。`Source_Type`/`detect_source_type`（git schema 表 + `git@` + `.git` 尾，其余 LOCAL）/`clean_local_path`；`find_files_recursive`/`find_package_in_repo`；`packages_dir`（`<root>/target/packages`）/`compiler_import_directories`（build/test 共享派生，旧 juice 从 build.jai 移来的同款）；`dependency_shim_content`（**shim 格式单一来源**：注释行 + `#load "<绝对入口>"`）；`ensure_import_shim`（**三布局探测序** module.jai → src/module.jai → 单文件 `<name>.jai`；单 shim 不链目录；无布局/缺失源目录 → true 留编译器）；`resolve_and_fetch_dependencies`（建目录 → 消费快照）/`link_workspace_member_dependency`/`find_workspace_member`/`fetch_workspace_dependencies`（**成员按名 link 不 fetch**——DEP source 被忽略，成员相对 source 永不按根 cwd 误解析；fetch/link_member 双 seam 可注入；失败即传播 "Failed to link workspace member: %1"/"Failed to fetch dependency: %1"）/`fetch_dependency`（LOCAL：**相对 source 锚进程 cwd = 包根**（juice 永不 chdir），**DEP.name 逐字消费无校验**；GIT：缓存克隆 → find_package_in_repo → 裸模块兜底）；`get_directory_path`/`get_git_repo_cache_path`/`ensure_git_repo_cloned`/`delete_directory_full`（Windows rmdir 反斜杠纪律）。
- `src/path_safety.jai` 追加 6 函数（008 决议「path_is_portable_* 等 target 面留 009」兑现）：`path_backslashes`/`path_is_symlink`/`path_exists_as_directory`/`path_exists_as_regular_file`/`path_is_portable_filename`（Windows 保留名 CON/PRN/AUX/NUL/COM1-9/LPT1-9 拒绝）/`path_is_portable_relative_jai`——近直搬（002 决定 7）。
- `src/workspace.jai`：**008 偏差 2 收口**——resolve/prepare_dependencies 两 seam 补生产默认值 `= resolve_artifact_plans` / `= resolve_and_fetch_dependencies`（跨文件前置引用 = 旧 juice workspace.jai:148 先例；两文件在 main.jai #load 序中位于 workspace 之后）；前置声明块删除；三 seam 至此全有生产默认。
- `src/main.jai`：#load 闭包接入 target.jai + dependency.jai（workspace 之后——旧 juice 序 xdg → path_safety → manifest → workspace → target → dependency 同款）。
- `tests/target_tests.jai`：26 块——便携路径门 2（文件名/相对 .jai 矩阵）+ 解析矩阵 12（unnamed/缺入口/非便携名/非便携源/缺源/非常规源/有效声明/多产物/重复名（大小写不敏感 + 精确重复）/近似名通过/身份三拒绝（非便携名/空版本/缺根，错误文本逐字节））+ LIB 面 4（targets 冲突逐字节/缺入口逐字节/零计划/显式 LIB 接受 src 入口）+ 推导四分支 5（根入口 LIB/src 入口 LIB/默认入口 BIN/无入口留 BIN/隐式 src/main.jai 非常规）+ revalidate 大门 1——旧 juice target.jai 内联测试 11 名全映射 + 新矩阵。
- `tests/dependency_tests.jai`：18 块——来源类型矩阵/本地路径清洗/packages_dir 派生/git 缓存路径净化 + shim 面 7（**shim 形状逐字节**/三布局各一/根布局优先/无布局跳过/缺失源目录跳过）+ 工作区依赖面 5（成员 link 不 fetch（fetch/link 录制 fakes——旧 juice 语义）/link 失败传播/fetch 失败传播/按名匹配/DEP.name 逐字消费（异名 `juice_core` shim 形状））+ 准备面 1（建目录 + 真 link）+ **E2E 1**（生成 driver 真 jai 子进程：真求值器子进程发现 workspace-ok → 真 resolve_and_fetch_dependencies 于 scratch 根 → 两成员 shim 逐字节（member_extra 的相对 source 被 link 忽略）+ 相对 source 异名 fetch 逐字节）。
- `tests/test_support.jai`：`library_fixture_package`/fetch+link 录制 fakes + `reset_dependency_recording`/`shim_content_for`/`dependency_prep_driver_code` + `run_dependency_prep_child`；workspace 发现 driver 补 #load target.jai + dependency.jai（workspace seam 默认值引用面）。
- fixture 9 文件：`tests/data/target-{lib-module,lib-src-module,bin-package}`（旧 juice lib-module/lib-src-module/bin-package 同款）+ `tests/data/dep-fixture/{shim-pkg,file-pkg,root-pkg,both-pkg,empty-pkg}`（旧 juice shim-fixture 同款 + both-pkg 探针序新增）。

**验证矩阵**：

| 步骤 | 结果 |
| --- | --- |
| `jai build.jai`（旧 juice debug） | 成功 → target/juice.exe |
| 清 target/transpile → `juice.exe build` + `test` 于 otter 根（debug） | exit 0，**126 passed, 0 failed**（含 dep E2E driver 1 块） |
| `jai build.jai - release`（旧 juice release） | 成功 |
| 清 target/transpile → `juice.exe build` + `test`（release） | exit 0，**126 passed, 0 failed** |

126 = 008 的 82 + target_tests 26 + dependency_tests 18。fixture 树零污染（E2E 全走 scratch 根）。旧 juice 对无 modules/ 包根的 import dir 探测提示为通用无害行为（map Notes 已记）。

**偏差清单**：

1. **GIT 依赖分支零测试**（旧 juice 同状先例）：`find_package_in_repo` 内 `load_package_manifest` 走生产推导（modules_dir="" 默认）在 bootstrap 测试程序不可命中，且真 git clone 属网络面不可确定——与旧 juice 一致零测试；`detect_source_type`/`get_git_repo_cache_path` 纯函数已测。fetch_workspace_dependencies 的 fetch seam 保留可注入形状，未来如需 GIT 面测试经 seam 注入。
2. **E2E driver 须显式 `set_working_directory`**：实测 jai 编译期相对路径锚在**入口文件目录**（#run 期 `get_working_directory()` = driver 所在目录，run_command 的 working_directory 不影响）——首跑 rel fetch 静默锚错至 driver 目录（「无布局」分支假绿，dep_rel shim 缺失）。driver main() 首行 chdir 到 otter 根，模拟生产纪律（juice 进程 cwd = 包根、永不 chdir）。已存记忆（jai-child-cwd-anchoring）——011-013 的生成 driver 同纪律。
3. **`ensure_import_shim` 的 normalize 失败分支 = 防御性死代码**：normalize_existing_path 从不验证存在性（008 实测钉住），缺失源目录走「无布局」分支返回 true（无 shim 留编译器）——测试文档化（"Import shim skips a missing source directory"）。
4. **依赖 strip front 不在本票**（shim_load_target/collect_shim_names/prepare_dependency_strip_views）：转译面归 1c（002 范围切线 C）；1a 的 build/test 直编译原文。
5. **`both-pkg` fixture 为新增**：旧 juice 无「根 + src 双布局并存」探针序直测（语义在代码，无测试）；otter 以 fixture + 逐字节断言钉住根布局优先。

**测试组织**：src 实现模块全部 test-free（bootstrap #load 集纪律）；测试驻 tests/（target_tests/dependency_tests 姊妹文件 + test_support 共享声明，旧 juice src 内联测试语义先例）。Jai 事实备忘：`#type` seam 默认值跨文件前置引用（旧 juice workspace.jai:148 先例，main #load 序 workspace 先于 target/dependency 照旧容忍）；driver 子进程编译期 cwd = 入口文件目录（见偏差 2）。
