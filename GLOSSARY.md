# Juice 包与构建领域词汇

本文件是 juice 重构版（otter）的**唯一权威词汇表**，合并了原先的 `GLOSSARY.md`（领域概念）与 `CONTEXT.md`（工程实现契约）。每个会话开工前先读。

文件分为两层：前七节是**领域概念**，用来说明"这是什么"；最后一节是**实现契约**，用来记录"在代码里叫什么、落在哪、格式是什么"。讨论需求时以领域概念为准；写代码和排查问题时查实现契约。

边界：领域概念不依赖具体实现；实现契约可以随重构变化，但改动时必须同步更新本节与相关票据。

## 一、包与产物

**包（Package）**：
具有自身身份、组织可复用代码与程序的单位。一个包可以提供零个或多个导入模块和可执行产物，也可以没有公开产物，不由互斥的"库包"或"程序包"角色限制。
_Avoid_: 用 LIB/BIN 二选一表示包的全部能力

**包声明（Package declaration）**：
对包身份、所提供的能力、依赖和扩展配置的描述，即 `package.jai` 里 `PACKAGE :: Package.{...}` 的声明。它不是完整构建步骤的编排。
_Avoid_: 用包声明代指任意构建任务图；manifest（指求值器的 KEY=VALUE 协议）；config

模块名 `"Juice"` 是 load-bearing 的。

**声明三态（Declaration presence）**：
可省略字段区分省略、显式空与显式非空。用户只写普通字符串与数组；内部保留默认标记只属于加载器，不是公开配置值。数组零长度与空字符串都不是省略判据。
_Avoid_: 用空数组/空字符串表示省略

**包根（Package root）**：
一个包的目录根；workspace 成员与依赖都以包根为边界。

**导入模块（Import module）**：
包向使用者提供的、可以按名导入的代码接口。它不等同于包本身，也不等同于需要链接的二进制库。
_Avoid_: 把包名、模块名和二进制库名视为同一个名字

**可执行产物（Executable）**：
从包中构建出来、能够独立运行的程序。它是包提供的一种产物，而不是包的类型。
_Avoid_: 用 BIN 表示整个包

**默认运行程序（Default executable）**：
包为未显式选择程序的运行请求指定的可执行产物。它不等于包名所暗示的程序，也不表示包内其他程序不参与构建。
_Avoid_: 把默认运行程序当作包的唯一可执行产物

**源码入口（Entry）**：
导入模块或可执行产物采用的源码起点。它与包身份、模块导出名和程序名是不同概念。
_Avoid_: 把入口文件名视为公开名称

**导出名（Export name）**：
提供方给公开导入模块定义的名字。它属于提供方接口，不等于包身份，也不等于使用者可另取的导入名。
_Avoid_: 把导出名和消费方别名混为一谈

**导入名（Import name）**：
使用者在自己的代码中引用导入模块时使用的名字。导入名可以与提供方的包名不同。
_Avoid_: 把导入别名当作来源身份

**模块可见范围（Module visibility）**：
某个包内代码能够直接按名引用的模块集合。它不等于完成构建所需的全部模块集合；提供方内部使用的模块不因此成为消费方可直接引用的模块。
_Avoid_: 把构建需要的模块全集当作每个包的公共导入范围

## 二、依赖与解析

**依赖（Dependency）**：
包编译时导入的模块引用；只影响导入解析，不激活插件。每条引用写明来源（PATH/GIT/WORKSPACE）与模块选择；`name` 是消费包内的引用名，不是提供方包名。更细的概念见下方各条。
_Avoid_: dev dependency（本模型没有独立的 devDependencies；插件声明承担工具面）

**依赖引用（Dependency reference）**：
使用者从一个明确来源选择所需公开模块的引用，这些模块可以来自不同包。它只描述自己的选择，不复述提供方仓库的包或模块总览；来源和包身份独立于导出名与导入名。
_Avoid_: 同名成员自动覆盖已声明来源

