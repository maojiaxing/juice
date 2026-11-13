---
id: 007
title: manifest 求值器 + 协议面 + 结构体面起步
labels: [implementation, ready-for-agent]
status: closed
assignee: maojiaxing
blocked-by: []
blocks: [008, 010]
---

> 父 spec：`002-spec-build-clean-structure.md`（决定 5/6/14 + US 1-5）。上游规格：`docs/spec.md` §2.1/§2.2/§2.3；研究 R§1.2。

# 007: manifest 求值器 + 协议面 + 结构体面起步

**What to build:** package.jai 声明经**真 jai 子进程求值**（每 manifest spawn jai：#load manifest + #run main 打印行记录）→ 父进程**严格解析**成结构体（十二种记录 NAME/VERSION/TYPE/DESCRIPTION/BUILD_SCRIPT/JAIX_CONFIG/JAIX_EXE/TRANSPILE_PLUGIN/TARGET/MEMBER/EXCLUDE/DEP；未知键/重复单值/形状错 = 错误 + 行号）→ 两道校验门（validate_jaix_marker、validate_transpile_pipeline：未知 id/重复 id/非法选项拒绝）+ 写盘失败退出码 2、父重试至多两次。src/module.jai 落 Package 结构体面（Package/Package_Type/Target/Dependency/Workspace，§2.1 全字段）。main 占位维持（真接线 010）。

**Blocked by:** None (can start immediately)

**Status:** closed

- [x] 求值器子进程面：spawn jai 求值 manifest、行记录协议、写盘失败退出码 2、重试至多两次
- [x] 父进程严格解析：十二种记录 + 未知键/重复/形状错 = 错误 + 行号
- [x] 两道校验门（jaix marker / transpile pipeline）
- [x] src/module.jai = Package 结构体面（#load 直测，不 import；内部消费照旧 `#import "Juice"` 旧模块面）
- [x] manifest_tests 姊妹测试起步（协议矩阵/校验门/重试）
- [x] E2E：真 jai 子进程求值 fixture package.jai（tests/data/manifest-fixture）协议记录断言
- [x] 旧 juice build/test 于 otter 根零特判全绿（debug + release）
- [x] 票内 `## Resolution` + status: closed + map Decisions so far 追加一行（map 行归主会话——team-lead 指示本票不改 map.md）

## Resolution

**实现摘要**（新建文件 7 个，改动 0 个——src/main.jai 占位维持，真接线归 010）：

- `src/manifest.jai`：求值器 + 协议 + 加载器全链（语义等价重写自旧 juice manifest.jai）。`build_eval_code` 生成求值器程序（`#load` manifest + `#run main()` 打印十二种行记录，声明序锁定）；`parse_manifest_data_strict` 严格解析（未知键/重复单值/形状错 = 错误 + 1-based 行号，错误文本逐条同旧 juice）；`validate_jaix_marker`/`validate_transpile_pipeline` 两道 standalone 校验门（未知 id/重复 id/非法选项拒绝，id 集 = `load`/`test-block`）；`manifest_hash_hex`（FNV-1a 16 位 hex）+ `manifest_temp_file_names`（按 manifest 绝对路径哈希命名）；`load_package_manifest`（每 manifest 一个 jai 子进程；写盘失败退出码 2 重试至多两次共三次尝试；其他非零立即失败；读盘 → 严格解析 → 两道门 → `pkg.dir` 绝对路径回填）。
- `src/juice_module.jai`：`Juice :: #import "Juice"` 命名空间绑定（how_to 040 形态）——内部消费照旧解析 load-bearing "Juice" 模块（bootstrap 期 = 旧 juice 模块面），src 代码以 `Juice.Package` 等限定名消费。**原因见偏差 1**。
- `src/module.jai`：Package 结构体面 = Package_Type/Target/Dependency/Workspace_Config/Jaix_Prestep/Transpile_Plugin_Option/Transpile_Plugin_Declaration/Transpile_Pipeline_Declaration/Package + 两个内置 id 常量（§2.1 全字段，字段形状同旧 juice/modules/Juice.jai:97-118）。
- `src/path_safety.jai`：`path_slashes` + `juice_modules_dir`（spec §9.3 有意偏差：`<exe>/modules`，见偏差 3）。
- `tests/test_support.jai`：otter_root（intermediate_path 剥尾分隔符，旧 juice juice_root 同款）、bootstrap_juice_modules_dir（兄弟仓旧 juice modules 的 bootstrap 窗口助手，jaix_exe 先例形态，阶段 3 退役）、Eval_Spawn_Recorder 记录 fake（exit_codes 按序返回 + 罐装协议写盘）。
- `tests/module_tests.jai`：结构体面直测（6 块：零值默认、TYPE 枚举协议编号 0/1/2、Dependency 默认、全字段字面量往返、内置 id 常量、options 类型化行）——经 Test discovery 全包扫描把 src/module.jai 声明带进测试程序应用作用域，**不** `#import "Juice"`。
- `tests/manifest_tests.jai`：协议矩阵（解析面 11 块）+ 校验门矩阵（5 块）+ 加载器 seam 测试（9 块：退出码 2 重试至多两次后失败/第三次成功/非 2 立即失败/缺 manifest 短路/协议错/两门/回填/缺数据文件）+ E2E（1 块）。
- `tests/data/manifest-fixture/package.jai`：E2E fixture——十二种记录全集（TRANSPILE_PLUGIN×2 声明序、TARGET×1、MEMBER×2、EXCLUDE×1、DEP×2 含异名 package 字段）。

