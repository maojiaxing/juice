#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
#import "Testing";

// ---------------------------------------------------------------------------
// Command-level plugin preparation + PRESTEP-only plugin host (ticket 060,
// spec §5.2/§11.13). The unit matrix pins the prepare product (the only
// scan/registration landing point), the strict host record parser (the
// manifest protocol's posture: unknown keys, duplicate/missing OK, malformed
// escapes, blank lines), the spawn failure channels (nonzero exit, missing
// record file, stale-record masking) and the stage-effect application (the
// prestep_add_* table rules). The E2E matrix runs the real otter executable
// against tests/data/plugin-prestep-fixture — a root package declaring one
// workspace member plugin with a PRESTEP hook and options — plus negative
// scratch copies (options rejection, merge conflict, host compile crash) and
// the zero-plugin no-host posture.
//
// All helpers are prefixed ph_ (the single-program test namespace
// convention); this file is test-only and is not #loaded by src/main.jai.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Scratch roots and fake-plugin packages
// ---------------------------------------------------------------------------

ph_scratch :: (name: string) -> string {
    root := otter_scratch(tprint("plugin-host-tests/%1", name));
    delete_directory_full(root);
    make_directory_if_it_does_not_exist(root, recursive = true);
    return root;
}

ph_fixture_root :: (name: string) -> string {
    return path_slashes(tprint("%1/tests/data/%2", otter_root(), name));
}

// A scratch copy of a fixture (the static fixture tree stays clean): the
// copy's target/ is dropped so every run regenerates its session artifacts.
ph_fixture_copy :: (name: string, fixture_name: string) -> string {
    scratch := ph_scratch(name);
    copy_directory(ph_fixture_root(fixture_name), scratch);
    delete_directory_full(package_target_dir(scratch));
    return scratch;
}

// The lexical plugin anchors used by the prepare tests: the scan is lexical
// (the scratch member never compiles), so an anchor plus an optional hooks
// face token is enough. PH_HOOKS_ANCHOR_SOURCE carries the IDENT "hooks" —
// the scan's conservative host trigger.
PH_PLAIN_ANCHOR_SOURCE :: "get_juice_plugin :: () -> *X { return null; } @juice_plugin\n";
PH_HOOKS_ANCHOR_SOURCE :: "get_juice_plugin :: () -> *X { plugin.hooks; return null; } @juice_plugin\n";

// A prepared workspace over a scratch root with one declared member plugin
// (the declaration-driven scan surface: declaration order + member snapshot).
ph_prepared_with_member :: (root: string, member_name: string, anchor_source: string) -> Juice.Prepared_Workspace {
    build_seam_write(root, tprint("packages/%1/module.jai", member_name), anchor_source);
    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.discovery.has_package = true;
    prepared.discovery.root_package.name = "plugin-host-root";
    plugins: [..] Juice.Plugin_Declaration;
    array_add(*plugins, .{id = member_name, version = "0.1.0"});
    prepared.discovery.root_package.plugins = plugins;
    members: [..] Juice.Package;
    array_add(*members, .{name = "plugin-host-root", dir = root});
    array_add(*members, .{name = member_name, dir = path_slashes(tprint("%1/packages/%2", root, member_name))});
    prepared.discovery.member_packages = members;
    return prepared;
}

// ---------------------------------------------------------------------------
// Host spawn fakes
// ---------------------------------------------------------------------------

PH_HOST_SPAWN_CALLS: s64;
PH_HOST_SPAWN_EXIT: s32;
PH_HOST_SPAWN_TEXT: string;
PH_HOST_SPAWN_PATH: string;

ph_reset_host_spawn :: () {
    PH_HOST_SPAWN_CALLS = 0;
    PH_HOST_SPAWN_EXIT = 0;
    PH_HOST_SPAWN_TEXT = "";
    PH_HOST_SPAWN_PATH = "";
}

// The host spawn fake: records the call and, when a record text was staged,
// writes it to the staged records path (the production host writes the same
// file, so run_plugin_host's read/parse path runs for real).
ph_fake_host_spawn :: (host_path: string, import_dirs: [] string) -> Process_Result {
    PH_HOST_SPAWN_CALLS += 1;
    if PH_HOST_SPAWN_TEXT != "" && PH_HOST_SPAWN_PATH != "" {
        make_directory_if_it_does_not_exist(path_strip_filename(PH_HOST_SPAWN_PATH), recursive = true);
        write_entire_file(PH_HOST_SPAWN_PATH, PH_HOST_SPAWN_TEXT);
    }
    return .{exit_code = PH_HOST_SPAWN_EXIT};
}

