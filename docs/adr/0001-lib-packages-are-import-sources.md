# 0001: LIB package 是导入源，不是编译产物

Jai 的模块是源码目录：消费者通过 `#import` + import 目录解析，不存在二进制库链接。此前 juice 把所有 target 一律编译为 executable（`Binary_Target`），库被迫伪造 `main` 或无名 target 塞进 bin 模型——这正是 parser-kit 构建报错（空 target 名经 `-exe ''` 触发 Windows 空参数丢弃、参数左移）的模型根源。

**决定**：

1. `Package.type` 成为真实判别：LIB 包不声明 executable target、不产生 artifact plan，Build 对它只验证导入入口（package root 的 `module.jai`，import 名 = package 名）；BIN 包行为不变。LIB 声明显式 target 属于无效声明——先严格，未来放宽（允许库附带 demo executable）不破坏已有 manifest，反向收紧则会。
2. 删除 manifest 的 `root_file` 字段。导入入口是文件系统约定（`module.jai` 在 package root），Jai 的模块查找规则不接受重定向，一个只能取单值的声明字段是噪音；旧默认值 `"modulejai"` 本就是 `"module.jai"` 的 typo。
3. Workspace member 的引用消费走本地依赖目录：member 必须被声明为依赖，dependency preparation 把 member 目录链接进 `.packages/<name>`，消费者的 `#import` 经现有 import 目录注入解析。对齐 Cargo 的 path dependency 模型（是 workspace member 不等于可引用，必须声明为依赖）。

**Considered Options**: member 直接注入 import 目录（旧版 `driver.member_paths` 的做法，注入 member 父目录或 member 根）。否决：注入父目录会让成员的兄弟目录以模块名形式泄漏进解析空间（`#import "src"` 命中 root/src），注入 member 根则要求自命名布局、与 `.packages` 的约定不一致；且无声明即引用，无法表达"member 存在但不被依赖"。

**Consequences**: 依赖解析目前不递归——消费者需自己声明完整依赖闭包，LIB 包的传递依赖不会自动进入 `.packages`（未来需要类似 lockfile 的闭包解析）。库包的"可编译性"不由 Build 验证（Jai 无独立的类型检查命令），只验证入口存在；真正的编译检查发生在消费者构建时。
