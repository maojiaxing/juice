---
title: Juice 自身测试迁移步骤与文件组织
status: closed
labels: [wayfinder:grilling]
assignee: maojiaxing
blocked-by: [0011-transpiled-output-formatting-and-golden.md]
---

## Question

Juice 仓库自身测试迁移到 test block 体系（目的地 spec「实施顺序」的最后一环；从地图 Not yet specified 毕业）：

- 迁移范围：现有 `tests/test_*.jai`（commands / dispatcher / workspace / target 断言式测试）哪些迁、哪些留（compile seam 录制适配器类集成测试是否天然属于 test block 形态）。
- 文件组织：迁移后测试放哪（内嵌于 src 各文件 vs 独立测试文件）、`tests/` 目录去留、`tests/data`（golden fixture）与 golden 基线的关系。
- 自举路径：转译器自身的测试（golden + 负例 + 编译运行矩阵）与仓库存量测试的关系；实施顺序上先用旧设施开发 test 体系、最后一步迁移自身（鸡生蛋顺序如何写成可执行步骤）。
- 退役时机：旧测试设施（如 `tests/build_test.jai`）何时删除。

## Resolution

（2026-10-13 grilling 一轮 7 问，票主逐条全按推荐拍板；本票是目的地「实施顺序」最后一环，关闭后地图完成）

1. **Juice 自身被测形态 = BIN package.jai**：迁移步骤中补 `package.jai`（`TARGET=juice|src/main.jai`）——诚实反映 Juice 是 CLI 工具；test 不消费 artifact plan（0010 决议），BIN 可测；顺带获得 `juice build` 自举。否决 LIB + 伪造 module 入口（不诚实）、否决无 manifest 测试模式（与「discovery without package stays empty」冲突，模型改动）。
2. **test discovery 排除集修订**：增加「仅排除 package root 的 `tests/data/` 与 `modules/`」——`tests/data/` 是 fixture 约定目录（转译负例含非法测试语法，进测试程序即破坏转译），`modules/` 是模块目录（`#import` 源而非测试源，入扫描只是冗余视图）。仅 root 一级，与 `target/` 同先例。已附 [测试发现范围规则](0003-test-discovery-scope.md) 勘误并更新 CONTEXT.md Test discovery 词条。
3. **迁移范围 = 全部 53 个现有测试，1:1 语义迁移，单轨**：录制适配器类（compile/launch/delete/fetch seam 注入）与 test block 天然相容——seam 是生产面（IMPLEMENTATION.md Test seams），测试只是调用方；test block 顶层可见性（0004 决议 3）下记录全局与适配器平移无摩擦。实现期验证项：编译期执行下的文件系统 IO（build 重校验门走真实 fs 检查）——不可用则退化为注入 fake 的路径检查。
4. **文件组织 = 独立测试文件保留 tests/**：`test_*.jai` 就地转 test block——删 `main`、删 `run_test` 汇总（Testing 收口）、删全部 `#load` 列表（test 模式 driver 全视图加载、顶层符号程序级可见，独立文件零成本拿到被测代码）；`#import` 保留；helper 过程与记录全局留在文件顶层。`tests/data/` 不动（既有 fixture + 0011 的 transpile 三矩阵）。
5. **自举顺序（可执行步骤）**：
   1. **转译器库 + 其测试先经旧设施**：实现转译器纯函数，golden/negative/run 三矩阵 fixture（0011 §4）配测试代码，经旧 harness 编译运行；旧 `build_test.jai` 参数化为循环编译测试程序清单（`test_dispatcher` + 新增 `test_transpile`），不复制 harness 文件。
   2. **`juice test` 命令端到端**：test 命令、Testing 模块、first.jai/driver 生成落地，用 fixture 包（`tests/data/transpile/run/`、`bin-package` 等）验证。
   3. **迁移**：补 package.jai（决议 1）、`tests/*.jai` 转 test block（决议 4）、转译器测试代码转 test block。
   4. **退役**（决议 6）。开发循环自 3 起为 `jai build.jai` → `juice test`。
6. **退役时机 = 迁移全绿即删、同提交单轨**：删 `build_test.jai`、`bin/` 测试 exe、旧 `run_test` 模式；1:1 语义转换（同一断言集）无需观察期，旧设施由 git 历史保留。
7. **迁移计划落点 = 本票 Resolution 即计划**：地图 Decisions so far 索引之，不另立文档（SUMMARY.md 是历史性总结非活文档；再立实施文档与地图重复）。

影响：0003 附勘误；CONTEXT.md Test discovery 词条当场更新；无新票。全部 11 张决策票至此关闭，地图完成——决策集齐备，可开工实施。
