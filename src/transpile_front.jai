// ---------------------------------------------------------------------------
// Strip front: the test-free shared module for closure probing, view
// computation and the production transpile step.
//
// Three consumers:
// - bootstrap build.jai reuses it via #load (a metaprogram compile unit
//   cannot contain test blocks, so every #load target must be test-free —
//   this file's tests live in tests/transpile_front_tests.jai, following the
//   tests/transpile_tests.jai precedent and the test organization rule);
// - the Build command and the dependency strip front reuse it via the
//   program-level #load (main.jai load order: transpile.jai ->
//   transpile_cache.jai -> this file, symmetric to build.jai's #load order).
//
// Two adapters over the same real seam: the view landing and entry handling
// are parameterized by Strip_View_Layout — CONTENT_ADDRESSED (runtime:
// content-addressed + cache-hit-skip writing, the entry lands on disk) and
// PLAIN (bootstrap: <base>/<rel> always written, the entry view is kept in
// memory for add_build_string, with the constant +5 line offset). The error
// prefix is injected per consumer (error_prefix).
// ---------------------------------------------------------------------------

#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

// Normalize path separators to forward slashes. A self-contained local
// implementation: bootstrap #loads this module and cannot depend on the
// runtime code in path_safety/manifest (same semantics as path_safety.jai's
// path_slashes; bootstrap's own local copy was deleted with the strip front
// consolidation).
front_slashes :: (path: string) -> string {
    result := copy_string(path);
    for i: 0..result.count-1 {
        if result[i] == #char "\\" result[i] = #char "/";
    }
    return result;
}

// One build source file: package-relative path ("/" separated) and absolute
// path, mirroring the test command's Test_Source_File. A dependency closure
// file's rel_path is relative to the dependency package root (views land
// under deps/<name>/..., the path itself stays dependency-relative).
// Originally lived in dependency.jai; moved here with the strip front.
Build_Source_File :: struct {
    rel_path: string;
    abs_path: string;
}

// One probed closure file: its resolved in-package literal #load targets in
// statement order, and whether it contains test blocks.
Build_Closure_File :: struct {
    file:      Build_Source_File;
    loads:     [..] string;
    has_tests: bool;
}

// The transpile step's output for one file: the strip-mode view, the
// content-addressed cache key, and transpile diagnostics (rejected with the
// original file coordinates).
Build_File_Output :: struct {
    view:        string;
    key:         string;
    diagnostics: [..] Transpile_Diagnostic;
}

probe_visited :: (visited: [] string, rel_path: string) -> bool {
    for seen: visited {
        if seen == rel_path return true;
    }
    return false;
}

// Probe one package's closure: DFS from the entry over literal in-package
// #load edges, with `package_root` as the resolution boundary. Non-literal
// and out-of-package targets are not followed. Files are listed in DFS
// preorder — the entry first, then each load target's subtree in statement
// order. The consumer package's build closure (build.jai's
// probe_build_closure), dependency closures (dependency.jai's dependency
// strip front) and the bootstrap closure (build.jai) share this probe.
// error_prefix is injected by the consumer (bootstrap uses
// "[Build System] ❌ ").
probe_package_closure :: (package_root: string, entry_rel: string, error_prefix: string = "[juice ERROR] ") -> [..] Build_Closure_File, bool {
    entry: Build_Source_File;
    entry.rel_path = entry_rel;
    entry.abs_path = front_slashes(tprint("%1/%2", package_root, entry_rel));

    files: [..] Build_Closure_File;
    visited: [..] string;
    stack: [..] Build_Source_File;
    array_add(*stack, entry);

    while stack.count > 0 {
        file := stack[stack.count - 1];
        stack.count -= 1;
        if probe_visited(visited, file.rel_path) continue;
        array_add(*visited, copy_string(file.rel_path));

        source, ok := read_entire_file(file.abs_path);
        if !ok {
            print("%1无法读取源文件: %2\n", error_prefix, file.abs_path);
            return files, false;
        }

        cf: Build_Closure_File;
        cf.file = file;
        cf.has_tests = source_has_test_block(source);
        cf.loads = source_load_targets(source, file.rel_path);
        array_add(*files, cf);

        // Push in reverse so targets pop in statement order.
        i := cf.loads.count;
        while i > 0 {
            i -= 1;
            target: Build_Source_File;
            target.rel_path = cf.loads[i];
            target.abs_path = front_slashes(tprint("%1/%2", package_root, cf.loads[i]));
            array_add(*stack, target);
        }
    }
    return files, true;
}

