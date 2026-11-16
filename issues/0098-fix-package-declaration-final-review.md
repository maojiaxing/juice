---
title: 修复：0087 最终双轴审查与跨平台验收缺口
status: closed
labels: [ready-for-agent]
assignee: maojiaxing
parent: "0087"
blocked-by: []
---

## Goal and contract

完成 [0087](0087-spec-package-declaration-semantics.md) 既定契约，修复最终 Standards / Spec 审查发现，而不是新增产品政策。0096 尚未关闭；此前实施票 Resolution 只记录当时的门禁，不能豁免本票确认的规格违反。

全部修复由同一个实施分支/实施代理承担；各行为先写真实 CLI 回归并验证红灯，再修复。静态推断须进一步验证，不能把尚未执行的情形记成通过或失败。不得删断言、减少覆盖、隐藏编译错误、以强制模块目录布局绕过问题，或修改权威规格使实现显得合规。

固定审查范围：`8d689b3e5bf75fc43bb10016e467a4fb5b309e15...e1743fb785abf1f5719627cd8a857d1dec9ded23`。报告、可重放脚本、JSON 与原始日志位于：

`C:/Users/maojiaxing/DevTools/msys/tmp/juice-package-implementation/final-review/`

- `standards-review.md`：有文档依据的规则问题与 Fowler 判断项分开；剩余文件审查补充进行中，不宣称已穷尽。
- `spec-review.md`：S01–S18 静态轨迹和五项待验证事项；二次返回未写回的最新证据由下一项补充。
- `orchestrator-triage.md`：主审实测、S16 原决策裁定及修复约束。
- `independent-no-git-probes.py`、`independent-no-git/results.json`：13 次独立 Windows CLI，4 个对照、9 个规格期望不匹配。
- `module-path-probes.py`、`module-path-probes/results.json`：S01/S16 三次真实失败。
- `plugin-probes/`：插件宿主正控、S09/S10 实测，后续证据按实际结果追加。
- `../linux-acceptance-attempt.md` 与 `../linux-env-probes/`：真实 Linux debug/release、路径/安装检查及两个失败接缝。

## Confirmed observable failures

| 编号 | 必须修复的可观察行为 | 当前实测 |
|---|---|---|
| S01 | 合法包内公开模块可供测试导入，且模块自身测试不丢失、不重复实例化 | `src/api.jai` 同时被 driver 直接 load 和模块 import，Windows/Linux、ASCII/Unicode 均 exit 1；中途“1 passed”不是成功 |
| S02 | 成员子目录定位当前包后仍发现所属工作区；校验全部成员；CWD 不改变上下文 | 根可选择兄弟，成员子目录同参数失败；无效未选兄弟从成员调用被忽略 |
| S03 | 导入名/依赖可见性只属于各消费包；批量选择不合并命名空间 | 未声明 Secret 的成员单选失败、批量却成功；不同成员合法同名 Data alias 被误判冲突 |
| S09 | test 的 CWD、插件配置、诊断归属属于所选成员 | 成员测试读取了根目录 ROOT；成员 lint 未执行，同一 lint 的根包正控已触发预期 ERROR |
| S10 | generated/substitute/drop 覆盖完整逻辑源码图，不只程序根入口 | generated helper 找不到；只替换 helper 仍输出旧值；替换 main 后相对 load 错指物理派生目录 |
| S11 | 相同替换也必须判重；物理输出规范化后只能位于派生区 | 第二次相同 substitute 仍 true；`derived_root/../outside.jai` 注册仍 true；两次包操作均错误成功 |
| S12 | 插件宿主导入必须独立于业务导入，插件启用不开放普通导入 | 普通 Tool 返回7，启用同ID插件后错误改为99；无依赖仅启用插件仍可普通 import |
| S13 | 所有已选插件先校验真实模块入口、ABI/options；校验不依赖存在hook | 无hook错误ABI/未知options均build0；有效#load唯一入口build1；普通导入正控证明三个模块均有效，带hook负控会正确报错 |
| S14 | 全部名称类别校验与 ASCII 大小写比较贯通 | `run Tool` 成功、`run tool` 失败；依赖引用名 `bad name` 被接受 |
| S15 | typed XDG 根失败立即可观察；所有缓存消费者使用验证后根 | XDG_CACHE_HOME 指向普通文件，无 Git build 仍成功 |
| S16 | 普通本地 PATH 不额外限于消费根父目录；WORKSPACE 合法根唯一模块支持统一简写 | `../../libraries/math` 及成员引用工作区根唯一 RootApi 均被拒；0081/0082/0087 合同已由主审完整核对 |
| S17 | default_members、exclude 根包规则在声明阶段校验，不能由显式选包绕过 | missing 默认成员配 `-p` 仍成功；exclude=[.] 静默忽略 |
| L01 | 仓库外安装测试在 Unix 保留所复制程序的执行权限 | `publication_install` 9/6 exit 1，六项均先 Permission denied；Jai Unix copy_file 将0755复制为0644，不是六个安装 verifier 缺陷 |

