#import "Basic";
#import "File";
#import "File_Utilities";
#import "Hash";
#import "Process";
#import "String";

// The manifest protocol and loader: package.jai is an executable Jai source
// file, interpreted only through the generated evaluator child process
// (#load the manifest + #run main() printing line records). The stdout of
// the child is never part of the protocol — the protocol is the data file
// the child writes. The parent parses that file strictly (eleven record
// kinds; unknown keys, duplicate single-value records and malformed shapes
// are errors carrying 1-based line numbers). Plugin declarations are parsed
// structurally here; semantic validation (unknown ids, member resolution,
// versions, options) belongs to plugin preparation — the declaration-driven
// workspace scan and resolve_plugin_configs (ticket 056). A child write
// failure exits with code 2 and is retried at most twice; any other nonzero
// exit fails immediately.
//
// The Package face is consumed through the namespaced Juice binding
// (src/juice_module.jai — the load-bearing "Juice" module name constraint):
// the evaluator children receive the published modules directory on their
// import path, so the declarations package.jai files are written against
// are exactly the ones this layer evaluates.

Manifest_Parse_Result :: struct {
    success:       bool;
    package:       Juice.Package;
    line_number:   int;
    error_message: string;
}

to_forward_slashes :: (path: string) -> string {
    return path_slashes(path);
}

