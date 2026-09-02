#import "Basic";
#import "Compiler";
#import "File";
#import "Process";

#import "Juice";

Build_Driver :: struct {
    root_dir:     string;
    packages_dir: string;
    bin_dir:      string;
    cache_dir:    string;
    data_dir:     string;
    config_dir:   string;
    member_paths: [..] string;
}

build_all_targets :: (driver: *Build_Driver, root_pkg: Package) -> bool {
    make_directory_if_it_does_not_exist(driver.bin_dir, recursive = true);

    for member_path : driver.member_paths {
        pkg, ok := load_package_manifest(driver, member_path);
        if !ok continue;

        if pkg.type == .LIB {
            print("[juice] Verified Library '%1'\n", pkg.name);
            continue;
        }

        targets := pkg.targets;
        if targets.count == 0 {
            default_target: Binary_Target;
            default_target.name = pkg.name;
            default_target.main_file = "src/main.jai";
            array_add(*targets, default_target);
        }

        for target : targets {
            if !compile_binary_target(driver, member_path, target) return false;
        }
    }
    return true;
}

compile_binary_target :: (driver: *Build_Driver, pkg_dir: string, target: Binary_Target) -> bool {
    out_dir := ifx target.output_dir != "" then target.output_dir else driver.bin_dir;

    print("[juice Build] Compiling Target '%1' (%2) -> %3/%1 ...\n", target.name, target.main_file, out_dir);

    w := compiler_create_workspace(target.name);
    options := get_build_options(w);

    options.output_executable_name = target.name;
    options.output_path            = out_dir;

    import_paths: [..] string;
    array_add(*import_paths, .. options.import_path);
    array_add(*import_paths, driver.packages_dir);

    for path : driver.member_paths {
        array_add(*import_paths, path);
    }

    options.import_path = import_paths;
    set_build_options(options, w);

    compiler_begin_intercept(w);
    main_entry := tprint("%1/%2", pkg_dir, target.main_file);
    add_build_file(main_entry, w);

    success := true;
    while true {
        msg := compiler_wait_for_message();
        if !msg continue;
        if msg.kind == {
            case .ERROR;    success = false;
            case .COMPLETE; break;
        }
    }
    compiler_end_intercept(w);

    return success;
}

run_executable :: (driver: *Build_Driver, root_pkg: Package, target_name: string) {
    exec_name := target_name;
    if exec_name == "" && root_pkg.targets.count > 0 {
        exec_name = root_pkg.targets[0].name;
    }
    if exec_name == "" exec_name = root_pkg.name;

    bin_path := tprint("%1/%2", driver.bin_dir, exec_name);
    if !file_exists(bin_path) {
        print("[juice ERROR] Executable binary not found: %1\n", bin_path);
        return;
    }

    print("[juice Run] Running %1 ...\n\n", bin_path);
    run_command(bin_path);
}

clean_workspace :: (driver: *Build_Driver) {
    print("[juice Clean] Cleaning output directories...\n");
    delete_directory_full(driver.bin_dir);
    delete_directory_full(driver.packages_dir);
    print("[juice Clean] Workspace cleaned.\n");
}