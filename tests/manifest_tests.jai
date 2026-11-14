#import "Basic";
#import "Testing";

SCHEMA_MINIMAL_PROTOCOL :: "SCHEMA=2\nNAME=fixture\nVERSION=1\nDESCRIPTION=\x01juice-omitted\nDEFAULT_RUN=\x01juice-omitted\nWORKSPACE=0\nMEMBERS=-1\nEXCLUDES=-1\nDEFAULT_MEMBERS=-1\nMODULES=-1\nEXECUTABLES=-1\nDEPENDENCIES=-1\nPLUGINS=-1\n";
SCHEMA_BUILTIN_RECORD :: "PLUGIN=\x01juice-omitted|load|0|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted\n";
FULL_PROTOCOL :: "SCHEMA=2\nNAME=manifest-fixture\nVERSION=1.2.3\nDESCRIPTION=Evaluator protocol E2E fixture.\nDEFAULT_RUN=app\nWORKSPACE=1\nMEMBERS=2\nMEMBER=packages/a\nMEMBER=packages/b\nEXCLUDES=1\nEXCLUDE=packages/skip\nDEFAULT_MEMBERS=1\nDEFAULT_MEMBER=packages/a\nMODULES=1\nMODULE=Api|src/module.jai\nEXECUTABLES=1\nEXECUTABLE=app|src/main.jai\nDEPENDENCIES=3\nDEP=dep_a|1|../a|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|1\nDEP_MODULE=lib|Api|LocalApi\nDEP=dep_b|2|\x01juice-omitted|https://example.test/dep-b.git|\x01juice-omitted|v1|\x01juice-omitted|-1\nDEP=dep_member|3|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|1\nDEP_MODULE=packages/b|Bee|BeeAlias\nPLUGINS=3\nPLUGIN=\x01juice-omitted|load|0|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted\nPLUGIN=\x01juice-omitted|test-block|0|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted\nPLUGIN=external-lint|\x01juice-omitted|1|../lint-plugin|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|src|Lint|LintAlias\nPLUGIN_OPTION=mode|strict\n";

