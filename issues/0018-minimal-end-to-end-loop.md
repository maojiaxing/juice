---
title: 最小端到端环路（walking skeleton）
status: closed
labels: [ready-for-agent]
assignee:
blocked-by: [0016-transpiler-core-pure-function.md, 0017-testing-assertion-module.md]
---

> 父票：[Spec: juice test 命令与 test block 单元测试](0013-spec-juice-test-command-and-test-block.md)

## What to build

第一颗贯穿全程的 tracer bullet：`juice test` 在**固定 fixture 包**上端到端跑通——转译 → driver 生成 → metaprogram 入口生成 → jai 编译期执行 → 报告与退出码。无缓存落盘（产物临时目录或内存直传）、无发现扫描（显式文件清单）。driver 按 [排版规范 §2](../docs/transpiled-output-formatting.md) 四参数化点生成（视图清单字典序、映射表 `#run` 块首行注入 `Testing.path_mapping`、pattern 过滤后的测试清单、`if finish() != 0 assert(false)` 收口）；metaprogram 按规范 §3（NO_OUTPUT、`import_path` 注入 Testing、`add_build_file` driver）。test 命令走编排层注入式 seam（默认真实现、测试注入假实现，与既有 compile seam 同构）；juice 侧输出 `[juice Test]` 阶段行，测试输出原样透传。

## Acceptance criteria

- [x] `juice test` 于固定 fixture 包：含内嵌与独立测试文件的包，测试经编译期执行全部运行
- [x] 输出含 `[juice Test]` 阶段行、每测试 `[test] <报告名>` 开始行、`N passed, M failed` 汇总
- [x] 失败退出码 1、全过 0；失败行 `path:line,col: 消息` 指回原文件坐标（映射表改写路径生效）
- [x] `juice test <pattern>` 过滤命中测试（大小写敏感子串、匹配最终报告名含匿名路径名）；零命中成功退出并说明
- [x] 编排 seam 可注入：测试注入假实现验证转译步骤被调用、假产物被编译
- [x] 零测试包成功退出 + 说明、跳过 driver 编译
