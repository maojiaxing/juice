#import "Basic";
#import "Testing";
#import "String";
#import "File";
#import "File_Utilities";

// ---------------------------------------------------------------------------
// Test discovery pure-function matrix (tickets 016/017): note filtering,
// numeric-aware ordering, numbering continuation, duplicate detection and
// file-source isolation — the #load-direct test face of
// src/test_discovery.jai (the declarations enter this test program's
// application scope through Test discovery's full-package scan). The
// collect_test_entries composite (ticket 017) wires the primitives the way
// the generated test metaprogram's message loop does; the metaprogram
// generation itself is covered by tests/test_runner_tests.jai. Ticket
// 018 adds the post-collection pattern filter, the production file
// collection (the scan_walk skeleton plus the test exclusion set), the
// command orchestration seam matrix (collect/spawn fakes with the real
// generators) and the E2E start (the real otter exe `test` on the @test
// fixtures). Ticket 019 deepens the E2E family: the static test-empty
// package (the command-layer zero-file short circuit), the test-fixture
// numbering face (the numeric-aware juice_test_N run order plus the
// numbering base 1 pinned in the generated metaprogram product) and the
// pattern case-sensitivity/substring faces. Ticket 045 adds the plugin
// wiring matrix: the COMPILE stage's workspace scan -> registration write ->
// metaprogram option handover through the injected spawn seam, the zero-hit
// unwired shape, the scan/write failure channels and the non-member DEP
// fixture staying scan-free. Ticket 046 adds the full-chain CLI E2E: the
// real exe drives a runtime-built scratch workspace whose member is a byte
// copy of the real packages/juice-plugin-lint, plus the member-root smoke.
// Ticket 051 adds the installed-layout plugin E2E: the real exe plus the
// whole published modules tree copied to a scratch install with no sibling
// src/ or target/, driving a scratch workspace whose member is a byte-for-
// byte copy of the whole real member package tree (tests/ included). The
// installed juice_core artifact contract (relative #load lines, closure
// copies present, every target inside the install) is pinned there too.
// ---------------------------------------------------------------------------

test "Discovery: note_matches_test exact and prefix only" {
    // The exact "test" and the parameterized prefix "test(" qualify.
    expect(note_matches_test("test"));
    expect(note_matches_test("test(x)"));
    expect(note_matches_test("test()"));
    expect(note_matches_test("test(custom_name)"));
    // Substring matches never qualify — compiler-internal notes
    // (PrintLike/NoProfile) and near misses must not be mis-collected.
    expect(!note_matches_test("tests"));
    expect(!note_matches_test("testing"));
    expect(!note_matches_test("mytest"));
    expect(!note_matches_test("testx"));
    expect(!note_matches_test("atest"));
    expect(!note_matches_test("test "));
    expect(!note_matches_test("PrintLike"));
    expect(!note_matches_test("NoProfile"));
    expect(!note_matches_test(""));
}

test "Discovery: header_is_test gates on the note and a non-empty name" {
    expect(header_is_test("addition", string.["test"]));
    expect(header_is_test("named", string.["test(custom)"]));
    // Any one matching note qualifies, whatever its position.
    expect(header_is_test("multi", string.["PrintLike", "test"]));
    expect(header_is_test("multi2", string.["test", "NoProfile"]));
    // The empty name never qualifies — anonymous headers are not tests.
    expect(!header_is_test("", string.["test"]));
    // No matching note never qualifies.
    expect(!header_is_test("plain", string.["PrintLike", "NoProfile"]));
    expect(!header_is_test("plain", string.[]));
    expect(!header_is_test("plain", string.["tests", "testx"]));
}

test "Discovery: parse_test_number_prefix strips the numeric prefix" {
    number, rest, ok := parse_test_number_prefix("juice_test_3");
    expect(ok && number == 3 && rest == "");
    number, rest, ok = parse_test_number_prefix("juice_test_10_extra");
    expect(ok && number == 10 && rest == "_extra");
    number, rest, ok = parse_test_number_prefix("juice_test_007");
    expect(ok && number == 7 && rest == "");
    // The prefix demands at least one digit immediately after it.
    number, rest, ok = parse_test_number_prefix("juice_test_");
    expect(!ok);
    number, rest, ok = parse_test_number_prefix("juice_test_abc");
    expect(!ok);
    // Without the exact prefix the name never parses.
    number, rest, ok = parse_test_number_prefix("juice_testx_3");
    expect(!ok);
    number, rest, ok = parse_test_number_prefix("test_3");
    expect(!ok);
    number, rest, ok = parse_test_number_prefix("juice_test");
    expect(!ok);
}

test "Discovery: test_name_less numeric-aware on the juice_test_N prefix" {
    // Numeric comparison: 2 sorts before 10 (plain lexicographic would not).
    expect(test_name_less("juice_test_2", "juice_test_10"));
    expect(!test_name_less("juice_test_10", "juice_test_2"));
    expect(test_name_less("juice_test_9", "juice_test_10"));
    // Equal numeric parts compare the remainder lexicographically.
    expect(test_name_less("juice_test_1_alpha", "juice_test_1_beta"));
    expect(!test_name_less("juice_test_1_beta", "juice_test_1_alpha"));
    // The raw-name tiebreak keeps distinct names ordered (juice_test_02 vs
    // juice_test_2 — same value, different digit text).
    expect(test_name_less("juice_test_02", "juice_test_2"));
    expect(!test_name_less("juice_test_2", "juice_test_02"));
    // Mixed forms fall back to plain string comparison ('1' sorts before
    // 'a', so the numeric-prefixed name comes first).
    expect(!test_name_less("juice_test_abc", "juice_test_10"));
    expect(test_name_less("juice_test_10", "juice_test_abc"));
    expect(test_name_less("juice_test_2", "zebra"));
    expect(!test_name_less("zebra", "juice_test_2"));
    // Plain names compare lexicographically.
    expect(test_name_less("alpha", "beta"));
    expect(!test_name_less("beta", "alpha"));
    expect(!test_name_less("alpha", "alpha"));
}

test "Discovery: sort_test_names produces the deterministic order" {
    names: [..] string;
    array_add(*names, "zebra");
    array_add(*names, "juice_test_10");
    array_add(*names, "alpha");
    array_add(*names, "juice_test_2");
    array_add(*names, "juice_test_1_beta");
    array_add(*names, "juice_test_1_alpha");
    sort_test_names(names);
    expected := string.[
        "alpha",
        "juice_test_1_alpha",
        "juice_test_1_beta",
        "juice_test_2",
        "juice_test_10",
        "zebra",
    ];
    if names.count != expected.count {
        print("[test discovery] got %1 names, want %2\n", names.count, expected.count);
    }
    expect(names.count == expected.count);
    for i: 0..expected.count-1 expect(names[i] == expected[i]);

    // Stable: equal names keep their collection order.
    names2: [..] string;
    array_add(*names2, "dup");
    array_add(*names2, "mid");
    array_add(*names2, "dup");
    sort_test_names(names2);
    expect(names2.count == 3);
    expect(names2[0] == "dup" && names2[1] == "dup" && names2[2] == "mid");
}

test "Discovery: first_duplicate_test_name finds the first repeat" {
    expect(first_duplicate_test_name(string.[]) == -1);
    expect(first_duplicate_test_name(string.["a"]) == -1);
    expect(first_duplicate_test_name(string.["a", "b", "c"]) == -1);
    expect(first_duplicate_test_name(string.["a", "b", "a"]) == 2);
    expect(first_duplicate_test_name(string.["a", "a", "b"]) == 1);
    expect(first_duplicate_test_name(string.["a", "b", "b", "a"]) == 2);
    expect(first_duplicate_test_name(string.["a", "a", "a"]) == 1);
}