**依赖引用名（Dependency reference name）**：
使用者在自身包内识别一条依赖引用的名字。它不等于提供方包身份，也不会自动成为代码中的导入名。
_Avoid_: 把依赖引用名当作包名或模块导入别名

**依赖来源（Dependency source）**：
取得提供方内容的依据，可以是本地位置、Git 来源或工作区引用。它不由导入名或同名成员的存在隐式替代。
_Avoid_: 把来源定位、包身份和导入别名合成一个名称

**模块选择（Module selection）**：
消费方从具体包中选择某个公开导入模块的引用项，可赋予自己的导入名。它不是模块定义，也不是上游全部模块的枚举。
_Avoid_: 把引用清单当作提供方结构清单

**来源根（Source root）**：
一条依赖来源所确定的引用基准位置。它可以有根包，也可以只组织成员包，不等于某个模块的源码入口。
_Avoid_: 把来源根、包根和模块入口混为一谈

**已解析修订（Resolved revision）**：
某条 Git 依赖实际选定的具体提交。它与声明中可能移动的分支或标签引用不同，也不等于本地缓存副本；不同工程可以各自记录选择，同时共享对象内容缓存。
_Avoid_: 把声明引用、已选提交和缓存目录当成同一件事

**解析上下文（Resolution context）**：
以某个消费工程为根、确定其依赖选择的范围。不同上下文可以使用相同提供方源码而具有不同的传递依赖选择，不因共享源码就合并。
_Avoid_: 把全局源码存放位置当作所有消费者共享的依赖选择范围

**依赖解析状态（Dependency resolution state）**：
某个解析上下文中已经选定的依赖修订及其所属声明关系。它保留该工程的选择，不等于可重建的源码内容缓存。
_Avoid_: 把清理下载内容等同于清除工程的依赖选择

**源码内容缓存（Source content cache）**：
Juice 留存、可供多个解析上下文复用的 Git 来源内容副本。它表示哪些源码内容可取得，不决定各工程选择哪个修订。
_Avoid_: 把共享源码内容当成全局共享的依赖选择

## 三、工作区

**工作区（Workspace）**：
协调一组包的组织范围，自身不必也是一个包。属于同一工作区，不自动表示这些包是某条命令的全部操作对象。
_Avoid_: 把工作区成员集合等同于默认执行集合

**工作区成员（Workspace member）**：
被工作区纳入其组织范围的包，即根包声明在 `workspace.members` 里的另一个包。一个包至多归属一个工作区，成员关系不等于依赖关系；成员测试以自身为根，不从根包聚合。
_Avoid_: 把目录嵌套或依赖引用等同于成员资格

**工作区根包（Workspace root package）**：
包根与工作区根重合的包。它是该工作区的成员，纯工作区没有根包。
_Avoid_: 把工作区本身或任意当前包称为工作区根包

**默认成员（Default members）**：
工作区为根位置的未显式选包操作指定的成员集合。它不改变成员资格，也不替代成员位置调用时的当前包选择。
_Avoid_: 把默认成员当作工作区全部成员

**工作区引用（Workspace reference）**：
消费方明确要求来自自身所属工作区成员的本地依赖引用。它表达成员关系约束，不等于按任意本地位置引用，也不表示自动依赖所有成员。
_Avoid_: 把工作区引用当作普通路径的隐式替代

## 四、插件：领域概念

**插件（Plugin）**：
定义 `get_juice_plugin` 并以 `@juice_plugin` 尾注标记的模块；可贡献 transpile、lint、hooks 与 options schema 面。
_Avoid_: extension、addon

**插件模块（Plugin module）**：
提供 Juice 构建扩展入口契约的公开导入模块。它不是第三类包产物，普通导入该模块不等于启用其插件能力。
_Avoid_: 把插件模块等同于插件专用包或自动启用的依赖

**插件启用（Plugin activation）**：
消费包选择插件并使其能力参与自身构建流程的行为。它与取得插件源码、普通模块导入及工作区成员关系不同。
_Avoid_: 把可找到或已导入插件当作已经启用

