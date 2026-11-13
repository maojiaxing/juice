---
id: 012
title: clean 命令
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [009, 010]
blocks: [014]
---

> 父 spec：`002-spec-build-clean-structure.md`（决定 12 + US 20/21）。上游规格：`docs/spec.md` §4.6（clean 序 c1-c3）；研究 L§1（clean 阶段清单）。

# 012: clean 命令

**What to build:** `juice clean` 端到端：发现（**不 prepare**）→ 路径收集 → **先全量校验后删除**（任一校验失败 = 不删 + 错误）→ 清根 target + 各成员 target（§3.5）。

**Blocked by:** 009（clean 的路径收集消费产物计划/成员面）+ 010（clean 是 dispatcher 的 handler）

**Status:** closed

- [x] 发现不 prepare → 路径收集 → 先全量校验后删除
- [x] 清根 target + 成员 target
- [x] 校验失败面：不删 + 错误 + 非零退出码
- [x] clean_tests 姊妹测试
- [x] E2E fixture clean（删除断言 + 校验失败不删断言）
- [x] 旧 juice build/test 于 otter 根零特判全绿（debug + release）
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话，本票不改 map.md）

## Resolution

**实现摘要**（新建文件 1 个测试 + fixture 6 文件；改写 4 个：src/commands/clean.jai 占位 → 真实现、src/main.jai 注释、tests/test_support.jai、tests/e2e_cli_tests.jai）：

- `src/commands/clean.jai`：clean 全链（语义等价重写自旧 juice commands/clean.jai:6-70，**零转译面**）：
  - `clean_command`：参数守卫 → `discover_workspace(ctx.root_dir, ctx.cache_dir)`（两参生产调用，modules_dir 默认推导 `<exe>/modules`——**发现不 prepare**，clean 不需要依赖/计划）→ 失败打印 `"[juice ERROR] Clean discovery failed; no files were deleted."` → `clean_discovered_workspace`；
  - `clean_path_is_safe`（生产校验门）：不存在 → 安全；symlink/junction → `"Refusing to delete symlink/junction: %"` + 拒绝；否则必须是目录；
  - `clean_discovered_workspace`（validate_path/delete_path 两 seam 形状逐字段保留旧 juice——1c 的 at 挂载点）：**收集**（有 manifest → 根包 + 每个成员包的 `<dir>/target`；无 manifest → `<root>/target`；legacy result/ 与 .packages 永不触碰）→ **先全量校验，任一不过一个不删**（校验阶段在 "Cleaning output directories..." 打印之前）→ 删除循环失败不中断（`"Could not delete: %"` + 继续删剩下的）→ 全成 `"[juice Clean] Workspace cleaned."`。错误文本逐条同旧 juice；删除经 `delete_directory_full`（009，Windows rmdir 反斜杠纪律）。
- `src/main.jai`：#load 序不动（clean.jai 已在闭包）；头注释更新（012 落 clean 真实现，剩余占位 run/test/version 归 013）。
- `tests/test_support.jai` 追加：clean seam 录制 fakes（test_clean_validated/deleted/invalid_path/failed_delete/expected_validations/deleted_too_early + reset_clean_test/test_validate_clean_path/test_delete_clean_path——旧 juice test_support.jai:231-256 语义，`deleted_too_early` 钉「校验完才删」违约）+ `make_test_link`（近直搬旧 juice test_support.jai:642-658——cmd mklink /J // /D 反斜杠纪律，机器拒绝 → false → SKIP 惯例）。
- `tests/clean_tests.jai`：14 块——编排 seam 4（收集面（根+成员序）/无 manifest 根/校验失败零删除/删除失败继续——旧 juice clean.jai 内联测试 4 名全映射）+ 生产校验门 4（不存在/真目录/常规文件/junction——junction 分支旧 juice 零测试，otter 单位级直测）+ E2E 6（真 otter exe：clean-fixture 删除断言（根+成员 target 整目录删除、源文件不动、无 target/ 的成员不失败）/常规文件占位 target 拒删（确定性，无 mklink 依赖——exit 1 + 零删除 + 无 Clean 打印）/junction target 拒删（mklink SKIP 惯例，`"Refusing to delete symlink/junction: "` 逐字节）/无 manifest 根清根 target（scratch）/发现失败不删（`"Existing package.jai is invalid."` + `"Clean discovery failed; no files were deleted."` 逐字节）/多余参数守卫（Usage + exit 1 + 零创建））。
- `tests/e2e_cli_tests.jai` 修订（011 偏差 5 同款）：占位命令测试移除 clean（真 clean 于 otter 根 = 删 otter/target——绝不进测试；argv 面由 clean_tests E2E 覆盖），test/version 保持占位断言。
- fixture 6 文件：`tests/data/clean-fixture`（根 BIN + 两成员 member_lib/member_extra——workspace-ok 同形状，无 DEP 声明（clean 永不 prepare）；fixture 从不提交 target/，测试运行时制造 + defer 清理）。

**验证矩阵**：

| 步骤 | 结果 |
| --- | --- |
| `jai build.jai`（旧 juice debug） | 成功 → target/juice.exe |
| 清 target/transpile → `juice.exe build` 于 otter 根 + `test`（debug） | exit 0，**163 passed, 0 failed**（149 + clean_tests 14） |
| `jai build.jai - release`（旧 juice release） | 成功 |
| 清 target/transpile → `juice.exe build` + `test`（release） | exit 0，**163 passed, 0 failed** |
| exe 冒烟：otter exe `clean` 于 clean-fixture 包根 | exit 0 + `"[juice Clean] Workspace cleaned."` + 根/成员 target/ 整目录删除 + 源文件不动；fixture 树零污染 |

旧 juice 对无 modules/ 包根的 import dir 探测提示为通用无害行为（map Notes 已记）。诊断期曾误跑旧 juice exe `clean` 于 otter 根（删掉 otter/target——生成件，重建零影响；fixture 树未触碰）。

**偏差清单**：

1. **发现走直接 `discover_workspace`（而非 ensure_workspace_discovered）**：状态机的发现入口会拒绝无 manifest 根（打印 `"No package.jai found in current directory."` + 失败）——旧 juice clean 显式支持无 manifest 根（内联测试 "Clean without a manifest uses the current root" + 本票 E2E 同款钉住），且会额外打印 `"Package '%' (v%) discovered."`（旧 juice clean 从不打印）。直接两参生产调用 = 旧 juice clean.jai:17 精确形状，002 决定 7「语义等价重写」优先；「发现不 prepare」意图不变。
2. **校验失败不删 E2E 两个变体**：常规文件占位 target（确定性、无 mklink 依赖）+ junction 拒删（mklink SKIP 惯例）；clean_path_is_safe 的 junction 分支旧 juice 零测试，otter 单位级直测补上。
3. **发现失败 E2E 用 workspace-bad-root-manifest**（坏根 manifest）：首跑实测钉住 workspace-bad-invalid-manifest 的坏 manifest 在**成员**（错误 = `"Workspace member manifest is invalid."` 而非根面），切换后断言与根面错误文本精确匹配。

**测试组织**：src 实现模块全部 test-free（bootstrap #load 集纪律）；测试驻 tests/（clean_tests 姊妹文件 + test_support 共享声明）。移交面：014 fixture 收口复用 run_otter_child_at + ensure_bootstrap_modules + make_test_link；013 run/version 无文件交集；clean 的 validate/delete 两 seam = 1c 的 at 挂载点（形状已按旧 juice 保留）。
