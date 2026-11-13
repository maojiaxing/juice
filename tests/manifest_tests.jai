#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// Manifest protocol tests: the parser matrix and the plugin declaration
// gate run purely in-process; the loader tests drive the evaluator spawn seam
// with a recording fake (deterministic retry paths); the E2E test at the
// bottom spawns a real jai child to evaluate the fixture manifest and
// asserts the protocol records field by field.
// ---------------------------------------------------------------------------

// The protocol text the E2E fixture's declarations must evaluate to
// (record order matches build_eval_code's fixed print order; repeatable
// records keep declaration order).
FULL_PROTOCOL :: "NAME=manifest-fixture\nVERSION=1.2.3\nTYPE=1\nDESCRIPTION=Evaluator protocol E2E fixture.\nBUILD_SCRIPT=build.py\nPLUGIN=load|1\nPLUGIN=test-block|2\nTARGET=app|src/main.jai\nMEMBER=packages/a\nMEMBER=packages/b\nEXCLUDE=packages/skip\nDEP=dep_a|0.1||\nDEP=dep_b|0.2|../sibling|renamed\n";

test "Protocol: a complete manifest parses into every field" {
    result := parse_manifest_data_strict(FULL_PROTOCOL);
    expect(result.success);
    pkg := result.package;
    expect(pkg.name == "manifest-fixture");
    expect(pkg.version == "1.2.3");
    expect(pkg.type == .BIN);
    expect(pkg.description == "Evaluator protocol E2E fixture.");
    expect(pkg.build_script == "build.py");
    expect(pkg.plugins.count == 2);
    expect(pkg.plugins[0].id == "load" && pkg.plugins[0].version == "1");
    expect(pkg.plugins[1].id == "test-block" && pkg.plugins[1].version == "2");
    expect(pkg.plugins[0].options.count == 0);
    expect(pkg.targets.count == 1);
    expect(pkg.targets[0].name == "app" && pkg.targets[0].main_file == "src/main.jai");
    expect(pkg.workspace.members.count == 2);
    expect(pkg.workspace.members[0] == "packages/a" && pkg.workspace.members[1] == "packages/b");
    expect(pkg.workspace.exclude.count == 1 && pkg.workspace.exclude[0] == "packages/skip");
    expect(pkg.dependencies.count == 2);
    expect(pkg.dependencies[0].name == "dep_a" && pkg.dependencies[0].version == "0.1"
        && pkg.dependencies[0].source == "" && pkg.dependencies[0].package == "");
    expect(pkg.dependencies[1].name == "dep_b" && pkg.dependencies[1].version == "0.2"
        && pkg.dependencies[1].source == "../sibling" && pkg.dependencies[1].package == "renamed");
}

test "Protocol: unknown records are rejected with a line number" {
    result := parse_manifest_data_strict("NAME=x\nVERSION=1\nBOGUS=y\n");
    expect(!result.success);
    expect(result.line_number == 3);
    expect(result.error_message == "Unknown manifest record: BOGUS");
}

test "Protocol: duplicate single-value records are rejected with a line number" {
    result := parse_manifest_data_strict("NAME=a\nVERSION=1\nTYPE=\nNAME=b\n");
    expect(!result.success);
    expect(result.line_number == 4);
    expect(result.error_message == "Duplicate NAME record.");

    result = parse_manifest_data_strict("NAME=a\nVERSION=1\nVERSION=2\n");
    expect(!result.success);
    expect(result.line_number == 3);
    expect(result.error_message == "Duplicate VERSION record.");
}

test "Protocol: malformed records carry their line number" {
    result := parse_manifest_data_strict("NAME=x\nnoequals\n");
    expect(!result.success);
    expect(result.line_number == 2);
    expect(result.error_message == "Malformed manifest record on line 2.");
}

test "Protocol: a key reduced to nothing is malformed" {
    // The whole line is trimmed before splitting, so a whitespace-only key
    // (and a bare "=value") both land in the malformed branch — same split
    // as old juice, whose separate empty-key branch stays defensive.
    result := parse_manifest_data_strict("   =value\n");
    expect(!result.success);
    expect(result.line_number == 1);
    expect(result.error_message == "Malformed manifest record on line 1.");
}

