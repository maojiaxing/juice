#import "Basic";
#import "File";
#import "Hash";
#import "Process";
#import "String";
#import "System";
#import "Juice";
#import "Testing";

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
    append(*builder, "    print_to_builder(*builder, \"BUILD_SCRIPT=%\\n\", PACKAGE.build_script);\n");
    append(*builder, "    print_to_builder(*builder, \"JAIX_CONFIG=%\\n\", PACKAGE.jaix.config);\n");
    append(*builder, "    print_to_builder(*builder, \"JAIX_EXE=%\\n\", PACKAGE.jaix.exe);\n\n");

    // Repeatable pipeline records in declaration order (spec 0060 decision
    // 6): zero declarations print zero records — the parser then sees an
    // empty pipeline, which means the default. Options never cross the
    // protocol (id+version only — the jaix "options don't cross the process
    // boundary" stance).
    append(*builder, "    for decl: PACKAGE.transpile.plugins {\n");
    append(*builder, "        print_to_builder(*builder, \"TRANSPILE_PLUGIN=%1|%2\\n\", decl.id, decl.version);\n");
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
    seen_jaix_config := false;
    seen_jaix_exe := false;

    targets: [..] Target;
    members: [..] string;
    excluded: [..] string;
    deps: [..] Dependency;
    transpile_plugins: [..] Transpile_Plugin_Declaration;

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

            case "JAIX_CONFIG";
                if seen_jaix_config return manifest_parse_failure(line_index + 1, "Duplicate JAIX_CONFIG record.");
                seen_jaix_config = true;
                result.package.jaix.config = copy_string(value);

            case "JAIX_EXE";
                if seen_jaix_exe return manifest_parse_failure(line_index + 1, "Duplicate JAIX_EXE record.");
                seen_jaix_exe = true;
                result.package.jaix.exe = copy_string(value);

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

            case "TRANSPILE_PLUGIN";
                parts := split(value, "|");
                if parts.count != 2 return manifest_parse_failure(line_index + 1, "TRANSPILE_PLUGIN record must contain id|version.");
                for decl: transpile_plugins {
                    if decl.id == parts[0] return manifest_parse_failure(line_index + 1, "Duplicate TRANSPILE_PLUGIN record.");
                }
                decl: Transpile_Plugin_Declaration;
                decl.id = copy_string(parts[0]);
                decl.version = copy_string(parts[1]);
                array_add(*transpile_plugins, decl);

            case;
                return manifest_parse_failure(line_index + 1, tprint("Unknown manifest record: %1", key));
        }
    }

    result.package.targets = targets;
    result.package.workspace.members = members;
    result.package.workspace.exclude = excluded;
    result.package.dependencies = deps;
    result.package.transpile.plugins = transpile_plugins;
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

// Marker cross-record validation: an exe override without a config is a
// declaration error — without a config the pre-step has nothing to run. The
// gate is standalone so the load path's check is testable in-process
// (load_package_manifest itself needs a real jai child; see workspace.jai's
// validation matrix note for the same split).
validate_jaix_marker :: (pkg: Package) -> (bool, string) {
    if pkg.jaix.exe != "" && pkg.jaix.config == "" {
        return false, "JAIX_EXE set without JAIX_CONFIG.";
    }
    return true, "";
}

