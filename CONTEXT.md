# Juice CLI Context

Juice 是一个面向 Jai  的命令行构建工具；本上下文统一描述其命令、workspace 准备、命令执行语言与测试语言。

## Command language

**Command**:
用户通过 Juice 请求的一项可命名操作，例如 `build`、`run` 或 `clean`。一个 command 具有自己的参数语义、前置条件和成功/失败结果。

**Prerequisite command（前置 command）**:
在目标 command 之前必须成功完成的另一个 command。前置关系表达命令之间的执行依赖，而不是把两个 command 合并为一个 command。

**Build**:
根据当前 workspace 的 package 与 target 定义，产生可执行输出的 command。Build 从入口闭包探测 test block：闭包含之则以剥离视图编译，不含则原样直编。Testing 断言模块源码含 test block 时不可被 jai 直接编译，Build 以该模块的 STRIP 视图替代 `#import "Testing"` 解析（与 Test 的 EXPAND 视图、Bootstrap build 的 STRIP 视图三路径对称的特例；模块 test-free 或不存在时无此行为）。Build 构建 root package 的全部 effective target，但不会在每次构建前自动清空 target directory。没有 effective target 时，Build 无需准备 dependencies，也不创建 target directory 或 artifact，但仍成功完成并明确说明没有可构建目标。对 LIB package，Build 仅验证导入入口，不调用编译器。

**Run**:
选择一个 target，先通过 `build` 构建 root package 的全部 effective target，再启动所选 target 的 artifact。只有一个 effective target 时默认选择它；有多个时优先选择与 package 同名的 target，否则必须以大小写完全一致的名称明确指定 target。

**Clean**:
递归删除 root package 与 workspace member 的 target directory 整目录（含依赖 shim 与转译产物）。Clean 通过 workspace discovery 确定 member，但不解析、获取或更新 dependencies。所有清理路径先完成验证；单个删除失败不阻止其他已验证路径的清理，但会使 Clean 整体失败。

**Test**:
执行当前 package 单元测试的 command。Test 以 prepare-workspace 为前置 command，不依赖 build；消费 prepared workspace 但不消费 artifact plan——LIB package 没有 effective target 时依然可测。Test 接受至多一个 pattern 参数，对最终报告名做大小写敏感子串匹配。没有发现任何 test block 或 pattern 零命中时，Test 成功完成并明确说明，不进入测试构建；测试失败使 command 失败，与编译失败共用非零退出码。

**Bootstrap build（自举构建）**:
仓库根 `build.jai` metaprogram 直接构建 juice 自身的路径，独立于 Build command。src 原文件内联 test block 后，Bootstrap build 的构建输入是剥离视图——与 Build command 共用同一转译器与视图契约（[ADR 0006](docs/adr/0006-bootstrap-build-strips-inline-test-blocks.md)）；行号与诊断经视图映射对应原文件。Test support 文件不在其构建输入内。
_Avoid_: 发布视图树（预生成剥离源码树作为构建输入的方案，已被 ADR 0006 排除）。

## Workspace language

**Workspace preparation**:
为需要 package、target 和依赖信息的 command 准备当前 workspace 状态的过程。它包含读取 root package、发现 workspace member、解析 effective target，以及按 command 需要解析或获取 dependencies。

**Workspace discovery**:
通过执行 root package manifest 来发现并验证位于 package root 内的 workspace member 的过程。Workspace discovery 产生独立的 discovery 结果，不解析、获取或更新 dependencies；因 manifest 本身是可执行的 Jai 声明，所以它不承诺没有 manifest 自身产生的副作用。Discovery 保留已评估的 member declaration；dependency preparation 消费同一快照，不重新执行 workspace manifest。没有 package declaration 时，当前目录仍可产生仅包含自身的最小 discovery，供 Clean 使用；已有但无效的 package declaration 不产生可清理的 workspace。

**Workspace member**:
由 root package 声明、位于 root package 目录之内的另一个 package。每个 member 路径必须唯一、可移植并解析到包含 package manifest 的目录；不同文本路径不得指向同一个 member。

