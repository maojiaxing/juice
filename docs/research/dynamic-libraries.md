# 动态库编译与运行时加载研究（Jai / Juice）

> 面向 Juice 增加"动态库 target / 加载命令"的前期调研。
> 全部结论来自一手来源：Jai 发行版 `C:/Users/maojiaxing/DevTools/jai`（版本 beta 0.2.009，2025-02-06，见文末"发行版版本"）的模块源码、how_to/examples、编译器实际运行输出，以及本仓库源码。
> 每条论断标注来源类型：【实验】= 本机编译运行验证；【源码】= 读发行版/本仓库源码确认；【推断】= 基于事实的推理，非直接证据。

## 结论摘要

1. Jai 编译动态库的方式是设置 `Build_Options.output_type = .DYNAMIC_LIBRARY`（枚举值 2），通过 workspace/metaprogram 构建脚本完成【源码 + 实验】。
2. 导出符号的机制是 `#program_export` 指令；发行版中不存在 `#export` 或 `#dll_export`【源码】。导出的符号名不修饰【实验】。
3. `jai` 命令行**没有**设置 output type 的 flag；`-exe`/`-output_path` 只能改名字和路径。仅靠 CLI 无法产出 DLL，必须有一个 metaprogram 构建脚本【源码 + 运行 `jai -help`】。
4. 编译器默认链接路径原生支持 DYNAMIC_LIBRARY：Windows 上自动调用 link.exe 并加 `/DLL`，同时生成导入库 `.lib` 与 `.exp`【实验】。
5. 运行时加载：发行版**没有** `Dynamic_Library.jai` 模块【源码】。官方上层机制是 `#library` + `#elsewhere`（编译期加载 DLL 取类型、链接期导入、运行期由导入表加载）；底层手工加载用 `Windows.jai` 的 `LoadLibraryA/W`/`GetProcAddress`/`FreeLibrary` 或 POSIX 的 `dlopen`/`dlsym`/`dlclose`【源码】。
6. 跨模块调用有 context 与调用约定约束：面向 C 风格调用方的导出应写 `#c_call`；Jai↔Jai 调用走默认约定并需要 `Remap_Context()` 或 `#no_context`【源码 + 实验（实验中不匹配约定会崩溃，见"实验记录"）】。
7. Juice 现状的 target/artifact 链整条假设"产物是可执行文件"（`src/target.jai:138-142` 硬编码 `.exe`、`src/commands/build.jai:84-87` 只传 `-exe`/`-output_path`），要支持动态库需扩展 Target 结构、artifact 命名、编译调用与 run 的启动钩子。`Package_Type.LIB` 虽已存在，但不参与 target 解析。【源码 + 推断】

## Jai 动态库编译

### 输出类型枚举

【源码】`C:/Users/maojiaxing/DevTools/jai/modules/Compiler/Compiler.jai:78-85`，`Build_Options.output_type`：

```jai
output_type: enum u8 {
    NO_OUTPUT       :: 0;
    EXECUTABLE      :: 1;
    DYNAMIC_LIBRARY :: 2;
    STATIC_LIBRARY  :: 3;
    OBJECT_FILE     :: 4;
} = .EXECUTABLE;
```

相关字段（同一文件）：
- `output_executable_name`（Compiler.jai:171）：无路径、不含扩展名（如 ".exe"）。
- `output_path` / `intermediate_path`（Compiler.jai:172-173）：产物目录 / 临时中间文件目录（实验中中间 `.obj` 落在 `<输出目录>/.build/`）。
- `append_executable_filename_extension`（Compiler.jai:178）：注释原文 "Append extensions like .dll, .so, .exe, etc to the name given in output_executable_name"。
- `additional_linker_arguments`（Compiler.jai:186）、`use_custom_link_command`（Compiler.jai:180）：附加链接参数 / 接管链接。
- `runtime_support_definitions`（Compiler.jai:116-121）：`AUTO` 在 `output_type == .EXECUTABLE` 时为 `ENTRY_POINT_AND_INIT`，其余输出类型为 `ONLY_INIT`——即 DLL 默认带 `__jai_runtime_init`/`__jai_runtime_fini` 但不定义 `__system_entry_point`，这解释了实验中 DLL 导出表里出现这两个符号。

