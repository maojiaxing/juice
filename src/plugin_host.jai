// Command-level plugin preparation and the PRESTEP-only plugin host (ticket
// 060, spec §5.2/§11.13 design revision 2026-10-21).
//
// Prepare (spec §5.2 "命令级插件准备"): the single scan/registration landing
// point shared by the build and test commands. It runs the declaration-driven
// workspace scan (src/plugin_scan.jai — declaration order, member import
// shims), writes <root>/target/plugins/registration.jai when at least one
// member plugin is declared, and reports whether a spawned host could have
// PRESTEP hooks work to do. Zero declared member plugins = no registration
// file, no host (the built-in transpile values resolve in-process). The test
// command hands the same registration path to the generated metaprogram — the
// metaprogram never scans again (ticket 060's single-scan rule).
//
// Host (spec §5.2 "PRESTEP-only plugin host"): member plugin values live only
// in a program that imports their modules, so the command process cannot run
// their hooks itself. With potential member hooks declared, the prepare
// generates <root>/target/plugins/host.jai — `#import "juice_core"` (the
// published plugin face) plus `#load "<registration>"`, with the root, mode,
// member directories and the member Plugin_Config values embedded as literals
// — and spawns `jai -quiet -import_dir <modules> -import_dir
// <target/packages> host.jai`. The host's `#run` main():
//   1. get_scanned_plugins() -> merge_plugins() (merge diagnostics = failure);
//   2. resolve_plugin_configs() (options apply/validate, version checks —
//      resolver diagnostics = failure);
//   3. fills a Lifecycle_Context + Prestep_Stage and runs
//      run_mounted_hooks(.PRESTEP, .before);
//   4. writes the record file: SUBSTITUTE=<rel>|<abs>, DROP=<rel>,
//      DIAG=<LEVEL>|<message>, OK=0|1 (values %XX-encoded with the shared
//      record encoding discipline; each field is escaped separately because
//      "|" is the field delimiter).
// The parent parses strictly (parse_plugin_host_records) and applies the
// effects to the command's Prestep_Stage through the stage-level prestep_add_*
// rules. A nonzero exit, a missing record file, a malformed record or an
// OK=0/ERROR-diagnostic host result fails the command before any compile.
//
// The host is PRESTEP-only on purpose: it is not a general third-party host
// (spec §11.7) and it only dispatches the `before` mount. Since ticket 061
// every declared member plugin — the pre-step plugin included — resolves and
// dispatches through this host; the command process holds built-in values
// only. Member `after` hooks are not run by this host — the only documented
// Phase-2 limitation (the host driver runs `before`, per the ticket).
//
// The host trigger: the command process cannot load member values, so whether
// a member plugin contributes hooks is decided by the scan's lexical hooks
// probe (Plugin_Scan_Result.has_hooks — a conservative over-approximation;
// a false positive spawns a host that reports no hooks, never a wrong result).
//
// Session artifacts: the registration, the host driver and the record file
// live under <root>/target/ (regenerated every run, removed by clean with the
// whole target tree, never checked in, never part of the bootstrap #load set
// or the published module faces).
//
// Load order: this file references plugin_scan.jai (scan + registration
// codegen), plugin.jai (Plugin_Config / Option_Row), lifecycle.jai
// (Prestep_Stage / Lifecycle_Context / hook dispatch), manifest.jai
// (unescape_record_value — the shared record decoder) and dependency.jai
// (packages_dir); main.jai loads it after those. It must stay test-free; its
// tests live in tests/plugin_host_tests.jai (0053 rule).

#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";

// ---------------------------------------------------------------------------
// Command-level prepare
// ---------------------------------------------------------------------------

// The prepare product: the registration landing path ("" = no declared
// member plugins), the scanned member-plugin hits in declaration order, the
// conservative hooks face signal (true = a host could have PRESTEP work) and
// the scan reports. ok=false means the command must fail before any compile.
Plugin_Prepare_Result :: struct {
    registration_path: string;
    hits:              [..] Plugin_Scan_Hit;
    member_hooks:      bool;
    ok:                bool;
    diagnostics:       [..] Plugin_Scan_Diagnostic;
}

