---
id: 026
title: 视图层（缓存键 + 剥离前端）
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: [024]
blocks: [027, 028]
---

> 父 spec：`004-spec-plugin-surface-skeleton.md`（决定 18/19 + US 15-17）。上游规格：`docs/spec.md` §11.9；参照面：旧 juice transpile_cache.jai + transpile_front.jai（语义等价重写）。

# 026: 视图层（缓存键 + 剥离前端）

**What to build:** 视图键 = hash(路径 + 源 + 模式 + 版本 + load 重写表 + 管线描述)（otter 带自身版本分量、与旧 juice 键不共享——有意选择）+ 内容寻址落盘/命中跳过 + 闭包探测（test-free 直编原文 / 含 test 闭包全有全无 STRIP 视图，探测经管线 has_anchor 聚合）+ 依赖剥离前端（依赖闭包 STRIP 视图落 target/transpile/deps/ + shim #load 改写——依赖测试不发现不执行面）。本票 = 库面，命令接线随 027/028。

**Blocked by:** 024（管线组装——探测与剥离走合并后的管线）

**Status:** ready-for-agent

- [x] 视图键全成分 + otter 版本分量（与旧 juice 键不共享）
- [x] 内容寻址落盘 + 命中跳过写入
- [x] 闭包探测矩阵（test-free 直编 / 含 test STRIP / 探测经管线 has_anchor）
- [x] 依赖剥离前端 + shim 改写（依赖测试不发现不执行面）
- [x] 姊妹测试 + 旧 juice build/test 于 otter 根零特判全绿（debug+release）+ 335 存量不回归
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话）

## Resolution

**实现摘要**：

- **`src/transpile_cache.jai`**（新建，test-free——链约定 bootstrap #load 集纪律；旧 juice transpile_cache.jai 语义等价重写）：
  - **`VIEW_CONTRACT_VERSION :: "otter-0.1.0"`**——缓存键版本分量 = 管线输出契约版本（spec 004 决定 19 的 JUICE_VERSION 语义）；"otter-" 前缀刻意 = 与旧 juice 键空间不共享（spec §11.9 有意选择——不混用存量视图树，旧 hash 目录随 clean 消失）；
  - **`transpile_view_key`**（视图键全成分：路径 + 源 + 模式 + 版本 + load 重写表 + 管线描述；load 重写表嵌入子视图 hash 目录 = Merkle 链；管线描述 = 有序 name+version 序列——改名/升版/换序精确失效；省略/空管线 = 缺省管线 resolve_pipeline，省略版本 = 契约版本常量）+ `hash_hex`（FNV-1a 64 → 16 小写 hex）+ `cache_slashes`；
  - **视图路径助手**：`transpile_hash_dir`（`<tree>/<hash>`）/`transpile_view_path`（`<tree>/<hash>/<rel>`——包相对结构镜像防名撞）/`transpile_dependency_view_path`（`<tree>/deps/<name>/<hash>/<rel>`——依赖子树互不撞）/`transpile_tree_dir`（`<root>/target/transpile`）。
- **`src/transpile_front.jai`**（新建，test-free；旧 juice transpile_front.jai 语义等价重写）：
  - **`Build_Source_File`/`Build_Closure_File`/`Build_File_Output`** 三记录（旧 juice 形状）；
  - **闭包探测 `probe_package_closure`**（入口 DFS 经 pipeline_load_edges、visited 去重、DFS 前序——入口先于子树、load 目标语句序；探测聚合经 pipeline_has_anchors——test-free 闭包零转译直编原文、含 test 闭包全有全无 STRIP 视图的决策源）+ `closure_has_tests` 全有全无判定 + error_prefix 注入面；
  - **`Strip_View_State` + `view_of_file`**（两布局：CONTENT_ADDRESSED——内容寻址落盘 + `front_view_exists` 命中跳过写入；PLAIN——`<base>/<rel>` 恒写，阶段 2 bootstrap 消费面；依赖序 children-first 计算 = Merkle 链；环检测「循环加载无法重写路径」/缺视图目标/诊断拒绝全失败路径）+ `closure_index`；
  - **`transpile_build_file`**（生产转译步：读 → STRIP 管线转译 → 键推导）+ **`testing_module_strip_view_dir`**（Testing 模块 STRIP 特例——test-free 模块零动作返回 ""，US 19，027/028 直接消费）；
  - 依赖剥离前端面 = `dep_name` 非空 → `deps/<name>/` 子树 + 视图内 #load 改写（**外层 shim 改写 packages/<name>.jai → 入口视图归 027 b5 接线**——旧 juice dependency.jai prepare_dependency_strip_views 面，本票库面不含）。
