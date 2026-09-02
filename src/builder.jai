#import "Basic";
#import "Process";
#import "File";
#import "String";

Build_Driver :: struct {
    root_dir:     string;
    packages_dir: string;
    bin_dir:      string;
    cache_dir:    string;
    data_dir:     string;
    config_dir:   string;
    member_paths: [..] string;
} 

compile_binary_target :: (driver: *Build_Driver, pkg: *Package, target: *Binary_Target) -> bool {
    source_file := to_forward_slashes(tprint("%1/%2", pkg.dir, target.main_file));
    output_dir  := to_forward_slashes(tprint("%1/%2", pkg.dir, target.output_dir));

    if !file_exists(source_file) {
        print("[juice ERROR] Target source file not found: %\n", source_file);
        return false;
    }

    make_directory_if_it_does_not_exist(output_dir, recursive = true);

    print("[juice Build] Compiling Target '%' (%) -> %/...\n", target.name, target.main_file, target.output_dir);

    // 构建命令行参数：jai <源文件> -exe <程序名> -output_path <输出路径>
    args: [..] string;
    array_add(*args, "jai");
    array_add(*args, source_file);
    array_add(*args, "-exe", target.name);
    array_add(*args, "-output_path", output_dir);

    // 如果包含 juice 全局 modules 目录，自动引入
    exe_path := get_path_of_running_executable();
    bin_dir  := path_strip_filename(exe_path);
    global_modules_dir := to_forward_slashes(tprint("%1/../modules", bin_dir));
    if is_directory(global_modules_dir) {
        array_add(*args, "-import_dir", global_modules_dir);
    }

    // 引入已解析依赖和 workspace 成员的导入路径
    if is_directory(driver.packages_dir) {
        array_add(*args, "-import_dir", to_forward_slashes(driver.packages_dir));
    }
    for member_path: driver.member_paths {
        if is_directory(member_path) {
            array_add(*args, "-import_dir", to_forward_slashes(member_path));
        }
    }

    // 执行编译命令
    result := run_command(..args);
    if result.exit_code != 0 {
        print("[juice ERROR] Compilation failed for target '%'\n", target.name);
        return false;
    }

    return true;
}

// 编译包中的所有 Target
build_all_targets :: (driver: *Build_Driver, pkg: *Package) -> bool {
    if pkg.targets.count == 0 {
        // 如果 package.jai 没有显式定义 targets，默认按 src/main.jai 编译
        default_target := Binary_Target.{
            name = pkg.name,
            main_file = "src/main.jai",
            output_dir = "bin"
        };
        return compile_binary_target(driver, pkg, *default_target);
    }

    for * target: pkg.targets {
        success := compile_binary_target(driver, pkg, target);
        if !success return false;
    }

    return true;
}

// 执行编译完成后的程序（用于 juice run 命令）
run_executable :: (driver: *Build_Driver, pkg: *Package, requested_target: string) -> bool {
    target_name := ifx requested_target != "" then requested_target else pkg.name;
    output_dir  := "bin";

    if pkg.targets.count > 0 {
        found := false;
        for target: pkg.targets {
            if requested_target == "" || target.name == requested_target {
                target_name = target.name;
                output_dir = ifx target.output_dir != "" then target.output_dir else "bin";
                found = true;
                break;
            }
        }

        if !found {
            print("[juice ERROR] Unknown binary target: %\n", requested_target);
            return false;
        }
    } else if requested_target != "" && requested_target != pkg.name {
        print("[juice ERROR] Unknown binary target: %\n", requested_target);
        return false;
    }

    #if OS == .WINDOWS {
        exe_path := to_forward_slashes(tprint("%1/%2/%3.exe", pkg.dir, output_dir, target_name));
    } else {
        exe_path := to_forward_slashes(tprint("%1/%2/%3", pkg.dir, output_dir, target_name));
    }

    if !file_exists(exe_path) {
        print("[juice ERROR] Could not find executable to run: %\n", exe_path);
        return false;
    }

    print("[juice Run] Launching % ...\n\n", exe_path);

    result := run_command(exe_path);
    return result.exit_code == 0;
}

clean_workspace :: (driver: *Build_Driver) {
    print("[juice Clean] Cleaning output directories...\n");
    delete_directory_full(driver.bin_dir);
    delete_directory_full(driver.packages_dir);
    print("[juice Clean] Workspace cleaned.\n");
}