// Command-level plugin preparation: the only declaration scan / member shim /
// registration landing point (build and test both call this before PRESTEP;
// the test metaprogram consumes the returned registration without scanning).
// The scan validates every declared member id, links the declared members
// through their ordinary import shims and returns the hits in declaration
// order. With hits the merged registration file lands at
// <root>/target/plugins/registration.jai; zero hits write nothing (the
// in-process static values need no registration and no host).
prepare_workspace_plugins :: (prepared: *Juice.Prepared_Workspace) -> Plugin_Prepare_Result {
    result: Plugin_Prepare_Result;
    scan := scan_workspace_plugins(prepared.discovery);
    result.hits = scan.hits;
    result.diagnostics = scan.diagnostics;
    result.ok = scan.ok;
    result.member_hooks = scan.has_hooks;
    if !scan.ok return result;
    if scan.hits.count == 0 {
        // Zero declared member plugins = no registration file. A previous run
        // in this workspace may have declared some (the session artifact
        // outlives the declaration); remove the stale file so the contract
        // holds. It is never consumed anyway — the path is only handed out
        // when this run wrote it.
        if prepared.discovery.root_dir != "" {
            target_dir := package_target_dir(prepared.discovery.root_dir);
            registration := workspace_plugin_registration_path(target_dir);
            if file_exists(registration) && !file_delete(registration) {
                array_add(*result.diagnostics, .{rel_path = "target/plugins/registration.jai", message = tprint("Could not remove the stale plugin registration: %", registration), fatal = true});
                result.ok = false;
            }
        }
        return result;
    }

    target_dir := package_target_dir(prepared.discovery.root_dir);
    registration := workspace_plugin_registration_path(target_dir);
    registration_dir := path_strip_filename(registration);
    if !make_directory_if_it_does_not_exist(registration_dir, recursive = true) {
        array_add(*result.diagnostics, .{rel_path = "target/plugins", message = tprint("Could not create the plugin registration directory: %", registration_dir), fatal = true});
        result.ok = false;
        return result;
    }
    if !write_entire_file(registration, generate_plugin_registration(scan.hits)) {
        array_add(*result.diagnostics, .{rel_path = "target/plugins/registration.jai", message = tprint("Could not write the workspace plugin registration: %", registration), fatal = true});
        result.ok = false;
        return result;
    }
    result.registration_path = registration;
    return result;
}

// Print the prepare reports through the command's stderr/stdout conventions:
// fatal reports are errors, dropped duplicates are warnings, and a failed
// prepare prints the one-line summary (the pre-ticket-060 build message kept
// byte-for-byte). Both commands call this so the reporting shape cannot
// drift between them.
report_plugin_prepare :: (result: Plugin_Prepare_Result) {
    for diagnostic: result.diagnostics {
        if diagnostic.fatal {
            print("[juice ERROR] %1: %2\n", diagnostic.rel_path, diagnostic.message);
        } else {
            print("[juice WARNING] %1: %2\n", diagnostic.rel_path, diagnostic.message);
        }
    }
    if !result.ok print("[juice ERROR] Could not prepare the workspace's plugin declarations.\n");
}

// ---------------------------------------------------------------------------
// Host options and landing paths
// ---------------------------------------------------------------------------

// Everything the generated host driver embeds as literals plus the session
// paths the parent writes/reads. configs = the member declarations in the
// shared Plugin_Config shape (the generated test metaprogram embeds the same
// conversion — one declaration-driven drive path for both consumers).
Plugin_Host_Options :: struct {
    root_dir:          string;
    mode:              string;   // "build" / "test" (embedded; the PRESTEP-only
                                 // host behaves identically today)
    member_dirs:       [] string;
    configs:           [] Plugin_Config;
    registration_path: string;
    host_path:         string;
    records_path:      string;
}