test "Protocol: a complete manifest parses into every field" {
    result := parse_manifest_data_strict(FULL_PROTOCOL);
    expect(result.success);
    pkg := result.package;
    expect(pkg.name == "manifest-fixture" && pkg.version == "1.2.3");
    expect(pkg.has_package && pkg.has_workspace);
    expect(pkg.description == "Evaluator protocol E2E fixture.");
    expect(pkg.default_run == "app");
    expect(pkg.modules.count == 1 && pkg.modules[0].name == "Api" && pkg.modules[0].entry == "src/module.jai");
    expect(!pkg.modules_omitted && !pkg.executables_omitted);
    expect(pkg.executables.count == 1 && pkg.executables[0].name == "app" && pkg.executables[0].entry == "src/main.jai");
    expect(pkg.workspace.members.count == 2 && pkg.workspace.members[0] == "packages/a" && pkg.workspace.members[1] == "packages/b");
    expect(pkg.workspace.exclude.count == 1 && pkg.workspace.exclude[0] == "packages/skip");
    expect(pkg.workspace.default_members.count == 1 && pkg.workspace.default_members[0] == "packages/a");
    expect(!pkg.workspace.default_members_omitted && !pkg.plugins_omitted);
    expect(pkg.dependencies.count == 3);
    expect(!pkg.dependencies[0].modules_omitted && pkg.dependencies[1].modules_omitted && !pkg.dependencies[2].modules_omitted);
    expect(pkg.dependencies[0].name == "dep_a" && pkg.dependencies[0].source.kind == .PATH && pkg.dependencies[0].source.path == "../a");
    expect(pkg.dependencies[0].modules.count == 1 && pkg.dependencies[0].modules[0].path == "lib" && pkg.dependencies[0].modules[0].name == "Api" && pkg.dependencies[0].modules[0].alias == "LocalApi");
    expect(pkg.dependencies[1].name == "dep_b" && pkg.dependencies[1].source.kind == .GIT && pkg.dependencies[1].source.url == "https://example.test/dep-b.git" && pkg.dependencies[1].source.tag == "v1");
    expect(pkg.dependencies[2].name == "dep_member" && pkg.dependencies[2].source.kind == .WORKSPACE);
    expect(pkg.dependencies[2].modules.count == 1 && pkg.dependencies[2].modules[0].path == "packages/b" && pkg.dependencies[2].modules[0].name == "Bee" && pkg.dependencies[2].modules[0].alias == "BeeAlias");
    expect(pkg.plugins.count == 3 && pkg.plugins[0].builtin && pkg.plugins[1].builtin && !pkg.plugins[2].builtin);
    expect(pkg.plugins[0].id == "load" && pkg.plugins[1].id == "test-block");
    expect(pkg.plugins[2].id == "external-lint" && pkg.plugins[2].source.kind == .PATH && pkg.plugins[2].source.path == "../lint-plugin");
    expect(pkg.plugins[2].module.path == "src" && pkg.plugins[2].module.name == "Lint" && pkg.plugins[2].module.alias == "LintAlias");
    expect(pkg.plugins[2].options.count == 1 && pkg.plugins[2].options[0].key == "mode" && pkg.plugins[2].options[0].value == "strict");
    expect(pkg.fields.count > 0);

    // Each Git selector has its own wire position; empty selectors stay omitted.
    branch_protocol := replace(FULL_PROTOCOL, "https://example.test/dep-b.git|\x01juice-omitted|v1|\x01juice-omitted", "https://example.test/dep-b.git|main|\x01juice-omitted|\x01juice-omitted");
    branch_result := parse_manifest_data_strict(branch_protocol);
    expect(branch_result.success);
    expect(branch_result.package.dependencies[1].source.branch == "main");
    expect(branch_result.package.dependencies[1].source.tag == "" && branch_result.package.dependencies[1].source.rev == "");
    revision_protocol := replace(FULL_PROTOCOL, "https://example.test/dep-b.git|\x01juice-omitted|v1|\x01juice-omitted", "https://example.test/dep-b.git|\x01juice-omitted|\x01juice-omitted|deadbeef");
    revision_result := parse_manifest_data_strict(revision_protocol);
    expect(revision_result.success);
    expect(revision_result.package.dependencies[1].source.rev == "deadbeef");
    expect(revision_result.package.dependencies[1].source.branch == "" && revision_result.package.dependencies[1].source.tag == "");

    git_plugin_protocol := replace(FULL_PROTOCOL, "external-lint|\x01juice-omitted|1|../lint-plugin|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted|\x01juice-omitted", "external-lint|\x01juice-omitted|2|\x01juice-omitted|https://example.test/plugin.git|main|\x01juice-omitted|\x01juice-omitted");
    git_plugin_result := parse_manifest_data_strict(git_plugin_protocol);
    expect(git_plugin_result.success);
    expect(git_plugin_result.package.plugins[2].source.kind == .GIT);
    expect(git_plugin_result.package.plugins[2].source.url == "https://example.test/plugin.git" && git_plugin_result.package.plugins[2].source.branch == "main");
    workspace_plugin_protocol := replace(FULL_PROTOCOL, "external-lint|\x01juice-omitted|1|../lint-plugin", "external-lint|\x01juice-omitted|3|\x01juice-omitted");
    workspace_plugin_result := parse_manifest_data_strict(workspace_plugin_protocol);
    expect(workspace_plugin_result.success);
    expect(workspace_plugin_result.package.plugins[2].source.kind == .WORKSPACE);
    expect(workspace_plugin_result.package.plugins[2].module.path == "src");
}
test "Protocol: unknown records are rejected with a line number" {
    result := parse_manifest_data_strict("NAME=x\nVERSION=1\nBOGUS=y\n");
    expect(!result.success && result.line_number == 3);
    expect(result.error_message == "Unknown manifest record: BOGUS; see docs/migrations/package-declarations.md");
}
test "Protocol: duplicate single-value records are rejected with a line number" {
    result := parse_manifest_data_strict("NAME=a\nVERSION=1\nDESCRIPTION=x\nNAME=b\n");
    expect(!result.success && result.line_number == 4 && result.error_message == "Duplicate NAME record.");
    result = parse_manifest_data_strict("NAME=a\nVERSION=1\nVERSION=2\n");
    expect(!result.success && result.line_number == 3 && result.error_message == "Duplicate VERSION record.");
}
test "Protocol: malformed records carry their line number" {
    result := parse_manifest_data_strict("NAME=x\nnoequals\n");
    expect(!result.success && result.line_number == 2 && result.error_message == "Malformed manifest record.");
}
test "Protocol: an empty key is malformed" {
    result := parse_manifest_data_strict("=value\n");
    expect(!result.success && result.line_number == 1 && result.error_message == "Malformed manifest record.");
}
test "Protocol: all retired TYPE values are rejected" {
    for value: string.["0", "1", "2", ""] {
        result := parse_manifest_data_strict(tprint("TYPE=%\n", value));
        expect(!result.success && result.line_number == 1 && result.error_message == "Unknown manifest record: TYPE; see docs/migrations/package-declarations.md");
    }
}
test "Protocol: invalid TYPE is also rejected" {
    for value: string.["7", "1x"] {
        result := parse_manifest_data_strict(tprint("TYPE=%\n", value));
        expect(!result.success && result.line_number == 1 && result.error_message == "Unknown manifest record: TYPE; see docs/migrations/package-declarations.md");
    }
}
test "Protocol: executable shape errors are rejected" {
    result := parse_manifest_data_strict("EXECUTABLE=app\n");
    expect(!result.success && result.line_number == 1 && result.error_message == "Product requires name|entry.");
    result = parse_manifest_data_strict("EXECUTABLE=app|src/main.jai|extra\n");
    expect(!result.success && result.line_number == 1 && result.error_message == "Product requires name|entry.");
}
test "Protocol: DEP shape errors are rejected" {
    for value: string.["a|1|2", "a|1|2|3|4"] {
        result := parse_manifest_data_strict(tprint("DEP=%\n", value));
        expect(!result.success && result.line_number == 1 && result.error_message == "DEP requires name, source and module count.");
    }
}
test "Protocol: PLUGIN shape errors and duplicates are rejected" {
    for value: string.["load", "load|1|extra"] {
        result := parse_manifest_data_strict(tprint("PLUGIN=%\n", value));
        expect(!result.success && result.line_number == 1 && result.error_message == "PLUGIN requires id, builtin, source and module selection.");
    }
    result := parse_manifest_data_strict(tprint("%1%2", SCHEMA_BUILTIN_RECORD, SCHEMA_BUILTIN_RECORD));
    expect(!result.success && result.line_number == 2 && result.error_message == "Duplicate PLUGIN record.");
}
test "Protocol: PLUGIN_OPTION shape encoding order and duplicate keys" {
    result := parse_manifest_data_strict(tprint("%PLUGIN_OPTION=config\n", SCHEMA_BUILTIN_RECORD));
    expect(!result.success && result.line_number == 2 && result.error_message == "PLUGIN_OPTION requires a plugin and key|value.");
    protocol := replace(SCHEMA_MINIMAL_PROTOCOL, "PLUGINS=-1", "PLUGINS=1");
    result = parse_manifest_data_strict(tprint("%1%2%3", protocol, SCHEMA_BUILTIN_RECORD, "PLUGIN_OPTION=config|a%7Cb%25c%0Ad\n"));
    expect(result.success && result.package.plugins.count == 1);
    expect(result.package.plugins[0].options.count == 1);
    expect(result.package.plugins[0].options[0].key == "config" && result.package.plugins[0].options[0].value == "a|b%c\nd");
    result = parse_manifest_data_strict("PLUGIN_OPTION=config|x\n");
    expect(!result.success && result.line_number == 1 && result.error_message == "PLUGIN_OPTION requires a plugin and key|value.");
    result = parse_manifest_data_strict(tprint("%PLUGIN_OPTION=config|x\nPLUGIN_OPTION=config|y\n", SCHEMA_BUILTIN_RECORD));
    expect(!result.success && result.line_number == 3 && result.error_message == "Duplicate plugin option key.");
    result = parse_manifest_data_strict(tprint("%PLUGIN_OPTION=config|%", SCHEMA_BUILTIN_RECORD, "%zz\n"));
    expect(!result.success && result.line_number == 2 && result.error_message == "Invalid %XX escape in manifest record.");
}
test "Protocol: record-value encoding round-trips" {
    raw := "a|b%c\nd\re";
    encoded := escape_record_value(raw);
    expect(encoded == "a%7cb%25c%0ad%0de");
    decoded, ok := unescape_record_value(encoded);
    expect(ok && decoded == raw);
    expect(escape_record_value("plain") == "plain");
    plain, plain_ok := unescape_record_value(escape_record_value(""));
    expect(plain_ok && plain == "");
}
test "Protocol: empty MEMBER and EXCLUDE records are rejected independently" {
    result := parse_manifest_data_strict("MEMBER=\n");
    expect(!result.success && result.line_number == 1 && result.error_message == "MEMBER cannot be empty.");
    result = parse_manifest_data_strict("EXCLUDE=\n");
    expect(!result.success && result.line_number == 1 && result.error_message == "EXCLUDE cannot be empty.");
}
test "Protocol: empty lines and CRLF are tolerated" {
    result := parse_manifest_data_strict(replace(SCHEMA_MINIMAL_PROTOCOL, "\n", "\r\n\r\n"));
    expect(result.success && result.package.name == "fixture" && result.package.version == "1");
    result = parse_manifest_data_strict("NAME=x\r\n\r\nBOGUS=y\r\n");
    expect(!result.success && result.line_number == 3);
}
test "Protocol: the convenience parser keeps the same shape" {
    pkg := parse_manifest_data(SCHEMA_MINIMAL_PROTOCOL);
    expect(pkg.name == "fixture");
}