// Transpile pipeline validation (the validate_jaix_marker sibling — spec
// 0060 decision 6): the declared plugin list must contain only built-in
// plugin ids, no id may repeat, and no options may be declared (v1: both
// built-in plugins' option sets are empty — the typed slot exists, no
// legal option rows). The gate is standalone so the load path's check is
// testable in-process (load_package_manifest itself needs a real jai
// child; same split as the jaix marker gate). The duplicate-id check here
// overlaps the strict parser's "Duplicate TRANSPILE_PLUGIN record."
// rejection on purpose: the parser covers the protocol text with line
// numbers, this gate stays the single validation function for
// programmatically constructed packages.
validate_transpile_pipeline :: (pkg: Package) -> (bool, string) {
    seen: [..] string;
    for decl: pkg.transpile.plugins {
        if decl.id != TRANSPILE_PLUGIN_LOAD_ID && decl.id != TRANSPILE_PLUGIN_TEST_BLOCK_ID {
            return false, tprint("Unknown transpile plugin id: %1", decl.id);
        }
        for id: seen {
            if id == decl.id return false, tprint("Duplicate transpile plugin id: %1", decl.id);
        }
        array_add(*seen, copy_string(decl.id));
        if decl.options.count > 0 {
            return false, tprint("Invalid transpile plugin options for %1: the option set is empty.", decl.id);
        }
    }
    return true, "";
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
    jaix_ok, jaix_error := validate_jaix_marker(parsed.package);
    if !jaix_ok {
        print("[juice ERROR] Invalid jaix marker at %: %\n", manifest_path, jaix_error);
        return .{}, false;
    }
    pipeline_ok, pipeline_error := validate_transpile_pipeline(parsed.package);
    if !pipeline_ok {
        print("[juice ERROR] Invalid transpile pipeline at %: %\n", manifest_path, pipeline_error);
        return .{}, false;
    }
    parsed.package.dir = copy_string(pkg_dir);
    return parsed.package, true;
}

// ---------------------------------------------------------------------------
// Inline tests: the jaix marker and transpile pipeline validation matrices.
// The parse faces are pure protocol; the cross-record checks live in
// validate_jaix_marker / validate_transpile_pipeline (the load path's
// testable seams — load_package_manifest needs a real jai child, so its
// branches stay covered by E2E message assertions elsewhere).
// ---------------------------------------------------------------------------

test "Jaix marker parses a config and exe pair" {
    parsed := parse_manifest_data_strict("NAME=demo\nVERSION=1\nJAIX_CONFIG=jaix.config.jai\nJAIX_EXE=jaix.exe\n");
    expect(parsed.success);
    expect(parsed.package.jaix.config == "jaix.config.jai");
    expect(parsed.package.jaix.exe == "jaix.exe");
}

test "Jaix marker records default to empty when absent" {
    parsed := parse_manifest_data_strict("NAME=demo\nVERSION=1\n");
    expect(parsed.success);
    expect(parsed.package.jaix.config == "");
    expect(parsed.package.jaix.exe == "");
}

test "Jaix marker rejects a duplicate JAIX_CONFIG record" {
    parsed := parse_manifest_data_strict("NAME=demo\nVERSION=1\nJAIX_CONFIG=a\nJAIX_CONFIG=b\n");
    expect(!parsed.success);
    expect(parsed.line_number == 4);
    expect(parsed.error_message == "Duplicate JAIX_CONFIG record.");
}

test "Jaix marker rejects a duplicate JAIX_EXE record" {
    parsed := parse_manifest_data_strict("NAME=demo\nVERSION=1\nJAIX_EXE=a\nJAIX_EXE=b\n");
    expect(!parsed.success);
    expect(parsed.line_number == 4);
    expect(parsed.error_message == "Duplicate JAIX_EXE record.");
}

test "Jaix marker rejects an exe without a config" {
    ok, message := validate_jaix_marker(.{name = "demo", version = "1", jaix = .{config = "", exe = "jaix.exe"}});
    expect(!ok);
    expect(message == "JAIX_EXE set without JAIX_CONFIG.");
}

test "Jaix marker accepts a config with or without an exe override" {
    ok, _ := validate_jaix_marker(.{name = "demo", version = "1", jaix = .{config = "jaix.config.jai"}});
    expect(ok);
    ok, _ = validate_jaix_marker(.{name = "demo", version = "1", jaix = .{config = "jaix.config.jai", exe = "jaix.exe"}});
    expect(ok);
    ok, _ = validate_jaix_marker(.{name = "demo", version = "1"});
    expect(ok);
}

