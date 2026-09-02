#import "Basic";
#import "File";
#import "String";
#import "Compiler";

#import "Juice";

MANIFEST_TEMPLATE :: #string JAI
#import "Basic";
#import "File";
#import "Juice";

#load "%1";

main :: () {
	builder: String_Builder;
	print_to_builder(*builder, "NAME=%\n", PACKAGE.name);
	print_to_builder(*builder, "VERSION=%\n", PACKAGE.version);
    print_to_builder(*builder, "TYPE=%\n", cast(s64) PACKAGE.type);
    print_to_builder(*builder, "ROOT_FILE=%\n", PACKAGE.root_file);
    print_to_builder(*builder, "BUILD_SCRIPT=%\n", PACKAGE.build_script);

    for target: PACKAGE.targets {
        print_to_builder(*builder, "TARGET=%1|%2|%3\n", target.name, target.main_file, target.output_dir);
    }

    for member: PACKAGE.workspace.members {
        print_to_builder(*builder, "MEMBER=%\n", member);
    }

    for dep: PACKAGE.dependencies {
        print_to_builder(*builder, "DEP=%1|%2|%3|%4\n", dep.name, dep.version, dep.source, dep.package);
    }

    write_entire_file("%2", builder_to_string(*builder));
}
JAI;

load_package_manifest :: (driver: *Build_Driver, dir: string) -> Package, bool {
	manifest_path := tprint("%1/package.jai", dir);
    if !file_exists(manifest_path) return .{}, false;

    dir_safe_name := sanitize_path_to_filename(dir);
    eval_cache_dir := tprint("%1/eval_tmp/%2", driver.cache_dir, dir_safe_name);

    make_directory_if_it_does_not_exist(eval_cache_dir, recursive = true);
    defer delete_directory_full(eval_cache_dir);

    eval_src_path := tprint("%1/eval_gen.jai", eval_cache_dir);
    out_data_path := tprint("%1/pkg_out.txt", eval_cache_dir);

    gen_code := tprint(MANIFEST_TEMPLATE, manifest_path, out_data_path);
    write_entire_file(eval_src_path, gen_code);

    w := compiler_create_workspace(tprint("Manifest Evaluator - %1", dir_safe_name));
    options := get_build_options(w);
    options.output_executable_name = "eval_gen";
    options.output_path            = eval_cache_dir;
    options.output_type            = .EXECUTABLE;

    import_paths: [..] string;
    array_add(*import_paths, .. options.import_path);
    array_add(*import_paths, "./modules");
    options.import_path = import_paths;
    set_build_options(options, w);

    compiler_begin_intercept(w);
    add_build_file(eval_src_path, w);

    comp_success := true;
    while true {
        msg := compiler_wait_for_message();
        if !msg continue;
        if msg.kind == {
            case .ERROR;    comp_success = false;
            case .COMPLETE; break;
        }
    }
    compiler_end_intercept(w);

    if !comp_success return .{}, false;

    eval_bin := tprint("%1/eval_gen", eval_cache_dir);
    res_eval := run_command(eval_bin);
    if res_eval.exit_code != 0 return .{}, false;

    data_content, read_ok := read_entire_file(out_data_path);
    if !read_ok return .{}, false;

    return parse_package_manifest_output(data_content), true;
}

parse_package_manifest_output :: (content: string) -> Package {
    pkg: Package;
    targets: [..] Binary_Target;
    members: [..] string;
    deps:    [..] Dependency;

    lines := split(content, "\n");
    for line : lines {
        trimmed := trim(line);
        if trimmed == "" continue;

        if starts_with(trimmed, "NAME=") {
            pkg.name = copy_string(advance(trimmed, 5));
        } else if starts_with(trimmed, "VERSION=") {
            pkg.version = copy_string(advance(trimmed, 8));
        } else if starts_with(trimmed, "TYPE=") {
            val_str := advance(trimmed, 5);
            val_int := parse_int(*val_str);
            pkg.type = cast(Package_Type) val_int;
        } else if starts_with(trimmed, "ROOT_FILE=") {
            pkg.root_file = copy_string(advance(trimmed, 10));
        } else if starts_with(trimmed, "BUILD_SCRIPT=") {
            pkg.build_script = copy_string(advance(trimmed, 13));
        } else if starts_with(trimmed, "TARGET=") {
            raw := advance(trimmed, 7);
            parts := split(raw, "|");
            if parts.count >= 3 {
                t: Binary_Target;
                t.name       = copy_string(parts[0]);
                t.main_file  = copy_string(parts[1]);
                t.output_dir = copy_string(parts[2]);
                array_add(*targets, t);
            }
        } else if starts_with(trimmed, "MEMBER=") {
            array_add(*members, copy_string(advance(trimmed, 7)));
        } else if starts_with(trimmed, "DEP=") {
            raw := advance(trimmed, 4);
            parts := split(raw, "|");
            if parts.count >= 4 {
                d: Dependency;
                d.name    = copy_string(parts[0]);
                d.version = copy_string(parts[1]);
                d.source  = copy_string(parts[2]);
                d.package = copy_string(parts[3]);
                array_add(*deps, d);
            }
        }
    }

    pkg.targets           = targets;
    pkg.workspace.members = members;
    pkg.dependencies      = deps;

    return pkg;
}

sanitize_path_to_filename :: (path: string) -> string {
    builder: String_Builder;
    for i: 0..path.count-1 {
        ch := path[i];
        if (ch >= #char "a" && ch <= #char "z") || 
           (ch >= #char "A" && ch <= #char "Z") || 
           (ch >= #char "0" && ch <= #char "9") {
            append(*builder, ch);
        } else {
            append(*builder, #char "_");
        }
    }
    return builder_to_string(*builder);
}