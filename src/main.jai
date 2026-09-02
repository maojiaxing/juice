#import "Basic";
#import "System";

#import "Juice";

#load "xdg.jai";
#load "manifest.jai";
#load "dependency.jai";
#load "builder.jai";

main :: () {
    auto_release_temp();

    args := get_command_line_arguments();
    command := ifx args.count > 1 then args[1] else "build";

    driver: Build_Driver;
    driver.root_dir     = get_working_directory();
    driver.packages_dir = tprint("%1/.packages", driver.root_dir);
    driver.bin_dir      = tprint("%1/bin", driver.root_dir);
    
    // 初始化 XDG 路径
    driver.cache_dir    = tprint("%1/juice", get_cache_home());
    driver.data_dir     = tprint("%1/juice", get_data_home());
    driver.config_dir   = tprint("%1/juice", get_config_home());

    print("[juice 🍹] Squeezing build dependencies in %1 ...\n", driver.root_dir);

    // 1. 加载根目录 package.jai
    root_pkg, ok := load_package_manifest(*driver, driver.root_dir);
    if !ok {
        print("[juice ERROR] Could not load 'package.jai' in directory: %1\n", driver.root_dir);
        exit(1);
    }

    print("[juice] Package '%1' (v%2) loaded.\n", root_pkg.name, root_pkg.version);

    // 2. 解析 Workspace 成员路径
    array_add(*driver.member_paths, driver.root_dir);
    if root_pkg.workspace.members.count > 0 {
        for rel_path : root_pkg.workspace.members {
            abs_path := tprint("%1/%2", driver.root_dir, rel_path);
            array_add(*driver.member_paths, abs_path);
        }
    }

    // 3. 全局依赖解析与提升
    if !resolve_and_fetch_dependencies(*driver, root_pkg) {
        print("[juice ERROR] Dependency resolution failed.\n");
        exit(1);
    }

    // 4. 执行 CLI 指令
    if command == {
        case "build";
            if !build_all_targets(*driver, root_pkg) exit(1);
            print("[juice 🍹] Build completed successfully!\n");

        case "run";
            target_name := ifx args.count > 2 then args[2] else "";
            if build_all_targets(*driver, root_pkg) {
                run_executable(*driver, root_pkg, target_name);
            } else {
                exit(1);
            }

        case "clean";
            clean_workspace(*driver);

        case;
            print("[juice ERROR] Unknown command: %1\n", command);
            print("Usage: juice [build|run|clean]\n");
            exit(1);
    }
}