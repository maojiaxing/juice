# juice 重构版（otter）

juice 重构版的领域词汇表：包声明、插件、转译与测试的共享语言。每个会话开工前先读。

## 包与工作区

**Package declaration（包声明）**：
`package.jai` 里 `PACKAGE :: Package.{...}` 的声明，描述包的身份、目标、依赖、工作区成员与插件。模块名 `"Juice"` 是 load-bearing 的。
_Avoid_: manifest（指求值器的 KEY=VALUE 协议）、config

**Package root（包根）**：
一个包的目录根；workspace 成员与依赖都以包根为边界。

**Workspace member（工作区成员）**：
根包声明在 `workspace.members` 里的另一个包；成员测试以自身为根，不从根包聚合。

**Dependency（依赖）**：
包编译时导入的包；只影响导入解析，不激活插件。
_Avoid_: dev dependency（本模型没有独立的 devDependencies；插件声明承担工具面）

**Plugin declaration（插件声明）**：
`Package.plugins` 的一项：`id` + `version` + `options`。声明即让插件可用、激活、配置，并按声明序参与管线、钩子与 lint。成员插件的 id 是成员包名；内置插件用保留 id。
_Avoid_: plugin config file、transpile declaration、devDependency

**Plugin id**：
插件的身份。内置插件用保留 id（`load`、`test-block`）；成员插件用成员包名。
_Avoid_: rule name（lint 规则名是插件内部的另一层身份）

## Target 目录

**Target layout（目标布局）**：
包根下 `target/` 目录的布局契约：区根（`build/`、`modules/`、`transpile/`（含 `testing-module/`）、`plugins/`、`packages/`、`tests/`、`recovery/`、`evidence/`）与落点由 `Target_Layout` 模块（`src/target_layout.jai`）单一拥有；artifact 根、发布 modules 树与 transpile 视图树是 spec 钉死的字面量。`build/` 同时收生成的构建驱动与 build/test 程序的编译中间件（`.obj/.lib/.exp/.pdb/.added_strings`）；测试 scratch 在 `tests/`，崩溃恢复备份在 `recovery/`，证据日志在 `evidence/`；clean 整棵删除。
_Avoid_: build directory、输出目录（不区分区根与落点）

**Target scratch（测试临时区）**：
测试在 `target/tests/` 下的临时根，经 `target_scratch_dir` 派生；每次 test 命令启动先整区 prune，运行期测试自行重建。
_Avoid_: test cache、临时目录

**Test package root（测试包根常量）**：
生成的 test driver 顶层声明的 `JUICE_TEST_PACKAGE_ROOT`：测试程序的 intermediate_path 是 `target/build/`，包根不能从 Build_Options 剥离，测试助手直接消费该常量。
_Avoid_: juice_root（旧 juice 从 intermediate_path 推导的形态）

**Target recovery（恢复区）**：
`target/recovery/` 下的崩溃恢复备份：missing-source 测试在删除源文件前先落盘备份。test 命令的 scratch prune 刻意排除该区（崩溃后备份是唯一副本）；只有 clean 删除整个 target/。
_Avoid_: backup 目录、missing-source-backups（旧名）

**Target evidence（证据区）**：
`target/evidence/` 下的会话证据/日志，由开发工作流人工写入，工具不写；与所有 target 产物一样是易失的（clean 删除）。需要持久保留的验收证据仍入 `docs/implementation/`。
_Avoid_: audit 目录（旧的一次性文件散落形态）

## 插件

**Plugin（插件）**：
定义 `get_juice_plugin` 并以 `@juice_plugin` 尾注标记的模块；可贡献 transpile、lint、hooks 与 options schema 面。
_Avoid_: extension、addon

**Plugin face（插件面）**：
插件对框架的一项贡献面：transpile 管线、lint 观察、lifecycle 钩子、options schema。
_Avoid_: plugin type

**Pre-step plugin（前置插件）**：
贡献 PRESTEP `before` 钩子的插件，在 Transpile 之前变换编译输入（例如 jaix）。
_Avoid_: 单独使用 "pre-step" 指代插件、jaix front

**Source substitution table（源替换表）**：
前置插件的输出：原包相对路径 → 替换绝对路径，外加剔除集；命令据此选择编译输入。append-only、仅 root package、不新增文件。
_Avoid_: mirror table、view map