// The host options over a scratch root (empty declaration list — the tests
// only need the landing paths and an empty config table).
ph_host_options :: (root: string) -> Plugin_Host_Options {
    prepared := test_command_prepared(root);
    stage: Prestep_Stage;
    stage.root_dir = root;
    return plugin_host_options(*prepared, *stage, "test");
}

ph_parse_error :: (text: string) -> string {
    return parse_plugin_host_records(text).error;
}

// ===========================================================================
// Prepare: the single scan / registration landing point
// ===========================================================================

test "Plugin prepare: declaration order drives the scan, shims and registration" {
    // The real plugin-workspace fixture through the production discovery face:
    // the declarations (zeta first, alpha second) drive the scan order, the
    // declared members get their import shims and one registration file lands
    // under target/plugins. The fixture's anchors carry no hooks face, so the
    // prepare reports no host need (a member lint-style plugin still gets the
    // registration — the test metaprogram consumes it).
    discovery, ok := discover_plugin_workspace_fixture("plugin-workspace");
    expect(ok && discovery.has_package);
    root := plugin_workspace_fixture_root("plugin-workspace");
    defer delete_directory_full(package_target_dir(root));

    prepared: Juice.Prepared_Workspace;
    prepared.discovery = discovery;
    prepare := prepare_workspace_plugins(*prepared);
    expect(prepare.ok);
    expect(prepare.diagnostics.count == 0);
    expect(prepare.hits.count == 2);
    expect(prepare.hits[0].module_name == "zeta-plugin");
    expect(prepare.hits[1].module_name == "alpha-plugin");
    expect(!prepare.member_hooks);
    expect(prepare.registration_path == workspace_plugin_registration_path(package_target_dir(root)));
    expect(file_contains(prepare.registration_path, "JUICE_PLUGIN_0 :: #import \"zeta-plugin\";"));
    expect(file_contains(prepare.registration_path, "JUICE_PLUGIN_1 :: #import \"alpha-plugin\";"));
    // The member import shims are the scan's ordinary member link.
    expect(file_exists(tprint("%1/zeta-plugin.jai", packages_dir(root))));
    expect(file_exists(tprint("%1/alpha-plugin.jai", packages_dir(root))));
}

test "Plugin prepare: zero member plugins write no registration and need no host" {
    root := ph_scratch("prepare-zero");
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(root, recursive = true));

    prepared := test_command_prepared(root);
    prepare := prepare_workspace_plugins(*prepared);
    expect(prepare.ok);
    expect(prepare.hits.count == 0);
    expect(prepare.registration_path == "");
    expect(!prepare.member_hooks);
    // Zero declarations cost nothing: not even the plugins directory exists.
    expect(!is_directory(target_plugins_dir(package_target_dir(root))));
}

test "Plugin prepare: the hooks face probe decides the host need" {
    // A lint-style member (anchor only) gets a registration but no host; a
    // member whose sources mention the hooks face marks member_hooks — the
    // conservative host trigger (the parent cannot load member values).
    plain_root := ph_scratch("prepare-plain");
    defer delete_directory_full(plain_root);
    plain_prepared := ph_prepared_with_member(plain_root, "plain-plugin", PH_PLAIN_ANCHOR_SOURCE);
    plain := prepare_workspace_plugins(*plain_prepared);
    expect(plain.ok);
    expect(plain.hits.count == 1);
    expect(plain.registration_path != "");
    expect(file_exists(plain.registration_path));
    expect(!plain.member_hooks);

    hooks_root := ph_scratch("prepare-hooks");
    defer delete_directory_full(hooks_root);
    hooks_prepared := ph_prepared_with_member(hooks_root, "hooks-plugin", PH_HOOKS_ANCHOR_SOURCE);
    hooks := prepare_workspace_plugins(*hooks_prepared);
    expect(hooks.ok);
    expect(hooks.hits.count == 1);
    expect(hooks.registration_path != "");
    expect(hooks.member_hooks);
}

