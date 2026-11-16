// ---------------------------------------------------------------------------
// The `juice-plugin-jaix` member plugin (ticket 061, spec §8.3): one
// Juice_Plugin contributing a PRESTEP `before` hook and the `config` / `exe`
// options schema. Phase 1 kept this value static in src/jaix_plugin.jai;
// Phase 2 moves it here — the command-level plugin prepare locates this
// member through the root's Package.plugins declaration, links its import
// shim and the PRESTEP-only host loads the value (the command process never
// does). The acquisition contract is the ordinary member one:
// `get_juice_plugin` with the @juice_plugin tail note.
//
// The plugin owns the whole pre-step: the package scan (its own exclusion
// set — dot entries at any depth, non-.jai files, the root manifest, the
// root-level target/, member subtrees, the declared config file, stale
// driver litter and files containing juice test blocks), the per-file
// `jaix transpile` spawn (all-absolute paths, stderr passed through
// verbatim, the child's working directory pinned to target/jaix-drivers/ so
// the CLI's per-call session drivers never become package sources), the
// target/jaix/ mirror (package-relative structure; the sidecar .map files
// land next to the views by the CLI's own default) and the executable
// resolution (the `exe` option, or the PATH probe for "jaix").
//
// The scan is the plugin's own (spec §11.14): the member packages never
// publish scan_walk, so the deterministic DFS enumeration lives here,
// together with the plugin's path helpers (path_safety is a tool-internal
// module, not part of the juice_core face). The walk itself is Jai's
// File_Utilities visit_files with two exclusion predicates; the enumeration
// is files-first-then-subdirectories, lexicographic by name.
//
// Stage effects (the PRESTEP tables of ticket 057): every mirrored file
// becomes a source substitution (original = the package-relative path,
// replacement = the mirror's absolute path); the declared config file
// becomes a drop (it is jaix's compile-time input, not a package source);
// stale driver litter removed from the package root becomes a drop too (the
// test file collection runs before the pre-step, so a collected litter file
// must never reach the test program). Test-block files are never mirrored —
// jaix cannot parse the juice test block syntax without its test block
// plugin, which the config excludes — so they keep their original transpile
// path. Member subtrees are never scanned: members run their own pre-step
// as their own package root.
//
// Failure = stage failure = command failure: a missing executable, a
// missing config, an unscannable or undeletable package root, a spawn
// failure (the child's diagnostics pass through verbatim) and any table
// conflict all return false after an ERROR diagnostic (and a user-facing
// [juice ERROR] line). Inside the host the failure turns into OK=0 records
// the parent command rejects before any compile.
//
// juice_core is the tool-provided module face (resolved from the installed
// executable's adjacent modules directory). This module MUST stay test-free:
// the generated host and the test metaprogram compile it directly, so test
// blocks would not compile there. The member's own tests live in
// tests/jaix_plugin_tests.jai and run with the member root as their package.
// ---------------------------------------------------------------------------

#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
#import "juice_core";

#if OS == .WINDOWS {
    #import "Windows";
    #import "Windows_Utf8";

    // The environment probe (the PATH fallback). The stdlib Windows module
    // does not expose GetEnvironmentVariable, so the plugin declares the one
    // symbol it needs (the tool-internal xdg.jai helper is not published).
    jaix_kernel32 :: #system_library "kernel32";
    GetEnvironmentVariableA :: (lpName: *u8, lpBuffer: *u8, nSize: u32) -> u32 #foreign jaix_kernel32;

    jaix_get_env :: (name: string) -> string {
        c_name := temp_c_string(name);
        needed := GetEnvironmentVariableA(c_name, null, 0);
        if needed == 0 return "";
        buf := cast(*u8) talloc(needed);
        len := GetEnvironmentVariableA(c_name, buf, needed);
        return ifx len == 0 then "" else to_string(buf, len);
    }
} else {
    #import "POSIX";

    jaix_get_env :: (name: string) -> string {
        c_name := temp_c_string(name);
        c_val := getenv(c_name);
        return ifx !c_val then "" else to_string(c_val);
    }
}