S16 的裁定不是仅凭失败反推：0081 第八轮和 Resolution §10 明确举 `apps/cli -> ../../packages/codec`；§1–§3 对三种显式来源共用根唯一模块简写；0082 明确根包自动是成员。保持 Git 检出边界、链接拒绝和成员资格，不能反向放宽纯工作区猜成员。

## Static findings requiring regression confirmation and disposition

每项须提供红/绿或具体反证，不得遗漏后把整张审查称已修复。

- S04：发起消费包维度遗漏导致两个成员共享提供方的传递 Git 选择；更新一个成员可能改变另一个普通构建。
- S05：Git 提供方经过内部 PATH/WORKSPACE 边后丢失仓库/提交 provenance，多跳合法链可能失败或改变身份。
- S06：Git 插件来源另走轻量解析、不持久化选择、不准备插件自身依赖图；update 未纳入插件来源。
- S07：解析状态早于适用插件校验提交；批量包未执行前已解析/提交；run 基数校验晚于获取。
- S08：提供方内部依赖未执行与最外层消费者一致的模块身份、最终名称及标准/自有模块冲突检查。
- S11 剩余项：输出范围放大到整个 target、清理失败只告警仍需针对性回归；相同替换判重与物理点段越界已真实确认。验证注册契约，不建立任意插件代码沙箱。
- S12 已由宿主正控及业务值7→99的真实 CLI 确认，按上表修复并回归。
- S13 已由 `plugin-probes/16`–`24` 的有效模块/有效插件/带hook负控与无hook失败探针确认，按上表修复。
- S18：产品规格旧默认补插件/优先级/未来工作区描述冲突；E04–E07 缺完整可独立重放输入；A 组“全覆盖”声明超出真实用例。
- 五项待核实：Windows物理路径身份、默认分支变更/缺缓存文件完整性、安装兼容纪元与构建身份区别、提供方反向偷用消费者依赖、既有非PRESTEP生命周期贡献。相同兼容契约的完整安装来自不同构建不自动构成缺陷；没有反证不得扩大需求。

## Standards disposition

首轮 H1–H4：13 处冗余结构体类型、38 处缩写声明、3 个单调用点单行辅助函数、5 行新增 emoji；见报告全部位置及规则引用。修复时保留 Unicode/补充平面字符测试覆盖。

J1/J2/J3 为维护性判断而非硬错误：普通依赖与插件重复来源解析、generated 两入口重复校验、字符串排序/摘要重复、重复 target_root 赋值、无额外行为的转发包装。与上述功能修复重合者共用实现；其余消除具体重复，不新增通用框架。对不适用项给出明确技术反证。Standards补充审查结果到达后并入同一分支，禁止另开互相竞争的修复者。

## Ownership and implementation ordering