// ===========================================================================
// Host protocol: encoding, strict parsing
// ===========================================================================

test "Plugin host protocol: encoded records round-trip through the shared pair" {
    // The parent-side pair (manifest.jai, shared with the host protocol) and
    // the strict parser agree on the %XX discipline: the delimiter, the escape
    // character and line breaks survive arbitrary values.
    raw := "tab\there | pipe % percent\r\nnewline";
    encoded := escape_record_value(raw);
    decoded, decode_ok := unescape_record_value(encoded);
    expect(decode_ok && decoded == raw);

    text := tprint("SUBSTITUTE=%1|%2\nDROP=%3\nDIAG=INFO|%4\nOK=1\n",
        escape_record_value("src/a.jai"),
        escape_record_value("C:/repo/target/.prestep/main.jai"),
        escape_record_value("src/dropped_tests.jai"),
        encoded);
    records := parse_plugin_host_records(text);
    expect(records.error == "");
    expect(records.ok);
    expect(records.substitutions.count == 1);
    expect(records.substitutions[0].original == "src/a.jai");
    expect(records.substitutions[0].replacement == "C:/repo/target/.prestep/main.jai");
    expect(records.drops.count == 1 && records.drops[0] == "src/dropped_tests.jai");
    expect(records.diagnostics.count == 1);
    expect(records.diagnostics[0].level == .INFO);
    expect(records.diagnostics[0].message == raw);

    // Lowercase hex (the host's encoder) and uppercase hex (a hand-written
    // record) both decode.
    upper := parse_plugin_host_records("DIAG=WARNING|a%7Cb%25c\nOK=0\n");
    expect(upper.error == "");
    expect(!upper.ok);
    expect(upper.diagnostics.count == 1);
    expect(upper.diagnostics[0].level == .WARNING);
    expect(upper.diagnostics[0].message == "a|b%c");
}

test "Plugin host protocol: strict parsing rejects malformed record files" {
    // Each malformed shape fails with a precise error — the parent never
    // reinterprets a damaged host product.
    expect(ph_parse_error("SUBSTITUTE=src/a.jai\nOK=1\n") != "");
    expect(ph_parse_error("UNKNOWN=value\nOK=1\n") != "");
    expect(ph_parse_error("DIAG=BOGUS|x\nOK=1\n") != "");
    expect(ph_parse_error("OK=2\n") != "");
    expect(ph_parse_error("OK=1\nOK=0\n") != "");
    expect(ph_parse_error("OK=1\nDROP=src/a.jai\n") != "");
    expect(ph_parse_error("DROP=src/a.jai\n") != "");
    expect(ph_parse_error("SUBSTITUTE=src/a.jai|C:/x%zz\nOK=1\n") != "");
    expect(ph_parse_error("SUBSTITUTE=|C:/x\nOK=1\n") != "");
    expect(ph_parse_error("DROP=\nOK=1\n") != "");
    expect(ph_parse_error("\nOK=1\n") != "");
    expect(ph_parse_error("no equals sign\nOK=1\n") != "");
    // A valid file with a trailing newline parses clean (the generated shape).
    expect(ph_parse_error("DROP=src/a.jai\nOK=1\n") == "");
}

// ===========================================================================
// Host run: spawn failure channels and staging
// ===========================================================================

