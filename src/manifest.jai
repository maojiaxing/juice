#import "Basic";
#import "File";
#import "File_Utilities";
#import "Hash";
#import "Process";
#import "String";

Manifest_Parse_Result :: struct {
    success: bool;
    package: Normalized_Package;
    line_number: int;
    error_message: string;
}

to_forward_slashes :: (path: string) -> string { return path_slashes(path); }

// The evaluator is the only bridge from public Package values to runtime data.
// Source diagnostics are the compiler's; protocol positions are never claimed
// to be source coordinates. Every field is escaped without trimming its value.
build_eval_code :: (manifest_path: string, output_path: string) -> string {
    builder: String_Builder;
    append(*builder, "#import \"Basic\";\n#import \"File\";\n#import \"Juice\";\n#import \"Compiler\";\n");
    print_to_builder(*builder, "#load %;\n", quote_jai_string(to_forward_slashes(manifest_path)));
    append(*builder, #string EVALUATOR
manifest_eval_escape :: (value: string) -> string {
    result: String_Builder;
    for character: value {
        if character == #char "%" || character == #char "|" || character == #char "\n" || character == #char "\r" {
            digits :: "0123456789abcdef";
            append(*result, #char "%");
            append(*result, digits[(character >> 4) & 15]);
            append(*result, digits[character & 15]);
        } else append(*result, character);
    }
    return builder_to_string(*result);
}
manifest_eval_source :: (source: Source) -> string {
    return tprint("%|%|%|%|%|%", cast(s64) source.kind, manifest_eval_escape(source.path), manifest_eval_escape(source.git.url), manifest_eval_escape(source.git.branch), manifest_eval_escape(source.git.tag), manifest_eval_escape(source.git.rev));
}
manifest_eval_strings :: (builder: *String_Builder, key: string, row: string, values: [] string) {
    omitted := values.count == 1 && values[0] == "\x01juice-omitted";
    print_to_builder(builder, "%=%\n", key, ifx omitted then -1 else values.count);
    if !omitted for value: values print_to_builder(builder, "%=%\n", row, manifest_eval_escape(value));
}
manifest_eval_products :: (builder: *String_Builder, key: string, row: string, values: [] Product) {
    omitted := values.count == 1 && values[0].name == "\x01juice-omitted" && values[0].entry == "\x01juice-omitted";
    print_to_builder(builder, "%=%\n", key, ifx omitted then -1 else values.count);
    if !omitted for value: values print_to_builder(builder, "%=%|%\n", row, manifest_eval_escape(value.name), manifest_eval_escape(value.entry));
}
#run {
    set_build_options_dc(.{do_output = false});
    manifest_eval_main();
}
manifest_eval_source_omitted :: (source: Source) -> bool {
    sentinel :: "\x01juice-omitted";
    return source.kind == .UNSPECIFIED && source.path == sentinel && source.git.url == sentinel && source.git.branch == sentinel && source.git.tag == sentinel && source.git.rev == sentinel;
}
manifest_eval_selection_omitted :: (selection: Module_Selection) -> bool {
    sentinel :: "\x01juice-omitted";
    return selection.path == sentinel && selection.name == sentinel && selection.alias == sentinel;
}
manifest_eval_main :: () {
    // Assignment also enforces the unique PACKAGE value's public type.
    declaration: Package = PACKAGE;
    builder: String_Builder;
    append(*builder, "SCHEMA=2\n");
    print_to_builder(*builder, "NAME=%\nVERSION=%\nDESCRIPTION=%\nDEFAULT_RUN=%\n", manifest_eval_escape(declaration.name), manifest_eval_escape(declaration.version), manifest_eval_escape(declaration.description), manifest_eval_escape(declaration.default_run));
    workspace := declaration.workspace;
    members_default := workspace.members.count == 1 && workspace.members[0] == "\x01juice-workspace-omitted";
    exclude_default := workspace.exclude.count == 1 && workspace.exclude[0] == "\x01juice-omitted";
    default_members_default := workspace.default_members.count == 1 && workspace.default_members[0] == "\x01juice-omitted";
    has_workspace := !(members_default && exclude_default && default_members_default);
    print_to_builder(*builder, "WORKSPACE=%\n", ifx has_workspace then 1 else 0);
    // A computed Package may change only exclude/default_members. Decode the
    // inherited members marker without discarding those explicit values.
    if members_default workspace.members = .["\x01juice-omitted"];
    manifest_eval_strings(*builder, "MEMBERS", "MEMBER", workspace.members);
    manifest_eval_strings(*builder, "EXCLUDES", "EXCLUDE", workspace.exclude);
    manifest_eval_strings(*builder, "DEFAULT_MEMBERS", "DEFAULT_MEMBER", workspace.default_members);
    manifest_eval_products(*builder, "MODULES", "MODULE", declaration.modules);
    manifest_eval_products(*builder, "EXECUTABLES", "EXECUTABLE", declaration.executables);
    dependencies_omitted := declaration.dependencies.count == 1 && declaration.dependencies[0].name == "\x01juice-omitted" && manifest_eval_source_omitted(declaration.dependencies[0].source) && declaration.dependencies[0].modules.count == 1 && manifest_eval_selection_omitted(declaration.dependencies[0].modules[0]);
    print_to_builder(*builder, "DEPENDENCIES=%\n", ifx dependencies_omitted then -1 else declaration.dependencies.count);
    if !dependencies_omitted for dependency: declaration.dependencies {
        omitted := dependency.modules.count == 1 && dependency.modules[0].path == "\x01juice-omitted" && dependency.modules[0].name == "\x01juice-omitted" && dependency.modules[0].alias == "\x01juice-omitted";
        print_to_builder(*builder, "DEP=%|%|%\n", manifest_eval_escape(dependency.name), manifest_eval_source(dependency.source), ifx omitted then -1 else dependency.modules.count);
        if !omitted for selection: dependency.modules print_to_builder(*builder, "DEP_MODULE=%|%|%\n", manifest_eval_escape(selection.path), manifest_eval_escape(selection.name), manifest_eval_escape(selection.alias));
    }
    plugins_omitted := declaration.plugins.count == 1 && declaration.plugins[0].id == "\x01juice-omitted" && declaration.plugins[0].builtin == "\x01juice-omitted" && manifest_eval_source_omitted(declaration.plugins[0].source) && manifest_eval_selection_omitted(declaration.plugins[0].module) && declaration.plugins[0].options.count == 0;
    print_to_builder(*builder, "PLUGINS=%\n", ifx plugins_omitted then -1 else declaration.plugins.count);
    if !plugins_omitted for plugin: declaration.plugins {
        print_to_builder(*builder, "PLUGIN=%|%|%|%|%|%\n", manifest_eval_escape(plugin.id), manifest_eval_escape(plugin.builtin), manifest_eval_source(plugin.source), manifest_eval_escape(plugin.module.path), manifest_eval_escape(plugin.module.name), manifest_eval_escape(plugin.module.alias));
        for option: plugin.options print_to_builder(*builder, "PLUGIN_OPTION=%|%\n", manifest_eval_escape(option.key), manifest_eval_escape(option.value));
    }
EVALUATOR
    );
    print_to_builder(*builder, "    if !write_entire_file(%, builder_to_string(*builder)) exit(2);\n}\n", quote_jai_string(to_forward_slashes(output_path)));
    return builder_to_string(*builder);
}

