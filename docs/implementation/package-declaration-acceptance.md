# 包声明语义验收记录（ticket 0096）

本文件是 `issues/0087-spec-package-declaration-semantics.md` 的验收证据：29 个实现决策、16 个验收组
A01–A16、10 个示例 E01–E10 的覆盖映射，三条发布路径的实际执行结果，以及明确未验证项。

`target/evidence/` 是易失区（`clean` 会删除它），因此结果摘要落在本文件；原始日志仍留在
`target/evidence/`，需要重放时按 §7 的命令重跑。

## 1. 环境事实

| 项 | 值 |
| --- | --- |
| 工作树 | `C:/Users/maojiaxing/Workspace/projects/jai/juice-impl-acceptance-verification` |
| 分支 | `implement/acceptance-verification` |
| 起始提交 | `1003f7251db616b824ab45f197e7116717d85841`（`integration/package-declaration-semantics` tip，0097 关闭提交） |
| 编译器 | `C:/Users/maojiaxing/DevTools/jai/bin/jai.exe`，`jai 0.2.9`（`juice version` 输出） |
| 平台 | Windows 10.0.26300.9974（`cmd /c ver`）；Git `2.56.0` |
| 大小写敏感文件系统 | **未验证**（本机只有默认的 Windows 大小写不敏感卷，无 WSL/WSL2 Linux 运行环境） |
| Linux | **未验证**（沿 0088–0097 结论：可用 WSL 工具链不能完成 Jai 链接；不得把 Windows 结果当跨平台结论） |
| 测试夹具根 | `target/dep-resolution/`（每个用例唯一子目录）、`target/`（其余 scratch）、仓库外临时根 `%TEMP%` |
| XDG 隔离 | 每个 CLI 用例在进程内改写 `XDG_CACHE_HOME`/`XDG_STATE_HOME` 并在 `defer` 中恢复 |

## 2. 覆盖映射 A01–A16

“状态”只区分本记录实际核对过的两类：**已覆盖**（有真实 CLI 或已确认函数级证据并本次跑过）与
**部分覆盖 / 未验证**（列出缺口）。测试名都是 `test <pattern>` 可以直接选中的命名用例；
`test "..." { }` 内联块由收集器重命名为 `juice_test_N`，不可过滤，只能靠完整套件执行（下表按需注明）。