test "Discovery: number_tests continues the global numbering" {
    entries := number_tests(string.[]);
    expect(entries.count == 0);
    entries = number_tests(string.["alpha", "beta"]);
    expect(entries.count == 2);
    expect(entries[0].number == 1 && entries[0].name == "alpha");
    expect(entries[1].number == 2 && entries[1].name == "beta");
    // The continuation: the caller threads the next start across the whole
    // program (juice t3 semantics — numbers never restart).
    entries = number_tests(string.["gamma"], 3);
    expect(entries.count == 1);
    expect(entries[0].number == 3 && entries[0].name == "gamma");
    entries = number_tests(string.["delta"], start = 42);
    expect(entries[0].number == 42);
}

test "Discovery: source_path_allowed isolates dependency sources" {
    package_views := string.["C:/pkg/src/main.jai", "C:/pkg/src/tests_a.jai"];
    whitelist := string.["C:/pkg/target/testing-view/Testing.jai"];
    // In the package view set: discovered.
    expect(source_path_allowed("C:/pkg/src/main.jai", package_views, whitelist));
    // In the whitelist (the driver-injected compile views): discovered.
    expect(source_path_allowed("C:/pkg/target/testing-view/Testing.jai", package_views, whitelist));
    // Dependency closure declarations entering through shims: excluded.
    expect(!source_path_allowed("C:/cache/packages/some-dep/shim.jai", package_views, whitelist));
    // Exact string comparison: near misses never qualify.
    expect(!source_path_allowed("C:/pkg/src/main.jai2", package_views, whitelist));
    expect(!source_path_allowed("C:/pkg/src/main", package_views, whitelist));
    expect(!source_path_allowed("pkg/src/main.jai", package_views, whitelist));
    expect(!source_path_allowed("", package_views, whitelist));
    // Empty sets allow nothing.
    expect(!source_path_allowed("C:/pkg/src/main.jai", string.[], string.[]));
}

test "Discovery: collect_test_entries isolates, orders, numbers and rejects duplicates" {
    package_views := string.["C:/pkg/src/a.jai", "C:/pkg/src/b.jai"];
    // Collected in message order; the composite orders by name.
    sources: [..] Collected_Test_Source;
    array_add(*sources, .{ name = "zebra", path = "C:/pkg/src/a.jai" });
    array_add(*sources, .{ name = "alpha", path = "C:/pkg/src/b.jai" });
    array_add(*sources, .{ name = "dep_test", path = "C:/cache/packages/dep/shim.jai" });
    entries, duplicate := collect_test_entries(sources, package_views, string.[]);
    expect(duplicate == "");
    expect(entries.count == 2);
    expect(entries[0].number == 1 && entries[0].name == "alpha");
    expect(entries[1].number == 2 && entries[1].name == "zebra");

    // The whitelist admits the Testing module compile view family (1c).
    entries, duplicate = collect_test_entries(sources, package_views, string.["C:/cache/packages/dep/shim.jai"]);
    expect(duplicate == "");
    expect(entries.count == 3);
    expect(entries[2].number == 3 && entries[2].name == "zebra");

    // The global numbering continuation threads through (juice t3).
    entries, duplicate = collect_test_entries(sources, package_views, string.[], numbering_start = 10);
    expect(entries[0].number == 10 && entries[1].number == 11);

    // Duplicates are rejected at collection time with the offending name
    // (isolation runs first, so excluded sources never collide).
    sources2: [..] Collected_Test_Source;
    array_add(*sources2, .{ name = "alpha", path = "C:/pkg/src/a.jai" });
    array_add(*sources2, .{ name = "alpha", path = "C:/pkg/src/b.jai" });
    entries, duplicate = collect_test_entries(sources2, package_views, string.[]);
    expect(duplicate == "alpha");
    expect(entries.count == 0);
    entries, duplicate = collect_test_entries(sources2, string.["C:/pkg/src/a.jai"], string.[]);
    expect(duplicate == "");
    expect(entries.count == 1);

    // A null enclosing load (string-added files) reports an empty path and
    // never passes isolation.
    sources3: [..] Collected_Test_Source;
    array_add(*sources3, .{ name = "ghost", path = "" });
    entries, duplicate = collect_test_entries(sources3, package_views, string.[]);
    expect(duplicate == "" && entries.count == 0);

    // An empty stream collects nothing.
    entries, duplicate = collect_test_entries(Collected_Test_Source.[], package_views, string.[]);
    expect(duplicate == "" && entries.count == 0);
}

test "Discovery: filter_test_entries filters after collection" {
    entries := Numbered_Test.[
        .{ number = 1, name = "addition" },
        .{ number = 2, name = "addition with negatives" },
        .{ number = 3, name = "greeting" },
    ];
    // The empty pattern keeps everything.
    all := filter_test_entries(entries, "");
    expect(all.count == 3);
    // Substring, case-sensitive: "addition" matches the first two only.
    matched := filter_test_entries(entries, "addition");
    expect(matched.count == 2);
    expect(matched[0].name == "addition" && matched[1].name == "addition with negatives");
    // The numbering survives the filter unchanged (a filtered run never
    // renumbers the remaining tests).
    expect(matched[0].number == 1 && matched[1].number == 2);
    // An upper-case pattern matches nothing (case-sensitive, aligned with
    // target selection).
    expect(filter_test_entries(entries, "ADDITION").count == 0);
    // A no-match pattern returns an empty list; an empty stream stays empty.
    expect(filter_test_entries(entries, "nomatch").count == 0);
    expect(filter_test_entries(Numbered_Test.[], "x").count == 0);
}

// ---------------------------------------------------------------------------
// Command declaration and argument guards (the old juice test.jai contract
// tests).
// ---------------------------------------------------------------------------

test "Test command declaration and argument contract" {
    expect(TEST_COMMAND.name == "test");
    expect(TEST_COMMAND.usage == "juice test [pattern]");
    expect(TEST_COMMAND.prerequisites.count == 0);
    expect(TEST_COMMAND.handler == test_command);
    expect(TEST_COMMAND.validate_arguments == test_arguments_are_valid);
    expect(TEST_COMMAND.validate_arguments(string.[]) && TEST_COMMAND.validate_arguments(string.["x"]));
    expect(!TEST_COMMAND.validate_arguments(string.["x", "y"]));
}

test "Test command argument guard" {
    ctx: Command_Context;
    expect(!TEST_COMMAND.handler(*ctx, string.["one", "two"]));
}

// ---------------------------------------------------------------------------
// File collection (ticket 018): the production exclusion set over the
// scan_walk skeleton (ticket 015's handover — the skeleton owns the walk
// mechanics, this wrapper owns the exclusion predicates and the error
// message). The static scan-fixture mirrors the old juice
// tests/data/scan-fixture layout; the scratch roots cover the link faces.
// (Pre-step plugin drops filter the collected list at the PRESTEP stage —
// ticket 057/058 — so the collector itself carries no plugin knowledge.)
// ---------------------------------------------------------------------------

