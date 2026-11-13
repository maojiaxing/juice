#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// Bootstrap metaprogram tests (ticket 031): the bootstrap options assembly
// (the pure function src/metaprogram.jai gained for build.jai's #run) and
// the very_optimized release emission in the generated compiler
// metaprogram, plus the real-child E2E scenarios — the real jai compiler
// running otter's build.jai on the otter root (debug self-build, release
// self-build, the failure path). Good-test discipline (005 testing
// decisions): only external behavior — exit codes, artifact existence and
// runs, view landing.
//
// The E2E runs on the otter root by necessity, not choice: the metaprogram
// anchors its working directory to the entry file's directory (the jai
// entry-file anchoring — build.jai's #run resolves relative paths and
// get_working_directory() against the otter root regardless of the
// invocation cwd), so build.jai always self-builds its own package. A
// scratch-root fixture could never be probed. The self-build overwrites
// target/juice.exe mid-suite — the tests run sequentially and the product
// is the same source, so the replacement is safe; the artifact version
// smoke below proves the product is complete.
// ---------------------------------------------------------------------------

// Spawns the real jai compiler on otter's build.jai with the otter root as
// the working directory; args feeds the `-` separator's metaprogram command
// line (["release"] for the release mode, empty for debug).
run_bootstrap_child :: (args: [] string) -> (Process_Result, string, string) {
    spawn_args: [..] string;
    // The whole command line goes through one splat: a fixed argument before
    // a spread occupies the varargs slot (the ticket 011 deviation 7 Jai
    // fact), so the program path joins the array.
    array_add(*spawn_args, JAI_COMPILER_PATH);
    array_add(*spawn_args, tprint("%1/build.jai", otter_root()));
    if args.count > 0 {
        array_add(*spawn_args, "-");
        for arg: args array_add(*spawn_args, arg);
    }
    result, output, errors, _ := run_command(..spawn_args, working_directory = otter_root(), capture_and_return_output = true);
    return result, output, errors;
}

// ---------------------------------------------------------------------------
// The bootstrap options assembly (src/metaprogram.jai).
// ---------------------------------------------------------------------------

test "The bootstrap options assembly derives absolute paths from the root" {
    options := bootstrap_compiler_metaprogram_options("X:\\demo", "X:/demo/src/main.jai", "", false);
    expect(options.workspace_name == "Juice Build");
    expect(options.executable_name == "juice");
    expect(options.output_path == "X:/demo/target");
    expect(options.intermediate_path == "X:/demo/target/build");
    expect(options.build_file == "X:/demo/src/main.jai");
    expect(options.testing_view_dir == "");
    expect(!options.very_optimized);
    expect(options.import_dirs.count == 3);
    expect(options.import_dirs[0] == "X:/demo/src");
    // The bootstrap window's module face lives in target/modules (the seed
    // home; ticket 032's publish step lands the real face at the same
    // path) — not the old juice shape's in-repo modules/ directory.
    expect(options.import_dirs[1] == "X:/demo/target/modules");
    expect(options.import_dirs[2] == "X:/demo");
}

test "The release flag switches the bootstrap options to very optimized" {
    options := bootstrap_compiler_metaprogram_options("X:\\demo", "X:/demo/src/main.jai", "X:/demo/target/transpile/testing-module", true);
    expect(options.very_optimized);
    expect(options.testing_view_dir == "X:/demo/target/transpile/testing-module");
}

// ---------------------------------------------------------------------------
// The very_optimized emission (the ticket 011 handover point).
// ---------------------------------------------------------------------------

test "The generated compiler metaprogram emits the very-optimized line only for release" {
    options: Compiler_Metaprogram_Options;
    options.workspace_name    = "Juice Build";
    options.executable_name   = "app";
    options.output_path       = "X:/demo/target";
    options.intermediate_path = "X:/demo/target";
    options.import_dirs       = string.[];
    options.build_file        = "X:/demo/src/main.jai";
    options.very_optimized    = true;

    line := "    set_optimization(*options, .VERY_OPTIMIZED);\n";
    generated := generate_compiler_metaprogram(options);
    expect(find_index_from_left(generated, line) >= 0);
    // The emission sits between the import-path assignment and the options
    // hand-off, so the optimization reaches the same options object the
    // workspace receives.
    expect(find_index_from_left(generated, line) < find_index_from_left(generated, "    set_build_options(options, workspace);\n"));

    // The default shape stays byte-identical (the build_tests byte-locks
    // cover the false case; asserted directly here as well).
    options.very_optimized = false;
    expect(find_index_from_left(generate_compiler_metaprogram(options), line) < 0);
}

