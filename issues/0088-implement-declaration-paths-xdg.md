---
title: 实施：声明路径身份与 XDG 目录基础
status: open
labels: [ready-for-agent]
assignee: maojiaxing
parent: "0087"
blocked-by: []
---

## Goal

为 [包声明语义实施规格](0087-spec-package-declaration-semantics.md) 的名称、路径与内容/状态目录提供实际可调用接口。对应 Implementation Decisions 6、8、15；验收 A01/A11/A15。独立于公开 Package 类型变更，可以先行合入。

## Ownership

只修改 `src/path_safety.jai`、`src/xdg.jai` 和新增的 `tests/declaration_paths_tests.jai`。不修改公开声明、main、依赖模块、现有其他测试、产品文档。若存在真正必要的额外接线，写清给后续票，不能未经协调侵入其文件。

## Required behavior

- 分离逻辑名称校验与文件路径：包/依赖名/插件 ID 使用已定 ASCII 范围，导出/程序/alias/option key 使用标识符范围；提供 ASCII 等价比较而不改原始值。不要收紧包名规则以沿用 Windows 文件名保留规则。
- 包内路径逻辑消解 . 和 .. 后做包含检查，拒绝绝对/卷相对/UNC 越界；合法 src/../module.jai 可以规范化，普通本地依赖 ../sibling 的定位能力交给调用者选根。
- 文件系统路径链任何受约束组件为 symlink/junction 时拒绝（不是仅检查叶子）。物理大小写身份沿用平台语义，Unicode 路径不使用 ASCII 名称折叠。
- 提供分别取得 Juice 内容缓存根与解析状态根的有成功/失败结果接口；所有平台优先有效绝对 XDG 值，相对 XDG 值警告后回退。Windows 默认 LOCALAPPDATA/juice/cache、LOCALAPPDATA/juice/state；非Windows默认 HOME/.cache/juice、HOME/.local/state/juice。
- 缺少可靠用户默认根时失败，不回退系统根/cwd/临时目录；有效配置不可写或创建失败不换目录。保持对现有调用者可编译的函数形状，新的失败/目录结果供后续 main/dependency 接线；若修改旧 get_cache_home，确保其语义不会引入双重 juice 后缀并说明如何迁移调用者。
- 不自行删除用户缓存/状态，不读取或输出秘密。环境/文件系统失败测试可在现有函数边界注入或用受控临时根，不新增通用状态框架。

## Validation

先读 tdd 技能，使用已批准的现有模块接口与真实临时文件系统测试，逐行为 red/green。覆盖规范化后包内/越界、Windows卷相对、至少可运行平台的物理别名/链接拒绝、XDG绝对优先/相对回退/无可靠根/不可写失败及内容与状态目录分离。建立源码自举验证（jai build.jai）并报告可用的测试执行命令；不要把 test 的过滤零命中当通过，测试块显示名可能是 juice_test_N。

## Integration

集成分支 `integration/package-declaration-semantics`；共享执行纪律在仓库外 `C:/Users/maojiaxing/DevTools/msys/tmp/juice-package-implementation/README.md`。报告精确的新函数签名/失败语义，供声明及依赖票消费。完成前合并集成分支最新 tip，提交变更；由 merger 核对并关闭本票。