test "Plugin host run: a nonzero exit, a missing record file and a stale record fail" {
    root := ph_scratch("host-run");
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(root, recursive = true));
    options := ph_host_options(root);

    // A nonzero exit fails even when a stale successful record file exists:
    // the runner removes the stale file before spawning, so an older success
    // can never mask a crashed host.
    expect(make_directory_if_it_does_not_exist(path_strip_filename(options.records_path), recursive = true));
    expect(write_entire_file(options.records_path, "OK=1\n"));
    ph_reset_host_spawn();
    PH_HOST_SPAWN_EXIT = 1;
    _, ok := run_plugin_host(options, ph_fake_host_spawn);
    expect(!ok);
    expect(PH_HOST_SPAWN_CALLS == 1);
    expect(!file_exists(options.records_path));
    // The driver was generated before the spawn.
    expect(file_exists(options.host_path));

    // Exit 0 with no record file: the host did not report a result.
    ph_reset_host_spawn();
    _, ok = run_plugin_host(options, ph_fake_host_spawn);
    expect(!ok);
    expect(PH_HOST_SPAWN_CALLS == 1);

    // Exit 0 with a well-formed record file: the parsed product comes back.
    // (Fresh names: Jai's tuple `:=` does not rebind an existing name, so
    // reusing `ok` here would leave it at its previous false value.)
    ph_reset_host_spawn();
    PH_HOST_SPAWN_PATH = options.records_path;
    PH_HOST_SPAWN_TEXT = "DROP=src/a.jai\nOK=1\n";
    host_records, host_ok := run_plugin_host(options, ph_fake_host_spawn);
    expect(host_ok);
    expect(host_records.error == "");
    expect(host_records.ok);
    expect(host_records.drops.count == 1 && host_records.drops[0] == "src/a.jai");

    // Exit 0 with a corrupted record file: parse failure, not a silent skip.
    ph_reset_host_spawn();
    PH_HOST_SPAWN_PATH = options.records_path;
    PH_HOST_SPAWN_TEXT = "OK=1\ngarbage\n";
    _, ok = run_plugin_host(options, ph_fake_host_spawn);
    expect(!ok);
}

test "Plugin host effects: rows merge through the stage-level rules" {
    // The happy path: the host's rows land in the stage exactly like an
    // in-process hook's prestep_add_* calls.
    stage: Prestep_Stage;
    diags: [..] Lifecycle_Diagnostic;
    records: Plugin_Host_Records;
    records.ok = true;
    array_add(*records.substitutions, .{original = "src/main.jai", replacement = "C:/repo/target/.prestep/main.jai"});
    array_add(*records.drops, "src/dropped_tests.jai");
    expect(apply_plugin_host_effects(*stage, records, *diags));
    expect(stage.substitutions.count == 1);
    expect(stage.substitutions[0].original == "src/main.jai");
    expect(stage.drops.count == 1 && stage.drops[0] == "src/dropped_tests.jai");
    expect(diags.count == 0);

    // A conflicting substitution (same original, different replacement) is a
    // stage failure with the rule's ERROR diagnostic.
    conflicting: Plugin_Host_Records;
    conflicting.ok = true;
    array_add(*conflicting.substitutions, .{original = "src/main.jai", replacement = "C:/other/main.jai"});
    expect(!apply_plugin_host_effects(*stage, conflicting, *diags));
    expect(diags.count == 1);
    expect(diags[0].level == .ERROR);
    expect(contains(diags[0].message, "conflicting source substitution: src/main.jai"));

    // A substitution and a drop on the same original conflict in either
    // order (the host rows go through the same stage API).
    cross: Plugin_Host_Records;
    cross.ok = true;
    array_add(*cross.substitutions, .{original = "src/keep.jai", replacement = "C:/keep.jai"});
    array_add(*cross.drops, "src/keep.jai");
    expect(!apply_plugin_host_effects(*stage, cross, *diags));
    expect(contains(diags[diags.count - 1].message, "drop conflicts with a source substitution: src/keep.jai"));

    // OK=0 (merge/resolver rejection) fails the command even without an ERROR
    // row; an OK=1 host whose diagnostics carry an ERROR fails too (the
    // dispatch failure rule).
    failed: Plugin_Host_Records;
    failed.ok = false;
    expect(!apply_plugin_host_effects(*stage, failed, *diags));
    error_row: Plugin_Host_Records;
    error_row.ok = true;
    array_add(*error_row.diagnostics, .{level = .ERROR, message = "host rejected"});
    expect(!apply_plugin_host_effects(*stage, error_row, *diags));
}

// ===========================================================================
// Host driver generation
// ===========================================================================

