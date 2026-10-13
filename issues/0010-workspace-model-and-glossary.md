---
title: workspace 模型与词汇修订
status: closed
labels: [wayfinder:grilling]
assignee: maojiaxing
blocked-by: [0003-test-discovery-scope.md, 0007-test-build-organization.md]
---

## Question

test 进入 workspace 模型后的 CONTEXT.md 词汇与关系（本票是收口票，前置票定案后执行）：

- 新词条：Test command（前置 prepare-workspace；消费 workspace discovery 还是 prepared workspace——LIB 无 target 时 test 拿到什么状态）、Test block、Test discovery（与 workspace discovery 的关系）、Test runner（是 Artifact 吗？——已答：无 runner exe，全部生成物在 `target/transpile/`）。
- 新词条（0008 定案新增）：Target directory（**取代 Result directory 词条**：`target/` 统一构建目录，与 Target declaration 的撞词注记）、Transpile（转译：build 探测剥离 / test 展开）、剥离视图 / 测试视图（build view 与 test view 的区分与内容寻址缓存）。
- 修订词条：Build / Run / Prepared workspace / Artifact / Result directory 中与新机制冲突的句子；0008 扩大范围——Local dependency directory（`.packages` → `target/packages/`）、Clean（删 root 与 member 的 `target/` 整目录）。
- Relationships 段新增行。
- 判断 LIB 可测带来的模型变化是否值得 ADR（参考既有 [ADR 0003](../docs/adr/0003-unified-target-directory.md)、[ADR 0004](../docs/adr/0004-transpile-baked-into-juice.md)，避免重复）。

> 补充输入（2026-10-13，[诊断与位置映射](0009-diagnostics-and-location-mapping.md) 决议后）：词汇候选——Test view 词条写明行号保真承诺及边界（逐字区列零偏移，编辑行不承诺）；「转译期诊断精确引用原文件、产物编译错误人工对照缓存前缀」边界句并入 Test view 或 Transpile 词条；不单设「位置映射」词条（内部机制，非命令语言词汇）。

## Resolution

（2026-10-13 grilling 两轮 7 问，票主逐条按推荐拍板；决议已当场落地 CONTEXT.md）

1. **test 与 workspace 模型 = 复用 prepared workspace，不造新状态**：Test 的 prerequisite 是 prepare-workspace，消费 prepared workspace 但不消费 artifact plan；artifact plan 为空或未被消费不妨碍 prepared workspace 成立，LIB package 无 effective target 时仍可测（Prepared workspace 词条补句，Package type 词条 LIB 半句同步）。否决新造「testable workspace」与从 prepared workspace 拆出 artifact plan 两种改法——现有 discovery/preparation/消费者三层词汇已够用。
2. **词条命名与切分**：新增 8 条——Test command（Command language，Clean 之后）、Test block / Test discovery / Testing / Test driver（新节「Test language」，与 Command/Workspace language 并列）、Target directory / Transpile / View（Workspace language；Transpile 与 View 因 build 也消费而不进 Test language）。定名裁决：**Test driver** 否决 Test runner（0007 已毙运行期 runner 形态，防误导；_Avoid_ 行显式排除）；**View 一条**内述剥离/测试两模式，不按模式拆两条；`first.jai` 文件名与 `juice_test_N`、占位注释等不进词条（实现细节，归 0011/ADR）。
3. **CONTEXT.md 当场落地**：对齐 ADR 0003/0004 决议即落库先例；词汇暂时超前于实现（代码仍 `result/`），由实施收尾抹平。
4. **LIB 可测不写 ADR**：可逆（收紧为 BIN-only 随时可加）、自解释（Test command 词条即答案）、无真权衡存档价值；机制层已由 ADR 0003/0004 覆盖。
5. **落地清单**（CONTEXT.md 实际变更）：
   - 新增词条 8：Test、Test block、Test discovery、Testing、Test driver、Target directory、Transpile、View（含各 _Avoid_ 行）。
   - 修订 7 处：首部描述句（+测试语言）；Build（入口闭包探测转译句 + 结果目录→target directory 措辞）；Clean（递归删 target directory 整目录，本地依赖链接句删除）；Prepared workspace（artifact plan 句）；Artifact（「测试生成物不是 artifact」句）；Local dependency directory（`target/packages/` 位置、清理句归 Clean）；Package type（LIB 可被 Test 测试半句）。
   - 删除 1 条：Result directory（被 Target directory 取代，含撞词注记与 _Avoid_）。
   - Relationships：clean 行改写、discovery/prepared 消费行加 Test、dispatcher 业务行为行加 test，新增 7 行（test 前置与消费、test block→转译、test discovery 分层、测试生成物非 artifact、Testing 注入、视图行号对应、Clean 删 target/）。
