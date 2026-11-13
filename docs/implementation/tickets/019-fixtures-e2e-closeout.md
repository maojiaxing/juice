---
id: 019
title: fixture E2E 家族 + 收口（关闭 spec 003）
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [018]
blocks: []
---

> 父 spec：`003-spec-test-note-discovery.md`（US 20 条 + 决定 1-10 + Testing Decisions 三接缝 + 完成定义）。上游规格：`docs/spec.md` §7。

# 019: fixture E2E 家族 + 收口（关闭 spec 003）

**What to build:** 零产品代码改动（测试侧重收口票，014 同款）——**fixture 全家族落盘 + E2E 矩阵**：test-fixture（手写 `@test` 包：发现 + 执行 + 排序 + `juice_test_N` 编号断言）、test-empty（零收集短路 "No tests found" 逐字节）、test-fail（失败继续 + run/finish 汇总退出码）、pattern 面（收集后过滤断言）；**旧 juice 不变式复核**（debug+release 4/4）；**spec 003 收口**：US 20 条全兑现映射 + 决定 1-10 直落 + 偏差清单随链记录 + 003 票内写 `## Resolution` + `status: closed` + map Decisions so far 追加一行（map 行归主会话）→ **1b 闭环 → 下一步 = 1c 新 spec（004，/to-spec）**。

**Blocked by:** 018（收口需复核 test 命令全链）

**Status:** closed

- [x] fixture 全家族落盘（test-fixture/test-empty/test-fail/pattern）
- [x] E2E 矩阵全绿（发现/执行/排序/编号/短路/汇总退出码逐字节）
- [x] 旧 juice 不变式复核：debug+release build/test 于 otter 根零特判全绿
- [x] spec 003 收口：US 20 映射 + 决定直落 + 偏差清单
- [x] 003 票 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**（零产品代码改动；新建 fixture 1 文件，改写 2 个 fixture/测试文件 + 2 个 spec/票文档，spec.md 四处执行级订正）：

- **fixture 全家族盘点**（对照 spec 003 Testing Decisions 的 fixture 清单）：test-fixture（手写 @test ×3 包——发现 + 执行 + 排序 + 计数断言，017）、test-fail（失败继续 + 汇总退出码 + 映射坐标，017）、pattern 面（收集后过滤/零命中 E2E，018）已全量落盘——**缺口 = test-empty（零收集短路逐字节）与编号/pattern 深化面**：test-empty 此前为零文件 scratch（018 E2E 临时 build_seam_write 包），无静态 fixture；test-fixture 无 `juice_test_N` 面（数值感知排序 + 编号基 1 零 E2E 覆盖）；pattern 子串大小写敏感面（纯函数矩阵有、真链面无）。
- **补缺：test-empty 静态 fixture 化**（`tests/data/test-empty/package.jai`）：仅 manifest 无任何 .jai 源文件——零文件收集 → 命令层真短路（跳过编译，t4 语义）。E2E 块改指静态 fixture（scratch 退役）："No tests found." 逐字节 + target/test/ 未创建 + target/ 会话产物 defer 清除。
- **test-fixture 编号面深化**（`src/tests_a.jai` 追加 `juice_test_10`/`juice_test_2` @test 过程，**声明序故意反数值序**）：E2E 断言数值感知排序（juice_test_2 先于 juice_test_10 运行——普通字典序会反过来）+ 编号基 1 钉生成产品（真命令产出的 target/test/first.jai 嵌 `collect_test_entries(..., 1)`；1b 显示名 = 过程名（017 偏差 5），编号不经输出可见，产品面是唯一真链可观察点）。
- **pattern 面 E2E ×2**（tests/test_command_tests.jai 追加）：大小写敏感（"ALPHA" → "No tests matched 'ALPHA'." exit 0）+ 子串语义（"juice_test_1" 只命中 juice_test_10——子串非前缀解析，1 passed 且负断言守其他测试）。**不重复已覆盖面**：018 已有 E2E ×6（发现执行/过滤/零命中/失败续跑/双短路）保持零改动语义；metaprogram 级 fixture E2E 块随新 fixture 更新计数（3 → 5）+ 排序断言（生成器直驱面与命令面两条链各自钉住）。
- **旧 juice 不变式复核**（验证前清 otter/target/transpile）：debug+release 各 `juice build`/`juice test` 于 otter 根零特判全绿 4/4（exit 0 + "Found 238 tests"；旧 juice 对无 modules/ 包根的 import dir 提示 = 无害通用行为；"expect failed" 行 = module_tests 子进程对拍场景的预期失败输出，测试锁字节）。
- **spec 003 收口**（`003-spec-test-note-discovery.md`）：`## Resolution` 落笔——US 20 条全兑现映射表 + 决定 1-10 直落对照（偏差指认：决定 2 切线 B 的 Testing 面 prefixed 形状经 016 spike 成形；决定 6 单编译约束下零入口短路 = 打印不注入的 1b 等价形）+ 链 015-018 偏差汇总清单（22 项一览 + 归属：全部有意设计决定，无遗留缺陷）+ 完成定义复核（三接缝 + 出范围面）；frontmatter `status: closed`；Further Notes「已拆分」→「已闭环」。下一步 = 1c 新 spec（004，/to-spec）。
- **spec.md 执行级订正折回**（014 同款纪律，「执行级订正」风格并入对应节，保持决策即规格）：§4.6 test 序（"test 序见 §7" → t1-t12 的 1b 子集全序列 + 无转译层归属）；§7.2 追加产品落 target/test/ + bootstrap 源面推导（exe 相对 ../src，阶段 2 切 import 发布面，005 切换点）；§7.3 重写为执行级订正（零入口双短路分层 + pattern 子串大小写敏感 + 编号基 1）；§9.5 追加 Testing 面 prefixed 形状（005 剥前缀转换承接裸名兼容）。