**插件声明（Plugin declaration）**：
`Package.plugins` 的一项：`id` + `builtin` 或 `source`+`module` + `options`。声明即让插件可用、激活、配置，并按声明序参与管线、钩子与 lint。声明侧没有 `version`；内置插件用 `builtin = "load"` / `"test-block"`，外部插件给出显式来源与公开模块选择。
_Avoid_: plugin config file、transpile declaration、devDependency

**插件 id（Plugin id）**：
插件的身份，也是消费包内的引用名。内置插件用保留 id（`load`、`test-block`）；外部插件的 `id` 由显式 `source` + `module` 定位，不按成员包名猜测。
_Avoid_: rule name（lint 规则名是插件内部的另一层身份）

**插件面（Plugin face）**：
插件对框架的一项贡献面：transpile 管线、lint 观察、lifecycle 钩子、options schema。
_Avoid_: plugin type

## 五、插件：运行机制

**前置插件（Pre-step plugin）**：
贡献 PRESTEP `before` 钩子的插件，在 Transpile 之前变换编译输入（例如 jaix）。
_Avoid_: 单独使用 "pre-step" 指代插件、jaix front

**源替换表（Source substitution table）**：
前置插件的输出：原包相对路径 → 替换绝对路径，外加剔除集；命令据此选择编译输入。append-only、仅 root package、不新增文件。
_Avoid_: mirror table、view map

**派生视图（Derived source view）**：
一次包操作中由插件生成的、将逻辑包内源码路径映射到工程私有派生文件并明确记录丢弃/辅助源码的编译输入视图。它不改变包声明或源文件。
_Avoid_: 把派生视图当作新的包、公开产物或可回写的源码树

**插件准备（Plugin prepare）**：
命令级步骤：解析被选包自身的插件声明、按显式来源解析插件模块并写 import shim、写注册文件、决定是否需要 plugin host；每个被选包只准备一次，根配置不继承给成员。
_Avoid_: plugin load

**插件注册文件（Plugin registration file）**：
命令级插件准备生成的会话产物 `target/plugins/registration.jai`：按声明序 import 插件模块并装配钩子；测试 metaprogram 与 plugin host 消费同一份，不二次扫描。不是发布模块面。
_Avoid_: plugin manifest、plugins.jai

**插件宿主（Plugin host）**：
PRESTEP-only 生成的子进程：加载注册文件、应用 options、运行 PRESTEP 钩子，经 host 记录返回阶段效果（替换、剔除、诊断）；零声明 hooks 插件 = 不 spawn。
_Avoid_: plugin runtime、third-party host（后者指通用 DLL/进程外宿主）

**host 记录（Plugin host record）**：
plugin host 子进程写出的阶段效果文件 `target/plugins/host-records.txt`：`SUBSTITUTE` / `DROP` / `DIAG` / `OK` 行，值用 `%XX` 编码；父进程严格解析，缺失或坏记录 = 命令失败。
_Avoid_: host log

**成员 hook 面（Member hook face）**：
成员插件经 plugin host 执行的 lifecycle hook 集合；v1 只支持 PRESTEP/before。其它 stage/position 的声明在 prepare 期（host 校验）失败。AT 仍是 in-process 测试 seam，不是成员插件的承诺。
_Avoid_: hook face（不区分 in-process 与 member）

## 六、编排与 lifecycle

**命令 lifecycle 会话（Command lifecycle session）**：
一次 build/test 命令内，把 plugin prepare、插件声明解析、typed stage state 构造、PRESTEP host 与 seam 派发绑在一起的编排概念；命令只提供自己的前置动作与 stage body。`prepare → resolve → dispatch` 的协议由它拥有。
_Avoid_: lifecycle manager、orchestrator、pipeline（后者是 Transpile 管线）

**阶段状态（Stage state）**：
某个 stage seam 执行时由前置动作与主体读写的明确类型的状态，包括编译输入、视图与产物信息；状态随所属 seam 区分，不用通用上下文承载所有阶段。
_Avoid_: stage context、phase data、context bag