// ---------------------------------------------------------------------------
// The version assertion driver generator (src/metaprogram.jai, ticket 032).
// ---------------------------------------------------------------------------

test "The version assertion driver #loads the manifest, embeds the verbatim constant line and asserts at compile time" {
    generated := generate_version_assertion_driver("X:/demo/package.jai", "JUICE_VERSION :: \"0.1.0\";");
    // The manifest evaluator's driver shape (ticket 007): the Basic/Compiler
    // imports, the #load of the manifest path (quoted, "/"-separated), the
    // do_output-false #run/main skeleton.
    expect(find_index_from_left(generated, "#import \"Basic\";\n#import \"Compiler\";\n#import \"Juice\";\n") >= 0);
    expect(find_index_from_left(generated, "#load \"X:/demo/package.jai\";\n") >= 0);
    // The constant declaration line is the definition source's own line,
    // embedded verbatim (the single source — the published juice_core
    // discipline), so the assertion compiles against the real constant.
    expect(find_index_from_left(generated, "JUICE_VERSION :: \"0.1.0\";\n") >= 0);
    // The comparison is a compile-time #assert carrying the loud failure
    // message (a runtime print would be swallowed by the failure path's
    // exit — the pinned Jai fact), plus the success-path print.
    expect(find_index_from_left(generated, "#assert PACKAGE.version == JUICE_VERSION \"package.jai VERSION must equal JUICE_VERSION") >= 0);
    expect(find_index_from_left(generated, "[Version Assert] ✅") >= 0);
    expect(find_index_from_left(generated, "set_build_options_dc(.{do_output = false});") >= 0);
}

// ---------------------------------------------------------------------------
// E2E child scenarios: the real jai compiler on build.jai at the otter root
// (the self-build — the entry-file anchoring makes the otter root the only
// reachable target). The publish step inside build.jai lands the module
// faces itself (ticket 032: publish before compile — the retired bootstrap
// window pre-seeding is gone), so the self-build needs no seed; the blocks
// pin the published artifacts, the seed retirement and the assertion
// trigger against the real run.
// ---------------------------------------------------------------------------

// The published artifact paths (the src/publication.jai landing helpers).
// The fourth path is the ticket 037 internal discovery artifact — the
// verbatim source copy under <modules>/juice_internal/.
bootstrap_published_paths :: () -> (string, string, string, string) {
    target_dir := otter_target_dir();
    modules_dir := path_slashes(tprint("%1/modules", target_dir));
    return juice_module_path(target_dir), testing_module_path(target_dir), juice_core_module_path(target_dir), test_discovery_module_path(modules_dir);
}

// The self-lock guard (ticket 033): when the suite runs from the package
// artifact (target/juice.exe test — the self-hosted acceptance run), the
// running image holds target/juice.exe without write sharing, so the
// bootstrap compile child's linker would fail with LNK1104 (the bootstrap
// carries no hand-off: 005 decision 10 / ticket 031 deviation 7 — hand-off
// belongs to the artifact's own Build command). The self-build E2E blocks
// skip loudly in that environment; the only full-coverage path is a run
// from a target/ copy (the artifact released).
bootstrap_e2e_self_locked :: () -> bool {
    if !artifact_is_running(otter_exe()) return false;
    print("[bootstrap E2E] SKIP: target/juice.exe is running (self-hosted suite; the self-build's link would hit LNK1104 — run the suite from a target/ copy for full coverage).\n");
    return true;
}