编译期构建接口（【源码】Compiler.jai:1485-1630）：`compiler_create_workspace`、`set_build_options`、`add_build_file`、`add_build_string`、`compiler_wait_for_message`、`compiler_begin_intercept`、`compiler_end_intercept`、`set_build_options_dc`（`_dc` = during compile，可用于 `do_output=false`）。

### 导出机制：#program_export

【源码】`C:/Users/maojiaxing/DevTools/jai/how_to/400_workspaces.jai:100-111`：

```
// The #program_export also ensures that the function is exposed
// as a visible entry point into the DLL or static library.
```

同段（100-102 行注释）说明为什么 DLL 导出常配 `#no_context`："the context of a DLL may diverge from that of the main program"。示例 `factorial :: (n: int) -> int #no_context`（107-111 行），配套的 workspace 构建见同文件 236-252 行（`output_type = .DYNAMIC_LIBRARY`，且不添加 `main()`，249-251 行注释："we don't add main(), because this is a library"）。

- 【源码】全发行版 grep `#export`（精确指令）无匹配——不存在 `#export`/`#dll_export` 指令。
- 【源码】`#program_export` 后可用字符串覆盖导出名：`C:/Users/maojiaxing/DevTools/jai/modules/Runtime_Support.jai:421` 的 `#program_export "main"`；对应的 AST 字段 `program_export_name`（Compiler.jai:710，注释 "Non-empty if the user specified a name"）。另有 `#scope_export`（Runtime_Support.jai:384）。
- 【源码】DLL 的运行时入口符号由 Runtime_Support 提供：`__jai_runtime_init`/`__jai_runtime_fini` 在 `Runtime_Support.jai:384-407` 以 `#program_export` + `#c_call` 导出。
- 【实验】导出符号名不修饰：dumpbin 导出表直接可见 `add_numbers`、`greet`（见"实验记录"）。
- 【源码】面向 C 调用方的导出惯用法：`#program_export` + `#c_call`，见 `C:/Users/maojiaxing/DevTools/jai/examples/ios_library/library.jai:1-8`（`hello_from_jai :: (s: string, number: int) -> string #c_call`，内部用 `push_context { }` 使用 context 相关例程）。CHANGELOG.txt:8321 也提及 "building a dynamic library using the C calling convention, that is called into by a C program"。

### 平台产物命名

- 【源码】`C:/Users/maojiaxing/DevTools/jai/modules/Bindings_Generator/module.jai:6827-6839` 给出平台后缀表（含 `#if OS == .WINDOWS` 写法）：

```jai
#if OS == .WINDOWS {
    SHARED_LIBRARY_SUFFIX :: ".dll";
    STATIC_LIBRARY_SUFFIX :: ".lib";
} else #if OS == .LINUX {
    SHARED_LIBRARY_SUFFIX :: ".so";
    STATIC_LIBRARY_SUFFIX :: ".a";
} else #if OS == .MACOS {
    SHARED_LIBRARY_SUFFIX :: ".dylib";
    STATIC_LIBRARY_SUFFIX :: ".a";
}
```

- 【源码】`C:/Users/maojiaxing/DevTools/jai/modules/BuildCpp.jai:173-189`：动态库输出名 `.dylib`（MACOS）/ `.so`（LINUX、ANDROID），静态库 `.a`，可执行文件不加扩展名。
- 【源码】扩展名由编译器按平台自动追加：Compiler.jai:178（"Append extensions like .dll, .so, .exe, etc"）。
- 【实验】Windows 一次 DYNAMIC_LIBRARY 构建的产物集合：`mylib.dll` + `mylib.lib`（导入库）+ `mylib.exp` + `mylib.pdb`（见"实验记录"）。
- 【源码】Windows 上链接需要本机装有 Windows SDK 与 MSVC 工具链：发行版根目录 `README.txt`（"in order to compile on Windows, you need to have installed ... one Windows SDK ... and one Visual C++ Redistributable"）。实验链接行印证（link.exe 来自 VS2022 BuildTools 14.44.35207，lib 来自 Windows Kits 10.0.26100.0）。

### jai 命令行 flag

【源码 + 运行】`jai -help` 输出全量（原样记录关键部分）：

```
-exe name        Set output_executable_name on the target workspace to 'name'.
-output_path     Set the path where your output files (such as the executable) will go.
-                Every argument after - is ignored by the compiler itself,
                     and is passed to the user-level metaprogram for its own use.
```