1. `workspace.jai`/`commands/selection.jai` 分离声明发现+归属+选择/基数预检与逐包执行，保留最近无效声明权威性、排除/内层工作区规则。
2. `dependency_resolution.jai`/`resolution_state.jai` 以发起消费包为状态与导入归属；来源 variant 与实际 Git provenance 分开；普通/插件共用 typed 来源解析，图构建不直接提交。
3. `plugin_scan.jai`/`plugin_host.jai` 校验真实选定模块和全部配置后才允许提交及hooks；插件宿主目录不进入普通程序导入面。
4. `commands/build.jai`/`commands/test.jai`/`test_runner.jai`/`test_discovery.jai`/`transpile*.jai`/`lifecycle.jai` 统一消费逻辑视图，保证模块唯一实例、模块内测试、相对load、诊断与包归属。
5. `manifest.jai`/`main.jai`/`xdg.jai` 完整名称与typed根检查；安装测试复制接缝处理可执行权限。
6. 文档、验收、Standards清理及持久证据同步；不更改另一Testing effort组织或放松已关闭语义决定。

具体实现可调整内部类型，但不得引入无约束Any/void、全局mutable当前工程或让调用方手工协调多个重复解析器。读取完整文件后再编辑；结构体类型可推断处优先`.{} `。

## Validation and integration

- 既有用户批准的真实CLI/现有模块/自举/相邻模块安装测试接缝继续有效，不再次请求审批。
- 单独 sibling worktree + 分支，从当前集成tip开始，确认基线；只写自己的工作区或指定外部scratch。
- 行为逐项红绿，保留负例：无隐式可见性、无来源替代、坏配置无hook、副作用与状态提交时机、不丢模块测试。
- **平台范围（用户决定）：本轮验收以 Windows 为准。** 实际debug/release自举、配套安装、修复后的`publication_install`与S01均须在Windows真实退出0。超时、0命中过滤与打印中间汇总不能算通过。
- Linux 改为**显式未验证**，不再作为本轮关闭门禁：已获 Linux 证据（此前debug/release自举0、S01失败、`publication_install`复制权限缺陷）保留为历史记录；L01修复代码保留，但不得在任何文档/Resolution中声称 Linux 已通过。文档须逐项列出“Windows已验证 / Linux未验证”，不得用Windows结果推断POSIX行为。
- 完整套件需真实终止和连续两轮最终0失败，确认新增测试按名称执行。合入最新integration后再验证；merger核对diff、独立复核后关闭本票与0096。
- 挂起Windows测试及关联Git进程的终止/maintenance对照仍等待用户许可；本票不授权停用防护、改全局Git或擅自终止这些进程。不得用主检出的挂起测试目录运行并发构建。
- 产出每个S/H/J/L编号的修复、反证或未解决映射；未解决的强制合同阻止0087关闭。
- **本轮门禁实测（2026-11-15，分支 `implement/final-review-fixes`，HEAD `610e761` 合入 integration `3de8bd9` 后）**