| 组 | 外部可见断言 | 证据（本次执行） | 状态 |
| --- | --- | --- | --- |
| A01 声明与旧字段 | 唯一 `PACKAGE` 入口、纯工作区判定、省略/空/非空三态、旧字段拒绝、`workspace` 保留 | `declaration_schema_`（11/0）：显式空关闭自动发现、`dir` 运行期字段拒绝、`plugins = []` 关闭 test-block、依赖/插件默认值局部伪造拒绝、省略产物双发现、模块+多程序、纯工作区无根包、包+工作区共存、计算式 workspace 保留显式默认；`declaration_loader_`（3/0）；`declaration_paths_tests.jai` 的名称语法与 XDG 用例；`acceptance_a13_unselected_invalid_member_blocks` 用旧字段 `type = .BIN` 在真实 CLI 上复现 `'type' is not a member of Package.`（exit 1） | 已覆盖 |
| A02 工作区与 Git 同名 | 同名成员不覆盖 Git；来源是声明事实 | `dependency_resolution_workspace_source_membership`（同名的仓库外包不能替代 WORKSPACE 来源）；**新增** `acceptance_a02_member_does_not_override_git_source`（同名成员与 Git 提供方并存：Git 门 100、WORKSPACE 门 999） | 已覆盖 |
| A03 来源资格与去重 | path/workspace 各自合法后同一模块重复失败、不同导出/来源可用 | `dependency_resolution_path_source_alias`；`dependency_resolution_module_selection_rules`；`dependency_resolution_module_identity_and_name_conflicts`（同一实际模块重复、alias 覆盖本包模块/标准模块）；**新增** `acceptance_a03_same_name_sources_coexist`（两个仓库同名包 `dupe` 并存）、`acceptance_a03_same_name_revisions_coexist`（同仓库两个修订并存） | 已覆盖 |
| A04 传递可见性 | 提供方自声明依赖、同包模块可用、传递模块不可直接导入、环完整链路 | `dependency_resolution_transitive_visibility`（`Netlib -> Cipher` 不泄漏）；`dependency_resolution_package_cycle_reports_chain`（完整链路 `app -> alpha -> beta -> alpha`）；`dependency_resolution_own_module_public_import`、`_workspace_members`、`_in_test_source`（story 37） | 已覆盖 |
| A05 普通引用与插件 | 不自动导入或启用；同插件模块双重选择失败；独立 API 合法 | `plugin_derived_duplicate_enablement_cli`；`plugin_derived_ordinary_dependency_roles_cli`；E09 两个负例（插件模块兼作普通依赖、同模块二次启用） | 已覆盖 |
| A06 插件默认与配置 | 省略/空/显式不同、缺项不补默认、坏 options 在 hook 前失败 | `plugin_derived_options_errors_cli`（未知键/必填缺失/重复键，均 exit 1 且无派生输出）；`plugin_derived_builtin_triad_cli`、`_resolver`、`_test_cli`；`plugin_host_tests.jai` 内联 E2E “member plugin options rejection fails the build through the host”（`OK=0`、无产物） | 已覆盖 |
| A07 多程序与批量插件 | 包级准备一次、各包隔离、run 只编译目标、依赖插件不自动执行 | `plugin_derived_prepare_once`（同包第二次准备返回同一上下文、`prepare_count == 1`，另一包得到独立私有派生区）；`plugin_derived_unselected_member_isolation_cli`；`run_selection_only_selected_program_cli`；`command_selection_test_batch_cli` | 已覆盖 |
| A08 派生输出 | 只读取本次注册内容、逻辑路径稳定、输出冲突失败、源码只读 | `plugin_derived_view_rules`（substitute/drop/generated 的冲突矩阵、保留源码不可被覆盖、“本轮注册表即视图”使上一轮磁盘文件不可见、无私有派生区即插件错误）；`plugin_derived_legacy_stage`；`plugin_host_tests.jai` 内联 E2E（真实 CLI：替换后的入口被编译、drop 的失败测试不进入测试程序、`original = "src/main.jai"` 逻辑路径保留、host 记录 `SUBSTITUTE=`/`DROP=`/`OK=1`）；`plugin_derived_git_source_read_only_cli`（hook 后 `git status --porcelain` 为空） | 已覆盖 |
| A09 离线解析 | 有记录复用、完整提交无记录例外、浮动/短修订/缺内容拒绝 | `dependency_resolution_offline_matrix`（浮动无记录拒绝、短修订拒绝、完整 commit 且内容已在缓存可建立选择、记录+完整内容离线复用、完整 commit 但内容缺失拒绝）；`dependency_resolution_git_content_restore`（离线缺内容失败） | 已覆盖 |
| A10 更新与失败 | 全图刷新、上下文隔离、失败保旧、成员不回滚、离线更新冲突 | `dependency_resolution_git_reuse_and_update`（`update` 刷新、`update --offline` 被拒）；`dependency_resolution_context_isolation`（两工程、两成员各自选择，互不跟随）；`dependency_resolution_failure_preserves_old_state`（解析失败保旧记录、编译失败不回滚已选定修订）；`command_selection_update_scope_cli`（`update` 只刷新不编译、离线冲突在 discovery 前失败） | 已覆盖 |
| A11 内容与状态 | 清缓存不清选择、损坏报错、移根新上下文、cwd 不改上下文、XDG 回退 | `dependency_resolution_git_content_restore`（删内容缓存后记录仍在、离线失败、在线只恢复记录提交）；`dependency_resolution_corrupt_state_fails`（状态损坏 exit 1 且报 corrupt）；**新增** `acceptance_a11_moved_root_is_new_context`（新根重新解析到分支新 tip，原根保持旧提交，包内子目录调用不改上下文）、`acceptance_a11_xdg_relative_falls_back`（相对 XDG 两条 WARNING + 平台默认回退 + 不产生 cwd 相对目录） | 已覆盖 |
| A12 提供方内部来源 | Git 内工作区不借消费者、非成员内部 path 可用、检出越界失败 | `dependency_resolution_git_checkout_boundary`（检出内兄弟包可用、`../../outside` 报 `escapes its Git checkout`、共享检出 `git status` 为空且检出内无 `target/`）；**新增** `acceptance_a12_git_provider_workspace_boundary`（提供方在检出内的工作区解析到 5×2=10，而非消费者同名成员的 500×2；指向消费者成员目录的 WORKSPACE 选择失败） | 已覆盖 |
| A13 成员校验与扫描 | 未选声明错误阻止操作、无关远程图不获取、下级包测试不混入 | `workspace_products_child_scan_boundary_cli`（未登记子包的 `package.jai` 不被求值、其测试不运行）；`workspace_tests.jai` 内联 discovery E2E（非法成员清单/越界成员/缺失目录/无清单）；**新增** `acceptance_a13_unselected_invalid_member_blocks`（`build`/`run`/`test -p good` 都 exit 1，且无 `good` 产物）；无关远程图不获取见 `command_selection_update_scope_cli` | 已覆盖 |
| A14 命令选择与零集合 | 默认/显式集合、歧义/零包失败、零程序与零测试区别、参数透传 | `command_selection_`（7/0：纯工作区默认、flag 矩阵、拒绝矩阵、`run` 基数、测试批量、首个失败停止并报告未执行、update 范围）；`run_selection_`（12/0：程序选择矩阵、`--` 原样透传、启动失败传播、不安全/缺失产物、只编译被选程序） | 已覆盖 |
| A15 跨文件系统路径 | 名称 ASCII 判重、物理大小写身份、链接拒绝、跨类别规则不同 | `declaration_paths_tests.jai`（包名/标识符语法、ASCII 大小写比较不折叠 Unicode、链接祖先拒绝、XDG 绝对路径规则）；`test_command_tests.jai` 的链接目录/junction/文件链接扫描夹具；**新增** `acceptance_a15_entry_through_link_is_rejected`（经 junction 进入的 `entry` → `Product entry is not a regular link-free file: via_link/main.jai`，无产物）、`acceptance_a15_case_identity_and_cross_category_names`（`entry = "SRC/main.jai"` 在 Windows 上同一物理文件可构建；同包 module 与 executable 同名 `tool` 合法并各自可用） | 已覆盖（除下方大小写敏感项） |
| A16 完整安装 | 同版本配套在仓库外使用、缺模块/错配明确失败、无其他安装回退 | `publication_install`（15/0：marker 文本与解析矩阵、完整单元校验、缺 marker/epoch/ABI/缺件/改件/集合不符、真实 CLI 无旁路源码、仓库外项目 build/run/test/update/offline）；`bootstrap_publication_unit_marker`（自举产物与生成的 marker 逐字节一致、替换 `Testing.jai` 后该产物失败）；**本次另跑** §4 路径 3（仓库外安装单元 + 无回退负例） | 已覆盖 |