plugin_host_dir :: (target_dir: string) -> string {
    return target_plugins_dir(target_dir);
}

plugin_host_path :: (target_dir: string) -> string {
    return path_slashes(tprint("%1/host.jai", plugin_host_dir(target_dir)));
}

plugin_host_records_path :: (target_dir: string) -> string {
    return path_slashes(tprint("%1/host-records.txt", plugin_host_dir(target_dir)));
}

// Assemble the host options over a prepared workspace and the PRESTEP stage
// the command already filled (root/member directories). The declaration
// configs carry only member declarations — the host's registry is exactly the
// scanned member values (the static built-in values never cross the process
// boundary).
plugin_host_options :: (prepared: *Juice.Prepared_Workspace, stage: *Prestep_Stage, mode: string) -> Plugin_Host_Options {
    options: Plugin_Host_Options;
    options.root_dir = path_slashes(prepared.discovery.root_dir);
    options.mode = mode;
    member_dirs: [..] string;
    for dir: stage.member_dirs array_add(*member_dirs, copy_string(dir));
    options.member_dirs = member_dirs;
    options.configs = plugin_configs_from_declarations(prepared.discovery.root_package.plugins, prepared.discovery.member_packages);
    target_dir := package_target_dir(prepared.discovery.root_dir);
    options.registration_path = workspace_plugin_registration_path(target_dir);
    options.host_path = plugin_host_path(target_dir);
    options.records_path = plugin_host_records_path(target_dir);
    return options;
}

// ---------------------------------------------------------------------------
// Host driver generation
// ---------------------------------------------------------------------------

// Append the generated host's record encoder. The parent's
// unescape_record_value is the exact inverse (the shared record encoding
// discipline): only "%", "|", CR and LF are encoded, so arbitrary option
// messages and paths survive the line-record shape. The host is a child
// program and cannot #load src/manifest.jai (not a published module face), so
// the encoder ships as generated text — the manifest evaluator's established
// shape; the host protocol round-trip tests pin the pair.
append_host_escape_code :: (builder: *String_Builder) {
    append(builder, "host_hex_digit :: (n: u8) -> u8 {\n");
    append(builder, "    return cast(u8) ifx n < 10 then #char \"0\" + n else #char \"a\" + (n - 10);\n");
    append(builder, "}\n\n");
    append(builder, "host_escape :: (value: string) -> string {\n");
    append(builder, "    out: [..] u8;\n");
    append(builder, "    for i: 0..value.count-1 {\n");
    append(builder, "        c := value[i];\n");
    append(builder, "        if c == #char \"%\" || c == #char \"|\" || c == #char \"\\n\" || c == #char \"\\r\" {\n");
    append(builder, "            array_add(*out, #char \"%\");\n");
    append(builder, "            array_add(*out, host_hex_digit(cast(u8) ((c >> 4) & 0xf)));\n");
    append(builder, "            array_add(*out, host_hex_digit(cast(u8) (c & 0xf)));\n");
    append(builder, "        } else {\n");
    append(builder, "            array_add(*out, c);\n");
    append(builder, "        }\n");
    append(builder, "    }\n");
    append(builder, "    if out.count == 0 return \"\";\n");
    append(builder, "    return copy_string(to_string(out.data, out.count));\n");
    append(builder, "}\n\n");
}

// One Plugin_Config literal array (the same shape the test metaprogram
// embeds): the member declarations' ids, versions and option rows in
// declaration order.
append_host_plugin_configs :: (builder: *String_Builder, configs: [] Plugin_Config) {
    append(builder, "plugin_configs: [] Plugin_Config = Plugin_Config.[");
    for config, config_index: configs {
        if config_index > 0 append(builder, ", ");
        print_to_builder(builder, ".{ id = %1, version = %2, options = Option_Row.[", quote_jai_string(config.id), quote_jai_string(config.version));
        for row, row_index: config.options {
            if row_index > 0 append(builder, ", ");
            print_to_builder(builder, ".{ key = %1, value = %2 }", quote_jai_string(row.key), quote_jai_string(row.value));
        }
        append(builder, "] }");
    }
    append(builder, "];\n\n");
}

