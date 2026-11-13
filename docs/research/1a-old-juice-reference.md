# 旧 juice 参照面（otter 1a 结构层实现链 007-014 用）

> 只读参照面笔记：全部内容摘自 `C:/Users/maojiaxing/Workspace/projects/jai/juice/`（juice v1 交付后工作树）。
> 行号以**当前工作树**为准（juice 有注释英化重构在途，行号会漂移；引用时以符号名为锚）。
> 路径引用格式：`src/manifest.jai:97` = `juice/src/manifest.jai` 第 97 行。

---

## 0. 总览：模块加载序与横切约定

`src/main.jai:6-26` 的 `#load` 顺序（决定声明可见性，后文件能看到先文件的声明）：

```
xdg → path_safety → manifest → workspace → target → dependency
→ transpile → transpile_plugin → transpile_config → transpile_cache
→ transpile_front → metaprogram → scan_walk → jaix_front
→ commands/command → commands/build → commands/run → commands/clean
→ commands/test → commands/registry → dispatcher
```

横切约定（实现 otter 时应照搬）：

- **路径一律正斜杠**：跨进程与写盘路径都用 `/`（`path_slashes`/`to_forward_slashes`）；仅 Windows `rmdir`/`mklink` 调用转反斜杠（`path_backslashes`，见 dependency.jai:509 注释：cmd 内建命令把正斜杠段当选项开关）。
- **错误消息前缀**：`[juice ERROR] ...`（进程内）、子进程诊断走 stderr、juice 自身失败行走 stdout（build.jai:826 注释）。
- **退出码**：main 对 dispatch 失败 `exit(1)`（main.jai:46）；manifest 评估子进程专有 exit 2 = 数据写盘失败（见 §3）。
- **juice 永不 chdir**：包根 = juice 进程 cwd（main.jai:39），所有相对路径解析都锚在这里（见 §14 子进程 CWD 纪律）。
- **seam 姿态**：凡是「真实子进程/文件系统」边界的生产函数，都做成可注入 `#type` 参数（默认 = 生产实现），测试用 recording fake 跨同一接口。构建/测试/清理三条命令都遵守。
- **test 组织规则**：src 内联 test 块贴实现（会被 STRIP 掉）；bootstrap `#load` 的文件必须 test-free，其测试放 `tests/`（如 metaprogram.jai:10-12、transpile_front 的姊妹测试文件）。

---

## 1. main.jai — 入口

- `main :: ()`（main.jai:28-47）：
  - `auto_release_temp()`；
  - `args[1]` 为命令名，缺省 `"build"`；`args[2..]` 为命令参数（main.jai:31-36）；
  - `ctx.root_dir = get_working_directory()`（**包根 = 调用 cwd**，main.jai:39）；
  - `ctx.cache_dir = tprint("%1/juice", get_cache_home())`（main.jai:44）——juice 管的缓存（manifest 评估临时文件、git repo 缓存）全在 XDG 缓存家目录下；其余派生路径（packages_dir 等）由各 owner 从 root_dir 派生；
  - `dispatch_command(COMMAND_REGISTRY, command, *ctx, command_arguments)`；`!result.success` → `exit(1)`（main.jai:45-46）。

## 2. xdg.jai — 环境与缓存家目录

- `get_env :: (name: string) -> string`（xdg.jai:10-19 Windows / 23-28 POSIX）：kernel32 `GetEnvironmentVariableA` / `getenv`；空 → `""`。
- `get_user_home_directory :: () -> string`（xdg.jai:31-45）：Windows `USERPROFILE` → 兜底 `"C:/"`；POSIX `HOME` → 兜底 `"/tmp"`。
- `get_cache_home :: () -> string`（xdg.jai:51-61）：
  - Windows：`LOCALAPPDATA` 环境变量 → 兜底 `%USERPROFILE%/AppData/Local`；
  - POSIX：`XDG_CACHE_HOME` → 兜底 `~/.cache`。
  - 注释（xdg.jai:47-49）：曾经的 get_config_home/get_data_home 随 Build_Driver 拆除删除，只剩 cache home（manifest 评估器 + git 缓存用）。

## 3. manifest.jai — manifest 协议与加载

### 3.1 协议记录全集（十二种）

评估器生成代码（`build_eval_code`，manifest.jai:23-95）逐行打印，**stdout 从不作为协议**——协议 = 评估子进程写盘的数据文件。十二种记录：

| 记录 | 形状 | 重复性 | 解析处 |
|---|---|---|---|
| `NAME` | 任意字符串 | 单例，重复 → `Duplicate NAME record.` | manifest.jai:133-137 |
| `VERSION` | 任意字符串 | 单例 | manifest.jai:139-142 |
| `TYPE` | `""` 或 `0/1/2` | 单例；空 → `.UNSPECIFIED`；非 0/1/2 或带余数 → `Invalid package type enum.` | manifest.jai:144-155 |
| `DESCRIPTION` | 任意字符串 | 单例 | manifest.jai:157-160 |
| `BUILD_SCRIPT` | 任意字符串 | 单例 | manifest.jai:162-165 |
| `JAIX_CONFIG` | 任意字符串 | 单例 | manifest.jai:167-170 |
| `JAIX_EXE` | 任意字符串 | 单例 | manifest.jai:172-175 |
| `TARGET` | `name\|main_file` 恰好 2 段，否则 `TARGET record must contain name|main_file.` | 可重复 | manifest.jai:177-183 |
| `MEMBER` | 非空字符串，否则 `MEMBER record cannot be empty.` | 可重复 | manifest.jai:185-187 |
| `EXCLUDE` | 非空字符串，否则 `EXCLUDE record cannot be empty.` | 可重复 | manifest.jai:189-191 |
| `DEP` | `name\|version\|source\|package` 恰好 4 段，否则 `DEP record must contain four fields.` | 可重复 | manifest.jai:193-201 |
| `TRANSPILE_PLUGIN` | `id\|version` 恰好 2 段，否则 `TRANSPILE_PLUGIN record must contain id|version.`；解析层就查 id 重复 → `Duplicate TRANSPILE_PLUGIN record.` | 可重复 | manifest.jai:203-212 |

注意评估器代码生成的**顺序锁定**（manifest.jai:52-59 注释，spec 0060 决策 6）：`TRANSPILE_PLUGIN` 按声明顺序逐条打印；零声明打印零记录（解析器视为空管线 = 默认管线）；**options 永不过协议**（id+version 而已——jaix「options 不跨进程边界」立场）。

### 3.2 严格解析规则（parse_manifest_data_strict）

- `Manifest_Parse_Result :: struct { success; package; line_number: int; error_message: string }`（manifest.jai:10-15）。
- `parse_manifest_data_strict :: (content: string) -> Manifest_Parse_Result`（manifest.jai:97-226）：
  - 行 trim（`" \r\t\n"`），空行跳过；
  - 无 `=` 或 key 为空 → `Malformed manifest record on line N.` / `Manifest record has an empty key on line N.`（manifest.jai:120-131）；
  - 未知 key → `Unknown manifest record: X`（manifest.jai:214-215）；
  - **所有错误带 1-based 行号**。
- `manifest_parse_failure :: (line_number, message)`（manifest.jai:228-230）构造失败结果。
- `parse_manifest_data :: (content) -> Package`（manifest.jai:234-237）：纯解析便利包装（丢诊断），需要诊断的调用方用 strict 版。
- 顺带：`manifest_hash_hex :: (s: string) -> string`（manifest.jai:286-294）= FNV-1a 64 → 16 位小写十六进制（transpile_cache.jai hash_hex 的本地副本——#load 顺序导致 hash_hex 不可见，注释解释了为什么不重排 #load）。

### 3.3 两道校验门（standalone，进程内可测）

load 路径需要真实 jai 子进程，所以跨记录校验拆成纯函数（manifest.jai:239-243 注释的解释是这两个门的立身之本）：

1. `validate_jaix_marker :: (pkg: Package) -> (bool, string)`（manifest.jai:244-249）：`JAIX_EXE` 非空而 `JAIX_CONFIG` 为空 → `("JAIX_EXE set without JAIX_CONFIG.", false)`——没有 config，pre-step 无事可跑。
2. `validate_transpile_pipeline :: (pkg: Package) -> (bool, string)`（manifest.jai:262-277）：
   - id 必须 ∈ {`TRANSPILE_PLUGIN_LOAD_ID`, `TRANSPILE_PLUGIN_TEST_BLOCK_ID`}（即 `load`/`test-block`），否则 `Unknown transpile plugin id: X`；
   - id 不重复，否则 `Duplicate transpile plugin id: X`（与解析层查重**故意重叠**：解析层带行号覆盖协议文本，此门是程序化构造包的唯一校验函数）；
   - `decl.options.count > 0` → `Invalid transpile plugin options for X: the option set is empty.`（v1 两内置插件选项集为空）。

