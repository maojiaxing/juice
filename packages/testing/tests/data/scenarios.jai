#import "Basic";
#import "Testing";

// Loaded only by a child driver. tests/data is excluded from test discovery.
passing_assertions :: () {
    expect(1 + 1 == 2);
    expect(true, "not printed: %", 7);
    expect_eq("abc", "abc");
    expect_eq(2.5, 2.5);
    expect_eq(3, 3, "not printed either");
    print("pass-continued\n");
}

default_failure :: () {
    expect(false);
    print("UNREACHABLE default\n");
}

equality_failure :: () {
    expect_eq(3, 5);
    print("UNREACHABLE equality\n");
}

explicit_failure :: () {
    fail("boom");
    print("UNREACHABLE fail\n");
}

message_failure :: () {
    expect(false, "got % and %", 7, 9);
    print("UNREACHABLE message\n");
}

custom_equality_failure :: () {
    expect_eq(3, 5, "custom mismatch");
    print("UNREACHABLE custom equality\n");
}

deferred_failure :: () {
    defer print("defer-ran\n");
    expect(false, "deferred failure");
    print("UNREACHABLE defer\n");
}

next_test :: () {
    print("next-test-continued\n");
}

early_return :: () {
    should_return := true;
    if should_return return;
    print("UNREACHABLE return\n");
}

mapped_failure :: () {
    expect(2 + 2 == 5);
}

exercise_testing :: (fixture_path: string) {
    print("default-mapping=%\n", path_mapping.count);
    array_add(*path_mapping, .{view = "not-the-fixture.jai", original = "wrong.jai"});
    array_add(*path_mapping, .{view = fixture_path, original = "src/scenarios.jai"});
    run("pass", passing_assertions);
    run("default-failure", default_failure);
    run("equality-failure", equality_failure);
    run("explicit-failure", explicit_failure);
    run("message-failure", message_failure);
    run("custom-equality-failure", custom_equality_failure);
    run("deferred-failure", deferred_failure);
    run("next-test", next_test);
    run("bare-return", early_return);
    failures := finish();
    print("failures=%\n", failures);
    empty_failures := finish();
    print("empty-failures=%\n", empty_failures);
    run("fresh-suite", next_test);
    fresh_failures := finish();
    print("fresh-failures=%\n", fresh_failures);

    run("mapped", mapped_failure);
    mapped_failures := finish();
    print("mapped-failures=%\n", mapped_failures);
    array_reset(*path_mapping);
    print("reset-mapping=%\n", path_mapping.count);
    run("passthrough", mapped_failure);
    passthrough_failures := finish();
    print("passthrough-failures=%\n", passthrough_failures);
    final_failures := finish();
    print("final-failures=%\n", final_failures);
}