| 门禁项 | Windows | Linux |
| --- | --- | --- |
| debug 自举 `jai.exe build.jai` | 已验证 exit 0（`GATE-build-debug.log`） | 未验证（本轮范围外） |
| release 自举 `jai.exe build.jai - release` | 已验证 exit 0，`target/juice.exe` 1056256 B（`GATE-build-release.log`） | 未验证（本轮范围外） |
| `publication_install` 过滤 | 已验证 15/0 exit 0（`GATE-publication_install.log`） | 未验证（本轮范围外） |
| S01 单实例（ASCII + Unicode 夹具） | 已验证 1/0 exit 0，两个子进程均 exit 0（`GATE-final_review_module_owned_tests_run_once.log`） | 未验证（本轮范围外） |
| 完整套件第 1 轮 | 已验证 380 passed / 0 failed，exit 0（`GATE-round1.log`） | 未验证 |
| 完整套件第 2 轮 | 已验证 380 passed / 0 failed，exit 0（`GATE-round2.log`） | 未验证 |
| 合入 integration 后完整套件 | 已验证 380 passed / 0 failed，exit 0（`GATE-postmerge.log`） | 未验证 |
| H1 后完整套件 | 已验证 380 passed / 0 failed，exit 0（`GATE-h1.log`） | 未验证 |
| H2/J1/J2a–g/J3 全部完成后 debug 自举 | 已验证 exit 0（`GATE3-debug.log`） | 未验证（本轮范围外） |
| H2/J1/J2a–g/J3 全部完成后 release 自举 | 已验证 exit 0，`target/juice.exe` 1051136 B（`GATE3-release.log`） | 未验证（本轮范围外） |
| `publication_install` 过滤（终轮） | 已验证 15/0 exit 0（`GATE3-publication_install.log`） | 未验证（本轮范围外） |
| S01 单实例（ASCII + Unicode）按名称 | 已验证 1/0 exit 0，两个子进程均 exit 0（`GATE3-s01.log`） | 未验证（本轮范围外） |
| `final_review_` 按名称 | 已验证 32/0 exit 0（`GATE3-final_review.log`） | 未验证（本轮范围外） |
| 完整套件（终轮第 1 轮） | 已验证 380 passed / 0 failed，exit 0（`GATE3-round1.log`） | 未验证 |
| 完整套件（终轮第 2 轮） | 已验证 380 passed / 0 failed，exit 0（`GATE3-round2.log`） | 未验证 |
| L01 `ic_create_install` 模式复刻 | Windows 分支立即返回 true，POSIX 分支未被触及 → Windows 不构成该分支的证据 | **未验证**：POSIX 分支（`POSIX.stat`/`chmod`）在任何平台都未执行过 |

Linux 历史记录（仅对 `e1743fb` 及其修复前状态有效，不得读作当前通过）：debug/release 自举 exit 0；S01 红；
安装复制把 0755 降为 0644。


**计数口径说明（不得改写）**：完整套件的 `380` 不含 S16b 新增的两个测试。把这两个测试的 `@test`
标记去掉后套件同样报 380（`CNT-withNew.log` / `CNT-noNew.log` 双向实测），因为汇总把内联
`test "…"` 块计为 `juice_test_N`。它们的证据是按名称运行的结果，以及 `final_review_` 由 30/0
增长到 32/0，而不是这 380。

**Standards 终轮处置**：H2 的 100 处声明（首轮 38 + 补充 62）已全部改为完整词，全程未使用保留字
`context`；J1 抽出共享的来源定位与 Git 选择步骤，保留两侧各自的能力校验、错误文案与离线策略差异，
WORKSPACE 分支给出不合并的具体技术反证（祖先工作区发现 vs 消费方 discovery 根）；J2a–g 逐项
或抽取或给出反证；J3 两处转发包装已内联。逐项记录见
`target/evidence/final-review-fixes/ledger.md`。

## Resolution

关闭本票：0087 最终双轴审查确认的全部缺口已修复，并经合并后独立验证。**平台边界：本轮只在 Windows 验收；Linux 显式未验证。**

### 合并与提交范围

- 实现分支 `implement/final-review-fixes`（起点 `92ff745`，即集成 tip），最终 HEAD `2c27e3f`。
- 经 `3f848e3`（`--no-ff`，父 `3de8bd9` + `2c27e3f`）合入 `integration/package-declaration-semantics`，无冲突。
- 主要提交：`382e9b2`（S02/S17）、`b317ba1`（S07 预检）、`4230cd5`（S03/S04/S05/S08/S16）、`a766170`（S13）、`d6e765b`（S12）、`91f5400`（S09）、`b38f3e2`（S06/S07 事务）、`ff4293c`（S14）、`9377698`（S15）、`b5fef04`（S11）、`02232b0`（S10）、`d6f0a1b`（S01）、`d52fcee`（S18）、`2634f5a`（断言迁移 + 静默丢弃修复）、`0355fe0`（S16b）、`48b606e`（H1）、`8aba06c`（H3/H4）、`b2d377f`（H2）、`ea4e033`/`d46d006`（J2/J1）、`2c27e3f`（门禁记录）。