test "Plugin host driver: the generated text embeds the inputs and runs PRESTEP before hooks" {
    options: Plugin_Host_Options;
    options.root_dir = "C:/repo";
    options.mode = "test";
    options.member_dirs = string.["C:/repo/packages/prestep-plugin"];
    options.configs = Plugin_Config.[
        .{id = "prestep-plugin", version = "0.1.0", options = Option_Row.[.{key = "entry", value = "src/main.jai"}]},
    ];
    options.registration_path = "C:/repo/target/plugins/registration.jai";
    options.host_path = "C:/repo/target/plugins/host.jai";
    options.records_path = "C:/repo/target/plugins/host-records.txt";
    text := generate_plugin_host(options);

    // The face + registration imports and the #run main() shape.
    expect(find_index_from_left(text, "#import \"juice_core\";") >= 0);
    expect(find_index_from_left(text, "#load \"C:/repo/target/plugins/registration.jai\";") >= 0);
    expect(find_index_from_left(text, "#run {") >= 0);
    expect(find_index_from_left(text, "main();") >= 0);
    // The embedded inputs: root / mode / member dirs / config literals.
    expect(find_index_from_left(text, "HOST_ROOT :: \"C:/repo\";") >= 0);
    expect(find_index_from_left(text, "HOST_MODE :: \"test\";") >= 0);
    expect(find_index_from_left(text, "HOST_MEMBER_DIRS :: string.[\"C:/repo/packages/prestep-plugin\"];") >= 0);
    expect(find_index_from_left(text, "HOST_OUTPUT_PATH :: \"C:/repo/target/plugins/host-records.txt\";") >= 0);
    expect(find_index_from_left(text, "plugin_configs: [] Plugin_Config = Plugin_Config.[.{ id = \"prestep-plugin\", version = \"0.1.0\", options = Option_Row.[.{ key = \"entry\", value = \"src/main.jai\" }] }];") >= 0);
    // The resolve + dispatch + record emission chain.
    expect(find_index_from_left(text, "merged := merge_plugins(plugins);") >= 0);
    expect(find_index_from_left(text, "resolved := resolve_plugin_configs(merged.registry, plugin_configs);") >= 0);
    expect(find_index_from_left(text, "run_mounted_hooks(resolved.hook_table, .PRESTEP, .before, *lctx);") >= 0);
    expect(find_index_from_left(text, "SUBSTITUTE=%1|%2\\n") >= 0);
    expect(find_index_from_left(text, "DROP=%\\n") >= 0);
    expect(find_index_from_left(text, "DIAG=%1|%2\\n") >= 0);
    expect(find_index_from_left(text, "\"OK=1\\n\"") >= 0);
    expect(find_index_from_left(text, "\"OK=0\\n\"") >= 0);
}

// ===========================================================================
// Command wiring: single scan, host trigger, effect merge
// ===========================================================================

test "Test command: the prepare registration drives the metaprogram without a second scan" {
    // The COMPILE front consumes the prepare's registration path verbatim. The
    // prepared snapshot names a declared member whose directory does not exist:
    // a second scan would fail loudly, so a successful compile proves the front
    // never scans (ticket 060's single-scan rule).
    root := ph_scratch("compile-single-scan");
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(root, recursive = true));

    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.discovery.has_package = true;
    prepared.discovery.root_package.name = "compile-single-scan";
    plugins: [..] Juice.Plugin_Declaration;
    array_add(*plugins, .{id = "ghost-member", version = "0.1.0"});
    prepared.discovery.root_package.plugins = plugins;
    members: [..] Juice.Package;
    array_add(*members, .{name = "compile-single-scan", dir = root});
    array_add(*members, .{name = "ghost-member", dir = path_slashes(tprint("%1/packages/ghost-member", root))});
    prepared.discovery.member_packages = members;

    stage: Test_Compile_Stage;
    stage.prepared = *prepared;
    stage.transpile_dir = path_slashes(transpile_tree_dir(root));
    expect(make_directory_if_it_does_not_exist(stage.transpile_dir, recursive = true));
    stage.registration_path = "C:/sentinel/registration.jai";
    reset_test_command_seam();
    expect(test_compile_front(*stage, test_spawn_test_compiler));
    expect(test_test_spawn_calls == 1);
    generated, ok := read_entire_file(test_test_spawn_path);
    expect(ok);
    expect(find_index_from_left(generated, "#load \"C:/sentinel/registration.jai\";") >= 0);
    expect(find_index_from_left(generated, ".{ id = \"ghost-member\", version = \"0.1.0\", options = Option_Row.[] }") >= 0);
    expect(find_index_from_left(generated, tprint("set_working_directory(\"%1\");", root)) >= 0);
    // No scan landed a registration in this workspace.
    expect(!is_directory(target_plugins_dir(package_target_dir(root))));
}

