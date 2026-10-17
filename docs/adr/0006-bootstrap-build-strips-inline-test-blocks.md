# 0006: 自举构建以剥离视图为输入——build.jai 内嵌转译器纯函数

src 原文件内联 test block 后（[地图 0025](../issues/0025-spec-src-inline-test-blocks.md)），juice 自身有两类构建路径：Build command（`juice build`，闭包探测剥离，ADR 0004）与自举构建（仓库根 `build.jai` metaprogram 直接编译 src）。自举构建原先零转译、直编原文件，src 内联后必报错（test block 不是合法 Jai）。本 ADR 决定自举构建如何获得剥离能力。

**决定**：

1. **内嵌转译器**：`build.jai` metaprogram 以 `#load` 复用进程内转译器纯函数（src/transpile.jai，仅依赖 Basic/String，无 IO）。被 load 代码编译进 metaprogram 执行环境、不进入被构建程序；剥离视图作为构建输入，不直编原文件。票 0050/0052 后 #load 集扩大为 test-free 共享模块：src/transpile_front.jai（剥离前端）与 src/metaprogram.jai（Metaprogram generator）。
2. **入口与其他文件同样落盘（票 0052 修订，原「入口走虚拟源文本」重写）**：闭包含 test block 时，含入口的全部闭包视图落盘 `target/transpile/bootstrap/`（自举构建专属子目录，不与 Build command 的内容寻址缓存混用），in-package `#load` 重写为视图绝对路径（STRIP 已有机制，无新增转译规则）。bootstrap 经共享 Metaprogram generator 生成编译 metaprogram（`target/bootstrap-meta.jai`，与 Build command 同形状）后 spawn 子进程 jai 编译，入口视图经 `add_build_file` 编译——诊断精确文件+行号，原决定的 `add_build_string` 虚拟路径与行号偏移恒 +5 随之退役（机制实验：metaprogram `#run` 内 `run_command` spawn 子进程 jai 可行，退出码可判；`exit(1)` 退出码正确但会吞掉 metaprogram 自身的收集打印——票 0015 机制，失败路径的退出码与子进程错误输出仍完整）。
3. **与 Build command 同一契约**：自举构建与 Build command 共享同一转译器、同一视图排版规范（docs/transpiled-output-formatting.md）、同一 Metaprogram generator 与行号保真不变量；test-free 闭包仍原样直编（零转译零落盘）。机制事实见 [研究报告：Jai metaprogram 内加载转译器并喂视图的机制](../research/jai-metaprogram-view-feeding.md)。
4. **测试支撑代码不进闭包**：测试共享声明集中 `tests/test_support.jai`，不被入口 `#load` 引用——两条构建路径都不转译、不编译它；发布产物纯净无需新剥离规则（[0027 决议](../issues/0027-test-helper-organization-and-strip-boundary.md)）。

**Considered Options**: (a) 发布视图树（预生成剥离源码树、自举构建编译发布树）——否决：多一条生成步骤与第二个"源码真身"，且 bootstrap 鸡生蛋（无 juice 时谁生成视图树）；(b) src test-free 纪律（不允许 src 内联，测试留 tests/）——否决：与目的地（内联贴近实现）直接冲突；(c) 自举构建退役（bootstrap 冻结快照）——否决：快照腐烂，单一构建入口退化；(d) 维持手写骨架对称复制（票 0036 搁置的形态）——否决（票 0052）：骨架与哨兵约定靠注释互相承诺，且 +5 偏移是自举路径的常驻诊断税；生成 + 子进程与 Build command 同形状。

**Consequences**: 自举构建从此依赖转译器存在（与 Build command 同等义务）；`build.jai` 成为转译器、剥离前端与 Metaprogram generator 的共同消费方，其接口变更需同时照顾两条路径（bootstrap 侧以三路径验收兜底）。票 0052 后：bootstrap 无进程内拦截与消息循环，编译诊断经子进程输出透传（与 `juice build` 的诊断形态一致）；父 metaprogram 的打印由 jai 收集、正常结束时才刷出（🚀/✅ 行出现在编译输出之后）。

**修订（2026-10，用户拍板）**：第 4 条中测试共享声明的约定位置由 `src/test_support.jai` 改为 `tests/test_support.jai`（纯测试支撑代码不驻 src/；机制不变——不进两条构建路径）。

**修订（2026-10-14，票 0052，用户拍板）**：决定 2 重写为「入口与其他文件同样落盘 + 生成 metaprogram + 子进程」；决定 1 的 #load 集扩为共享剥离前端与生成器核心；Considered Options 增 (d)。

**修订（2026-10-18，[ADR 0008](0008-transpile-pipeline-contract.md)）**：决定 1 的 #load 集再增 src/transpile_plugin.jai（注册表驱动转译管线——插件接口、两内置插件与管线 runner；test-free 共享模块，其单元测试驻 tests/transpile_plugin_tests.jai）。
