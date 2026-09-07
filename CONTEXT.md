# Juice CLI Context

Juice 是一个面向 Jai workspace 的命令行构建工具；本上下文统一描述其命令、workspace 准备和命令执行语言。

## Command language

**Command**:
用户通过 Juice 请求的一项可命名操作，例如 `build`、`run` 或 `clean`。一个 command 具有自己的参数语义、前置条件和成功/失败结果。

**Prerequisite command（前置 command）**:
在目标 command 之前必须成功完成的另一个 command。前置关系表达命令之间的执行依赖，而不是把两个 command 合并为一个 command。

**Build**:
根据当前 workspace 的 package 与 target 定义，产生可执行输出的 command。

**Run**:
选择一个 target，确保它已经由 `build` 产生可执行输出，然后启动该输出的 command；`build` 是 `run` 的前置 command。

**Clean**:
删除当前 workspace 的 Juice 生成输出和本地依赖链接的 command；它不要求先读取 package manifest 或解析依赖。

## Workspace language

**Workspace preparation**:
为需要 package 和依赖信息的 command 准备当前 workspace 状态的过程，包含读取根 package、识别 workspace member 和解析/获取依赖。它不是所有 command 的共同前置条件。

**Target**:
Package 中可独立构建和运行的可执行产物定义，至少确定名称、入口文件和输出目录。

## Command organization

**Command registry**:
Juice 当前可用 command 的目录。它让 command 的名称、说明、参数责任和前置关系可被统一发现，但不改变各 command 自己拥有其行为的事实。

**Dispatcher**:
根据用户输入在 command registry 中选择 command，按其前置关系执行所需 command，并把最终成功/失败结果交给 CLI 进程。

## Relationships

- Dispatcher 从 command registry 选择一个 command。
- Command 可以声明零个或多个 prerequisite command；prerequisite command 成功后，目标 command 才能执行。
- `run` 依赖 `build`；`build` 依赖 workspace preparation。
- `clean` 不依赖 workspace preparation。
- Command registry 描述可发现的 command；Dispatcher 负责执行顺序，但不拥有 build、run、clean 的业务行为。