### 2.1 仍未覆盖或不可验证

| 项 | 原因 | 处理 |
| --- | --- | --- |
| A15 大小写敏感文件系统契约（`src/` 与 `SRC/` 是不同物理文件时按实际身份判定） | 本机无大小写敏感卷，Linux 工具链不可用（0088 起结论） | 明确未验证；`acceptance_a15_case_identity_and_cross_category_names` 在非 Windows 分支写的断言（`SRC/main.jai` 不存在 → 拒绝）从未执行过，记录为未运行代码路径 |
| Linux / POSIX 分支（`setenv`/`unsetenv`、`TMPDIR`、`/tmp` 默认根） | 同上 | 未验证 |
| `install_compatibility_` 过滤前缀 | `tests/install_compatibility_tests.jai` 的 15 个命名用例前缀是 `publication_install_`；`test install_compatibility_` 命中 0 个用例（`target/evidence/filter-install_compatibility_.log` 打印 `No tests matched`） | 不用 0 命中过滤充数：A16 的真实证据是 `publication_install` 15/0 + §4 路径 3 |
| 报告里“批量首个失败即停”的失败分支 | 由 `command_selection_first_failure_cli` 覆盖（0093），不在迁移示例里 | 已由 0093 实现测试覆盖，本次随 `command_selection_` 过滤重跑通过 |
| `juice test` 的包内文件双包含 | 见 §6 限制 1（既有行为，非本次引入） | 记为已知限制 |

