---
title: 修复：0087 最终双轴审查与跨平台验收缺口
status: open
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
| S09 | test 的 CWD、插件配置、诊断归属属于所选成员 | 成员测试读取了根目录 ROOT；成员 lint 未执行（另需有效 lint 正控核实） |
| S10 | generated/substitute/drop 覆盖完整逻辑源码图，不只程序根入口 | generated helper 找不到；只替换 helper 仍输出旧值；替换 main 后相对 load 错指物理派生目录 |
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
- S11：派生路径仅字符串前缀检查、允许相同替换重复注册、输出范围放大到整个 target、清理失败只告警。验证注册契约，不建立任意插件代码沙箱。
- S12：插件 ID 直接写普通依赖 shim，可覆盖正常业务导入并造成插件模块隐式可见。
- S13：无 hooks 的外部插件 build 未校验 ABI/options；只按入口文件词法计数会拒绝同模块 #load 的唯一真实插件入口。
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
- Windows与可用WSL大小写敏感FS验证；实际debug/release自举、配套安装、修复后的`publication_install`与S01均须真实退出0。超时、0命中过滤与打印中间汇总不能算通过。
- 完整套件需真实终止和连续两轮最终0失败，确认新增测试按名称执行。合入最新integration后再验证；merger核对diff、独立复核后关闭本票与0096。
- 挂起Windows测试及关联Git进程的终止/maintenance对照仍等待用户许可；本票不授权停用防护、改全局Git或擅自终止这些进程。不得用主检出的挂起测试目录运行并发构建。
- 产出每个S/H/J/L编号的修复、反证或未解决映射；未解决的强制合同阻止0087关闭。
