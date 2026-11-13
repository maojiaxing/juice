#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";
#import "System";

#if OS == .WINDOWS {
    #import "Windows";
    #import "Windows_Utf8";

    // winerror.h value; Windows.jai does not export it.
    ERROR_SHARING_VIOLATION :: 32;
}

// The build command (spec section 4.6, the old juice commands/build.jai
// semantics): b1 argument guard -> b2 workspace preparation (the command-side
// one-stop entry, idempotent) -> plugin preparation (ticket 060: the shared
// command-level prepare — the declaration-driven member scan validates every
// declared member plugin id, lands the member import shims and writes the
// workspace registration file; the declaration resolver produces the in-process
// transpile pipeline and hook table; a declared member hooks plugin runs
// through the generated PRESTEP-only host, ticket 060) -> b3 zero-plan short
// circuit -> b4 whole-input revalidation -> b5 dependency strip front (ticket
// 027's wiring over ticket 026's view layer: shims of test-bearing dependency
// closures are rewritten to their entry strip views under
// target/transpile/deps/) -> b6 PRESTEP (ticket 057: the pre-step plugin stage
// — the host's returned effects and the in-process before hooks fill the
// source substitution table and drop set, after hooks observe; no built-in
// implementation, undeclared = no-op) -> b7 per-plan entry selection (a
// substituted entry compiles the replacement path directly, a dropped entry
// fails; otherwise a test-free closure compiles the original source and a
// closure containing test blocks is viewed all-or-nothing in STRIP and the
// entry becomes the entry file's view) -> b8 per-plan compile (generated
// metaprogram + spawned jai + artifact check).
// The LNK1104 face (002 decision 13): a running artifact cannot be
// overwritten by the linker, so the build hands off to a copy inside target/.
//
// The PRESTEP, TRANSPILE and COMPILE stages dispatch through the lifecycle
// hook table (spec §6, the 004 decision 17 representative subset extended by
// ticket 057): before hooks run first, a mounted at hook replaces the stage's
// built-in implementation (no mount = the built-in runs — the empty hook set
// is the default pipeline; PRESTEP has no built-in implementation and never
// dispatches at), after hooks run last, all in registration order; any hook
// failure (false or an ERROR diagnostic) fails the stage, the command and the
// exit code (HANDLER_FAILED through the dispatcher). The LNK1104
// is_running/handoff faces stay plain seams — they are not lifecycle stages.
//
// The Package face is consumed through the namespaced Juice binding
// (src/juice_module.jai), as in the workspace/target layers.

BUILD_COMMAND :: Command.{
    name          = "build",
    description   = "Build all targets in the root package",
    usage         = "juice build",
    prerequisites = string.[],
    handler       = build_command,
};

build_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if !command_arguments_are_valid(BUILD_COMMAND, arguments) return false;
    prepared := ensure_workspace_prepared(ctx.root_dir, ctx.cache_dir, *ctx.workspace);
    if prepared == null return false;
    if !build_prepared_workspace(prepared) return false;
    if prepared.artifact_plans.count == 0 {
        if prepared.package_type == .LIB {
            print("[juice] Library package '%'; nothing to build.\n", prepared.discovery.root_package.name);
        } else {
            print("[juice] No executable targets; nothing to build.\n");
        }
    }
    print("[juice] Build completed successfully!\n");
    return true;
}

// Revalidate the whole build input before compiling anything, so an unsafe
// plan cannot produce a partial build. Plan structure and paths are owned by
// this gate; compile_artifact_plan pre-checks only its own source file.
revalidate_build_plans :: (prepared: *Juice.Prepared_Workspace) -> bool {
    package_root := prepared.discovery.root_dir;
    root_entry := inspect_path_entry(package_root);
    if !root_entry.exists || !root_entry.is_directory || root_entry.is_symlink || root_entry.is_junction {
        print("[juice ERROR] Package root changed or is unsafe before build.\n");
        return false;
    }

    for plan: prepared.artifact_plans {
        if !revalidate_artifact_plan(plan, package_root) {
            print("[juice ERROR] Artifact path became unsafe before build: %\n", plan.artifact_path);
            return false;
        }
        source_entry := inspect_path_entry(plan.target.source_path);
        if !source_entry.exists || source_entry.is_directory || source_entry.is_symlink || source_entry.is_junction {
            print("[juice ERROR] Target source became unsafe before build: %\n", plan.target.source_path);
            return false;
        }
    }
    return true;
}