test "Loader: temp file names are stable per manifest and distinct per package" {
    src_a, out_a := manifest_temp_file_names("C:/cache", "C:/pkg/a");
    src_b, out_b := manifest_temp_file_names("C:/cache", "C:/pkg/a");
    expect(src_a == src_b && out_a == out_b);
    expect(src_a != out_a);

    src_c, out_c := manifest_temp_file_names("C:/cache", "C:/pkg/b");
    expect(src_a != src_c && out_a != out_c);
}

// ---------------------------------------------------------------------------
// Loader: the spawn seam drives the retry loop deterministically.
// ---------------------------------------------------------------------------

test "Loader: a write-failure exit code 2 is retried at most twice, then fails" {
    reset_eval_spawn();
    EVAL_SPAWN.exit_codes = s32.[2, 2, 2];

    cache := otter_scratch("manifest-retry-cache");
    fixture := tprint("%1/tests/data/manifest-fixture", otter_root());
    pkg, ok := load_package_manifest(cache, fixture, "ignored", test_eval_spawn);
    expect(!ok);
    expect(pkg.name == "");
    expect(EVAL_SPAWN.calls == 3);
}

test "Loader: a retried evaluator succeeds on the final attempt" {
    reset_eval_spawn();
    EVAL_SPAWN.exit_codes = s32.[2, 2, 0];
    EVAL_SPAWN.data_output = SCHEMA_MINIMAL_PROTOCOL;

    cache := otter_scratch("manifest-retry-cache");
    fixture := tprint("%1/tests/data/manifest-fixture", otter_root());
    pkg, ok := load_package_manifest(cache, fixture, "C:/modules/injected", test_eval_spawn);
    expect(ok);
    expect(EVAL_SPAWN.calls == 3);
    expect(pkg.name == "fixture" && pkg.version == "1");
    expect(EVAL_SPAWN.last_modules_dir == "C:/modules/injected");
}