### 逐项处置

| ID | 处置 | 说明 |
|---|---|---|
| S01 | fixed | 每个已声明模块单一实例，模块自有测试保留。仅在另一收集文件确实 `#import` 该模块时才把导入 shim 重指到同一展开视图并停止直接 load，因此无人导入的模块仍编译并运行其测试。无文件排除、无强制 `modules/` 布局、未拆分 Testing register |
| S02 | fixed | 成员子目录定位所属工作区；未选成员的非法声明不再因 cwd 被忽略 |
| S03 | fixed | 每消费包私有导入区 `target/imports`；批量选择不再合并命名空间 |
| S04 | fixed | 解析状态以发起消费包为 key，共享提供方的传递 Git 选择不再互相影响 |
| S05 | fixed | Git 内部 PATH 边保留仓库/提交 provenance 与检出边界 |
| S06 | fixed | 插件 Git 来源走同一 typed 解析/状态；插件提供方自身依赖图在同一事务内解析；update 刷新且不跑 hooks |
| S07 | fixed | 声明/选择/命令基数预检先于任何获取；插件角色/ABI/options 校验先于状态发布 |
| S08 | fixed | provider 作用域强制与消费者一致的模块身份/名称冲突校验 |
| S09 | fixed | `Test_Compile_Stage.package` 携带被测包，测试 cwd、插件配置、lint 诊断归属成员 |
| S10 | fixed | 单一逻辑输入图覆盖整个 `#load` 闭包；生成/替换/丢弃作用于当前轮；诊断与相对 load 保留逻辑路径 |
| S11 | fixed | 重复替换拒绝；物理注册规范化并限制在真实派生根内；清理/注册/写入失败致命 |
| S12 | fixed | 插件私有导入命名空间（`<id>__plugin_<hash>`，落在 `target/plugins/imports`），不覆盖业务别名，单独启用插件不暴露普通导入 |
| S13 | fixed | 按所选模块 `#load` 闭包计数入口锚点；所有启用插件无条件校验 ABI/options，与是否存在 hook 无关 |
| S14 | fixed | 名称语法校验贯通（依赖引用名等）；公开名 ASCII 大小写不敏感比较，拼写保留 |
| S15 | fixed | typed XDG 根在入口校验并传播失败；评估缓存使用同一已验证根，无旧 `get_cache_home` 回退 |
| S16a | fixed | 撤销无授权的消费根父目录上限；Git 检出边界与链接拒绝保留 |
| S16b | fixed | WORKSPACE 根包唯一导出简写生效；视图目录改为与消费者 shim 所在目录一致，且 `modules/` 不再被排除导致入口漏拷；纯工作区仍要求显式成员 |
| S17 | fixed | `default_members`、根 `exclude` 在声明期校验，显式选包不能掩盖 |
| S18 | fixed | 删除 `docs/spec.md` 旧默认表述；A 表改为真实测试名与计数；E04–E07 补为可独立重放的完整输入 |
| H1 | fixed | 13 处冗余结构体类型字面量改为推断 `.{}`；显式类型数组字面量按审查结论不动 |
| H2 | fixed | 100 处缩写声明改全词；全程未使用 Jai 保留字 `context`（用 `lifecycle_context`/`test_context`/`command_context`） |
| H3 | fixed | 3 处单调用点单行包装内联 |
| H4 | fixed | 5 行新增 emoji 移除；非 BMP 覆盖由 U+10400/U+10428 测试保留 |
| J1 | fixed + 反证 | 抽出 `git_resolve_source`（record→offline→selector→content）与 `source_path_root`。两处**故意不合并**并给出理由：离线判定策略 `REQUIRE_CACHED_CONTENT` vs `TRUST_PINNED_COMMIT`（合并即行为变更）；WORKSPACE 分支为祖先工作区发现 + 前置全量校验，与插件的 `has_workspace` + 单选择事后校验不同。角色/能力校验未动（决策 21） |
| J2a–g | fixed / 逐项反证 | J2a 抽出 `prestep_auxiliary_stage`/`prestep_auxiliary_path_is_free`（保留各自物理输出步骤顺序）；J2b `sort_strings_lexicographically` 共用，`sort_test_names` 拒绝合并（用 `test_name_less` 而非 `compare`）；J2c 摘要去重，`manifest_hash_hex` 拒绝（`manifest.jai` 第 40 个 load 早于 `transpile_cache.jai` 第 54 个，作用域不可见）；J2d 树内本就只有一处 `target_root` 赋值；J2e/J2f fixture 复用共享写入器；J2g 删除被立即覆盖的死赋值与非插值 `tprint` |
| J3 | fixed | `plugin_prepare_once_for` 直接成为实现，删除 `prepare_plugins_once` 转发；`dr_run` 删除，81 处调用改 `run_otter_child_at`；`dr_run_app` 按审查豁免保留（附加子进程输出） |
| L01 | fixed（POSIX 分支未执行） | `ic_create_install` 用 `POSIX.stat`/`chmod` 复刻源文件模式，避免 Unix 上 0755→0644；六项安装断言原样保留。**该分支在任何平台都未执行过**，Windows 走早返回 |