【源码】Default_Metaprogram 的参数分派在 `C:/Users/maojiaxing/DevTools/jai/modules/Default_Metaprogram.jai:125-249`（case 列表：-release、-very_debug、-no_inline、-quiet、-x64、-llvm、-no_cwd、-no_dce、-no_split、-output_ir、-debug_for、-msvc_format、-natvis、-no_backtrace_on_crash、-version、-exe(182-190)、-output_path(192-200)、-add、-run、-plug、-help、-debugger、-context_size…）；`-exe`/`-output_path` 的应用在 346-347 行。**没有**任何设置 `output_type` 的 flag。

推论（【推断】，依据上面两条）：CLI 无法直接要求 jai 产出 DLL；设置输出类型必须走 metaprogram——即一个 build 脚本文件（workspace 模式），如 `examples/dll/build.jai`、`examples/output_types/build.jai`、`how_to/400_workspaces.jai:236-252`。`-` 之后的参数会转给用户级 metaprogram，因此 Juice 若想用纯 CLI 实现 dll 构建，只能给 jai 传一个预生成/内置的 build 脚本。

### 链接方式

- 【实验 + 源码】默认路径：编译器自动完成链接。`C:/Users/maojiaxing/DevTools/jai/examples/output_types/build.jai:49-52` 构建 `release_dll` 时未设置 `use_custom_link_command`，直接产出 DLL。实验中编译器自动调用本机 `link.exe` 并带 `/DLL`（链接行原文见"实验记录"）。
- 【源码】自定义链接路径：设 `use_custom_link_command = true` 后收到 `READY_FOR_CUSTOM_LINK_COMMAND` 消息（Message_Phase，Compiler.jai:305-314）。参考实现 `C:/Users/maojiaxing/DevTools/jai/modules/Compiler/examples/compile_me.jai:132-287`：Windows 下 `options.output_type == .DYNAMIC_LIBRARY` 时追加 `/DLL`（266-268 行）；Linux 下 `-export-dynamic`、`--dynamic-linker`（224-230 行）；macOS 下 `-export_dynamic -dynamic`（231-242 行）。

## Jai 运行时加载

### 不存在 Dynamic_Library 模块

【源码】发行版 `modules/` 下没有 `Dynamic_Library.jai`（文件名 glob 无结果）。运行时加载有三条实际路径：

### 路径 A：平台 API 手工加载

【源码】Windows 绑定（`C:/Users/maojiaxing/DevTools/jai/modules/Windows.jai`）：
- `FreeLibrary :: (module: HMODULE) -> BOOL #foreign kernel32;`（2331 行）
- `GetProcAddress :: (module: HMODULE, proc_name: *u8) -> *void #foreign kernel32;`（2339 行）
- `LoadLibraryA/W`、`LoadLibraryExA/W`（2340-2343 行）

【源码】Linux 绑定（`C:/Users/maojiaxing/DevTools/jai/modules/POSIX/bindings/linux/base.jai`）：
- `dlopen :: (__file: *u8, __mode: s32) -> *void #foreign libdl;`（515 行）
- `dlclose :: (__handle: *void) -> s32 #foreign libdl;`（519 行）
- `dlsym :: (__handle: *void, __name: *u8) -> *void #foreign libdl;`（523 行）
- macOS 绑定同样提供 dlopen（`modules/POSIX/bindings/macos/*/base.jai`，grep 命中）。

【源码】官方手工加载惯用法：`C:/Users/maojiaxing/DevTools/jai/modules/Gamepad/Xinput.jai:188, 208-235`——先声明过程指针变量 `XInputGetState : (dwUserIndex: u32, pState: *XINPUT_STATE) -> u32 #c_call;`（188 行），运行时 `LoadLibraryA` 失败返回 null 时依次尝试候选 DLL（221-224 行），成功后 `XInputGetState = xx GetProcAddress(module, "XInputGetState");`（227-228 行）。同类用法：`modules/telemetry3/telemetry.jai:68`。

### 路径 B：#library + #elsewhere（官方高层机制）

【源码】`#library` 指令的 AST 与 flags 在 `C:/Users/maojiaxing/DevTools/jai/modules/Compiler/Compiler.jai:877-887`（`Code_Directive_Library`）：

