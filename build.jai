#import "Basic";
#import "String";
#import "File";
#import "Compiler";

#run {
    // -------------------------------------------------------------
    // 1. 读取命令行参数
    // -------------------------------------------------------------
    options_main := get_build_options();
    build_args := options_main.compile_time_command_line;

    is_release := false;
    for arg: build_args {
        if arg == "release" || arg == "-release" {
            is_release = true;
        } else if arg == "debug" || arg == "-debug" {
            is_release = false;
        }
    }

    // -------------------------------------------------------------
    // 2. 创建目标程序的 Workspace
    // -------------------------------------------------------------
    set_build_options_dc(.{do_output = false});
    workspace := compiler_create_workspace("Juice App");
    if !workspace return;

    // -------------------------------------------------------------
    // 3. 配置目标 Workspace 选项
    // -------------------------------------------------------------
    options := get_build_options(workspace);
    options.output_executable_name = "juice";
    options.output_path            = "bin";

    // 关键：确保 bin 目录存在，防止链接器报错 LNK1104
    make_directory_if_it_does_not_exist(options.output_path);

    // 模块导入路径设置
    import_paths: [..] string;
    array_add(*import_paths, .. options.import_path);
    array_add(*import_paths, "./src");
    array_add(*import_paths, "./modules");
    array_add(*import_paths, ".");
    options.import_path = import_paths;

    if is_release {
        print("[Build System] 🚀 Building in RELEASE mode (Very Optimized)...\n");
        set_optimization(*options, .VERY_OPTIMIZED);
    } else {
        print("[Build System] 🛠️  Building in DEBUG mode...\n");
        set_optimization(*options, .DEBUG);
    }

    // -------------------------------------------------------------
    // 4. 应用配置（必须在 begin_intercept 和 add_build_file 之前）
    // -------------------------------------------------------------
    set_build_options(options, workspace);

    // -------------------------------------------------------------
    // 5. 开启拦截并加载入口文件
    // -------------------------------------------------------------
    compiler_begin_intercept(workspace);
    add_build_file("src/main.jai", workspace);

    // -------------------------------------------------------------
    // 6. 编译期消息循环与错误拦截
    // -------------------------------------------------------------
    has_errors := false;
    while true {
        msg := compiler_wait_for_message();
        if !msg continue;

        if msg.workspace == workspace {
            if msg.kind == {
                case .ERROR;
                    has_errors = true;
                case .COMPLETE;
                    break;
            }
        }
    }

    compiler_end_intercept(workspace);

    if !has_errors {
        mode_str := ifx is_release then "Release" else "Debug";
        print("[Build System] ✅ %1 build succeeded! Binary -> %2/%3.exe\n", 
              mode_str, options.output_path, options.output_executable_name);
    } else {
        print("[Build System] ❌ Build failed.\n");
    }
}