## 3. 迁移示例 E01–E10（本次重放）

重放脚本：`target/evidence/reproduce-examples.sh`（0095 交付，本次原样复用），安装在
`target/evidence/install-home/`（`juice.exe` + 相邻 `modules/`，来自本次分支 tip 的 debug 构建），
scratch 根 `C:/Users/maojiaxing/DevTools/msys/tmp/juice-096-examples`，独立 XDG。逐次调用的 cwd、参数与
退出码在 `target/evidence/migration-examples-index.txt`。

| 示例 | 命令 | 退出码 |
| --- | --- | --- |
| E01 最小程序 | `build` / `run` | 0 / 0 |
| E02 只有模块 | `build`（零程序）/ `run` | 0 / 1 |
| E03 模块 + 多程序 | `build` / `run`（default_run）/ `run adder` / `run nosuch` | 0 / 0 / 0 / 1 |
| E04 纯工作区 | `build` / `build --workspace` / `run --workspace` | 0 / 0 / 1 |
| E05 根包 + 工作区 | `build` / `build --workspace` / 成员内 `build` | 0 / 0 / 0 |
| E05b 无 `default_members` 的根默认 | `build` / `-p rootapp` / `--package-path libs/api` / `-p nosuch` | 0 / 0 / 0 / 1 |
| E06 本地依赖 | `run` / 环探针 `build` | 0 / 1 |
| E07 Git 上下文 | 首次 `run` / 复用 `run` / `run` / `update` / `run --offline` | 0 / 0 / 0 / 0 / 0 |
| E08 lint | `test` | 0 |
| E09 jaix + 普通 API | `build` / `run` / 插件当依赖负例 / 重复启用负例 | 0 / 0 / 1 / 1 |
| E10 零产物 | `build` / `run` / `test` | 0 / 1 / 0 |

合计 33 次调用：25 次 exit 0，8 次 exit 1（全部是上表列的预期失败）。与 0095 记录的矩阵一致。

## 4. 三条发布路径

| 路径 | 命令（cwd） | 结果 | 日志 |
| --- | --- | --- | --- |
| 1. debug 源码自举 | `jai.exe build.jai`（工作树根） | exit 0，`target/juice.exe` | `target/evidence/build-debug-final.log` |
| 2. release 源码自举 | `jai.exe build.jai - release`（工作树根） | exit 0，`target/juice.exe`（1654784 B） | `target/evidence/build-release.log` |
| 3. 相邻 `modules` 发布安装，仓库外使用 | `sh target/evidence/reproduce-published-install.sh` | 见下表 | `target/evidence/published-install.log` |

路径 3 的安装单元 = release `juice.exe` + `target/modules/` 复制到仓库外临时根
`/tmp/juice-acceptance-published-install`（脚本断言该根不在仓库内），项目同时使用 PATH 兄弟包、
本地 Git 提供方、WORKSPACE 成员、显式内置插件对，独立 XDG：

| 步骤 | 命令 | 退出码 | 观察 |
| --- | --- | --- | --- |
| 版本 | `juice version` | 0 | `juice 0.1.0` / `jai 0.2.9`，无安装噪声 |
| 构建 | `juice build` | 0 | 编译 `app` |
| 运行 | `juice run` | 0 | `path=21 git=34 member=55` |
| 测试 | `juice test` | 0 | `[test] installed_unit_bound` / `1 passed, 0 failed` |
| 更新 | `juice update` | 0 | `Dependency resolution graph updated.` |
| 离线 | `juice build --offline` | 0 | 复用已记录提交 |
| 缺件负例 | 删除相邻 `modules/Testing.jai` 后 `juice build` | 1 | `not one compatible installation` + `the installed artifact Testing.jai is missing` |
| 修复后 | 复原 `Testing.jai` 后 `juice build` | 0 | 恢复构建 |
| 无回退负例 | 删除相邻 `juice_core.jai`、另放一份完整 `modules/` 在别处，`juice version` | 1 | `the installed artifact juice_core.jai is missing`（不向其他安装目录回退） |
| 修复后 | 复原 `juice_core.jai` 后 `juice version` | 0 | 恢复 |