test "E2E: jai build.jai self-builds the otter root in debug and publishes the module faces" {
    if bootstrap_e2e_self_locked() return;

    // Plant a stale flat Juice.jai seed before the build: the publish step
    // must retire it (the directory module takes over — no flat/directory
    // ambiguity at the modules dir, 005 US 14). The defer cleans up on a
    // failed build so later E2E children never see the flat face.
    flat_seed := path_slashes(tprint("%1/Juice.jai", target_modules_dir(otter_target_dir())));
    expect(make_directory_if_it_does_not_exist(path_strip_filename(flat_seed), recursive = true));
    expect(write_entire_file(flat_seed, "// stale flat seed, must be retired\n"));
    defer {
        if file_exists(flat_seed) file_delete(flat_seed);
    }

    result, _, _ := run_bootstrap_child(string.[]);
    expect(expect_exit("bootstrap-debug", result, 0, "bootstrap child"));

    // The three published artifacts exist and match the in-process
    // publication byte for byte (005 US 19: publication drift fails
    // loudly); the fourth is the verbatim discovery source (ticket 037).
    source, source_ok := read_entire_file(tprint("%1/src/module.jai", otter_root()));
    expect(source_ok);
    expected_juice, _ := publish_juice_module(source);
    expected_testing, _ := publish_testing_module(source);
    expected_core, _ := publish_juice_core(source);
    juice_path, testing_path, core_path, discovery_path := bootstrap_published_paths();
    actual_juice, juice_read_ok := read_entire_file(juice_path);
    actual_testing, testing_read_ok := read_entire_file(testing_path);
    actual_core, core_read_ok := read_entire_file(core_path);
    discovery_source, discovery_source_ok := read_entire_file(tprint("%1/src/test_discovery.jai", otter_root()));
    actual_discovery, discovery_read_ok := read_entire_file(discovery_path);
    expect(juice_read_ok && actual_juice == expected_juice, "published Juice module must match the in-process publication byte for byte");
    expect(testing_read_ok && actual_testing == expected_testing, "published Testing module must match the in-process publication byte for byte");
    expect(core_read_ok && actual_core == expected_core, "published juice_core module must match the in-process publication byte for byte");
    expect(discovery_source_ok && discovery_read_ok && actual_discovery == discovery_source, "the discovery source publication must be the verbatim source");
    // Ticket 049: the four plugin face closure copies are the verbatim
    // sources under <modules>/juice_internal/plugin_face/ — the published
    // juice_core's module-relative #load lines resolve through them.
    target_dir := otter_target_dir();
    modules_dir := path_slashes(tprint("%1/modules", target_dir));
    for file: JUICE_CORE_LOAD_FILES {
        closure_source, closure_source_ok := read_entire_file(path_slashes(tprint("%1/src/%2", otter_root(), file)));
        face_path := juice_plugin_face_file_path(modules_dir, file);
        actual_copy, copy_read_ok := read_entire_file(face_path);
        expect(closure_source_ok, "the plugin face source must be readable: %", file);
        expect(copy_read_ok, "the plugin face copy must land at %", face_path);
        expect(actual_copy == closure_source, "the plugin face copy must be the verbatim source: %", file);
    }
    // The flat seed retired — zero residue.
    expect(!file_exists(flat_seed), "the stale flat Juice.jai seed must be retired by the publish step");

    // The PLAIN-layout views landed under the bootstrap-exclusive tree —
    // the whole closure including the entry (never the content-addressed
    // cache).
    expect(file_exists(path_slashes(tprint("%1/bootstrap/src/main.jai", target_transpile_dir(otter_target_dir())))));
    expect(file_exists(path_slashes(tprint("%1/bootstrap/src/module.jai", target_transpile_dir(otter_target_dir())))));
    // The Testing module special case wrote the STRIP view of the
    // PUBLISHED face: the bare published names (not the seed's prefixed
    // ones) prove the special case consumed the publication.
    expect(file_exists(path_slashes(tprint("%1/Testing.jai", target_testing_module_dir(otter_target_dir())))));
    testing_view, view_ok := read_entire_file(path_slashes(tprint("%1/Testing.jai", target_testing_module_dir(otter_target_dir()))));
    expect(view_ok);
    expect(find_index_from_left(testing_view, "run :: (name: string") >= 0, "the Testing special case must consume the published bare-name face");
    expect(find_index_from_left(testing_view, "Testing_run") < 0);
    // ...and the compile metaprogram session product landed under
    // target/build/.
    expect(file_exists(path_slashes(target_session_driver_path(target_build_dir(otter_target_dir()), "bootstrap-meta.jai"))));

    // The self-built artifact replaces the suite's exe; the version smoke
    // proves the product is complete (the version command's output
    // contract).
    artifact := otter_exe();
    expect(file_exists(artifact));
    // C5: the compiler intermediates (object files, import lib/exp and the
    // PDB) live in target/build; the artifact root keeps only the exe and
    // the zone directories.
    #if OS == .WINDOWS {
        expect(file_exists(path_slashes(tprint("%1/juice.pdb", target_build_dir(otter_target_dir())))));
        expect(!file_exists(path_slashes(tprint("%1/juice.pdb", otter_target_dir()))));
    }
    run_result, run_output, _, _ := run_command(artifact, "version", capture_and_return_output = true);
    expect(expect_exit("bootstrap-debug artifact", run_result, 0, "bootstrap child"));
    expect(child_output_contains("bootstrap-debug artifact", run_output, "juice 0.1.0"));
}