// ---------------------------------------------------------------------------
// Lifecycle stage dispatch (spec §6.3, the 004 decision 17 representative
// subset): the build's TRANSPILE and COMPILE mounts. The stage state
// travels through the lifecycle context's observable-state slots
// (views/artifact_paths); the at hook reads and writes it. A mounted at
// hook owns the stage's implementation and its outputs; with no mount the
// built-in implementation runs — the production default.
// ---------------------------------------------------------------------------

// The TRANSPILE stage state: the input is the prepared workspace plus the
// resolved transpile pipeline (the declaration-driven resolution — one
// resolution per command, ticket 056; build_plan_entry no longer resolves)
// and the PRESTEP stage's tables (ticket 057: the entry selection consumes
// them); the output is one chosen compile entry per plan (same order — the
// compile loop pairs entries[index] with artifact_plans[index]). A mounted
// at hook fills entries itself; the built-in front fills it through b5/b7.
Build_Transpile_Stage :: struct {
    prepared: *Juice.Prepared_Workspace;
    pipeline: [] Transpile_Plugin;
    prestep:  *Prestep_Stage;   // PRESTEP's tables (null = no pre-step ran)
    entries:  [..] string;
}

// The TRANSPILE stage's built-in implementation: the b5 dependency strip
// front (shims of test-bearing dependency closures are rewritten to the
// entry strip views) then the b7 per-plan entry selection.
build_transpile_front :: (stage: *Build_Transpile_Stage) -> bool {
    prepared := stage.prepared;
    if !prepare_dependency_strip_views(prepared.discovery.root_dir) return false;
    for plan: prepared.artifact_plans {
        entry, ok := build_plan_entry(prepared, plan, stage.pipeline, stage.prestep);
        if !ok return false;
        array_add(*stage.entries, entry);
    }
    return true;
}

// The COMPILE stage state: the prepared workspace and the TRANSPILE stage's
// chosen entries.
Build_Compile_Stage :: struct {
    prepared: *Juice.Prepared_Workspace;
    entries:  [] string;
}

// The COMPILE stage's built-in implementation: the b8 fail-fast per-plan
// compile loop. The compile step is an internal test seam (the built-in
// implementation's own injection point — NOT a lifecycle mount: the COMPILE
// at hook replaces this whole loop). The default is the three-parameter
// adapter: compile_artifact_plan itself carries a fourth internal spawn
// seam (011 deviation 4), and a #type parameter's arity must match exactly.
build_compile_loop :: (
    stage: *Build_Compile_Stage,
    compile: #type (root_dir: string, plan: Juice.Artifact_Plan, entry: string) -> bool = compile_artifact_default
) -> bool {
    prepared := stage.prepared;
    for plan, index: prepared.artifact_plans {
        if !compile(prepared.discovery.root_dir, plan, stage.entries[index]) return false;
    }
    return true;
}