// The generated host driver (session artifact under target/plugins/). All
// paths are absolute and "/"-separated: the jai child anchors its #run
// working directory at the driver's own directory, so relative paths would
// resolve one layer deeper (the established generated-text discipline).
generate_plugin_host :: (options: Plugin_Host_Options) -> string {
    builder: String_Builder;
    append(*builder, "// juice plugin host — generated session artifact: regenerated every run,\n");
    append(*builder, "// removed by clean with target/, never edited. PRESTEP-only (ticket 060,\n");
    append(*builder, "// spec §5.2): load the declared member plugins, apply their options, run\n");
    append(*builder, "// the PRESTEP before hooks and record the stage effects for the parent.\n");
    append(*builder, "#import \"Basic\";\n");
    append(*builder, "#import \"Compiler\";\n");
    append(*builder, "#import \"File\";\n");
    append(*builder, "#import \"String\";\n");
    append(*builder, "#import \"juice_core\";\n\n");
    print_to_builder(*builder, "#load %1;\n\n", quote_jai_string(path_slashes(options.registration_path)));
    append(*builder, "#run {\n");
    append(*builder, "    set_build_options_dc(.{do_output = false});\n");
    append(*builder, "    main();\n");
    append(*builder, "}\n\n");

    // The embedded inputs: root / mode / member dirs / configs (spec §5.2).
    print_to_builder(*builder, "HOST_ROOT :: %1;\n", quote_jai_string(path_slashes(options.root_dir)));
    print_to_builder(*builder, "HOST_MODE :: %1;\n", quote_jai_string(options.mode));
    append(*builder, "HOST_MEMBER_DIRS :: string.[");
    for dir, index: options.member_dirs {
        if index > 0 append(*builder, ", ");
        print_to_builder(*builder, "%1", quote_jai_string(path_slashes(dir)));
    }
    append(*builder, "];\n");
    print_to_builder(*builder, "HOST_OUTPUT_PATH :: %1;\n\n", quote_jai_string(path_slashes(options.records_path)));
    append_host_plugin_configs(*builder, options.configs);
    append_host_escape_code(*builder);

    // Diagnostics-level mapping and the failure emitter: merge/resolver
    // rejections are host failures — every diagnostic is an ERROR record and
    // OK=0.
    append(*builder, "host_diag_level :: (level: Lifecycle_Diagnostic_Level) -> string {\n");
    append(*builder, "    if level == .ERROR return \"ERROR\";\n");
    append(*builder, "    if level == .WARNING return \"WARNING\";\n");
    append(*builder, "    return \"INFO\";\n");
    append(*builder, "}\n\n");
    append(*builder, "host_emit_failure :: (builder: *String_Builder, diagnostics: [] Transpile_Diagnostic) {\n");
    append(*builder, "    for diagnostic: diagnostics print_to_builder(builder, \"DIAG=ERROR|%\\n\", host_escape(diagnostic.message));\n");
    append(*builder, "    print_to_builder(builder, \"OK=0\\n\");\n");
    append(*builder, "}\n\n");

    append(*builder, "main :: () {\n");
    append(*builder, "    builder: String_Builder;\n");
    append(*builder, "    plugins := get_scanned_plugins();\n");
    append(*builder, "    merged := merge_plugins(plugins);\n");
    append(*builder, "    if !merged.ok {\n");
    append(*builder, "        host_emit_failure(*builder, merged.diagnostics);\n");
    append(*builder, "        if !write_entire_file(HOST_OUTPUT_PATH, builder_to_string(*builder)) exit(1);\n");
    append(*builder, "        return;\n");
    append(*builder, "    }\n");
    append(*builder, "    resolved := resolve_plugin_configs(merged.registry, plugin_configs);\n");
    append(*builder, "    if !resolved.ok {\n");
    append(*builder, "        host_emit_failure(*builder, resolved.diagnostics);\n");
    append(*builder, "        if !write_entire_file(HOST_OUTPUT_PATH, builder_to_string(*builder)) exit(1);\n");
    append(*builder, "        return;\n");
    append(*builder, "    }\n");
    append(*builder, "    stage: Prestep_Stage;\n");
    append(*builder, "    stage.root_dir = HOST_ROOT;\n");
    append(*builder, "    for dir: HOST_MEMBER_DIRS array_add(*stage.member_dirs, dir);\n");
    append(*builder, "    diags: [..] Lifecycle_Diagnostic;\n");
    append(*builder, "    lctx: Lifecycle_Context;\n");
    append(*builder, "    lctx.diagnostics = *diags;\n");
    append(*builder, "    lctx.prestep = *stage;\n");
    append(*builder, "    for slot: resolved.slot_options array_add(*lctx.plugin_state, slot);\n");
    append(*builder, "    hooks_ok := run_mounted_hooks(resolved.hook_table, .PRESTEP, .before, *lctx);\n");
    append(*builder, "    for substitution: stage.substitutions {\n");
    append(*builder, "        print_to_builder(*builder, \"SUBSTITUTE=%1|%2\\n\", host_escape(substitution.original), host_escape(substitution.replacement));\n");
    append(*builder, "    }\n");
    append(*builder, "    for dropped: stage.drops print_to_builder(*builder, \"DROP=%\\n\", host_escape(dropped));\n");
    append(*builder, "    for diagnostic: diags {\n");
    append(*builder, "        print_to_builder(*builder, \"DIAG=%1|%2\\n\", host_diag_level(diagnostic.level), host_escape(diagnostic.message));\n");
    append(*builder, "    }\n");
    append(*builder, "    if hooks_ok {\n");
    append(*builder, "        print_to_builder(*builder, \"OK=1\\n\");\n");
    append(*builder, "    } else {\n");
    append(*builder, "        print_to_builder(*builder, \"OK=0\\n\");\n");
    append(*builder, "    }\n");
    append(*builder, "    if !write_entire_file(HOST_OUTPUT_PATH, builder_to_string(*builder)) exit(1);\n");
    append(*builder, "}\n");
    return builder_to_string(*builder);
}