```jai
library_flags: enum u32 {
    IS_SYSTEM_LIBRARY           :: 0x1;
    DYNAMIC_LIBRARY_UNAVAILABLE :: 0x2;
    STATIC_LIBRARY_UNAVAILABLE  :: 0x4;
    LINK_ALWAYS                 :: 0x8;
}
```

【源码】实际用法（`C:/Users/maojiaxing/DevTools/jai/examples/dll/main.jai:1-4`）：

```jai
Helper :: #library,no_static_library "helper";

do_something_simple              :: () #no_context #elsewhere Helper;
do_something_more_complicated    :: () -> string   #elsewhere Helper;
```

flag 名称实例：`no_static_library`（上例）、`no_dll,link_always`（`modules/Android/generate.jai:369`）、`system`（`modules/Android/EGL/bindings.jai:265` 等大量系统库绑定）。
【源码】编译期行为：编译器在编译主程序时会实际加载该 DLL（`examples/dll/build.jai:34-41` 注释原文："our main program's workspace wants to see the DLL at compile-time"；因此 build.jai 先用拦截循环等 DLL 编译完成）。运行期行为：DLL 随主程序一起由系统加载（默认链接进导入表；`no_dll` 表示仅编译期使用——【推断】，依据是 flag 名与 Bindings_Generator 中系统库 `#library` 的普遍用法，未单独做运行实验）。
【源码】Jai↔Jai 调用与 context：DLL 内使用 context 的函数先 `Remap_Context()` 切换到自己 context（`examples/dll/helper.jai:6-27`；`modules/Remap_Context.jai:20`）。跨模块共享数据用 `#add_context` + 双方 `#load` 同一文件（`examples/dll/backchannel.jai`）。

### 调用约定与 context 规则

- 【源码】`#c_call` = C ABI 且不传 context：`C:/Users/maojiaxing/DevTools/jai/how_to/011_context.jai:298-324`（"#c_call means we use the C ABI"；324 行 "Since callback is #c_call, we do not pass the context here!"）。
- 【源码】`#c_call` 例程看不到 context，要用 context 依赖例程须 `push_context { }`（how_to/011_context.jai:305-318；`examples/ios_library/library.jai:3-7`）。
- 【源码】DLL 导出若无 `#c_call` 且想避开 context 问题，用 `#no_context`（how_to/400_workspaces.jai:100-111）。
- 【实验】加载器侧指针类型与 DLL 侧声明的约定不一致会导致运行时崩溃（两次崩溃记录见下），两侧都写 `#c_call` 后正常。Jai 默认约定（非 #c_call）会隐式传递 context，与 C 风格裸指针调用不兼容。

## 实验记录

【实验】目录：`C:/Users/maojiaxing/AppData/Local/Temp/juice_dll_research`（Windows 临时目录；实验后保留，未删除）。编译器：`C:/Users/maojiaxing/DevTools/jai/bin/jai.exe`，版本 beta 0.2.009（built on 6 February 2025，`jai -version -quiet loader.jai` 输出原文：`Version: beta 0.2.009, built on 6 February 2025.`）。

三个文件（最终可用版本）：

1. `mylib.jai`（DLL 源码）：

```jai
#import "Basic";

#program_export
add_numbers :: (a: s64, b: s64) -> s64 #c_call {
    return a + b;
}

#program_export
greet :: () -> string #c_call {
    push_context {
        return sprint("Hello from the Jai DLL!");
    }
}
```

2. `build.jai`（metaprogram 构建脚本，编译 mylib.jai 为 DLL）：

```jai
build :: () {
    set_build_options_dc(.{do_output=false});
    w := compiler_create_workspace();
    options := get_build_options();
    options.output_executable_name = "mylib";
    options.output_type            = .DYNAMIC_LIBRARY;
    options.text_output_flags      = .OUTPUT_LINK_LINE;
    set_build_options(options, w);
    compiler_begin_intercept(w);
    add_build_file("mylib.jai", w);
    while true {
        message := compiler_wait_for_message();
        if message.kind == .COMPLETE break;
    }
    compiler_end_intercept(w);
}
#import "Basic";
#import "Compiler";
#run build();
```

3. `loader.jai`（加载器，LoadLibraryA/GetProcAddress/FreeLibrary，函数指针类型两侧都用 `#c_call`）：