**验证矩阵**：

| 步骤 | 结果 |
| --- | --- |
| `jai build.jai`（旧 juice debug） | 成功 |
| 清 otter/target/transpile → `juice.exe build` + `test` 于 otter 根（debug） | exit 0，**Found 238 tests** 全绿（236 基线 + pattern 面 E2E 2） |
| `jai build.jai - release`（旧 juice release） | 成功 |
| 清 otter/target/transpile → `juice.exe build` + `test`（release） | exit 0，**Found 238 tests** 全绿 |

238 = 018 收口的 236 + 019 新 E2E 2 块（pattern 大小写敏感 + juice_test_N 子串面）；fixture 树零污染（test-fixture/test-fail/test-empty 无 target/ 残留，scan-fixture/target/h.jai = 静态 fixture 内容非残留）。

**偏差清单**：

1. **编号基 1 的 E2E 面 = 钉生成产品**：1b 显示名 = 过程名（017 偏差 5），编号不经输出可见——真链唯一可观察点 = 真命令产出的 target/test/first.jai 嵌 `collect_test_entries(..., 1)`；纯函数面（number_tests 续号）已有 in-process 矩阵（016/018），E2E 只补真链面。
2. **test-fixture 编号面 = 手写 juice_test_N 名**（非 EXPAND 产物）：切线 A 下 fixture 必须手写——与 1c EXPAND 产物同形（同前缀命名），发现机制零区别接收（US 7 的 1b 落实面）；声明序故意反数值序以钉排序。
3. **零产品代码改动**：全部工作 = fixture + 测试块 + 文档收口（014 同款收口姿态）。

**测试组织**：src 实现模块全部 test-free（bootstrap #load 集纪律，未触碰）；新 E2E 块驻 tests/test_command_tests.jai（test 命令面的既有 E2E 节扩展）。移交面：阶段 2 发布落位后 ensure_bootstrap_modules 退役 + test 命令切 import 发布面（005 复核面）；1c（004）接手 EXPAND 转译/lifecycle 接线/Testing 模块编译视图特例。