manifest_parse_failure :: (line_number: int, message: string) -> Manifest_Parse_Result {
    return .{line_number = line_number, error_message = copy_string(message)};
}
manifest_is_omitted :: (value: string) -> bool { return value == "\x01juice-omitted"; }
manifest_optional :: (value: string) -> string { return ifx manifest_is_omitted(value) then "" else copy_string(value); }

manifest_source :: (parts: [] string, start: int) -> Source_Reference, bool {
    source: Source_Reference;
    number, valid, remainder := string_to_int(parts[start]);
    if !valid || remainder.count != 0 || number < 1 || number > 3 return source, false;
    source.kind = cast(Juice.Source_Kind) number;
    source.path = manifest_optional(parts[start+1]);
    source.url = manifest_optional(parts[start+2]);
    source.branch = manifest_optional(parts[start+3]);
    source.tag = manifest_optional(parts[start+4]);
    source.rev = manifest_optional(parts[start+5]);
    for index: start+1..start+5 if parts[index] == "" return source, false;
    selectors := 0;
    if source.branch != "" selectors += 1;
    if source.tag != "" selectors += 1;
    if source.rev != "" selectors += 1;
    if selectors > 1 return source, false;
    if source.kind == .PATH return source, source.path != "" && source.url == "" && selectors == 0;
    if source.kind == .GIT return source, source.path == "" && source.url != "";
    return source, source.path == "" && source.url == "" && selectors == 0;
}
manifest_selection :: (parts: [] string, start: int) -> Module_Reference, bool {
    selection: Module_Reference;
    for index: start..start+2 if parts[index] == "" return selection, false;
    if !manifest_is_omitted(parts[start]) selection.path = copy_string(parts[start]);
    selection.name = manifest_optional(parts[start+1]);
    selection.alias = manifest_optional(parts[start+2]);
    return selection, true;
}