// ---------------------------------------------------------------------------
// Identity and options
// ---------------------------------------------------------------------------

// The plugin declaration identity: the member package name (v1 member plugin
// id = member package name) and the version a declaration must repeat (the
// resolver's version gate).
JAIX_PLUGIN_ID :: "juice-plugin-jaix";
JAIX_PLUGIN_VERSION :: "0.1.0";

// The derived plugin value: the unified face plus the typed options —
// `config` (package-relative path of the jaix configuration; empty = the
// declaration runs nothing, the undeclared no-op shape) and `exe` (optional
// executable; empty = the PATH probe for "jaix"). The typed member must not
// be named `options`: that name is the framework's *void channel on the
// base face (Jai rejects the redeclaration).
Jaix_Plugin :: struct {
    using base: Juice_Plugin;
    config:     string = "";
    exe:        string = "";
}

// Module-held option defaults (Config_Option.default points at stable
// storage; the framework reads it, never writes it).
JAIX_DEFAULT_CONFIG: string = "";
JAIX_DEFAULT_EXE: string = "";

// The options applier: the plugin owns the key set, so an unknown key is
// its error (the Config_Option.apply contract).
jaix_apply_option :: (options: *void, key: string, value: string) -> string {
    plugin := cast(*Jaix_Plugin) options;
    if key == "config" {
        plugin.config = value;
        return "";
    }
    if key == "exe" {
        plugin.exe = value;
        return "";
    }
    return tprint("unknown option '%'", key);
}

// The post-assembly check: an executable without a config is a declaration
// mistake (there would be nothing to transpile; a bare exe would otherwise
// silently do nothing). An empty config alone stays legal — the declared
// no-op shape.
jaix_validate_options :: (options: *void) -> string {
    plugin := cast(*Jaix_Plugin) options;
    if plugin.exe != "" && plugin.config == "" return "option 'exe' requires 'config'";
    return "";
}

// The acquisition contract: one PRESTEP before hook plus the two-row options
// schema. The options channel points at the plugin instance itself (the
// Config_Option.apply / hook plugin_state contract). The @juice_plugin tail
// note is the lexical anchor the command-level member scan matches
// (src/plugin_scan.jai).
get_juice_plugin :: () -> *Jaix_Plugin {
    plugin := New(Jaix_Plugin);
    plugin.id = JAIX_PLUGIN_ID;
    plugin.version = JAIX_PLUGIN_VERSION;
    plugin.options = cast(*void) plugin;
    array_add(*plugin.hooks, .{stage = .PRESTEP, position = .before, hook = jaix_prestep_hook});
    array_add(*plugin.options_schema, config_option("config", *JAIX_DEFAULT_CONFIG, jaix_apply_option, jaix_validate_options));
    // The assembled-options check runs once per schema entry's validate; the
    // second row carries no validator so a rejection reports exactly once.
    array_add(*plugin.options_schema, config_option("exe", *JAIX_DEFAULT_EXE, jaix_apply_option, null));
    return plugin;
} @juice_plugin

// ---------------------------------------------------------------------------
// The PRESTEP hook
// ---------------------------------------------------------------------------

// The hook: reads its typed options from the plugin_state slot (the slot
// carries plugin.options — the same pointer the resolver applied the rows
// to), then runs the whole pre-step against the stage's root. An empty
// config is the declared no-op (true, zero effects). A missing slot or a
// missing prestep state is a wiring failure (false + ERROR).
jaix_prestep_hook :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    if state == null {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("%: missing options state", JAIX_PLUGIN_ID)});
        return false;
    }
    plugin := cast(*Jaix_Plugin) state;
    if plugin.config == "" return true;
    if ctx.prestep == null {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("%: missing prestep state", JAIX_PLUGIN_ID)});
        return false;
    }
    return run_jaix_prestep(ctx, plugin);
}

// Report one pre-step failure: the user-facing line on stdout (the plain
// [juice ERROR] convention) plus an ERROR diagnostic (which fails the stage
// by the ordinary dispatch rule).
jaix_prestep_failure :: (ctx: *Lifecycle_Context, message: string) -> bool {
    print("[juice ERROR] %\n", message);
    array_add(ctx.diagnostics, .{level = .ERROR, message = message});
    return false;
}