**Plugin prepare（插件准备）**：
命令级步骤：解析插件声明、扫描与链接成员插件、写注册文件、决定是否需要 plugin host。
_Avoid_: plugin load

**Plugin host（插件宿主）**：
PRESTEP-only 生成的子进程：加载注册文件、应用 options、运行 PRESTEP 钩子，经 host 记录返回阶段效果（替换、剔除、诊断）；零声明 hooks 插件 = 不 spawn。
_Avoid_: plugin runtime、third-party host（后者指通用 DLL/进程外宿主）

**Plugin registration file（插件注册文件）**：
命令级插件准备生成的会话产物 `target/plugins/registration.jai`：按声明序 import 插件模块并装配钩子；测试 metaprogram 与 plugin host 消费同一份，不二次扫描。不是发布模块面。
_Avoid_: plugin manifest、plugins.jai

**Plugin host record（host 记录）**：
plugin host 子进程写出的阶段效果文件 `target/plugins/host-records.txt`：`SUBSTITUTE` / `DROP` / `DIAG` / `OK` 行，值用 `%XX` 编码；父进程严格解析，缺失或坏记录 = 命令失败。
_Avoid_: host log

**Member hook face（成员 hook 面）**：
成员插件经 plugin host 执行的 lifecycle hook 集合；v1 只支持 PRESTEP/before。其它 stage/position 的声明在 prepare 期（host 校验）失败。AT 仍是 in-process 测试 seam，不是成员插件的承诺。
_Avoid_: hook face（不区分 in-process 与 member）

## 编排与 lifecycle

**Command lifecycle session（命令 lifecycle 会话）**：
一次 build/test 命令内，把 plugin prepare、插件声明解析、typed stage state 构造、PRESTEP host 与 seam 派发绑在一起的编排概念；命令只提供自己的前置动作与 stage body。`prepare → resolve → dispatch` 的协议由它拥有。
_Avoid_: lifecycle manager、orchestrator、pipeline（后者是 Transpile 管线）

**Stage state（阶段状态）**：
某个 stage seam 执行时由前置动作与主体读写的明确类型的状态，包括编译输入、视图与产物信息；状态随所属 seam 区分，不用通用上下文承载所有阶段。
_Avoid_: stage context、phase data、context bag

**Stage seam（阶段 seam）**：
可在不修改命令编排处改变阶段行为的接入点。活跃 seam 只有 PRESTEP 与 COMPILE；执行顺序为 before → body → after，`at` 不再是第三种挂载位置，而是 body 的替换。TRANSPILE 是 COMPILE 的首个前置动作，不是独立 seam。
_Avoid_: mount matrix、stage/position hook、lifecycle context

## 转译与测试

**Transpile（转译）**：
juice 进程内的锚点级文本变换，只服务 test block 与 `#load`。
_Avoid_: jaix、pre-step（两者是外部工具或前置层，不是 Transpile）

**Transpile pipeline（转译管线）**：
按声明序派发的转译插件链；内置插件是 `load` 与 `test-block`。
_Avoid_: 把 pre-step 混入管线

**View（视图）**：
Transpile 生成的、与源文件一一对应的合法 Jai 文本，行号保真。
_Avoid_: artifact

**Mirror（镜像）**：
jaix CLI 的逐文件输出树，作为前置插件的编译输入；不是 view。
_Avoid_: view

**Test block（测试块）**：
源文件顶层的 `test "name" { ... }` 或匿名 `test { ... }` 声明；不是合法 Jai，必须经 Transpile 才能编译。
_Avoid_: test case

**Test discovery（测试发现）**：
从编译器注记流中枚举测试过程的机制；test block 与手写 `@test` 走同一发现源。
_Avoid_: test scan（扫描是文件收集，不是发现）

**Test runner（测试运行器）**：
生成的测试程序入口 `<root>/target/transpile/test_runner.jai`；由 `src/test_runner.jai` 发射（driver 源以 `add_build_string` 嵌入，不单独落盘），`test` 命令 spawn，`build.jai` 按 `TEST_RUNNER_FILE_NAME`（`src/metaprogram.jai`）识别并跳过自身构建。
_Avoid_: first.jai（旧名）、driver.jai（旧两文件形态；driver 是嵌入 runner 的 build 字符串，不是入口）
