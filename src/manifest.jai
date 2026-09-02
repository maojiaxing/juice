#import "Basic";
#import "File";
#import "Process";
#import "String";
#import "System";
#import "Juice";

to_forward_slashes :: (path: string) -> string {
    res := copy_string(path);
    for i: 0..res.count-1 {
        if res[i] == #char "\\" {
            res[i] = #char "/";
        }
    }
    return res;
}

// 使用 String_Builder 构建评估中间代码，完全避开 tprint 的 % 占位符冲突
build_eval_code :: (manifest_path: string, output_path: string) -> string {
    clean_manifest := to_forward_slashes(manifest_path);
    clean_output   := to_forward_slashes(output_path);

    builder: String_Builder;
    append(*builder, "#import \"Basic\";\n");
    append(*builder, "#import \"File\";\n");
    append(*builder, "#import \"Juice\";\n\n");
    append(*builder, "#import \"Compiler\";\n");
    
    append(*builder, "#load \"");
    append(*builder, clean_manifest);
    append(*builder, "\";\n\n");

    append(*builder, "#run {\n");
    append(*builder, "    set_build_options_dc(.{do_output=false});\n");
    append(*builder, "    main();\n");
    append(*builder, "}\n\n");

    append(*builder, "main :: () {\n");
    append(*builder, "    builder: String_Builder;\n");
    append(*builder, "    print_to_builder(*builder, \"NAME=%\\n\", PACKAGE.name);\n");
    append(*builder, "    print_to_builder(*builder, \"VERSION=%\\n\", PACKAGE.version);\n");
    append(*builder, "    print_to_builder(*builder, \"TYPE=%\\n\", cast(s64) PACKAGE.type);\n");
    append(*builder, "    print_to_builder(*builder, \"ROOT_FILE=%\\n\", PACKAGE.root_file);\n");
    append(*builder, "    print_to_builder(*builder, \"BUILD_SCRIPT=%\\n\", PACKAGE.build_script);\n\n");

    append(*builder, "    for target: PACKAGE.targets {\n");
    append(*builder, "        print_to_builder(*builder, \"TARGET=%1|%2|%3\\n\", target.name, target.main_file, target.output_dir);\n");
    append(*builder, "    }\n\n");

    append(*builder, "    for member: PACKAGE.workspace.members {\n");
    append(*builder, "        print_to_builder(*builder, \"MEMBER=%\\n\", member);\n");
    append(*builder, "    }\n\n");

    append(*builder, "    for dep: PACKAGE.dependencies {\n");
    append(*builder, "        print_to_builder(*builder, \"DEP=%1|%2|%3|%4\\n\", dep.name, dep.version, dep.source, dep.package);\n");
    append(*builder, "    }\n\n");

    append(*builder, "    write_entire_file(\"");
    append(*builder, clean_output);
    append(*builder, "\", builder_to_string(*builder));\n");
    append(*builder, "}\n");

    return builder_to_string(*builder);
}

load_package_manifest :: (driver: *Build_Driver, pkg_dir: string) -> Package, bool {
    manifest_path := to_forward_slashes(tprint("%1/package.jai", pkg_dir));
    if !file_exists(manifest_path) return .{}, false;

    // 1. 确保缓存目录存在
    make_directory_if_it_does_not_exist(driver.cache_dir, recursive = true);
    temp_eval_src := to_forward_slashes(tprint("%1/eval_manifest.jai", driver.cache_dir));
    temp_eval_out := to_forward_slashes(tprint("%1/manifest_data.txt", driver.cache_dir));

    // 2. 生成评估代码并写入临时文件
    eval_code := build_eval_code(manifest_path, temp_eval_out);
    write_entire_file(temp_eval_src, eval_code);

    // 3. 推导 Juice 的全局 modules 目录路径
    exe_path := get_path_of_running_executable();
    bin_dir  := path_strip_filename(exe_path);
    global_modules_dir := to_forward_slashes(tprint("%1/../modules", bin_dir));

    // 4. 调用外部 jai 编译器评估，并添加 -import_dir 参数告诉编译器 Juice 模块的位置
    result := run_command("jai", temp_eval_src, "-import_dir", global_modules_dir, "-quiet");
    if result.exit_code != 0 {
        print("[juice ERROR] Failed to evaluate manifest at %\n", manifest_path);
        return .{}, false;
    }

    // 5. 读取解析生成的结果数据
    content, ok := read_entire_file(temp_eval_out);
    if !ok {
        print("[juice ERROR] Could not read manifest output file: %\n", temp_eval_out);
        return .{}, false;
    }

    pkg := parse_manifest_data(content);
    pkg.dir = copy_string(pkg_dir);
    return pkg, true;
}

parse_manifest_data :: (content: string) -> Package {
    pkg: Package;

    targets: [..] Binary_Target;
    members: [..] string;
    deps:    [..] Dependency;

    lines := split(content, "\n");
    for line: lines {
        trimmed := trim(line, " \r\t\n");
        if trimmed.count == 0 continue;

        found, key, value := split_from_left(trimmed, #char "=");
        if !found continue;

        if key == {
            case "NAME";
                pkg.name = copy_string(value);
            case "VERSION";
                pkg.version = copy_string(value);
            case "TYPE";
                pkg.type = cast(Package_Type) string_to_int(value);
            case "ROOT_FILE";
                pkg.root_file = copy_string(value);
            case "BUILD_SCRIPT";
                pkg.build_script = copy_string(value);
            case "TARGET";
                parts := split(value, "|");
                if parts.count >= 3 {
                    target: Binary_Target;
                    target.name = copy_string(parts[0]);
                    target.main_file = copy_string(parts[1]);
                    target.output_dir = copy_string(parts[2]);
                    array_add(*targets, target);
                }
            case "MEMBER";
                array_add(*members, copy_string(value));
            case "DEP";
                parts := split(value, "|");
                if parts.count >= 4 {
                    dep: Dependency;
                    dep.name = copy_string(parts[0]);
                    dep.version = copy_string(parts[1]);
                    dep.source = copy_string(parts[2]);
                    dep.package = copy_string(parts[3]);
                    array_add(*deps, dep);
                }
        }
    }

    pkg.targets = targets;
    pkg.workspace.members = members;
    pkg.dependencies = deps;

    return pkg;
}