// The pre-step orchestration over the stage's root:
//   1. resolve the config (package-relative; it must exist) and the
//      executable (option or PATH);
//   2. clean stale driver litter from the package root (content marker; the
//      removed paths join the drop set);
//   3. scan the package under the plugin's exclusion set;
//   4. spawn one `jaix transpile` per file into the target/jaix/ mirror and
//      fill the substitution table;
//   5. drop the config file.
// The spawn step is injectable (the seam tests run a recording fake instead
// of the real CLI); path_value is the PATH probe's injectable input ("" =
// the process PATH — a default parameter cannot be an imperative call).
run_jaix_prestep :: (
    ctx: *Lifecycle_Context,
    plugin: *Jaix_Plugin,
    spawn: #type (exe: string, input: string, output: string, config: string, driver_dir: string) -> (s64, string) = spawn_jaix_transpile,
    path_value := ""
) -> bool {
    stage := cast(*Prestep_Stage) ctx.prestep;
    root_dir := jaix_path_slashes(stage.root_dir);
    config_rel := jaix_path_slashes(plugin.config);
    config_abs := jaix_path_slashes(tprint("%1/%2", root_dir, config_rel));
    if !jaix_regular_file_exists(config_abs) {
        return jaix_prestep_failure(ctx, tprint("jaix config not found: %", config_abs));
    }

    exe, exe_ok := resolve_jaix_exe(plugin, root_dir, path_value);
    if !exe_ok return false;

    // Stale litter first: old runs left driver files at the package root
    // (the CLI writes its session driver into the child's working
    // directory). They are not package sources; the scan below would
    // otherwise transpile them, and the test file collection (which runs
    // before this stage) may already hold them — hence the drop rows.
    if !clean_jaix_driver_litter(ctx) return false;

    files, scan_ok := collect_jaix_files(root_dir, config_rel, stage.member_dirs);
    if !scan_ok {
        return jaix_prestep_failure(ctx, tprint("Could not scan package root for jaix sources: %", root_dir));
    }
    print("[juice] Running jaix pre-step (% files) -> target/jaix/...\n", files.count);

    // The CLI writes its per-call session driver into the child's working
    // directory (the driver cannot run from a read-only cwd); target/ is
    // outside every package scan, so the drivers can never be mistaken for
    // sources.
    driver_dir := jaix_path_slashes(tprint("%1/target/jaix-drivers", root_dir));
    if !make_directory_if_it_does_not_exist(driver_dir, recursive = true) {
        return jaix_prestep_failure(ctx, tprint("Could not create the jaix driver directory: %", driver_dir));
    }

    for file: files {
        output := jaix_mirror_view_path(root_dir, file.rel_path);
        if !make_directory_if_it_does_not_exist(path_strip_filename(output), recursive = true) {
            return jaix_prestep_failure(ctx, tprint("Could not create mirror directory for %", file.rel_path));
        }
        exit_code, stderr := spawn(exe, file.abs_path, output, config_abs, driver_dir);
        if exit_code != 0 {
            // The child's diagnostics pass through verbatim on stderr; the
            // failure summary stays the plugin's own line.
            if stderr.count > 0 print("%", stderr, to_standard_error = true);
            return jaix_prestep_failure(ctx, tprint("jaix pre-step failed for %", file.rel_path));
        }
        if !prestep_add_substitution(ctx, file.rel_path, output) return false;
    }

    // The config file is jaix's compile-time input, never a package source:
    // a collected config (the test command collects every root .jai file)
    // leaves the test program.
    return prestep_add_drop(ctx, config_rel);
}

// ---------------------------------------------------------------------------
// Executable resolution
// ---------------------------------------------------------------------------

