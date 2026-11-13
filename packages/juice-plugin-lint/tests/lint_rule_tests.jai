#import "Basic";
#import "Testing";

// The member's own tests (ticket 044): the v1 lint rule's predicate,
// exercised with this package as the root (juice test from
// packages/juice-plugin-lint). The module itself stays test-free — the
// registration program compiles it directly — so its tests live here in
// tests/, like any user package's. The assertion names come from the
// published Testing face the generated driver imports (the single register
// every test program consumes since ticket 035); the predicate is the
// top-level declaration the test program #loads from module.jai.
//
// The procedure names below are snake_case themselves: once ticket 045 wires
// the plugin scan into juice test, the shipped rule applied to its own suite
// stays quiet.

test_name_rule_accepts_generated_and_handwritten_names :: () {
    expect(test_name_is_snake_case("juice_test_1"));
    expect(test_name_is_snake_case("note_suite_x"));
    expect(test_name_is_snake_case("test_name_2"));
    expect(test_name_is_snake_case("a"));
} @test

test_name_rule_rejects_uppercase_names :: () {
    expect(!test_name_is_snake_case("BadName"));
    expect(!test_name_is_snake_case("hasUpper"));
    expect(!test_name_is_snake_case("Test"));
} @test

test_name_rule_rejects_empty_names :: () {
    expect(!test_name_is_snake_case(""));
    expect(!test_name_is_snake_case("has-dash"));
    expect(!test_name_is_snake_case("has space"));
    expect(!test_name_is_snake_case("dotted.name"));
} @test