test "Loader: any other nonzero exit fails immediately without retries" {
    reset_eval_spawn();
    EVAL_SPAWN.exit_codes = s32.[1];

    cache := otter_scratch("manifest-retry-cache");
    fixture := tprint("%1/tests/data/manifest-fixture", otter_root());
    _, ok := load_package_manifest(cache, fixture, "", test_eval_spawn);
    expect(!ok);
    expect(EVAL_SPAWN.calls == 1);
}

test "Loader: a missing package.jai short-circuits without spawning" {
    reset_eval_spawn();

    _, ok := load_package_manifest(otter_scratch("manifest-retry-cache"),
                                   tprint("%1/tests/data", otter_root()), "", test_eval_spawn);
    expect(!ok);
    expect(EVAL_SPAWN.calls == 0);
}

test "Loader: an invalid protocol is rejected after the child finishes" {
    reset_eval_spawn();
    EVAL_SPAWN.data_output = "NAME=x\nBOGUS=y\n";

    cache := otter_scratch("manifest-retry-cache");
    fixture := tprint("%1/tests/data/manifest-fixture", otter_root());
    _, ok := load_package_manifest(cache, fixture, "", test_eval_spawn);
    expect(!ok);
}

test "Loader: unknown plugin ids load (semantic validation moved to plugin preparation)" {
    // Ticket 056 removed the transitional declaration gate: the loader only
    // parses the protocol structurally. An unknown id is caught later by the
    // declaration-driven workspace scan / resolver (build/test plugin
    // preparation), so the load itself succeeds.
    reset_eval_spawn();
    EVAL_SPAWN.data_output = tprint("%1%2", replace(SCHEMA_MINIMAL_PROTOCOL, "PLUGINS=-1", "PLUGINS=1"), replace(SCHEMA_BUILTIN_RECORD, "load", "mystery"));

    cache := otter_scratch("manifest-retry-cache");
    fixture := tprint("%1/tests/data/manifest-fixture", otter_root());
    pkg, ok := load_package_manifest(cache, fixture, "", test_eval_spawn);
    expect(ok);
    expect(pkg.plugins.count == 1);
    expect(pkg.plugins[0].id == "mystery" && pkg.plugins[0].builtin);
}