```jai
#import "Basic";
#import "Windows";

add_numbers : (a: s64, b: s64) -> s64 #c_call;
greet       : () -> string #c_call;

main :: () {
    module := LoadLibraryA("mylib.dll");
    if !module { print("FAIL: LoadLibraryA returned null for mylib.dll\n"); return; }
    add_numbers = xx GetProcAddress(module, "add_numbers");
    if !add_numbers { FreeLibrary(module); return; }
    result := add_numbers(2, 3);
    print("add_numbers(2, 3) = %\n", result);
    greet = xx GetProcAddress(module, "greet");
    if greet {
        s := greet();
        print("greet() = %\n", s);
    }
    ok := FreeLibrary(module);
    print("FreeLibrary returned %\n", ok);
}
```

构建命令与输出原文：

```
$ jai build.jai
  正在创建库 C:\Users\maojiaxing\AppData\Local\Temp\juice_dll_research\mylib.lib 和对象 C:\Users\maojiaxing\AppData\Local\Temp\juice_dll_research\mylib.exp
Running linker: "...MSVC\14.44.35207\bin\Hostx64\x64\link.exe" /nologo C:/.../juice_dll_research/.build/mylib_0_w3.obj ... /OUT:C:/.../juice_dll_research/mylib.dll /MACHINE:AMD64 /INCREMENTAL:NO /DEBUG /libpath:"...\lib\x64" /libpath:"...\um\x64" /libpath:"...\ucrt\x64" /DLL -nodefaultlib kernel32.lib libcmt.lib vcruntime.lib ucrt.lib
```

产物（`ls` 实录）：`mylib.dll`(258560)、`mylib.lib`(2268)、`mylib.exp`(1115)、`mylib.pdb`(659456)；中间对象 `.build/mylib_{0..3}_w3.obj`。

导出表（`dumpbin /EXPORTS mylib.dll` 输出原文节选）：

```
    ordinal hint RVA      name
          1    0 00009530 __jai_runtime_fini = __jai_runtime_fini
          2    1 000174B0 __jai_runtime_init = __jai_runtime_init
          3    2 000157F0 add_numbers = add_numbers
          4    3 00001000 greet = greet
```

加载器运行输出原文（loader 编译命令 `jai loader.jai`，运行通过副本 `loader6.exe` 执行）：

```
Loaded mylib.dll, HMODULE = 7ffa_1c3b_0000
GetProcAddress(module, "add_numbers") = procedure 0x7ffa_1c3c_9830
add_numbers(2, 3) = 5
GetProcAddress(module, "greet") = procedure 0x7ffa_1c3d_a790
greet() = Hello from the Jai DLL!
FreeLibrary returned TRUE
```

（校验：0x7ffa_1c3c_9830 − 0x7ffa_1c3b_0000 = 0x29830，落在 DLL 映像的 .text 区段内；`FreeLibrary` 返回 `TRUE`。）

失败迭代（如实记录，说明约定的重要性）：

- 版本 1：DLL 侧 `add_numbers` 无 `#c_call` 也无 `#no_context`，加载器侧 `#c_call` 调用 → 崩溃输出 "The program crashed because it tried to write to a null pointer."（Runtime_Support_Crash_Handler 捕获）。
- 版本 2：DLL 侧加 `#no_context`（默认 Jai 约定），加载器侧 `#c_call` → 崩溃输出 "The program crashed because of an access violation reading location 0xffffffffffffffff."
- 版本 3：两侧都声明 `#c_call`（DLL 侧遵循 `examples/ios_library/library.jai` 的写法）→ 运行成功，输出如上。

环境插曲（如实记录）：实验目录位于 Windows 临时目录，本会话 Bash 沙箱默认禁止执行其中新生成的 exe（首次运行报 "Permission denied"/"Access is denied"）；把 loader.exe 拷贝为新文件名后经 cmd 正常执行。此外运行 `jai.exe` 无参数时无任何输出、退出码 0（usage 需 `-help`）。

## 对 Juice 的落点（现状 seam 与建议扩展点）

以下现状锚点均为【源码】事实（行号基于本仓库工作树）；"如何扩展"为【推断】。

### 现状：产物链假设单一可执行文件

