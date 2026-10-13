#import "Basic";
#import "File";
#import "Hash";
#import "Process";
#import "String";
#import "System";
#import "Juice";

Manifest_Parse_Result :: struct {
    success:      bool;
    package:      Package;
    line_number:  int;
    error_message: string;
}

to_forward_slashes :: (path: string) -> string {
    return path_slashes(path);
}

// Generate a tiny evaluator program. The evaluator is intentionally the only
// way package.jai is interpreted; its stdout is never used as the protocol.
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
    append(*builder, "    print_to_builder(*builder, \"DESCRIPTION=%\\n\", PACKAGE.description);\n");
    append(*builder, "    print_to_builder(*builder, \"BUILD_SCRIPT=%\\n\", PACKAGE.build_script);\n\n");

    append(*builder, "    for target: PACKAGE.targets {\n");
    append(*builder, "        print_to_builder(*builder, \"TARGET=%1|%2\\n\", target.name, target.main_file);\n");
    append(*builder, "    }\n\n");

    append(*builder, "    for member: PACKAGE.workspace.members {\n");
    append(*builder, "        print_to_builder(*builder, \"MEMBER=%\\n\", member);\n");
    append(*builder, "    }\n\n");

    append(*builder, "    for excluded: PACKAGE.workspace.exclude {\n");
    append(*builder, "        print_to_builder(*builder, \"EXCLUDE=%\\n\", excluded);\n");
    append(*builder, "    }\n\n");

    append(*builder, "    for dep: PACKAGE.dependencies {\n");
    append(*builder, "        print_to_builder(*builder, \"DEP=%1|%2|%3|%4\\n\", dep.name, dep.version, dep.source, dep.package);\n");
    append(*builder, "    }\n\n");

    // 写失败必须让 child 以非零退出码失败（票 0035）：旧实现静默忽略写入
    // 结果，child 退出码仍为 0，父进程会把陈旧/缺失数据当作成功——偶发
    // workspace member 丢失或 "Failed to fetch dependency"。退出码 2 是
    // 「manifest 数据写失败」专用信号，父进程据此重试；manifest 编译错误等
    // 其他失败仍是退出码 1，不触发重试。
    append(*builder, "    if !write_entire_file(\"");
    append(*builder, clean_output);
    append(*builder, "\", builder_to_string(*builder)) {\n");
    append(*builder, "        print(\"[manifest-eval ERROR] Could not write manifest data: ");
    append(*builder, clean_output);
    append(*builder, "\\n\");\n");
    append(*builder, "        exit(2);\n");
    append(*builder, "    }\n");
    append(*builder, "}\n");

    return builder_to_string(*builder);
}