test "Loader: a successful load backfills the package dir" {
    reset_eval_spawn();
    EVAL_SPAWN.data_output = SCHEMA_MINIMAL_PROTOCOL;

    cache := otter_scratch("manifest-retry-cache");
    fixture := tprint("%1/tests/data/manifest-fixture", otter_root());
    pkg, ok := load_package_manifest(cache, fixture, "", test_eval_spawn);
    expect(ok);
    expect(pkg.dir == fixture);
}

test "Loader: a missing data file after exit 0 fails the read" {
    // The package root never evaluates through the fake (the fake writes
    // nothing and exits 0), so the temp data file must not exist — use the
    // otter root as the package dir to keep this test's temp names distinct
    // from the fixture's (the fixture's data file may exist from an earlier
    // test in this program).
    reset_eval_spawn();

    _, ok := load_package_manifest(otter_scratch("manifest-retry-cache"),
                                   otter_root(), "", test_eval_spawn);
    expect(!ok);
    expect(EVAL_SPAWN.calls == 1);
}

// ---------------------------------------------------------------------------
// E2E: a real jai child evaluates the fixture manifest.
// ---------------------------------------------------------------------------

test "E2E: a real jai child evaluates the fixture manifest protocol" {
    expect(ensure_published_modules());
    cache := otter_scratch("manifest-e2e-cache");
    fixture := tprint("%1/tests/data/manifest-fixture", otter_root());
    // The evaluator child resolves `#import "Juice"` from the published
    // modules directory (ticket 033's switch — the seeds retired with
    // ticket 032; the fixture manifest compiles against the published face).
    pkg, ok := load_package_manifest(cache, fixture, plugin_face_modules_dir());
    expect(ok);
    if !ok return;

    expect(pkg.name == "manifest-fixture");
    expect(pkg.version == "1.2.3");
    expect(pkg.has_package);
    expect(pkg.description == "Evaluator protocol E2E fixture.");
    expect(pkg.default_run == "app");
    expect(pkg.has_workspace);
    expect(pkg.modules.count == 1 && pkg.modules[0].name == "Api" && pkg.modules[0].entry == "src/module.jai");
    expect(pkg.executables.count == 1 && pkg.executables[0].name == "app" && pkg.executables[0].entry == "src/main.jai");
    expect(pkg.plugins.count == 3);
    expect(pkg.plugins[0].id == "load" && pkg.plugins[0].builtin);
    expect(pkg.plugins[1].id == "test-block" && pkg.plugins[1].builtin);
    expect(pkg.plugins[2].id == "external-lint" && !pkg.plugins[2].builtin);
    expect(pkg.plugins[2].source.kind == .PATH && pkg.plugins[2].source.path == "../lint-plugin");
    expect(pkg.plugins[2].module.path == "src" && pkg.plugins[2].module.name == "Lint" && pkg.plugins[2].module.alias == "LintAlias");
    expect(pkg.plugins[0].options.count == 0 && pkg.plugins[2].options.count == 1);
    expect(pkg.plugins[2].options[0].key == "mode" && pkg.plugins[2].options[0].value == "strict");
    expect(pkg.workspace.members.count == 2);
    expect(pkg.workspace.members[0] == "packages/a" && pkg.workspace.members[1] == "packages/b");
    expect(pkg.workspace.exclude.count == 1 && pkg.workspace.exclude[0] == "packages/skip");
    expect(pkg.workspace.default_members.count == 1 && pkg.workspace.default_members[0] == "packages/a");
    expect(!pkg.workspace.default_members_omitted && !pkg.plugins_omitted);
    expect(pkg.dependencies.count == 3);
    expect(!pkg.dependencies[0].modules_omitted && pkg.dependencies[1].modules_omitted && !pkg.dependencies[2].modules_omitted);
    expect(pkg.dependencies[0].name == "dep_a" && pkg.dependencies[0].source.kind == .PATH && pkg.dependencies[0].modules.count == 1);
    expect(pkg.dependencies[0].source.path == "../a");
    expect(pkg.dependencies[0].modules[0].path == "lib" && pkg.dependencies[0].modules[0].name == "Api" && pkg.dependencies[0].modules[0].alias == "LocalApi");
    expect(pkg.dependencies[1].name == "dep_b" && pkg.dependencies[1].source.kind == .GIT && pkg.dependencies[1].source.url == "https://example.test/dep-b.git" && pkg.dependencies[1].source.tag == "v1");
    expect(pkg.dependencies[2].name == "dep_member" && pkg.dependencies[2].source.kind == .WORKSPACE);
    expect(pkg.dependencies[2].modules.count == 1);
    expect(pkg.dependencies[2].modules[0].path == "packages/b" && pkg.dependencies[2].modules[0].name == "Bee" && pkg.dependencies[2].modules[0].alias == "BeeAlias");
    expect(pkg.dir == fixture);
}