// Decide one plan's compile entry (b7, the old juice build_plan_entry
// semantics plus ticket 057's PRESTEP consumption): the pre-step's tables
// apply to the entry first — a substituted entry compiles the replacement's
// absolute path directly (the replacement is already the compile-ready
// source: no closure probe, no strip views, no cache) and a dropped entry
// fails the build with a diagnostic. An untouched entry probes its literal
// in-package #load closure through the resolved pipeline (declaration order =
// pipeline order; the resolver already supplied the face default for an
// undeclared package). A test-free closure compiles the original entry
// unchanged (zero transpile, zero cache); a closure containing test blocks is
// viewed all-or-nothing and the entry becomes the entry file's strip view.
// (Strip_View_State / closure_index / view_of_file live in
// src/transpile_front.jai.) The replacement is trusted as-is: the compile
// step's own source check catches a missing replacement.
build_plan_entry :: (
    prepared: *Juice.Prepared_Workspace,
    plan: Juice.Artifact_Plan,
    pipeline: [] Transpile_Plugin,
    prestep: *Prestep_Stage = null
) -> (string, bool) {
    entry_rel := path_slashes(plan.target.main_file);
    if prestep_is_dropped(prestep, entry_rel) {
        print("[juice ERROR] The pre-step dropped the build entry: %\n", entry_rel);
        return "", false;
    }
    replacement, substituted := prestep_substitution_for(prestep, entry_rel);
    if substituted {
        return path_slashes(replacement), true;
    }

    closure, ok := probe_package_closure(prepared.discovery.root_dir, entry_rel, pipeline = pipeline);
    if !ok return "", false;
    if !closure_has_tests(closure) return path_slashes(plan.target.source_path), true;

    state: Strip_View_State;
    state.transpile_dir = transpile_tree_dir(prepared.discovery.root_dir);
    state.layout = .CONTENT_ADDRESSED;
    state.closure = closure;
    state.transpile = transpile_build_file;
    state.pipeline = pipeline;
    for _: closure {
        array_add(*state.states, 0);
        array_add(*state.view_paths, "");
    }
    entry_index, found := closure_index(*state, entry_rel);
    if !found return "", false;
    entry_path, view_ok := view_of_file(*state, entry_index);
    return entry_path, view_ok;
}

// Production spawn of the compile child: jai compiles the generated
// metaprogram. The child inherits the caller's working directory (the
// package root — juice never chdirs); the metaprogram itself quotes only
// absolute paths, so jai's own #run cwd switch (to the metaprogram's
// directory) changes nothing.
spawn_build_compiler :: (metaprogram_path: string) -> Process_Result {
    return run_command("jai", metaprogram_path);
}

compile_artifact_plan :: (root_dir: string, plan: Juice.Artifact_Plan, entry: string,
                          spawn: #type (metaprogram_path: string) -> Process_Result = spawn_build_compiler) -> bool {
    // The compile entry is chosen by the entry selection (b7): the original
    // entry file (test-free closure, zero transpile) or its strip view.
    source_file := path_slashes(entry);
    if !path_exists_as_regular_file(source_file) {
        print("[juice ERROR] Target source file not found: %\n", source_file);
        return false;
    }

    if !make_directory_if_it_does_not_exist(plan.target_dir, recursive = true) {
        print("[juice ERROR] Could not create target directory: %\n", plan.target_dir);
        return false;
    }
    if !make_directory_if_it_does_not_exist(target_build_dir(plan.target_dir), recursive = true) {
        print("[juice ERROR] Could not create the build driver directory: %\n", target_build_dir(plan.target_dir));
        return false;
    }

    print("[juice Build] Compiling Target '%' (%) -> target/...\n", plan.target.name, plan.target.main_file);

    // The Testing module import root: the published Testing.jai is test-free
    // (the definition source's self-tests are cut at publication), so the
    // modules directory itself is the import path — no strip view, no special
    // case. The directory is prepended so `#import "Testing"` resolves to the
    // published face.
    testing_dir := juice_modules_dir();

    // The compile runs through a generated metaprogram (session product in
    // target/build/, like the bootstrap and test drivers): jai has no flag
    // for Build_Options.intermediate_path, so the metaprogram sets it to
    // target/build — compiler intermediates (.obj, .lib, .exp, .pdb,
    // .added_strings_*) land there instead of the artifact root, and Clean
    // removes them with target/.
    metaprogram_path := target_session_driver_path(target_build_dir(plan.target_dir), tprint("build-%1.jai", plan.target.name));
    options: Compiler_Metaprogram_Options;
    options.workspace_name    = "Juice Build";
    options.executable_name   = plan.target.name;
    options.output_path       = path_slashes(plan.target_dir);
    options.intermediate_path = path_slashes(target_build_dir(plan.target_dir));
    options.pdb_path          = path_slashes(tprint("%1/%2.pdb", target_build_dir(plan.target_dir), plan.target.name));
    options.import_dirs       = compiler_import_directories(packages_dir(root_dir));
    options.build_file        = source_file;
    options.testing_view_dir  = testing_dir;
    if !write_entire_file(metaprogram_path, generate_compiler_metaprogram(options)) {
        print("[juice ERROR] Could not write build metaprogram: %\n", metaprogram_path);
        return false;
    }

    result := spawn(metaprogram_path);
    if result.exit_code != 0 {
        print("[juice ERROR] Compilation failed for target '%'.\n", plan.target.name);
        return false;
    }

    if !file_exists(plan.artifact_path) {
        print("[juice ERROR] Compiler did not produce expected artifact: %\n", plan.artifact_path);
        return false;
    }
    return true;
}

