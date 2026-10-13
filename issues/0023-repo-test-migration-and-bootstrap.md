---
title: 仓库存量测试迁移 + 自举
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: [0019-test-discovery-scan-and-exclusions.md, 0022-test-matrix-completion.md]
---

> 父票：[Spec: juice test 命令与 test block 单元测试](0013-spec-juice-test-command-and-test-block.md)

## What to build

Juice 自举（实施最后一环）：仓库补 BIN manifest（target 为自身入口）；存量断言式测试 1:1 迁入 test block——独立测试文件保留、就地转换（删 main 汇总、删旧 run_test 模式、删全部 `#load` 列表——test 模式全视图加载、顶层符号程序级可见），helper 过程与记录全局留在文件顶层；转译器测试代码同迁。`juice test` 于仓库根跑通全部存量测试（tests/data/ 与 modules/ 排除集生效）。

## Acceptance criteria

- [x] 仓库补 BIN manifest（target = 自身入口），`juice test` 于仓库根可运行
- [x] 存量测试逐条 1:1 迁移：断言语义不变、测试名沿用、全绿
- [x] 迁移后测试文件无 main / 无 run_test 汇总 / 无 `#load` 列表
- [x] `juice test` 于仓库根跑通全部存量测试（含转译器与 Testing 的测试）
- [x] 实现期验证项处理：编译期文件系统 IO（build 重校验门）验证可用性，不可用则 fake 化并记录
- [x] 排除集在自测场景生效（tests/data/ 负例 fixture 不进入 Juice 测试程序）

## 实现注记

- 编译期文件系统 IO 验证可用（重校验门与 seam 测试在编译期直跑真实文件系统），未 fake 化。
- 编译期执行环境实测可启动子进程（与 spec 0013 US 27 的「子进程不可用」声明不同）：Testing child 场景改为经 `juice test` 于 tests/data/testing-child/ 三个 fixture 包断言输出契约与退出码（fail 场景退出码断言 5 → 1，随新执行模型收敛）。
- build.jai 的 `#run` 会被测试程序加载执行；加末参数 first.jai 守卫跳过，直接 `jai build.jai` 不受影响。
- 旧测试设施（tests/build_test.jai 与各 main 汇总）已随迁移退役删除。