// Full discovery rules over the static scan fixture: recursive
// lowercase-.jai discovery in deterministic scan order (per directory: files
// first, then subdirectories, both lexicographic). Excluded: dot entries at
// any depth, the root-level target/, tests/data/ and modules/, the root
// manifest, and the member-a subtree (boundary from the discovery
// snapshot). Included despite same names elsewhere: src/target/,
// src/modules/, src/data/ and a nested package.jai source file.
test "Collection applies the exclusion set in scan order" {
    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = tprint("%1/tests/data/scan-fixture", otter_root());
    prepared.discovery.member_packages = Juice.Package.[
        .{name = "scan-fixture", dir = prepared.discovery.root_dir},
        .{name = "member-a", dir = tprint("%1/tests/data/scan-fixture/member-a", otter_root())},
    ];
    files, ok := collect_test_files(*prepared);
    expect(ok);
    expected := string.[
        "a_root.jai",
        "lib_deep/package.jai",
        "src/b.jai",
        "src/data/d.jai",
        "src/modules/e.jai",
        "src/target/c.jai",
        "tests/e.jai",
    ];
    if files.count != expected.count {
        print("[collect] got %1 files, want %2\n", files.count, expected.count);
        for file: files print("[collect] got %\n", file.rel_path);
    }
    expect(files.count == expected.count);
    for i: 0..expected.count-1 {
        expect(files[i].rel_path == expected[i]);
        expect(files[i].abs_path == tprint("%1/tests/data/scan-fixture/%2", otter_root(), expected[i]));
    }
}

test "Collection rejects a missing package root" {
    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = tprint("%1/tests/data/no-such-package", otter_root());
    _, ok := collect_test_files(*prepared);
    expect(!ok);
}

// No link following: a symlinked directory, a junctioned directory and a
// symlinked file all stay out of the scan, while the real targets are still
// discovered through their own paths (make_test_link lives in
// test_support.jai; the SKIP convention applies on machines that refuse
// mklink).
test "Collection skips symlinks and junctions" {
    root := otter_scratch("collect-links");
    delete_directory_full(root);
    defer delete_directory_full(root);
    real_dir := lexical_absolute_path(tprint("%1/real", root));
    expect(make_directory_if_it_does_not_exist(real_dir, recursive = true));
    expect(write_entire_file(tprint("%1/with_test.jai", real_dir), ""));
    expect(write_entire_file(tprint("%1/real_file.jai", lexical_absolute_path(root)), ""));

    link_ok := true;
    link_ok = make_test_link(tprint("%1/link_dir", lexical_absolute_path(root)), real_dir, directory = true, junction = false) && link_ok;
    link_ok = make_test_link(tprint("%1/junction_dir", lexical_absolute_path(root)), real_dir, directory = true, junction = true) && link_ok;
    link_ok = make_test_link(tprint("%1/link_file.jai", lexical_absolute_path(root)), tprint("%1/real_file.jai", lexical_absolute_path(root)), directory = false, junction = false) && link_ok;
    if !link_ok {
        print("[collect] SKIP: this machine refuses mklink; link exclusion not exercised\n");
        return;
    }

    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = lexical_absolute_path(root);
    files, ok := collect_test_files(*prepared);
    expect(ok);
    expected := string.["real_file.jai", "real/with_test.jai"];
    if files.count != expected.count {
        print("[collect] got %1 files, want %2\n", files.count, expected.count);
        for file: files print("[collect] got %\n", file.rel_path);
    }
    expect(files.count == expected.count);
    for i: 0..expected.count-1 {
        expect(files[i].rel_path == expected[i]);
    }
}

// ---------------------------------------------------------------------------
// Command orchestration (ticket 018, the 1c shape kept): the zero-file
// short circuit and the collect failure propagation over the recording
// fakes (test_support.jai). The full 1c transpile front, the generated
// products and the hook dispatch live in tests/test_transpile_tests.jai
// (ticket 028).
// ---------------------------------------------------------------------------

test "Test command short-circuits the zero-file collection" {
    root := otter_scratch("test-cmd-empty");
    prepared := test_command_prepared(root);
    reset_test_command_seam();
    expect(test_prepared_workspace(*prepared, "", Hook_Registration.[], test_collect_test_files, test_spawn_test_compiler));
    expect(test_test_collect_calls == 1 && test_test_spawn_calls == 0);
    // No test program can exist: neither the 1c transpile tree nor the 1b
    // product directory is created.
    expect(!file_exists(transpile_tree_dir(root)));
    expect(!file_exists(tprint("%1/target/test", root)));
}

test "Test command propagates a collect failure" {
    prepared := test_command_prepared(otter_scratch("test-cmd-collect-fail"));
    reset_test_command_seam();
    test_test_collect_ok = false;
    expect(!test_prepared_workspace(*prepared, "", Hook_Registration.[], test_collect_test_files, test_spawn_test_compiler));
    expect(test_test_collect_calls == 1 && test_test_spawn_calls == 0);
}

test "Test command prunes the target/tests scratch zone" {
    root := otter_scratch("test-cmd-prune");
    delete_directory_full(root);
    defer delete_directory_full(root);
    tests_dir := target_tests_dir(package_target_dir(root));
    expect(make_directory_if_it_does_not_exist(tprint("%1/stale", tests_dir), recursive = true));
    probe := tprint("%1/stale/probe.txt", tests_dir);
    expect(write_entire_file(probe, "stale"));
    expect(prune_test_scratch(root));
    expect(!file_exists(probe) && !file_exists(tests_dir));
    // A missing zone is success: the next run's prune must be idempotent.
    expect(prune_test_scratch(root));
}

// ---------------------------------------------------------------------------
// E2E child scenarios (tickets 018/019): the real otter exe `test` on the
// @test fixtures — discovery through the real scan, the real generated driver
// and metaprogram, the real jai child (the test program really compiles and
// the injected #run really executes), and the exit code passthrough. Ticket
// 019 deepens the fixture family: the static test-empty package (the
// command-layer zero-file short circuit), the test-fixture numbering face
// (the numeric-aware juice_test_N order plus the numbering base 1 pinned in
// the generated metaprogram) and the pattern case-sensitivity/substring
// faces. The fixtures' target/ directories are session products — removed
// after each run so the static fixture trees stay clean.
// ---------------------------------------------------------------------------