### 五项低置信项

书面裁定见 `docs/implementation/final-review-dispositions.md`：Windows 物理身份（大小写不敏感卷上视为同一文件，大小写敏感分支未执行）；默认分支/缓存完整性（三条规则构成可判定矩阵且均有测试，远端前进不是缺陷）；安装兼容纪元 vs 构建身份（同契约的完整安装来自不同构建不构成缺陷）；提供方反向可见性；非 PRESTEP 生命周期贡献。每项均标注未验证边界。

### 验证

**合并后（`3f848e3`，独立 worktree `juice-verify-0098`，`target/evidence/merger-0098/`）**

| 门禁 | 结果 |
|---|---|
| debug 自举 | exit 0 |
| 完整套件 | 380 passed / 0 failed，exit 0，913 s |
| `final_review_` 按名称 | 32/0，exit 0 |
| `publication_install_` | 15/0，exit 0 |
| S01 按名称（`final_review_module_owned_tests_run_once`） | 2/0，exit 0 |

**实现分支（`2c27e3f`）**：debug 自举 ×2、release 自举（`target/juice.exe` 1051136 B）均 exit 0；完整套件连续两轮各 380/0 exit 0（960 s / 1012 s）。

**独立探针复验（主审，非实现者测试）**：用原始审查脚本对发布安装重放，13 项 no-Git 探针（S02/S03/S14/S15/S17）+ S01 + S16a + S16b **全部符合期望，0 处不匹配**；见 `final-review/independent-reverification.md`。

**计数口径（不得改写）**：完整套件的 380 **不含** S16b 新增两项。去掉其 `@test` 标记后套件同样报 380（`CNT-withNew.log` / `CNT-noNew.log` 双向实测）。它们的证据是按名称运行与 `final_review_` 30/0→32/0，不是这 380。

### 已知限制与未验证项

- **Linux/POSIX 全部未验证**（用户本轮决定）。此前 e1743fb 时代获得的 Linux 证据（debug/release 自举成功、S01 失败、`publication_install` 复制权限缺陷）保留为历史记录，不代表当前状态。不得据 Windows 结果推断 POSIX 行为。
- L01 的 POSIX 分支从未在任何平台执行。
- 大小写敏感文件系统上的入口大小写契约未执行。
- MAX_PATH 与深层路径未额外验证。
- 主检出遗留的挂起 Windows 测试/Git 进程未被处置（无用户许可），未作为本票证据，也未在其上构建。
