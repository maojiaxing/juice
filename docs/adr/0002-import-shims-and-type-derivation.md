# 0002: 依赖消费统一走导入 shim；类型按约定推导

ADR 0001 定了"导入入口 = 包根 module.jai"并把 member 链接为 `.packages/<name>` 目录 junction。三件事推翻了它：用户期望入口约定是 `src/module.jai`（与 `src/main.jai` 对仗）且类型可从入口文件自动推导；Jai 编译器解析 junction 后按**真实目录名**做可移植性检查，依赖名 ≠ 源目录名即被拒；junction 目录与同名 `<name>.jai` 在同一 import 目录下会被判 "both single-file and directory form" 冲突。

**决定**：

1. **依赖消费只经导入 shim**：`.packages` 中不再放目录 junction，每个依赖生成一个普通单文件 shim `<name>.jai`，内容 `#load "<源包绝对路径>/<入口>"`。普通文件不触发目录名规范化，任意源目录名、任意布局（`module.jai` / `src/module.jai` / `<name>.jai` 单文件）都可解析。代价是 shim 内嵌机器本地绝对路径——`.packages` 本就是 clean 可重建的本地缓存，可接受。
2. **被依赖方不要求 package manifest**：探测纯按文件系统约定，社区里非 Juice 构建的普通 Jai 模块（无 `package.jai`）同样可作为依赖声明与引用；git 依赖在找不到 `package.jai` 时回退到 repo 根的模块布局。
3. **`Package_Type` 增加 `UNSPECIFIED`（默认）**：未指定类型时按约定推导——显式 target 或 `src/main.jai` → BIN；导入入口存在 → LIB；其余 BIN。导入入口约定扩展为包根 `module.jai` 或 `src/module.jai`（前者优先）。

**Considered Options**: `.packages` 内藏 `.links/<name>/` junction 子目录 + 相对路径 shim——保留 `.packages` 可搬运性，但多一层目录与一次 mklink（NTFS/cmd 依赖），收益仅是缓存目录可整体拷贝，否决。

**Consequences**: junction 链接路径（`link_directory`/mklink）整体删除，此前为 mklink/rmdir 做的 Windows 反斜杠参数修复只剩 rmdir 一处仍在使用。类型推导发生在 target 解析层，`Prepared_Workspace` 携带推导后的角色供命令消费；推导不回写 manifest 声明。