test "Protocol: TYPE accepts the three enum values and an empty value" {
    result := parse_manifest_data_strict("TYPE=0\n");
    expect(result.success && result.package.type == .LIB);

    result = parse_manifest_data_strict("TYPE=1\n");
    expect(result.success && result.package.type == .BIN);

    result = parse_manifest_data_strict("TYPE=2\n");
    expect(result.success && result.package.type == .UNSPECIFIED);

    result = parse_manifest_data_strict("TYPE=\n");
    expect(result.success && result.package.type == .UNSPECIFIED);
}

test "Protocol: an invalid TYPE is rejected" {
    result := parse_manifest_data_strict("TYPE=7\n");
    expect(!result.success && result.line_number == 1 && result.error_message == "Invalid package type enum.");

    result = parse_manifest_data_strict("TYPE=1x\n");
    expect(!result.success && result.error_message == "Invalid package type enum.");
}

test "Protocol: TARGET shape errors are rejected" {
    result := parse_manifest_data_strict("TARGET=app\n");
    expect(!result.success && result.line_number == 1 && result.error_message == "TARGET record must contain name|main_file.");

    result = parse_manifest_data_strict("TARGET=app|src/main.jai|extra\n");
    expect(!result.success && result.error_message == "TARGET record must contain name|main_file.");
}

test "Protocol: DEP shape errors are rejected" {
    result := parse_manifest_data_strict("DEP=a|1|2\n");
    expect(!result.success && result.error_message == "DEP record must contain four fields.");

    result = parse_manifest_data_strict("DEP=a|1|2|3|4\n");
    expect(!result.success && result.error_message == "DEP record must contain four fields.");
}

test "Protocol: PLUGIN shape errors and duplicates are rejected" {
    result := parse_manifest_data_strict("PLUGIN=load\n");
    expect(!result.success && result.line_number == 1 && result.error_message == "PLUGIN record must contain id|version.");

    result = parse_manifest_data_strict("PLUGIN=load|1|extra\n");
    expect(!result.success && result.error_message == "PLUGIN record must contain id|version.");

    result = parse_manifest_data_strict("PLUGIN=load|1\nPLUGIN=load|2\n");
    expect(!result.success);
    expect(result.line_number == 2);
    expect(result.error_message == "Duplicate PLUGIN record.");
}

test "Protocol: PLUGIN_OPTION shape, encoding, declaration order and duplicate keys" {
    result := parse_manifest_data_strict("PLUGIN=jaix|1\nPLUGIN_OPTION=jaix\n");
    expect(!result.success && result.error_message == "PLUGIN_OPTION record must contain id|key|value.");

    // %7C -> |, %25 -> %, %0A -> LF: the encoded value survives the
    // line-record shape and decodes back exactly.
    result = parse_manifest_data_strict("PLUGIN=jaix|1\nPLUGIN_OPTION=jaix|config|a%7Cb%25c%0Ad\n");
    expect(result.success);
    expect(result.package.plugins.count == 1);
    expect(result.package.plugins[0].options.count == 1);
    expect(result.package.plugins[0].options[0].key == "config");
    expect(result.package.plugins[0].options[0].value == "a|b%c\nd");

    result = parse_manifest_data_strict("PLUGIN_OPTION=jaix|config|x\n");
    expect(!result.success && result.error_message == "PLUGIN_OPTION for an undeclared plugin.");

    result = parse_manifest_data_strict("PLUGIN=jaix|1\nPLUGIN_OPTION=jaix|config|x\nPLUGIN_OPTION=jaix|config|y\n");
    expect(!result.success && result.error_message == "Duplicate plugin option key: config");

    result = parse_manifest_data_strict("PLUGIN=jaix|1\nPLUGIN_OPTION=jaix|config|%zz\n");
    expect(!result.success && result.error_message == "Invalid %XX escape in PLUGIN_OPTION record.");
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

test "Protocol: empty MEMBER and EXCLUDE records are rejected" {
    result := parse_manifest_data_strict("MEMBER=\n");
    expect(!result.success && result.error_message == "MEMBER record cannot be empty.");

    result = parse_manifest_data_strict("EXCLUDE=\n");
    expect(!result.success && result.error_message == "EXCLUDE record cannot be empty.");
}

test "Protocol: empty lines and CRLF are tolerated" {
    result := parse_manifest_data_strict("NAME=x\r\n\r\nVERSION=1\r\n");
    expect(result.success);
    expect(result.package.name == "x" && result.package.version == "1");

    // Line numbers still count the blank line.
    result = parse_manifest_data_strict("NAME=x\r\n\r\nBOGUS=y\r\n");
    expect(!result.success && result.line_number == 3);
}

test "Protocol: the convenience parser keeps the same shape" {
    pkg := parse_manifest_data("NAME=plain\n");
    expect(pkg.name == "plain");
}

// ---------------------------------------------------------------------------
// Temp file naming.
// ---------------------------------------------------------------------------

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
    EVAL_SPAWN.data_output = "NAME=fixture\nVERSION=1\n";

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
    EVAL_SPAWN.data_output = "PLUGIN=mystery|1\n";

    cache := otter_scratch("manifest-retry-cache");
    fixture := tprint("%1/tests/data/manifest-fixture", otter_root());
    pkg, ok := load_package_manifest(cache, fixture, "", test_eval_spawn);
    expect(ok);
    expect(pkg.plugins.count == 1);
    expect(pkg.plugins[0].id == "mystery" && pkg.plugins[0].version == "1");
}