**验证矩阵**：

| 步骤 | 结果 |
| --- | --- |
| `jai build.jai`（旧 juice debug） | 成功 → target/juice.exe |
| 清 target/transpile → `juice.exe build` 于 otter 根 | exit 0，「Build completed successfully!」 |
| `juice.exe test`（debug） | exit 0，**37 passed, 0 failed**（含 E2E 真 jai 子进程块） |
| `jai build.jai - release`（旧 juice release） | 成功 |
| 清 target/transpile → `juice.exe build` + `test`（release） | exit 0，**37 passed, 0 failed** |

37 = stage0 1 + module_tests 6 + manifest_tests 30。旧 juice 对无 modules/ 包根的 import dir 探测提示为通用无害行为（map Notes 已记）。

**偏差清单**：

1. **"Juice" 消费面改命名空间导入（load-bearing 约束的形式偏差，实质不变）**：硬约束「内部消费照旧 `#import "Juice"`（裸导入）」与「src/module.jai 落 Package 面」在同一程序内不可共存——旧 juice 的测试程序把全包文件编译进**同一应用作用域**（src 内联测试机制），裸 `#import "Juice"` 会把 Package 等链接进应用作用域，与 src/module.jai 的同名声明撞成 "Redeclaration of 'Package'"（spike 实录，`AppData/Local/Temp/otter-scope-spike/`；`#scope_file` 舞蹈、`#import,file` 隔离均 spike 证伪）。解法 = `Juice :: #import "Juice"` 命名空间绑定（共享文件 src/juice_module.jai，load 序最先）：模块名 "Juice" 依旧 load-bearing、依旧经 import 目录解析到旧 juice 模块面，仅消费面从裸名变 `Juice.Package` 限定名；package.jai 与生成的求值器程序保持裸导入（独立进程无冲突）。
2. **load_package_manifest 签名扩展两个默认参数**：`(cache_dir, pkg_dir, modules_dir = "", spawn = spawn_manifest_evaluator)`——modules_dir 注入供 bootstrap 期 E2E 指向旧 juice modules（spec §9.3 推导在 bootstrap 期不可命中）；spawn seam（`(eval_src, eval_out, modules_dir) -> s32`）供重试回路确定性测试（真子进程写盘失败无法按需制造；旧 juice 该回路零测试）。两者皆默认参数，008 起调用点保持旧 juice 两参形状；符合 002 决定 7 的 seam 姿态。
3. **juice_modules_dir = `<exe>/modules`**：按 spec §9.3 有意偏离旧 juice 的 `<exe>/../modules`（modules 是生成件与 exe 相邻）；bootstrap 期生产推导不可命中（otter/target/modules 尚不存在），全部经注入 seam 覆盖，阶段 2 发布步骤落位后自然命中。
4. **解析器「空 key」分支为防御性死代码**（与旧 juice 同状）：整行先 trim 再 split，"=value" 与空白 key 均落 malformed 分支；语义等价保留该分支，测试文档化。

**测试组织**：src 实现模块全部 test-free（bootstrap #load 集纪律）；测试驻 tests/（module_tests/manifest_tests 姊妹文件 + test_support 共享声明，0053 规则同款）。Jai 事实备忘：结构体字段 `[]` 切片不可 `array_add`（需 `[..]` 局部数组赋值）；函数形参不可变（局部变量承接）。

