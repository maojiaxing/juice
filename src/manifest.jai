#import "Basic";
#import "File";
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
    append(*builder, "    print_to_builder(*builder, \"ROOT_FILE=%\\n\", PACKAGE.root_file);\n");
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

    append(*builder, "    write_entire_file(\"");
    append(*builder, clean_output);
    append(*builder, "\", builder_to_string(*builder));\n");
    append(*builder, "}\n");

    return builder_to_string(*builder);
}

parse_manifest_data_strict :: (content: string) -> Manifest_Parse_Result {
    result: Manifest_Parse_Result;
    result.package.type = .BIN;
    result.package.root_file = "modulejai";

    seen_name := false;
    seen_version := false;
    seen_type := false;
    seen_description := false;
    seen_root_file := false;
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
                    result.package.type = .BIN;
                } else {
                    enum_value, enum_ok, remainder := string_to_int(value);
                    if !enum_ok || remainder.count != 0 || (enum_value != 0 && enum_value != 1) {
                        return manifest_parse_failure(line_index + 1, "Invalid package type enum.");
                    }
                    result.package.type = cast(Package_Type) enum_value;
                }

            case "DESCRIPTION";
                if seen_description return manifest_parse_failure(line_index + 1, "Duplicate DESCRIPTION record.");
                seen_description = true;
                result.package.description = copy_string(value);

            case "ROOT_FILE";
                if seen_root_file return manifest_parse_failure(line_index + 1, "Duplicate ROOT_FILE record.");
                seen_root_file = true;
                if value != "" result.package.root_file = copy_string(value);

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

load_package_manifest :: (driver: *Build_Driver, pkg_dir: string) -> Package, bool {
    manifest_path := to_forward_slashes(tprint("%1/package.jai", pkg_dir));
    if !file_exists(manifest_path) return .{}, false;

    if !make_directory_if_it_does_not_exist(driver.cache_dir, recursive = true) {
        print("[juice ERROR] Could not create manifest cache directory: %\n", driver.cache_dir);
        return .{}, false;
    }
    temp_eval_src := to_forward_slashes(tprint("%1/eval_manifest.jai", driver.cache_dir));
    temp_eval_out := to_forward_slashes(tprint("%1/manifest_data.txt", driver.cache_dir));

    eval_code := build_eval_code(manifest_path, temp_eval_out);
    if !write_entire_file(temp_eval_src, eval_code) {
        print("[juice ERROR] Could not write manifest evaluator: %\n", temp_eval_src);
        return .{}, false;
    }

    exe_path := get_path_of_running_executable();
    bin_dir  := path_strip_filename(exe_path);
    global_modules_dir := to_forward_slashes(tprint("%1/../modules", bin_dir));

    result := run_command("jai", temp_eval_src, "-import_dir", global_modules_dir, "-quiet");
    if result.exit_code != 0 {
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