### 3.4 临时文件命名与加载重试循环

- `manifest_temp_file_names :: (cache_dir, pkg_dir) -> (string, string)`（manifest.jai:305-310）：`<cache>/eval_manifest_<hash>.jai` + `<cache>/manifest_data_<hash>.txt`，hash = pkg_dir 绝对路径的 FNV-1a（manifest.jai:296-304 注释：旧固定名在顺序/并发子进程间互相覆盖 + AV 瞬锁 + 静默读陈旧数据丢 workspace 成员；按 manifest 路径哈希后不同 manifest 永不撞名，同一 manifest 并发评估内容相同共享无害）。
- `load_package_manifest :: (cache_dir: string, pkg_dir: string) -> Package, bool`（manifest.jai:312-374），全流程：
  1. `package.jai` 不存在 → `.{}, false`；
  2. 建 cache 目录（recursive）；写评估器源文件（`build_eval_code`）；
  3. **重试循环**（manifest.jai:338-349）：`run_command("jai", temp_eval_src, "-import_dir", global_modules_dir, "-quiet")`（modules 目录 = exe 旁 `../modules`，manifest.jai:328-330 内联同 path_safety.jai:40-45 的推导）；
     - exit 0 → break；
     - **exit 2（写盘失败）且 attempts < 2 → 重试**（至多两次重试 = 共 3 次尝试；复用同一对临时文件名——同 manifest 同名、失败写盘内容不变，重试即覆盖）。评估器侧写盘失败 `exit(2)`（manifest.jai:84-91），旧实现静默忽略写盘结果导致父进程把陈旧/缺失数据当成功；
     - 其他非零（编译错等）→ 立即报错，**从不重试**；
  4. 读数据文件 → strict 解析 → `validate_jaix_marker` → `validate_transpile_pipeline`（manifest.jai:357-371）；
  5. `parsed.package.dir = pkg_dir`（**绝对路径回填**，此后所有路径解析以 pkg.dir 为锚）。

## 4. workspace.jai — 三态机与发现

### 4.1 成员路径校验面

- `workspace_relative_path_is_valid :: (path: string) -> bool`（workspace.jai:8-12）：非空、非绝对（含卷标）、无 `..` 逃逸分量；**`.` 与 `member_lib/.` 合法**（注释 workspace.jai:466-475：放行 `.` 让 `member_lib/.` 拼写能走到重复分支，由发现流程的 normalize + 查重收口）。
- `workspace_member_path :: (root_dir, relative_path) -> string`（workspace.jai:14-16）：正斜杠拼接。
- `workspace_path_already_seen :: (paths: [] string, candidate: string) -> bool`（workspace.jai:18-23）：`paths_equal` 比较（斜杠归一 + Windows 大小写不敏感）。

### 4.2 发现（discover_workspace）

`discover_workspace :: (root_dir, cache_dir) -> Workspace_Discovery, bool`（workspace.jai:29-106）：

- 根目录**双重检查**：先按拼写查（inspect_path_entry：存在 + 目录 + 非 symlink/junction），normalize 后再查一遍（workspace.jai:31-45）；
- 无 `package.jai` → `.{root_dir = root_abs, has_package = false}, true`（合法空态）；
- 根 manifest 无效 → `"Existing package.jai is invalid."`；
- `members` 先入根，`packages` 先入根包；**只迭代根包的 members 列表**（成员自己声明的 members 被静默忽略——test_monorepo.jai:87-100 钉住此行为）；
- 每个成员按序校验（workspace.jai:63-99）：路径合法性 → normalize 存在性 → **安全真实目录**（存在 + 目录 + 非 symlink/junction）→ `path_is_within(root_abs, member_abs)`（`"Workspace member escapes package root"`）→ 查重（`"Duplicate workspace member path"`）→ 有 `package.jai` → load 成员 manifest；
- **发现只加载 manifest 与校验成员根，绝不取依赖**（workspace.jai:25-28 注释：依赖准备是另一道命令前置）。

### 4.3 三态机

- `Workspace_Phase :: enum { EMPTY; DISCOVERED; PREPARED; }`（workspace.jai:108-112）。
- `Workspace_State :: struct { phase; discovery: Workspace_Discovery; prepared: Prepared_Workspace; }`（workspace.jai:114-118）。
- `ensure_workspace_discovered :: (root_dir, cache_dir, state: *Workspace_State, discover: #type (...) -> (Workspace_Discovery, bool) = discover_workspace) -> bool`（workspace.jai:120-136）：
  - `phase != .EMPTY` → 直接 true（**一旦发现，只跑一次**）；
  - 失败留 EMPTY；成功 → `.DISCOVERED` 并打印 `Package '%' (v%) discovered.`。
- `prepare_workspace :: (root_dir, cache_dir, state, resolve: #type (pkg) -> Artifact_Plan_Result = resolve_artifact_plans, prepare_dependencies: #type (root_dir, cache_dir, member_packages: [] Package) -> bool = resolve_and_fetch_dependencies, force_dependencies := false) -> bool`（workspace.jai:144-177）：
  - `.PREPARED` → true（幂等）；非 `.DISCOVERED` → 报错；
  - 先 resolve 产物计划（失败 → 报错返回）；
  - **依赖只在 `plans.count > 0 || force_dependencies` 时准备**（0 计划 = LIB 包默认不准备；`force_dependencies` 是 Test 用的——LIB 包测试程序经 import shim 引用依赖，workspace.jai:138-143 注释）；
  - **全部成功才发布**（workspace.jai:138-139 注释）：resolve + 依赖准备都成功才 `state.prepared = prepared; state.phase = .PREPARED`；失败留在 `.DISCOVERED`，`get_prepared_workspace` 拿不到任何半成品。
- `get_prepared_workspace :: (state: *Workspace_State) -> *Prepared_Workspace`（workspace.jai:179-182）：非 PREPARED → null。
- `ensure_workspace_prepared :: (...五个注入参数...) -> *Prepared_Workspace`（workspace.jai:194-207）：命令侧一站式入口，链式发现 + 准备，null = 失败（具体错误已由失败相位打印——不再有泛化「requires workspace preparation」守卫消息）；幂等（run 在 build 前置跑完后可再调）。

**三 seam** = `discover` / `resolve` / `prepare_dependencies` 三个可注入 `#type` 参数（workspace.jai:124, 148-149, 198-200），生产默认分别为 `discover_workspace` / `resolve_artifact_plans` / `resolve_and_fetch_dependencies`。

## 5. target.jai — 目标推导与产物计划

### 5.1 错误面

- `Target_Resolution_Error :: enum`（target.jai:8-21）：`NONE; INVALID_PACKAGE_ROOT; INVALID_PACKAGE_NAME; INVALID_PACKAGE_VERSION; INVALID_TARGET_NAME; INVALID_TARGET_SOURCE; DUPLICATE_TARGET_NAME; SOURCE_NOT_FOUND; SOURCE_NOT_REGULAR; SOURCE_OUTSIDE_PACKAGE; LIBRARY_TARGET_CONFLICT; MODULE_ENTRY_NOT_FOUND;`
- `Target_Resolution_Result :: struct { success; targets: [] Effective_Target; error; error_message; package_type: Package_Type }`（target.jai:23-30）；`Artifact_Plan_Result :: struct { success; plans: [] Artifact_Plan; error; error_message; package_type }`（target.jai:32-39）。`package_type` = UNSPECIFIED 按约定推导后的包角色。

### 5.2 校验与推导

