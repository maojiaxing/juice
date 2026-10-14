---
title: monorepo 测试 fixture 家族
status: closed
labels: [wayfinder:task]
assignee: maojiaxing
blocked-by: []
---

## Question

落地本 effort 的专用 fixture 家族 `tests/data/workspace-*`，供 discovery 校验矩阵、build/clean/test E2E 四张票共同消费。已锁定决策（grilling 2026-10-13）：

- **不复用 scan-fixture**：其文件是特意构造的非法 Jai（为扫描排除语义服务），不适合承担构建语义。专用家族。
- **每个失败模式一个独立 fixture**：discovery 首错即停，单 fixture 混多个坏 member 只能测到第一个。
- **symlink/junction 与 clean 的 target 垃圾不提交**：由测试运行时在 target/ scratch 制造。

Fixture 清单：

1. `workspace-ok/` —— 合法多 member workspace：root BIN（`package.jai` + `src/main.jai`，声明依赖并 `#import` 两个 member）+ `member-lib/`（LIB，导入入口 `src/module.jai`，导出一个可被断言的函数）+ `member-extra/`（LIB，导入入口根 `module.jai`，覆盖第二种布局）。两 member 同时覆盖多 member link。root 的 `main.jai` 调用两 member 的函数并输出可断言结果。
2. `workspace-bad-root-manifest/` —— root `package.jai` 语法非法（其余内容最小）。
3. `workspace-bad-escape/` —— member 路径含逃逸组件（如 `../outside`），其余声明有效。
4. `workspace-bad-missing-dir/` —— member 路径指向不存在的目录。
5. `workspace-bad-no-manifest/` —— member 目录存在但无 `package.jai`。
6. `workspace-bad-invalid-manifest/` —— member `package.jai` 语法非法。
7. `workspace-bad-duplicate/` —— 两个文本不同、归一化后同目录的 member 路径（首选 `["member-lib", "member-lib/."]`；若 validity 检查先拒绝 `.` 组件则改用 Windows 大小写撞车 `["Member-Lib", "member-lib"]`，以实际打到 duplicate 分支为准）。
8. `workspace-edge-self/` —— root 把 `"."` 列为 member（边界用例，供矩阵票钉住行为）。
9. `workspace-edge-nested/` —— 合法 workspace 中，某 member 的 `package.jai` 再声明 `workspace.members`（边界用例，供矩阵票钉住行为）。

约束：每个 bad fixture 只坏被点名的那一支（root manifest 除 `workspace-bad-root-manifest` 外全部有效）；**不提交任何 `target/`**；package 名称非空、可作 portable filename，版本明确；文件全部 ASCII/UTF-8 可被 git 干净提交。

## Acceptance criteria

- [ ] 上述 9 个 fixture 目录存在且形状正确（member 路径、入口布局、manifest 内容与规格一致）。
- [ ] `workspace-ok` 的 root manifest 可被 `load_package_manifest` 成功求值（executor 自行脚本验证，不写入测试）。
- [ ] 除 `workspace-bad-root-manifest` 外，各 bad fixture 的 root manifest 均有效、坏点恰为点名的那一支。
- [ ] 无 fixture 提交 `target/` 目录；git status 无 .gitignore 相关的意外排除。

## Out of Scope

- 本票不写测试块（矩阵票写）；仅交付 fixture 形状。
- symlink/junction fixture 与 clean 的 target 垃圾（运行时制造，见矩阵票与 clean 票）。

## Further Notes

- fixture 根目录名统一 `workspace-*` 前缀，与既有 `scan-fixture`、`test-package` 命名并列。
- 若 discovery 行为与分支预判不符（如 `.` 组件也被 validity 拒绝），以实际打到目标分支为准调整 fixture 拼写，并在 Resolution 记录实际拼写。

## Resolution

9 个 fixture 全部落地并经真实 `target/juice.exe`（最新构建，含票 0040）逐冒烟验证：

- **workspace-ok**：root BIN `ws_root`（依赖两 member）+ `member_lib`（LIB，`src/module.jai` 布局）+ `member_extra`（LIB，根 `module.jai` 布局）。全链路通过：discovery → 依赖准备（两 shim 均生成、各自指向对应布局的导入入口）→ 构建 → artifact 运行输出 `ws_root: hello from member_lib | hello from member_extra`，证明两 member 函数被实际调用。fixture 内包名用下划线（`member_lib`），目录名用连字符（`member_lib` 目录、`workspace-*` 根）——`#import "member_lib"` 经 shim 编译解析验证可行。
- **6 个 bad fixture 全部命中预期分支**（build 均退出 1 + 预期 `[juice ERROR]` 行）：root manifest 无效→`Existing package.jai is invalid.`；逃逸→`Invalid workspace member path: ../outside`；目录不存在→`Workspace member is not a safe real directory: ghost_member`（**实测事实，见下**）；缺 manifest→`lacks package.jai`；member manifest 无效→`Workspace member manifest is invalid`；重复→`Duplicate workspace member path: member_lib/.`（**`member_lib/.` 拼写成功命中 duplicate 分支**，`get_absolute_path` 会归约 `.`，无需回退大小写撞车）。
- **workspace-edge-self**：`"."` 命中 `Duplicate workspace member path: .`。
- **workspace-edge-nested**：build 成功、artifact 运行正常——member 的嵌套 `workspace.members` 声明被**静默忽略**（sub_member 不进 discovery）。行为与 CONTEXT.md「member 由 root package 声明」一致，非缺陷；矩阵票按此钉住，wrap-up 可考虑在 CONTEXT.md 补事实陈述。

**供 [discovery 成员校验矩阵](0043-discovery-validation-matrix.md) 消费的实测事实**：`normalize_existing_path` 对不存在的目录也返回成功（仅词法归一，不验证存在），所以「member 目录不存在」实际命中 **not a safe real directory** 分支（消息：`Workspace member is not a safe real directory`）；代码中的 `does not exist` 分支只在 `get_absolute_path` 自身失败时可达——直测请按实测分支断言。`plain_member/placeholder.txt` 是占位文件（git 不跟踪空目录，否则干净检出会退化到「目录不存在」）。

冒烟后已清理全部 fixture 的 `target/` 残留；git status 确认 9 个 fixture 均可干净跟踪、无 gitignore 误伤。

