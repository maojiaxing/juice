# Zig 包描述、模块导出与构建编排分工

## 版本来源

查证日期：**2026-11-13**。当日[官方下载索引][index]列出的最新稳定版为 **0.17.1，发布于 2026-11-02**；其发布说明链接指向 [0.17.0 发布说明][release]。以下事实、API 和片段统一依据 **0.17.1 tag**，不混入 master。

实际读取了官方[发布源码包][archive]，SHA-256 与下载索引一致：`1e89bf06610b769a8c77676c6c8d54b093a0db60f4891f2f91014829012f0e24`；另读取下列对应 tag 原始源码，引用链接指向其行号。片段是接口说明，省略业务源码和外围声明，未编译运行。

## 查证事实及示例

### 包身份、版本和来源

`name` 是枚举字面量，也是 `zig fetch --save` 默认采用的依赖键；消费方可以改名。它与 `fingerprint` 共同标识包的持续身份。fingerprint 是 64 位整数，包含随机 ID 和名称校验码，区别于内容摘要；正常更新保留，仍在维护的上游被 fork 时应重新生成。[字段文档][fields]、[实现][identity]

`version` 必须能解析为 SemVer，但**不是依赖版本范围求解条件**：该版依赖项只解析 `url/path/hash/lazy`，抓取按具体来源和 hash 进行；版本会进入包快照标识字符串。模板仍把将来利用版本去重写为未来事项。因此不能类推 Cargo 的版本约束、求解与统一升级语义。[解析器][manifest]、[模板][zon]、[抓取与快照][fetch-hash]

`url` 是获取途径，`hash` 是指定快照的依据；同一内容可以换镜像。hash 按解包并应用 `paths` 后的文件集合计算，不等于压缩包校验和。`paths` 同时决定保留哪些文件，目录递归包含，空字符串表示整个构建根目录。[模板][zon]

`name/version/fingerprint/paths` 缺失会被正常解析路径报错；`dependencies` 可省略，`lazy` 默认 false。`minimum_zig_version` 校验 SemVer 格式，但该版文档明确说尚属建议信息。未知字段会被忽略，不能假定拼错字段必然报错。[解析器][manifest]、[字段文档][fields]

**片段 1：生产包的 zon 字段。** 以 `codec` 目录运行 `zig init` 的结果为底稿，保留与名称对应的工具生成 fingerprint；这里省略其数值。[模板][zon]

```zig
.{
    .name = .codec,
    .version = "1.2.0",
    // 此处保留 zig init 生成的 .fingerprint 字段。
    .minimum_zig_version = "0.17.1",
    .paths = .{ "build.zig", "build.zig.zon", "src", "LICENSE" },
}
```

本次核对的 manifest、Fetch 与 Maker 路径没有 Cargo.lock 式独立依赖求解结果文件；不能因此把 hash 泛称为锁文件。可复现来源依靠各级 zon 中的具体来源/hash、递归抓取与缓存，以及内容不符时拒绝使用。缺少远程 hash 的正常抓取会报错并给出应填值。本地 path 不计算内容 hash，不能据此保证本地修改后的内容相同；整个构建还可能依赖工具链、系统库或外部命令。[抓取校验][fetch-hash]、[本地路径][fetch-path]、[外部命令][run]

还有一处文档差异：字段文档仍链接 multihash，而该版 `Hash.init` 实际生成 `name-semver-hashplus`，后段编码 ID、大小和截断摘要。报告不把旧格式说明当作当前编码规范。[字段文档][fields]、[编码实现][hash-format]

### 包、模块与产物

包不是单一模块或程序。`addModule` 注册可供依赖方选择的公开模块，`createModule` 创建私有模块；模块包含源文件和编译选项，并不自动产生二进制库。`addLibrary` 创建库编译步骤，支持 static/dynamic；`addExecutable` 创建程序步骤。[模块 API][modules]、[产物 API][artifacts]

