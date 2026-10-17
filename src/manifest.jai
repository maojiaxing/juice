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

    // A write failure must fail the child with a nonzero exit code: the old
    // implementation silently ignored the write result, the child still
    // exited 0, and the parent treated stale/missing data as success —
    // occasionally losing a workspace member or reporting "Failed to fetch
    // dependency". Exit code 2 is the dedicated "manifest data write failed"
    // signal the parent retries on; other failures (manifest compile errors
    // etc.) stay exit code 1 and never trigger a retry.
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

// FNV-1a 64-bit hash rendered as 16 lowercase hex characters (a local copy:
// same semantics as src/transpile_cache.jai's hash_hex). Declarations
// injected via #load are shared across files (like to_forward_slashes) but
// only visible to files loaded after the #load statement: main.jai loads
// manifest.jai before transpile_cache.jai, so hash_hex is not visible here;
// reordering the #loads would ripple through the production build chain
// (transpile_cache depends on transpile.jai's types), so the copy stays.
manifest_hash_hex :: (s: string) -> string {
    hash := fnv1a_hash(s.data, s.count);
    out: [16] u8;
    for i: 0..15 {
        nibble := cast(s64) ((hash >> cast(u64) (4 * (15 - i))) & 0xf);
        out[i] = cast(u8) ifx nibble < 10 then #char "0" + nibble else #char "a" + (nibble - 10);
    }
    return copy_string(to_string(out.data, 16));
}

// Temp file naming: the manifest evaluator's temp files used to share fixed
// names (eval_manifest.jai / manifest_data.txt) — sequential or concurrent
// evaluator child processes overwrote each other: a file written by one
// child got transiently locked (AV), and a later child whose write failed
// silently read stale manifest data (occasionally losing a workspace
// member). Names now hash the absolute path of the manifest being
// evaluated: distinct manifests never collide across processes; concurrent
// evaluations of the same manifest produce identical content, so the shared
// name is harmless.
manifest_temp_file_names :: (cache_dir: string, pkg_dir: string) -> (string, string) {
    stem := manifest_hash_hex(pkg_dir);
    eval_src := to_forward_slashes(tprint("%1/eval_manifest_%2.jai", cache_dir, stem));
    eval_out := to_forward_slashes(tprint("%1/manifest_data_%2.txt", cache_dir, stem));
    return eval_src, eval_out;
}

load_package_manifest :: (cache_dir: string, pkg_dir: string) -> Package, bool {
    manifest_path := to_forward_slashes(tprint("%1/package.jai", pkg_dir));
    if !file_exists(manifest_path) return .{}, false;

    if !make_directory_if_it_does_not_exist(cache_dir, recursive = true) {
        print("[juice ERROR] Could not create manifest cache directory: %\n", cache_dir);
        return .{}, false;
    }
    temp_eval_src, temp_eval_out := manifest_temp_file_names(cache_dir, pkg_dir);

    eval_code := build_eval_code(manifest_path, temp_eval_out);
    if !write_entire_file(temp_eval_src, eval_code) {
        print("[juice ERROR] Could not write manifest evaluator: %\n", temp_eval_src);
        return .{}, false;
    }

    exe_path := get_path_of_running_executable();
    bin_dir  := path_strip_filename(exe_path);
    global_modules_dir := to_forward_slashes(tprint("%1/../modules", bin_dir));

    // Retry a data-write failure (exit code 2) at most twice: transient file
    // locks (AV etc.) disappear across retries; each retry reuses the same
    // temp file pair (same manifest, same names, and a file that failed to
    // write has unchanged content, so the retry just overwrites it). Any
    // other nonzero exit code is a real evaluation failure and errors out
    // immediately.
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