**Prepared workspace（已准备 workspace）**:
由成功的 workspace discovery 继续完成 effective target 解析后交给 command 的完整状态，聚合 package declaration、已验证的 workspace member 和 root package 的 artifact plan。它要求存在有效 package declaration；消费它的 command 不再重新解释 target 缺省值或 workspace member。artifact plan 为空或未被消费不妨碍其成立——Test 消费 prepared workspace 但不消费 artifact plan，LIB package 无 effective target 时仍可测。

**Package root**:
包含当前 package manifest、作为 package-relative path 基准的目录。Juice 将启动时的工作目录视为 package root，不向父目录搜索 manifest。

**Package declaration**:
Package manifest 对 package 的显式描述。它保留作者声明的 target 信息，而不把约定产生的默认 target 混入声明本身。每个 package 都具有非空、可作为 portable filename 的稳定名称以及明确版本；名称不从目录名推导。无效或不完整的 package declaration 不产生 prepared workspace。

**Package type（包类型）**:
Package 的角色：LIB 表示该 package 是供其他 package 通过 `#import` 引用的库，不声明 executable target、不产生 artifact，但可被 Test 测试；BIN 表示按 target declaration 与默认入口产生 executable。类型未指定时由约定推导：存在显式 target 或默认入口 `src/main.jai` 推导为 BIN，存在导入入口推导为 LIB，其余视为 BIN。
_Avoid_: module 类型、library target。

**Import entry（导入入口）**:
LIB package 提供给消费者的模块入口，约定为 package root 的 `module.jai` 或 `src/module.jai`（前者优先）；消费者以 package 名执行 `#import`。Import entry 是文件系统事实与约定的结合，不在 manifest 中声明。
_Avoid_: root_file、入口文件（易与 target 的入口文件混淆）。

**Target declaration**:
Package declaration 中对一个可构建、可运行目标的显式描述。Target declaration 必须明确 target 名称与入口文件；target 名称在 package 内唯一，是不包含路径含义且在支持平台上都可作为文件名的标识；名称比较在命令选择时大小写敏感，在 artifact 冲突检查时不区分大小写；入口文件使用可移植的 package-relative path，必须解析为 package root 内存在的普通 `.jai` 文件；一旦存在显式 target，package 就不再发现 implicit target。显式 target 只属于 BIN package；LIB package 声明显式 target 是无效声明。

**Implicit target（隐式 target）**:
BIN package 没有显式 target、但 package 中存在默认入口文件 `src/main.jai` 时由约定产生的 target。Implicit target 使用 package 名称作为 target 名称；默认入口若是指向 package 外部的符号链接，则它是无效声明而不是“没有 target”。是否产生 implicit target 取决于默认入口文件是否存在，而不取决于其他约定。

**Effective target（有效 target）**:
将 root package 的 target declaration 或 implicit target 与 package 默认约定合并后得到的完整 target 含义。其入口文件是 package root 内不能发生路径逃逸的相对路径，并且必须解析为存在的普通 `.jai` 文件。Build 和 Run 共同依据 effective target，而不各自解释缺省值。LIB package 没有 effective target。

**Artifact plan（产物计划）**:
描述 effective target 将产生的 artifact，包含 target 名称、结果目录以及带平台扩展名的规范化绝对 artifact 路径。Build 与 Run 共同消费同一份 artifact plan。

**Artifact（产物）**:
Effective target 构建后得到的可执行输出，具有确定的名称与位置；Build 产生 artifact，Run 启动同一个 artifact。Artifact 的默认名称等于 effective target 名称。测试生成物不是 artifact。