- **main.jai 零改动**（020-025 先例）：首生产消费者 = 027/028。
- **`tests/transpile_cache_tests.jai`**（新建，5 test 块）+ **`tests/transpile_front_tests.jai`**（新建，13 test 块——好测试标准 = 只测外部行为：给定包根/入口/管线 → 视图落盘/键/命中/探测结果）：键确定性 + 全成分敏感（路径/源/模式/版本/管线描述）+ **otter 键与旧 juice 键空间隔离钉**（"otter-0.1.0" vs "0.1.0" 键不同）/ Merkle 链（重写表三变体）/ 管线描述敏感（改名/升版/换序 + 省略 = 缺省）/ 路径形状全集（hash 目录/镜像防撞/deps 子树/树根/反斜杠归一）；前端：生产转译步剥离真 test 块 + 键一致性 / 不可改写 load 逐字保留 / PLAIN 恒写两矩阵 / **CONTENT_ADDRESSED 落盘 + 命中跳过（陈旧文件逐字节不动）** / **依赖子树真链（真实 transpile_build_file + dep_name → deps/<name>/<key>/<rel> 落盘 + 入口视图嵌子视图路径 + 依赖 test 块剥净——无 juice_test_N 无 @test）** / 探测矩阵（test-free 直编/含 test STRIP/显式管线同判）/ DFS 前序钉 / 缺入口失败 / 环拒绝 / 缺视图目标拒绝 / Testing 模块两矩阵；助手 prefixed 命名 tfront_*/tcache 无裸名（单命名空间纪律）。

**验证矩阵**（旧 juice 双路径，各先清 otter/target/transpile）：

| 路径 | juice build | otter build | otter test |
| --- | --- | --- | --- |
| debug | exit 0 | exit 0 | exit 0，**Found 353 tests**（335 基线 + 18 新），206 passed, 0 failed |
| release | exit 0 | exit 0 | exit 0，**Found 353 tests**，206 passed, 0 failed |

expect failed 白名单 4 行（module_tests Testing face 自测 :178/:183/:207/:212，debug+release 逐行同状，无新增）；debug 额外连跑 1 次零 stall。

**偏差清单**（全有意设计决定，无遗留缺陷）：

1. **缓存键版本分量 = `VIEW_CONTRACT_VERSION`（非 JUICE_VERSION 名）**：JUICE_VERSION 已被 `src/commands/version.jai` 占用（013 产品版本契约「juice 0.1.0」——version_tests 逐字节钉死）；spec 004 决定 19 的「JUICE_VERSION 语义 = 管线输出契约版本」落为 transpile_cache.jai 独立常量，值 "otter-0.1.0" 前缀承载与旧 juice 键不共享的选择（测试钉两值键不同）。
2. **管线描述分量 = 有序 name+version 序列（非 id+version）**：管线是 `[..] Transpile_Plugin` 列表，Transpile_Plugin 无 id 字段——024 已钉「name 即管线身份」（otter 无关键字 claim 面）；US 10 的 Juice_Plugin id+version 身份经合并产物的 name+version 序列进键（合并查重已保 name 唯一）。
3. **PLAIN 布局 + testing_module_strip_view_dir 随库面全量落地**（票面未逐条列，父 spec 决定 18 t9 + 旧 juice 文件划分）：PLAIN = 阶段 2 bootstrap 消费面（5 票 spec 阶段 2 照抄 ADR 0006）；testing_module = US 19（027 build b5 面 / 028 t9 面直接消费）。
4. **测试助手 prefixed 命名**（tfront_*/tcache 无裸名助手）：测试程序单命名空间——build_seam_write/file_contains 等裸名已占（023 偏差 2 同族）。
5. **前端测试 13 块 = 旧 juice 8 块语义 + 本票新面 5 块**：CONTENT_ADDRESSED 落盘+命中跳过、依赖子树真链、DFS 前序钉、环拒绝、缺视图目标拒绝（旧 juice 无姊妹测试对应面，语义按 spec 决定 18 钉）。