- `validate_package_identity :: (pkg) -> Target_Resolution_Result, bool`（target.jai:49-60）：name 是 `path_is_portable_filename`；version 非空；`pkg.dir` 是存在的真实目录。
- `make_effective_target :: (pkg, name, main_file) -> Effective_Target, Target_Resolution_Error, string`（target.jai:62-97）：name 便携文件名；main_file 必须 `path_is_portable_relative_jai`（相对、无逃逸、`.jai` 尾）；源文件存在、非 symlink/junction/目录、normalize 后在 `path_is_within(package_root)`。
- `library_import_entry :: (pkg) -> string, bool`（target.jai:102-113）：**先包根 `module.jai`，再 `src/module.jai`**；命中要求存在 + 非目录 + 非 symlink/junction。
- `derive_package_type :: (pkg) -> Package_Type`（target.jai:118-125）：声明 targets > 0 → BIN；`src/main.jai` 存在 → BIN；有 import entry → LIB；否则 BIN（无事可建的包）。
- `validate_library_package :: (pkg) -> Target_Resolution_Result`（target.jai:129-139）：LIB 声明 targets → **`LIBRARY_TARGET_CONFLICT`**（`"Library package '%' cannot declare executable targets."`）；无 import entry → `MODULE_ENTRY_NOT_FOUND`（`"Library package must provide module.jai at the package root or src/module.jai."`）。

### 5.3 推导序四分支（resolve_effective_targets，target.jai:141-189）

1. `validate_package_identity` 先过；
2. `pkg.type == .UNSPECIFIED` → `derive_package_type`；
3. **type == .LIB**（显式或推导）→ `validate_library_package` → 成功即 0 targets、package_type = .LIB；
4. **无声明 targets**（BIN）→ 隐式 `src/main.jai`：存在且是常规文件 → 以 `pkg.name` 为名建 target（target.jai:156-169）；不存在 → 0 targets 成功返回；存在但是 symlink/junction/目录 → `SOURCE_NOT_REGULAR`（`"Implicit src/main.jai is not a regular file."`）；
5. **显式 targets** → 逐个：name/main_file 空 → `INVALID_TARGET_NAME`（`"Explicit target % has required name and main_file fields."`）；与前面声明 **`equal_nocase` 撞名 → `DUPLICATE_TARGET_NAME`**（`"Target name collides with another target: %"`——声明唯一性大小写不敏感，但 run 选择时拼写精确区分，见 §11）；再走 `make_effective_target`。

### 5.4 产物计划

- `make_artifact_plan :: (pkg, target) -> Artifact_Plan, bool`（target.jai:191-209）：产物**统一落在 `<root>/target/` 根**（target_dir = `<package_root>/target`）；Windows 产物名 `<name>.exe`，其他平台裸 `<name>`。
- `resolve_artifact_plans :: (pkg) -> Artifact_Plan_Result`（target.jai:211-224）：resolve_effective_targets → 每 target 一个 plan。
- `revalidate_artifact_plan :: (plan, package_root) -> bool`（target.jai:226-238）：包根安全目录；`target_dir`、`artifact_path` 都在根内；target_dir 若存在必须是真实目录（非 symlink/junction）；artifact 若存在不能是目录/symlink/junction；name 便携、main_file 便携相对 `.jai`。这是 build/run 共用的大门。

## 6. dependency.jai — shim 生成/消费与相对 DEP 纪律

### 6.1 依赖目录与 import 目录

- `packages_dir :: (root_dir: string) -> string`（dependency.jai:58-60）：**`<root>/target/packages`**（Build_Driver 拆除后 packages_dir 不再是结构体字段，由本模块统一派生）。
- `compiler_import_directories :: (packages_dir: string) -> [..] string`（dependency.jai:70-81）：每次编译在 jai 默认之外的 import 目录 = `juice_modules_dir()`（Testing.jai/Juice.jai，存在才加）+ `packages_dir`（存在才加）。**从 build.jai 移来——build/test 共享**（旧 bug：test 只注入 modules 目录，根测试程序的 `#import <依赖名>` 永远解析失败，dependency.jai:66-69 注释）。

### 6.2 来源类型与 shim

- `Source_Type :: enum { LOCAL_PATH; GIT_URL; }`（dependency.jai:10-13）。
- `detect_source_type :: (source: string) -> Source_Type`（dependency.jai:15-29）：`""` 或 `file://` 前缀 → LOCAL；git schema 表 `https:// http:// git:// ssh:// git+https:// git+ssh://` → GIT；`git@` + 含 `:` → GIT；`.git` 尾 → GIT；**其余全 LOCAL**。
- `clean_local_path :: (source) -> string`（dependency.jai:31-34）：剥 `file://`（advance 7）。
- `find_files_recursive :: (dir, filename) -> [..] string`（dependency.jai:47-52）：visit_files 递归按 `short_name == filename` 收集（find_package_in_repo 用）。
- `find_package_in_repo :: (cache_dir, repo_dir, target_pkg_name) -> string, bool`（dependency.jai:83-93）：递归找所有 `package.jai`，逐个 load 并按 name 匹配。

### 6.3 shim 生成（ensure_import_shim）

- `dependency_shim_content :: (name, entry) -> string`（dependency.jai:112-114）：shim 格式单一来源 = `"// Generated by juice: import shim for package '%1'.\n#load \"%2\";\n"`。
- `ensure_import_shim :: (packages_dir, name, source_dir) -> bool`（dependency.jai:123-142）：
  1. `normalize_existing_path(source_dir)`（失败 → false）；
  2. 候选入口按序探测：`<abs>/module.jai`、`<abs>/src/module.jai`、单文件 `<abs>/<name>.jai`；命中即写 `<packages_dir>/<name>.jai`；
  3. 三种布局都无 → **return true**（不报错，留解析给编译器自己的错误——所以普通 Jai 模块无 manifest 也能当依赖）。
  - **为什么是 shim 而非链目录**（dependency.jai:116-122 注释）：编译器 canonicalize junction 并拒绝「import 名 ≠ 真实目录名」；目录放 shim 旁会撞「单文件与目录并存」冲突。所以每个依赖恰好一个生成 shim，按路径 #load 真实入口。
- **相对 DEP 纪律**：`fetch_dependency` 对 LOCAL_PATH 直接 `ensure_import_shim(packages_dir(root_dir), dep.name, clean_path)`（dependency.jai:430-432）；shim 内 `normalize_existing_path` → `get_absolute_path` 以**进程 cwd** 为锚解析相对 source。juice 永不 chdir、root_dir = 调用 cwd（main.jai:39），所以**相对 dep.source 恒以包根为基准**。成员不走此路——见下。

### 6.4 工作区成员：link 不 fetch

- `resolve_and_fetch_dependencies :: (root_dir, cache_dir, member_packages: [] Package) -> bool`（dependency.jai:96-99）：建 packages_dir 后调 fetch_workspace_dependencies。**消费发现快照，绝不重执行 manifest**。
- `link_workspace_member_dependency :: (root_dir, member: Package) -> bool`（dependency.jai:104-106）：= `ensure_import_shim(packages_dir(root_dir), member.name, member.dir)`（member.dir 已是绝对路径）。
- `find_workspace_member :: (member_packages, name) -> Package, bool`（dependency.jai:393-398）：按 name 精确匹配。
- `fetch_workspace_dependencies :: (root_dir, cache_dir, member_packages, fetch = fetch_dependency, link_member = link_workspace_member_dependency) -> bool`（dependency.jai:400-424）：遍历所有成员包的 dependencies；名字命中成员 → **link**（`"Failed to link workspace member"`）；否则 → fetch（`"Failed to fetch dependency"`）；任一失败立即传播 false。

### 6.5 git 依赖

- `fetch_dependency`（dependency.jai:426-456）GIT 分支：缓存目录 `<cache_dir>/git_repos/<sanitized>`；`ensure_git_repo_cloned`；`target_name = dep.package != "" ? dep.package : dep.name`；`find_package_in_repo`；找不到时兜底「repo 根有 module.jai 即普通 Jai 模块」；否则 `"Package '%1' not found in Git repo %2!"`。
- `get_git_repo_cache_path :: (base_dir, url, version) -> string`（dependency.jai:472-488）：非字母数字 → `_`；version 非空追加 `_<version>`。
- `ensure_git_repo_cloned :: (url, version, dst_dir) -> bool`（dependency.jai:490-504）：已存在 → `git -C dst fetch --all`；否则 `git clone url dst`；version 非空 → `git -C dst checkout version`。
- `delete_directory_full :: (path) -> bool`（dependency.jai:506-517）：不存在且非 symlink → true；Windows `cmd /c rmdir /S /Q` + **反斜杠路径**（rmdir 把正斜杠段解析成选项开关）；POSIX `rm -rf`。

### 6.6 依赖 strip front（prepare_dependency_strip_views）