test "E2E: jai build.jai - release self-builds the otter root" {
    if bootstrap_e2e_self_locked() return;

    result, _, _ := run_bootstrap_child(string.["release"]);
    expect(expect_exit("bootstrap-release", result, 0, "bootstrap child"));

    // The release run also publishes (every build regenerates the module
    // faces, the internal source artifact and the plugin face closure
    // copies — 005 US 10, tickets 037/049) and leaves no flat seed behind.
    juice_path, testing_path, core_path, discovery_path := bootstrap_published_paths();
    expect(file_exists(juice_path));
    expect(file_exists(testing_path));
    expect(file_exists(core_path));
    expect(file_exists(discovery_path));
    modules_dir := target_modules_dir(otter_target_dir());
    for file: JUICE_CORE_LOAD_FILES {
        expect(file_exists(juice_plugin_face_file_path(modules_dir, file)), "the release build must publish the plugin face copy %", file);
    }
    expect(!file_exists(path_slashes(tprint("%1/Juice.jai", target_modules_dir(otter_target_dir())))));

    artifact := otter_exe();
    expect(file_exists(artifact));
    // C5: the compiler intermediates (object files, import lib/exp and the
    // PDB) live in target/build; the artifact root keeps only the exe and
    // the zone directories.
    #if OS == .WINDOWS {
        expect(file_exists(path_slashes(tprint("%1/juice.pdb", target_build_dir(otter_target_dir())))));
        expect(!file_exists(path_slashes(tprint("%1/juice.pdb", otter_target_dir()))));
    }
    run_result, run_output, _, _ := run_command(artifact, "version", capture_and_return_output = true);
    expect(expect_exit("bootstrap-release artifact", run_result, 0, "bootstrap child"));
    expect(child_output_contains("bootstrap-release artifact", run_output, "juice 0.1.0"));
}

test "E2E: a version drift between package.jai and JUICE_VERSION fails the self-build loudly" {
    // Rewrite package.jai's VERSION record for the duration of the test
    // (the assertion driver compiles the manifest and #asserts against the
    // JUICE_VERSION constant line extracted from src/commands/version.jai;
    // the publish step is unaffected — it reads src/module.jai — so the
    // run fails at the assertion, before the compile child). The defer
    // restores the manifest so later E2E children keep building green.
    manifest_path := tprint("%1/package.jai", otter_root());
    original, read_ok := read_entire_file(manifest_path);
    expect(read_ok);

    needle := "version = \"0.1.0\"";
    index := find_index_from_left(original, needle);
    expect(index >= 0);
    drifted := tprint("%1version = \"9.9.9\"%2",
                      slice(original, 0, index),
                      slice(original, index + needle.count, original.count - index - needle.count));
    defer {
        write_entire_file(manifest_path, original);
    }
    expect(write_entire_file(manifest_path, drifted));

    result, _, errors := run_bootstrap_child(string.[]);
    expect(expect_exit("bootstrap-version-drift", result, 1, "bootstrap child"));
    // The assertion driver's compile-time #assert fails the child compiler
    // loudly: jai prints the error with file:line and the message below on
    // stderr, and the child exits nonzero (a runtime print would be
    // swallowed by the failure path's exit — the pinned Jai fact).
    expect(output_matches("bootstrap-version-drift", errors, string.[
        "Compile-time assertion failed.",
        "package.jai VERSION must equal JUICE_VERSION",
    ]));
}

test "E2E: a missing definition source fails the self-build" {
    // Park the definition source for the duration of the test: the publish
    // step reads src/module.jai first, so the build fails before any child
    // spawns — the observable is the exit code only (the parent's failure
    // print is swallowed by exit(1), the pinned Jai fact; the loud-output
    // child failure seam is covered by the version drift test above). The
    // park is crash-safe (ticket 053 F2): the source is copied to a target/
    // backup and verified on disk before the original is removed, so a test
    // process killed mid-run leaves the only copy recoverable; the defer
    // restores from the backup and asserts the restore so later E2E
    // children keep building green.
    module_path := path_slashes(tprint("%1/src/module.jai", otter_root()));
    backup_path := path_slashes(otter_recovery_path("bootstrap-definition-module.jai"));
    expect(park_source_file(module_path, backup_path));
    defer expect(restore_source_file(module_path, backup_path));

    result, _, _ := run_bootstrap_child(string.[]);
    expect(expect_exit("bootstrap-missing-source", result, 1, "bootstrap child"));
}