**阶段 seam（Stage seam）**：
可在不修改命令编排处改变阶段行为的接入点。活跃 seam 只有 PRESTEP 与 COMPILE；执行顺序为 before → body → after，`at` 不再是第三种挂载位置，而是 body 的替换。TRANSPILE 是 COMPILE 的首个前置动作，不是独立 seam。
_Avoid_: mount matrix、stage/position hook、lifecycle context

## 七、转译与测试

**转译（Transpile）**：
juice 进程内的锚点级文本变换，只服务 test block 与 `#load`。
_Avoid_: jaix、pre-step（两者是外部工具或前置层，不是 Transpile）

**转译管线（Transpile pipeline）**：
按声明序派发的转译插件链；内置插件是 `load` 与 `test-block`。
_Avoid_: 把 pre-step 混入管线

**视图（View）**：
Transpile 生成的、与源文件一一对应的合法 Jai 文本，行号保真。
_Avoid_: artifact

**镜像（Mirror）**：
jaix CLI 的逐文件输出树，作为前置插件的编译输入；不是 view。
_Avoid_: view

**测试块（Test block）**：
源文件顶层的 `test "name" { ... }` 或匿名 `test { ... }` 声明；不是合法 Jai，必须经 Transpile 才能编译。
_Avoid_: test case

**测试发现（Test discovery）**：
从编译器注记流中枚举测试过程的机制；test block 与手写 `@test` 走同一发现源。
_Avoid_: test scan（扫描是文件收集，不是发现）

**测试运行器（Test runner）**：
生成的测试程序入口 `<root>/target/transpile/test_runner.jai`；由 `src/test_runner.jai` 发射（driver 源以 `add_build_string` 嵌入，不单独落盘），`test` 命令 spawn，`build.jai` 按 `TEST_RUNNER_FILE_NAME`（`src/metaprogram.jai`）识别并跳过自身构建。
_Avoid_: first.jai（旧名）、driver.jai（旧两文件形态；driver 是嵌入 runner 的 build 字符串，不是入口）

## 八、实现契约：Target 目录

本节及以下记录代码中的实际名称与落点，会随重构变化。

**目标布局（Target layout）**：
包根下 `target/` 目录的布局契约：区根（`build/`、`modules/`、`transpile/`（含 `testing-module/`）、`plugins/`、`packages/`、`tests/`、`recovery/`、`evidence/`）与落点由 `Target_Layout` 模块（`src/target_layout.jai`）单一拥有；artifact 根、发布 modules 树与 transpile 视图树是 spec 钉死的字面量。`build/` 同时收生成的构建驱动与 build/test 程序的编译中间件（`.obj/.lib/.exp/.pdb/.added_strings`）；测试 scratch 在 `tests/`，崩溃恢复备份在 `recovery/`，证据日志在 `evidence/`；clean 整棵删除。
_Avoid_: build directory、输出目录（不区分区根与落点）

**测试临时区（Target scratch）**：
测试在 `target/tests/` 下的临时根，经 `target_scratch_dir` 派生；每次 test 命令启动先整区 prune，运行期测试自行重建。
_Avoid_: test cache、临时目录

**测试包根常量（Test package root）**：
生成的 test driver 顶层声明的 `JUICE_TEST_PACKAGE_ROOT`：测试程序的 intermediate_path 是 `target/build/`，包根不能从 Build_Options 剥离，测试助手直接消费该常量。
_Avoid_: juice_root（旧 juice 从 intermediate_path 推导的形态）

**恢复区（Target recovery）**：
`target/recovery/` 下的崩溃恢复备份：missing-source 测试在删除源文件前先落盘备份。test 命令的 scratch prune 刻意排除该区（崩溃后备份是唯一副本）；只有 clean 删除整个 target/。
_Avoid_: backup 目录、missing-source-backups（旧名）

**证据区（Target evidence）**：
`target/evidence/` 下的会话证据/日志，由开发工作流人工写入，工具不写；与所有 target 产物一样是易失的（clean 删除）。需要持久保留的验收证据仍入 `docs/implementation/`。
_Avoid_: audit 目录（旧的一次性文件散落形态）