- `shim_load_target :: (source: string) -> string, bool`（dependency.jai:167-180）：lex shim，找**第一个** `#load <STRING> ;` 三元组，decode 出 #load 字面目标；形状不匹配（手写 shim）→ false（保持原样，留给编译器报错）。
- `get_filename`（dependency.jai:183-189）、`Shim_Scan_Context`/`shim_scan_visitor`/`sort_shim_names`/`collect_shim_names`（dependency.jai:191-223）：依赖目录下**直接子级**每个 `*.jai`（非目录、非 `.` 开头）去扩展名，**字典序**。
- `prepare_dependency_strip_views :: (root_dir, transpile: #type (file, load_targets, pipeline) -> Build_File_Output) -> bool`（dependency.jai:244-286）：
  - packages 目录不存在 → true（no-op）；
  - 每 shim：读 → `shim_load_target` → 入口非真实常规文件或解析失败 → **跳过**；`probe_package_closure(入口目录, 入口文件名)`（生产实现在 transpile_front.jai）；失败 → false；`closure_has_tests` 否 → **跳过**（零 transpile、零缓存，shim 逐字节不动）；
  - 有 test 块 → 整个闭包 STRIP 视图（`Strip_View_State`：`transpile_dir = transpile_tree_dir(root_dir)`、`dep_name = name`、`layout = .CONTENT_ADDRESSED`），**DFS 前序入口先算**（`view_of_file(*state, 0)`，children-before-parents 的 Merkle 链由 view_of_file 内部保证）；落地 `target/transpile/deps/<name>/<key>/...`；**shim 重写**指向入口视图；
  - 依赖包的 pipeline 恒为默认（依赖 manifest 不保留到准备之后——spec 0060 决策 6，dependency.jai:240-243 注释）。
  - Build 与 Test 共享此 front（build.jai:225 调用点）；依赖内 test 块既不发现也不执行，只求可编译。

## 7. commands/command.jai + registry.jai + dispatcher.jai

### 7.1 声明面

- `Command_Handler :: #type (ctx: *Command_Context, arguments: [] string) -> bool;`、`Command_Argument_Validator :: #type (arguments: [] string) -> bool;`（command.jai:1-2）。
- `Command_Context :: struct { root_dir: string; cache_dir: string; workspace: Workspace_State; }`（command.jai:4-12）——**仅有的两个进程级路径**（Build_Driver 拆除幸存者），派生路径（packages_dir 等）由 owner 派生。
- `Command :: struct { name; description; usage; prerequisites: [] string; handler; validate_arguments = command_accepts_no_arguments; }`（command.jai:14-21）。
- `command_accepts_no_arguments`（command.jai:23-25）、`command_arguments_are_valid :: (command, arguments) -> bool`（command.jai:27-31）：validator 不过 → 打印 `Usage: ...` → false。
- `COMMAND_REGISTRY :: Command.[ BUILD_COMMAND, RUN_COMMAND, CLEAN_COMMAND, TEST_COMMAND ]`（registry.jai:3-8）。

### 7.2 校验（validate_registry）

`validate_registry :: (registry: [] Command) -> Dispatch_Result`（dispatcher.jai:35-59）：
- 空 name / null handler / null validate_arguments → `INVALID_COMMAND`；
- 同名 → `DUPLICATE_COMMAND_NAME`；
- 前置命令不存在 → `MISSING_PREREQUISITE`（`"Command '%' has unknown prerequisite: '%'"`）。

### 7.3 计划 DFS（plan_command）

`Dispatch_State :: enum { UNVISITED; VISITING; COMPLETED; }`（dispatcher.jai:22-26）。

`plan_command :: (registry, cmd: *Command, arguments: [] string, states: *Table(string, Dispatch_State), ordered: *[..] Command) -> Dispatch_Result`（dispatcher.jai:64-92）：
- **VISITING → `CYCLE_DETECTED`**（`"Cycle detected involving command: '%'"`）；
- COMPLETED → 直接成功（**菱形去重**：共享前置只计划一次）；
- **计划期就做参数校验**（`command_arguments_are_valid`）——在任何 handler 执行前（dispatcher.jai:174-179 测试钉住「参数非法先于前置」）；
- 递归计划前置时**恒传空参数** `string.[]`（dispatcher.jai:86）——只有被请求命令收到用户参数；
- 后序追加 `ordered`（子先父后 → 执行序 = 前置先跑）。

### 7.4 执行（dispatch_command）

`dispatch_command :: (registry, command_name, ctx: *Command_Context, arguments) -> Dispatch_Result`（dispatcher.jai:94-121）：
1. `validate_registry` → 2. 找命令（`find_command` dispatcher.jai:28-33；未知 → `UNKNOWN_COMMAND` + `print_usage` dispatcher.jai:123-129）→ 3. `plan_command` → 4. 按 ordered 序执行；**仅目标命令拿用户参数**（dispatcher.jai:113），handler false → 目标命令 `HANDLER_FAILED`、前置 `PREREQUISITE_FAILED`（`"Command '%' failed while executing '%'."`）。

## 8. commands/build.jai — 构建八步

`BUILD_COMMAND`（build.jai:9-15）：无前置；`build_command`（build.jai:17-31）：参数守卫 → `ensure_workspace_prepared` → `build_prepared_workspace` → 无计划时打印区分消息（LIB → `"Library package '%'; nothing to build."`；否则 `"No executable targets; nothing to build."`）→ `"Build completed successfully!"`。

`build_prepared_workspace` 的三个 seam（build.jai:208-213）：
- `transpile: #type (file: Build_Source_File, load_targets: [] Load_Target, pipeline: [] Transpile_Plugin = .[]) -> Build_File_Output = transpile_build_file`
- `compile: #type (root_dir, plan: Artifact_Plan, entry: string) -> bool = compile_artifact_plan`
- `prestep: #type (prepared, transpile) -> bool = run_jaix_prestep`（jaix_front.jai）

按执行序的八步（对应 1a 的 b1-b8 视角）：

**b1 命令入口**：`build_command`（build.jai:17-31），如上。

**b2 工作区准备**：`ensure_workspace_prepared`（workspace.jai:194-207）——发现 + 计划解析 + 依赖准备三合一，幂等。

**b3 计划重校验**：`revalidate_build_plans :: (prepared: *Prepared_Workspace) -> bool`（build.jai:40-60）——**编译任何东西之前整体重验构建输入**（不安全计划不可能产出半截构建）：包根仍是安全真实目录（`"Package root changed or is unsafe before build."`）；每 plan 过 `revalidate_artifact_plan`（`"Artifact path became unsafe before build"`）；每 plan 的源文件仍存在且非常规文件排除项（`"Target source became unsafe before build"`）。

**b4 依赖 strip front**：`prepare_dependency_strip_views(prepared.discovery.root_dir, transpile)`（build.jai:225，实现 dependency.jai:244-286）——依赖经 shim 的闭包含 test 块则整闭包 STRIP + shim 重写；jaix 标记作用域只有根包（spec 055 决策 9），依赖不走 jaix。

**b5 jaix pre-step（有标记时）**：`prepared.discovery.root_package.jaix.config != ""` → `prestep(prepared)`（build.jai:233-235）——整包扫描 jaix-transpile 进 `target/jaix/` 镜像；在入口循环前跑，让 b6 直接选镜像入口；无标记包永不触达（零行为变化）。实现：`run_jaix_prestep`（jaix_front.jai）。

**b6 入口选择（每 plan）**：`build_plan_entry :: (prepared, plan, transpile) -> (string, bool)`（build.jai:166-197）：
- jaix 标记 → 直接返回 `jaix_mirror_view_path(root_dir, main_file)`（镜像入口；**不 probe、不 strip**，镜像内 #load 链自然解析）；
- 否则 `probe_build_closure`（build.jai:148-152：pipeline = `resolve_transpile_pipeline(root_package.transpile.plugins)` 声明序；`probe_package_closure(root_dir, main_file)` 生产实现在 transpile_front.jai）：
  - 闭包无 test → 返回**原始入口** `plan.target.source_path`（零 transpile、零缓存）；
  - 有 test → `Strip_View_State`（`transpile_dir = transpile_tree_dir(root_dir)`、`layout = .CONTENT_ADDRESSED`、pipeline 声明序、空管线 = 默认）→ `closure_index` 找入口 → `view_of_file(*state, entry_index)`（DFS 前序：**children before parents**，load 改写嵌入子视图路径 = Merkle 链）→ 入口文件视图即编译入口。
