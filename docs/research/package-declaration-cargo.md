# 研究：Cargo 的包、产物、依赖与工作区语义

核查日期：2026-11-13。文档参考渠道：Rust 官方文档站 Cargo Book 的固定版本目录 `1.85.0`；Rust 1.85.0 发布公告于 2025-02-20 发布。文档规则不冒充当前稳定版规则，也未核查 Cargo 源码。另用本机 `cargo 1.96.0 (30a34c682 2026-05-25)` 对“同名成员与显式 Git 依赖”做了独立实验；实验版本与文档版本分开标注，不能据此宣称全部规则已在两版验证。

## 查证事实及示例

### Package、crate、target

Cargo manifest 描述一个 package；package 下可有多个 target。Cargo Book 在“Cargo Targets”把 target 描述为可编译为 crate 的源入口，列出 library、binary、example、test、benchmark。**这里的 target 是 package 内的编译单元/产物入口，不是 `--target` 指定的操作系统、架构等编译平台三元组。** Package 最多一个 library；可以有多个 bin（`[[bin]]`），也可有多个 example、integration test、benchmark。Library 默认源为 `src/lib.rs`，bin 常见入口是 `src/main.rs` 或 `src/bin/`；bin 可调用同 package library 的公开 API。因此单一 package 同时提供库和可执行程序是 Cargo 的一等形态。

约定目录布局会自动发现 targets；`[lib]`、`[[bin]]`、`[[example]]`、`[[test]]`、`[[bench]]` 可配置非约定目标，文档描述其为增加额外目标。`[package]` 中 `autolib`、`autobins`、`autoexamples`、`autotests`、`autobenches = false` 分别关闭相应类别的自动发现，不会替代手写声明。Target 名称/源路径可独立配置。2018 edition 起自动发现默认启用；2015 edition 在手工声明任一 target 时默认关闭自动发现，需注意这是 edition 条件，不宜泛化为固定优先级。

