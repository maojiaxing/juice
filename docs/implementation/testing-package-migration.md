# Testing 标准成员包迁移验收

## 已交付结构

```text
packages/testing/
├── package.jai             # name=testing；显式导出 Testing；无可执行产物
├── src/module.jai          # 唯一裸名实现，标准 Jai，无自测
└── tests/
    ├── module_tests.jai    # 外层行为验收
    ├── test_support.jai    # 成员专用子进程与坐标助手
    └── data/scenarios.jai  # 由子进程加载，排除于包测试扫描
```

Testing 拥有断言、失败状态、单个测试执行、结果汇总及诊断路径映射。转译、测试发现、测试运行器生成与命令编排留在 juice。外部 `../testing`、环境变量定位与 vendored 同步方案已废弃。

公开导入仍为 `#import "Testing"`，普通使用者不新增依赖声明；安装仍为可执行文件与相邻 `modules/`。`build.jai` 直接读取仓库内成员入口，逐字节发布为 `modules/Testing.jai`。旧 `packages/juice/testing.jai`、根包 Testing 定义源加载、`Testing_` 前缀、发布重命名 adapter 及无引用旧 fixtures 已删除。

公开过程的原形参名（包括 `args`、`loc`、`proc`）保留，以免破坏 Jai 命名实参；异构格式化实参沿用原有 `Any` interface，不是此次新增类型擦除。

## 接线缺陷与修正

迁移前最小复现：普通包显式导出 `Testing`，入口 `src/module.jai`；测试只通过生成 driver 的隐式导入使用它。旧工具既加载该入口又导入宿主 Testing，得到 `Procedure call matches 2 possible overloads`，退出 1。

修正：

1. 将生成 driver 的 `#import "Testing"` 计入既有模块入口去重；已导入入口不再由 driver 重复加载。
2. 从包声明的入口视图生成只包含 Testing 导入名的 shim，置于该次测试编译的外层命令行和内层 workspace 导入路径首位。
3. 保持其他模块相对搜索顺序；不依赖特殊源码 `modules/` 目录，不增加用户开关。
4. 声明入口没有可用视图时失败，不回退宿主旧副本。

`tests/testing_package_tests.jai` 通过真实 CLI 同时验证显式、隐式导入：成员源码独有标记可以读取；一次故意失败由同一 `finish` 汇总为 `0 passed, 1 failed` 且退出 1；入口缺失失败。修正后原最小复现退出 0。

## 验证记录

环境：Windows，本地 Jai 编译器；未验证其他平台。完整测试使用 `target/juice-testing-verify.exe` 副本，避免测试中重新构建 `target/juice.exe` 的文件锁。

| 验证 | 命令/范围 | 结果 |
| --- | --- | --- |
| 自举 | `jai build.jai` | exit 0 |
| 自托管构建 | 根包 `target/juice-testing-verify.exe build` | exit 0 |
| 成员声明构建验证 | 成员目录执行 `../../target/juice-testing-verify.exe build` | exit 0；无可执行产物，按普通包语义仅验证声明与依赖，不作为模块类型检查证据 |
| 原重复加载复现 | 新工具运行标准 Testing 包最小用例 | exit 0，1 passed / 0 failed；旧工具同用例 exit 1 |
| 成员独立自测 | 在 `packages/testing/` 执行 `../../target/juice-testing-verify.exe test` | exit 0，1 个综合行为自测通过 |
| 标准入口回归 | `target/juice-testing-verify.exe test testing_package_declared` | exit 0，1 passed / 0 failed |
| 完整工作区 | `target/juice-testing-verify.exe test --workspace` | exit 0，1412.4 秒 |
| 根包套件 | 上述工作区运行中的根包 | 668 passed / 0 failed |
| Testing 套件 | 上述工作区运行中的成员 | 1 passed / 0 failed |
| jaix 插件套件 | 上述工作区运行中的成员 | 17 passed / 0 failed |
| lint 插件套件 | 上述工作区运行中的成员 | 3 passed / 0 failed |
| 差异格式 | `git -c core.whitespace=cr-at-eol diff --check` | exit 0；仓库已有 CRLF 文件 |

成员的一个综合用例在独立编译子进程中验证连续完整输出：断言通过、默认与自定义失败文案、格式化实参、断言失败终止当前过程、后续测试继续、defer、提前返回、finish 返回与重置、映射路径及原始路径的精确行列。故意失败不污染外层套件。

根套件保留并通过发布恒等、空/缺失源码、失败无部分发布、无成员声明也可自举、debug/release 自举、安装摘要与可搬迁安装、真实消费者导入等验证。

第一次完整工作区运行因 540 秒时限中断，不计为通过。重跑使用实时日志与 1500 秒时限，完整退出 0；结束时无恢复备份残留，Testing 源与包声明均完整。

## 发布一致性与日志

验收结束时，`packages/testing/src/module.jai` 与 `target/modules/Testing.jai` 逐字节一致：

- 长度：2542 字节。
- SHA-256：`3ef4ac1c0ca0904869921c6418f1d47ea8b924fbb8aac47902cc1e613ca2162e`。

易失运行日志（clean 会清除；此文保留结果）：

- `target/evidence/testing-package-bootstrap.log`
- `target/evidence/testing-package-probe.log`
- `target/evidence/testing-package-member.log`
- `target/evidence/testing-package-regression.log`
- `target/evidence/testing-package-workspace.log`
- `target/evidence/testing-package-self-build.log`
- `target/evidence/testing-package-member-build.log`

本记录仅描述此次迁移验收，不改写其他 effort 的历史结果或扩大其范围。
