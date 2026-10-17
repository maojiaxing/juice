# 0007: jaix 前置转译——可选、子进程、通用扩展

jaix 是独立于 juice 的通用语法转译库（spec §1「绿色田野独立库」：零 juice 代码依赖、juice 调用 jaix、juice 自身代码不动），提供 test block 之外的扩展语法（try/catch）。juice 自身的转译器只服务 test block，是编译路径上的**义务前置**（[ADR 0004](0004-transpile-baked-into-juice.md)：进程内库、test-only、构建含测试语法的包不能要求用户手工剥离）。spec 055 把 jaix 接为 juice 的**可选前置步骤**：package 声明 jaix 标记 → build/test 前置逐文件 spawn `jaix transpile` → 镜像 `target/jaix/` → 编译镜像视图。这是 ADR 0004 Considered Option (c)「将来做通用转译器再抽出」的兑现面：转译器不在 juice 进程内、不为 test block 服务，是外部通用转译器的可选接线。

**决定**：

1. **可选前置**：package 的 jaix 标记（config 路径 + 可选 exe）缺席 = 零行为变化——既有包、既有转译路径、既有测试零影响。与 ADR 0004 的义务前置相对：test block 是 juice 已定的合法形态（含 test 的源码交 jai 必报错，转译是义务）；jaix 扩展语法不是 juice 的语言特性，启用是包作者的选择，构建不替包作者做此决定。标记在但零 effective target（如 LIB 包）时，build 的零 target 早退先于前置：不跑前置、照常成功「无构建目标」——前置随编译面存在（早退语义不创建 target/，跑前置会违反之）；test 无此门——测试程序编译为全包面、无 target 门（LIB 包零 target 依然可测），且转译循环读镜像要求镜像先存在：pre-step 无条件先跑、随后「No tests found」照常成功。build 与 test 的非对称语义各随其编译面（059 偏差 5 据此订正）。
2. **子进程编排**：逐文件 spawn `jaix transpile`（全绝对路径、stderr 透传、任一非 0 = 前置失败 = command 失败），非进程内库。与 ADR 0004 决定 3 的理由相反：jaix 独立分发、版本与 juice 解耦，进程内并入会固化版本耦合；jaix 的 LIB 包形态已支持嵌入（spec §12），juice 选子进程是分发与边界面，不是能力面。子进程成本按 demo 文件数接受（无磁盘缓存——v1 defer，055 决定 3）。
3. **镜像视图 = 编译输入**：产物落 `target/jaix/`（ADR 0003 统一 target 目录惯例），包相对结构镜像，sidecar `.map` 随落（v1 不消费）；未触碰文件视图 = 原文逐字节（往返恒等），#load 链在镜像内自然解析（零路径改写）。接线点 = 编译入口选择面（marker 在 → build 入口 = 镜像内入口视图；test 的镜像文件 abs_path 改指镜像视图），compile_artifact_plan 零改动。
4. **扫描规则 = test 发现同族**：点前缀任意深度/非 .jai/根 package.jai/root 级 target//workspace member 子树排除（target/ 排除仅 root 级——嵌套 target/（如 src/target/）照常入扫，实现与扫描矩阵一致、与 test 发现同族），加两处 jaix 特有排除——marker 的 config 文件（jaix 编译期输入而非转译输入）与含 juice test block 的文件（双重处理排除：jaix 无 test block 插件时无法解析，test block 文件保持 juice 原路径）。juice 自身 test block 机制照常：混合包中 test block 文件走原文 EXPAND/STRIP，test-free 文件走镜像视图，两层视图（行保真断点 = 文档化限制）。
5. **边界**：标记作用面 = root package（被 build/test 的包）；成员/依赖的标记视图、磁盘缓存、.map 消费方、批量 CLI 留未来（055 Out of Scope——0049 同族面）。

**Considered Options**: (a) jaix 库进程内嵌入（ADR 0004 同款）——否决：版本耦合与分发耦合，且 juice 已有自己的转译路径，两个转译器同驻进程内徒增边界模糊；(b) jaix 替代 juice 自身转译器（test block 也走 jaix）——否决：test block 是 juice 的语言特性，其转译是义务前置（ADR 0004），test 面契约（发现/EXPAND/报告/path_mapping）不容外部工具接管；双重处理由「标记配置不用 jaix test block 插件」排除（055 US 18）；(c) 批量 CLI 单次 spawn 转译全包——否决：049 已锁逐文件循环（demo 文件数小、诊断定位直白），批量面留未来。

**Consequences**: 含 jaix 标记的包依赖 PATH 上的 jaix 可执行文件（缺 exe = 清晰错误，环境问题直接定位）；jaix 的 CLI driver 文件落 spawn 时 CWD（049 决定 12）——包根被连续 build 时会被下一轮扫描误收（demo 两步脚本以步骤间清理规避；产品级排除面留未来票）；镜像随 target/ 清理、每构建全覆写（v1 无缓存、无增量）；混合文件（test block + try/catch 同文件）不入镜像（058 偏差 1(b)）——两层视图的行保真断点与跨界 #load 限制随 058/059 文档化。