- 非字面量与包外 #load 目标**从不视图化/改写**（那里面的 test 块表现为普通 jai 编译错误）；循环 #load 图 → 专有诊断失败（build.jai:447-461 测试）。

**b7 编译循环（fail-fast）**：`for plan, index: prepared.artifact_plans { compile(root_dir, plan, entries[index]) }`（build.jai:246-248）——任一失败立即返回 false，不编译剩余。

**b8 编译单计划**：`compile_artifact_plan :: (root_dir: string, plan: Artifact_Plan, entry: string) -> bool`（build.jai:62-112）：
1. 编译入口存在性检查（**由 transpile front 选定的入口**：原始入口 / strip 视图 / jaix 镜像视图，build.jai:63-66 注释；`path_exists_as_regular_file` 不过 → `"Target source file not found"`）；
2. `make_directory_if_it_does_not_exist(plan.target_dir, recursive = true)`（build.jai:73）——**这是 LNK1104 面**：链接器要求 target 目录先存在（bootstrap 侧同款纪律在 juice/build.jai:154-156 有注释「make sure the target directory exists so the linker does not error with LNK1104」）；
3. 打印 `[juice Build] Compiling Target '%' (%) -> target/...`；
4. **生成 metaprogram**：`metaprogram_path = <target_dir>/build-<name>.jai`（会话产物，与 test 命令 driver/metaprogram 同族）；组装 `Compiler_Metaprogram_Options`（build.jai:86-95）：`workspace_name = "Juice Build"`、`executable_name = plan.target.name`、`output_path = plan.target_dir`、`intermediate_path = plan.target_dir`（**jai 无 intermediate_path 命令行旗标，靠 metaprogram 设置**——编译器中间产物 .obj/.lib/.added_strings_* 落 target 目录而非入口旁 .build，Clean 随 target/ 一并删除，build.jai:80-85 注释）、`import_dirs = compiler_import_directories(packages_dir(root_dir))`、`build_file = 入口`、`testing_view_dir = testing_module_strip_view_dir(root_dir, <modules>/Testing.jai)`（Testing 模块编译视图特例，§13.1）；`generate_compiler_metaprogram(metaprogram)`（metaprogram.jai:63）→ `write_entire_file`；
5. **spawn jai**：`run_command("jai", metaprogram_path)`（build.jai:101）——**无 working_directory，继承 juice cwd**；exit != 0 → `"Compilation failed for target '%'."`；
6. **artifact 检查**：`file_exists(plan.artifact_path)` 不过 → `"Compiler did not produce expected artifact: %"`（build.jai:107-110）。

## 9. commands/clean.jai

- `CLEAN_COMMAND`（clean.jai:6-12）：无前置、无参数。
- `clean_command`（clean.jai:14-23）：参数守卫 → `discover_workspace(ctx.root_dir, ctx.cache_dir)` → 失败打印 `"Clean discovery failed; no files were deleted."` → `clean_discovered_workspace`。
- `clean_path_is_safe :: (path) -> bool`（clean.jai:25-33）：**不存在 → 安全（true）**；symlink/junction → 拒绝（`"Refusing to delete symlink/junction"`）；否则必须是目录。
- `clean_discovered_workspace :: (root_dir, discovery, validate_path = clean_path_is_safe, delete_path = delete_directory_full) -> bool`（clean.jai:35-70）：
  - **收集**：有 manifest → 根包 + 每个成员包的 `<dir>/target`；无 manifest → `<root>/target`。legacy `result/` 与 `.packages` **永不触碰**（clean.jai:44-46 注释）；
  - **先全部校验，后删除**（clean.jai:55-58）——任一路径校验不过，一个都不删；
  - 删除循环**失败不中断**：逐个删、失败记 `all_ok = false` 并打印 `"Could not delete: %"`，继续删剩下的（clean.jai:60-69）；全成 → `"[juice Clean] Workspace cleaned."`。

## 10. commands/run.jai

- `RUN_COMMAND`（run.jai:7-14）：`prerequisites = string.["build"]`；`validate_arguments = run_arguments_are_valid`（≤1 参数，run.jai:16-18）。
- `run_command_handler`（run.jai:20-26）：`ensure_workspace_prepared`（build 前置已跑过则幂等拿回现成状态）→ `target_name = arguments.count == 1 ? arguments[0] : ""` → `run_prepared_workspace`。
- `select_artifact_plan :: (plans: [] Artifact_Plan, package_name: string, requested_target: string) -> Artifact_Plan, bool`（run.jai:30-45）：
  1. 0 计划 → false；
  2. 指定 target → **拼写精确（大小写敏感）**遍历匹配（注释 run.jai:28-29：声明唯一性大小写不敏感、命令行拼写精确）；
  3. 未指定且恰好 1 计划 → 该计划；
  4. 未指定多计划 → 名字 == 包名者；否则 false。
- `run_artifact_plan :: (plan, package_root) -> bool`（run.jai:47-60）：`revalidate_artifact_plan`（不安全 → `"Refusing unsafe artifact path"`）→ `file_exists`（缺 → `"Could not find executable to run"`）→ 打印 `[juice Run] Launching % ...` → `run_command(plan.artifact_path)`（**继承 cwd = 包根**，§14）→ `exit_code == 0`。
- `run_prepared_workspace :: (prepared, requested_target, launch = run_artifact_plan) -> bool`（run.jai:62-79）：选择失败的三条消息：0 计划 → `"Package has no executable target to run."`；未指定多计划 → `"Multiple targets exist; select one explicitly or define a target named '%'."`；指定未命中 → `"Unknown binary target: %"`。

## 11. metaprogram.jai — 编译器 metaprogram 生成器

- **单一生成器**（旧有两个生成器 + bootstrap 手写对称副本，ADR 0006 收敛后 skeleton 与 `""` 哨兵只在本文件）。**必须 test-free**（bootstrap `#load` 它；测试在 tests/metaprogram_tests.jai，metaprogram.jai:9-12）。
- `Compiler_Metaprogram_Options :: struct { workspace_name: string; no_output: bool = false; executable_name: string = ""; output_path: string = ""; intermediate_path: string; import_dirs: [] string; build_file: string; testing_view_dir: string = ""; very_optimized: bool = false; }`（metaprogram.jai:51-61）。
- `generate_compiler_metaprogram :: (options) -> string`（metaprogram.jai:63-122）：
  - 骨架：`#import "Basic"; #import "Compiler";` → `#run { set_build_options_dc(.{do_output=false}); workspace := compiler_create_workspace(...); ... }`；
  - **两种字节锁定形状**（metaprogram.jai:22-31）：可执行形状（对齐的 output_executable_name/output_path/intermediate_path 三行、无 output_type 行）与 test 形状（`output_type = .NO_OUTPUT` + 不对齐 intermediate_path 行、无可执行名/路径行）；test 形状被 `tests/data/transpile/golden/*/first.jai` 字节锁定，可执行形状被 tests/metaprogram_tests.jai 内联锁；
  - import 序：先 `.. options.import_path`（默认），`testing_view_dir != ""` 时**前插**视图目录（`#import "Testing"` 解析到 test-free 视图而非模块源），再逐条 `options.import_dirs`；
  - `very_optimized` → 额外 `set_optimization(*options, .VERY_OPTIMIZED)` 一行（bootstrap release 路径；默认不 emit，保持既有消费方字节不变）；
  - 消息循环只消费消息（`compiler_wait_for_message`，ERROR 忽略、COMPLETE break）——jai 对 intercepted workspace 出错时自己非零退出；**metaprogram 里调 exit() 会先杀进程吞掉 jai 收集的 print 输出**（metaprogram.jai:104-107 注释）。
  - **哨兵约定**：`testing_view_dir == ""` = 「Testing 模块编译视图特例禁用」（metaprogram.jai:33-37）。
- `bootstrap_compiler_metaprogram_options :: (root, entry, testing_view_dir, is_release) -> Compiler_Metaprogram_Options`（metaprogram.jai:134-152）：**output_path/intermediate_path 从根派生为绝对路径**——生成的 metaprogram 的子 jai 会把 #run 工作目录切到 metaprogram 自身目录（target/），相对 `"target"` 会落一层到 `target/target/`（058 偏差 ④）；import_dirs = `<root>/src`、`<root>/modules`、`<root>`。

## 12. scan_walk.jai — 共享包扫描骨架