test "E2E: the test command discovers and runs the fixture's @test procedures" {
    fixture_root := path_slashes(tprint("%1/tests/data/test-fixture", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    result, output, _ := run_otter_child_at(fixture_root, string.["test"]);
    expect(expect_exit("test-fixture", result, 0));
    expect(output_matches("test-fixture", output, string.[
        "[test] juice_test_2",
        "[test] juice_test_10",
        "[test] test_alpha",
        "[test] test_beta",
        "[test] test_gamma",
        "5 passed, 0 failed",
    ]));
    // The deterministic order: name sort with the numeric-aware juice_test_N
    // prefix (juice_test_2 runs before juice_test_10 — plain lexicographic
    // order would put 10 first; tests_a.jai declares them the other way
    // around on purpose), whatever the message order.
    n2 := find_index_from_left(output, "[test] juice_test_2");
    n10 := find_index_from_left(output, "[test] juice_test_10");
    alpha := find_index_from_left(output, "[test] test_alpha");
    beta := find_index_from_left(output, "[test] test_beta");
    gamma := find_index_from_left(output, "[test] test_gamma");
    expect(n2 >= 0 && n2 < n10 && n10 < alpha && alpha < beta && beta < gamma);

    // The real command's generated metaprogram carries the numbering base 1
    // (juice t3 — the global continuation starts at 1). The numbers
    // themselves never reach the output (the 1b display name is the
    // procedure name, ticket 017 deviation 5), so the product pins the base.
    expect(file_contains(tprint("%1/test_runner.jai", transpile_tree_dir(fixture_root)),
        "collect_test_entries(collected_sources, package_view_paths, whitelist_paths, 1)"));
}

test "E2E: the pattern filters the executed tests" {
    fixture_root := path_slashes(tprint("%1/tests/data/test-fixture", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    result, output, _ := run_otter_child_at(fixture_root, string.["test", "alpha"]);
    expect(expect_exit("test pattern", result, 0));
    expect(output_matches("test pattern", output, string.["[test] test_alpha", "1 passed, 0 failed"]));
    expect(output_matches("test pattern", output, string.["[test] test_beta"], want = false));
}

test "E2E: a zero-match pattern reports and skips the runner" {
    fixture_root := path_slashes(tprint("%1/tests/data/test-fixture", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    result, output, _ := run_otter_child_at(fixture_root, string.["test", "nomatch"]);
    expect(expect_exit("zero-match", result, 0));
    expect(output_matches("zero-match", output, string.["[juice Test] No tests matched 'nomatch'."]));
    expect(output_matches("zero-match", output, string.["[test]"], want = false));
}

// The pattern filter is a case-sensitive substring match (spec section 7.3):
// an upper-case pattern matches nothing.
test "E2E: the pattern filter is case-sensitive" {
    fixture_root := path_slashes(tprint("%1/tests/data/test-fixture", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    result, output, _ := run_otter_child_at(fixture_root, string.["test", "ALPHA"]);
    expect(expect_exit("test pattern case", result, 0));
    expect(output_matches("test pattern case", output, string.["[juice Test] No tests matched 'ALPHA'."]));
    expect(output_matches("test pattern case", output, string.["[test]"], want = false));
}

// The pattern matches by substring, not by prefix parse: "juice_test_1" is a
// substring of juice_test_10 only, so the filtered run executes exactly that
// test (substring semantics — "juice_test_1" is not the juice_test_1 name).
test "E2E: the pattern substring-matches the juice_test_N names" {
    fixture_root := path_slashes(tprint("%1/tests/data/test-fixture", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    result, output, _ := run_otter_child_at(fixture_root, string.["test", "juice_test_1"]);
    expect(expect_exit("test pattern number", result, 0));
    expect(output_matches("test pattern number", output, string.["[test] juice_test_10", "1 passed, 0 failed"]));
    expect(output_matches("test pattern number", output, string.["[test] juice_test_2", "[test] test_alpha"], want = false));
}

test "E2E: a failing test continues the suite and exits nonzero" {
    fixture_root := path_slashes(tprint("%1/tests/data/test-fail", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    result, output, _ := run_otter_child_at(fixture_root, string.["test"]);
    expect(expect_exit("test-fail", result, 1));
    // The failure continues the suite, prints the mapped package-relative
    // coordinate, aggregates the failure count, and the compile error
    // (finish()/assert gate) propagates through the command's exit code.
    expect(output_matches("test-fail", output, string.[
        "[test] test_after",
        "[test] test_boom",
        "src/failing.jai:",
        "boom",
        "1 passed, 1 failed",
        "[juice ERROR] Test compilation failed.",
    ]));
}

test "E2E: a zero-file package short-circuits with No tests found" {
    // The static zero-file fixture (ticket 019): only the manifest, no .jai
    // sources at all — the collection returns nothing and the command
    // short-circuits before generating any test program (the command-layer
    // t4 semantics; the zero-ENTRY face — files present, no @test procedures
    // — short-circuits inside the generated metaprogram, the next block).
    fixture_root := path_slashes(tprint("%1/tests/data/test-empty", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    result, output, _ := run_otter_child_at(fixture_root, string.["test"]);
    expect(expect_exit("test-empty", result, 0));
    expect(output_matches("test-empty", output, string.["[juice Test] No tests found."]));
    expect(!file_exists(transpile_tree_dir(fixture_root)));
}

test "E2E: files without @test procedures short-circuit inside the metaprogram" {
    root := path_slashes(otter_scratch("test-cmd-e2e-noentries"));
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"test-noentries-e2e\",\n    version = \"0.1.0\",\n    type    = .BIN,\n};\n"));
    expect(build_seam_write(root, "src/plain.jai", "#import \"Basic\";\n\nhelper :: () -> s32 {\n    return 1;\n}\n"));
    result, output, _ := run_otter_child_at(root, string.["test"]);
    expect(expect_exit("test-no-entries", result, 0));
    expect(output_matches("test-no-entries", output, string.["[juice Test] No tests found."]));
}

// ---------------------------------------------------------------------------
// The bare-name gate regression (ticket 035, 006 spec decision 2): an
// old-juice-style user package — `#import "Testing"` plus bare `expect` —
// has its failing assertion counted by the finish gate, exits 1 and reports
// the original source coordinate. Before the single-register convergence the
// injected runner drove the prefixed bootstrap names while the bodies wrote
// the published bare register: the failure printed, but the summary read
// "2 passed, 0 failed" and the child exited 0.
// ---------------------------------------------------------------------------

test "E2E: a bare-name failing assertion is counted and exits 1" {
    root := path_slashes(otter_scratch("bare-name-fail"));
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"bare-name-fail\",\n    version = \"0.1.0\",\n    type    = .BIN,\n};\n"));
    expect(build_seam_write(root, "src/main.jai",
        "#import \"Basic\";\n#import \"Testing\";\n\nfailing_test :: () {\n    expect(1 == 2);\n} @test\n\npassing_test :: () {\n    expect(true);\n} @test\n"));
    result, output, _ := run_otter_child_at(root, string.["test"]);
    expect(expect_exit("bare-name-fail", result, 1));

    line, col := fixture_line_col(tprint("%1/src/main.jai", root), "expect(1 == 2);");
    expect(line != 0);
    // The failing assertion is counted (not "0 failed"), the passing one is
    // counted, the failure reports the original package-relative coordinate,
    // and the finish()/assert gate turns the count into exit 1.
    expect(output_matches("bare-name-fail", output, string.[
        "[test] failing_test",
        tprint("src/main.jai:%1:%2: expect failed", line, col),
        "[test] passing_test",
        "1 passed, 1 failed",
        "[juice ERROR] Test compilation failed.",
    ]));
}

test "E2E: a bare-name passing package exits 0 with the expected counts" {
    root := path_slashes(otter_scratch("bare-name-pass"));
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"bare-name-pass\",\n    version = \"0.1.0\",\n    type    = .BIN,\n};\n"));
    expect(build_seam_write(root, "src/main.jai",
        "#import \"Basic\";\n#import \"Testing\";\n\ntest_alpha :: () {\n    expect(1 + 1 == 2);\n} @test\n\ntest_beta :: () {\n    expect_eq(2 + 3, 5);\n} @test\n"));
    result, output, _ := run_otter_child_at(root, string.["test"]);
    expect(expect_exit("bare-name-pass", result, 0));
    expect(output_matches("bare-name-pass", output, string.[
        "[test] test_alpha",
        "[test] test_beta",
        "2 passed, 0 failed",
    ]));
    expect(output_matches("bare-name-pass", output, string.["expect failed"], want = false));
}

// ---------------------------------------------------------------------------
// Installed-layout E2E (ticket 037, 006 decision 4): the built executable
// and its modules directory copied to a scratch layout with no sibling
// src/ — the packaged shape. The test command must work there because the
// discovery source is the published internal artifact
// (<exe>/modules/juice_internal/test_discovery.jai). Before this ticket the
// generated metaprogram #loaded <exe>/../src/test_discovery.jai, which does
// not exist in an installed layout, so the compile failed. The generated
// metaprogram's #load path is pinned to the installed modules directory and
// the retired ../src form is pinned absent.
// ---------------------------------------------------------------------------
test "E2E: the test command works in an installed layout without a sibling src" {
    layout := path_slashes(otter_scratch("installed-layout-e2e"));
    delete_directory_full(layout);
    defer delete_directory_full(layout);
    bin_dir := tprint("%1/bin", layout);
    // The adjacent modules directory is the executable's only runtime
    // dependency (juice_modules_dir = <exe>/modules).
    modules_dir := tprint("%1/modules", bin_dir);
    expect(make_directory_if_it_does_not_exist(modules_dir, recursive = true));
    installed_exe := tprint("%1/juice.exe", bin_dir);
    expect(copy_file(otter_exe(), installed_exe));
    expect(ensure_published_modules());
    copy_directory(plugin_face_modules_dir(), modules_dir);
    // No source tree next to the executable: the retired <exe>/../src
    // derivation has nothing to resolve.
    expect(!is_directory(tprint("%1/src", layout)));

    fixture_root := path_slashes(tprint("%1/tests/data/test-fixture", otter_root()));
    defer delete_directory_full(package_target_dir(fixture_root));
    result, output, _, _ := run_command(installed_exe, "test", working_directory = fixture_root, capture_and_return_output = true);
    expect(expect_exit("installed-layout", result, 0));
    expect(output_matches("installed-layout", output, string.[
        "[test] test_alpha",
        "5 passed, 0 failed",
    ]));

    // The metaprogram #loads the discovery source from the exe-adjacent
    // modules directory (the published internal artifact); the retired
    // <exe>/../src form appears nowhere.
    generated, generated_ok := read_entire_file(tprint("%1/test_runner.jai", transpile_tree_dir(fixture_root)));
    expect(generated_ok);
    expected_load := tprint("#load \"%1\";", test_discovery_module_path(modules_dir));
    expect(find_index_from_left(generated, expected_load) >= 0,
        "the test metaprogram must #load the installed internal discovery artifact");
    expect(find_index_from_left(generated, "/../src/test_discovery.jai") < 0,
        "the retired <exe>/../src derivation must not appear");
}

// ---------------------------------------------------------------------------
// Plugin wiring (ticket 045, parent 040 decisions 9/11/13): the COMPILE
// stage scans the root package's declared member dependencies (the ticket
// 043 workspace scan), writes the workspace-level registration file and
// hands both metaprogram options over through the injected spawn seam. The
// scratch roots live under target/ (session artifacts); the scratch member
// only needs the lexical @juice_plugin anchor because the fake spawn never
// compiles the generated program — the assertions read the products and the
// generated text directly. The discovery snapshot is the only plugin input
// the command consumes (production builds it from the manifests; the seam
// tests construct it, the build_seam_prepared posture).
// ---------------------------------------------------------------------------

// The minimal anchored plugin declaration (the scan is lexical; the scratch
// member's source never compiles).
PLUGIN_WIRING_ANCHOR_SOURCE :: "get_juice_plugin :: () -> *X { return null; } @juice_plugin\n";

plugin_wiring_root :: (name: string) -> string {
    return otter_scratch(tprint("test-cmd-plugin-wiring/%1", name));
}

// A prepared workspace over a scratch root: one source file with a valid
// test block (the real collect/TRANSPILE fronts run) and, when member_name
// is non-empty, one member package carrying the anchor plus the root's
// Package.plugins declaration that activates it (ticket 056 — declaration =
// activation; dependencies never activate plugins).
plugin_wiring_prepared :: (root: string, member_name := "") -> Juice.Prepared_Workspace {
    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.discovery.has_package = true;
    prepared.discovery.root_package.name = "plugin-wiring-root";
    members: [..] Juice.Package;
    array_add(*members, .{name = "plugin-wiring-root", dir = root});
    if member_name != "" {
        // Heap-backed slices: the fields escape this frame (a fixed-array
        // literal's storage would die with it — the 028 deviation).
        plugins: [..] Juice.Plugin_Declaration;
        array_add(*plugins, .{id = member_name, version = "0.1.0"});
        prepared.discovery.root_package.plugins = plugins;
        array_add(*members, .{name = member_name, dir = path_slashes(tprint("%1/packages/%2", root, member_name))});
    }
    prepared.discovery.member_packages = members;
    return prepared;
}

test "Test command: plugin hits register and wire the metaprogram" {
    root := plugin_wiring_root("hit");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/wiring_tests.jai", "test \"plugin wiring hit\" {\n    expect(true);\n}\n"));
    expect(build_seam_write(root, "packages/scratch-plugin/module.jai", PLUGIN_WIRING_ANCHOR_SOURCE));
    prepared := plugin_wiring_prepared(root, "scratch-plugin");

    reset_test_command_seam();
    expect(test_prepared_workspace(*prepared, "", Hook_Registration.[], collect_test_files, test_spawn_test_compiler));
    expect(test_test_spawn_calls == 1);
    expect(test_test_spawn_path == path_slashes(tprint("%1/test_runner.jai", transpile_tree_dir(root))));

    // The workspace-level registration file landed under target/ with the
    // member's module import (the scan order = the declaration order).
    registration := workspace_plugin_registration_path(package_target_dir(root));
    expect(file_exists(registration));
    expect(file_contains(registration, "JUICE_PLUGIN_0 :: #import \"scratch-plugin\";"));

    // Both metaprogram options reached the generated text: the registration
    // #load (the absolute path), the package-root anchor (ticket 042
    // deviation 1 — the two go together), the embedded declaration configs
    // and the merge + resolver + lint observation wiring the ticket 056
    // generator emits.
    generated, read_ok := read_entire_file(test_test_spawn_path);
    expect(read_ok);
    expect(find_index_from_left(generated, "#import \"juice_core\";") >= 0);
    expect(find_index_from_left(generated, tprint("#load \"%1\";", registration)) >= 0);
    expect(find_index_from_left(generated, tprint("set_working_directory(\"%1\");", root)) >= 0);
    expect(find_index_from_left(generated, "plugin_configs: [] Plugin_Config = Plugin_Config.[.{ id = \"scratch-plugin\", version = \"0.1.0\", options = Option_Row.[] }];") >= 0);
    expect(find_index_from_left(generated, "merged_plugins = merge_plugins(plugins);") >= 0);
    expect(find_index_from_left(generated, "resolved_plugins = resolve_plugin_configs(merged_plugins.registry, plugin_configs);") >= 0);
    expect(find_index_from_left(generated, "for lint: resolved_plugins.lint_plugins {") >= 0);
    expect(find_index_from_left(generated, "lint.inspect_test_header(header, tc.subexpressions)") >= 0);
}

test "Test command: zero plugin hits leave the metaprogram unwired" {
    root := plugin_wiring_root("zero");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/wiring_tests.jai", "test \"plugin wiring zero\" {\n    expect(true);\n}\n"));
    prepared := plugin_wiring_prepared(root);

    reset_test_command_seam();
    expect(test_prepared_workspace(*prepared, "", Hook_Registration.[], collect_test_files, test_spawn_test_compiler));
    expect(test_test_spawn_calls == 1);
    // No registration file, not even the plugins directory.
    expect(!file_exists(workspace_plugin_registration_path(package_target_dir(root))));
    expect(!is_directory(target_plugins_dir(package_target_dir(root))));
    // The pre-plugin generated shape: no juice_core import and no merge
    // block (parent decision 8). The package-root anchor lives in the
    // embedded driver string, so it is always present now (the driver fold);
    // only the plugin wiring strings prove the zero-hit shape.
    generated, read_ok := read_entire_file(test_test_spawn_path);
    expect(read_ok);
    expect(find_index_from_left(generated, "juice_core") < 0);
    expect(find_index_from_left(generated, "merged_plugins") < 0);
}

test "Test command: a plugin scan failure fails the command before compiling" {
    root := plugin_wiring_root("scan-fail");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/wiring_tests.jai", "test \"plugin wiring scan fail\" {\n    expect(true);\n}\n"));
    // The snapshot names a member whose directory does not exist: the scan
    // must fail loudly, never degrade into "no plugins".
    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.discovery.has_package = true;
    prepared.discovery.root_package.plugins = Juice.Plugin_Declaration.[.{id = "ghost-plugin", version = "0.1.0"}];
    prepared.discovery.member_packages = Juice.Package.[
        .{name = "plugin-wiring-root", dir = root},
        .{name = "ghost-plugin", dir = path_slashes(tprint("%1/packages/ghost-plugin", root))},
    ];

    reset_test_command_seam();
    expect(!test_prepared_workspace(*prepared, "", Hook_Registration.[], collect_test_files, test_spawn_test_compiler));
    expect(test_test_spawn_calls == 0);
    // The COMPILE front fails before writing the runner product.
    expect(!file_exists(tprint("%1/test_runner.jai", transpile_tree_dir(root))));
    expect(!file_exists(workspace_plugin_registration_path(package_target_dir(root))));
}

test "Test command: a plugin registration write failure fails the command" {
    root := plugin_wiring_root("write-fail");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "src/wiring_tests.jai", "test \"plugin wiring write fail\" {\n    expect(true);\n}\n"));
    expect(build_seam_write(root, "packages/scratch-plugin/module.jai", PLUGIN_WIRING_ANCHOR_SOURCE));
    // Block the landing path: a directory squatting on the registration
    // file name makes the write fail.
    expect(make_directory_if_it_does_not_exist(workspace_plugin_registration_path(package_target_dir(root)), recursive = true));
    prepared := plugin_wiring_prepared(root, "scratch-plugin");

    reset_test_command_seam();
    expect(!test_prepared_workspace(*prepared, "", Hook_Registration.[], collect_test_files, test_spawn_test_compiler));
    expect(test_test_spawn_calls == 0);
    expect(!file_exists(tprint("%1/test_runner.jai", transpile_tree_dir(root))));
}