// The executable resolution: the declared exe wins — a package-relative
// path resolves against the package root, an absolute path is used as-is;
// otherwise the PATH is probed for "jaix" ("jaix.exe" on Windows). The ""
// path sentinel means the real process PATH (tests inject a crafted PATH).
// A missing executable fails with the clear error before any spawn.
resolve_jaix_exe :: (plugin: *Jaix_Plugin, root_dir: string, path_value := "") -> (exe: string, ok: bool) {
    path := path_value;
    if path == "" path = jaix_get_env("PATH");
    if plugin.exe != "" {
        declared := ifx jaix_path_is_absolute(plugin.exe)
            then jaix_path_slashes(plugin.exe)
            else jaix_path_slashes(tprint("%1/%2", root_dir, plugin.exe));
        if file_exists(declared) && !is_directory(declared) return declared, true;
        print("[juice ERROR] jaix executable not found: %\n", declared);
        return "", false;
    }

    #if OS == .WINDOWS {
        separator := ";";
        candidate_name := "jaix.exe";
    } else {
        separator := ":";
        candidate_name := "jaix";
    }
    entries := split(path, separator);
    for entry: entries {
        if entry == "" continue;
        candidate := jaix_path_slashes(tprint("%1/%2", entry, candidate_name));
        if file_exists(candidate) && !is_directory(candidate) return candidate, true;
    }
    print("[juice ERROR] jaix executable not found: 'jaix' is not on PATH (declare the exe option in the % declaration).\n", JAIX_PLUGIN_ID);
    return "", false;
}

// ---------------------------------------------------------------------------
// Spawn
// ---------------------------------------------------------------------------

// The production per-file spawn: `jaix transpile <abs input> -o <abs output>
// --config <abs config>` with the child's working directory at the driver
// directory (the CLI writes its session driver there). All three paths are
// absolute: the CLI's driver child runs with its own working directory
// switched to the driver file's location, so relative arguments would
// resolve against the wrong directory. stderr is captured for the
// passthrough; a non-EXITED result counts as failure.
spawn_jaix_transpile :: (exe: string, input: string, output: string, config: string, driver_dir: string) -> (exit_code: s64, stderr: string) {
    result, _, errors, _ := run_command(exe, "transpile", input, "-o", output, "--config", config,
        working_directory = driver_dir, capture_and_return_output = true);
    if result.type == .EXITED return result.exit_code, errors;
    return 1, errors;
}

// ---------------------------------------------------------------------------
// Scan (the plugin's own exclusion set and walk)
// ---------------------------------------------------------------------------

// One scanned package file: the package-relative path ("/" separated,
// mirroring the package directory structure) and the absolute source path.
Jaix_File :: struct {
    rel_path: string;
    abs_path: string;
}

// Raw walk entries (short name plus full path) collected during the walk;
// the deterministic enumeration consumes them after the walk.
Jaix_Scan_Entry :: struct {
    short_name: string;
    full_name:  string;
}

// The walk state: the scan root, the declared config's package-relative
// path (skipped — jaix's compile-time input, and the CLI's parser cannot
// round-trip the config shape), the member boundaries from the stage
// (members run their own pre-step as their own roots) and the raw entries.
Jaix_Walk_State :: struct {
    root:        string;
    config_rel:  string;
    member_dirs: [..] string;
    files:       [..] Jaix_Scan_Entry;
    dirs:        [..] Jaix_Scan_Entry;
}

// Full-package scan: the deterministic DFS walk (files first in
// lexicographic order, then subdirectories) under the plugin's exclusion
// predicates. Failure = the walk could not read the root; the caller prints
// its own message.
collect_jaix_files :: (root_dir: string, config_rel: string, member_dirs: [] string) -> ([] Jaix_File, bool) {
    walk: Jaix_Walk_State;
    walk.root = jaix_path_slashes(root_dir);
    while walk.root.count > 0 && walk.root[walk.root.count - 1] == #char "/" walk.root.count -= 1;
    walk.config_rel = jaix_path_slashes(config_rel);
    for member: member_dirs {
        normalized := jaix_path_slashes(member);
        while normalized.count > 0 && normalized[normalized.count - 1] == #char "/" normalized.count -= 1;
        array_add(*walk.member_dirs, normalized);
    }
    visited := visit_files(walk.root, true, *walk, jaix_walk_visitor,
        visit_files = true, visit_directories = true,
        visit_symlinks = false, follow_directory_symlinks = false);
    if !visited return Jaix_File.[], false;
    return jaix_enumerate_files(*walk), true;
}