parse_manifest_data_strict :: (content: string) -> Manifest_Parse_Result {
    result: Manifest_Parse_Result;
    result.package.has_package = false;
    seen: [..] string;
    fields: [..] Declaration_Field;
    modules: [..] Declared_Product;
    executables: [..] Declared_Product;
    dependencies: [..] Dependency_Reference;
    plugins: [..] Plugin_Reference;
    members: [..] string;
    excluded: [..] string;
    default_members: [..] string;
    expected_modules := -1;
    expected_executables := -1;
    expected_dependencies := -1;
    expected_plugins := -1;
    expected_members := -1;
    expected_excludes := -1;
    expected_defaults := -1;
    dependency_module_counts: [..] s64;
    for raw_line, line_index: split(content, "\n") {
        line := raw_line;
        if ends_with(line, "\r") line.count -= 1;
        if line.count == 0 continue;
        found, key, encoded := split_from_left(line, #char "=");
        if !found || key == "" return manifest_parse_failure(line_index+1, "Malformed manifest record.");
        parts: [..] string;
        for part: split(encoded, "|") {
            decoded, ok := unescape_record_value(part);
            if !ok return manifest_parse_failure(line_index+1, "Invalid %XX escape in manifest record.");
            array_add(*parts, decoded);
        }
        value := parts[0];
        array_add(*fields, .{path = copy_string(key), value = copy_string(encoded), protocol_line = line_index+1});
        repeatable := key == "MODULE" || key == "EXECUTABLE" || key == "DEP" || key == "DEP_MODULE" || key == "PLUGIN" || key == "PLUGIN_OPTION" || key == "MEMBER" || key == "EXCLUDE" || key == "DEFAULT_MEMBER";
        if !repeatable {
            if parts.count != 1 return manifest_parse_failure(line_index+1, "Scalar record contains unescaped delimiters.");
            for previous: seen if key == previous return manifest_parse_failure(line_index+1, tprint("Duplicate % record.", key));
            array_add(*seen, copy_string(key));
        }
        if key == {
            case "SCHEMA";
                if value != "2" return manifest_parse_failure(line_index+1, "Unsupported declaration protocol version.");
            case "NAME";
                result.package.name = manifest_optional(value);
                if !manifest_is_omitted(value) result.package.has_package = true;
            case "VERSION";
                result.package.version = manifest_optional(value);
                if !manifest_is_omitted(value) result.package.has_package = true;
            case "DESCRIPTION";
                result.package.description = manifest_optional(value);
                if !manifest_is_omitted(value) result.package.has_package = true;
            case "DEFAULT_RUN";
                if value == "" return manifest_parse_failure(line_index+1, "default_run cannot be empty.");
                result.package.default_run = manifest_optional(value);
                if !manifest_is_omitted(value) result.package.has_package = true;
            case "WORKSPACE";
                if value != "0" && value != "1" return manifest_parse_failure(line_index+1, "Invalid workspace presence.");
                result.package.has_workspace = value == "1";
            case "MODULES"; #through;
            case "EXECUTABLES"; #through;
            case "DEPENDENCIES"; #through;
            case "PLUGINS"; #through;
            case "MEMBERS"; #through;
            case "EXCLUDES"; #through;
            case "DEFAULT_MEMBERS";
                count, ok, remainder := string_to_int(value);
                if !ok || remainder.count != 0 || count < -1 return manifest_parse_failure(line_index+1, "Invalid list count.");
                if key == "MODULES" { expected_modules = count; result.package.modules_omitted = count == -1; }
                if key == "EXECUTABLES" { expected_executables = count; result.package.executables_omitted = count == -1; }
                if key == "DEPENDENCIES" expected_dependencies = count;
                if key == "PLUGINS" { expected_plugins = count; result.package.plugins_omitted = count == -1; }
                if key == "MEMBERS" expected_members = count;
                if key == "EXCLUDES" expected_excludes = count;
                if key == "DEFAULT_MEMBERS" { expected_defaults = count; result.package.workspace.default_members_omitted = count == -1; }
                if count >= 0 && (key == "MODULES" || key == "EXECUTABLES" || key == "DEPENDENCIES" || key == "PLUGINS") result.package.has_package = true;
            case "MODULE"; #through;
            case "EXECUTABLE";
                if parts.count != 2 return manifest_parse_failure(line_index+1, "Product requires name|entry.");
                if parts[1] == "" || manifest_is_omitted(parts[1]) return manifest_parse_failure(line_index+1, "Product entry is required.");
                if parts[0] == "" return manifest_parse_failure(line_index+1, "Product name cannot be empty.");
                product: Declared_Product = .{name = manifest_optional(parts[0]), entry = copy_string(parts[1]), name_present = !manifest_is_omitted(parts[0])};
                if key == "MODULE" array_add(*modules, product); else array_add(*executables, product);
            case "MEMBER"; #through;
            case "EXCLUDE"; #through;
            case "DEFAULT_MEMBER";
                if parts.count != 1 || value == "" return manifest_parse_failure(line_index+1, tprint("% cannot be empty.", key));
                if key == "MEMBER" array_add(*members, copy_string(value));
                if key == "EXCLUDE" array_add(*excluded, copy_string(value));
                if key == "DEFAULT_MEMBER" array_add(*default_members, copy_string(value));
            case "DEP";
                if parts.count != 8 return manifest_parse_failure(line_index+1, "DEP requires name, source and module count.");
                source, ok := manifest_source(parts, 1);
                if !ok return manifest_parse_failure(line_index+1, "Invalid dependency source: choose PATH, GIT or WORKSPACE with matching payload; Git selectors are mutually exclusive.");
                if value == "" || manifest_is_omitted(value) return manifest_parse_failure(line_index+1, "Dependency name is required.");
                // A dependency reference name is a declaration identifier: it is
                // reported and compared as written, but it must be spellable —
                // the same grammar the package name and plugin id use.
                if !package_name_is_valid(value) return manifest_parse_failure(line_index+1, tprint("Invalid dependency name: % (ASCII letters, digits, '.', '_' and '-', starting with a letter or digit).", value));
                count, count_ok, remainder := string_to_int(parts[7]);
                if !count_ok || remainder.count != 0 || count < -1 || count == 0 return manifest_parse_failure(line_index+1, "Dependency modules cannot be empty.");
                for previous: dependencies if equal_nocase(previous.name, value) return manifest_parse_failure(line_index+1, "Duplicate dependency name.");
                array_add(*dependencies, .{name = copy_string(value), source = source, modules_omitted = count == -1});
                array_add(*dependency_module_counts, count);
            case "DEP_MODULE";
                if parts.count != 3 || dependencies.count == 0 return manifest_parse_failure(line_index+1, "DEP_MODULE requires a dependency and path|name|alias.");
                selection, ok := manifest_selection(parts, 0);
                if !ok return manifest_parse_failure(line_index+1, "Module selection cannot contain empty path/name/alias.");
                rows: [..] Module_Reference;
                for row: dependencies[dependencies.count-1].modules array_add(*rows, row);
                array_add(*rows, selection);
                dependencies[dependencies.count-1].modules = rows;
            case "PLUGIN";
                if parts.count != 11 return manifest_parse_failure(line_index+1, "PLUGIN requires id, builtin, source and module selection.");
                if value == "" return manifest_parse_failure(line_index+1, "Plugin id cannot be empty.");
                // Plugin ids share the package-name grammar (the built-in ids
                // `load` and `test-block` are legal spellings), and the internal
                // omitted sentinel is not a user spelling at all.
                if !manifest_is_omitted(value) && !package_name_is_valid(value) return manifest_parse_failure(line_index+1, tprint("Invalid plugin id: % (ASCII letters, digits, '.', '_' and '-', starting with a letter or digit).", value));
                plugin: Plugin_Reference;
                plugin.id = manifest_optional(value);
                plugin.builtin = !manifest_is_omitted(parts[1]);
                if plugin.builtin {
                    if parts[1] == "" || parts[2] != "0" return manifest_parse_failure(line_index+1, "Plugin builtin and source are mutually exclusive.");
                    for index: 3..10 if !manifest_is_omitted(parts[index]) return manifest_parse_failure(line_index+1, "Builtin plugin cannot select an external source or module.");
                    if plugin.id == "" plugin.id = copy_string(parts[1]);
                    if !ascii_names_equal(plugin.id, parts[1]) return manifest_parse_failure(line_index+1, "Builtin plugin id must match builtin.");
                } else {
                    source, ok := manifest_source(parts, 2);
                    if !ok return manifest_parse_failure(line_index+1, "External plugin requires an explicit source.");
                    plugin.source = source;
                    selection, selection_ok := manifest_selection(parts, 8);
                    if !selection_ok return manifest_parse_failure(line_index+1, "Invalid plugin module selection.");
                    plugin.module = selection;
                    if plugin.id == "" return manifest_parse_failure(line_index+1, "External plugin id is required.");
                }
                for previous: plugins if equal_nocase(previous.id, plugin.id) return manifest_parse_failure(line_index+1, "Duplicate PLUGIN record.");
                array_add(*plugins, plugin);
            case "PLUGIN_OPTION";
                if parts.count != 2 || plugins.count == 0 return manifest_parse_failure(line_index+1, "PLUGIN_OPTION requires a plugin and key|value.");
                if !declaration_identifier_is_valid(value) return manifest_parse_failure(line_index+1, tprint("Invalid plugin option key: % (ASCII identifier).", value));
                rows: [..] Juice.Plugin_Option;
                for row: plugins[plugins.count-1].options {
                    if equal_nocase(row.key, value) return manifest_parse_failure(line_index+1, "Duplicate plugin option key.");
                    array_add(*rows, row);
                }
                array_add(*rows, .{key = copy_string(value), value = copy_string(parts[1])});
                plugins[plugins.count-1].options = rows;
            case;
                return manifest_parse_failure(line_index+1, tprint("Unknown manifest record: %; see docs/migrations/package-declarations.md", key));
        }
    }
    for required: string.["SCHEMA", "NAME", "VERSION", "DESCRIPTION", "DEFAULT_RUN", "WORKSPACE", "MEMBERS", "EXCLUDES", "DEFAULT_MEMBERS", "MODULES", "EXECUTABLES", "DEPENDENCIES", "PLUGINS"] {
        found := false;
        for key: seen if key == required found = true;
        if !found return manifest_parse_failure(0, tprint("Missing % record.", required));
    }
    if modules.count != max(expected_modules, 0) || executables.count != max(expected_executables, 0) || dependencies.count != max(expected_dependencies, 0) || plugins.count != max(expected_plugins, 0) || members.count != max(expected_members, 0) || excluded.count != max(expected_excludes, 0) || default_members.count != max(expected_defaults, 0) return manifest_parse_failure(0, "Manifest list count does not match records.");
    for dependency, index: dependencies if dependency.modules.count != max(dependency_module_counts[index], 0) return manifest_parse_failure(0, "Dependency module count does not match records.");
    if !result.package.has_package && !result.package.has_workspace return manifest_parse_failure(0, "PACKAGE must declare a package or workspace.");
    if result.package.has_package && (result.package.name == "" || result.package.version == "") return manifest_parse_failure(0, "Package name and version are required and cannot be empty.");
    if expected_plugins == -1 && result.package.has_package {
        array_add(*plugins, .{id = "load", builtin = true});
        array_add(*plugins, .{id = "test-block", builtin = true});
    }
    result.package.modules = modules;
    result.package.executables = executables;
    result.package.dependencies = dependencies;
    result.package.plugins = plugins;
    result.package.workspace.members = members;
    result.package.workspace.exclude = excluded;
    result.package.workspace.default_members = default_members;
    result.package.fields = fields;
    result.success = true;
    return result;
}
parse_manifest_data :: (content: string) -> Normalized_Package {
    return parse_manifest_data_strict(content).package;
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
    result := run_command("jai", "-import_dir", modules_dir, "-quiet", eval_src);
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
                          spawn: #type (eval_src: string, eval_out: string, modules_dir: string) -> s32 = spawn_manifest_evaluator) -> Normalized_Package, bool {
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
        print("[juice] Migration: docs/migrations/package-declarations.md; replace type/targets/main_file with modules/executables and entry; remove dir/build_script and dependency/plugin version; use explicit source.\n");
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
    normalized_root, root_ok := normalize_existing_path(pkg_dir);
    if !root_ok || !path_exists_as_directory(normalized_root) || !path_chain_is_link_free(pkg_dir) || !path_chain_is_link_free(normalized_root) {
        print("[juice ERROR] Invalid package root for manifest at %: Package root must be an existing real directory.\n", manifest_path);
        return .{}, false;
    }
    parsed.package.dir = copy_string(normalized_root);
    targets := resolve_effective_targets(parsed.package);
    if !targets.success {
        print("[juice ERROR] Invalid package declaration at %: %\n", manifest_path, targets.error_message);
        return .{}, false;
    }
    return parsed.package, true;
}