## 5. 本次新增的覆盖（`tests/package_declaration_acceptance_tests.jai`）

9 个命名用例，全部是真实 CLI + 真实本地 Git + 独立 XDG。红线证据分两类，明确区分：

| 用例 | 覆盖 | 红证据与方式 |
| --- | --- | --- |
| `acceptance_a02_member_does_not_override_git_source` | A02 | 判别式夹具：把 Git 门换成成员门（模拟“同名成员覆盖来源”），断言 `git=100` 失败（`acceptance-red-discriminating.log`） |
| `acceptance_a03_same_name_sources_coexist` | A03 | 判别式夹具：把第二个来源 URL 改成第一个（模拟按名字合并身份），`From_Second` 解析失败 → 构建 exit 1 |
| `acceptance_a03_same_name_revisions_coexist` | A03 | 判别式夹具：把旧修订内容改成与新修订同符号（模拟修订不进身份），`Old_Value` 未声明 → 构建 exit 1 |
| `acceptance_a11_moved_root_is_new_context` | A11 | 产品变异：解析上下文塌成全局单例（`resolution_state_directory` 固定 key + `resolution_declaring_key_local` 固定值）后，搬迁根编译出 `value=100`（`acceptance-red-a11-2.log`） |
| `acceptance_a11_xdg_relative_falls_back` | A11 | 断言依赖真实子进程输出的两条 WARNING 与回退目录；回退实现由 `declaration_paths_tests.jai` 函数级用例独立保证 |
| `acceptance_a12_git_provider_workspace_boundary` | A12 | 产品变异：WORKSPACE 成员解析改用消费者根（`resolution_membership_for(..., graph.consumer_root)`）后失败（`acceptance-red-1.log`） |
| `acceptance_a13_unselected_invalid_member_blocks` | A13 | 产品变异：discovery 对无效成员从失败改为跳过（`continue`）后，`build -p good` 变成成功、产物出现（`acceptance-red-1.log`） |
| `acceptance_a15_entry_through_link_is_rejected` | A15 | 产品变异：去掉 `make_effective_target` 的 `path_chain_is_link_free` 检查后成功构建（`acceptance-red-1.log`） |
| `acceptance_a15_case_identity_and_cross_category_names` | A15 | 断言两条规则同时成立：跨类别同名可构建、Windows 大小写别名指向同一物理文件 |

产品变异批次（`target/evidence/acceptance-red-1.log`）= 4 处真实产品改动，跑完立即 `git checkout -- src/`
还原并重新构建；`acceptance-green-1.log`/`-2.log` 是还原后的绿灯（9/0）。
“判别式夹具”指把夹具改成旧语义的输入、让新断言必须失败：它证明断言确实在读真实子进程结果并区分两种来源/修订，
但不等同于产品变异，按此区分记录，不混用。

## 6. 已知限制（本次观察到、非本次引入）

1. **`juice test` 与包根公开模块的双包含。** `test` 的测试程序 `#load` 包内每个不在根级
   `target/`、`modules/`、`tests/data/` 之下的 `.jai` 文件；若包自己的公开模块入口也在这些位置之外，
   同一文件会被 `#load` 一次又被 own-module shim `#import` 一次，报 `Redeclaration of '<symbol>'`。
   路径 3 的夹具因此把公开模块放在包内 `modules/` 下。`build`/`run` 不受影响。这是 0097 记录的既有行为
   （`docs/migrations/package-declarations.md` §4.3、已知限制 3），不属于 0096 的修复范围。
2. **`workspace_` 过滤现在命中 14 个用例**，其中 1 个是本次新增的
   `acceptance_a12_git_provider_workspace_boundary`（名字里含 `workspace_`）。0097 记录的是 13，差异来自
   子串匹配，不是既有用例变化。
