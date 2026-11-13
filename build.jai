#import "Basic";
#import "String";
#import "File";
#import "File_Utilities";
#import "Compiler";
#import "Process";

// ---------------------------------------------------------------------------
// Bootstrap build metaprogram (spec section 10 stage 2, ADR 0006 shape —
// the old juice build.jai reference, semantically equivalent rewrite not a
// copy): `jai build.jai` and `jai build.jai - release` build the otter root
// with no juice involvement.
//
// Entry-file anchoring (the ticket 031 Jai fact): the metaprogram's #run
// resolves get_working_directory() and every relative path against this
// file's own directory, not the invocation cwd — jai anchors the compile to
// the entry file. This build.jai therefore always builds the otter root
// (its package), whatever directory jai was invoked from; that is the
// product semantics (self-bootstrap), and it is why the bootstrap E2E in
// tests/bootstrap_tests.jai runs the self-build rather than a scratch
// fixture. The same anchoring makes the generated metaprogram's child jai
// switch its #run working directory to target/build/ (the metaprogram's own
// directory) — so every path the generated text quotes must be absolute
// (the 058 deviation ④ discipline, shared with the Build command).
//
// The stage-2 #load closure contract (005 US 24): every file below must
// stay test-free — their tests live in tests/ (the test organization rule).
// Adding a module here means bootstrap and the Build command share it, so
// both paths take on the change; update this list deliberately.
//   src/transpile.jai        — lexer, edits, string helpers, the canonical
//                              quote pair (ticket 022's face);
//   src/transpile_plugin.jai — the plugin interface, the two built-in
//                              plugins, the transpile_source runner, the
//                              probe aggregation;
//   src/transpile_cache.jai  — the content-addressed path functions the
//                              shared front references;
//   src/transpile_front.jai  — closure probing, Strip_View_State/view
//                              computation (the PLAIN layout lands every
//                              view, entry included), the production
//                              transpile step, the Testing module STRIP
//                              special case;
//   src/metaprogram.jai      — the compiler metaprogram generator plus the
//                              bootstrap options assembly
//                              (bootstrap_compiler_metaprogram_options) and
//                              the version assertion driver generator
//                              (generate_version_assertion_driver, ticket
//                              032);
//   src/publication.jai      — the publication transforms (the three module
//                              artifact generators, the constant-line
//                              extraction, the landing path helpers — the
//                              fourth, verbatim discovery-source artifact's
//                              landing paths included since ticket 037; the
//                              ticket 032 publish step's face).
//   src/target_layout.jai    — the target layout (the zone roots and landing
//                              paths the commands, the bootstrap and the
//                              tests share; no Juice dependency).
// The #loaded code compiles into the metaprogram execution environment and
// never into the built program. The order is the old juice bootstrap order
// (front_slashes/quote_jai_string resolve across the shared scope).
#load "src/transpile.jai";
#load "src/transpile_plugin.jai";
#load "src/transpile_cache.jai";
#load "src/transpile_front.jai";
#load "src/target_layout.jai";
#load "src/metaprogram.jai";
#load "src/publication.jai";