test "Test command: zero member plugins never spawn the host" {
    root := ph_scratch("command-zero-host");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/a.jai", "test \"zero host\" { expect(true); }\n"));
    prepared := test_command_prepared(root);

    files: [..] Scan_File;
    array_add(*files, .{rel_path = "src/a.jai", abs_path = path_slashes(tprint("%1/src/a.jai", root))});
    reset_test_command_seam();
    ph_reset_host_spawn();
    test_test_collect_files = files;
    expect(test_prepared_workspace(*prepared, "", Hook_Registration.[], test_collect_test_files, test_spawn_test_compiler, ph_fake_host_spawn));
    expect(PH_HOST_SPAWN_CALLS == 0);
    expect(test_test_spawn_calls == 1);
    expect(!is_directory(target_plugins_dir(package_target_dir(root))));
    generated, ok := read_entire_file(test_test_spawn_path);
    expect(ok);
    // The zero-plugin generated text keeps the pre-plugin shape.
    expect(find_index_from_left(generated, "juice_core") < 0);
    expect(find_index_from_left(generated, "merged_plugins") < 0);
}

test "Test command: a member hooks plugin spawns the host and merges its effects" {
    root := ph_scratch("command-host-effects");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/a.jai", "test \"original\" { expect(true); }\n"));
    // The replacement lives in a dot directory: outside the real test scan
    // (dot entries are excluded at any depth) while the host substitution
    // still points at it.
    replacement := path_slashes(tprint("%1/.alt/a.jai", root));
    expect(build_seam_write(root, ".alt/a.jai", "ALT_MARKER :: true;\n\ntest \"alt\" { expect(true); }\n"));
    prepared := ph_prepared_with_member(root, "hooks-plugin", PH_HOOKS_ANCHOR_SOURCE);

    reset_test_command_seam();
    ph_reset_host_spawn();
    PH_HOST_SPAWN_PATH = plugin_host_records_path(package_target_dir(root));
    PH_HOST_SPAWN_TEXT = tprint("SUBSTITUTE=src/a.jai|%1\nOK=1\n", replacement);
    expect(test_prepared_workspace(*prepared, "", Hook_Registration.[], collect_test_files, test_spawn_test_compiler, ph_fake_host_spawn));
    expect(PH_HOST_SPAWN_CALLS == 1);
    expect(test_test_spawn_calls == 1);
    // The host driver and the prepare registration landed under target/.
    expect(file_exists(plugin_host_path(package_target_dir(root))));
    expect(file_exists(workspace_plugin_registration_path(package_target_dir(root))));

    // The host's substitution reached the TRANSPILE front: the view for
    // src/a.jai is the replacement's EXPAND view (the original never reads).
    runner, runner_ok := read_entire_file(tprint("%1/test_runner.jai", transpile_tree_dir(root)));
    expect(runner_ok);
    view_path := "";
    for view: test_program_package_view_paths(runner) {
        if ends_with(view, "/src/a.jai") view_path = view;
    }
    expect(view_path != "");
    view, view_ok := read_entire_file(view_path);
    expect(view_ok);
    expect(find_index_from_left(view, "ALT_MARKER") >= 0);
}

test "Test command: a host failure fails the command before compiling" {
    root := ph_scratch("command-host-fail");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/a.jai", "test \"host fail\" { expect(true); }\n"));
    prepared := ph_prepared_with_member(root, "hooks-plugin", PH_HOOKS_ANCHOR_SOURCE);

    reset_test_command_seam();
    ph_reset_host_spawn();
    PH_HOST_SPAWN_EXIT = 1;
    expect(!test_prepared_workspace(*prepared, "", Hook_Registration.[], collect_test_files, test_spawn_test_compiler, ph_fake_host_spawn));
    expect(PH_HOST_SPAWN_CALLS == 1);
    expect(test_test_spawn_calls == 0);
    expect(!file_exists(tprint("%1/test_runner.jai", transpile_tree_dir(root))));
}

// ===========================================================================
// E2E: the real executable against the member-plugin fixture
// ===========================================================================