**Target directory（目标目录）**:
Package 的全部 Juice 管理生成物所在的固定约定目录 `target/`：artifact 与编译中间物（obj、构建 metaprogram 等）落其根，依赖导入 shim 落 `target/packages/`，转译产物落 `target/transpile/`。同一 package 的不同 artifact 以各自名称共存于其根。Target directory 必须是位于 package root 内的普通目录，不能是符号链接或其他路径重定向；artifact 也不能以符号链接占据计划路径。Clean 递归删除 root package 与 workspace member 的 target directory 整目录。与 Target declaration 同名异义（生成物目录 vs 构建目标声明），接受撞词。
_Avoid_: result 目录（遗留不再管理）、bin 目录。

**Transpile（转译）**:
将含 test block 的源文件转换为合法 Jai 的 source-to-source 步骤，是 Juice 进程内的库。Build 从入口闭包探测：闭包含 test block 才转译（剥离模式），否则原样直编；Test 对发现的全部文件转译（展开模式）。Test block 的保证生效范围是 build 下入口经字面量 in-package `#load` 可达的文件、test 下全包发现的文件；非字面量与 out-of-package `#load` 的目标不转译，其含 test block 由编译错误暴露。转译产物按内容寻址缓存。
_Avoid_: 通用语法扩展框架（转译只为 test block 服务）。

**View（视图）**:
一个源文件经 Transpile 生成、与其一一对应的合法 Jai 产物，镜像 package 相对目录结构。剥离视图删除 test block 并将 in-package `#load` 重写为指向目标视图；测试视图将 test block 转换为带注记的普通过程并剥离 in-package `#load`，符号经程序级可见性共享。视图与原文件行号一一对应，产物中的行列坐标可直接对照原文件；原文件路径的还原由测试驱动携带的映射承担。
_Avoid_: 把视图与一般「产物」混称（视图专指转译产物）。

**Local dependency directory（本地依赖目录）**:
Root workspace 中由 Juice 管理的 `target/packages/` 子目录。Juice 为每个依赖生成一个以依赖名命名的导入 shim，指向被依赖方的导入入口；消费者以 package 名 `#import` 引用。被依赖方不要求有 package manifest——任何符合导入入口约定的 Jai 模块都可作为依赖。本地依赖目录随 target directory 一并清理。

**Unspecified value（未指定值）**:
Package declaration 中省略的可选值或显式提供的空值；两者具有相同含义。若某值没有可用约定，未指定该值就是无效声明。

## Test language

**Test block**:
源文件顶层的 Zig 风格单元测试声明：`test "name" { ... }` 或匿名 `test { ... }`。Test block 不是合法 Jai，必须经 Transpile 转换为普通过程后才能编译。块体是无参数、无返回值的过程体：失败不经返回值通道，由 Testing 全局登记；裸 `return` 提前结束当前测试。可见性等于所在文件顶层的可见性；仅文件顶层允许，函数体与类型声明体内的 test 由转译期拒绝。命名测试以名字为报告名，允许同名共存，撞名时报告附 package 相对路径消歧；匿名测试的报告名为 package 相对路径:行号。
_Avoid_: 测试函数、容器式测试。

**Test discovery**:
为 Test 确定测试源的过程：从 package root 全量递归扫描小写扩展名的 `.jai` 文件，不跟随符号链接；排除点开头条目、package root 的 target directory、tests/data/（fixture 目录）与 modules/（模块目录）以及各 package 的 manifest。Test discovery 消费 workspace discovery 快照（member 边界）但不并入 workspace discovery。root 扫描不进 member 子树，member 以自身为 root 测试；依赖中的 test block 不发现、不执行。遍历顺序确定（字典序），测试枚举、调用与报告顺序由它派生。

**Testing**:
Juice 的一级断言模块，测试程序中的用户代码以 `#import "Testing"` 引用。提供最小断言集 expect、expect_eq、fail：断言失败即登记并中止当前测试，套件继续；失败即时逐条输出，结束时汇总计数，失败数非零使测试构建失败。失败报告以 `路径:行,列` 语法指向原文件坐标。Testing 仅依赖 Basic，对执行模型中立。