- `modules/Juice.jai:4-7`：`Package_Type :: enum { LIB; BIN; }` 已存在，但 `Package_Type` 不参与 target/artifact 解析（CONTEXT.md:43 "Package type 不限制显式或隐式 executable target"）。
- `modules/Juice.jai:10-13`：`Target :: struct { name; main_file; }`——没有输出类型/kind 字段。
- `modules/Juice.jai:23-27`：`Artifact_Plan :: struct { target; result_dir; artifact_path; }`——每个 target 恰好一个 artifact。
- `src/target.jai:133-150` `make_artifact_plan`：Windows 上硬编码 `tprint("%1.exe", target.name)`（138-142 行），其余平台 `target.name`。
- `src/commands/build.jai:69-103` `compile_artifact_plan`：对 `jai` 的调用只有 `jai <source> -exe <name> -output_path <result_dir>`（84-87 行），之后校验 `file_exists(plan.artifact_path)`（98-101 行）。
- `src/commands/run.jai:50-63` `run_artifact_plan`：`run_command(plan.artifact_path)` 直接启动可执行文件。
- `src/commands/run.jai:65-82` `run_prepared_workspace` 已有一个 `launch: #type (plan, package_root) -> bool = run_artifact_plan` 注入参数（68 行）。
- `src/commands/registry.jai:1-7`：命令注册表为静态数组，新增命令在此声明。
- `src/commands/command.jai:9-17`：`Command` 结构（name/description/usage/prerequisites/handler/validate_arguments）。

### 推断：需要扩展的 seam

1. **Target 增加输出类型字段**（推断）：`Target`（modules/Juice.jai:10-13）需增加如 `kind`（executable / dynamic_library）字段；manifest 解析、`Effective_Target`（Juice.jai:16-20）、`make_effective_target`（src/target.jai:55-90）随之传递。`Package_Type.LIB` 与 target kind 的关系需要在 CONTEXT.md 词汇表中重新定义。
2. **artifact 命名按 kind + 平台选择扩展名**（推断）：`make_artifact_plan`（src/target.jai:138-142）的分支要从"Windows 加 .exe"扩展为"Windows .exe/.dll、Linux 无扩展/.so、macOS 无扩展/.dylib"；Jai 编译器本身会按平台自动追加扩展名（Compiler.jai:178），与现有 `-exe <target.name>` 的约定兼容（DLL 场景下产物为 `<name>.dll`）。注意 Windows 上 DYNAMIC_LIBRARY 一次构建产生 `.dll` + `.lib` + `.exp` + `.pdb` 多个文件（实验），`Artifact_Plan` 的单一 `artifact_path` 只够描述主产物，校验逻辑（src/commands/build.jai:98-101）需明确主产物是哪一种。
3. **编译调用需走 metaprogram**（推断，硬约束）：jai CLI 无 output_type flag（Default_Metaprogram.jai:125-249），`compile_artifact_plan`（src/commands/build.jai:84-87）无法用现有 flag 拼出 DLL 构建。可行方案是 Juice 为 lib target 生成/内置一个 build 脚本（workspace 模式，仿 examples/dll/build.jai 或 examples/output_types/build.jai），再以 `jai <build 脚本>` 形式调用；这同时影响 `-output_path`/`-exe` 的传递方式（DLL 场景下两者都写在 build 脚本里）。
4. **"加载命令"没有现成宿主**（推断）：Juice 自身是已编译好的 Jai 程序，无法在编译期使用 `#library`/`#elsewhere` 指向"构建时才产出的 DLL"（该机制要求编译期加载，examples/dll/build.jai:34-41）。若新增 `load`/`run-lib` 命令，宿主要么由 Juice 生成一个小 Jai 加载器源码再编译运行（底层 API：Windows.jai LoadLibrary/GetProcAddress，POSIX dlopen/dlsym；函数指针类型两侧都要 `#c_call`——实验两次崩溃是反例），要么把 `#library`/`#elsewhere` 的宿主程序作为 lib package 的一部分由用户编写。Command 结构（command.jai:9-17）与注册表（registry.jai）可承载该命令；`run_prepared_workspace` 的 `launch` 参数（run.jai:68）可直接复用为注入点，但加载与"启动可执行文件"的语义不同，CONTEXT.md 的 Run/Artifact 词条需要相应修订。
5. **CONTEXT.md 词汇**（推断）：需新增或修订 Artifact plan/Artifact（"可执行输出"字样，CONTEXT.md:51-55）、Run（CONTEXT.md:16-17）等条目，以容纳动态库产物与加载命令。