- 一个 walk 实现、两个消费包装（test 命令 `collect_test_files` 与 jaix pre-step `collect_jaix_files`），spec 054 决策 7 / 票 0057（scan_walk.jai:1-29）。
- `Scan_File :: struct { rel_path: string; abs_path: string; }`（scan_walk.jai:41-44）；`Scan_Entry { short_name; full_name }`（scan_walk.jai:48-51）。
- `Scan_Walk_Context :: struct ($T: Type) { root; files: [..] Scan_Entry; dirs: [..] Scan_Entry; user_data: T; dir_excluded; file_excluded; }`（scan_walk.jai:56-63）——Jai 无闭包，排除谓词以 proc 值 + 消费方上下文指针注入（pre-step seam 姿态）。
- `collect_scan_files :: (root, user_data: $T, dir_excluded, file_excluded) -> [] Scan_File, bool`（scan_walk.jai:70-86）：visit_files 递归（不跟 symlink）；**排除的目录剪掉整棵子树**（`descend_into_directory = false`）；根不可扫描 → ok = false（失败通道，消息归消费方）。
- 确定性 DFS 枚举：`enumerate_scan_files`（scan_walk.jai:129-160）——每目录**文件先（字典序），再子目录（字典序）**；子目录反序入栈保证弹出有序。test 命令的 transpile/call/report 顺序与 jaix pre-step 的 spawn 顺序都由此派生。
- 路径助手：`scan_entry_parent`（scan_walk.jai:109-113，去尾分隔符）、`scan_rel_path`（scan_walk.jai:117-123）。
- **jaix driver litter 谓词**（spec 054 决策 5，票 0058）：`JAIX_DRIVER_MARKER :: "// jaix transpile driver"`（scan_walk.jai:193）、`DRIVER_HEAD_SCAN_LIMIT :: 1024`（scan_walk.jai:198）、`is_jaix_driver_litter :: (path) -> bool`（scan_walk.jai:200-220）：只读**头部 1024 字节**（热路径部分读），逐行找**行首**（列 0）以 marker 开头的行；CRLF 容忍（行尾 \r 剥掉）；协议版本不参与匹配（跨 jaix 版本稳定）；**内容判据而非名字判据**，且不设 jaix 标记门槛（legacy 无点前缀 hash 命名 litter 也排除）；不可读文件 = 不是 litter（真诊断归消费方）。

## 13. transpile_front.jai（相关段）

### 13.1 testing_module_strip_view_dir（:327-355）

`testing_module_strip_view_dir :: (package_root: string, module_source: string, error_prefix: string = "[juice ERROR] ") -> string`（transpile_front.jai:327）：

- **Testing 模块 STRIP 特例**（test 侧特例的镜像，合并到此处使 bootstrap 与 Build 命令共享一份——旧时各持对称副本）：模块源内联 test 块后 jai 无法直接编译，任何解析到 `#import "Testing"` 的构建必须解析到 test-free STRIP 视图；
- 每次编译前重写 `<package_root>/target/testing-module/Testing.jai`（**会话产物**，与 test 命令编译视图同路径——test 写 EXPAND、build/bootstrap 写 STRIP，各自运行前重写，transpile_front.jai:317-320 注释）；
- 流程：`front_view_exists` 否 / 读失败 → `""`；`pipeline_has_anchors(default_transpile_pipeline(), source, "modules/Testing.jai")` 否（test-free）→ `""`；否则 STRIP transpile，诊断非空 → 带 error_prefix 打印 → `""`；建目录、写视图 → 返回目录；
- **返回 `""` 哨兵 = 特例禁用**，metaprogram 输出与特例前字节一致（零变化）；module_source 由消费方给：bootstrap 传 cwd 相对 `"modules/Testing.jai"`，Build 命令传 `juice_modules_dir()` 派生的绝对路径（bootstrap 不能引用 path_safety 的运行时代码，transpile_front.jai:322-325 注释）。

### 13.2 transpile_build_file（:289-308，build strip 生产步）

`transpile_build_file :: (file: Build_Source_File, load_targets: [] Load_Target, pipeline: [] Transpile_Plugin = .[]) -> Build_File_Output`（transpile_front.jai:289）：读源失败 → 诊断（`无法读取源文件`）；`Transpile_Context { mode = .STRIP; path = file.rel_path; load_targets; plugins = pipeline 拷贝 }` → `transpile_source` → `output.key = transpile_view_key(rel_path, source, .STRIP, load_targets, JUICE_VERSION, ctx.plugins)`（缓存键含 pipeline 描述 = 内容寻址；load 改写表嵌入子视图 hash 目录 → **Merkle 链**，依赖序可算，transpile_front.jai:280-287 注释）。原在 build.jai，移来供 bootstrap 与 Build 命令共享同一生产步。

## 14. 子进程 CWD 纪律（横切）

juice **从不 chdir**；包根 = 进程 cwd（main.jai:39）。各子进程：

| 子进程 | 调用点 | CWD |
|---|---|---|
| manifest 评估器 | `run_command("jai", temp_eval_src, "-import_dir", ..., "-quiet")` manifest.jai:340 | 继承（包根）；评估器只打印结构体字段，不做路径解析 |
| 构建编译器 | `run_command("jai", metaprogram_path)` build.jai:101 | 继承（包根）；**jai 的 #run 会切到 metaprogram 自身目录（target/）**——因此 metaprogram 的 output_path/intermediate_path/build_file 必须绝对（metaprogram.jai:17-20、build.jai:140-144 同注，058 偏差 ④；bootstrap build.jai:140-144 同） |
| 运行产物 | `run_command(plan.artifact_path)` run.jai:58 | 继承（包根）——**产物以包根为 cwd 运行** |
| git clone/fetch/checkout | dependency.jai:492-501 | 继承；用 `git -C dst_dir` 显式指目录 |
| 删除目录 | `cmd /c rmdir /S /Q <反斜杠路径>` dependency.jai:511 | 继承；路径必须反斜杠 |
| jaix spawn | jaix_front.jai（pre-step 每文件一次） | 继承；jaix CLI 的 driver litter 落在 spawn cwd（test_support.jai:1047-1052 注释） |
| 测试内子进程 | `run_juice_child`（test_support.jai:372-381）、`run_juice_test`（test_support.jai:117-126） | **显式** `working_directory = fixture_abs` + `capture_and_return_output = true` |

## 15. path_safety.jai — 检查面全集

- `Path_Entry_Check :: struct { exists; is_directory; is_symlink; is_junction; had_error; }`（path_safety.jai:12-18）。
- `path_slashes`/`path_backslashes`（path_safety.jai:20-34）：全量替换。
- `juice_modules_dir :: () -> string`（path_safety.jai:40-45）：运行中 exe 旁 `../modules`（Testing.jai/Juice.jai）；一处推导、三处调用（build/test 编译 import 目录 + Testing 模块源查找 + manifest 评估子进程 `-import_dir`）。
- `paths_equal :: (left, right) -> bool`（path_safety.jai:47-55）：斜杠归一 + Windows 大小写不敏感。
- `lexical_absolute_path`（path_safety.jai:65-72）：相对 → 前缀 cwd；`parse_path(reduce = true)` 归一。
- `inspect_path_entry :: (path) -> Path_Entry_Check`（path_safety.jai:74-116）：空 → 全 false；**枚举父目录**（非递归，visit_symlinks = true、follow_directory_symlinks = false——能看到悬空链接，file_exists 会跟链接，path_safety.jai:63-64 注释）按 `paths_equal` 匹配；父目录不可扫描且没找到 → `had_error`；Windows 上 reparse point 且非 symlink → `is_junction`（GetFileAttributesW）。
- `path_is_symlink`（:118-121）= symlink **或 junction**。
- `path_exists_as_directory`（:123-126）/ `path_exists_as_regular_file`（:128-131）：**都拒绝 symlink/junction**——「安全真实目录/常规文件」语义。
- `path_is_absolute_portable`（:133-141）：`/`、`\` 开头，或含 `:`（卷标 C:foo 也算绝对）。
- `path_has_escape_component`（:143-150）：分量含 `..`。
- `path_is_portable_filename`（:152-168）：拒绝空/`.`/`..`、尾 `.`/空格、控制字符、`/\:*?"<>|`、Windows 保留名 CON/PRN/AUX/NUL、COM1-9/LPT1-9（大写比较）。
- `path_is_portable_relative_jai`（:170-175）：相对 + 无逃逸 + `.jai` 尾（大小写不敏感）。
- `path_is_within :: (root, candidate) -> bool`（:177-190）：get_absolute_path 归一（失败用词法绝对路径兜底）→ 等则 true，root 补尾 `/` 后前缀 `paths_equal`。
- `normalize_existing_path :: (path) -> string, bool`（:192-196）：get_absolute_path + 正斜杠。