// ---------------------------------------------------------------------------
// Host spawn and record parsing
// ---------------------------------------------------------------------------

// The host's import directories: the published plugin face (<exe>/modules —
// juice_core and its closure) and the dependency shim directory
// (<root>/target/packages — the declared members' import shims). The scan
// already linked every declared member, so the shim directory exists.
plugin_host_import_dirs :: (root_dir: string) -> [..] string {
    dirs: [..] string;
    array_add(*dirs, path_slashes(juice_modules_dir()));
    array_add(*dirs, path_slashes(packages_dir(root_dir)));
    return dirs;
}

// Production host spawn: `jai -quiet -import_dir <modules> -import_dir
// <target/packages> host.jai`. stderr is inherited (the child's compile
// diagnostics pass through verbatim); the host driver stays the last argument
// — the jai entry file.
spawn_plugin_host :: (host_path: string, import_dirs: [] string) -> Process_Result {
    args: [..] string;
    array_add(*args, "jai");
    array_add(*args, "-quiet");
    for dir: import_dirs {
        array_add(*args, "-import_dir");
        array_add(*args, dir);
    }
    array_add(*args, host_path);
    return run_command(..args);
}

// The parsed host records. error != "" = the record file is malformed (the
// command fails before any compile); ok = the host's final OK=1; the stage
// effects and diagnostics keep the host's emission order.
Plugin_Host_Records :: struct {
    substitutions: [..] Source_Substitution;
    drops:         [..] string;
    diagnostics:   [..] Lifecycle_Diagnostic;
    ok:            bool;
    error:         string;
}

