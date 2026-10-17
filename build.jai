#import "Basic";
#import "String";
#import "File";
#import "Compiler";
#import "Process";

// Bootstrap transpile front (ADR 0006): the metaprogram #loads the test-free
// shared modules — src/transpile_front.jai (closure probing, view computation
// and the production transpile step; PLAIN layout: <base>/<rel> always
// written, the whole closure including the entry lands on disk) and
// src/metaprogram.jai (the shared Metaprogram generator plus the
// bootstrap options assembly pure function; this file generates
// the compile metaprogram and then spawns a child jai to compile — the same
// shape as the Build command; the entry view compiles via add_build_file
// with exact file+line diagnostics; the add_build_string +5 offset is
// retired). src/transpile_plugin.jai provides the registry-driven pipeline
// (plugin interface, the two built-in plugins, the transpile_source runner,
// the probe aggregation). src/transpile_cache.jai provides the
// content-addressed path functions the shared front references. The #loaded
// code compiles into the metaprogram execution environment and never into
// the built program. Known and harmless: compiling transpile.jai /
// transpile_plugin.jai under beta 0.2.009 emits two `%%` print
// compatibility warnings (do not "fix" them; keep the transpiler
// untouched).
#load "src/transpile.jai";
#load "src/transpile_plugin.jai";
#load "src/transpile_cache.jai";
#load "src/transpile_front.jai";
#load "src/metaprogram.jai";

// Strip front (the probe semantics, the shared machinery, the entry
// landing): probe the entry (src/main.jai) over its transitive closure of
// literal in-package #loads. A test-free closure returns the original
// file's absolute path (zero transpile, zero landing, compiled as-is); a
// closure containing test blocks is viewed all-or-nothing — the whole
// closure's views including the entry land in target/transpile/bootstrap/
// (the bootstrap-exclusive subdirectory under the target directory's
// transpile subtree; never mixed with the Build command's content-addressed
// cache) and the entry view path is returned; in-package #loads are
// rewritten to view absolute paths (the existing STRIP mechanism, no new
// transpile rules). Shares the same transpiler and view contract with the
// Build command; the line-fidelity invariant is identical (ADR 0005).
bootstrap_build_entry :: (entry_rel: string) -> string, bool {
    root := front_slashes(get_working_directory());
    closure, ok := probe_package_closure(root, entry_rel, "[Build System] ❌ ");
    if !ok return "", false;
    if !closure_has_tests(closure) return tprint("%1/%2", root, entry_rel), true;

    state: Strip_View_State;
    state.closure = closure;
    state.transpile = transpile_build_file;
    state.transpile_dir = tprint("%1/target/transpile/bootstrap", root);
    state.layout = .PLAIN;
    state.error_prefix = "[Build System] ❌ ";
    for _: closure {
        array_add(*state.states, 0);
        array_add(*state.view_paths, "");
    }
    entry_index, found := closure_index(*state, entry_rel);
    if !found {
        print("[Build System] ❌ 入口不在闭包中: %1\n", entry_rel);
        return "", false;
    }
    entry_path, view_ok := view_of_file(*state, entry_index);
    return entry_path, view_ok;
}