test "Test command: a non-member dependency fixture never registers plugins" {
    // The real t11 dependency fixture: a local source DEP that names no
    // workspace member. Discovery runs through the production face (real
    // manifest evaluation); the member set is the root alone, so the scan
    // surface stays empty and nothing reaches the metaprogram.
    fixture_root := path_slashes(tprint("%1/tests/data/test-dep-root", otter_root()));
    delete_directory_full(package_target_dir(fixture_root));
    defer delete_directory_full(package_target_dir(fixture_root));
    expect(ensure_published_modules());
    cache := path_slashes(otter_scratch("test-cmd-plugin-wiring/discovery-cache"));
    delete_directory_full(cache);
    discovery, discovery_ok := discover_workspace(fixture_root, cache, plugin_face_modules_dir());
    expect(discovery_ok && discovery.has_package);
    expect(discovery.root_package.dependencies.count == 1);
    expect(discovery.member_packages.count == 1);

    prepared: Juice.Prepared_Workspace;
    prepared.discovery = discovery;
    reset_test_command_seam();
    expect(test_prepared_workspace(*prepared, "", Hook_Registration.[], collect_test_files, test_spawn_test_compiler));
    expect(test_test_spawn_calls == 1);
    expect(!file_exists(workspace_plugin_registration_path(package_target_dir(fixture_root))));
    generated, read_ok := read_entire_file(test_test_spawn_path);
    expect(read_ok);
    expect(find_index_from_left(generated, "juice_core") < 0);
    expect(find_index_from_left(generated, "merged_plugins") < 0);
}