// Generate the evaluator program: the only way package.jai is interpreted.
// The generated main prints one KEY=VALUE line record per declaration, in
// the fixed order below. Repeatable records keep declaration order (the
// plugin loop is ordered on purpose — declaration order = pipeline order);
// zero declarations print zero records, which the parser reads as the
// default pipeline. Plugin options cross as PLUGIN_OPTION records; values
// are %XX-encoded (% | CR LF) so the line-record shape survives arbitrary
// option strings.
build_eval_code :: (manifest_path: string, output_path: string) -> string {
    clean_manifest := to_forward_slashes(manifest_path);
    clean_output   := to_forward_slashes(output_path);

    builder: String_Builder;
    append(*builder, "#import \"Basic\";\n");
    append(*builder, "#import \"File\";\n");
    append(*builder, "#import \"Juice\";\n");
    append(*builder, "#import \"Compiler\";\n\n");

    append(*builder, "#load \"");
    append(*builder, clean_manifest);
    append(*builder, "\";\n\n");

    append(*builder, "#run {\n");
    append(*builder, "    set_build_options_dc(.{do_output = false});\n");
    append(*builder, "    main();\n");
    append(*builder, "}\n\n");

    // The record-value encoder, generated into the child: the parent's
    // unescape_record_value is the exact inverse. Only the delimiter, the
    // escape character and line breaks are encoded; the rest passes through.
    append(*builder, "manifest_eval_hex_digit :: (n: u8) -> u8 {\n");
    append(*builder, "    return cast(u8) ifx n < 10 then #char \"0\" + n else #char \"a\" + (n - 10);\n");
    append(*builder, "}\n\n");
    append(*builder, "manifest_eval_escape :: (value: string) -> string {\n");
    append(*builder, "    out: [..] u8;\n");
    append(*builder, "    for i: 0..value.count-1 {\n");
    append(*builder, "        c := value[i];\n");
    append(*builder, "        if c == #char \"%\" || c == #char \"|\" || c == #char \"\\n\" || c == #char \"\\r\" {\n");
    append(*builder, "            array_add(*out, #char \"%\");\n");
    append(*builder, "            array_add(*out, manifest_eval_hex_digit(cast(u8) ((c >> 4) & 0xf)));\n");
    append(*builder, "            array_add(*out, manifest_eval_hex_digit(cast(u8) (c & 0xf)));\n");
    append(*builder, "        } else {\n");
    append(*builder, "            array_add(*out, c);\n");
    append(*builder, "        }\n");
    append(*builder, "    }\n");
    append(*builder, "    if out.count == 0 return \"\";\n");
    append(*builder, "    return copy_string(to_string(out.data, out.count));\n");
    append(*builder, "}\n\n");

    append(*builder, "main :: () {\n");
    append(*builder, "    builder: String_Builder;\n");
    append(*builder, "    print_to_builder(*builder, \"NAME=%\\n\", PACKAGE.name);\n");
    append(*builder, "    print_to_builder(*builder, \"VERSION=%\\n\", PACKAGE.version);\n");
    append(*builder, "    print_to_builder(*builder, \"TYPE=%\\n\", cast(s64) PACKAGE.type);\n");
    append(*builder, "    print_to_builder(*builder, \"DESCRIPTION=%\\n\", PACKAGE.description);\n");
    append(*builder, "    print_to_builder(*builder, \"BUILD_SCRIPT=%\\n\", PACKAGE.build_script);\n");
    append(*builder, "    for decl: PACKAGE.plugins {\n");
    append(*builder, "        print_to_builder(*builder, \"PLUGIN=%1|%2\\n\", manifest_eval_escape(decl.id), manifest_eval_escape(decl.version));\n");
    append(*builder, "        for opt: decl.options {\n");
    append(*builder, "            print_to_builder(*builder, \"PLUGIN_OPTION=%1|%2|%3\\n\", manifest_eval_escape(decl.id), manifest_eval_escape(opt.key), manifest_eval_escape(opt.value));\n");
    append(*builder, "        }\n");
    append(*builder, "    }\n\n");

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

    // A write failure must fail the child with a nonzero exit code: the
    // parent retries only exit code 2 (the dedicated "manifest data write
    // failed" signal) — silently ignoring the write result would let the
    // parent treat stale or missing data as success. Other failures
    // (manifest compile errors etc.) stay exit code 1 and never retry.
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

// Strict protocol parsing: every error carries the 1-based line number of
// the offending record. The parser is pure (no filesystem, no child), so
// the whole protocol matrix is testable in-process; load_package_manifest
// runs it after the child finishes.
parse_manifest_data_strict :: (content: string) -> Manifest_Parse_Result {
    result: Manifest_Parse_Result;

    seen_name := false;
    seen_version := false;
    seen_type := false;
    seen_description := false;
    seen_build_script := false;

    targets: [..] Juice.Target;
    members: [..] string;
    excluded: [..] string;
    deps: [..] Juice.Dependency;
    plugins: [..] Juice.Plugin_Declaration;

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
                    result.package.type = cast(Juice.Package_Type) enum_value;
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
                target: Juice.Target;
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
                dep: Juice.Dependency;
                dep.name = copy_string(parts[0]);
                dep.version = copy_string(parts[1]);
                dep.source = copy_string(parts[2]);
                dep.package = copy_string(parts[3]);
                array_add(*deps, dep);

            case "PLUGIN";
                parts := split(value, "|");
                if parts.count != 2 return manifest_parse_failure(line_index + 1, "PLUGIN record must contain id|version.");
                plugin_id, id_ok := unescape_record_value(parts[0]);
                plugin_version, version_ok := unescape_record_value(parts[1]);
                if !id_ok || !version_ok return manifest_parse_failure(line_index + 1, "Invalid %XX escape in PLUGIN record.");
                for decl: plugins {
                    if decl.id == plugin_id return manifest_parse_failure(line_index + 1, "Duplicate PLUGIN record.");
                }
                decl: Juice.Plugin_Declaration;
                decl.id = plugin_id;
                decl.version = plugin_version;
                array_add(*plugins, decl);

            case "PLUGIN_OPTION";
                parts := split(value, "|");
                if parts.count != 3 return manifest_parse_failure(line_index + 1, "PLUGIN_OPTION record must contain id|key|value.");
                plugin_id, id_ok := unescape_record_value(parts[0]);
                option_key, key_ok := unescape_record_value(parts[1]);
                option_value, value_ok := unescape_record_value(parts[2]);
                if !id_ok || !key_ok || !value_ok return manifest_parse_failure(line_index + 1, "Invalid %XX escape in PLUGIN_OPTION record.");
                plugin_index := -1;
                for decl, index: plugins {
                    if decl.id == plugin_id {
                        plugin_index = index;
                        break;
                    }
                }
                if plugin_index < 0 return manifest_parse_failure(line_index + 1, "PLUGIN_OPTION for an undeclared plugin.");
                for opt: plugins[plugin_index].options {
                    if opt.key == option_key return manifest_parse_failure(line_index + 1, tprint("Duplicate plugin option key: %1", option_key));
                }
                option: Juice.Plugin_Option;
                option.key = option_key;
                option.value = option_value;
                // The face's options slot is a [] slice; rebuild through a
                // dynamic array (row counts are tiny) and store the view.
                rows: [..] Juice.Plugin_Option;
                for existing: plugins[plugin_index].options {
                    array_add(*rows, existing);
                }
                array_add(*rows, option);
                plugins[plugin_index].options = rows;

            case;
                return manifest_parse_failure(line_index + 1, tprint("Unknown manifest record: %1", key));
        }
    }

    result.package.targets = targets;
    result.package.workspace.members = members;
    result.package.workspace.exclude = excluded;
    result.package.dependencies = deps;
    result.package.plugins = plugins;
    result.success = true;
    return result;
}

