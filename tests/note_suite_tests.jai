#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// Handwritten @test suite face (ticket 038, spec 006 decisions 6/7; spec
// sections 7.1/7.3/10): the stage-3 note-based style exercised by otter's
// own suite. These procedures are discovered by the same note enumeration
// that collects the EXPAND-generated juice_test_N procedures of the
// existing test blocks — one discovery source, one deterministic order
// (the juice_test_N prefix compares numerically, every other name
// lexicographically) and one global numbering (base 1, threaded across the
// whole program). They assert through the published bare Testing face the
// driver imports (`expect`/`expect_eq`), exactly like a user package's
// tests; no shared test declarations live here (the test support file
// stays the one home for those).
//
// Every procedure name below starts with 'n' while the generated test-block
// family starts with "juice_test_" ('j'), so the handwritten faces sort
// after the whole block family and the suite log shows the mixed discovery
// order directly — that log tail is the mixed-run evidence (ticket 038).
//
// @test(custom_name) is the parameterized note form: the note argument is
// identifier-form (jai rejects string literals in notes) and today only
// marks the discovery form — the display name the runner prints is the
// procedure name. Display-name restoration (@test("name") parameterized
// emission) is a future ticket, out of scope here; this procedure running
// at all is the custom-note discovery pin.
// ---------------------------------------------------------------------------

// The published Testing face, the same register a user package's bare
// assertions write: a passing handwritten test uses it end to end.
note_suite_published_face :: () {
    expect(1 + 1 == 2);
    expect_eq("handwritten", "handwritten");
} @test

// The parameterized note form (the "test(" prefix match). The suite log's
// `[test] note_suite_custom_note` line is the display-name pin: the name
// comes from the procedure, not from the note argument.
note_suite_custom_note :: () {
    expect(true);
} @test(custom_name)

// Mixed collection order: the numeric-aware juice_test_N comparison wins
// inside the block family (2 before 10), handwritten names compare
// lexicographically, and the whole order is total and deterministic.
note_suite_mixed_order :: () {
    names: [..] string;
    array_add(*names, "note_suite_beta");
    array_add(*names, "juice_test_10");
    array_add(*names, "note_suite_alpha");
    array_add(*names, "juice_test_2");
    array_add(*names, "juice_test_1");
    sort_test_names(names);
    expected := string.[
        "juice_test_1",
        "juice_test_2",
        "juice_test_10",
        "note_suite_alpha",
        "note_suite_beta",
    ];
    if names.count != expected.count {
        print("[note suite] got %1 names, want %2\n", names.count, expected.count);
    }
    expect(names.count == expected.count);
    for i: 0..expected.count-1 expect(names[i] == expected[i]);
    // Deterministic across calls: sorting the sorted list changes nothing.
    sort_test_names(names);
    for i: 0..expected.count-1 expect(names[i] == expected[i]);
} @test

// Mixed numbering: the collected names — test-block generated and
// handwritten forms together — receive consecutive numbers from the global
// base 1 with no gap and no duplicate. Isolation runs against the package
// view set the metaprogram supplies; everything here is inside it.
note_suite_mixed_numbering :: () {
    package_views := string.[
        "C:/pkg/target/transpile/aa/src/a.jai",
        "C:/pkg/target/transpile/bb/tests/b.jai",
    ];
    sources: [..] Collected_Test_Source;
    array_add(*sources, .{ name = "note_suite_second", path = package_views[1] });
    array_add(*sources, .{ name = "juice_test_1",    path = package_views[0] });
    array_add(*sources, .{ name = "note_suite_first", path = package_views[1] });
    array_add(*sources, .{ name = "juice_test_2",    path = package_views[0] });
    entries, duplicate := collect_test_entries(sources, package_views, string.[], numbering_start = 1);
    expect(duplicate == "");
    expect(entries.count == 4);
    expect(entries[0].name == "juice_test_1" && entries[0].number == 1);
    expect(entries[1].name == "juice_test_2" && entries[1].number == 2);
    expect(entries[2].name == "note_suite_first" && entries[2].number == 3);
    expect(entries[3].name == "note_suite_second" && entries[3].number == 4);
} @test

// No duplicate names survive collection: a mixed handwritten/generated
// collision is rejected before the run list exists (the metaprogram turns
// the duplicate name into a compile error, so no duplicate test can ever
// be numbered or run).
note_suite_mixed_duplicate_rejected :: () {
    package_views := string.[
        "C:/pkg/target/transpile/aa/src/a.jai",
        "C:/pkg/target/transpile/bb/tests/b.jai",
    ];
    sources: [..] Collected_Test_Source;
    array_add(*sources, .{ name = "note_suite_dup", path = package_views[1] });
    array_add(*sources, .{ name = "juice_test_1", path = package_views[0] });
    array_add(*sources, .{ name = "note_suite_dup", path = package_views[1] });
    entries, duplicate := collect_test_entries(sources, package_views, string.[]);
    expect(duplicate == "note_suite_dup");
    expect(entries.count == 0);
} @test