test "Loader: a successful load backfills the package dir" {
    reset_eval_spawn();
    EVAL_SPAWN.data_output = "NAME=fixture\n";

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
    expect(pkg.type == .BIN);
    expect(pkg.description == "Evaluator protocol E2E fixture.");
    expect(pkg.build_script == "build.py");
    expect(pkg.plugins.count == 2);
    expect(pkg.plugins[0].id == "load" && pkg.plugins[0].version == "1");
    expect(pkg.plugins[1].id == "test-block" && pkg.plugins[1].version == "2");
    expect(pkg.plugins[0].options.count == 0);
    expect(pkg.targets.count == 1);
    expect(pkg.targets[0].name == "app" && pkg.targets[0].main_file == "src/main.jai");
    expect(pkg.workspace.members.count == 2);
    expect(pkg.workspace.members[0] == "packages/a" && pkg.workspace.members[1] == "packages/b");
    expect(pkg.workspace.exclude.count == 1 && pkg.workspace.exclude[0] == "packages/skip");
    expect(pkg.dependencies.count == 2);
    expect(pkg.dependencies[0].name == "dep_a" && pkg.dependencies[0].version == "0.1"
        && pkg.dependencies[0].source == "" && pkg.dependencies[0].package == "");
    expect(pkg.dependencies[1].name == "dep_b" && pkg.dependencies[1].version == "0.2"
        && pkg.dependencies[1].source == "../sibling" && pkg.dependencies[1].package == "renamed");
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
        "tests/data/bad-manifest-duplicate-plugin/package.jai (line 7): Duplicate PLUGIN record."));
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
        "tests/data/bad-manifest-empty-member/package.jai (line 6): MEMBER record cannot be empty."));
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
        "tests/data/bad-manifest-empty-exclude/package.jai (line 6): EXCLUDE record cannot be empty."));
    expect(child_output_contains("bad-manifest-empty-exclude", output,
        "[juice ERROR] Existing package.jai is invalid."));
    expect(output_matches("bad-manifest-empty-exclude", output, string.["[juice] Build completed successfully!"], want = false));
    expect(!file_exists(package_target_dir(fixture_root)));
}

test "E2E: an out-of-range type enum fails discovery byte-for-byte" {
    fixture_root := path_slashes(tprint("%1/tests/data/bad-manifest-invalid-type", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));

    result, output, _ := run_otter_child_at(fixture_root, string.["build"]);
    expect(expect_exit("bad-manifest-invalid-type", result, 1, "build child"));
    expect(child_output_contains("bad-manifest-invalid-type", output,
        "tests/data/bad-manifest-invalid-type/package.jai (line 3): Invalid package type enum."));
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
        "[juice ERROR] mystery: Unknown plugin id: mystery"));
    expect(child_output_contains("bad-manifest-plugin-id", output,
        "[juice ERROR] Could not prepare the workspace's plugin declarations."));
    expect(output_matches("bad-manifest-plugin-id", output, string.["[juice] Build completed successfully!"], want = false));
    expect(!file_exists(package_target_dir(fixture_root)));
}