test "E2E: the member PRESTEP plugin runs through the host and substitutes the build entry" {
    fixture := ph_fixture_root("plugin-prestep-fixture");
    delete_directory_full(package_target_dir(fixture));
    defer delete_directory_full(package_target_dir(fixture));

    result, output, _ := run_otter_child_at(fixture, string.["build"]);
    expect(expect_exit("prestep-build", result, 0, "build child"));
    // The host's INFO diagnostic survives the record file round-trip (its
    // message carries "|" and "%" — the escaping pin).
    expect(child_output_contains("prestep-build", output, "[juice] prestep|50% done"));
    expect(child_output_contains("prestep-build", output, "[juice Build] Compiling Target 'plugin-prestep-fixture' (src/main.jai) -> target/..."));

    // The build entry compiled the substitution: the artifact prints the
    // replacement view's line.
    artifact := target_artifact_path(package_target_dir(fixture), "plugin-prestep-fixture");
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("prestep-build artifact", run_result, 0, "build child"));
    expect(child_output_contains("prestep-build artifact", run_output, "prestep replacement entry"));
    expect(output_matches("prestep-build artifact", run_output, string.["original entry"], want = false));

    // The host driver and its record file are session artifacts under
    // target/plugins; the records carry the substitution, the drop and OK=1.
    host_path := plugin_host_path(package_target_dir(fixture));
    records_path := plugin_host_records_path(package_target_dir(fixture));
    expect(file_exists(host_path));
    records, records_ok := read_entire_file(records_path);
    expect(records_ok);
    expect(find_index_from_left(records, "SUBSTITUTE=src/main.jai|") >= 0);
    expect(find_index_from_left(records, "DROP=src/dropped_tests.jai") >= 0);
    expect(find_index_from_left(records, "OK=1") >= 0);
}

test "E2E: the member PRESTEP plugin's host effects drive the test program" {
    fixture := ph_fixture_root("plugin-prestep-fixture");
    delete_directory_full(package_target_dir(fixture));
    defer delete_directory_full(package_target_dir(fixture));

    result, output, _ := run_otter_child_at(fixture, string.["test"]);
    expect(expect_exit("prestep-test", result, 0, "test child"));
    expect(output_matches("prestep-test", output, string.[
        "[juice] prestep|50% done",
        "[test] juice_test_1",
        "1 passed, 0 failed",
    ]));
    // The dropped failing test never enters the test program.
    expect(output_matches("prestep-test", output, string.["the dropped test must never run"], want = false));

    // The substituted source's view comes from .prestep/main.jai while the
    // path mapping keeps the original package-relative path.
    metaprogram, metaprogram_ok := read_entire_file(tprint("%1/test_runner.jai", transpile_tree_dir(fixture)));
    expect(metaprogram_ok);
    expect(find_index_from_left(metaprogram, "original = \"src/main.jai\"") >= 0);
    expect(find_index_from_left(metaprogram, "original = \"src/dropped_tests.jai\"") < 0);
}

test "E2E: a member plugin options rejection fails the build through the host" {
    scratch := ph_fixture_copy("options-error", "plugin-prestep-fixture");
    defer delete_directory_full(scratch);
    // Re-declare the same member with an unknown option key: the host's
    // resolver rejects before any hook runs, the record file reports OK=0 and
    // the command fails without an artifact.
    expect(build_seam_write(scratch, "package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"plugin-prestep-fixture\",\n    version = \"0.1.0\",\n    type    = .BIN,\n    targets = Target.[.{name = \"plugin-prestep-fixture\", main_file = \"src/main.jai\"}],\n    workspace = .{ members = string.[\"packages/prestep-plugin\"] },\n    plugins = Plugin_Declaration.[\n        .{id = \"prestep-plugin\", version = \"0.1.0\", options = Plugin_Option.[.{key = \"nope\", value = \"x\"}]},\n    ],\n};\n"));

    result, output, _ := run_otter_child_at(scratch, string.["build"]);
    expect(expect_exit("prestep-options", result, 1, "build child"));
    expect(child_output_contains("prestep-options", output, "[juice ERROR] unknown plugin option: prestep-plugin (nope)"));
    expect(child_output_contains("prestep-options", output, "[juice ERROR] The plugin host reported a pre-step failure."));
    expect(!file_exists(target_artifact_path(package_target_dir(scratch), "plugin-prestep-fixture")));
    records, records_ok := read_entire_file(plugin_host_records_path(package_target_dir(scratch)));
    expect(records_ok);
    expect(find_index_from_left(records, "DIAG=ERROR|unknown plugin option: prestep-plugin (nope)") >= 0);
    expect(find_index_from_left(records, "OK=0") >= 0);
}