// The shared all-or-nothing closure decision: any file containing a test
// block views the whole closure. The bootstrap front, the Build command
// front and the dependency strip front all converge on this one scan.
closure_has_tests :: (closure: [] Build_Closure_File) -> bool {
    for file: closure {
        if file.has_tests return true;
    }
    return false;
}

// The content-addressed cache's skip-existing check. A self-contained local
// implementation: bootstrap #loads this module and cannot depend on the
// runtime code in path_safety.jai (its path_exists_as_regular_file has the
// same semantics via inspect_path_entry — exists and is a regular file means
// skip the write). The target directory is constrained to be a real
// directory, not a symlink (CONTEXT.md); a symlink on a view path is a
// same-level corner outside that existing defense. The PLAIN layout never
// runs this check (always writes).
front_view_exists :: (path: string) -> bool {
    return file_exists(path) && !is_directory(path);
}

// The two view-landing and entry-handling layouts (two adapters, one real
// seam):
// - CONTENT_ADDRESSED: runtime — content-addressed view paths
//   (transpile_cache.jai's transpile_view_path /
//   transpile_dependency_view_path), cache hits skip the write;
// - PLAIN: bootstrap — <transpile_dir>/<rel> always written, no cache. The
//   entry now lands on disk like every other file (bootstrap switched to
//   "generate + child process": the generated metaprogram compiles the entry
//   view via add_build_file, with exact file+line diagnostics — the
//   add_build_string +5 offset and the "entry into memory" branch are
//   retired).
Strip_View_Layout :: enum {
    CONTENT_ADDRESSED;
    PLAIN;
}

// Shared state of one closure's view computation: per-file states (0 =
// uncomputed, 1 = computing, 2 = done) and the resulting view paths.
// "Computing" re-entry means the literal in-package #load graph has a
// cycle and the path rewrites cannot be resolved.
// dep_name non-empty marks a dependency closure: views land under
// deps/<dep_name>/ instead of the tree root. Formerly Build_View_State
// (dependency.jai); generalized and moved here.
Strip_View_State :: struct {
    closure:       [] Build_Closure_File;
    transpile:     #type (file: Build_Source_File, load_targets: [] Load_Target) -> Build_File_Output;
    transpile_dir: string;   // CONTENT_ADDRESSED: transpile tree root; PLAIN: view base dir (absolute)
    dep_name:      string;   // CONTENT_ADDRESSED non-empty -> deps/<name> subtree
    layout:        Strip_View_Layout;
    error_prefix:  string = "[juice ERROR] ";
    states:        [..] s64;
    view_paths:    [..] string;
    failed:        bool;
}

closure_index :: (state: *Strip_View_State, rel_path: string) -> (s64, bool) {
    for i: 0..state.closure.count-1 {
        if state.closure[i].file.rel_path == rel_path return i, true;
    }
    return -1, false;
}

// Compute one closure file's strip view in dependency order (children
// first, Merkle chain) and write it per the state's layout. Returns the
// absolute view path. Both layouts land the entry on disk (the PLAIN
// "entry into memory" branch retired with add_build_string).
view_of_file :: (state: *Strip_View_State, index: s64) -> string, bool {
    if state.failed return "", false;
    if state.states[index] == 2 return state.view_paths[index], true;
    if state.states[index] == 1 {
        print("%1%2: 循环加载无法重写路径\n", state.error_prefix, state.closure[index].file.rel_path);
        state.failed = true;
        return "", false;
    }
    state.states[index] = 1;

    // Children first: every in-package load target is in the closure by
    // construction, so its view path exists before the parent's key embeds
    // it in a load rewrite.
    load_targets: [..] Load_Target;
    for resolved: state.closure[index].loads {
        child_index, found := closure_index(state, resolved);
        if !found {
            print("%1%2: in-package #load 缺少视图目标\n", state.error_prefix, state.closure[index].file.rel_path);
            state.failed = true;
            return "", false;
        }
        child_path, ok := view_of_file(state, child_index);
        if !ok return "", false;
        target: Load_Target;
        target.from = resolved;
        target.to = child_path;
        array_add(*load_targets, target);
    }

    output := state.transpile(state.closure[index].file, load_targets);
    if output.diagnostics.count > 0 {
        for diagnostic: output.diagnostics {
            print("%1%2:%3,%4: %5\n", state.error_prefix, state.closure[index].file.rel_path, diagnostic.line, diagnostic.column, diagnostic.message);
        }
        state.failed = true;
        return "", false;
    }

    rel := state.closure[index].file.rel_path;
    view_path := ifx state.layout == .CONTENT_ADDRESSED
        then ifx state.dep_name == ""
            then transpile_view_path(state.transpile_dir, output.key, rel)
            else transpile_dependency_view_path(state.transpile_dir, output.key, state.dep_name, rel)
        else tprint("%1/%2", front_slashes(state.transpile_dir), rel);

    // The parent must exist before the existence check: the inspection
    // scans the parent directory, and a missing parent would make
    // visit_files log a spurious "Unable to open directory" error.
    if !make_directory_if_it_does_not_exist(path_strip_filename(view_path), recursive = true) {
        print("%1无法创建视图目录: %2\n", state.error_prefix, rel);
        state.failed = true;
        return "", false;
    }
    if state.layout == .PLAIN || !front_view_exists(view_path) {
        if !write_entire_file(view_path, output.view) {
            print("%1无法写入视图: %2\n", state.error_prefix, rel);
            state.failed = true;
            return "", false;
        }
    }

    state.view_paths[index] = copy_string(view_path);
    state.states[index] = 2;
    return view_path, true;
}