// The walk callback: exclusion predicates prune directories and filter
// files; the surviving entries are collected for the deterministic
// enumeration below.
jaix_walk_visitor :: (info: *File_Visit_Info, walk: *Jaix_Walk_State) {
    if info.is_directory {
        if jaix_scan_directory_excluded(info, walk) {
            info.descend_into_directory = false;
            return;
        }
        entry: Jaix_Scan_Entry;
        entry.short_name = copy_string(info.short_name);
        entry.full_name  = copy_string(info.full_name);
        array_add(*walk.dirs, entry);
        return;
    }
    if jaix_scan_file_excluded(info, walk) return;
    entry: Jaix_Scan_Entry;
    entry.short_name = copy_string(info.short_name);
    entry.full_name  = copy_string(info.full_name);
    array_add(*walk.files, entry);
}

// Directory-side exclusions: dot entries at any depth; the root-level
// target/ (managed products — the mirror and driver landing spots);
// workspace member subtrees; links of any kind (visit_files skips symlink
// entries itself, Windows junctions surface as plain directories there, so
// they are inspected explicitly — the plugin's own path-safety posture).
jaix_scan_directory_excluded :: (info: *File_Visit_Info, walk: *Jaix_Walk_State) -> bool {
    if info.short_name.count > 0 && info.short_name[0] == #char "." return true;
    rel := jaix_rel_path(info.full_name, walk.root);
    if jaix_paths_equal(rel, "target") return true;
    for member: walk.member_dirs {
        if jaix_paths_equal(info.full_name, member) return true;
    }
    if info.is_symlink return true;
    return jaix_is_reparse_point(info.full_name);
}

// File-side exclusions: dot entries at any depth; non-.jai files; the scan
// root's own manifest (a nested package.jai is user code and stays
// scanned); the declared config file; stale driver litter (content marker,
// any depth — legacy hash-named litter is caught too); and files containing
// juice test blocks (the mixed-package seam: jaix cannot parse the test
// block syntax without its test block plugin, which the config excludes, so
// juice's own test block files keep their original transpile path). An
// unreadable file stays included — the CLI child's own read diagnostic
// passes through.
jaix_scan_file_excluded :: (info: *File_Visit_Info, walk: *Jaix_Walk_State) -> bool {
    if info.short_name.count > 0 && info.short_name[0] == #char "." return true;
    if !ends_with(info.short_name, ".jai") return true;
    if info.short_name == "package.jai" && jaix_paths_equal(jaix_entry_parent(info.full_name), walk.root) return true;
    rel := jaix_rel_path(info.full_name, walk.root);
    if walk.config_rel != "" && jaix_paths_equal(rel, walk.config_rel) return true;
    if is_jaix_driver_litter(info.full_name) return true;
    source, read_ok := read_entire_file(info.full_name, log_errors = false);
    if read_ok && pipeline_has_anchors(default_transpile_pipeline(), source, rel) return true;
    return false;
}

// Deterministic DFS enumeration in scan order: within each directory,
// files first (lexicographic by name), then subdirectories (lexicographic),
// recursing. The spawn order and the mirror order derive from it.
jaix_enumerate_files :: (walk: Jaix_Walk_State) -> [..] Jaix_File {
    out: [..] Jaix_File;
    stack: [..] string;
    array_add(*stack, copy_string(walk.root));
    while stack.count > 0 {
        dir := stack[stack.count - 1];
        stack.count -= 1;
        dir_files: [..] Jaix_Scan_Entry;
        dir_subdirs: [..] Jaix_Scan_Entry;
        for entry: walk.files {
            if jaix_paths_equal(jaix_entry_parent(entry.full_name), dir) array_add(*dir_files, entry);
        }
        for entry: walk.dirs {
            if jaix_paths_equal(jaix_entry_parent(entry.full_name), dir) array_add(*dir_subdirs, entry);
        }
        jaix_sort_entries(dir_files);
        jaix_sort_entries(dir_subdirs);
        for entry: dir_files {
            file: Jaix_File;
            file.abs_path = jaix_path_slashes(entry.full_name);
            file.rel_path = jaix_rel_path(entry.full_name, walk.root);
            array_add(*out, file);
        }
        // Push in reverse so the subdirectories pop in sorted order.
        i := dir_subdirs.count;
        while i > 0 {
            i -= 1;
            array_add(*stack, dir_subdirs[i].full_name);
        }
    }
    return out;
}