// The LNK1104 face (002 decision 13, spec section 10 stage 1): Windows
// cannot overwrite a running executable — the image section holds the file
// without write sharing, so the linker fails with LNK1104. The probe mirrors
// the linker's own open: write access with no sharing. A running image makes
// that open fail with ERROR_SHARING_VIOLATION; other failures (a read-only
// artifact, access denied) are not "running". A missing artifact is not
// running. POSIX binaries are never locked by their image.
artifact_is_running :: (artifact_path: string) -> bool {
    if !file_exists(artifact_path) return false;
    #if OS == .WINDOWS {
        wide_path, wide_ok, _ := utf8_to_wide(path_slashes(artifact_path));
        if !wide_ok return false;
        handle := CreateFileW(wide_path, GENERIC_WRITE, share_mode = 0, creation = OPEN_EXISTING);
        if handle != INVALID_HANDLE_VALUE {
            CloseHandle(handle);
            return false;
        }
        return cast(u32) GetLastError() == ERROR_SHARING_VIOLATION;
    } else {
        return false;
    }
}

// The copy's path: the artifact name with a -build suffix inside the same
// target/ directory. The copy must stay in target/ so the modules
// derivation (spec section 9.3: modules live next to the running
// executable) keeps working for it.
handoff_copy_path :: (plan: Juice.Artifact_Plan) -> string {
    return target_handoff_copy_path(plan.target_dir, plan.target.name);
}

// Hand the build to a copy of the running artifact: copy it to
// <name>-build.exe, spawn the copy with this process's command line, and
// exit immediately. The original must be gone before the copy's compile
// opens the artifact (the running image holds the file without write
// sharing — LNK1104), so the copy is the build runner from here on; its own
// detection finds the artifact free and compiles normally. A running copy
// cannot delete itself, so the finished copy is removed by the next
// hand-off (at most one lingers between builds) and by clean (the whole
// target/). The exit code of the original is 0 — the copy's result reaches
// the user through its own output.
running_artifact_handoff :: (plan: Juice.Artifact_Plan) -> bool {
    copy_path := handoff_copy_path(plan);

    if file_exists(copy_path) {
        #if OS == .WINDOWS {
            wide_path, wide_ok, _ := utf8_to_wide(copy_path);
            if !wide_ok || !DeleteFileW(wide_path) {
                print("[juice ERROR] Could not remove the previous hand-off copy: %\n", copy_path);
                return false;
            }
        } else {
            if run_command("rm", "-f", copy_path).exit_code != 0 {
                print("[juice ERROR] Could not remove the previous hand-off copy: %\n", copy_path);
                return false;
            }
        }
    }

    if !copy_file(plan.artifact_path, copy_path) {
        print("[juice ERROR] Could not copy the running target: %\n", plan.artifact_path);
        return false;
    }

    print("[juice Build] Target '%' is running; rebuilding through a copy in target/...\n", plan.target.name);

    args := get_command_line_arguments();
    // cmd /c start /b launches the copy in the same console and returns
    // immediately (run_command is blocking — waiting here would keep the
    // original's image lock alive through the copy's compile).
    spawn_args: [..] string;
    array_add(*spawn_args, "cmd");
    array_add(*spawn_args, "/c");
    array_add(*spawn_args, "start");
    array_add(*spawn_args, "/b");
    array_add(*spawn_args, "");
    array_add(*spawn_args, copy_path);
    for i: 1..args.count-1 array_add(*spawn_args, args[i]);
    run_command(..spawn_args);
    exit(0);
    return true; // Unreachable: exit above ends the process.
}