parse_manifest_data_strict :: (content: string) -> Manifest_Parse_Result {
    result: Manifest_Parse_Result;

    seen_name := false;
    seen_version := false;
    seen_type := false;
    seen_description := false;
    seen_build_script := false;

    targets: [..] Target;
    members: [..] string;
    excluded: [..] string;
    deps: [..] Dependency;

    lines := split(content, "\n");
    for line, line_index: lines {
        trimmed := trim(line, " \r\t\n");
        if trimmed.count == 0 continue;

        found, key, value := split_from_left(trimmed, #char "=");
        if !found || key == "" {
            result.line_number = line_index + 1;
            result.error_message = tprint("Malformed manifest record on line %.", line_index + 1);
            return result;
        }
        key = trim(key, " \r\t");
        value = trim(value, " \r\t");
        if key == "" {
            result.line_number = line_index + 1;
            result.error_message = tprint("Manifest record has an empty key on line %.", line_index + 1);
            return result;
        }

        if key == {
            case "NAME";
                if seen_name return manifest_parse_failure(line_index + 1, "Duplicate NAME record.");
                seen_name = true;
                result.package.name = copy_string(value);

            case "VERSION";
                if seen_version return manifest_parse_failure(line_index + 1, "Duplicate VERSION record.");
                seen_version = true;
                result.package.version = copy_string(value);

            case "TYPE";
                if seen_type return manifest_parse_failure(line_index + 1, "Duplicate TYPE record.");
                seen_type = true;
                if value == "" {
                    result.package.type = .UNSPECIFIED;
                } else {
                    enum_value, enum_ok, remainder := string_to_int(value);
                    if !enum_ok || remainder.count != 0 || (enum_value != 0 && enum_value != 1 && enum_value != 2) {
                        return manifest_parse_failure(line_index + 1, "Invalid package type enum.");
                    }
                    result.package.type = cast(Package_Type) enum_value;
                }

            case "DESCRIPTION";
                if seen_description return manifest_parse_failure(line_index + 1, "Duplicate DESCRIPTION record.");
                seen_description = true;
                result.package.description = copy_string(value);

            case "BUILD_SCRIPT";
                if seen_build_script return manifest_parse_failure(line_index + 1, "Duplicate BUILD_SCRIPT record.");
                seen_build_script = true;
                result.package.build_script = copy_string(value);

            case "TARGET";
                parts := split(value, "|");
                if parts.count != 2 return manifest_parse_failure(line_index + 1, "TARGET record must contain name|main_file.");
                target: Target;
                target.name = copy_string(parts[0]);
                target.main_file = copy_string(parts[1]);
                array_add(*targets, target);

            case "MEMBER";
                if value == "" return manifest_parse_failure(line_index + 1, "MEMBER record cannot be empty.");
                array_add(*members, copy_string(value));

            case "EXCLUDE";
                if value == "" return manifest_parse_failure(line_index + 1, "EXCLUDE record cannot be empty.");
                array_add(*excluded, copy_string(value));

            case "DEP";
                parts := split(value, "|");
                if parts.count != 4 return manifest_parse_failure(line_index + 1, "DEP record must contain four fields.");
                dep: Dependency;
                dep.name = copy_string(parts[0]);
                dep.version = copy_string(parts[1]);
                dep.source = copy_string(parts[2]);
                dep.package = copy_string(parts[3]);
                array_add(*deps, dep);

            case;
                return manifest_parse_failure(line_index + 1, tprint("Unknown manifest record: %1", key));
        }
    }

    result.package.targets = targets;
    result.package.workspace.members = members;
    result.package.workspace.exclude = excluded;
    result.package.dependencies = deps;
    result.success = true;
    return result;
}

manifest_parse_failure :: (line_number: int, message: string) -> Manifest_Parse_Result {
    return .{success = false, line_number = line_number, error_message = copy_string(message)};
}

// Kept as a small convenience for pure parser callers. Callers that need the
// diagnostic should use parse_manifest_data_strict().
parse_manifest_data :: (content: string) -> Package {
    result := parse_manifest_data_strict(content);
    return result.package;
}

// FNV-1a 64 位散列 → 16 位小写十六进制（本地复制：与 src/transpile_cache.jai
// 的 hash_hex 同语义）。#load 注入的声明跨文件共享（如 to_forward_slashes），
// 但仅对 #load 语句之后加载的文件可见：main.jai 中 manifest.jai 先于
// transpile_cache.jai 加载，故此处不可见 hash_hex 声明；调整 #load 顺序会
// 牵动生产构建链（transpile_cache 依赖 transpile.jai 的类型），保持复制。
manifest_hash_hex :: (s: string) -> string {
    hash := fnv1a_hash(s.data, s.count);
    out: [16] u8;
    for i: 0..15 {
        nibble := cast(s64) ((hash >> cast(u64) (4 * (15 - i))) & 0xf);
        out[i] = cast(u8) ifx nibble < 10 then #char "0" + nibble else #char "a" + (nibble - 10);
    }
    return copy_string(to_string(out.data, 16));
}

// 临时文件命名（票 0035）：manifest 求值器的临时文件曾共享固定名
// （eval_manifest.jai / manifest_data.txt）——连序或并发的求值 child 进程
// 互相覆盖：前一 child 写完的文件被瞬时锁定（AV），后一 child 写失败却静默
// 读到陈旧 manifest 数据（偶发 workspace member 丢失）。现按被求值 manifest
// 的绝对路径散列命名：不同 manifest 绝不同名，跨进程互不干扰；同一 manifest
// 的并发求值内容相同，同名无害。
manifest_temp_file_names :: (cache_dir: string, pkg_dir: string) -> (string, string) {
    stem := manifest_hash_hex(pkg_dir);
    eval_src := to_forward_slashes(tprint("%1/eval_manifest_%2.jai", cache_dir, stem));
    eval_out := to_forward_slashes(tprint("%1/manifest_data_%2.txt", cache_dir, stem));
    return eval_src, eval_out;
}

load_package_manifest :: (driver: *Build_Driver, pkg_dir: string) -> Package, bool {
    manifest_path := to_forward_slashes(tprint("%1/package.jai", pkg_dir));
    if !file_exists(manifest_path) return .{}, false;

    if !make_directory_if_it_does_not_exist(driver.cache_dir, recursive = true) {
        print("[juice ERROR] Could not create manifest cache directory: %\n", driver.cache_dir);
        return .{}, false;
    }
    temp_eval_src, temp_eval_out := manifest_temp_file_names(driver.cache_dir, pkg_dir);

    eval_code := build_eval_code(manifest_path, temp_eval_out);
    if !write_entire_file(temp_eval_src, eval_code) {
        print("[juice ERROR] Could not write manifest evaluator: %\n", temp_eval_src);
        return .{}, false;
    }

    exe_path := get_path_of_running_executable();
    bin_dir  := path_strip_filename(exe_path);
    global_modules_dir := to_forward_slashes(tprint("%1/../modules", bin_dir));

    // 数据写失败（退出码 2）重试至多两次（票 0035）：瞬时文件锁（AV 等）随
    // 重试消失；重试沿用同一临时文件对（同 manifest 同名，写入失败前文件
    // 内容未变，重试直接覆盖）。其余非零退出码是真正的求值失败，立即报错。
    attempts := 0;
    while true {
        result := run_command("jai", temp_eval_src, "-import_dir", global_modules_dir, "-quiet");
        if result.exit_code == 0 break;
        if result.exit_code == 2 && attempts < 2 {
            attempts += 1;
            print("[juice] Manifest evaluator failed to write its data (transient); retrying (%1/2)...\n", attempts);
            continue;
        }
        print("[juice ERROR] Failed to evaluate manifest at %\n", manifest_path);
        return .{}, false;
    }

    content, ok := read_entire_file(temp_eval_out);
    if !ok {
        print("[juice ERROR] Could not read manifest output file: %\n", temp_eval_out);
        return .{}, false;
    }

    parsed := parse_manifest_data_strict(content);
    if !parsed.success {
        print("[juice ERROR] Invalid manifest protocol at % (line %): %\n", manifest_path, parsed.line_number, parsed.error_message);
        return .{}, false;
    }
    parsed.package.dir = copy_string(pkg_dir);
    return parsed.package, true;
}