// ---------------------------------------------------------------------------
// Full-chain plugin lint E2E (ticket 046, parent 040 decisions 6/11, US
// 33-34): the real executable drives a scratch workspace built only under
// <otter>/target — the root manifest declares the real member through
// workspace.members plus the same-name DEP, the member package files are
// copied byte for byte from packages/juice-plugin-lint at test runtime, and
// a deliberately bad-named @test procedure exercises the shipped rule end to
// end: scan -> workspace registration -> generated test metaprogram ->
// collection-time lint observation -> compiler_report on the child's stderr.
// The suite still runs and the exit code stays 0 (a WARNING is advisory).
// The real member package root also runs its own suite as a CLI smoke.
// ---------------------------------------------------------------------------

// The scratch root manifest: BIN with no target (test needs only discovery,
// dependency preparation and the file scan), the real declaration surface
// (workspace.members + Package.plugins — ticket 056: no root DEP activates
// the plugin).
LINT_FULL_CHAIN_PACKAGE_SOURCE :: "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"lint-full-chain-e2e\",\n    version = \"0.1.0\",\n    type    = .BIN,\n    workspace = .{\n        members = string.[\"packages/juice-plugin-lint\"],\n    },\n    plugins = .[\n        .{id = \"juice-plugin-lint\", version = \"0.1.0\"},\n    ],\n};\n";

// The bad-named @test procedure plus one snake_case sibling: both must run
// and count; only the first draws the shipped rule's warning.
LINT_FULL_CHAIN_TEST_SOURCE :: "#import \"Testing\";\n\nBadName :: () {\n    expect(true);\n} @test\n\ntest_good_name :: () {\n    expect(true);\n} @test\n";

// The scratch workspace: the real member package files are read and written
// byte for byte (a runtime copy, never a fixture mirror), the root manifest
// declares them, and the test source carries the bad-named procedure.
build_lint_full_chain_scratch :: (scratch: string) -> bool {
    real_member := path_slashes(tprint("%1/packages/juice-plugin-lint", otter_root()));
    member_manifest, manifest_ok := read_entire_file(tprint("%1/package.jai", real_member));
    if !manifest_ok return false;
    member_module, module_ok := read_entire_file(tprint("%1/module.jai", real_member));
    if !module_ok return false;
    if !build_seam_write(scratch, "packages/juice-plugin-lint/package.jai", member_manifest) return false;
    if !build_seam_write(scratch, "packages/juice-plugin-lint/module.jai", member_module) return false;
    if !build_seam_write(scratch, "package.jai", LINT_FULL_CHAIN_PACKAGE_SOURCE) return false;
    return build_seam_write(scratch, "tests/bad_name_tests.jai", LINT_FULL_CHAIN_TEST_SOURCE);
}

test "E2E: the real member plugin lints a scratch workspace and the tests still run" {
    scratch := path_slashes(otter_scratch("lint-full-chain-e2e"));
    delete_directory_full(scratch);
    defer delete_directory_full(scratch);
    expect(build_lint_full_chain_scratch(scratch));

    result, output, errors := run_otter_child_at(scratch, string.["test"]);
    expect(expect_exit("lint-full-chain", result, 0));

    // The warning never blocks execution: both tests run (name-sorted) and
    // the suite reports the passing summary.
    expect(output_matches("lint-full-chain", output, string.[
        "[test] BadName",
        "[test] test_good_name",
        "2 passed, 0 failed",
    ]));

    // The finding arrives on the child's stderr as a compiler report: the
    // original package-relative path with the 1-based header line/column
    // (the compiler's header coordinate is the "(" column — the 042
    // precedent) and the shipped rule's message. The line is computed from
    // the scratch source, never hardcoded.
    bad_file := tprint("%1/tests/bad_name_tests.jai", scratch);
    line, name_column := fixture_line_col(bad_file, "BadName :: (");
    expect(line != 0 && name_column != 0);
    column := name_column + 11;   // "BadName :: " precedes the header's "("
    expect(child_output_contains("lint-full-chain", errors, tprint(
        "tests/bad_name_tests.jai:%1,%2: Warning: [juice lint] test procedure name must be snake_case: BadName",
        line, column)));
    // A warning must not turn into a compile error.
    expect(output_matches("lint-full-chain", errors, string.["Error:"], want = false));

    // The workspace-level registration really landed under the scratch
    // target/ (the ticket 045 production wiring); the deferred cleanup
    // removes the whole scratch tree afterwards.
    expect(file_exists(workspace_plugin_registration_path(package_target_dir(scratch))));
}