## 16. 测试面

### 16.1 test_support.jai（tests/，1094 行，**0 个 test 块**——纯支撑，test-free）

约定（test_support.jai:1-33 头部注释）：**测试共享声明只允许在本文件**；不被 main.jai #load → 不在 Build 入口闭包 → 永不 transpile/编译/进 release；含 Testing 模块自测支撑段（机器 marker `__testing_module_support_begin__/__end__` 框住，test.jai 的 `testing_module_support_block` 按 marker 整段剪进模块编译视图，模块是 sealed scope，段内声明必须全在 marker 间——test_support.jai:43-53）。

E2E 助手签名与语义（团队要求重点）：

- `juice_root :: () -> string`（:75-83）：测试程序编译期在 jai 编译器子进程内执行，cwd 是入口文件目录（target/transpile）而非调用 cwd；从 `get_build_options().intermediate_path` 剥尾分隔符得包根（自包含形状——不进 src/path_safety 依赖）。
- `juice_exe :: () -> string`（:107-109）：`<root>/target/juice.exe`。
- `run_juice_child :: (fixture: string, command: string, target := "") -> Process_Result, string, string`（:372-381）：跑真 `juice.exe <command> [target]`，`working_directory = <root>/tests/data/<fixture>`，capture；返回 `(result, stdout, stderr)`。
- `run_juice_test :: (fixture, pattern := "", fixture_base := "tests/data/") -> Process_Result, string, string`（:117-126）：同上但跑 `juice test [pattern]`。
- `expect_exit :: (name: string, result: Process_Result, want: s32, tag := "child") -> bool`（:138-142）：`result.type == .EXITED && result.exit_code == want`；失败打印 `[<tag> <name>] exit result <type>/<code>, want <want>`。
- `normalize_crlf :: (s: string) -> string`（:148-171）：CRLF → LF（子进程原生行尾无关比较）。
- `output_matches :: (name, output, needles: [] string, want := true, tag := "child") -> bool`（:178-189）：CRLF 归一后逐 needle 检查存在/不存在（`want = false` 断言缺席）；失败打印整段 output。
- `child_output_contains :: (name, output, needle) -> bool`（:383-387）：仅存在性；失败打印 `[build child <name>] output missing '<needle>'` + 全 output。
- `fixture_line_col :: (file, needle) -> (line: s64, col: s64)`（:195-209）：1-based 行列，构建期望失败行而不硬编码行号。

其他关键支撑：

- seam fakes：`test_launch_*`（:219-229，run launch 记录）、`test_clean_*` + `reset_clean_test` + `test_validate_clean_path`/`test_delete_clean_path`（:231-256，`deleted_too_early` 记录「校验完才删」违约）、`test_compile_*` + `test_compile_artifact`（:258-270）、`fake_key`（:279-285，扁平无碰撞 fake 键，测试重建期望路径用同一函数）、`fake_build_transpile`（:305-319，记录 files/rewrites/pipelines + 罐装 view + 可选诊断）、`fake_build_compile`（:325-329）、`reset_build_seam`（:331-342）、`build_seam_plan`/`build_seam_prepared`/`build_seam_write`（:347-370，真实临时 fixture 上建计划/写文件——探针仍跑真实文件系统）、`fake_transpile`/`fake_compile`/`seam_files`/`seam_prepared`/`reset_seam_test`（:561-632，test 命令 seam）、`file_contains`（:634-638）、`make_test_link`（:642-658，cmd `mklink /J`//`/D` 反斜杠；机器拒绝（需开发者模式/提权）→ 返回 false → 测试走 SKIP 约定）、`Dir_Scan`/`dir_scan_entries`（:664-681）、`string_less`/`sort_strings`（:688-707，字节级字典序）。
- 分发测试登记处：`test_handler_a..d/fail`、`reset_dispatch_counters`、`TEST_REGISTRY_SIMPLE/DUPLICATE/MISSING_PREREQ/CYCLE/DIAMOND/FAILURE/ARGUMENTS`（:394-471）。
- workspace 测试 fakes：`test_fake_discover`/`test_fake_resolve`/`test_fake_prepare_dependencies` + `reset_preparation_test`（:478-513）、`test_fake_fetch`/`test_fake_link_member`（:515-528）、`shim_content_for`（:533-538，读 shim 文件内容）、`library_fixture_package`（:547-554，LIB fixture 包）。
- golden 系：`GOLDEN_CASES`（:723-731，7 例）、`NEGATIVE_CASES`（:733-741，7 例）、`wants_update`（:745-752，`JUICE_UPDATE_GOLDEN` 非空重写基线，CI 从不设）、`read_case_config`（:786-828，config.txt 的 mode/path/next_number/load_target 键）、`collect_case_files`（:834-856，生产扫描序）、`normalize_golden_abs`（:867-876，绝对根 → `<abs>` 占位）、`compare_or_update`（:878-900）、`run_golden_cases`（:911-976，含 driver.jai + first.jai 字节比对）、`run_negative_cases`（:978-1008）。
- jaix pre-step 支撑：`jaix_exe`（:1020-1022，**兄弟仓库** jaix-cli/target/jaix.exe——dev 布局产物）、`prepend_jaix_to_path`（:1035-1045，PATH 前插 jaix 目录，幂等）、`clean_jaix_driver_files`（:1053-1061，删 fixture 根的点前缀 driver litter）、`fake_jaix_spawn`/`reset_jaix_spawn`（:1070-1086，记录 `exe|input|output|config`）、`fake_jaix_prestep`（:1088-1094）。

### 16.2 test_monorepo.jai（tests/，E2E 先例形状）

**先例形状**（juice 的 E2E 都照这个形）：真 `juice.exe` 子进程跑 fixture 包，`run_juice_child` + `expect_exit` + `child_output_contains`/`output_matches` 断言**精确错误消息**；fixture 家族 `tests/data/workspace-*`；每个测试 defer 清理 fixture 的 target/。

- 发现校验矩阵（test_monorepo.jai:37-129）：每个失败分支一个 E2E，断言具体消息——坏根 manifest（`"Existing package.jai is invalid."`）、逃逸成员路径、成员目录不存在（实测走「非安全真实目录」分支——normalize_existing_path 只词法归一不验存在）、成员无 manifest、成员 manifest 无效、重复成员路径（`member_lib/.` 拼写）、根列自己为成员（`.` 命中重复分支）、**成员声明自己的成员被静默忽略**（成功，钉住现状）、junction 成员目录（运行时在 target/ 划痕目录用 mklink 制造；mklink 不可用 → 打印 SKIP 并 return）。注释（test_monorepo.jai:29-35）：两条防御分支不进矩阵——成员目录不存在（如上）与逃逸（路径门已拒所有可达拼写）。
- 构建 E2E（:140-182）：成员 link 不 fetch → shim 内容断言（member_lib 的 shim 被依赖 strip front 重写到 `target/transpile/deps/member_lib/...`；test-free 的 member_extra 的 shim 保持指向 `member_extra/module.jai` 原样）→ 产物运行输出断言两成员函数真被调用 → 依赖 strip 视图在纯契约路径逐字节可重建。
- clean E2E（:192-219）：target 垃圾运行时制造（fixture 从不提交 target/），根 + 成员整目录删除、源文件不动、无 target/ 的成员不失败（delete_directory_full 对不存在路径 true）。
- test E2E（:231-273）：根测试程序 `#import` lib 成员全链路；**成员自己的测试不在根下跑**（`want = false` 断言缺席，成员边界重申）；成员作为自己的根时跑全量（3 个：entry 内联 + 闭包内联 + tests/ 独立块，扫描序）；LIB 成员（0 计划）当自己的根跑测试时依赖仍经 `force_dependencies` 准备（旧「0 计划 = 无 shim」门让 import 恒失败，此场景是修复钉）。

### 16.3 test 块清单（当前工作树计数）

**tests/ 各文件**：

