# 0006: 自举构建以剥离视图为输入——build.jai 内嵌转译器纯函数

src 原文件内联 test block 后（[地图 0025](../issues/0025-spec-src-inline-test-blocks.md)），juice 自身有两类构建路径：Build command（`juice build`，闭包探测剥离，ADR 0004）与自举构建（仓库根 `build.jai` metaprogram 直接编译 src）。自举构建原先零转译、直编原文件，src 内联后必报错（test block 不是合法 Jai）。本 ADR 决定自举构建如何获得剥离能力。

**决定**：

1. **内嵌转译器**：`build.jai` metaprogram 以 `#load` 复用进程内转译器纯函数（src/transpile.jai，仅依赖 Basic/String，无 IO）。被 load 代码编译进 metaprogram 执行环境、不进入被构建程序；剥离视图作为构建输入，不直编原文件。
2. **入口走虚拟源文本**：入口文件的 STRIP 视图经 `add_build_string` 喂入编译器（虚拟路径，行号偏移恒 +5、列号精确，ADR 0005 映射保持）；闭包其余文件的视图落盘、in-package `#load` 重写为视图绝对路径（STRIP 已有机制，无新增转译规则）。插入点在 set_build_options 之后、compiler_begin_intercept 之前，消息循环不变。
3. **与 Build command 同一契约**：自举构建与 Build command 共享同一转译器、同一视图排版规范（docs/transpiled-output-formatting.md）与行号保真不变量；test-free 闭包仍原样直编。机制事实见 [研究报告：Jai metaprogram 内加载转译器并喂视图的机制](../research/jai-metaprogram-view-feeding.md)。
4. **测试支撑代码不进闭包**：测试共享声明集中 `src/test_support.jai`，不被入口 `#load` 引用——两条构建路径都不转译、不编译它；发布产物纯净无需新剥离规则（[0027 决议](../issues/0027-test-helper-organization-and-strip-boundary.md)）。

**Considered Options**: (a) 发布视图树（预生成剥离源码树、自举构建编译发布树）——否决：多一条生成步骤与第二个"源码真身"，且 bootstrap 鸡生蛋（无 juice 时谁生成视图树）；(b) src test-free 纪律（不允许 src 内联，测试留 tests/）——否决：与目的地（内联贴近实现）直接冲突；(c) 自举构建退役（bootstrap 冻结快照）——否决：快照腐烂，单一构建入口退化。

**Consequences**: 自举构建从此依赖转译器存在（与 Build command 同等义务）；`build.jai` 成为转译器的第二个消费方，转译器接口变更需同时照顾两条路径；入口视图的虚拟路径诊断需减固定行号偏移还原原文件坐标（实施时由测试覆盖）。