test "E2E: the real member package root runs its own suite green" {
    member_root := path_slashes(tprint("%1/packages/juice-plugin-lint", otter_root()));
    // Session products only (all under the member's target/): regenerate them
    // so stale views can never shadow the run, and leave the static member
    // tree untouched.
    delete_directory_full(package_target_dir(member_root));
    defer delete_directory_full(package_target_dir(member_root));
    result, output, errors := run_otter_child_at(member_root, string.["test"]);
    expect(expect_exit("member-root", result, 0));
    // The member's own three tests pass (ordering is not pinned); every
    // member test name is snake_case, so the shipped rule stays silent.
    expect(output_matches("member-root", output, string.["3 passed, 0 failed"]));
    expect(output_matches("member-root", errors, string.["[juice lint]"], want = false));
}

// ---------------------------------------------------------------------------
// Installed-layout plugin full-chain E2E (ticket 051, parent 048 decisions
// 1-3/7-9/12; US 1-9, 18-25, 33-35, 39-40): the real executable and its
// whole published modules tree copied into a scratch install with no sibling
// src/ or target/, driving a scratch workspace whose member is a byte-for-
// byte copy of the whole real packages/juice-plugin-lint tree (its tests/
// included). Unlike the ticket 046 E2E — which runs the dev-tree executable —
// every face the run consumes (Juice, Testing, the discovery source and the
// juice_core plugin closure) resolves from the modules directory adjacent to
// the installed executable, and no build-machine src path may cross into the
// install. The install artifact contract is pinned on the installed
// juice_core itself: only relative #load lines, no build root or drive
// letter, the four closure copies present, every target inside the install.
// ---------------------------------------------------------------------------

// The quoted #load statement the published juice_core emits:
// `#load "juice_internal/plugin_face/<file>";`.
PUBLISHED_LOAD_PREFIX :: "#load \"";

// The #load targets of a published module text, in line order: each
// line-leading `#load "<path>";` statement's quoted path. Lines carrying the
// word inside comments or other statements never match (only the trimmed
// line prefix counts).
published_module_load_paths :: (text: string) -> [..] string {
    load_paths: [..] string;
    for raw_line: split(text, "\n") {
        line := line_trimmed(raw_line);
        if line.count <= PUBLISHED_LOAD_PREFIX.count + 1 continue;
        if slice(line, 0, PUBLISHED_LOAD_PREFIX.count) != PUBLISHED_LOAD_PREFIX continue;
        rest := slice(line, PUBLISHED_LOAD_PREFIX.count, line.count - PUBLISHED_LOAD_PREFIX.count);
        quote := find_index_from_left(rest, "\"");
        if quote < 0 continue;
        array_add(*load_paths, copy_string(slice(rest, 0, quote)));
    }
    return load_paths;
}

// The whole-published-tree leak scan (ticket 053, review fix F4; parent 048
// US 33): every .jai artifact under the installed modules tree — the three
// module faces, the discovery source and the four plugin face closure copies
// — must be free of the build root and of the test-only otter_root() helper,
// and every published #load must be relative. The executable is outside the
// scanned tree on purpose: it embeds build-machine caller-location paths by
// design (ticket 053 F5 residual risk), so an "entire install tree has no
// build root" assertion must exclude the exe.
Published_Tree_Scan_Context :: struct {
    build_root: string;
    files:      s64;
    ok:         bool;
    failure:    string;
};

published_tree_scan_visitor :: (info: *File_Visit_Info, ctx: *Published_Tree_Scan_Context) {
    if !ctx.ok return;
    if info.is_directory return;
    if !ends_with(info.short_name, ".jai") return;
    ctx.files += 1;
    text, read_ok := read_entire_file(info.full_name);
    if !read_ok {
        ctx.ok = false;
        ctx.failure = tprint("unreadable published artifact: %1", info.full_name);
        return;
    }
    if find_index_from_left(text, ctx.build_root) >= 0 {
        ctx.ok = false;
        ctx.failure = tprint("the build root leaks into %1", info.full_name);
        return;
    }
    if find_index_from_left(text, "otter_root()") >= 0 {
        ctx.ok = false;
        ctx.failure = tprint("the test-only otter_root() helper leaks into %1", info.full_name);
        return;
    }
    for load_path: published_module_load_paths(text) {
        if path_is_absolute_portable(load_path) || find_index_from_left(load_path, "\\") >= 0 {
            ctx.ok = false;
            ctx.failure = tprint("absolute #load '%1' in %2", load_path, info.full_name);
            return;
        }
    }
}

// Walks the installed modules tree with the leak scan above.
scan_published_tree :: (modules_dir: string) -> Published_Tree_Scan_Context {
    ctx: Published_Tree_Scan_Context;
    ctx.build_root = otter_root();
    ctx.ok = true;
    if !visit_files(modules_dir, true, *ctx, published_tree_scan_visitor) {
        ctx.ok = false;
        ctx.failure = tprint("the published modules tree could not be walked: %1", modules_dir);
    }
    return ctx;
}

// The scratch member tree copy context: the real source root, the scratch
// destination root and the running failure flag (the visit_files callback
// cannot return a failure).
Copy_Member_Tree_Context :: struct {
    source_dir: string;
    dest_dir:   string;
    ok:         bool;
};

