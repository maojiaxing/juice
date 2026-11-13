// Fixture plugin package entry (tickets 042/044 antecedent): the root
// module.jai, whose #import name is the package directory name
// ("plugin-lint-fixture"). This plugin contributes ONE face: a lint rule
// that reports a WARNING for every collected test procedure whose name
// contains "Bad" (a synthetic stand-in for the shipped snake_case rule —
// ticket 044 builds the real member package).
//
// The fixture imports the plugin face by name (#import "juice_core") — the
// published library face (target/modules, landed by ensure_published_modules).
// The registration file's #import and this module must share that ONE
// name-imported module (a #load duplicate in two scopes would create
// incompatible duplicate types — spike-pinned). This file is compiled only
// by the E2E metaprogram child through the registration file; it lives
// under tests/data/, which test discovery exempts from the root package's
// test program.
//
// The observer reads the typechecked header's own location. Jai beta
// 0.2.009 reports Code_Procedure_Header location line/column fields 1-based
// (spike-pinned against a declaration on line 11); the Lint_Finding
// contract is 1-based, so the values pass through unchanged (the host never
// re-bases — ticket 042).
#import "Basic";
#import "Compiler";
#import "String";
#import "juice_core";

Lint_Fixture_Options :: struct {
    marker: string = "plugin-lint-fixture";
}

Lint_Fixture_Plugin :: struct {
    using base: Juice_Plugin;
    config: Lint_Fixture_Options;
}

lint_fixture_inspect :: (header: *Code_Procedure_Header, subexpressions: [] *Code_Node) -> [..] Lint_Finding {
    findings: [..] Lint_Finding;
    if find_index_from_left(header.name, "Bad") < 0 return findings;
    array_add(*findings, .{
        line    = cast(s64) header.l0,
        column  = cast(s64) header.c0,
        message = tprint("[juice lint] test procedure name contains 'Bad': %", header.name),
        level   = .WARNING,
    });
    return findings;
}

get_juice_plugin :: () -> *Lint_Fixture_Plugin {
    plugin := New(Lint_Fixture_Plugin);
    plugin.id = "plugin-lint-fixture";
    plugin.version = "1.0.0";
    plugin.options = cast(*void) plugin;
    plugin.lint = New(Lint_Plugin);
    plugin.lint.name = "test-name-no-bad";
    plugin.lint.version = "1.0.0";
    plugin.lint.inspect_test_header = lint_fixture_inspect;
    return plugin;
} @juice_plugin
