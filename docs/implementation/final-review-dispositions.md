# 0098 五项低置信项的书面裁定

本文件是 `issues/0098-fix-package-declaration-final-review.md` 要求的“五项低置信项各自书面裁定”。
每一项给出：观察到的现象、判定、依据（真实测试或代码位置）、以及**未验证边界**。

**平台范围**：本轮验收只在 Windows 完成（0098 Validation 章节）。以下所有“已验证”都指 Windows；
Linux/POSIX 一律未验证，不得由 Windows 结果推断。L01 的 POSIX 分支（`POSIX.stat`/`chmod`）在任何平台
都未执行过。

---

## 1. Windows 物理身份（A15 大小写契约）

**现象**：包内 `entry = "SRC/main.jai"` 与磁盘上的 `src/main.jai` 在 Windows 上指向同一个物理文件；
声明里的路径拼接、重复判据、越界判定都以“归一化后的物理身份”为准。

**裁定**：接受当前行为，作为 Windows 上的**已定义**语义：大小写不敏感卷上，两个拼写是同一个物理
文件，因此不算重复入口、不算越界。规则本身（“按实际物理身份判定”）是平台无关的表述，实现在
Windows 上的结果就是本条。

**依据**：`acceptance_a15_case_identity_and_cross_category_names`
（`entry = "SRC/main.jai"` 在 Windows 上可构建；同包模块与程序同名 `tool` 合法）在 Windows 通过。

**未验证边界**：大小写敏感文件系统（`src/` 与 `SRC/` 是不同文件时入口必须被拒绝）**从未执行**——
该分支只有在 Linux/macOS 卷上才跑。因此 A15 的“大小写敏感契约”仍是一个**未运行的代码路径**，
不得写成通过。

---

## 2. 默认分支与缓存完整性（A09 离线解析）

**现象**：首次解析记录提交；之后普通 build/run/test 复用记录不追新；`--offline` 只用记录与已缓存内容。

**裁定**：接受。三条规则合成一个可判定的矩阵，全部有测试：
浮动 selector（默认分支/分支名/短修订）**没有记录**时离线拒绝；完整 40 位提交**有记录且内容已缓存**
时离线可建立选择；完整提交但内容缺失时拒绝。

“默认分支在记录之后又前进”不是缺陷：记录已经存在，离线复用的就是记录值，与远端是否移动无关。

**依据**：`dependency_resolution_offline_matrix`、`dependency_resolution_git_content_restore`
（删除内容缓存后记录仍在、离线失败、在线只恢复记录提交）在 Windows 通过；
`dependency_resolution_git_reuse_and_update` 证明 `update` 刷新、`update --offline` 被拒。

**未验证边界**：Git 提供方在**并发**写入内容缓存（两个进程同时 fetch 同一 url）时的行为未测试；
本轮未做多进程压测。

---

## 3. 安装 epoch 与构建身份

**现象**：安装单元的兼容判据来自 marker（epoch、ABI、模块集合与逐件摘要），而不是“是否由同一次构建产出”。

**裁定**：**来自不同构建的、完整的、兼容的安装单元不是缺陷。** 判定“可用”的条件是
“同一 epoch + 同一 ABI + 完整集合 + 每件摘要匹配”，构建身份（时间戳、路径、二进制哈希本身）不参与判定。
理由：发布形态是一个可复制的目录（`juice.exe` + 相邻 `modules/`），运维会把两个同版本构建的产物互换；
把“必须是同一次构建”当成不变量会让正确的安装被拒。

**依据**：`publication_install_` 15/0（Windows）：完整单元校验通过；缺 marker、缺 epoch、ABI 不符、
缺件、改件、集合不符各自明确失败；`bootstrap_publication_unit_marker` 证明自举产物与生成的 marker
逐字节一致，替换 `Testing.jai` 后该产物失败。

**未验证边界**：两个**不同 epoch** 的构建混装（例如旧 `juice.exe` 配新 `modules/`）只会被 marker 判为
不兼容并失败——这一点由“epoch 不符即失败”的既有用例覆盖；跨操作系统可执行文件混用不在本轮范围。

---

## 4. 提供方反向可见性

**现象**：消费包能看到提供方选定的公开模块（按 alias/公开名），提供方看不到消费包，也看不到“消费方
如何重命名自己”。

**裁定**：保持单向。反向可见性不属于契约：提供方在解析时只知道自己导出了什么，不知道谁在用；
消费方的 alias 只存在于消费方私有 shim（`dependency_imports_dir(consumer_package.dir)`）与私有视图
（`<consumer>/target/deps/<key>/`）里，提供方源码与共享检出保持只读、不含任何消费方名字。

S16b 修复后这两处**同属消费包**，因此“私有视图里出现消费方私有名”也不会泄漏到提供方目录。

**依据**：`dependency_resolution_transitive_visibility`（`Netlib -> Cipher` 不泄漏）、
`dependency_resolution_own_module_public_import`、`final_review_workspace_root_provider_shorthand`
与 `final_review_pure_workspace_still_needs_explicit_selection`（Windows 通过）；
`plugin_derived_git_source_read_only_cli`（hook 后 `git status --porcelain` 为空）。

**未验证边界**：提供方是 Git 检出且**同时**被另一个消费方以不同 alias 使用时，两份私有视图互不影响
这一点由 `resolution_create_view` 的“按 node 身份取名 + 消费方私有目录”保证，但没有专门的
“两消费方同一提供方、不同 alias 同时构建”的 E2E 用例。

---

## 5. 非 PRESTEP 的生命周期贡献

**现象**：插件可能只贡献 TRANSPILE / COMPILE / 其它 stage 的钩子，而完全不参与 PRESTEP。

**裁定**：仍然需要宿主（PRESTEP host）。decision 22 的理由不是“有没有 PRESTEP 副作用”，而是
“只有编译出来的子进程才持有插件的真实值”：ABI 版本、options 的 apply/validate 都只在那里存在。
因此**每一个被启用的外部插件都要跑一次宿主**，`member_hooks` 是对声明的保守判定，不再取决于入口
是否恰好拼出 hooks face。

**依据**：`plugin_host_tests` 的 “the hooks face probe decides the host need” 用例现在对 lint 风格成员
断言 `member_hooks == true`（旧断言为 `false`，0098 迁移并说明）；
`test_command_tests` 的 “plugin hits register and wire the metaprogram” 用真实 host 记录文件驱动；
`plugin_derived_builtin_triad_cli`、`plugin_derived_options_errors_cli` 覆盖内置三件与 option 拒绝。

**未验证边界**：只声明**内置**插件（`load`/`test-block`）时宿主不启动——这一点由
`plugin_prepare` 的零外部插件路径覆盖（`prepare.hits.count == 0` 且不建 `target/plugins`），但
“内置插件 + 外部非 PRESTEP 插件混用”的组合没有单独用例，由 `plugin_derived_builtin_triad_cli`
与声明序用例间接覆盖。
