# Juice CLI Context

Juice 是一个面向 Jai  的命令行构建工具；本上下文统一描述其命令、workspace 准备和命令执行语言。

## Command language

**Command**:
用户通过 Juice 请求的一项可命名操作，例如 `build`、`run` 或 `clean`。一个 command 具有自己的参数语义、前置条件和成功/失败结果。

**Prerequisite command（前置 command）**:
在目标 command 之前必须成功完成的另一个 command。前置关系表达命令之间的执行依赖，而不是把两个 command 合并为一个 command。

**Build**:
根据当前 workspace 的 package 与 target 定义，产生可执行输出的 command。Build 构建 root package 的全部 effective target，但不会在每次构建前自动清空结果目录。没有 effective target 时，Build 无需准备 dependencies，也不创建结果目录或 artifact，但仍成功完成并明确说明没有可构建目标。

**Run**:
选择一个 target，先通过 `build` 构建 root package 的全部 effective target，再启动所选 target 的 artifact。只有一个 effective target 时默认选择它；有多个时优先选择与 package 同名的 target，否则必须以大小写完全一致的名称明确指定 target。

**Clean**:
删除 root package 与 workspace member 的结果目录，以及 workspace 的本地依赖链接。Clean 通过 workspace discovery 确定 member，但不解析、获取或更新 dependencies。所有清理路径先完成验证；单个删除失败不阻止其他已验证路径的清理，但会使 Clean 整体失败。

## Workspace language

**Workspace preparation**:
为需要 package、target 和依赖信息的 command 准备当前 workspace 状态的过程。它包含读取 root package、发现 workspace member、解析 effective target，以及按 command 需要解析或获取 dependencies。

**Workspace discovery**:
通过执行 root package manifest 来发现并验证位于 package root 内的 workspace member 的过程。Workspace discovery 产生独立的 discovery 结果，不解析、获取或更新 dependencies；因 manifest 本身是可执行的 Jai 声明，所以它不承诺没有 manifest 自身产生的副作用。没有 package declaration 时，当前目录仍可产生仅包含自身的最小 discovery，供 Clean 使用；已有但无效的 package declaration 不产生可清理的 workspace。

**Workspace member**:
由 root package 声明、位于 root package 目录之内的另一个 package。每个 member 路径必须唯一、可移植并解析到包含 package manifest 的目录；不同文本路径不得指向同一个 member。

**Prepared workspace（已准备 workspace）**:
由成功的 workspace discovery 继续完成 effective target 解析后交给 command 的完整状态，聚合 package declaration、已验证的 workspace member 和 root package 的 artifact plan。它要求存在有效 package declaration；消费它的 command 不再重新解释 target 缺省值或 workspace member。

**Package root**:
包含当前 package manifest、作为 package-relative path 基准的目录。Juice 将启动时的工作目录视为 package root，不向父目录搜索 manifest。

**Package declaration**:
Package manifest 对 package 的显式描述。它保留作者声明的 target 信息，而不把约定产生的默认 target 混入声明本身。每个 package 都具有非空、可作为 portable filename 的稳定名称以及明确版本；名称不从目录名推导。无效或不完整的 package declaration 不产生 prepared workspace。

**Target declaration**:
Package declaration 中对一个可构建、可运行目标的显式描述。Target declaration 必须明确 target 名称与入口文件；target 名称在 package 内唯一，是不包含路径含义且在支持平台上都可作为文件名的标识；名称比较在命令选择时大小写敏感，在 artifact 冲突检查时不区分大小写；入口文件使用可移植的 package-relative path，必须解析为 package root 内存在的普通 `.jai` 文件；一旦存在显式 target，package 就不再发现 implicit target。Package type 不限制显式或隐式 executable target。

**Implicit target（隐式 target）**:
Package 没有显式 target、但 package 中存在默认入口文件 `src/main.jai` 时由约定产生的 target。Implicit target 使用 package 名称作为 target 名称；默认入口若是指向 package 外部的符号链接，则它是无效声明而不是“没有 target”。是否产生 implicit target 取决于默认入口文件是否存在，而不取决于 package type。

**Effective target（有效 target）**:
将 root package 的 target declaration 或 implicit target 与 package 默认约定合并后得到的完整 target 含义。其入口文件是 package root 内不能发生路径逃逸的相对路径，并且必须解析为存在的普通 `.jai` 文件。Build 和 Run 共同依据 effective target，而不各自解释缺省值。

**Artifact plan（产物计划）**:
描述 effective target 将产生的 artifact，包含 target 名称、结果目录以及带平台扩展名的规范化绝对 artifact 路径。Build 与 Run 共同消费同一份 artifact plan。

**Artifact（产物）**:
Effective target 构建后得到的可执行输出，具有确定的名称与位置；Build 产生 artifact，Run 启动同一个 artifact。Artifact 的默认名称等于 effective target 名称。

**Result directory（结果目录）**:
Package 的 artifact 所在、由 Juice 管理的固定约定目录，目录名为 `result`。同一 package 的不同 artifact 以各自名称共存于该目录。结果目录必须是位于 package root 内的普通目录，不能是符号链接或其他路径重定向；artifact 也不能以符号链接占据计划路径。Clean 可递归删除结果目录中的全部内容，但不把旧的通用 `bin` 目录视为 Juice 管理的结果目录。

**Local dependency directory（本地依赖目录）**:
Root workspace 中由 Juice 管理的 `.packages` 目录。Workspace clean 只删除 root workspace 的本地依赖目录，不删除 member 目录中独立存在的 `.packages`。

**Unspecified value（未指定值）**:
Package declaration 中省略的可选值或显式提供的空值；两者具有相同含义。若某值没有可用约定，未指定该值就是无效声明。

## Command organization

**Command registry**:
Juice 当前可用 command 的目录。它让 command 的名称、说明、参数责任和前置关系可被统一发现，但不改变各 command 自己拥有其行为的事实。

**Dispatcher**:
根据用户输入在 command registry 中选择 command，按其前置关系执行所需 command，并把最终成功/失败结果交给 CLI 进程。

## Relationships

- Dispatcher 从 command registry 选择一个 command。
- Command 可以声明零个或多个 prerequisite command；prerequisite command 成功后，目标 command 才能执行。
- `run` 依赖 `build`；`build` 依赖完整的 workspace preparation；workspace preparation 依赖 workspace discovery。
- `clean` 依赖 workspace discovery，但不解析、获取或更新 dependencies；它清理 root package 与已验证 workspace member 的结果目录，以及 root workspace 的本地依赖目录。
- Workspace discovery 与 prepared workspace 是递进但不同的结果：Clean 只消费前者，Build 与 Run 消费后者。
- Package declaration 保留作者声明；effective target 和 artifact plan 表达约定补全后的构建含义。
- 当前 Build 和 Run 只解析 root package 的 effective target；workspace member 仍是 workspace discovery 的一部分。
- Package type 不决定是否存在 executable target；target declaration 与默认入口文件决定它。
- Build 按全部 artifact plan 产生 artifact；Run 在同一组 artifact plan 中选择并启动 artifact。
- Effective target 先于 dependency preparation 得到验证；没有 effective target 时，Build 不触发 dependency preparation。
- Command registry 描述可发现的 command；Dispatcher 负责执行顺序，但不拥有 build、run、clean 的业务行为。