#run {
    // -------------------------------------------------------------
    // 1. Read the command-line arguments
    // -------------------------------------------------------------
    build_args := get_toplevel_command_line();

    // When `juice test` loads this file into the test program as a view (the
    // test program's compile entry is the generated
    // target/transpile/first.jai), skip the build: compile-time execution
    // would drag the whole build tree into the test program compile. A
    // direct `jai build.jai` ends with this file itself as the last
    // argument.
    if build_args.count > 0 {
        last_arg := build_args[build_args.count - 1];
        if ends_with(last_arg, "/first.jai") || ends_with(last_arg, "\\first.jai") return;
    }

    is_release := false;
    for arg: build_args {
        if arg == "release" || arg == "-release" {
            is_release = true;
        } else if arg == "debug" || arg == "-debug" {
            is_release = false;
        }
    }

    root := front_slashes(get_working_directory());

    // -------------------------------------------------------------
    // 2. Declare the build self-handled by this metaprogram: jai falls back
    //    to Default_Metaprogram compiling the command-line file itself when
    //    #run created no workspace (build.jai has no main -> "No program
    //    entry point" error, exit code 1). Creating an empty workspace is
    //    the "this metaprogram handles the build" signal — the real compile
    //    happens in step 5's child jai.
    // -------------------------------------------------------------
    set_build_options_dc(.{do_output = false});
    delegation := compiler_create_workspace("Bootstrap Delegation");
    if !delegation return;

    // -------------------------------------------------------------
    // 3. Strip front: probe the entry closure and choose the compile entry
    //    (the original file or the entry view).
    // -------------------------------------------------------------
    entry, ok := bootstrap_build_entry("src/main.jai");
    if !ok return;

    // -------------------------------------------------------------
    // 4. The Testing module bootstrap special case (the mirror of the
    //    test-side special case; consolidated: the implementation lives in
    //    the shared strip front testing_module_strip_view_dir, one copy for
    //    bootstrap and the Build command; here we only pass a cwd-relative
    //    module path and the error prefix):
    //    modules/Testing.jai cannot be compiled by jai directly once test
    //    blocks are inlined, and `#import "Testing"` inside the closure
    //    would resolve to the module source file. When the module contains
    //    test blocks, its STRIP view is written to
    //    target/testing-module/Testing.jai and its directory is prepended to
    //    the generated metaprogram's import path. When the module is
    //    test-free or absent, testing_view_dir stays "", zero change.
    //    The sentinel convention: testing_view_dir == "" means "the
    //    compile-view special case is disabled" — the same convention as the
    //    shared Metaprogram generator's testing_view_dir parameter and the
    //    shared testing_module_strip_view_dir's return value.
    // -------------------------------------------------------------
    testing_view_dir := testing_module_strip_view_dir(root, "modules/Testing.jai", "[Build System] ❌ ");

    // -------------------------------------------------------------
    // 5. Generate the compile metaprogram (sharing the Metaprogram generator
    //    with the Build command) and spawn a child jai to compile. The
    //    options assembly is the shared generator's pure function
    //    (bootstrap_compiler_metaprogram_options): output_path and
    //    intermediate_path derive from the root as absolute paths — the
    //    generated metaprogram's child jai switches its #run working
    //    directory to the metaprogram's own directory (target/), so a
    //    relative "target" would resolve one layer deeper into
    //    target/target/ (058 deviation ④, fixed here). The child's output
    //    passes through in real time (this metaprogram's prints are
    //    collected by jai and flushed only on normal exit — so the 🚀/✅
    //    lines appear after the compile output; the failure path's exit(1)
    //    swallows this metaprogram's ❌ lines, but the exit code and the
    //    child's error output stay intact). Failures propagate the exit
    //    code with exit(1), keeping the three-path seam.
    // -------------------------------------------------------------
    meta := bootstrap_compiler_metaprogram_options(root, entry, testing_view_dir, is_release);

    // Key: make sure the target directory exists so the linker does not
    // error with LNK1104
    make_directory_if_it_does_not_exist("target");
    meta_path := "target/bootstrap-meta.jai";
    if !write_entire_file(meta_path, generate_compiler_metaprogram(meta)) {
        print("[Build System] ❌ 无法写入构建 metaprogram: %1\n", meta_path);
        exit(1);
    }

    if is_release {
        print("[Build System] 🚀 Building in RELEASE mode (Very Optimized)...\n");
    } else {
        print("[Build System] 🛠️  Building in DEBUG mode...\n");
    }
    result := run_command("jai", meta_path);
    if result.exit_code != 0 {
        print("[Build System] ❌ Build failed.\n");
        exit(1);
    }

    mode_str := ifx is_release then "Release" else "Debug";
    print("[Build System] ✅ %1 build succeeded! Binary -> target/juice.exe\n", mode_str);
}
