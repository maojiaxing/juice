---
title: 决策：testing 包定位与发布布局契约
status: closed
labels: [wayfinder:grilling]
assignee: maojiaxing
blocked-by: []
parent: 0065
---

> 2026-10-22 重锚：按新 juice（otter 实现）重写；旧 `modules/Testing.jai` 查找与旧发布树描述已失效。共同事实见 `0065` Notes。

## Question

新 juice 在运行时如何定位 testing 包 / 其模块面，并把哪个目录前插到编译 import path，使 `#import "Testing"`（以及 jaix 消费者对 `Jaix_Plugin_Test_Block` 的导入）解析到它？

新实现事实：

- `juice_modules_dir()` = `<exe>/modules`（`src/path_safety.jai:37`）；发布树 8 件（`docs/spec.md` §9.2）；安装布局 = exe + 相邻 `modules/`（无同级 `src/`）。
- `src/commands/test.jai:testing_module_source`（232）：`<pkg>/modules/Testing.jai`（in-package）→ `<exe>/modules/Testing.jai`（global）；`testing_module_view`（251）；`src/transpile_front.jai:testing_module_strip_view_dir`（313）；`src/commands/build.jai:248` 直接用 `<exe>/modules/Testing.jai`。
- 旧前提（包根 `Testing.jai` / `Jaix_Plugin_Test_Block.jai` 使 `#import` 直接解析）在新实现下需要复核：测试发现全包扫描会收录包根 `.jai`，而 driver 同时导入发布 Testing 面，裸名会撞重载（`src/module.jai:165-173` 的 spike 结论）。候选 = `testing/modules/Testing.jai`（沿用 in-package 约定、`modules/` 在扫描排除集）或包根 + 扫描/导入特例。

需要定清：

- 开发布局（juice 与 testing 同级）与发布布局（juice 发布树是否携带 testing 源/模块面；8 件是否变化）；
- 是否提供环境变量覆盖、探测顺序、缺失时的错误文案；
- `testing_module_source` / `testing_module_view` / `testing_module_strip_view_dir` 的查找规则如何泛化（包自身模块文件；legacy `modules/Testing.jai` 回退）；
- 对 `juice_modules_dir()`、发布树 8 件与安装布局的影响；
- jaix 消费者如何解析 `Jaix_Plugin_Test_Block`（testing 包根 / `modules/` 是否在 import path；与 juice 发布面的关系）。
- 测试发现面迁入 testing 后（0075），发现源件（生成 metaprogram 以绝对路径 `#load`）也须按同一包定位规则解析；定位契约应预留该消费面。

**Done when:** 定位契约写清（目录布局 + 搜索顺序 + 错误面 + 与 `modules/` 的关系）；后续接线票可直接照做。

## Resolution

（2026-10-22 grilling 敲定；Q1'/Q2/Q3/Q4/Q6 逐轮确认）

1. **Monorepo 形态**：`testing/` = root LIB 包；jaix AST 插件 = `testing/packages/Jaix_Plugin_Test_Block/` 成员包（`package.jai` 的 `PACKAGE.name = "Jaix_Plugin_Test_Block"`；根 `module.jai` = 插件源，test-free；成员自身零依赖、不作为独立 test root）。`testing/package.jai`：`workspace.members = ["packages/Jaix_Plugin_Test_Block"]`；dependencies = `jaix`（`../jaix`）、`packrat`（`../packrat`）、`Jaix_Plugin_Test_Block`（工作区成员按名链接，source 忽略）。插件测试与 fixture 驻 testing root（`tests/` / `fixture/`），经 root 的 shim `Jaix_Plugin_Test_Block :: #import "Jaix_Plugin_Test_Block"`（sealed 形态不变）。原因：新 juice 依赖准备按 root CWD 解析非成员相对 DEP（`src/dependency.jai:171-208`）；成员写 `../../../jaix` 会在 root prep 解析错，root 声明依赖 + 成员零依赖是安全形态。代价：成员不是独立可跑的测试根。
2. **外部消费者**：需要该插件的 jaix 用户声明 `Dependency.{name="Jaix_Plugin_Test_Block", source="<path>/testing/packages/Jaix_Plugin_Test_Block"}`（`ensure_import_shim` 命中成员根 `module.jai`）。jaix 自身按 0073 去掉该依赖；testing 自己的测试经 root 的同名 DEP 链接。
3. **Testing 面与包入口**：Testing 权威面 = `testing/modules/Testing.jai`（裸名；in-package 约定、`modules/` 在扫描排除集）。包入口 = 根 `testing/module.jai`（仅 `PACKAGE`）。**不提供 `#import "testing"` 包级面**（`testing.jai` vs `Testing.jai` 的 Windows 大小写近匹配风险；无消费方）；公开面只有 `#import "Testing"` 与 `#import "Jaix_Plugin_Test_Block"`。testing 根跑 `juice test` 时走 in-package EXPAND 视图；support 段落 `testing/tests/test_support.jai`（0070）。
4. **运行时定位 = 不新增**：`testing_module_source`（`src/commands/test.jai:232`）的 in-package `<pkg>/modules/Testing.jai` 分支正是 testing 包自己的路径；其他包继续走 `<exe>/modules/Testing.jai`。`testing_module_view` / `testing_module_strip_view_dir` / `juice_modules_dir()` / Build 的 Testing 特例全部不变。in-package 是约定，不是待删 legacy。
5. **发布布局 = 不变**：testing 源不随 juice 发布树携带；发布树仍 8 件；安装布局仍 exe + 相邻 `modules/`。testing 是 dev-time 兄弟包（`jai/testing/`），用 juice exe 跑自己的测试。0075 若迁出发现源，发布树变化归那票。
6. **dev-time 权威定位器**：新增 `src/testing_location.jai`（test-free），暴露 `testing_package_root(root_dir)`：`JUICE_TESTING_ROOT`（testing 包根）优先；未设置用 `<juice root>/../testing`。校验 `package.jai` + `modules/Testing.jai`。语义：显式 env 无效 = 失败；默认路径不存在 = 同步测试 SKIP（打印默认路径与 env 名）；默认路径存在但权威面缺失 = 失败。0066 同步测试与 0075 共用；主 exe 需要时 #load。
7. **错误面**：runtime 缺 `<exe>/modules/Testing.jai` 保持「特例禁用 + 编译器报错」，不加命令层早期失败（不使用 Testing 的包必须照常 build/test）；Build 侧同理（`testing_module_strip_view_dir` 缺失返回 ""）。dev-time 缺失由第 6 条的 SKIP/失败文案承担。
8. **fixture 布局**：沿用 jaix 的 dot-prefix `.jai`（`.input.jai` / `.config.jai` / `.stress-*.jai`），扫描排除集天然覆盖，不需要新排除规则。
9. **文本 test-block 转换落位**：归 0068/0072（root `modules/` 还是另一个 `packages/` 成员由 API 形状定），不在本票。
