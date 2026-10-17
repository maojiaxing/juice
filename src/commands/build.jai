#import "Basic";
#import "Process";
#import "File";
#import "File_Utilities";
#import "String";
#import "Juice";
#import "Testing";

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

// compiler_import_directories (the modules + packages import paths) is owned
// by the dependency module (the packages_dir derivation holder); shared by
// build and test.

// Revalidate the whole build input before compiling anything, so an unsafe
// plan cannot produce a partial build. Plan structure and paths are owned by
// this gate; compile_artifact_plan pre-checks only its own source file.
revalidate_build_plans :: (prepared: *Prepared_Workspace) -> bool {
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

compile_artifact_plan :: (root_dir: string, plan: Artifact_Plan, entry: string) -> bool {
    // The compile entry is chosen by the transpile front: the original
    // entry file (test-free closure, zero transpile), its strip view, or —
    // with the jaix marker — the entry's mirror view under target/jaix/
    // (spec 055 decision 8: selected directly, no probe, no strip).
    source_file := to_forward_slashes(entry);
    if !path_exists_as_regular_file(source_file) {
        print("[juice ERROR] Target source file not found: %\n", source_file);
        return false;
    }

    if !make_directory_if_it_does_not_exist(plan.target_dir, recursive = true) {
        print("[juice ERROR] Could not create target directory: %\n", plan.target_dir);
        return false;
    }

    print("[juice Build] Compiling Target '%' (%) -> target/...\n", plan.target.name, plan.target.main_file);

    // The compile runs through a generated metaprogram (session product in
    // the target directory, like the test command's driver/metaprogram):
    // jai has no flag for Build_Options.intermediate_path, so the
    // metaprogram sets it to the target directory — compiler intermediates
    // (.obj, .lib, .added_strings_*) land there instead of a .build
    // directory next to the entry, and Clean removes them with target/.
    metaprogram_path := to_forward_slashes(tprint("%1/build-%2.jai", plan.target_dir, plan.target.name));
    testing_dir := testing_module_strip_view_dir(root_dir, tprint("%1/Testing.jai", juice_modules_dir()));
    metaprogram: Compiler_Metaprogram_Options;
    metaprogram.workspace_name    = "Juice Build";
    metaprogram.executable_name   = plan.target.name;
    metaprogram.output_path       = to_forward_slashes(plan.target_dir);
    metaprogram.intermediate_path = to_forward_slashes(plan.target_dir);
    metaprogram.import_dirs       = compiler_import_directories(packages_dir(root_dir));
    metaprogram.build_file        = source_file;
    metaprogram.testing_view_dir  = testing_dir;
    if !write_entire_file(metaprogram_path, generate_compiler_metaprogram(metaprogram)) {
        print("[juice ERROR] Could not write build metaprogram: %\n", metaprogram_path);
        return false;
    }

    result := run_command("jai", metaprogram_path);
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

// The compile runs through a metaprogram generated by the shared
// Metaprogram generator (src/metaprogram.jai): Build assembles the
// options here — executable output into the plan's target directory, the
// juice module directory and the dependency shim directory as import
// directories, and the (possibly viewed) entry as the build file.

// Build transpile front (ADR 0004): per target, probe the
// entry's closure of literal in-package #loads. A test-free closure compiles
// the original entry unchanged (zero transpile, zero cache); a closure
// containing test blocks is viewed wholesale — every closure file gets a
// strip view and the entry becomes the entry file's view. Non-literal and
// out-of-package #load targets are never viewed or rewritten; test blocks
// there surface as plain jai compile errors. Dependency closures enter
// through import shims and are viewed by the shared dependency strip front
// (dependency.jai) before this probe runs.
// ---------------------------------------------------------------------------

// The Testing module build special case: a build that resolves
// `#import "Testing"` must resolve to a test-free STRIP view.
// testing_module_strip_view_dir lives in src/transpile_front.jai (shared
// with bootstrap; the module source is supplied by the consumer); the Test
// EXPAND variant lives in test.jai.

// The build transpile seam's production default (transpile_build_file) and
// Build_Source_File / Build_Closure_File / Build_File_Output live in
// src/transpile_front.jai (the test-free shared strip front — bootstrap
// reuses the same production step via #load).

// Probe one target's closure: the entry's literal in-package #load closure
// within the package root. Dependency closures enter through import shims
// and are probed separately by the dependency strip front (dependency.jai).
// The probe aggregates over the root package's declared pipeline (spec 0060
// decision 6): a declared package's closure decisions follow its pipeline,
// an undeclared package resolves to the default (zero behavior change).
probe_build_closure :: (prepared: *Prepared_Workspace, plan: Artifact_Plan) -> [..] Build_Closure_File, bool {
    pipeline := resolve_transpile_pipeline(prepared.discovery.root_package.transpile.plugins);
    files, ok := probe_package_closure(prepared.discovery.root_dir, path_slashes(plan.target.main_file), pipeline = pipeline);
    return files, ok;
}

// Decide one plan's compile entry: probe the entry's closure; a test-free
// closure compiles the original entry unchanged, a closure containing test
// blocks is viewed all-or-nothing and the entry becomes the entry file's
// view. (Strip_View_State / closure_index / view_of_file live in
// src/transpile_front.jai.)
//
// The jaix pre-step marker selects the mirror entry view instead: the whole
// package was jaix-transpiled into target/jaix/ (package-relative
// structure), so the entry's literal #load chain resolves inside the mirror
// without rewrites — no probe, no strip views. The compile seam
// (compile_artifact_plan) is untouched; its own entry-file existence check
// reports a missing mirror view.
build_plan_entry :: (
    prepared: *Prepared_Workspace,
    plan: Artifact_Plan,
    transpile: #type (file: Build_Source_File, load_targets: [] Load_Target, pipeline: [] Transpile_Plugin = .[]) -> Build_File_Output
) -> (string, bool) {
    if prepared.discovery.root_package.jaix.config != "" {
        return jaix_mirror_view_path(prepared.discovery.root_dir, path_slashes(plan.target.main_file)), true;
    }

    closure, ok := probe_build_closure(prepared, plan);
    if !ok return "", false;
    if !closure_has_tests(closure) return to_forward_slashes(plan.target.source_path), true;

    state: Strip_View_State;
    state.transpile_dir = transpile_tree_dir(prepared.discovery.root_dir);
    state.layout = .CONTENT_ADDRESSED;
    state.closure = closure;
    state.transpile = transpile;
    // The root package's declared pipeline (spec 0060 decision 6):
    // declaration order = pipeline order; an undeclared package resolves
    // to the default inside the seam (empty pipeline), zero behavior
    // change.
    state.pipeline = resolve_transpile_pipeline(prepared.discovery.root_package.transpile.plugins);
    for _: closure {
        array_add(*state.states, 0);
        array_add(*state.view_paths, "");
    }
    entry_index, found := closure_index(*state, path_slashes(plan.target.main_file));
    if !found return "", false;
    entry_path, view_ok := view_of_file(*state, entry_index);
    return entry_path, view_ok;
}

// The compile seam mirrors run's launch and clean's validate/delete seams;
// the transpile front mirrors the test command's orchestration seam:
// production handlers use the defaults; tests cross
// the same interfaces with recording adapters instead of the real compiler.
// Build receives no paths itself — the root comes from prepared (the compile
// seam takes only root_dir; packages_dir and the Testing view directory
// derive from it). The prestep seam (run_jaix_prestep, src/jaix_front.jai)
// joins the same injectable family: the production handler runs the jaix
// pre-step; tests cross the interface with a recording fake.
build_prepared_workspace :: (
    prepared: *Prepared_Workspace,
    transpile: #type (file: Build_Source_File, load_targets: [] Load_Target, pipeline: [] Transpile_Plugin = .[]) -> Build_File_Output = transpile_build_file,
    compile: #type (root_dir: string, plan: Artifact_Plan, entry: string) -> bool = compile_artifact_plan,
    prestep: #type (prepared: *Prepared_Workspace, transpile: #type (exe: string, input: string, output: string, config: string) -> (exit_code: s64, stderr: string) = spawn_jaix_transpile) -> bool = run_jaix_prestep
) -> bool {
    // Empty target sets are an intentional no-op. In particular, do not
    // create target/ and do not prepare dependencies for such a package.
    if prepared.artifact_plans.count == 0 return true;
    if !revalidate_build_plans(prepared) return false;

    // Dependency strip front: dependency sources reachable through
    // import shims are probed and, when they contain test blocks, viewed with
    // the same all-or-nothing strip semantics; shims are rewritten to the
    // entry views. Test-free dependencies stay untouched. The jaix marker's
    // scope is the root package only (spec 055 decision 9), so dependencies
    // keep this path unchanged.
    if !prepare_dependency_strip_views(prepared.discovery.root_dir, transpile) return false;

    // jaix pre-step (spec 055 decision 8): the root package's jaix marker
    // enables the shared front — the whole package is scanned and
    // jaix-transpiled into the target/jaix/ mirror. The pre-step runs
    // before the entry loop so build_plan_entry can pick the mirror entry
    // view; a marker-absent package never reaches the front (zero behavior
    // change).
    if prepared.discovery.root_package.jaix.config != "" {
        if !prestep(prepared) return false;
    }

    // Transpile front: per plan, probe the entry's closure and choose
    // between the original entry and the entry file's strip view.
    entries: [..] string;
    for plan: prepared.artifact_plans {
        entry, ok := build_plan_entry(prepared, plan, transpile);
        if !ok return false;
        array_add(*entries, entry);
    }

    for plan, index: prepared.artifact_plans {
        if !compile(prepared.discovery.root_dir, plan, entries[index]) return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// Inline tests: the Build orchestration, the transpile front
// seam and probe, the real strip step, and the fixture package E2E child
// scenarios. Shared helpers (the test_compile_* record globals,
// fake_build_transpile and the other seam fakes, build_seam_* and
// run_juice_child and the other child scenario helpers) live in
// tests/test_support.jai.
// ---------------------------------------------------------------------------

test "Build without targets compiles nothing" {
    prepared: Prepared_Workspace;
    prepared.artifact_plans = Artifact_Plan.[];
    test_compile_count = 0;
    expect(build_prepared_workspace(*prepared, fake_build_transpile, test_compile_artifact) && test_compile_count == 0);
}

test "Unsafe package root blocks every compilation" {
    root := tprint("%1/missing-package-root", juice_root());
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", juice_root())}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/alpha.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    test_build_transpile_calls = 0;
    expect(!build_prepared_workspace(*prepared, fake_build_transpile, test_compile_artifact));
    expect(test_compile_count == 0 && test_build_transpile_calls == 0);
}

test "Escaping artifact plan blocks compilation" {
    root := juice_root();
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/../escape", root), artifact_path = tprint("%1/../escape/alpha.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    expect(!build_prepared_workspace(*prepared, fake_build_transpile, test_compile_artifact) && test_compile_count == 0);
}

// The repository's own entry closure contains inline test blocks (they live
// next to the implementation): the transpile front views every closure file
// and compilation receives the entry file's strip view — the fixture
// semantics flipped with the migration (it used to assert the test-free
// pass-through: zero transpile, the original entry compiled).
test "Build forwards each prepared plan to compilation" {
    root := juice_root();
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/alpha.exe", root)},
        .{target = .{name = "beta",  main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/beta.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    closure, ok := probe_build_closure(*prepared, plans[0]);
    expect(ok);
    test_compile_count = 0;
    test_compile_success = true;
    test_build_transpile_calls = 0;
    // This test asserts counts from the test_build_transpiled_* arrays: they
    // are reset explicitly like the scalars (an earlier implicit invariant
    // relied on the previous fake consumer having cleared them, which broke
    // when the discovery order changed; the explicit reset stays so the
    // bookkeeping never depends on discovery order).
    array_reset(*test_build_transpiled_files);
    array_reset(*test_build_transpiled_rewrites);
    expect(build_prepared_workspace(*prepared, fake_build_transpile, test_compile_artifact));
    expect(test_compile_count == 2);
    expect(test_compiled_driver_root == juice_root());
    // The entry closure contains test blocks: the transpile step ran once
    // per closure file and per plan (children first, the entry last).
    expect(test_build_transpile_calls == 2 * closure.count);
    expect(test_build_transpiled_files.count == 2 * closure.count);
    expect(test_build_transpiled_files[closure.count - 1] == "src/main.jai");
    // Compilation receives the entry file's (fake) strip view, not the
    // original source path.
    entry_view := tprint("%1/target/transpile/%2/src/main.jai", root, fake_key("src/main.jai"));
    expect(test_compiled_entry == entry_view);
    expect(file_exists(entry_view));
    expect(test_compiled_plan.target.name == "beta" && test_compiled_plan.artifact_path == tprint("%1/target/beta.exe", root));
}

// The final gate before the compiler: a plan with an empty target name must
// never reach compile_artifact_plan (which would pass "-exe ''" through).
test "Build rejects a plan with an empty target name" {
    root := juice_root();
    plans := Artifact_Plan.[
        .{target = .{name = "", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    expect(!build_prepared_workspace(*prepared, fake_build_transpile, test_compile_artifact) && test_compile_count == 0);
}

test "Build fails fast on a compile failure" {
    root := juice_root();
    plans := Artifact_Plan.[
        .{target = .{name = "alpha", main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/alpha.exe", root)},
        .{target = .{name = "beta",  main_file = "src/main.jai", source_path = tprint("%1/src/main.jai", root)}, target_dir = tprint("%1/target", root), artifact_path = tprint("%1/target/beta.exe", root)},
    ];
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.artifact_plans = plans;
    test_compile_count = 0;
    test_compile_success = false;
    expect(!build_prepared_workspace(*prepared, fake_build_transpile, test_compile_artifact));
    expect(test_compile_count == 1);
}

// ---------------------------------------------------------------------------
// Build transpile front: the seam tests drive the production orchestration
// with recording fakes over real temp fixture files. The probe (production
// code) reads and lexes the closure; the injectable transpile step is never
// called for a test-free closure (zero transpile, zero cache) and otherwise
// runs once per closure file in dependency order.
// ---------------------------------------------------------------------------

// Test-free closure: the transpile step is never called, the compile seam
// receives the original entry, and no transpile tree is created.
test "Build front: a test-free closure skips the transpile step" {
    root := tprint("%1/target/build-seam-clean", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"helper.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/helper.jai", "helper :: () -> s32 { return 1; }\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    expect(build_prepared_workspace(*prepared, fake_build_transpile, fake_build_compile));
    expect(test_build_transpile_calls == 0);
    expect(test_build_compile_calls == 1);
    expect(test_build_compiled_entries[0] == to_forward_slashes(plan.target.source_path));
    // Zero cache: nothing under the transpile tree was created.
    expect(!file_exists(tprint("%1/target/transpile", root)));
}

// Closure with test blocks: every closure file is viewed all-or-nothing
// (dependency order, so the load rewrite embeds the child's view path), the
// entry becomes the entry file's view, and files outside the closure are
// never transpiled.
test "Build front: a test closure is viewed all-or-nothing with load rewrites" {
    root := tprint("%1/target/build-seam-view", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"math.jai\";\n\nmain :: () { print(\"hi\\n\"); }\n"));
    expect(build_seam_write(root, "src/math.jai", "add :: (a: s32, b: s32) -> s32 { return a + b; }\n\ntest \"addition\" {\n}\n"));
    expect(build_seam_write(root, "src/unloaded.jai", "test \"never viewed\" {\n}\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    expect(build_prepared_workspace(*prepared, fake_build_transpile, fake_build_compile));

    // Transpile ran once per closure file, children first (Merkle chain):
    // math.jai before main.jai; unloaded.jai stays untouched.
    expect(test_build_transpile_calls == 2);
    expect(test_build_transpiled_files.count == 2);
    expect(test_build_transpiled_files[0] == "src/math.jai" && test_build_transpiled_files[1] == "src/main.jai");

    // The entry's load rewrite points at the child's fake view path.
    math_view := tprint("%1/target/transpile/%2/src/math.jai", root, fake_key("src/math.jai"));
    expect(test_build_transpiled_rewrites.count == 1);
    expect(test_build_transpiled_rewrites[0] == tprint("src/math.jai -> %1", math_view));

    // The fake views were written content-addressed; the compile seam
    // received the entry file's fake view exactly once.
    expect(test_build_compile_calls == 1);
    entry_view := tprint("%1/target/transpile/%2/src/main.jai", root, fake_key("src/main.jai"));
    expect(test_build_compiled_entries[0] == entry_view);
    main_view, ok := read_entire_file(entry_view);
    expect(ok && main_view == "// fake build view of src/main.jai\n");
    expect(file_exists(math_view));
}

// Transpile diagnostics fail the build before the compile seam, with the
// original file coordinates.
test "Build front: transpile diagnostics fail before compiling" {
    root := tprint("%1/target/build-seam-diag", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "test \"nested in proc\" { }\n\nproc :: () {\n    test \"bad\" { }\n}\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    test_build_fake_diagnostic = "test block 仅允许文件顶层";
    expect(!build_prepared_workspace(*prepared, fake_build_transpile, fake_build_compile));
    expect(test_build_compile_calls == 0);
}

// A cycle in the literal in-package #load graph of a viewed closure cannot
// be rewritten and fails with the dedicated diagnostic.
test "Build front: a load cycle cannot be rewritten" {
    root := tprint("%1/target/build-seam-cycle", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"a.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/a.jai", "#load \"main.jai\";\n\ntest \"cycle\" { }\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    reset_build_seam();
    expect(!build_prepared_workspace(*prepared, fake_build_transpile, fake_build_compile));
    expect(test_build_compile_calls == 0);
}

// The root package's declared transpile pipeline reaches the strip seam in
// declaration order (spec 0060 decision 6): declaration order = pipeline
// order; an undeclared package hands the seam an empty pipeline, which the
// production seam resolves to the default (zero behavior change).
test "Build front: the declared pipeline reaches the transpile seam in declaration order" {
    root := tprint("%1/target/build-seam-pipeline", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"math.jai\";\n\nmain :: () { print(\"hi\\n\"); }\n"));
    expect(build_seam_write(root, "src/math.jai", "add :: (a: s32, b: s32) -> s32 { return a + b; }\n\ntest \"addition\" {\n}\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    prepared.discovery.root_package = .{name = "demo", version = "1", transpile = .{plugins = .[
        .{id = "load", version = "1.0.0"},
        .{id = "test-block", version = "1.0.0"},
    ]}};
    reset_build_seam();
    expect(build_prepared_workspace(*prepared, fake_build_transpile, fake_build_compile));
    expect(test_build_transpiled_pipelines.count == 2);
    expect(test_build_transpiled_pipelines[0] == "load,test-block");
    expect(test_build_transpiled_pipelines[1] == "load,test-block");

    // Declaration order is the pipeline order: the reversed declaration
    // reaches the seam reversed.
    prepared.discovery.root_package = .{name = "demo", version = "1", transpile = .{plugins = .[
        .{id = "test-block", version = "1.0.0"},
        .{id = "load", version = "1.0.0"},
    ]}};
    reset_build_seam();
    expect(build_prepared_workspace(*prepared, fake_build_transpile, fake_build_compile));
    expect(test_build_transpiled_pipelines.count == 2);
    expect(test_build_transpiled_pipelines[0] == "test-block,load");

    // An undeclared package hands the seam an empty pipeline (the default
    // resolution stays the seam's job — zero behavior change).
    prepared.discovery.root_package = .{name = "demo", version = "1"};
    reset_build_seam();
    expect(build_prepared_workspace(*prepared, fake_build_transpile, fake_build_compile));
    expect(test_build_transpiled_pipelines.count == 2);
    expect(test_build_transpiled_pipelines[0] == "");
    expect(test_build_transpiled_pipelines[1] == "");
}

// ---------------------------------------------------------------------------
// jaix pre-step wiring (spec 055 decision 8): the marker routes the build
// through the shared front — the pre-step runs once before the entry loop,
// the strip front is skipped (the mirror entry view is selected directly,
// the #load chain resolves inside the mirror), and compile_artifact_plan
// stays untouched. The recording fake (fake_jaix_prestep) lives in
// tests/test_support.jai.
// ---------------------------------------------------------------------------

test "Build front: the jaix marker routes the entry through the mirror view" {
    root := tprint("%1/target/build-seam-jaix", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"helper.jai\";\n\nmain :: () {}\n"));
    expect(build_seam_write(root, "src/helper.jai", "helper :: () -> s32 { return 1; }\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    prepared.discovery.root_package = .{name = "demo", version = "1", jaix = .{config = "jaix.config.jai"}};
    reset_build_seam();
    test_jaix_prestep_calls = 0;
    expect(build_prepared_workspace(*prepared, fake_build_transpile, fake_build_compile, fake_jaix_prestep));
    expect(test_jaix_prestep_calls == 1);
    // The marker skips the strip front entirely: no probe, no strip views.
    expect(test_build_transpile_calls == 0);
    expect(test_build_compile_calls == 1);
    expect(test_build_compiled_entries[0] == to_forward_slashes(tprint("%1/target/jaix/src/main.jai", root)));
}

test "Build front: a failed jaix pre-step blocks every compilation" {
    root := tprint("%1/target/build-seam-jaix-fail", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "main :: () {}\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    prepared.discovery.root_package = .{name = "demo", version = "1", jaix = .{config = "jaix.config.jai"}};
    reset_build_seam();
    test_jaix_prestep_calls = 0;
    test_jaix_prestep_success = false;
    expect(!build_prepared_workspace(*prepared, fake_build_transpile, fake_build_compile, fake_jaix_prestep));
    expect(test_jaix_prestep_calls == 1 && test_build_transpile_calls == 0 && test_build_compile_calls == 0);
}

test "Build entry: the jaix marker selects the mirror view without probing" {
    plan := build_seam_plan("mirror-root", "src/main.jai");
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = "mirror-root";
    prepared.discovery.root_package = .{name = "demo", version = "1", jaix = .{config = "jaix.config.jai"}};
    test_build_transpile_calls = 0;
    entry, ok := build_plan_entry(*prepared, plan, fake_build_transpile);
    expect(ok && entry == to_forward_slashes("mirror-root/target/jaix/src/main.jai"));
    expect(test_build_transpile_calls == 0);
}

// ---------------------------------------------------------------------------
// Production probe: closure shape over real fixture files (no fakes).
// ---------------------------------------------------------------------------

// The closure is the entry's literal in-package #load reachability: nested
// literal targets are followed, non-literal and out-of-package targets are
// not. Files come back in DFS preorder, loads in statement order.
test "Build probe: only literal in-package loads form the closure" {
    root := tprint("%1/target/build-probe-package", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/main.jai", "#load \"a.jai\";\n#load \"sub/b.jai\";\n#load CONST_NAME;\n#load \"../../outside.jai\";\n"));
    expect(build_seam_write(root, "src/a.jai", "x :: 1;\n"));
    expect(build_seam_write(root, "src/sub/b.jai", "y :: 2;\n"));

    plan := build_seam_plan(root, "src/main.jai");
    prepared := build_seam_prepared(root, plan);
    closure, ok := probe_build_closure(*prepared, plan);
    expect(ok && closure.count == 3);
    expect(closure[0].file.rel_path == "src/main.jai");
    expect(closure[1].file.rel_path == "src/a.jai" && closure[2].file.rel_path == "src/sub/b.jai");
    expect(closure[0].loads.count == 2);
    expect(closure[0].loads[0] == "src/a.jai" && closure[0].loads[1] == "src/sub/b.jai");
    for file: closure {
        expect(!file.has_tests);
    }
}

test "Build probe: test blocks are detected, pass-through shapes are not" {
    root := tprint("%1/target/build-probe-tests", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    // A top-level anchor, a nested anchor (rejected with a diagnostic when
    // viewed), and a non-statement `test` token that passes through.
    expect(build_seam_write(root, "src/has.jai", "test \"top\" { }\n"));
    expect(build_seam_write(root, "src/nested.jai", "proc :: () {\n    test \"bad\" { }\n}\n"));
    expect(build_seam_write(root, "src/pass.jai", "if test { }\n\ntest := 5;\n"));

    plan := build_seam_plan(root, "src/has.jai");
    prepared := build_seam_prepared(root, plan);
    closure, ok := probe_build_closure(*prepared, plan);
    expect(ok && closure.count == 1 && closure[0].has_tests);

    plan2 := build_seam_plan(root, "src/nested.jai");
    closure2, ok2 := probe_build_closure(*prepared, plan2);
    expect(ok2 && closure2.count == 1 && closure2[0].has_tests);

    plan3 := build_seam_plan(root, "src/pass.jai");
    closure3, ok3 := probe_build_closure(*prepared, plan3);
    expect(ok3 && closure3.count == 1 && !closure3[0].has_tests);
}

// Direct tests of transpile_build_file (the real strip step and the #load
// rewrite verbatim semantics) live with the production step in
// tests/transpile_front_tests.jai (test-free module test organization rule).

// ---------------------------------------------------------------------------
// E2E child scenarios: real juice.exe on fixture packages (juice_exe,
// run_juice_child, expect_exit, child_output_contains live in
// tests/test_support.jai).
// ---------------------------------------------------------------------------

// A BIN package with embedded tests builds through strip views: tests are
// stripped, the in-package load is rewritten to the child's view, the views
// match the pure transpile contract byte for byte, and the artifact keeps
// its semantics (prints the same greeting as the original program).
test "E2E: embedded-tests package builds through strip views" {
    fixture_root := tprint("%1/tests/data/test-package", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));

    result, output, _ := run_juice_child("test-package", "build");
    expect(expect_exit("build", result, 0, "build child"));
    expect(child_output_contains("build", output, "[juice Build] Compiling Target 'test-package' (src/main.jai) -> target/..."));

    // The artifact exists and behaves like the original program.
    artifact := tprint("%1/target/test-package.exe", fixture_root);
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("artifact", run_result, 0, "build child"));
    expect(child_output_contains("artifact", run_output, "hello from test-package"));

    // Both closure files have strip views at their pure-contract paths.
    transpile_dir := tprint("%1/target/transpile", fixture_root);
    math_source, ok := read_entire_file(tprint("%1/src/math.jai", fixture_root));
    expect(ok);
    math_key := transpile_view_key("src/math.jai", math_source, .STRIP, Load_Target.[], JUICE_VERSION);
    math_view := transpile_view_path(transpile_dir, math_key, "src/math.jai");
    expect(path_exists_as_regular_file(math_view));
    math_result := transpile_source(math_source, .{mode = .STRIP, path = "src/math.jai"});
    math_view_text, ok2 := read_entire_file(math_view);
    expect(ok2 && math_view_text == math_result.view);

    main_source, ok3 := read_entire_file(tprint("%1/src/main.jai", fixture_root));
    expect(ok3);
    main_key := transpile_view_key("src/main.jai", main_source, .STRIP, Load_Target.[.{from = "src/math.jai", to = math_view}], JUICE_VERSION);
    main_view := transpile_view_path(transpile_dir, main_key, "src/main.jai");
    expect(path_exists_as_regular_file(main_view));
    main_result := transpile_source(main_source, .{mode = .STRIP, path = "src/main.jai", load_targets = Load_Target.[.{from = "src/math.jai", to = math_view}]});
    main_view_text, ok4 := read_entire_file(main_view);
    expect(ok4 && main_view_text == main_result.view);
    // Tests were stripped and the load rewritten to the child view.
    expect(find_index_from_left(main_view_text, "// juice: test stripped") >= 0);
    expect(find_index_from_left(main_view_text, math_view) >= 0);
}

// A test-free package builds without any transpile: no views, no cache
// tree, the artifact comes straight from the original entry.
test "E2E: test-free package builds with zero transpile" {
    fixture_root := tprint("%1/tests/data/build-empty", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));

    result, output, _ := run_juice_child("build-empty", "build");
    expect(expect_exit("build-empty", result, 0, "build child"));
    expect(file_exists(tprint("%1/target/build-empty.exe", fixture_root)));
    expect(!file_exists(tprint("%1/target/transpile", fixture_root)));
}

// Count one tree's regular files recursively (visit_files with
// visit_directories = false never reports directories).
Transpile_File_Count :: struct {
    count: s64;
}

transpile_file_counter :: (info: *File_Visit_Info, user_data: *Transpile_File_Count) {
    user_data.count += 1;
}

// A package that explicitly declares the two built-in plugins in the
// default order produces exactly the same views and cache keys as an
// undeclared package (spec 0060 story 29): the views land at the
// pure-contract paths computed with the DEFAULT pipeline description, and
// no other view files exist (a differing pipeline description would change
// the keys — the hash directory names — and leave extra files behind).
test "E2E: explicit built-in pipeline declaration equals the default pipeline" {
    fixture_root := tprint("%1/tests/data/pipeline-explicit", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));

    result, output, _ := run_juice_child("pipeline-explicit", "build");
    expect(expect_exit("pipeline-explicit", result, 0, "build child"));
    expect(child_output_contains("pipeline-explicit", output, "[juice Build] Compiling Target 'pipeline-explicit' (src/main.jai) -> target/..."));

    // The artifact behaves like the original program.
    artifact := tprint("%1/target/pipeline-explicit.exe", fixture_root);
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("pipeline-explicit artifact", run_result, 0, "build child"));
    expect(child_output_contains("pipeline-explicit artifact", run_output, "hello from pipeline-explicit"));

    // Both closure views exist at the pure-contract paths computed with the
    // default pipeline (an explicit built-in declaration changes nothing),
    // byte for byte equal to the default pipeline's output.
    transpile_dir := tprint("%1/target/transpile", fixture_root);
    math_source, ok := read_entire_file(tprint("%1/src/math.jai", fixture_root));
    expect(ok);
    math_key := transpile_view_key("src/math.jai", math_source, .STRIP, Load_Target.[], JUICE_VERSION);
    math_view := transpile_view_path(transpile_dir, math_key, "src/math.jai");
    expect(path_exists_as_regular_file(math_view));
    math_result := transpile_source(math_source, .{mode = .STRIP, path = "src/math.jai"});
    math_view_text, ok2 := read_entire_file(math_view);
    expect(ok2 && math_view_text == math_result.view);

    main_source, ok3 := read_entire_file(tprint("%1/src/main.jai", fixture_root));
    expect(ok3);
    main_key := transpile_view_key("src/main.jai", main_source, .STRIP, Load_Target.[.{from = "src/math.jai", to = math_view}], JUICE_VERSION);
    main_view := transpile_view_path(transpile_dir, main_key, "src/main.jai");
    expect(path_exists_as_regular_file(main_view));
    main_result := transpile_source(main_source, .{mode = .STRIP, path = "src/main.jai", load_targets = Load_Target.[.{from = "src/math.jai", to = math_view}]});
    main_view_text, ok4 := read_entire_file(main_view);
    expect(ok4 && main_view_text == main_result.view);

    // Exactly these two views exist: no extra hash directories from a
    // differing key.
    counter: Transpile_File_Count;
    visit_files(transpile_dir, true, *counter, transpile_file_counter, visit_directories = false);
    expect(counter.count == 2);

    // The test path sees the same equality through the real exe.
    defer delete_directory_full(tprint("%1/target/transpile", fixture_root));
    test_result, test_output, _ := run_juice_test("pipeline-explicit");
    expect(expect_exit("pipeline-explicit test", test_result, 0));
    expect(output_matches("pipeline-explicit test", test_output, string.["[test] explicit pipeline addition", "1 passed, 0 failed"]));
}

// Declaring an unknown plugin id fails the manifest load with a clear
// diagnostic before anything is built.
test "E2E: an unknown transpile plugin id is rejected with a clear diagnostic" {
    fixture_root := tprint("%1/tests/data/pipeline-unknown", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));

    result, output, _ := run_juice_child("pipeline-unknown", "build");
    expect(expect_exit("pipeline-unknown", result, 1, "build child"));
    expect(child_output_contains("pipeline-unknown", output, "[juice ERROR] Invalid transpile pipeline at "));
    expect(child_output_contains("pipeline-unknown", output, "Unknown transpile plugin id: mystery-plugin"));
    expect(!file_exists(tprint("%1/target/transpile", fixture_root)));
}

// ---------------------------------------------------------------------------
// jaix pre-step E2E (real juice.exe on the demo fixture; prepend_jaix_to_path,
// jaix_exe and clean_jaix_driver_files live in tests/test_support.jai)
// ---------------------------------------------------------------------------

// The wired build: the jaix marker runs the pre-step, the mirror entry
// compiles, the artifact executes the lowered try/catch code (both the
// success and the error-propagation path), untouched mirror views are
// byte-identical to the originals, the cross-file #load chain resolves
// inside the mirror, the juice test block file stays out and the sidecar
// map landed.
test "E2E: jaix pre-step build compiles the mirror and the lowering runs" {
    fixture_root := tprint("%1/tests/data/jaix-demo", juice_root());
    defer delete_directory_full(tprint("%1/target", fixture_root));
    defer clean_jaix_driver_files(fixture_root);
    prepend_jaix_to_path();

    result, output, _ := run_juice_child("jaix-demo", "build");
    expect(expect_exit("jaix-demo", result, 0, "build child"));
    expect(child_output_contains("jaix-demo", output, "[juice] Running jaix pre-step (2 files) -> target/jaix/..."));
    expect(child_output_contains("jaix-demo", output, "[juice Build] Compiling Target 'jaix-demo' (src/main.jai) -> target/..."));

    // The artifact runs the lowered code: the try error propagation actually
    // executed (success and error paths).
    artifact := tprint("%1/target/jaix-demo.exe", fixture_root);
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("jaix-demo artifact", run_result, 0, "build child"));
    expect(child_output_contains("jaix-demo artifact", run_output, "double(20): NONE 40"));
    expect(child_output_contains("jaix-demo artifact", run_output, "double(-6): NEGATIVE 0"));

    // The mirror: untouched files are byte-identical to the originals (the
    // round-trip identity), the try file is lowered, the juice test block
    // file and the config stay out of the mirror, and the sidecar map
    // landed.
    mirror := tprint("%1/target/jaix", fixture_root);
    main_original, ok := read_entire_file(tprint("%1/src/main.jai", fixture_root));
    expect(ok);
    main_view, ok2 := read_entire_file(tprint("%1/src/main.jai", mirror));
    expect(ok2 && main_view == main_original);
    expect(find_index_from_left(main_view, "#load \"calc.jai\";") >= 0);

    calc_view, ok5 := read_entire_file(tprint("%1/src/calc.jai", mirror));
    expect(ok5);
    expect(find_index_from_left(calc_view, "try_0_err, try_0_v := half(n);") >= 0);
    expect(!file_exists(tprint("%1/src/calc_tests.jai", mirror)));
    expect(!file_exists(tprint("%1/jaix.config.jai", mirror)));
    expect(file_exists(tprint("%1/src/calc.jai.map", mirror)));
}

// A jaix transpile failure fails the build: the child's diagnostics pass
// through on stderr, the exit code is nonzero and no artifact exists.
test "E2E: a jaix transpile failure propagates diagnostics and produces no artifact" {
    root := tprint("%1/target/jaix-e2e-fail", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    prepend_jaix_to_path();
    expect(build_seam_write(root, "package.jai",
        "TARGETS :: Target.[\n    .{ name = \"jaix-fail\", main_file = \"src/main.jai\" },\n];\n\nPACKAGE :: Package.{\n    name    = \"jaix-fail\",\n    version = \"1\",\n    targets = TARGETS,\n    jaix    = .{ config = \"jaix.config.jai\" },\n};\n"));
    expect(build_seam_write(root, "jaix.config.jai",
        "#import \"jaix\";\nJaix_Plugin_Try_Catch :: #import \"Jaix_Plugin_Try_Catch\";\n\nget_config :: () -> Jaix_Config {\n    p := Jaix_Plugin_Try_Catch.get_plugin();\n    return .{ plugins = plugins_of(as_plugin(p)) };\n}\n"));
    expect(build_seam_write(root, "src/main.jai", "main :: () {\n    try half(1) catch;\n}\n"));

    juice := juice_exe();
    result, output, errors, _ := run_command(juice, "build", working_directory = lexical_absolute_path(root), capture_and_return_output = true);
    expect(expect_exit("jaix-fail", result, 1, "build child"));
    // The jaix child's diagnostics pass through on stderr; juice's own
    // failure line lands on stdout (the plain [juice ERROR] convention).
    expect(output_matches("jaix-fail", errors, string.["Error: Semicolon expected after expression."]));
    expect(output_matches("jaix-fail", errors, string.["src/main.jai"]));
    expect(output_matches("jaix-fail", output, string.["[juice ERROR] jaix pre-step failed for src/main.jai"]));
    expect(!file_exists(tprint("%1/target/jaix-fail.exe", root)));
}

// A declared exe that does not exist fails the pre-step with the clear
// error before any spawn: no artifact, no mirror directory.
test "E2E: a missing jaix executable fails the pre-step with a clear error" {
    root := tprint("%1/target/jaix-e2e-noexe", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai",
        "TARGETS :: Target.[\n    .{ name = \"jaix-noexe\", main_file = \"src/main.jai\" },\n];\n\nPACKAGE :: Package.{\n    name    = \"jaix-noexe\",\n    version = \"1\",\n    targets = TARGETS,\n    jaix    = .{ config = \"jaix.config.jai\", exe = \"no-such-jaix.exe\" },\n};\n"));
    expect(build_seam_write(root, "src/main.jai", "main :: () {}\n"));

    juice := juice_exe();
    result, output, _, _ := run_command(juice, "build", working_directory = lexical_absolute_path(root), capture_and_return_output = true);
    expect(expect_exit("jaix-noexe", result, 1, "build child"));
    expect(output_matches("jaix-noexe", output, string.["[juice ERROR] jaix executable not found: "]));
    expect(!file_exists(tprint("%1/target/jaix-noexe.exe", root)));
    expect(!file_exists(tprint("%1/target/jaix", root)));
}

// The dual-path E2E (spec 055 decision 12): the manual two-step script and
// the wired one-step build are the same build. The script's step 1 alone
// produces the mirror; the wired build then re-runs the pre-step over it and
// must yield the byte-identical mirror (the idempotency face). The full
// script (step 1 + juice build + juice run) and the wired path both produce
// the artifact and the same run output.
test "E2E: the two-step script and the wired build are the same build (dual path)" {
    fixture_root := tprint("%1/tests/data/jaix-demo", juice_root());
    delete_directory_full(tprint("%1/target", fixture_root));
    defer delete_directory_full(tprint("%1/target", fixture_root));
    defer clean_jaix_driver_files(fixture_root);
    prepend_jaix_to_path();
    script := tprint("%1/two-step.bat", fixture_root);
    mirror := tprint("%1/target/jaix", fixture_root);

    // The manual step 1 alone: the mirror is the script's own product —
    // untouched files byte-identical to the originals, the try file lowered,
    // the sidecar map landed.
    args: [..] string;
    array_add(*args, "cmd");
    array_add(*args, "/c");
    array_add(*args, script);
    array_add(*args, "transpile-only");
    result, output, _ := run_command(..args, working_directory = fixture_root, capture_and_return_output = true);
    expect(expect_exit("two-step transpile-only", result, 0, "build child"));
    main_view, ok1 := read_entire_file(tprint("%1/src/main.jai", mirror));
    expect(ok1);
    main_original, ok2 := read_entire_file(tprint("%1/src/main.jai", fixture_root));
    expect(ok2 && main_view == main_original);
    calc_view, ok3 := read_entire_file(tprint("%1/src/calc.jai", mirror));
    expect(ok3 && find_index_from_left(calc_view, "try_0_err, try_0_v := half(n);") >= 0);
    expect(file_exists(tprint("%1/src/calc.jai.map", mirror)));
    calc_map_step1, ok_map := read_entire_file(tprint("%1/src/calc.jai.map", mirror));
    expect(ok_map);

    // The wired build re-runs the pre-step over the script's mirror: the
    // mirror after the wired pre-step equals the manual step 1's mirror,
    // byte for byte (the idempotency face).
    result, output, _ = run_juice_child("jaix-demo", "build");
    expect(expect_exit("jaix-demo wired", result, 0, "build child"));
    expect(child_output_contains("jaix-demo wired", output, "[juice] Running jaix pre-step (2 files) -> target/jaix/..."));
    main_rewritten, ok4 := read_entire_file(tprint("%1/src/main.jai", mirror));
    calc_rewritten, ok5 := read_entire_file(tprint("%1/src/calc.jai", mirror));
    expect(ok4 && ok5 && main_rewritten == main_view && calc_rewritten == calc_view);
    // The sidecar joins the idempotency face: decision 12's byte-identity
    // claim covers the whole mirror, .map files included.
    calc_map_rewritten, ok_map2 := read_entire_file(tprint("%1/src/calc.jai.map", mirror));
    expect(ok_map2 && calc_map_rewritten == calc_map_step1);

    // The wired path's artifact runs the lowered code (success and error
    // paths).
    artifact := tprint("%1/target/jaix-demo.exe", fixture_root);
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("jaix-demo artifact", run_result, 0, "build child"));
    expect(child_output_contains("jaix-demo artifact", run_output, "double(20): NONE 40"));
    expect(child_output_contains("jaix-demo artifact", run_output, "double(-6): NEGATIVE 0"));

    // The full script path: step 1 again, then juice build (the wired
    // pre-step re-runs inside it) and juice run — the same artifact and the
    // same run output as the wired path.
    args2: [..] string;
    array_add(*args2, "cmd");
    array_add(*args2, "/c");
    array_add(*args2, script);
    result, output, _ = run_command(..args2, working_directory = fixture_root, capture_and_return_output = true);
    expect(expect_exit("two-step script", result, 0, "build child"));
    expect(child_output_contains("two-step script", output, "[juice] Running jaix pre-step (2 files) -> target/jaix/..."));
    expect(child_output_contains("two-step script", output, "double(20): NONE 40"));
    expect(child_output_contains("two-step script", output, "double(-6): NEGATIVE 0"));
    expect(file_exists(artifact));
}

// The double-build E2E (spec 054 Testing Decisions seam 3): two consecutive
// wired builds of the demo fixture. The first build's jaix driver litter
// stays on disk — the real jaix subprocess product, dot-prefixed
// (.jaix-<hash>.jai) and content-marked — and the second build succeeds
// unchanged, producing the same artifact behavior and the byte-identical
// mirror (round-trip against the originals, plus the direct seam-3
// assertion: the second pre-step's mirror views — the calc lowered view
// and the .map sidecar included — byte-for-byte equal to the first
// pre-step's). Red before 0056/0058: the second build's whole-package scan
// parsed the legacy hash-named litter as source and failed (060 deviation 3).
test "E2E: two consecutive wired builds are the same build despite driver litter" {
    fixture_root := tprint("%1/tests/data/jaix-demo", juice_root());
    delete_directory_full(tprint("%1/target", fixture_root));
    defer delete_directory_full(tprint("%1/target", fixture_root));
    defer clean_jaix_driver_files(fixture_root);
    prepend_jaix_to_path();

    // The first wired build: the pre-step runs and the real jaix
    // subprocess leaves its driver files at the fixture root (the spawn
    // cwd). They stay — no cleaning between the two builds, so the second
    // build's scans face the real litter.
    result, output, _ := run_juice_child("jaix-demo", "build");
    expect(expect_exit("jaix-demo first", result, 0, "build child"));
    expect(child_output_contains("jaix-demo first", output, "[juice] Running jaix pre-step (2 files) -> target/jaix/..."));

    // The litter is really on disk and dot-prefixed (the jaix naming,
    // 0056): without it the double build would prove nothing.
    litter_names: [..] string;
    scan, visited := dir_scan_entries(fixture_root);
    expect(visited);
    for name: scan.files {
        if !ends_with(name, ".jai") continue;
        if name == "package.jai" || name == "jaix.config.jai" continue;
        array_add(*litter_names, name);
    }
    expect(litter_names.count > 0);
    for name: litter_names {
        expect(name[0] == #char ".");
    }

    // The first artifact's run output is the idempotency baseline.
    artifact := tprint("%1/target/jaix-demo.exe", fixture_root);
    expect(file_exists(artifact));
    first_run, first_run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("jaix-demo artifact first", first_run, 0, "build child"));
    expect(child_output_contains("jaix-demo artifact first", first_run_output, "double(20): NONE 40"));
    expect(child_output_contains("jaix-demo artifact first", first_run_output, "double(-6): NEGATIVE 0"));

    // The first build's mirror views are the determinism baseline: seam 3
    // wants the second pre-step's mirror byte-identical to the first
    // pre-step's — read now and compared directly against the second
    // build's reads below (not only via the round-trip proxy against the
    // originals).
    mirror := tprint("%1/target/jaix", fixture_root);
    main_view_first, ok_main_first := read_entire_file(tprint("%1/src/main.jai", mirror));
    calc_view_first, ok_calc_first := read_entire_file(tprint("%1/src/calc.jai", mirror));
    calc_map_first, ok_map_first := read_entire_file(tprint("%1/src/calc.jai.map", mirror));
    expect(ok_main_first && ok_calc_first && ok_map_first);

    // The second wired build over the litter: the scans exclude the
    // driver files (dot-prefix entries at any depth plus the content
    // marker), the pre-step still scans exactly the two sources and the
    // build succeeds unchanged.
    result, output, _ = run_juice_child("jaix-demo", "build");
    expect(expect_exit("jaix-demo second", result, 0, "build child"));
    expect(child_output_contains("jaix-demo second", output, "[juice] Running jaix pre-step (2 files) -> target/jaix/..."));

    // The idempotency faces the double build holds: the artifact behaves
    // byte-identically at run time and the second pre-step's mirror is
    // byte-identical to the first pre-step's — asserted directly below,
    // and the mirror is byte-identical to the originals after the second
    // pre-step. (The exe itself is not bit-reproducible — jai debug builds
    // embed per-build data in the PE timestamp and the debug info, so two
    // identical compiles differ byte-wise; 0059 deviation 1. The run
    // output and the mirror are the deterministic faces.)
    second_run, second_run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("jaix-demo artifact second", second_run, 0, "build child"));
    expect(second_run_output == first_run_output);
    // The second build's mirror reads, compared byte for byte against the
    // first build's (the direct seam-3 assertion). The main view equals
    // the original both times, so its direct comparison is equivalent to
    // the round-trip check below; the calc lowered view and the .map
    // sidecar are not compared against originals elsewhere, so their
    // direct comparison is the real gain — it locks the two pre-steps'
    // product determinism.
    main_view_second, ok_main_second := read_entire_file(tprint("%1/src/main.jai", mirror));
    calc_view_second, ok_calc_second := read_entire_file(tprint("%1/src/calc.jai", mirror));
    calc_map_second, ok_map_second := read_entire_file(tprint("%1/src/calc.jai.map", mirror));
    expect(ok_main_second && ok_calc_second && ok_map_second);
    expect(main_view_second == main_view_first);
    expect(calc_view_second == calc_view_first);
    expect(calc_map_second == calc_map_first);
    main_original, ok3 := read_entire_file(tprint("%1/src/main.jai", fixture_root));
    expect(ok3 && main_view_second == main_original);
    expect(find_index_from_left(calc_view_second, "try_0_err, try_0_v := half(n);") >= 0);
}