// Insertion sort over one directory's entries (lexicographic by short
// name; the enumeration is deterministic).
jaix_sort_entries :: (entries: [] Jaix_Scan_Entry) {
    for i: 1..entries.count-1 {
        if i >= entries.count break;
        key := entries[i];
        j := i - 1;
        while j >= 0 && compare(entries[j].short_name, key.short_name) > 0 {
            entries[j+1] = entries[j];
            j -= 1;
        }
        entries[j+1] = key;
    }
}

// ---------------------------------------------------------------------------
// Mirror paths
// ---------------------------------------------------------------------------

// The mirror root: <package>/target/jaix/ with the package-relative
// structure mirrored inside; the sidecar <file>.map files land next to the
// views by the CLI's default behavior.
jaix_mirror_dir :: (root_dir: string) -> string {
    return jaix_path_slashes(tprint("%1/target/jaix", root_dir));
}

jaix_mirror_view_path :: (root_dir: string, rel_path: string) -> string {
    return jaix_path_slashes(tprint("%1/%2", jaix_mirror_dir(root_dir), jaix_path_slashes(rel_path)));
}

// ---------------------------------------------------------------------------
// Driver litter: identification and cleanup
// ---------------------------------------------------------------------------

// The literal marker prefix; a driver line starts with it at column 0. The
// CLI writes the marker as the driver's identification line —
// "// jaix transpile driver：JAIX_TRANSPILE_PROTOCOL=…" — right after the
// imports/#load/#run preamble (the first line is "#import \"Basic\";" and
// the marker sits within the first ~400 bytes), so the match scans lines
// inside a bounded head window — a partial read, never the whole file.
JAIX_DRIVER_MARKER :: "// jaix transpile driver";

// Head window in bytes the litter check inspects.
DRIVER_HEAD_SCAN_LIMIT :: 1024;