test "E2E: a missing discovery source fails the self-build without a partial publication" {
    // The fourth publication's source (ticket 037, 006 decision 4/5): the
    // publish step reads both sources before writing anything, so a missing
    // src/test_discovery.jai must fail the build loudly and land no
    // artifact at all — not even the three module faces. The modules
    // directory is removed first so the assertion observes this run's
    // writes only; the park is crash-safe (ticket 053 F2: target/ backup
    // verified on disk before the original is removed), and the defer
    // restores the source, asserts the restore and republishes the set for
    // the following E2E children.
    discovery_path := path_slashes(tprint("%1/src/test_discovery.jai", otter_root()));
    backup_path := path_slashes(otter_recovery_path("bootstrap-discovery-source.jai"));
    target_dir := otter_target_dir();
    modules_dir := path_slashes(tprint("%1/modules", target_dir));
    delete_directory_full(modules_dir);
    expect(park_source_file(discovery_path, backup_path));
    defer {
        expect(restore_source_file(discovery_path, backup_path));
        expect(ensure_published_modules());
    }

    result, _, _ := run_bootstrap_child(string.[]);
    expect(expect_exit("bootstrap-missing-discovery-source", result, 1, "bootstrap child"));
    // No partial set: none of the six published artifacts landed — the
    // module faces, the discovery source and the plugin face copies are
    // written only after every source reads.
    expect(!file_exists(juice_module_path(target_dir)), "the failed publish must not land the Juice module");
    expect(!file_exists(testing_module_path(target_dir)), "the failed publish must not land the Testing module");
    expect(!file_exists(juice_core_module_path(target_dir)), "the failed publish must not land the juice_core module");
    expect(!file_exists(test_discovery_module_path(modules_dir)), "the failed publish must not land the discovery source");
    for file: JUICE_CORE_LOAD_FILES {
        expect(!file_exists(juice_plugin_face_file_path(modules_dir, file)), "the failed publish must not land the plugin face copy %", file);
    }
}

test "E2E: a missing plugin face closure source fails the self-build without a partial publication" {
    // Ticket 049 (048 decision 3/7): src/lifecycle.jai is in the plugin
    // face closure list but not in the build metaprogram's own #load
    // closure, so build.jai still compiles and reaches the publish step —
    // the missing source must fail that step loudly, before any artifact
    // lands. The modules directory is removed first so the assertions
    // observe this run's writes only; the park is crash-safe (ticket 053
    // F2: target/ backup verified on disk before the original is removed),
    // and the defer restores the source, asserts the restore and
    // republishes the set for the following E2E children.
    closure_path := path_slashes(tprint("%1/src/lifecycle.jai", otter_root()));
    backup_path := path_slashes(otter_recovery_path("bootstrap-plugin-face-lifecycle.jai"));
    target_dir := otter_target_dir();
    modules_dir := path_slashes(tprint("%1/modules", target_dir));
    delete_directory_full(modules_dir);
    expect(park_source_file(closure_path, backup_path));
    defer {
        expect(restore_source_file(closure_path, backup_path));
        expect(ensure_published_modules());
    }

    result, _, _ := run_bootstrap_child(string.[]);
    expect(expect_exit("bootstrap-missing-closure-source", result, 1, "bootstrap child"));
    // No partial set: nothing under the modules directory landed.
    expect(!file_exists(juice_module_path(target_dir)), "the failed publish must not land the Juice module");
    expect(!file_exists(testing_module_path(target_dir)), "the failed publish must not land the Testing module");
    expect(!file_exists(juice_core_module_path(target_dir)), "the failed publish must not land the juice_core module");
    expect(!file_exists(test_discovery_module_path(modules_dir)), "the failed publish must not land the discovery source");
    for file: JUICE_CORE_LOAD_FILES {
        expect(!file_exists(juice_plugin_face_file_path(modules_dir, file)), "the failed publish must not land the plugin face copy %", file);
    }
}