1.85.0 文档依据：[Cargo Targets](https://doc.rust-lang.org/1.85.0/cargo/reference/cargo-targets.html)。

**例 1：一个 package 同时提供库和程序**

```toml
[package]
name = "toolkit"
version = "0.1.0"
edition = "2021"

[lib]
path = "src/module.rs"

[[bin]]
name = "toolkit-cli"
path = "src/main.rs"
```

`src/module.rs` 是显式 library crate 入口，`src/main.rs` 是 executable target。此例说明 Cargo 支持一包多产物；不表示 Jai 的 module 要编译成独立 crate。

### Workspace 与选包/选产物

Workspace 把多个 package 作为成员统一管理，共用根目录的 `Cargo.lock` 和输出目录。根 `Cargo.toml` 若同时有 `[package]` 与 `[workspace]`，就是带根 package 的 workspace；只有 `[workspace]` 则为 virtual workspace，本身不是 package。`members` 可写目录或 glob；工作区目录内被引用的 `path` 依赖自动成为成员，其他成员由 `members` 指定，`exclude` 可排除路径。`default-members` 决定在 workspace 根目录且未显式选包时操作哪些成员；未设置时，虚拟 workspace 默认全部成员，带根 package 的 workspace 默认根 package。进入成员目录或指定 `--manifest-path` 则按所选 manifest 决定默认 package。`-p/--package` 选特定包，`--workspace` 选全部成员，可与 `--exclude` 配合。

1.85.0 文档依据：[Workspaces](https://doc.rust-lang.org/1.85.0/cargo/reference/workspaces.html#the-members-and-exclude-fields)。

**例 2：纯 workspace**

```toml
# Cargo.toml（根目录）
[workspace]
members = ["crates/*", "apps/cli"]
exclude = ["crates/sandbox"]
default-members = ["apps/cli"]
resolver = "2"
```

**例 3：根 package 加 workspace**

```toml
[package]
name = "root-app"
version = "0.1.0"

[workspace]
members = ["crates/*"]
default-members = [".", "crates/common"]
```

`cargo build`、`cargo test` 的 package selection 遵循上述默认成员规则；`--workspace` 与 `-p` 明确覆盖默认选择。`cargo test` 默认会构建被选包的 library、bin（有 integration tests 时）、examples，并运行适用的单元测试、集成测试、文档测试等，不等同于只编一个可执行文件。`cargo run` 面向 binary：一个可运行 bin 时可直接运行；多个 bin 时必须用 `--bin NAME` 或在 manifest 设 `default-run`，example 则可用 `--example NAME`。这形成两层选择：先选 package，再选 target/产物。命令依据：[build](https://doc.rust-lang.org/1.85.0/cargo/commands/cargo-build.html#package-selection)、[test](https://doc.rust-lang.org/1.85.0/cargo/commands/cargo-test.html#target-selection)、[run](https://doc.rust-lang.org/1.85.0/cargo/commands/cargo-run.html#package-selection)。

### 依赖来源、身份与锁定

普通 registry 依赖以 package 名和版本约束声明；path 依赖以包含 `Cargo.toml` 的目录定位；Git 依赖以仓库 URL 定位，可选 `branch`、`tag`、`rev`。Cargo 遍历 Git 仓库寻找所请求包的清单；**`package` 指实际包名，不是子目录路径**。依赖表键是本地引用名，`package` 可指明外部实际 package 名，省略时默认等于依赖表键；别名不等于更名或复制 package。Git 分支/标签可能移动，`rev` 指定修订；解析后 `Cargo.lock` 保存具体版本、来源与 Git commit 等信息。`Cargo.toml` 表达声明约束，`Cargo.lock` 记录精确结果，两者职责不同。

`version` 与 `git` 或 `path` 可同时出现：本地构建使用 Git/path 来源并核查其版本，发布到 registry 时使用 registry 版本约束；这不是两种来源任意回退。工作区统一依赖需在根 `[workspace.dependencies]` 声明，再由成员显式写 `workspace = true` 继承；成员身份本身不会激活该依赖。来源见 [依赖声明](https://doc.rust-lang.org/1.85.0/cargo/reference/specifying-dependencies.html#multiple-locations) 和 [工作区依赖](https://doc.rust-lang.org/1.85.0/cargo/reference/workspaces.html#the-dependencies-table)。

**例 4：依赖别名**

```toml
[dependencies]
serde_for_config = { package = "serde", version = "1" }
```

源码侧用 `serde_for_config` 作为依赖名，而发布身份仍为 `serde`。

**例 5：显式 Git 来源与同名本地成员**

```toml
[workspace]
members = ["apps/tool", "crates/parser"]

# apps/tool/Cargo.toml
[dependencies]
parser = { git = "https://example.org/parser.git", rev = "0123456789abcdef" }
```

即使 workspace 内也存在名为 `parser` 的成员，单凭名称相同并未声明依赖改指该成员。需要本地路径时应明确写 `path = "../../crates/parser"`；显式覆写可用根 `[patch.<source>]` 向被补丁的来源提供替代候选，其包名与版本须满足依赖和解析条件，并非与原已选版本字符串机械相等。此片段为来源关系示意，URL 与修订不是可直接下载的真实依赖。

**离线来源实验（Cargo 1.96.0）**：临时目录中建立 Git 仓库 `parser@0.1.0`，另建工作区 `app` 与本地 `parser@0.1.0`。`app` 以 `git = "file:///…/git-parser"` 加完整 `rev` 引用远端样式来源。运行 `cargo metadata --format-version 1`（全为本地文件，没有 registry 依赖）得到两个不同 package ID：本地成员 `source = null`，Git 包 `source = git+file:///…#<commit>`；`resolve.nodes` 中 `app` 的依赖指向后者。退出码 0，明确来源没有被同名同版本成员替换。该实验验证来源选择，不声称测试了 Rust 代码执行、网络认证或 Cargo 1.85.0 二进制。

**例 6：run 的产物歧义**

```toml
[[bin]]
name = "serve"
path = "src/serve.rs"

[[bin]]
name = "admin"
path = "src/admin.rs"
```

`cargo run --bin serve` 明确产物；不带选择时多个 bin 会造成歧义。设置 `[package] default-run = "serve"` 才明确默认项。若 workspace 同时有多个 package，也需先 `-p package-name` 或从成员目录运行。

### 构建脚本与依赖类别

`build.rs` 是 package 的构建脚本（可通过 manifest 的 `build` 字段指定或关闭自动检测），用于构建/链接 native code 等，并通过 Cargo 约定输出指令影响编译。它是构建过程的代码，不是声明式依赖图。`[dependencies]` 提供 package 本身使用的依赖；`[dev-dependencies]` 面向测试、examples 等开发用途；`[build-dependencies]` 只提供给构建脚本，构建脚本不能使用普通或 dev 依赖（它们尚未构建），构建依赖也不会自动成为 package 本身的依赖。声明数据与脚本、执行产物应分开理解。依据：[Build Scripts](https://doc.rust-lang.org/1.85.0/cargo/reference/build-scripts.html#build-dependencies)、[Development dependencies](https://doc.rust-lang.org/1.85.0/cargo/reference/specifying-dependencies.html#development-dependencies)。

## 可借鉴取舍（不是 Juice 决定）

- 将 package 身份、导入模块入口和可执行产物分成不同声明层；Cargo 的一个 package 同时有 library 与 bin，说明“不必一包只对应一种产物”是可行模型。
- 约定发现能减少常见配置，但需可单独关闭，并容许显式非约定路径；若 Juice 要求来源显式，可借鉴关闭隐式发现的清晰度，不必照搬 Cargo 的自动发现。
- workspace 是成员选择与共享状态（lock、输出目录）的组合。Cargo 的 `members`、`exclude`、`default-members` 将成员集合与命令默认选择分开，便于工作区保持独立决策；但 Juice 可选择不聚合构建图。
- 依赖来源与别名/身份分开，且 Git 解析结果锁到提交，可为可复现性提供参考；这不要求 Juice 接受 registry 或 Git 依赖。
- Cargo 的 `run` 不猜多个二进制中的“正确”一个，要求显式选择或声明默认值，避免基于名称、目录顺序推断执行对象。

## 不能直接映射到 Jai 的部分

Rust crate 是 Rust 编译器的编译单元和链接边界；Jai 的导入模块是 Jai 语言的导入机制，不能因 Cargo 把 library target 称为 crate，就推导 Jai 模块应拥有 crate 式生命周期、独立编译或链接语义。Cargo 的 edition、features、test harness、build.rs、平台 target、Rust package registry 均有 Rust 专属约定。Juice 的声明若只描述来源、模块入口和程序产物，可以借鉴边界拆分，不能直接搬用 Cargo manifest 的字段含义或将声明变成构建图。

## 人工待决问题

1. 已定一包可同时提供模块与程序；接下来决定模块基数、约定入口、显式覆盖与歧义错误。
2. 工作区成员清单、排除项和默认成员是否需要分别配置？从根运行 build/run/test 是否只处理所选包，还是聚合成员？
3. 多程序包执行时，是否强制显式 target 名，或允许 manifest 指定默认程序？
4. 依赖别名与实际包身份如何表达？Git/path 同名包是否始终来源显式，是否需要显式覆写语法？
5. 构建脚本和普通依赖是否属于声明层、运行时执行层，或二者均不支持？

## 未核实项

未检查 Cargo 源码或 Cargo 1.85.0 二进制；文档规则未逐条运行验证。Cargo 1.96.0 的本地 metadata 实验只补强同名成员与显式 Git 来源的关键结论；未测试网络 Git 认证、所有 branch/tag/rev 组合、更新锁文件流程或 `run` 的跨多个默认成员边界。未穷尽 target 自动发现的历史兼容细节，未深入 features 与 registry 发布策略。后续若需要某一边界作为 Juice 精确设计的依据，应按版本追加针对性核验，不把未测边界当作结论。

## 官方来源

1. [Cargo 1.85.0 — Cargo Targets](https://doc.rust-lang.org/1.85.0/cargo/reference/cargo-targets.html)：Library、Binaries、Examples、Tests、Target auto-discovery、配置字段。
2. [Cargo 1.85.0 — Workspaces](https://doc.rust-lang.org/1.85.0/cargo/reference/workspaces.html)：Root package、Virtual workspace、members/exclude、default-members、workspace package/dependency inheritance。
3. [Cargo 1.85.0 — Specifying Dependencies](https://doc.rust-lang.org/1.85.0/cargo/reference/specifying-dependencies.html)：Registry/Git/Path dependencies、renaming dependencies、multiple locations。
4. [Cargo 1.85.0 — Overriding Dependencies](https://doc.rust-lang.org/1.85.0/cargo/reference/overriding-dependencies.html)：`[patch]` 与 package identity 条件。
5. [Cargo 1.85.0 — Cargo Build](https://doc.rust-lang.org/1.85.0/cargo/commands/cargo-build.html)、[Cargo Run](https://doc.rust-lang.org/1.85.0/cargo/commands/cargo-run.html)、[Cargo Test](https://doc.rust-lang.org/1.85.0/cargo/commands/cargo-test.html)：默认 package 与产物选择。
6. [Cargo 1.85.0 — Build Scripts](https://doc.rust-lang.org/1.85.0/cargo/reference/build-scripts.html)：build script 与 build-dependencies。
7. [Cargo 1.85.0 — Cargo.toml vs Cargo.lock](https://doc.rust-lang.org/1.85.0/cargo/guide/cargo-toml-vs-cargo-lock.html)：版本约束与精确锁定分工。
8. [Rust 1.85.0 release announcement](https://blog.rust-lang.org/2025/02/20/Rust-1.85.0/)：官方发行日期。