// The build transpile step's production default: read the file, strip test
// blocks, rewrite in-package #load targets to the given view paths, and
// derive the content-addressed cache key (path + source + mode + version +
// load targets). The load rewrite table embeds the target views' hash
// directories, so keys form a Merkle chain computable in dependency order.
// Originally lived in commands/build.jai; moved here so bootstrap and the
// Build command share one production step.
transpile_build_file :: (file: Build_Source_File, load_targets: [] Load_Target) -> Build_File_Output {
    output: Build_File_Output;
    source, ok := read_entire_file(file.abs_path);
    if !ok {
        array_add(*output.diagnostics, .{line = 0, column = 0, message = tprint("无法读取源文件: %1", file.abs_path)});
        return output;
    }
    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = file.rel_path;
    ctx.load_targets = load_targets;
    result := transpile_source(source, ctx);
    output.view = result.view;
    output.key = transpile_view_key(file.rel_path, source, .STRIP, load_targets, JUICE_VERSION);
    output.diagnostics = result.diagnostics;
    return output;
}

// ---------------------------------------------------------------------------
// The Testing module STRIP special case (the mirror of the Test-side special
// case; consolidated here so bootstrap and the Build command share one copy,
// where before each held a symmetric duplicate with the same path and
// sentinel): the module source file cannot be compiled by jai directly once
// test blocks are inlined, so any build that resolves `#import "Testing"`
// must resolve to a test-free STRIP view. This function rewrites
// <package_root>/target/testing-module/Testing.jai before every compile (a
// session product, same path as the test command's compile view — test
// writes EXPAND, build/bootstrap write STRIP, each rewritten before its own
// run). A test-free, missing or unreadable module returns "": the
// metaprogram output stays byte-identical to the pre-special-case shape,
// zero change. module_source is supplied by the consumer: bootstrap passes a
// cwd-relative "modules/Testing.jai", the Build command passes the absolute
// path derived from juice_modules_dir() (bootstrap cannot reference the
// runtime code in path_safety).
// ---------------------------------------------------------------------------
testing_module_strip_view_dir :: (package_root: string, module_source: string, error_prefix: string = "[juice ERROR] ") -> string {
    module_abs := front_slashes(module_source);
    if !front_view_exists(module_abs) return "";
    source, ok := read_entire_file(module_abs);
    if !ok return "";
    if !source_has_test_block(source) return "";

    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = "modules/Testing.jai";
    result := transpile_source(source, ctx);
    if result.diagnostics.count > 0 {
        for diagnostic: result.diagnostics {
            print("%1%2:%3,%4: %5\n", error_prefix, ctx.path, diagnostic.line, diagnostic.column, diagnostic.message);
        }
        return "";
    }

    dir := front_slashes(tprint("%1/target/testing-module", package_root));
    if !make_directory_if_it_does_not_exist(dir, recursive = true) {
        print("%1无法创建视图目录: %2\n", error_prefix, dir);
        return "";
    }
    view := tprint("%1/Testing.jai", dir);
    if !write_entire_file(view, result.view) {
        print("%1无法写入视图: %2\n", error_prefix, view);
        return "";
    }
    return dir;
}