**Test support（测试支撑代码）**:
`src/test_support.jai` 约定位置，收录供测试程序共享的声明：跨 test block 复用的 helper、recording fake、记录全局与测试常量。Test support 不被入口 `#load` 引用，不进 Build 闭包、不参与发布构建；Test discovery 全包扫描将其收录进测试程序，src 内联 test block 经程序级可见性引用其声明。测试共享声明只允许位于 Test support 文件。
_Avoid_: 测试专用声明散落其他源文件顶层（会随剥离视图进入发布产物）。

**Test driver**:
Juice 为执行测试生成的测试程序核心：一个无入口点的生成文件，收录全部视图，以编译期执行方式运行经 pattern 过滤的测试清单，存在失败时使编译失败。测试程序的全部生成物（视图、驱动、metaprogram）位于 target directory 的转译子树，不产生 artifact。测试在编译期环境执行，崩溃即测试构建失败、无汇总；Testing 模块经生成的 metaprogram 注入测试程序。
_Avoid_: test runner（无运行期 runner 进程）、测试可执行文件。

## Command organization

**Command registry**:
Juice 当前可用 command 的目录。它让 command 的名称、说明、参数责任和前置关系可被统一发现，但不改变各 command 自己拥有其行为的事实。

**Dispatcher**:
根据用户输入在 command registry 中选择 command，按其前置关系执行所需 command，并把最终成功/失败结果交给 CLI 进程。Dispatcher 在执行任何 prerequisite 之前用目标 command 自身的参数规则验证用户参数；参数无效时任何 command 都不执行。

## Relationships

- Dispatcher 从 command registry 选择一个 command。
- Command 可以声明零个或多个 prerequisite command；prerequisite command 成功后，目标 command 才能执行。
- `run` 依赖 `build`；`build` 依赖完整的 workspace preparation；workspace preparation 依赖 workspace discovery。
- `clean` 依赖 workspace discovery，但不解析、获取或更新 dependencies；它递归删除 root package 与已验证 workspace member 的 target directory 整目录。
- Workspace discovery 与 prepared workspace 是递进但不同的结果：Clean 只消费前者，Build、Run 与 Test 消费后者。
- Package declaration 保留作者声明；effective target 和 artifact plan 表达约定补全后的构建含义。
- 当前 Build 和 Run 只解析 root package 的 effective target；workspace member 仍是 workspace discovery 的一部分。
- Package type 决定 package 的角色：LIB package 是导入源，验证导入入口后成功完成且不产生 artifact；BIN package 按 target declaration 与默认入口产生 executable。未指定的类型按约定推导。
- Workspace member 要被引用，必须被声明为依赖；dependency preparation 为其在本地依赖目录中注册导入 shim 供 `#import` 解析。
- 依赖的被依赖方不要求是 Juice package；符合导入入口约定的普通 Jai 模块同样可被声明为依赖并引用。
- Build 按全部 artifact plan 产生 artifact；Run 在同一组 artifact plan 中选择并启动 artifact。
- Effective target 先于 dependency preparation 得到验证；没有 effective target 时，Build 不触发 dependency preparation。
- Command registry 描述可发现的 command；Dispatcher 负责执行顺序，但不拥有 build、run、clean、test 的业务行为。
- `test` 依赖 prepare-workspace（不依赖 build）；消费 prepared workspace 但不消费 artifact plan，LIB package 无 effective target 时仍可测。
- Test block 必须经 Transpile 转换为视图后才能编译；build 探测后剥离、test 展开，run 经 build 继承。
- Bootstrap build 与 Build command 共用同一转译器与视图契约；Test support 被 Test discovery 扫描收录、不进 Build 闭包与 Bootstrap build 输入。
- Test discovery 消费 workspace discovery 快照但不并入；member 以自身为 root 测试，依赖不发现不执行。
- 测试程序全部生成物位于 target directory 的转译子树，不是 artifact。
- Testing 经生成的 metaprogram 注入测试程序，收口断言与失败汇总。
- 视图与原文件行号一一对应；失败报告与转译期诊断引用原文件坐标。
- Clean 递归删除 root 与 member 的 target directory 整目录。