**片段 2：一个包同时提供模块、程序和静态库。** `b` 是 `*std.Build`，其余代码位于 `build` 内；业务入口文件需另行提供。改为 `.dynamic` 可声明动态库。[官方初始化示例][init]、[产物 API][artifacts]

```zig
const target = b.standardTargetOptions(.{});
const optimize = b.standardOptimizeOption(.{});
const core = b.addModule("core", .{
    .root_source_file = b.path("src/root.zig"),
    .target = target, .optimize = optimize,
});
const program = b.addExecutable(.{
    .name = "codec-tool",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target, .optimize = optimize,
        .imports = &.{.{ .name = "codec", .module = core }},
    }),
});
b.installArtifact(program);
const library = b.addLibrary(.{
    .name = "codec-c", .linkage = .static,
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target, .optimize = optimize,
    }),
});
b.installArtifact(library);
```

消费方先按依赖键得到包实例，再按公开模块名或产物名选择。`dependency.module` 查询模块表；`dependency.artifact` 搜索挂到安装步骤的编译产物，找不到或同名歧义会报错。仅创建编译步骤不等于通过该接口导出。依赖键、模块导出名、源码 import 名、产物名属于不同命名层。[选择实现][exports]

**片段 3：来源与依赖别名。** 这是消费方 zon 的局部字段；远程 URL/hash 是明确标出的占位符，必须替换为实际来源及 `zig fetch` 输出，不能直接运行。[模板][zon]、[依赖校验][manifest]

```zig
.dependencies = .{
    .syntax_vendor = .{ .path = "../codec" },
    .generator = .{
        .url = "https://example.invalid/generator-1.0.0.tar.gz",
        .hash = "<zig fetch 返回的完整包 hash>",
        .lazy = true,
    },
},
```

path 相对声明包的构建根目录，不能同时指定 URL；path 依赖带 hash 会被拒绝。远程包内部的相对依赖也不能逃出抓取目录。[本地路径实现][fetch-path]

**片段 4：选择与重命名。** `application` 是消费方的编译产物。源码用 `@import("parser")`，不必写包名 `codec`、依赖键 `syntax_vendor` 或模块导出名 `core`。[选择实现][exports]、[导入 API][imports]

```zig
const vendor = b.dependency("syntax_vendor", .{
    .target = target, .optimize = optimize,
});
application.root_module.addImport("parser", vendor.module("core"));
application.root_module.linkLibrary(vendor.artifact("codec-c"));
const tool = vendor.artifact("codec-tool");
```

### 配置、惰性依赖与执行

`build.zig.zon` 是包元数据；`build.zig` 是执行配置逻辑、构造构建步骤及依赖关系的 Zig 程序。配置函数运行不等于执行编译步骤；官方模板明确说明后续由 runner 执行图。配置阶段仍是代码，不能理解成纯数据声明。[字段文档][fields]、[初始化模板][init]

`target` 在这些 API 中指编译平台，不指可执行产物。标准选项默认本机平台；普通默认优化为 `.debug`。选项需要显式接到模块并传入依赖实例，不能假定平台、优化或自定义值自动继承。[平台与优化 API][options]、[初始化模板][init]

**片段 5：按配置启用惰性工具依赖。** 放入返回 `!void` 的 `build` 函数。`b.option` 定义消费方开关；传给依赖的选项仍须由依赖支持。[选项 API][custom]、[惰性 API][lazy]

```zig
if (b.option(bool, "generate", "Generate parser source") orelse false) {
    const generator = try b.dependencyLazy("generator", .{
        .target = b.graph.host, .optimize = .safe,
    });
    _ = generator; // 可接下面的生成步骤。
}
```

0.17.1 推荐 `dependencyLazy`；旧 `lazyDependency` 已标为弃用。所需包尚未抓取时，它返回 `LazyDependencyNeeded`，调用者传播错误；工具链抓取后重编译并重跑配置，随后才进入执行阶段。lazy 是抓取/配置协议，不是自动运行时延迟加载。[惰性 API][lazy]

