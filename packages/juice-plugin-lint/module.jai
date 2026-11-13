#import "Basic";
#import "Compiler";
#import "juice_core";

// The real lint plugin member (ticket 044, parent 040 decision 7/10): the v1
// shipped rule — test procedure names must be snake_case ([a-z0-9_], non
// empty). This file is the package's root entry (convention 1: its #import
// name is the directory name "juice-plugin-lint") and the module the
// generated workspace registration file imports and compiles inside the
// test metaprogram. It MUST stay test-free: the registration program
// compiles this module directly, so test blocks would not compile there.
// The member's own tests live in tests/lint_rule_tests.jai and run with the
// member root as their own package.
//
// The plugin face is the published juice_core module, imported by name — the
// same name-imported module the registration file and the generated test
// metaprogram consume (one shared type identity per program; a #load
// duplicate in two scopes would split the types — spike-pinned by 025).
//
// Lint findings carry 1-based line/column by contract (src/plugin.jai). Jai
// beta 0.2.009 reports the Code_Procedure_Header location fields 1-based
// (spike-pinned against a declaration on line 11 by ticket 042), so the
// header's own l0/c0 pass through unchanged — the host never re-bases.

// The derived plugin value: using-inherits the unified face and adds nothing
// (the rule needs no options). get_juice_plugin returns this type; the
// framework consumes it through as_plugin's upcast (the type gate).
Test_Name_Lint_Plugin :: struct {
    using base: Juice_Plugin;
}

// The v1 rule predicate: a test procedure name must be non-empty and contain
// only [a-z0-9_]. Generated juice_test_N names and handwritten snake_case
// names pass; non-@test helpers never reach the observer in the first place
// (the host calls it only for collected test procedures).
test_name_is_snake_case :: (name: string) -> bool {
    if name.count == 0 return false;
    for i: 0..name.count-1 {
        c := name[i];
        if c >= #char "a" && c <= #char "z" continue;
        if c >= #char "0" && c <= #char "9" continue;
        if c == #char "_" continue;
        return false;
    }
    return true;
}

// The lint observer: one WARNING anchored at the violating procedure's
// header, naming the procedure. The finding carries the header's 1-based
// line/column; the host maps the level onto the compiler_report three-sink
// and reports it against the original package-relative path. A WARNING never
// changes the exit code (v1 lint is advisory).
test_name_lint_inspect :: (header: *Code_Procedure_Header, subexpressions: [] *Code_Node) -> [..] Lint_Finding {
    findings: [..] Lint_Finding;
    if test_name_is_snake_case(header.name) return findings;
    array_add(*findings, .{
        line    = cast(s64) header.l0,
        column  = cast(s64) header.c0,
        message = tprint("[juice lint] test procedure name must be snake_case: %", header.name),
        level   = .WARNING,
    });
    return findings;
}

// The acquisition contract: the @juice_plugin tail note is the lexical anchor
// the plugin scan matches (src/plugin_scan.jai). The lint face's name is the
// merged rule identity — merge_plugins rejects empty names and cross-plugin
// duplicates. The member plugin id is the member package name
// ("juice-plugin-lint", the ticket 056 design revision; the root declares the
// plugin through Package.plugins). The base options pointer points at the
// plugin instance (the framework channel; this rule needs no options, so its
// schema stays empty).
get_juice_plugin :: () -> *Test_Name_Lint_Plugin {
    plugin := New(Test_Name_Lint_Plugin);
    plugin.id = "juice-plugin-lint";
    plugin.version = "0.1.0";
    plugin.options = cast(*void) plugin;
    plugin.lint = New(Lint_Plugin);
    plugin.lint.name = "test-name-snake-case";
    plugin.lint.version = "0.1.0";
    plugin.lint.inspect_test_header = test_name_lint_inspect;
    return plugin;
} @juice_plugin