test "Transpile pipeline records parse in declaration order" {
    parsed := parse_manifest_data_strict("NAME=demo\nVERSION=1\nTRANSPILE_PLUGIN=load|1.0.0\nTRANSPILE_PLUGIN=test-block|1.0.0\n");
    expect(parsed.success);
    expect(parsed.package.transpile.plugins.count == 2);
    expect(parsed.package.transpile.plugins[0].id == "load");
    expect(parsed.package.transpile.plugins[0].version == "1.0.0");
    expect(parsed.package.transpile.plugins[1].id == "test-block");
    expect(parsed.package.transpile.plugins[1].version == "1.0.0");
    expect(parsed.package.transpile.plugins[0].options.count == 0);
}

test "Transpile pipeline records default to empty when absent" {
    parsed := parse_manifest_data_strict("NAME=demo\nVERSION=1\n");
    expect(parsed.success);
    expect(parsed.package.transpile.plugins.count == 0);
}

// The evaluator codegen locks the protocol record shape at the generation
// level (the full child-process loop is covered by the E2E child scenarios
// in commands/build.jai): the repeatable TRANSPILE_PLUGIN=<id>|<version>
// record is printed per declaration, in declaration order.
test "Evaluator codegen prints TRANSPILE_PLUGIN records in declaration order" {
    code := build_eval_code("C:/pkg/package.jai", "C:/out/data.txt");
    expect(find_index_from_left(code, "PACKAGE.transpile.plugins") >= 0);
    expect(find_index_from_left(code, "TRANSPILE_PLUGIN=%1|%2") >= 0);
    expect(find_index_from_left(code, "decl.id, decl.version") >= 0);
}

test "Transpile pipeline rejects a record without id|version" {
    parsed := parse_manifest_data_strict("NAME=demo\nVERSION=1\nTRANSPILE_PLUGIN=load\n");
    expect(!parsed.success);
    expect(parsed.line_number == 3);
    expect(parsed.error_message == "TRANSPILE_PLUGIN record must contain id|version.");
}

test "Transpile pipeline rejects a duplicate plugin id" {
    parsed := parse_manifest_data_strict("NAME=demo\nVERSION=1\nTRANSPILE_PLUGIN=load|1.0.0\nTRANSPILE_PLUGIN=load|1.0.0\n");
    expect(!parsed.success);
    expect(parsed.line_number == 4);
    expect(parsed.error_message == "Duplicate TRANSPILE_PLUGIN record.");
}

test "Transpile pipeline validation rejects an unknown plugin id" {
    pkg: Package = .{name = "demo", version = "1", transpile = .{plugins = .[.{id = "mystery", version = "1.0.0"}]}};
    ok, message := validate_transpile_pipeline(pkg);
    expect(!ok);
    expect(message == "Unknown transpile plugin id: mystery");
}

test "Transpile pipeline validation rejects a duplicate plugin id" {
    pkg: Package = .{name = "demo", version = "1", transpile = .{plugins = .[
        .{id = "load", version = "1.0.0"},
        .{id = "load", version = "1.0.0"},
    ]}};
    ok, message := validate_transpile_pipeline(pkg);
    expect(!ok);
    expect(message == "Duplicate transpile plugin id: load");
}

test "Transpile pipeline validation rejects options on a built-in plugin" {
    pkg: Package = .{name = "demo", version = "1", transpile = .{plugins = .[
        .{id = "load", version = "1.0.0", options = .[.{key = "mode", value = "fast"}]},
    ]}};
    ok, message := validate_transpile_pipeline(pkg);
    expect(!ok);
    expect(message == "Invalid transpile plugin options for load: the option set is empty.");
}

test "Transpile pipeline validation accepts the built-in plugins" {
    pkg: Package = .{name = "demo", version = "1", transpile = .{plugins = .[
        .{id = "load", version = "1.0.0"},
        .{id = "test-block", version = "1.0.0"},
    ]}};
    ok, _ := validate_transpile_pipeline(pkg);
    expect(ok);
    ok, _ = validate_transpile_pipeline(.{name = "demo", version = "1"});
    expect(ok);
    reversed: Package = .{name = "demo", version = "1", transpile = .{plugins = .[
        .{id = "test-block", version = "1.0.0"},
        .{id = "load", version = "1.0.0"},
    ]}};
    ok, _ = validate_transpile_pipeline(reversed);
    expect(ok);
}