## 引用清单

Jai 发行版（`C:/Users/maojiaxing/DevTools/jai`，版本 beta 0.2.009，built on 6 February 2025，由 `jai -version` 输出）：

- `modules/Compiler/Compiler.jai`：output_type 枚举 78-85；runtime_support_definitions 116-121；output_executable_name 171；output_path/intermediate_path 172-173；append_executable_filename_extension 178；use_custom_link_command 180；additional_linker_arguments 186；Build_Options_During_Compile 202-211；Message_Phase 305-314；program_export_name 710；Code_Directive_Library 877-887；编译接口 1485-1630（compiler_create_workspace 1485、compiler_begin_intercept 1488、compiler_end_intercept 1489、compiler_wait_for_message 1491、add_build_file 1599、add_build_string 1600、get_build_options 1603、set_build_options 1604、set_build_options_dc 1630）。
- `modules/Compiler/examples/compile_me.jai`：自定义链接命令 132-287；Windows /DLL 266-268；Linux/macOS 链接参数 224-242。
- `modules/Default_Metaprogram.jai`：flag 分派 125-249（-exe 182-190、-output_path 192-200）；应用 346-347；帮助文本 511、536。
- `modules/Windows.jai`：FreeLibrary 2331；GetProcAddress 2339；LoadLibraryA/W/ExA/ExW 2340-2343。
- `modules/POSIX/bindings/linux/base.jai`：dlopen 515；dlclose 519；dlsym 523。
- `modules/Runtime_Support.jai`：#program_export + #c_call 的 __jai_runtime_init/fini 384-407；#program_export "main" 421。
- `modules/Remap_Context.jai`：Remap_Context 20。
- `modules/Gamepad/Xinput.jai`：函数指针声明 188；LoadLibraryA 候选链与 xx GetProcAddress 221-228。
- `modules/Bindings_Generator/module.jai`：平台后缀表 6827-6839。
- `modules/BuildCpp.jai`：动态库输出名 173-189。
- `how_to/011_context.jai`：#c_call 与 context 限制 298-324。
- `how_to/400_workspaces.jai`：#program_export/#no_context 100-111；DYNAMIC_LIBRARY workspace 236-252。
- `examples/dll/`：build.jai（DLL 编译与拦截循环 20-61；"see the DLL at compile-time" 34-41）；main.jai（#library/#elsewhere 1-4）；helper.jai（#program_export + Remap_Context 1-28）；backchannel.jai（#add_context 共享数据 1-5）。
- `examples/output_types/build.jai`：四种输出类型 workspace 49-52；无自定义链接命令。
- `examples/ios_library/library.jai`：#program_export + #c_call + push_context 1-20。
- `CHANGELOG.txt`：8321（C 调用约定的动态库）；6792（output_types 示例）；6784-6786（OBJECT_FILE/STATIC_LIBRARY）。
- 发行版根 `README.txt`：Windows 编译需要 Windows SDK 与 VC++ Redistributable。

实验（本机，Windows 11，`C:/Users/maojiaxing/AppData/Local/Temp/juice_dll_research`）：

- `jai build.jai` 链接行输出、产物清单、`dumpbin /EXPORTS` 输出、`loader6.exe` 运行输出：见"实验记录"节（均为运行原文）。

本仓库（工作树，行号以研究时为准）：

- `modules/Juice.jai`：Package_Type 4-7；Target 10-13；Effective_Target 16-20；Artifact_Plan 23-27；Package 41-56。
- `src/target.jai`：make_artifact_plan 133-150（.exe 硬编码 138-142）；make_effective_target 55-90；revalidate_artifact_plan 167-179。
- `src/commands/build.jai`：compile_artifact_plan 69-103（jai 调用 84-87，产物校验 98-101）。
- `src/commands/run.jai`：run_artifact_plan 50-63；run_prepared_workspace 的 launch 参数 65-82；select_artifact_plan 33-48。
- `src/commands/registry.jai`：注册表 1-7。
- `src/commands/command.jai`：Command 结构 9-17。
- `CONTEXT.md`：Build 13-14；Run 16-17；Effective target 48-49；Artifact plan 51-52；Artifact 54-55；Result directory 57-58；Package type 不限制 executable target 83。
