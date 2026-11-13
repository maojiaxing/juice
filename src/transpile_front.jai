// ---------------------------------------------------------------------------
// Strip front (ticket 026): the test-free shared module for closure probing,
// view computation and the production transpile step (old juice
// src/transpile_front.jai semantics — the reference face, rewritten not
// copied). Three surfaces:
// - probe_package_closure: the closure DFS from an entry over literal
//   in-package #load edges (pipeline_load_edges), with the per-file probe
//   aggregation (pipeline_has_anchors) feeding the all-or-nothing viewing
//   decision (closure_has_tests);
// - Strip_View_State + view_of_file: one closure's view computation in
//   dependency order (children first — the Merkle chain), landing views per
//   the layout: CONTENT_ADDRESSED (content-addressed paths + cache-hit-skip
//   writing) or PLAIN (<base>/<rel> always written, no cache — the bootstrap
//   strategy);
// - transpile_build_file: the production per-file step (read, STRIP
//   transpile, content-addressed key) and testing_module_strip_view_dir: the
//   Testing module STRIP special case.
//
// Dependency closures land under deps/<name>/ (Strip_View_State.dep_name
// non-empty), so distinct dependencies can never collide — the dependency
// tests-neither-discovered-nor-executed face (US 18): the closure's strip
// views carry no test blocks, and the outer shim rewrite (the dependency
// strip front's shim-to-entry-view rewrite) is the 027 b5 wiring over this
// library surface. The error prefix is injected per consumer (error_prefix).
//
// This module is a bootstrap #load target and must stay test-free; its unit
// tests live in tests/transpile_front_tests.jai (0053 rule). main.jai stays
// untouched — the first production consumers are the command wiring tickets
// (027/028).
// ---------------------------------------------------------------------------

#import "Basic";
#import "File";
#import "File_Utilities";

// Normalize path separators to forward slashes. A self-contained local
// implementation: the bootstrap #loads this module and cannot depend on the
// runtime code in path_safety/manifest (same semantics as path_safety.jai's
// path_slashes).
front_slashes :: (path: string) -> string {
    result := copy_string(path);
    for i: 0..result.count-1 {
        if result[i] == #char "\\" result[i] = #char "/";
    }
    return result;
}

// One build source file: package-relative path ("/" separated) and absolute
// path, mirroring the test command's Scan_File. A dependency closure
// file's rel_path is relative to the dependency package root (views land
// under deps/<name>/..., the path itself stays dependency-relative).
Build_Source_File :: struct {
    rel_path: string;
    abs_path: string;
}