copy_member_tree_visitor :: (info: *File_Visit_Info, ctx: *Copy_Member_Tree_Context) {
    if !ctx.ok return;
    rel := advance(info.full_name, ctx.source_dir.count);
    while rel.count > 0 && (rel[0] == #char "/" || rel[0] == #char "\\") rel = slice(rel, 1, rel.count - 1);
    if info.is_directory {
        // Session products are not package source: a stale target/ from a
        // previous member smoke run never travels into the workspace.
        if rel == "target" info.descend_into_directory = false;
        return;
    }
    content, read_ok := read_entire_file(info.full_name);
    if !read_ok {
        ctx.ok = false;
        return;
    }
    if !build_seam_write(ctx.dest_dir, path_slashes(rel), content) ctx.ok = false;
}

// The whole real member package tree copied byte for byte (source files:
// package.jai, module.jai and tests/...; the member's session target/ is
// skipped) under the scratch workspace's packages/ directory. The runtime
// copy — never a fixture mirror — is the distribution-contract proof: the
// copied package must run unchanged under the installed tool.
copy_real_member_tree :: (scratch: string) -> bool {
    real_member := path_slashes(tprint("%1/packages/juice-plugin-lint", otter_root()));
    ctx: Copy_Member_Tree_Context;
    ctx.source_dir = real_member;
    ctx.dest_dir = path_slashes(tprint("%1/packages/juice-plugin-lint", scratch));
    ctx.ok = true;
    delete_directory_full(ctx.dest_dir);
    if !visit_files(real_member, true, *ctx, copy_member_tree_visitor, visit_directories = true) return false;
    return ctx.ok;
}

test "E2E: an installed juice runs the real member plugin and lints a scratch workspace" {
    // Session artifacts only: the scratch install and workspace are deleted
    // before the run (a stale copy must never mask a missing publication
    // step) and after it.
    layout := path_slashes(otter_scratch("installed-plugin-e2e"));
    scratch := path_slashes(otter_scratch("installed-plugin-e2e-workspace"));
    delete_directory_full(layout);
    delete_directory_full(scratch);
    defer delete_directory_full(layout);
    defer delete_directory_full(scratch);

    // The scratch install: the real executable plus the whole published
    // modules tree (recursively, the plugin face closure copies included),
    // and nothing else. No sibling src/ or target/ anywhere above the
    // executable — the installed-layout contract (tickets 037/039).
    bin_dir := tprint("%1/bin", layout);
    modules_dir := tprint("%1/modules", bin_dir);
    expect(make_directory_if_it_does_not_exist(modules_dir, recursive = true));
    installed_exe := tprint("%1/juice.exe", bin_dir);
    expect(copy_file(otter_exe(), installed_exe));
    expect(ensure_published_modules());
    copy_directory(plugin_face_modules_dir(), modules_dir);
    expect(!is_directory(tprint("%1/src", layout)));
    expect(!is_directory(package_target_dir(layout)));
    expect(!is_directory(tprint("%1/src", bin_dir)));
    expect(!is_directory(package_target_dir(bin_dir)));

    // The install artifact contract (parent 048 US 33-34, decisions 2/3): the
    // published juice_core loads its closure only by module-relative paths —
    // no build root, no drive letter, no absolute path, no backslash — and
    // every load target plus the four closure copies exist inside the
    // install. The generated text's four lines are the JUICE_CORE_LOAD_FILES
    // list in order (one list drives generation and copying).
    core_text, core_ok := read_entire_file(tprint("%1/juice_core.jai", modules_dir));
    expect(core_ok);
    expect(find_index_from_left(core_text, otter_root()) < 0,
        "the installed juice_core must not quote the build root");
    load_paths := published_module_load_paths(core_text);
    expect(load_paths.count == JUICE_CORE_LOAD_FILES.count);
    for file, index: JUICE_CORE_LOAD_FILES {
        expected := tprint("%1/%2", juice_plugin_face_relative_dir(), file);
        load_path := load_paths[index];
        expect(load_path == expected);
        expect(!path_is_absolute_portable(load_path));
        expect(find_index_from_left(load_path, "\\") < 0);
        resolved := tprint("%1/%2", modules_dir, load_path);
        expect(file_exists(resolved));
        expect(path_is_within(modules_dir, resolved));
        expect(file_exists(juice_plugin_face_file_path(modules_dir, file)));
    }

    // Whole-tree leak scan (ticket 053 F4, closing the US 33 blind spot that
    // only inspected juice_core): every .jai artifact under the installed
    // modules tree — closure copies and discovery source included — is free
    // of the build root and the test-only otter_root() helper, and no
    // published #load is absolute. The artifact count is the 048 set: three
    // module faces + the discovery source + the closure copies.
    scan := scan_published_tree(modules_dir);
    expect(scan.ok, "the installed modules tree leaks the build machine: %", scan.failure);
    expect(scan.files == 3 + 1 + JUICE_CORE_LOAD_FILES.count,
        "the installed modules tree must hold the eight published artifacts, got %", scan.files);

    // The scratch workspace: the real declaration surface (workspace.members
    // plus the Package.plugins declaration — the 046 constants updated by
    // ticket 056, no protocol extension), the whole real member package tree
    // copied byte for byte
    // (tests/ included), and the bad-named @test plus its snake_case
    // sibling at the root.
    expect(copy_real_member_tree(scratch));
    real_member := path_slashes(tprint("%1/packages/juice-plugin-lint", otter_root()));
    copied_member := path_slashes(tprint("%1/packages/juice-plugin-lint", scratch));
    for rel: string.["package.jai", "module.jai", "tests/lint_rule_tests.jai"] {
        source, source_ok := read_entire_file(tprint("%1/%2", real_member, rel));
        copied, copied_ok := read_entire_file(tprint("%1/%2", copied_member, rel));
        expect(source_ok && copied_ok && source == copied);
    }
    expect(build_seam_write(scratch, "package.jai", LINT_FULL_CHAIN_PACKAGE_SOURCE));
    expect(build_seam_write(scratch, "tests/bad_name_tests.jai", LINT_FULL_CHAIN_TEST_SOURCE));

    // The installed executable drives the scratch root: the plugin activates
    // from the copied member, both root tests run and count, and the shipped
    // rule's warning arrives on the child's stderr as a compiler report with
    // the original package-relative path and 1-based coordinates. The
    // warning is advisory: exit 0 and no Error: line.
    result, output, errors, _ := run_command(installed_exe, "test", working_directory = scratch, capture_and_return_output = true);
    expect(expect_exit("installed-plugin-e2e", result, 0));
    expect(output_matches("installed-plugin-e2e", output, string.[
        "[test] BadName",
        "[test] test_good_name",
        "2 passed, 0 failed",
    ]));
    bad_file := tprint("%1/tests/bad_name_tests.jai", scratch);
    line, name_column := fixture_line_col(bad_file, "BadName :: (");
    expect(line != 0 && name_column != 0);
    column := name_column + 11;   // "BadName :: " precedes the header's "("
    expect(child_output_contains("installed-plugin-e2e", errors, tprint(
        "tests/bad_name_tests.jai:%1,%2: Warning: [juice lint] test procedure name must be snake_case: BadName",
        line, column)));
    expect(output_matches("installed-plugin-e2e", errors, string.["Error:"], want = false));
    // The workspace-level registration really landed in the scratch target/
    // (the same production wiring the ticket 046 E2E exercises).
    expect(file_exists(workspace_plugin_registration_path(package_target_dir(scratch))));

    // The same installed executable in the copied member root: the package is
    // its own root, resolves juice_core from the install's modules directory
    // (the 050 distribution contract), and its own suite is green.
    result, output, errors = run_command(installed_exe, "test", working_directory = copied_member, capture_and_return_output = true);
    expect(expect_exit("installed-plugin-e2e member", result, 0));
    expect(output_matches("installed-plugin-e2e member", output, string.["3 passed, 0 failed"]));

    // Negative case (ticket 053, review fix F1; parent 048 decision 12 /
    // US 4): delete exactly one installed closure copy — from the scratch
    // install only, never the repository — and rerun the installed
    // executable at the scratch root. The plugin test program imports
    // juice_core, whose module-relative #load now names a missing file: the
    // compile must fail loudly (jai's original error, nonzero exit), never
    // degrade into a green or zero-plugin run. The deletion happens after
    // every positive assertion above, so they observe the complete install.
    missing_closure := juice_plugin_face_file_path(modules_dir, "plugin.jai");
    expect(file_exists(missing_closure));
    expect(file_delete(missing_closure));
    result, output, errors = run_command(installed_exe, "test", working_directory = scratch, capture_and_return_output = true);
    expect(expect_exit("installed-plugin-e2e missing-closure", result, 1),
        "a missing installed closure copy must fail the run");
    // jai's original compile error names the missing closure file.
    expect(child_output_contains("installed-plugin-e2e missing-closure", errors, "Error: Unable to open file"));
    expect(child_output_contains("installed-plugin-e2e missing-closure", errors, "plugin_face/plugin.jai"));
    // The command reports the compile failure instead of a green or
    // zero-plugin run: no test start lines, no summary, no "No tests found"
    // degrade.
    expect(output_matches("installed-plugin-e2e missing-closure", output, string.["[juice ERROR] Test compilation failed."]));
    expect(output_matches("installed-plugin-e2e missing-closure", output, string.[
        "[test] BadName",
        "[test] test_good_name",
        "passed, 0 failed",
        "[juice Test] No tests found.",
    ], want = false));
}