| 文件 | test 块数 | 首行 |
|---|---|---|
| test_support.jai | 0 | —（纯支撑，test-free） |
| test_monorepo.jai | 14 | 37 |
| metaprogram_tests.jai | 7 | 26（Metaprogram 生成器字节形状 4 + Bootstrap options 3） |
| transpile_front_tests.jai | 8 | 29（真实 build transpile 步 2、PLAIN 布局 2、closure_has_tests 1、探针 1、Testing 模块视图 2） |
| transpile_plugin_tests.jai | 13 | 180（管线注册/合成插件/跨文件状态/模式门/剥离后不派发、探针聚合 2、runner 拒绝 2、缓存键 2、config 1） |
| transpile_tests.jai | 45 | 29（Expand 11、Immunity 2、Strip 10、Diagnostic 8、行保真 2、解码 6、缓存键/路径 4、golden/negative 2、run 矩阵 5） |

**src/ 内联测试**（共 155）：

| 文件 | 数 | 测试名一览 |
|---|---|---|
| dependency.jai | 6 | :296 shim load target parses the generated shape；:303 a test-free dependency stays untouched；:321 a test closure is viewed and the shim rewritten；:350 an escaping load stays verbatim and unviewed；:372 missing entry or bad shim is left to the compiler；:387 no shim directory is a no-op |
| jaix_front.jai | 9 | :248 scan applies the exclusion set in scan order；:299 scan excludes driver litter；:328 scan rejects a missing package root；:339 exe resolution prefers the marker and resolves relative to the root；:351 exe resolution falls back to the PATH probe in entry order；:362 a missing executable fails with the clear error；:375 the pre-step spawns per file with absolute paths into the mirror；:406 a nonzero spawn fails the pre-step fast with stderr passthrough；:426 an absent marker is a no-op |
| dispatcher.jai | 11 | :140 Production registry validation；:144 Duplicate command detection；:149 Missing prerequisite detection；:154 Unknown command rejected；:160 Cycle rejected before execution；:167 Diamond executes each command once；:174 Invalid arguments rejected before prerequisites；:181 Prerequisite failure propagates；:188 Handler failure reported；:195 Strict manifest protocol；:206 Case-sensitive target selection |
| manifest.jai | 15 | :384/:391/:398/:405/:412/:418 jaix marker 矩阵 6；:427/:438/:448/:455/:462 解析面 5；:469/:476/:486/:495 pipeline 门矩阵 4 |
| commands/build.jai | 25 | :261 Build without targets compiles nothing；:268 Unsafe package root blocks every compilation；:282 Escaping artifact plan blocks compilation；:299 Build forwards each prepared plan to compilation；:338 Build rejects a plan with an empty target name；:350 Build fails fast on a compile failure；:375/:397/:433/:449/:467 build front seam 5（test-free 跳过、all-or-nothing 视图+改写、诊断先于编译、load 环、声明序管线）；:516/:536/:552 jaix 路由 3；:570/:591 probe 2；:629/:670/:696/:748 E2E 4（strip 视图构建、零 transpile、显式管线=默认、未知插件拒绝）；:770/:811/:835/:857/:934 jaix E2E 5（镜像构建+lowering 运行、失败传播、缺 exe、双路径、双构建同构） |
| commands/clean.jai | 4 | :78 validates workspace scope before deletion；:89 without a manifest uses the current root；:97 Unsafe Clean path prevents every deletion；:108 Clean continues after a deletion fails |
| commands/registry.jai | 2 | :16 Command-owned declarations in production registry；:34 Command argument guards |
| commands/run.jai | 5 | :89 Run launches the selected prepared artifact；:108 Run defaults to the only target；:119 Invalid Run selection never launches；:134 Run propagates launch failure；:146 E2E: run inherits strip semantics through build |
| commands/test.jai | 38 | :610-823 seam 11（fake 视图驱动编译、缓存命中不动视图、pattern 过滤、零命中跳编译、零测试跳编译、诊断先于编译、编译失败传播、声明序管线、jaix 镜像路由、jaix pre-step 失败阻断、真实 transpile 展开镜像视图）；:892-950 Testing 模块 4（包内模块优先、test-free 禁用、自测拼接、marker 缺失）；:962-1063 collection 5（字典序、缺根拒绝、排除集、driver litter、symlink/junction 跳过）；:1100/:1110 声明与参数契约 2；:1121-1397 E2E 16（全过 fixture、失败映射坐标、pattern、零命中、匿名路径名、大小写敏感、零测试跳编译、排除集、成员自根、重复扫描字节稳定、缓存命中纯契约、内容变更新 hash 目录、clean 连带缓存、jaix 镜像测试、jaix 视图写失败点名源文件 等） |
| scan_walk.jai | 6 | :246 the skeleton applies injected exclusions in scan order；:284 an unscannable root fails the walk；:292 the path helpers；:305/:329/:339 driver litter 3（head marker、CRLF、非误杀面） |
| target.jai | 11 | :249 rejects an unnamed explicit target；:259 rejects a target without an entry file；:269 builds a plan for a valid declaration；:292 Library package rejects executable targets；:299 Library package requires a module.jai import entry；:306 Library package resolves to no plans；:313/:322/:331/:341 UNSPECIFIED 推导 4（根 entry→LIB、src entry→LIB、默认 entry→BIN、无 entry 仍 BIN）；:350 Explicit library accepts a src/module.jai entry |
| transpile_config.jai | 4 | :38 声明序保持；:48 零声明空管线；:59 防御性跳过未知 id；:72 校验与组装对内置注册表一致 |
| workspace.jai | 19 | :216 Discovery publishes workspace state once；:229 Discovery without a package stays empty；:238 Preparation without targets skips dependencies；:254 Preparation with targets prepares dependencies；:277 Preparation without targets forces dependencies on request；:296 Resolution failure publishes no prepared workspace；:312 Dependency failure publishes no prepared workspace；:327 Preparation requires discovery；:339 Prepared workspace ensure fails on an empty state；:348 Prepared workspace ensure hands back the prepared result；:362 Prepared workspace ensure is idempotent；:379 Workspace member dependencies are linked not fetched；:394 Member link failure propagates；:407 Dependency fetch failure propagates；:422/:433/:444/:455 import shim 布局 4（src/module.jai、单文件、根 module.jai、无布局跳过）；:478 Workspace member path validity gate |

> 注：juice 侧「200 测试」为更早时点计数；上表为当前工作树 grep 实测（src 155 + tests 87 = 242，含 E2E 与平台相关块），实现链对齐语义即可，勿以数字为契约。

## 17. otter 1a 直接可借的语义锚点（速查）

- manifest 加载 =「生成评估器源码 → 子进程 jai 编译执行 → 解析数据文件」三段；协议 12 记录；两道 standalone 校验门；exit 2 重试 ≤ 2 次。
- workspace = 三态机（EMPTY/DISCOVERED/PREPARED）+「全部成功才发布」+ 三 seam（discover/resolve/prepare_dependencies）；发现不取依赖；成员 link 不 fetch。
- target = 推导序四分支；`LIBRARY_TARGET_CONFLICT`（LIB 声明 targets）、`DUPLICATE_TARGET_NAME`（equal_nocase 查重）；产物统一 `<root>/target/<name>[.exe]`；`revalidate_artifact_plan` 是 build/run 共用大门。
- 依赖 = shim 单文件（`// Generated by juice...` + 单行 `#load`）；入口探测序 module.jai → src/module.jai → `<name>.jai`；无布局不报错；相对 DEP 以包根（进程 cwd）为锚；git 缓存 `<cache>/git_repos/<sanitized>[_<version>]`；依赖 strip front = 闭包含 test 则整闭包视图 + shim 重写。
- 分发 = validate_registry 三查（声明合法性/重名/前置存在）+ plan_command DFS（VISITING=环、COMPLETED=菱形去重、前置恒空参、计划期查参）+ 后序执行。
- 构建 = b1 入口 → b2 准备 → b3 整体重校验 → b4 依赖 strip → b5 jaix pre-step（有标记）→ b6 入口选择（probe → 原始/视图/镜像）→ b7 编译循环 fail-fast → b8 单计划（入口检查 → 建 target 目录（LNK1104 面）→ metaprogram 写盘 → spawn jai → artifact 检查）。
- clean = 收集（成员 `<dir>/target` 或根 target）→ 先全校验后删除 → 删除失败不中断。
- run = 选择（指定精确匹配 → 唯一计划 → 包名计划）+ `revalidate_artifact_plan` + cwd 继承启动。
- 测试 = src 内联贴实现 + tests/ 姊妹文件（test-free 模块）+ E2E 真子进程断言精确消息 + seam fakes 跨生产接口。