// One probed closure file: its resolved in-package literal #load targets in
// statement order, and whether it contains test blocks (the pipeline's
// anchor aggregation).
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
// order. The consumer package's build closure and the dependency strip
// front share this probe (ticket 027 wires both). error_prefix is injected
// by the consumer; pipeline is the configured pipeline the probe aggregates
// over — an empty pipeline means the default, so every existing caller
// keeps its behavior unchanged.
probe_package_closure :: (package_root: string, entry_rel: string, error_prefix: string = "[juice ERROR] ", pipeline: [] Transpile_Plugin = .[]) -> [..] Build_Closure_File, bool {
    entry: Build_Source_File;
    entry.rel_path = entry_rel;
    entry.abs_path = front_slashes(tprint("%1/%2", package_root, entry_rel));

    resolved := resolve_pipeline(pipeline);

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
        // Probe aggregation: the closure decisions ask the pipeline's plugin
        // hooks instead of hardcoding the two transforms (the configured
        // pipeline for a declared package, the default registry otherwise).
        cf.has_tests = pipeline_has_anchors(resolved, source, file.rel_path);
        cf.loads = pipeline_load_edges(resolved, source, file.rel_path);
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
// block views the whole closure; a test-free closure compiles its sources
// verbatim (zero transpile). The build command front and the dependency
// strip front converge on this one scan.
closure_has_tests :: (closure: [] Build_Closure_File) -> bool {
    for file: closure {
        if file.has_tests return true;
    }
    return false;
}

// The content-addressed cache's skip-existing check. A self-contained local
// implementation: the bootstrap #loads this module and cannot depend on the
// runtime code in path_safety.jai (its path_exists_as_regular_file has the
// same semantics via inspect_path_entry — exists and is a regular file means
// skip the write). The PLAIN layout never runs this check (always writes).
front_view_exists :: (path: string) -> bool {
    return file_exists(path) && !is_directory(path);
}

// The two view-landing and entry-handling layouts (two adapters, one real
// seam):
// - CONTENT_ADDRESSED: runtime — content-addressed view paths
//   (transpile_cache.jai's transpile_view_path /
//   transpile_dependency_view_path), cache hits skip the write;
// - PLAIN: bootstrap — <base>/<rel> always written, no cache (the generated
//   metaprogram compiles the entry view via add_build_file with exact
//   file+line diagnostics).
Strip_View_Layout :: enum {
    CONTENT_ADDRESSED;
    PLAIN;
}

// Shared state of one closure's view computation: per-file states (0 =
// uncomputed, 1 = computing, 2 = done) and the resulting view paths.
// "Computing" re-entry means the literal in-package #load graph has a
// cycle and the path rewrites cannot be resolved.
// dep_name non-empty marks a dependency closure: views land under
// deps/<dep_name>/ instead of the tree root.
Strip_View_State :: struct {
    closure:       [] Build_Closure_File;
    // The transpile seam: a function from one closure file (+ its load
    // rewrite table) to the strip view. The third parameter is the pipeline
    // (empty = the default); view_of_file passes state.pipeline below.
    transpile:     #type (file: Build_Source_File, load_targets: [] Load_Target, pipeline: [] Transpile_Plugin = .[]) -> Build_File_Output;
    // The pipeline the closure is transpiled with: the caller's configured
    // pipeline for a declared package; empty (the default) for closures
    // without a package declaration surface.
    pipeline:      [] Transpile_Plugin;
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
// absolute view path. Both layouts land the entry on disk.
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

    output := state.transpile(state.closure[index].file, load_targets, state.pipeline);
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
// pipeline description + load targets — the pipeline is the context's
// registry, so the key always reflects the pipeline that produced the
// view). The load rewrite table embeds the target views' hash directories,
// so keys form a Merkle chain computable in dependency order. pipeline is
// the configured pipeline; an empty pipeline means the default.
transpile_build_file :: (file: Build_Source_File, load_targets: [] Load_Target, pipeline: [] Transpile_Plugin = .[]) -> Build_File_Output {
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
    // ctx.plugins is a resizable array; copy the slice in so the context
    // owns its pipeline view.
    for plugin: pipeline array_add(*ctx.plugins, plugin);
    result := transpile_source(source, ctx);
    output.view = result.view;
    output.key = transpile_view_key(file.rel_path, source, .STRIP, load_targets, VIEW_CONTRACT_VERSION, ctx.plugins);
    output.diagnostics = result.diagnostics;
    return output;
}

// ---------------------------------------------------------------------------
// The Testing module STRIP special case (the mirror of the Test-side special
// case): the module source file cannot be compiled by jai directly once
// test blocks are inlined, so any build that resolves `#import "Testing"`
// must resolve to a test-free STRIP view. This function rewrites
// <package_root>/target/transpile/testing-module/Testing.jai before every
// compile (a session product, same path as the test command's compile view —
// test writes EXPAND, build writes STRIP, each rewritten before its own run).
// A test-free, missing or unreadable module returns "": the consumer's
// output stays byte-identical to the pre-special-case shape, zero change.
// module_source is supplied by the consumer (an absolute path — the
// bootstrap cannot reference the runtime code in path_safety).
// ---------------------------------------------------------------------------
testing_module_strip_view_dir :: (package_root: string, module_source: string, error_prefix: string = "[juice ERROR] ") -> string {
    module_abs := front_slashes(module_source);
    if !front_view_exists(module_abs) return "";
    source, ok := read_entire_file(module_abs);
    if !ok return "";
    if !pipeline_has_anchors(default_transpile_pipeline(), source, "modules/Testing.jai") return "";

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

    dir := target_testing_module_dir(package_target_dir(package_root));
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