3. **首次构建的目录探测噪声**：`Unable to open directory '<pkg>/target'`（目标目录尚未创建）不影响退出码。
4. **MAX_PATH**：绝对路径未加 `\\?\` 前缀，很深的夹具树仍可能失败（0091 起记录）。

## 7. 重放命令

```sh
# 1. 构建与套件（工作树根）
C:/Users/maojiaxing/DevTools/jai/bin/jai.exe build.jai                      # exit 0
C:/Users/maojiaxing/DevTools/jai/bin/jai.exe build.jai - release            # exit 0
cp target/juice.exe target/juice-full.exe                                   # Windows 不能替换运行中的映像
./target/accept.exe test acceptance_                                        # 9 passed, 0 failed
./target/accept.exe test dependency_resolution_                             # 17 passed, 0 failed
./target/accept.exe test workspace_                                         # 14 passed, 0 failed
./target/accept.exe test command_selection_                                 # 7 passed, 0 failed
./target/accept.exe test plugin_derived_                                    # 16 passed, 0 failed
./target/accept.exe test declaration_schema_                                # 11 passed, 0 failed
./target/accept.exe test run_selection_                                     # 12 passed, 0 failed
./target/accept.exe test publication_install                                # 15 passed, 0 failed
(nohup sh -c './target/juice-full.exe test; echo "EXIT: $?"' > target/evidence/full-1.log 2>&1 &)

# 2. E01–E10 重放（需要先复制一个安装单元）
sh target/evidence/reproduce-published-install.sh   # 路径 3
JUICE_HOME=$PWD/target/evidence/install-home JUICE_SOURCE=$PWD \
  SCRATCH_ROOT=C:/Users/maojiaxing/DevTools/msys/tmp/juice-096-examples \
  bash target/evidence/reproduce-examples.sh        # E01–E10
```

完整套件结果（两轮连续 `N passed, 0 failed` + `EXIT: 0`）见 `target/evidence/full-1.log`、
`full-2.log`；合入最新 integration tip 后的复跑见 `full-final.log`。套件打印的聚合数不是总用例数
（`tests/module_tests.jai` 调用 `finish()` 重置自己的计数），判定以最终摘要与退出码为准，新用例按名字在日志里
`grep -c "^\[test\] acceptance_"` 确认为 9。

## 8. 本次门禁结果（原文数值）

| 命令（cwd = 工作树根） | 退出码 | 计数 / 观察 |
| --- | --- | --- |
| `jai.exe build.jai` | 0 | debug 自举，`target/juice.exe` |
| `jai.exe build.jai - release` | 0 | release 自举，1654784 B |
| `./target/accept.exe test acceptance_` | 0 | 9 passed / 0 failed |
| `test dependency_resolution_` | 0 | 17 / 0 |
| `test workspace_` | 0 | 14 / 0 |
| `test command_selection_` | 0 | 7 / 0 |
| `test plugin_derived_` | 0 | 16 / 0 |
| `test declaration_schema_` | 0 | 11 / 0 |
| `test run_selection_` | 0 | 12 / 0 |
| `test publication_install` | 0 | 15 / 0 |
| `test install_compatibility_` | 0 | 0 命中（`No tests matched`，真实前缀是 `publication_install`） |
| `./target/juice-full.exe test`（第 1 轮） | 0 | 380 passed / 0 failed，`EXIT: 0` |
| `./target/juice-full.exe test`（第 2 轮） | 0 | 380 passed / 0 failed，`EXIT: 0` |
| 合入 integration tip | — | `already up to date`；`merge-base --is-ancestor` 为真 |
| 合入后 8 个过滤 | 0 | 与上表一致（`postmerge-*.log`） |
| `./target/juice-full.exe test`（合入后） | 0 | 380 passed / 0 failed，`EXIT: 0`（`full-final.log`） |
| `sh target/evidence/reproduce-published-install.sh` | 0 | 见 §4（版本/构建/运行/测试/更新/离线全 0，两个负例 1） |
| `bash target/evidence/reproduce-examples.sh` | 0 | 33 次调用：25 × exit 0，8 × exit 1（预期失败） |

每份完整套件日志中 `[test] acceptance_` 行数为 9，`expect failed` 行数为 6（`module_tests.jai` 与
已发布 Testing 模块自身的故意失败夹具，与 0097 基线同类型同数量）；`[test]` 行数 669。