manifest_parse_failure :: (line_number: int, message: string) -> Manifest_Parse_Result {
    return .{success = false, line_number = line_number, error_message = copy_string(message)};
}

// Kept as a small convenience for pure parser callers. Callers that need
// the diagnostic should use parse_manifest_data_strict().
parse_manifest_data :: (content: string) -> Juice.Package {
    result := parse_manifest_data_strict(content);
    return result.package;
}

// Record-value decoder: the exact inverse of the evaluator's generated
// manifest_eval_escape (%XX for %, |, CR and LF). Strict: a malformed
// escape fails the record instead of being silently reinterpreted.
hex_value_of :: (c: u8) -> s64 {
    if c >= #char "0" && c <= #char "9" return cast(s64) (c - #char "0");
    if c >= #char "a" && c <= #char "f" return cast(s64) (c - #char "a") + 10;
    if c >= #char "A" && c <= #char "F" return cast(s64) (c - #char "A") + 10;
    return -1;
}

unescape_record_value :: (value: string) -> (string, bool) {
    out: [..] u8;
    i := 0;
    while i < value.count {
        c := value[i];
        if c == #char "%" {
            if i + 2 >= value.count return "", false;
            high := hex_value_of(value[i+1]);
            low  := hex_value_of(value[i+2]);
            if high < 0 || low < 0 return "", false;
            array_add(*out, cast(u8) (high * 16 + low));
            i += 3;
            continue;
        }
        array_add(*out, c);
        i += 1;
    }
    if out.count == 0 return "", true;
    return copy_string(to_string(out.data, out.count)), true;
}

// FNV-1a 64-bit hash rendered as 16 lowercase hex characters.
manifest_hash_hex :: (s: string) -> string {
    hash := fnv1a_hash(s.data, s.count);
    out: [16] u8;
    for i: 0..15 {
        nibble := cast(s64) ((hash >> cast(u64) (4 * (15 - i))) & 0xf);
        out[i] = cast(u8) ifx nibble < 10 then #char "0" + nibble else #char "a" + (nibble - 10);
    }
    return copy_string(to_string(out.data, 16));
}

// Temp file naming: names hash the absolute path of the manifest being
// evaluated — distinct manifests never collide across sequential or
// concurrent evaluator children, and concurrent evaluations of the same
// manifest produce identical content, so the shared name is harmless.
manifest_temp_file_names :: (cache_dir: string, pkg_dir: string) -> (string, string) {
    stem := manifest_hash_hex(pkg_dir);
    eval_src := to_forward_slashes(tprint("%1/eval_manifest_%2.jai", cache_dir, stem));
    eval_out := to_forward_slashes(tprint("%1/manifest_data_%2.txt", cache_dir, stem));
    return eval_src, eval_out;
}

// Production evaluator spawn: one jai child per manifest, compiling and
// running the generated evaluator program. The child inherits the caller's
// working directory (the evaluator only prints declaration fields and never
// resolves paths, and every path it touches is absolute). The modules
// directory feeds -import_dir so the manifest's `#import "Juice"` resolves.
spawn_manifest_evaluator :: (eval_src: string, eval_out: string, modules_dir: string) -> s32 {
    result := run_command("jai", eval_src, "-import_dir", modules_dir, "-quiet");
    return result.exit_code;
}

// Load and validate a package manifest. Returns the parsed package with its
// dir backfilled to the absolute package directory (every later path
// resolution anchors on it), or an empty package and false on failure.
//
// modules_dir defaults to the derivation next to the running executable
// (spec section 9.3); tests inject the published modules directory
// (ensure_published_modules). The spawn
// seam is the child boundary (production default spawn_manifest_evaluator);
// tests inject a recording fake to drive the retry loop deterministically —
// a real child's write failure cannot be forced on demand.
load_package_manifest :: (cache_dir: string, pkg_dir: string,
                          modules_dir: string = "",
                          spawn: #type (eval_src: string, eval_out: string, modules_dir: string) -> s32 = spawn_manifest_evaluator) -> Juice.Package, bool {
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

    dir := modules_dir;
    if dir == "" dir = juice_modules_dir();

    // Retry a data-write failure (exit code 2) at most twice: transient file
    // locks disappear across retries; each retry reuses the same temp file
    // pair (same manifest, same names, and a file that failed to write has
    // unchanged content, so the retry just overwrites it). Any other nonzero
    // exit code is a real evaluation failure and errors out immediately.
    attempts := 0;
    while true {
        exit_code := spawn(temp_eval_src, temp_eval_out, dir);
        if exit_code == 0 break;
        if exit_code == 2 && attempts < 2 {
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