**片段 6：不能只用产物清单表达的生成流程。** 接在上例分支内，假定依赖导出 `generate-parser`，且程序接受输出文件参数；生成模块还须被实际使用。使用该版推荐的 `addOutputFileArg2`。[运行步骤][run]、[输出路径 API][output]

```zig
const generation = b.addRunArtifact(generator.artifact("generate-parser"));
const generated = generation.addOutputFileArg2("parser.zig", .{});
_ = b.addModule("generated-parser", .{
    .root_source_file = generated, .target = target,
});
```

## 可借鉴取舍（非 Juice 决定）

可借鉴的是分清包身份、源码来源、内容快照、模块导出和程序产物，并允许消费方给依赖及导入分别命名。同包提供模块与程序也有直接官方示例。`paths` 把发布内容边界显式化，但需要处理漏文件的成本；本地 path 方便协作，却与远程快照具有不同复现保证。

这些事实不决定 Jai `package.jai` 的具体结构，也不要求引入 fingerprint、ZON 或 Zig 的 API 形状。

## 不复制任务图时不能直接映射的部分

`artifact` 依赖安装步骤发现产物，`LazyPath` 可表示尚未生成的文件，生成器与消费编译之间依赖执行顺序和缓存；惰性依赖还需要配置重试。因此不能把这些对象原样塞进静态包声明。必须另行决定支持哪些有限产物、生成能力由谁编排。

在本次检查的 0.17.1 zon 字段文档、解析器、Build API 与初始化模板范围内，未发现 Cargo workspace 的成员、继承和统一依赖锁定模型的直接对应。相对 path 能连接多个包，根构建脚本也能编排它们，但这不足以推出 workspace 等价物。[字段文档][fields]、[解析器][manifest]、[Build API][build]

## 人工待决问题

- 哪些名称是稳定公共接口，哪些只属于消费方本地命名？
- 源码模块、二进制库与程序的导出清单是否分别表达？
- 远程内容固定、本地可变目录与工作区成员关系如何各自描述？
- 平台、优化和包参数允许怎样传播；惰性依赖是否值得引入配置重试？
- 生成源码和工具程序由外部构建编排承担多少职责？

## 未核实项

未运行这些组合片段，未验证特定平台的动态链接及生成器协议；未调查第三方 workspace 工具、registry、开发版或历史版差异。没有把源码固定等同于逐字节可复现构建，也没有据本次负面检索断言 Zig 生态永远不存在工作区能力。

[index]: https://ziglang.org/download/index.json
[release]: https://ziglang.org/download/0.17.0/release-notes.html
[archive]: https://ziglang.org/download/0.17.1/zig-0.17.1.tar.xz
[fields]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/doc/build.zig.zon.md#L11-L120
[identity]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/compiler/Maker/Package.zig#L7-L26
[hash-format]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/compiler/Maker/Package.zig#L90-L115
[manifest]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/compiler/Maker/Package/Manifest.zig#L156-L334
[zon]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/init/build.zig.zon#L2-L78
[fetch-hash]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/compiler/Maker/Fetch.zig#L820-L858
[fetch-path]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/compiler/Maker/Fetch.zig#L533-L573
[init]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/init/build.zig#L3-L90
[modules]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/std/Build.zig#L701-L724
[artifacts]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/std/Build.zig#L559-L651
[exports]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/std/Build.zig#L1853-L1884
[imports]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/std/Build/Module.zig#L306-L321
[options]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/std/Build.zig#L1189-L1234
[custom]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/std/Build.zig#L966-L985
[lazy]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/std/Build.zig#L1952-L1984
[run]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/std/Build.zig#L726-L771
[output]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/std/Build/Step/Run.zig#L296-L336
[build]: https://codeberg.org/ziglang/zig/src/tag/0.17.1/lib/std/Build.zig