test "E2E: a host merge conflict fails the build before compiling" {
    scratch := ph_scratch("merge-negative");
    defer delete_directory_full(scratch);
    // Two declared members provide the same plugin id: the host's
    // merge_plugins rejects the duplicate registration and reports OK=0.
    plugin_source := ph_fixture_root("plugin-prestep-fixture");
    expect(make_directory_if_it_does_not_exist(tprint("%1/packages", scratch), recursive = true));
    copy_directory(tprint("%1/packages/prestep-plugin", plugin_source), tprint("%1/packages/copy-a", scratch));
    copy_directory(tprint("%1/packages/prestep-plugin", plugin_source), tprint("%1/packages/copy-b", scratch));
    expect(build_seam_write(scratch, "packages/copy-a/package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"copy-a\",\n    version = \"0.1.0\",\n    type    = .LIB,\n};\n"));
    expect(build_seam_write(scratch, "packages/copy-b/package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"copy-b\",\n    version = \"0.1.0\",\n    type    = .LIB,\n};\n"));
    expect(build_seam_write(scratch, "src/main.jai", "#import \"Basic\";\n\nmain :: () { print(\"merge\\n\"); }\n"));
    expect(build_seam_write(scratch, "package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"merge-negative\",\n    version = \"0.1.0\",\n    type    = .BIN,\n    targets = Target.[.{name = \"merge-negative\", main_file = \"src/main.jai\"}],\n    workspace = .{ members = string.[\"packages/copy-a\", \"packages/copy-b\"] },\n    plugins = Plugin_Declaration.[\n        .{id = \"copy-a\", version = \"0.1.0\"},\n        .{id = \"copy-b\", version = \"0.1.0\"},\n    ],\n};\n"));

    result, output, _ := run_otter_child_at(scratch, string.["build"]);
    expect(expect_exit("prestep-merge", result, 1, "build child"));
    expect(child_output_contains("prestep-merge", output, "[juice ERROR] duplicate plugin registration: prestep-plugin"));
    expect(child_output_contains("prestep-merge", output, "[juice ERROR] The plugin host reported a pre-step failure."));
    expect(!file_exists(target_artifact_path(package_target_dir(scratch), "merge-negative")));
}

test "E2E: a host compile crash fails the build with the host error" {
    scratch := ph_fixture_copy("host-crash", "plugin-prestep-fixture");
    defer delete_directory_full(scratch);
    // A syntactically broken member plugin makes the generated host's compile
    // fail: nonzero exit, the stderr passes through and the command fails
    // before any build compile.
    module_path := tprint("%1/packages/prestep-plugin/module.jai", scratch);
    module_source, module_ok := read_entire_file(module_path);
    expect(module_ok);
    expect(write_entire_file(module_path, tprint("%1\nbroken declaration :: (\n", module_source)));

    result, output, errors := run_otter_child_at(scratch, string.["build"]);
    expect(expect_exit("prestep-crash", result, 1, "build child"));
    expect(child_output_contains("prestep-crash", output, "[juice ERROR] Plugin host failed (exit "));
    expect(child_output_contains("prestep-crash", output, "[juice ERROR] Command 'build' failed while executing 'build'."));
    // The child compiler's diagnostics pass through on stderr.
    expect(child_output_contains("prestep-crash", errors, "module.jai"));
    expect(!file_exists(target_artifact_path(package_target_dir(scratch), "plugin-prestep-fixture")));
}

test "E2E: a package without plugins never spawns the host" {
    root := ph_scratch("no-plugins-e2e");
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"no-plugins\",\n    version = \"0.1.0\",\n    type    = .BIN,\n    targets = Target.[.{name = \"no-plugins\", main_file = \"src/main.jai\"}],\n};\n"));
    expect(build_seam_write(root, "src/main.jai", "#import \"Basic\";\n\nmain :: () { print(\"plain\\n\"); }\n"));

    result, output, _ := run_otter_child_at(root, string.["build"]);
    expect(expect_exit("prestep-zero", result, 0, "build child"));
    expect(child_output_contains("prestep-zero", output, "[juice] Build completed successfully!"));
    expect(!is_directory(target_plugins_dir(package_target_dir(root))));
    expect(!file_exists(plugin_host_path(package_target_dir(root))));
}