// Strict record parser (the manifest protocol's parsing posture): every line
// must be a known KEY=VALUE record with the exact field count; unknown keys,
// malformed %XX escapes, empty required fields, duplicate/after-OK records,
// blank interior lines and a missing OK record are all errors. Values were
// escaped field-by-field because "|" delimits the fields.
parse_plugin_host_records :: (text: string) -> Plugin_Host_Records {
    out: Plugin_Host_Records;
    ok_seen := false;
    lines := split(text, "\n");
    for line_index: 0..lines.count-1 {
        line := lines[line_index];
        if line.count > 0 && line[line.count-1] == #char "\r" line = slice(line, 0, line.count - 1);
        if line.count == 0 {
            // The generated record file ends with a newline: split's final
            // empty segment is legal. Any other blank line corrupts the shape.
            if line_index == lines.count - 1 continue;
            out.error = tprint("blank line at line %", line_index + 1);
            return out;
        }
        if ok_seen {
            out.error = tprint("record after OK at line %", line_index + 1);
            return out;
        }
        equals := find_index_from_left(line, "=");
        if equals < 0 {
            out.error = tprint("missing '=' at line %", line_index + 1);
            return out;
        }
        key := slice(line, 0, equals);
        value := slice(line, equals + 1, line.count - equals - 1);

        if key == "OK" {
            if value == "1" {
                out.ok = true;
            } else if value == "0" {
                out.ok = false;
            } else {
                out.error = tprint("OK must be 0 or 1 at line %", line_index + 1);
                return out;
            }
            ok_seen = true;
            continue;
        }

        if key == "SUBSTITUTE" {
            separator := find_index_from_left(value, "|");
            if separator < 0 {
                out.error = tprint("SUBSTITUTE needs two fields at line %", line_index + 1);
                return out;
            }
            original, original_ok := unescape_record_value(slice(value, 0, separator));
            replacement, replacement_ok := unescape_record_value(slice(value, separator + 1, value.count - separator - 1));
            if !original_ok || !replacement_ok {
                out.error = tprint("malformed percent escape at line %", line_index + 1);
                return out;
            }
            if original.count == 0 || replacement.count == 0 {
                out.error = tprint("empty SUBSTITUTE field at line %", line_index + 1);
                return out;
            }
            array_add(*out.substitutions, .{original = original, replacement = replacement});
            continue;
        }

        if key == "DROP" {
            dropped, dropped_ok := unescape_record_value(value);
            if !dropped_ok {
                out.error = tprint("malformed percent escape at line %", line_index + 1);
                return out;
            }
            if dropped.count == 0 {
                out.error = tprint("empty DROP field at line %", line_index + 1);
                return out;
            }
            array_add(*out.drops, dropped);
            continue;
        }

        if key == "DIAG" {
            separator := find_index_from_left(value, "|");
            if separator < 0 {
                out.error = tprint("DIAG needs two fields at line %", line_index + 1);
                return out;
            }
            level_text := slice(value, 0, separator);
            message, message_ok := unescape_record_value(slice(value, separator + 1, value.count - separator - 1));
            if !message_ok {
                out.error = tprint("malformed percent escape at line %", line_index + 1);
                return out;
            }
            level: Lifecycle_Diagnostic_Level;
            if level_text == "ERROR" {
                level = .ERROR;
            } else if level_text == "WARNING" {
                level = .WARNING;
            } else if level_text == "INFO" {
                level = .INFO;
            } else {
                out.error = tprint("unknown diagnostic level '%' at line %", level_text, line_index + 1);
                return out;
            }
            array_add(*out.diagnostics, .{level = level, message = message});
            continue;
        }

        out.error = tprint("unknown record key '%' at line %", key, line_index + 1);
        return out;
    }
    if !ok_seen out.error = "missing OK record";
    return out;
}