// The internal compile seam's production default (the 011 deviation 4
// shape): the three-parameter adapter over the full compile step, whose
// own spawn seam is the direct-testing surface for the metaprogram write,
// the failure branches and the artifact check.
compile_artifact_default :: (root_dir: string, plan: Juice.Artifact_Plan, entry: string) -> bool {
    return compile_artifact_plan(root_dir, plan, entry);
}

// The build orchestration over a prepared workspace. The PRESTEP, TRANSPILE
// and COMPILE stages dispatch through the lifecycle hook table — the
// declaration-resolved table (ticket 056) followed by the caller's hooks
// (the 004 decision 17 representative subset — the seams' #type parameters
// became the hook-set data parameter): before hooks run first, a mounted at
// hook replaces the stage's built-in implementation (no mount = the built-in
// runs — the empty hook set is the default pipeline; PRESTEP has no built-in
// implementation and never dispatches at), after hooks run last, all in
// registration order (forward — 021). Any hook failure (false or an ERROR
// diagnostic) fails the stage and aborts the build (HANDLER_FAILED through
// the dispatcher). The at replacement's identity enters the pipeline
// description through the pipeline the hook passes to transpile_view_key —
// changing the implementation changes the view keys (documented semantics;
// the built-in front's keys always carry the built-in pipeline description,
// so replaced and built-in views never share a key unless the hook reuses
// the built-in step verbatim, which would be the same implementation).
//
// is_running and handoff stay the LNK1104 face's seams (not lifecycle
// stages): the production probe cannot be made to report "running" on
// demand (a real image lock needs a real running process — stage 2's
// self-build covers it naturally), so the decision logic is tested through
// recording fakes.
build_prepared_workspace :: (
    prepared: *Juice.Prepared_Workspace,
    hook_table: [] Hook_Registration = .[],
    is_running: #type (artifact_path: string) -> bool = artifact_is_running,
    handoff: #type (plan: Juice.Artifact_Plan) -> bool = running_artifact_handoff,
    host_spawn: #type (host_path: string, import_dirs: [] string) -> Process_Result = spawn_plugin_host
) -> bool {
    // Command-level plugin preparation (ticket 060, spec §5.2): the shared
    // prepare is the only scan / member shim / registration landing point —
    // the declaration-driven workspace scan validates every declared member
    // plugin id, lands the member import shims and writes
    // target/plugins/registration.jai when a member plugin is declared. The
    // declaration resolver produces the static transpile pipeline and hook
    // table (the command process holds built-in values only; member values
    // are validated where they exist — the test metaprogram / the PRESTEP
    // host). Zero declarations cost nothing (no I/O).
    plugin_prepare := prepare_workspace_plugins(prepared);
    report_plugin_prepare(plugin_prepare);
    if !plugin_prepare.ok return false;
    resolved := resolve_package_plugins(prepared.discovery.root_package.plugins);
    if !resolved.ok {
        for diagnostic: resolved.diagnostics print("[juice ERROR] %\n", diagnostic.message);
        print("[juice ERROR] Invalid plugin declarations.\n");
        return false;
    }

    // Empty target sets are an intentional no-op: do not prepare
    // dependencies and do not dispatch any stage, so no hook fires — the
    // PRESTEP stage included (ticket 057: zero plan short-circuits before
    // the pre-step). (The plugin preparation above is declaration-only and
    // may still land member import shims for declared plugins.)
    if prepared.artifact_plans.count == 0 return true;
    if !revalidate_build_plans(prepared) return false;

    // The LNK1104 face: check every plan's artifact before compiling
    // anything. A running artifact hands the whole build to a copy (the
    // copy re-runs the build from scratch, so no partial compile must have
    // happened) — the hand-off happens before any stage dispatch, so no
    // hook fires on the hand-off path (the PRESTEP stage included).
    for plan: prepared.artifact_plans {
        if is_running(plan.artifact_path) return handoff(plan);
    }

    // The lifecycle host state: one context per build, one diagnostic sink
    // reused across the stages (each dispatch inspects only its own
    // additions), one plugin_state slot per hook registration (host-owned
    // storage; slots start as the resolver's options pointers for the
    // declared plugins, null for the caller's hooks — the 021 slot
    // protocol). The dispatch table is the declaration-resolved hook table
    // followed by the caller's hooks: the command process holds built-in
    // plugin values only (member values live in the PRESTEP host — tickets
    // 060/061), so only caller hooks can mount in-process.
    diags: [..] Lifecycle_Diagnostic;
    lctx: Lifecycle_Context;
    lctx.diagnostics = *diags;
    dispatch_table := merge_hook_tables(resolved.hook_table, hook_table);
    for opt: resolved.slot_options array_add(*lctx.plugin_state, opt);
    for _: hook_table array_add(*lctx.plugin_state, null);

    // PRESTEP stage (b6): no built-in implementation — the before hooks fill
    // the source substitution table and the drop set, the after hooks
    // observe (fail fast on either). The command fills the stage's root and
    // member directories first; with no declared hook plugins both mounts are
    // empty and both tables stay empty — the undeclared no-op, so the entry
    // selection below reads the original sources exactly as before.
    pstage: Prestep_Stage;
    pstage.root_dir = prepared.discovery.root_dir;
    for pkg, index: prepared.discovery.member_packages {
        if index == 0 continue;   // the root package itself
        array_add(*pstage.member_dirs, copy_string(pkg.dir));
    }
    lctx.prestep = *pstage;

    // PRESTEP host (tickets 060/061): member plugins' before hooks cannot run
    // in this process (their values are only compiled into the host program),
    // so a declared member plugin that may contribute hooks runs first through
    // the generated host driver. Its returned substitution/drop rows merge
    // into the same Prestep_Stage through the stage-level prestep_add_*
    // rules — the host's effects are the PRESTEP before-stage effects. A
    // table conflict with the caller's in-process hooks is a stage failure.
    if plugin_prepare.member_hooks && plugin_prepare.registration_path != "" {
        host_options := plugin_host_options(prepared, *pstage, "build");
        host_records, host_ok := run_plugin_host(host_options, host_spawn);
        if !host_ok return false;
        if !apply_plugin_host_effects(*pstage, host_records, lctx.diagnostics) return false;
    }

    if !run_mounted_hooks(dispatch_table, .PRESTEP, .before, *lctx) return false;
    if !run_mounted_hooks(dispatch_table, .PRESTEP, .after, *lctx) return false;

    // TRANSPILE stage (b5 + b7): before -> at (mounted hook replaces the
    // front) | built-in front -> after. The pre-step tables travel with the
    // stage into the entry selection.
    tstage: Build_Transpile_Stage;
    tstage.prepared = prepared;
    tstage.pipeline = resolved.pipeline;
    tstage.prestep = *pstage;
    lctx.views = *tstage;
    if !run_mounted_hooks(dispatch_table, .TRANSPILE, .before, *lctx) return false;
    if has_mounted_hook(dispatch_table, .TRANSPILE, .at) {
        if !run_mounted_hooks(dispatch_table, .TRANSPILE, .at, *lctx) return false;
    } else if !build_transpile_front(*tstage) {
        return false;
    }
    if !run_mounted_hooks(dispatch_table, .TRANSPILE, .after, *lctx) return false;

    // COMPILE stage (b8): before -> at | built-in loop -> after.
    cstage: Build_Compile_Stage;
    cstage.prepared = prepared;
    cstage.entries = tstage.entries;
    lctx.artifact_paths = *cstage;
    if !run_mounted_hooks(dispatch_table, .COMPILE, .before, *lctx) return false;
    if has_mounted_hook(dispatch_table, .COMPILE, .at) {
        if !run_mounted_hooks(dispatch_table, .COMPILE, .at, *lctx) return false;
    } else if !build_compile_loop(*cstage) {
        return false;
    }
    if !run_mounted_hooks(dispatch_table, .COMPILE, .after, *lctx) return false;
    return true;
}