// ---------------------------------------------------------------------------
// E2E: the bad-manifest family (ticket 014). Each fixture declares a
// violation a real package.jai can produce — the evaluator child evaluates
// it, the parent's strict parser (or the plugin declaration gate) rejects
// it, and the whole chain's error text is locked byte for byte.
// The real otter exe runs `build` on the fixture (run_otter_child_at seeds
// the bootstrap modules), discovery fails at the root manifest, and nothing
// is created. The parser branches a real declaration cannot produce
// (unknown keys, duplicate single-value records, malformed lines, TARGET/
// DEP shape errors) stay in-process — the evaluator only ever prints the
// eleven well-formed record kinds, so those lines are unreachable through
// the real chain without tampering the data file.
// ---------------------------------------------------------------------------

test "E2E: a duplicate plugin declaration fails discovery byte-for-byte" {
    fixture_root := path_slashes(tprint("%1/tests/data/bad-manifest-duplicate-plugin", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, _ := run_otter_child_at(fixture_root, string.["build"]);
    expect(expect_exit("bad-manifest-duplicate-plugin", result, 1, "build child"));
    expect(child_output_contains("bad-manifest-duplicate-plugin", output,
        "[juice ERROR] Invalid manifest protocol at "));
    expect(child_output_contains("bad-manifest-duplicate-plugin", output,
        "tests/data/bad-manifest-duplicate-plugin/package.jai (line 15): Duplicate PLUGIN record."));
    expect(child_output_contains("bad-manifest-duplicate-plugin", output,
        "[juice ERROR] Existing package.jai is invalid."));
    expect(child_output_contains("bad-manifest-duplicate-plugin", output,
        "[juice ERROR] Command 'build' failed while executing 'build'."));
    expect(output_matches("bad-manifest-duplicate-plugin", output, string.[
        "[juice] Package 'bad_dup_plugin' (v0.1.0) discovered.",
        "[juice] Build completed successfully!",
    ], want = false));
    expect(!file_exists(package_target_dir(fixture_root)));
}

test "E2E: an empty member path fails discovery byte-for-byte" {
    fixture_root := path_slashes(tprint("%1/tests/data/bad-manifest-empty-member", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, _ := run_otter_child_at(fixture_root, string.["build"]);
    expect(expect_exit("bad-manifest-empty-member", result, 1, "build child"));
    expect(child_output_contains("bad-manifest-empty-member", output,
        "tests/data/bad-manifest-empty-member/package.jai (line 8): MEMBER cannot be empty."));
    expect(child_output_contains("bad-manifest-empty-member", output,
        "[juice ERROR] Existing package.jai is invalid."));
    expect(output_matches("bad-manifest-empty-member", output, string.["[juice] Build completed successfully!"], want = false));
    expect(!file_exists(package_target_dir(fixture_root)));
}

test "E2E: an empty exclude path fails discovery byte-for-byte" {
    fixture_root := path_slashes(tprint("%1/tests/data/bad-manifest-empty-exclude", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, _ := run_otter_child_at(fixture_root, string.["build"]);
    expect(expect_exit("bad-manifest-empty-exclude", result, 1, "build child"));
    expect(child_output_contains("bad-manifest-empty-exclude", output,
        "tests/data/bad-manifest-empty-exclude/package.jai (line 9): EXCLUDE cannot be empty."));
    expect(child_output_contains("bad-manifest-empty-exclude", output,
        "[juice ERROR] Existing package.jai is invalid."));
    expect(output_matches("bad-manifest-empty-exclude", output, string.["[juice] Build completed successfully!"], want = false));
    expect(!file_exists(package_target_dir(fixture_root)));
}

test "E2E: the removed type field fails declaration compilation" {
    fixture_root := path_slashes(tprint("%1/tests/data/bad-manifest-invalid-type", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, errors := run_otter_child_at(fixture_root, string.["build"]);
    expect(expect_exit("bad-manifest-invalid-type", result, 1, "build child"));
    expect(contains(errors, "'type' is not a member of Package") || contains(output, "'type' is not a member of Package"));
    expect(child_output_contains("bad-manifest-invalid-type", output, "docs/migrations/package-declarations.md"));
    expect(child_output_contains("bad-manifest-invalid-type", output,
        "Failed to evaluate manifest at"));
    expect(child_output_contains("bad-manifest-invalid-type", output,
        "[juice ERROR] Existing package.jai is invalid."));
    expect(output_matches("bad-manifest-invalid-type", output, string.["[juice] Build completed successfully!"], want = false));
    expect(!file_exists(package_target_dir(fixture_root)));
}

test "E2E: a manifest using the removed jaix field fails evaluation" {
    // Breaking-change fixture (ticket 055): `Package.jaix` was removed on
    // 2026-10-21, so the evaluator child cannot compile the manifest. The
    // failure path is the evaluator spawn failure, not a gate.
    fixture_root := path_slashes(tprint("%1/tests/data/bad-manifest-jaix-exe", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, _ := run_otter_child_at(fixture_root, string.["build"]);
    expect(expect_exit("bad-manifest-jaix-exe", result, 1, "build child"));
    expect(child_output_contains("bad-manifest-jaix-exe", output,
        "[juice ERROR] Failed to evaluate manifest at "));
    expect(child_output_contains("bad-manifest-jaix-exe", output, "jaix"));
    expect(child_output_contains("bad-manifest-jaix-exe", output,
        "[juice ERROR] Existing package.jai is invalid."));
    expect(output_matches("bad-manifest-jaix-exe", output, string.["[juice] Build completed successfully!"], want = false));
    expect(!file_exists(package_target_dir(fixture_root)));
}

test "E2E: an unknown plugin id fails plugin preparation byte-for-byte" {
    fixture_root := path_slashes(tprint("%1/tests/data/bad-manifest-plugin-id", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    // Ticket 056 moved semantic validation out of the loader into plugin
    // preparation: the protocol parses clean, then the declaration-driven
    // workspace scan rejects the id (neither built-in nor workspace member)
    // before any compile — even for this zero-plan package.
    result, output, _ := run_otter_child_at(fixture_root, string.["build"]);
    expect(expect_exit("bad-manifest-plugin-id", result, 1, "build child"));
    expect(child_output_contains("bad-manifest-plugin-id", output,
        "[juice ERROR] mystery: Plugin 'mystery' source: provider package has no declaration:"));
    expect(child_output_contains("bad-manifest-plugin-id", output,
        "[juice ERROR] Could not prepare the workspace's plugin declarations."));
    expect(output_matches("bad-manifest-plugin-id", output, string.["[juice] Build completed successfully!"], want = false));
    expect(!file_exists(package_target_dir(fixture_root)));
}