// ---------------------------------------------------------------------------
// Strip front (the probe semantics, the shared machinery, the entry
// landing): probe the entry (src/main.jai) over its transitive closure of
// literal in-package #loads. A test-free closure returns the original
// file's absolute path (zero transpile, zero landing, compiled as-is); a
// closure containing test blocks is viewed all-or-nothing — the whole
// closure's views including the entry land in target/transpile/bootstrap/
// (the bootstrap-exclusive subdirectory under the target directory's
// transpile subtree; never mixed with the Build command's content-addressed
// cache — the PLAIN layout always writes, no cache hits) and the entry view
// path is returned; in-package #loads are rewritten to view absolute paths
// (the existing STRIP mechanism, no new transpile rules). Shares the same
// transpiler and view contract with the Build command; the line-fidelity
// invariant is identical (ADR 0005).
//
// The otter root's entry closure is test-free after the self-test migration
// to tests/, so its bootstrap compiles the original sources. The bootstrap
// regression fixtures exercise the inline-test STRIP path explicitly.
// ---------------------------------------------------------------------------
bootstrap_build_entry :: (entry_rel: string) -> string, bool {
    root := front_slashes(get_working_directory());
    closure, ok := probe_package_closure(root, entry_rel, "[Build System] ❌ ");
    if !ok return "", false;
    if !closure_has_tests(closure) return tprint("%1/%2", root, entry_rel), true;

    state: Strip_View_State;
    state.closure = closure;
    state.transpile = transpile_build_file;
    state.transpile_dir = tprint("%1/bootstrap", target_transpile_dir(package_target_dir(root)));
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

    // Test-program guard: the otter test command's driver #loads every
    // collected file, so this build metaprogram is part of the test
    // program (the guard is live, not defensive). The test program's
    // compile entry is target/transpile/test_runner.jai (the shared
    // TEST_RUNNER_FILE_NAME in src/metaprogram.jai — this file #loads that
    // module, and the test program loads both); running the build inside
    // that compile would drag the whole build tree into it (and this
    // metaprogram would create a second workspace mid-compile). The suffix
    // check below skips the build for that entry (old juice's test program
    // used the same entry shape under the name first.jai).
    if build_args.count > 0 {
        last_arg := build_args[build_args.count - 1];
        runner_suffix := tprint("/%1", TEST_RUNNER_FILE_NAME);
        runner_backslash_suffix := tprint("\\%1", TEST_RUNNER_FILE_NAME);
        if ends_with(last_arg, runner_suffix) || ends_with(last_arg, runner_backslash_suffix) return;
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
    //    happens in step 7's child jai.
    // -------------------------------------------------------------
    set_build_options_dc(.{do_output = false});
    delegation := compiler_create_workspace("Bootstrap Delegation");
    if !delegation {
        // Practically unreachable; failing loudly beats a silent no-op
        // (the print would be swallowed by exit(1), so there is none).
        exit(1);
    }

    // -------------------------------------------------------------
    // 3. The publication step (005 decision 4: publish before compile):
    //    read the definition source and land the module artifacts under
    //    target/modules — Juice/module.jai (the Package compatibility
    //    directory module), Testing.jai (the prefix-stripped flat module,
    //    self-tests excluded) and juice_core.jai (the generated
    //    plugin face). Ticket 037 adds the fourth, non-module-face artifact:
    //    modules/juice_internal/test_discovery.jai, a verbatim copy of
    //    src/test_discovery.jai that the generated test metaprogram #loads
    //    by absolute path (the running executable carries every source it
    //    needs to run tests — the installed-layout contract). Ticket 049
    //    adds the plugin face closure copies: the four JUICE_CORE_LOAD_FILES
    //    sources land verbatim under modules/juice_internal/plugin_face/, so
    //    the generated juice_core's module-relative #load lines resolve in
    //    any relocated modules/ tree (no build-machine path is published).
    //    The same list drives the generated #load lines and these copies —
    //    there is no second file list. Every build regenerates the whole set
    //    (never edit — the published juice_core header says so). All six
    //    sources are read before anything is written, so a missing or
    //    unreadable source fails the publish step with exit 1 before a
    //    partial set can land (006 decision 5; 048 decisions 3/7). Then the
    //    bootstrap window's flat Juice.jai seed retires: a stale copy must
    //    not coexist with the directory module (no flat/directory ambiguity
    //    at the modules dir, 005 US 14) — the deletion runs right here so
    //    nothing later in this build can resolve the retired face. Any
    //    failure exits 1 (the swallowed-print fact as in the probe step).
    // -------------------------------------------------------------
    target_dir := package_target_dir(root);
    modules_dir := target_modules_dir(target_dir);
    module_source, module_read_ok := read_entire_file(tprint("%1/src/module.jai", root));
    if !module_read_ok {
        print("[Build System] ❌ 无法读取定义源 src/module.jai（发布步骤）\n");
        exit(1);
    }
    discovery_source, discovery_read_ok := read_entire_file(tprint("%1/src/test_discovery.jai", root));
    if !discovery_read_ok {
        print("[Build System] ❌ 无法读取发现面源 src/test_discovery.jai（发布步骤）\n");
        exit(1);
    }
    closure_sources: [..] string;
    for file: JUICE_CORE_LOAD_FILES {
        closure_source, closure_read_ok := read_entire_file(tprint("%1/src/%2", root, file));
        if !closure_read_ok {
            print("[Build System] ❌ 无法读取插件面闭包源 src/%1（发布步骤）\n", file);
            exit(1);
        }
        array_add(*closure_sources, closure_source);
    }
    juice_text, juice_ok := publish_juice_module(module_source);
    if !juice_ok {
        print("[Build System] ❌ 发布 Juice 模块失败（段标记契约破坏）\n");
        exit(1);
    }
    testing_text, testing_ok := publish_testing_module(module_source);
    if !testing_ok {
        print("[Build System] ❌ 发布 Testing 模块失败（段标记契约破坏）\n");
        exit(1);
    }
    core_text, core_ok := publish_juice_core(module_source);
    if !core_ok {
        print("[Build System] ❌ 发布 juice_core 模块失败（内置 id 常量缺失）\n");
        exit(1);
    }
    if !make_directory_if_it_does_not_exist(juice_module_dir(target_dir), recursive = true) {
        print("[Build System] ❌ 无法创建发布目录 %1\n", juice_module_dir(target_dir));
        exit(1);
    }
    if !make_directory_if_it_does_not_exist(juice_internal_dir(modules_dir), recursive = true) {
        print("[Build System] ❌ 无法创建发布目录 %1\n", juice_internal_dir(modules_dir));
        exit(1);
    }
    if !make_directory_if_it_does_not_exist(juice_plugin_face_dir(modules_dir), recursive = true) {
        print("[Build System] ❌ 无法创建发布目录 %1\n", juice_plugin_face_dir(modules_dir));
        exit(1);
    }
    if !write_entire_file(juice_module_path(target_dir), juice_text) {
        print("[Build System] ❌ 无法写入 %1\n", juice_module_path(target_dir));
        exit(1);
    }
    if !write_entire_file(testing_module_path(target_dir), testing_text) {
        print("[Build System] ❌ 无法写入 %1\n", testing_module_path(target_dir));
        exit(1);
    }
    if !write_entire_file(juice_core_module_path(target_dir), core_text) {
        print("[Build System] ❌ 无法写入 %1\n", juice_core_module_path(target_dir));
        exit(1);
    }
    if !write_entire_file(test_discovery_module_path(modules_dir), discovery_source) {
        print("[Build System] ❌ 无法写入 %1\n", test_discovery_module_path(modules_dir));
        exit(1);
    }
    for file, index: JUICE_CORE_LOAD_FILES {
        face_path := juice_plugin_face_file_path(modules_dir, file);
        if !write_entire_file(face_path, closure_sources[index]) {
            print("[Build System] ❌ 无法写入 %1\n", face_path);
            exit(1);
        }
    }
    flat_seed := tprint("%1/modules/Juice.jai", target_dir);
    if file_exists(flat_seed) {
        if !file_delete(flat_seed) {
            print("[Build System] ❌ 无法退役平铺 Juice.jai 种子 %1\n", flat_seed);
            exit(1);
        }
    }

    // -------------------------------------------------------------
    // 4. The compile-time version assertion (005 decision 9): a generated
    //    evaluator child — the manifest evaluator's driver shape (ticket
    //    007: #load the manifest, #run main(), do_output false) — #loads
    //    package.jai and compares PACKAGE.version against JUICE_VERSION,
    //    the constant declaration line extracted verbatim from
    //    src/commands/version.jai (the single source, the published
    //    juice_core discipline — the version command cannot read the
    //    manifest, so drift must fail the build). The driver's comparison
    //    is a compile-time #assert carrying the failure message: a drift
    //    fails the child's compile (jai prints the message with file:line
    //    on stderr and exits nonzero — a runtime print would be swallowed
    //    by the failure path's exit, the pinned Jai fact), and the nonzero
    //    exit propagates here as exit(1). The child resolves
    //    `#import "Juice"` through -import_dir target/modules — the face
    //    step 3 just published, so the assertion also proves the published
    //    Juice module compiles. A missing JUICE_VERSION declaration line
    //    fails the same way.
    // -------------------------------------------------------------
    version_source, version_read_ok := read_entire_file("src/commands/version.jai");
    if !version_read_ok {
        print("[Build System] ❌ 无法读取 src/commands/version.jai（版本断言）\n");
        exit(1);
    }
    juice_version_line, version_line_ok := extract_constant_line(version_source, "JUICE_VERSION");
    if !version_line_ok {
        print("[Build System] ❌ 未找到 JUICE_VERSION 常量声明（版本断言）\n");
        exit(1);
    }
    build_dir := target_build_dir(target_dir);
    if !make_directory_if_it_does_not_exist(build_dir, recursive = true) {
        print("[Build System] ❌ 无法创建构建驱动目录 %1\n", build_dir);
        exit(1);
    }
    version_check_path := target_session_driver_path(build_dir, "bootstrap-version-check.jai");
    if !write_entire_file(version_check_path, generate_version_assertion_driver(tprint("%1/package.jai", root), juice_version_line)) {
        print("[Build System] ❌ 无法写入版本断言 driver: %1\n", version_check_path);
        exit(1);
    }
    version_result := run_command("jai", version_check_path, "-import_dir", target_modules_dir(target_dir), "-quiet");
    if version_result.exit_code != 0 {
        print("[Build System] ❌ Version assertion failed.\n");
        exit(1);
    }

    // -------------------------------------------------------------
    // 5. Strip front: probe the entry closure and choose the compile entry
    //    (the original file or the entry view). A probe or view failure
    //    exits 1 (deviation from the old juice shape's exit 0 — CI must see
    //    failures, 005 US 8). The collected error prints are swallowed by
    //    exit(1) (the pinned Jai fact): the pre-child failure modes are
    //    narrow — unreadable sources, transpile structural diagnostics,
    //    #load cycles — and the exit code carries the signal; compile-time
    //    errors in the sources themselves flow through the child below
    //    with full output.
    // -------------------------------------------------------------
    entry, ok := bootstrap_build_entry("src/main.jai");
    if !ok exit(1);

    // -------------------------------------------------------------
    // 6. The Testing module bootstrap special case (the mirror of the
    //    test-side special case; consolidated: the implementation lives in
    //    the shared strip front testing_module_strip_view_dir, one copy for
    //    bootstrap and the Build command; here we only pass the module
    //    source and the error prefix):
    //    target/modules/Testing.jai cannot be compiled by jai directly once
    //    test blocks are inlined, and `#import "Testing"` inside the closure
    //    would resolve to the module source file. When the module contains
    //    test blocks, its STRIP view is written to
    //    target/transpile/testing-module/Testing.jai and its directory is
    //    prepended to the generated metaprogram's import path. When the
    //    module is test-free or absent, testing_view_dir stays "", zero
    //    change.
    //    The sentinel convention: testing_view_dir == "" means "the
    //    compile-view special case is disabled" — the same convention as the
    //    shared Metaprogram generator's testing_view_dir parameter and the
    //    shared testing_module_strip_view_dir's return value.
    //
    //    The module source is the PUBLISHED face (target/modules/
    //    Testing.jai — the step 3 product). Publication cuts its self-tests,
    //    so the current consumer face compiles directly and the special
    //    case stays disabled. The shared helper still handles sources with
    //    inline test blocks. A missing module degrades to "" (zero change)
    //    — but step 3 just wrote it, so that is a defensive branch only.
    // -------------------------------------------------------------
    testing_view_dir := testing_module_strip_view_dir(root, testing_module_path(target_dir), "[Build System] ❌ ");

    // -------------------------------------------------------------
    // 7. Generate the compile metaprogram (sharing the Metaprogram generator
    //    with the Build command) and spawn a child jai to compile. The
    //    options assembly is the shared generator's pure function
    //    (bootstrap_compiler_metaprogram_options): output_path is the
    //    artifact root and intermediate_path is target/build/, both absolute —
    //    the generated metaprogram's child jai switches its #run working
    //    directory to the metaprogram's own directory (target/build/), so a
    //    relative "target" would resolve one layer deeper into
    //    target/build/target/ (058 deviation ④, fixed here). The child's
    //    output passes through in real time (this metaprogram's prints are
    //    collected by jai and flushed only on normal exit — so the 🚀/✅
    //    lines appear after the compile output; the failure path's exit(1)
    //    swallows this metaprogram's ❌ lines, but the exit code and the
    //    child's error output stay intact). Failures propagate the exit
    //    code with exit(1), keeping the failure-seam contract.
    //
    //    LNK1104 posture (005 decision 10): no running-artifact hand-off
    //    here — the bootstrap assumes the artifact is not running (first
    //    build); a running target/juice.exe makes the child's linker fail
    //    loudly. The self-built exe's own Build command carries the
    //    hand-off (ticket 011).
    // -------------------------------------------------------------
    meta := bootstrap_compiler_metaprogram_options(root, entry, testing_view_dir, is_release);

    // Key: make sure the target build directory exists so the linker does
    // not error with LNK1104
    make_directory_if_it_does_not_exist(build_dir);
    meta_path := target_session_driver_path(build_dir, "bootstrap-meta.jai");
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