// Content-based litter identification (not name-based, and unconditional —
// legacy pre-dot-prefix hash-named litter is caught too). An unreadable
// file is not litter: the real diagnostic stays with the consumer.
is_jaix_driver_litter :: (path: string) -> bool {
    f, open_ok := file_open(path);
    if !open_ok return false;
    defer file_close(*f);
    buffer: [DRIVER_HEAD_SCAN_LIMIT] u8;
    read_ok, count := file_read(f, buffer.data, DRIVER_HEAD_SCAN_LIMIT);
    if !read_ok return false;
    head: string;
    head.data = buffer.data;
    head.count = count;
    rest := head;
    while true {
        found, line, tail := split_from_left(rest, #char "\n");
        // CRLF tolerance: a trailing carriage return stays out of the match.
        if line.count > 0 && line[line.count-1] == #char "\r" line.count -= 1;
        if starts_with(line, JAIX_DRIVER_MARKER) return true;
        if !found break;
        rest = tail;
    }
    return false;
}

// Remove stale driver files from the package root (the files older tools
// left there: one per transpile call, hash-named or dot-prefixed). Every
// removed path joins the drop set — the test file collection already ran,
// so a collected litter file must not reach the test program. A failed
// delete fails the stage (the file would otherwise be scanned as a source).
clean_jaix_driver_litter :: (ctx: *Lifecycle_Context) -> bool {
    stage := cast(*Prestep_Stage) ctx.prestep;
    root_dir := jaix_path_slashes(stage.root_dir);
    names: [..] string;
    visited := visit_files(root_dir, false, *names, jaix_root_file_visitor,
        visit_files = true, visit_directories = false,
        visit_symlinks = false, follow_directory_symlinks = false);
    if !visited return true;   // an unreadable root fails loudly in the scan below
    // Deterministic order (the file system's enumeration is not): the drop
    // rows and the report lines keep the lexical order the scans use.
    jaix_sort_names(names);
    for name: names {
        if !ends_with(name, ".jai") continue;
        path := jaix_path_slashes(tprint("%1/%2", root_dir, name));
        if !is_jaix_driver_litter(path) continue;
        if !file_delete(path) {
            return jaix_prestep_failure(ctx, tprint("Could not remove the stale jaix driver: %", path));
        }
        print("[juice] Removed stale jaix driver: %\n", name);
        if !prestep_add_drop(ctx, name) return false;
    }
    return true;
}

// The root-level name collector (visit_files with recursive=false visits the
// immediate entries only).
jaix_root_file_visitor :: (info: *File_Visit_Info, names: *[..] string) {
    if info.is_directory return;
    array_add(names, copy_string(info.short_name));
}

// Insertion sort over the collected root names (lexicographic; the cleanup
// order and the drop rows become deterministic).
jaix_sort_names :: (names: [] string) {
    for i: 1..names.count-1 {
        if i >= names.count break;
        key := names[i];
        j := i - 1;
        while j >= 0 && compare(names[j], key) > 0 {
            names[j+1] = names[j];
            j -= 1;
        }
        names[j+1] = key;
    }
}

// ---------------------------------------------------------------------------
// The plugin's path helpers (path_safety is tool-internal, not published)
// ---------------------------------------------------------------------------

// "/"-separated copy of a path (the mirror and record paths stay stable on
// Windows).
jaix_path_slashes :: (path: string) -> string {
    result := copy_string(path);
    for i: 0..result.count-1 {
        if result[i] == #char "\\" result[i] = #char "/";
    }
    return result;
}

// Path equality: slash-normalized, and case-insensitive on Windows (the
// filesystem's own comparison).
jaix_paths_equal :: (left: string, right: string) -> bool {
    a := jaix_path_slashes(left);
    b := jaix_path_slashes(right);
    #if OS == .WINDOWS {
        return equal_nocase(a, b);
    } else {
        return a == b;
    }
}

// Absoluteness: a leading separator or any volume designator (including
// C:foo — not portable).
jaix_path_is_absolute :: (path: string) -> bool {
    if path == "" return false;
    if path[0] == #char "/" || path[0] == #char "\\" return true;
    for i: 0..path.count-1 {
        if path[i] == #char ":" return true;
    }
    return false;
}

// Regular-file existence (a directory or a link is not a config file).
jaix_regular_file_exists :: (path: string) -> bool {
    return file_exists(path) && !is_directory(path);
}

// The directory part of a walk entry without the trailing separator
// (path_strip_filename keeps it; the walk roots and dir names do not).
jaix_entry_parent :: (full_name: string) -> string {
    parent := path_strip_filename(full_name);
    while parent.count > 0 && (parent[parent.count - 1] == #char "/" || parent[parent.count - 1] == #char "\\") parent.count -= 1;
    return parent;
}

// Package-relative path of a scanned absolute path: everything after the
// package root prefix, "/" separated.
jaix_rel_path :: (absolute: string, root: string) -> string {
    rel := jaix_path_slashes(absolute);
    prefix := jaix_path_slashes(root);
    if prefix.count > 0 && prefix[prefix.count - 1] == #char "/" prefix.count -= 1;
    if rel.count > prefix.count return slice(rel, prefix.count + 1, rel.count - prefix.count - 1);
    return rel;
}

// Windows junction / reparse-point detection (visit_files surfaces junctions
// as plain directories). Non-Windows: false — symlinks are the only link
// form and visit_files already flags them.
jaix_is_reparse_point :: (path: string) -> bool {
    #if OS == .WINDOWS {
        attributes := GetFileAttributesW(utf8_to_wide(path,, temp));
        if attributes == INVALID_FILE_ATTRIBUTES return false;
        return (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
    }
    return false;
}