// Run the host: write the driver, remove a stale record file (a crashed host
// must never be masked by an older success), spawn, then read and parse the
// record file. A nonzero exit, a missing file or a malformed file is a
// command failure (the caller aborts before any compile).
run_plugin_host :: (
    options: Plugin_Host_Options,
    spawn: #type (host_path: string, import_dirs: [] string) -> Process_Result = spawn_plugin_host
) -> (Plugin_Host_Records, bool) {
    records: Plugin_Host_Records;
    if options.registration_path == "" {
        print("[juice ERROR] Plugin host requires a plugin registration file.\n");
        return records, false;
    }
    host_dir := path_strip_filename(options.host_path);
    if !make_directory_if_it_does_not_exist(host_dir, recursive = true) {
        print("[juice ERROR] Could not create the plugin host directory: %\n", host_dir);
        return records, false;
    }
    if !write_entire_file(options.host_path, generate_plugin_host(options)) {
        print("[juice ERROR] Could not write the plugin host driver: %\n", options.host_path);
        return records, false;
    }
    if file_exists(options.records_path) {
        if !file_delete(options.records_path) {
            print("[juice ERROR] Could not remove the stale plugin host record file: %\n", options.records_path);
            return records, false;
        }
    }

    import_dirs := plugin_host_import_dirs(options.root_dir);
    result := spawn(options.host_path, import_dirs);
    if result.exit_code != 0 {
        // The child's stderr was inherited (passthrough); the summary is the
        // command's own line.
        print("[juice ERROR] Plugin host failed (exit %).\n", result.exit_code);
        return records, false;
    }

    text, read_ok := read_entire_file(options.records_path);
    if !read_ok {
        print("[juice ERROR] Plugin host produced no output record file: %\n", options.records_path);
        return records, false;
    }
    records = parse_plugin_host_records(text);
    if records.error != "" {
        print("[juice ERROR] Invalid plugin host output: %\n", records.error);
        return records, false;
    }
    return records, true;
}

// Apply the host's stage effects to the command's Prestep_Stage: report the
// host diagnostics (mapped to the [juice ERROR]/[juice WARNING]/[juice]
// convention and added to the lifecycle sink), fail on OK=0 or any ERROR
// diagnostic, then merge the substitution/drop rows through the stage-level
// prestep_add_* rules (the same conflict checks an in-process hook gets).
// A rejected row prints the rule's ERROR diagnostic and fails the command.
plugin_host_table_failure :: (diagnostics: *[..] Lifecycle_Diagnostic) -> bool {
    if diagnostics.count > 0 print("[juice ERROR] %\n", diagnostics.*[diagnostics.count - 1].message);
    return false;
}

apply_plugin_host_effects :: (stage: *Prestep_Stage, records: Plugin_Host_Records, diagnostics: *[..] Lifecycle_Diagnostic) -> bool {
    saw_error := false;
    for diagnostic: records.diagnostics {
        if diagnostic.level == .ERROR {
            print("[juice ERROR] %\n", diagnostic.message);
            saw_error = true;
        } else if diagnostic.level == .WARNING {
            print("[juice WARNING] %\n", diagnostic.message);
        } else {
            print("[juice] %\n", diagnostic.message);
        }
        array_add(diagnostics, diagnostic);
    }
    if !records.ok || saw_error {
        print("[juice ERROR] The plugin host reported a pre-step failure.\n");
        return false;
    }

    ctx: Lifecycle_Context;
    ctx.diagnostics = diagnostics;
    // The prestep_add_* helpers read the stage through the context slot; the
    // host's rows go through the same stage-level rules as in-process hooks.
    ctx.prestep = stage;
    for substitution: records.substitutions {
        if prestep_add_substitution(*ctx, substitution.original, substitution.replacement) continue;
        return plugin_host_table_failure(diagnostics);
    }
    for dropped: records.drops {
        if prestep_add_drop(*ctx, dropped) continue;
        return plugin_host_table_failure(diagnostics);
    }
    return true;
}
