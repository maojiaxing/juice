#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
#import "Testing";

// Golden and fixture paths derive from juice_root() (defined in
// test_commands.jai): the test program executes at compile time, where the
// working directory is the entry file's directory (target/transpile).

// ---------------------------------------------------------------------------
// Golden baselines (docs/transpiled-output-formatting.md §4). Every case dir
// holds one or more input *.jai files plus the expected view files
// (<name>.view.jai); negative cases hold the expected rendered diagnostics
// (diagnostic.txt). Rewrite the baselines by running `juice test` with the
// JUICE_UPDATE_GOLDEN environment variable set to any non-empty value (CI
// never sets it).
// ---------------------------------------------------------------------------

GOLDEN_CASES :: string.[
    "expand-basic",
    "loads",
    "immunity",
    "one-line",
    "test-free",
    "strip-basic",
    "multi",
];

NEGATIVE_CASES :: string.[
    "nested-in-proc",
    "nested-in-struct",
    "multiline-head",
    "shared-load-before",
    "shared-load-after",
    "strip-trailing",
    "unterminated",
];

// (GetEnvironmentVariableA comes from src/xdg.jai, loaded as a test view.)

wants_update :: () -> bool {
    #if OS == .WINDOWS {
        buffer: [512] u8;
        result := GetEnvironmentVariableA("JUICE_UPDATE_GOLDEN", buffer.data, 512);
        if result > 0 && result < 512 return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Unit tests over the pure function
// ---------------------------------------------------------------------------

expand_ctx :: (path := "src/foo.jai", next := 1) -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = .EXPAND;
    ctx.path = path;
    ctx.next_test_number = next;
    return ctx;
}

strip_ctx :: (path := "src/foo.jai", targets: [] Load_Target) -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = .STRIP;
    ctx.path = path;
    ctx.next_test_number = 1;
    ctx.load_targets = targets;
    return ctx;
}

count_lines :: (s: string) -> s64 {
    n := 1;
    for ch: s {
        if ch == #char "\n" n += 1;
    }
    return n;
}

test "Expand: named test header and entry" {
    result := transpile_source("test \"addition\" {\n    expect(2, 2);\n}\n", expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.tests.count == 1);
    expect(result.tests[0].name == "addition" && result.tests[0].number == 1 && result.tests[0].line == 1);
    expect(result.view == "juice_test_1 :: () -> () {\n    expect(2, 2);\n} @test\n");
}

test "Expand: anonymous test name is path:line" {
    result := transpile_source("test {\n}\n", expand_ctx());
    expect(result.tests.count == 1);
    expect(result.tests[0].name == "src/foo.jai:1");
    expect(result.view == "juice_test_1 :: () -> () {\n} @test\n");
}

test "Expand: @test sits before trailing comments" {
    result := transpile_source("test \"x\" {\n} // c\n", expand_ctx());
    expect(result.view == "juice_test_1 :: () -> () {\n} @test // c\n");
}

test "Expand: numbering continues across tests" {
    result := transpile_source("test \"a\" { }\ntest \"b\" { }\n", expand_ctx(next = 7));
    expect(result.tests.count == 2);
    expect(result.tests[0].number == 7 && result.tests[1].number == 8);
    expect(result.view == "juice_test_7 :: () -> () { } @test\njuice_test_8 :: () -> () { } @test\n");
}

test "Expand: in-package #load stripped" {
    result := transpile_source("#load \"helper.jai\";\n", expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.view == "// juice: load stripped: #load \"helper.jai\";\n");
}

test "Expand: multi-line #load gets (cont) placeholder" {
    result := transpile_source("#load\n\"multi.jai\";\n", expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.view == "// juice: load stripped: #load\n// juice: load stripped (cont)\n");
}

test "Expand: stripped #load keeps indentation" {
    result := transpile_source("    #load \"helper.jai\";\n", expand_ctx());
    expect(result.view == "    // juice: load stripped: #load \"helper.jai\";\n");
}

test "Expand: #load inside a test body is stripped" {
    result := transpile_source("test \"a\" {\n    #load \"helper.jai\";\n}\n", expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.view == "juice_test_1 :: () -> () {\n    // juice: load stripped: #load \"helper.jai\";\n} @test\n");
}

test "Expand: out-of-package and non-literal #load verbatim" {
    source := "#load \"../../outside.jai\";\n#load CONST_NAME;\n#load \"other\" + \".jai\";\n#import \"Basic\";\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 0);
    expect(result.view == source);
}

test "Expand: test-free file is identical" {
    source := "#import \"Basic\";\n\nmain :: () {\n    print(\"hello\\n\");\n}\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 0 && result.tests.count == 0);
    expect(result.view == source);
}

test "Expand: one-line blocks and one-line multi tests" {
    source := "test \"fast\" { assert(true); }\n\ntest \"a\" { } test \"b\" { }\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 0 && result.tests.count == 3);
    expected := "juice_test_1 :: () -> () { assert(true); } @test\n\njuice_test_2 :: () -> () { } @test juice_test_3 :: () -> () { } @test\n";
    expect(result.view == expected);
}

test "Immunity: test in strings, comments and calls" {
    source := "test :: () -> void { print(\"not a test\\n\"); }\n";
    source = tprint("%1%2", source, "x := \"test \\\"fake\\\" { }\";\n// test \"commented\" { }\n/* test \"blocked\" { } */\n");
    source = tprint("%1%2", source, "if ready test { work(); }\ntest(x);\ny := test;\n");
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 0 && result.tests.count == 0);
    expect(result.view == source);
}

test "Immunity: brace matching skips strings and comments" {
    source := "test \"braces\" {\n    s := \"{ } not braces\"; // } { \n    /* { } */\n}\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 0);
    expected := "juice_test_1 :: () -> () {\n    s := \"{ } not braces\"; // } { \n    /* { } */\n} @test\n";
    expect(result.view == expected);
}

test "Strip: test block becomes comment placeholder" {
    source := "test \"addition\" {\n    expect(2, 2);\n}\n";
    result := transpile_source(source, strip_ctx(targets = Load_Target.[]));
    expect(result.diagnostics.count == 0);
    expected := "// juice: test stripped: test \"addition\" {\n    // juice: test stripped\n// juice: test stripped\n";
    expect(result.view == expected);
}

test "Strip: one-line block keeps original text" {
    source := "test \"one\" { body(); }\n";
    result := transpile_source(source, strip_ctx(targets = Load_Target.[]));
    expected := "// juice: test stripped: test \"one\" { body(); }\n";
    expect(result.view == expected);
}

test "Strip: one-line multiple blocks share the line" {
    source := "test \"a\" { } test \"b\" { }\n";
    result := transpile_source(source, strip_ctx(targets = Load_Target.[]));
    expect(result.diagnostics.count == 0);
    expected := "// juice: test stripped: test \"a\" { } // juice: test stripped: test \"b\" { }\n";
    expect(result.view == expected);
}

test "Strip: placeholder keeps indentation" {
    source := "    test \"x\" {\n        body();\n    }\n";
    result := transpile_source(source, strip_ctx(targets = Load_Target.[]));
    expected := "    // juice: test stripped: test \"x\" {\n        // juice: test stripped\n    // juice: test stripped\n";
    expect(result.view == expected);
}

test "Strip: loads inside a stripped block vanish" {
    source := "test \"a\" {\n    #load \"helper.jai\";\n}\n";
    result := transpile_source(source, strip_ctx(targets = Load_Target.[]));
    expect(result.diagnostics.count == 0);
    expected := "// juice: test stripped: test \"a\" {\n    // juice: test stripped\n// juice: test stripped\n";
    expect(result.view == expected);
}

test "Strip: in-package #load rewritten to view path" {
    targets := Load_Target.[.{from = "src/helper.jai", to = "C:/pkg/target/transpile/hash1/src/helper.jai"}];
    result := transpile_source("#load \"helper.jai\";\n", strip_ctx(targets = targets));
    expect(result.diagnostics.count == 0);
    expect(result.view == "#load \"C:/pkg/target/transpile/hash1/src/helper.jai\";\n");
}

test "Strip: rewritten path is escaped" {
    targets := Load_Target.[.{from = "src/h.jai", to = "C:\\Users\\a\"b.jai"}];
    result := transpile_source("#load \"h.jai\";\n", strip_ctx(targets = targets));
    expect(result.view == "#load \"C:\\\\Users\\\\a\\\"b.jai\";\n");
}

test "Strip: test-free file is identical" {
    source := "#import \"Basic\";\n\nmain :: () {}\n";
    result := transpile_source(source, strip_ctx(targets = Load_Target.[]));
    expect(result.view == source);
}

test "Diagnostic: test inside a procedure body" {
    source := "foo :: () {\n    test \"inner\" { }\n}\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 1);
    d := result.diagnostics[0];
    expect(d.line == 2 && d.column == 5);
    expect(d.message == "test block 仅允许文件顶层");
    expect(result.view == source);
}

test "Diagnostic: test inside a struct body" {
    source := "Data :: struct {\n    x: int;\n    test { }\n}\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 1);
    d := result.diagnostics[0];
    expect(d.line == 3 && d.column == 5 && d.message == "test block 仅允许文件顶层");
}

test "Diagnostic: multi-line test head" {
    named := transpile_source("test\n    \"name\" {\n}\n", expand_ctx());
    anonymous := transpile_source("test\n{\n}\n", expand_ctx());
    expect(named.diagnostics.count == 1 && anonymous.diagnostics.count == 1);
    expect(named.diagnostics[0].line == 1 && named.diagnostics[0].column == 1);
    expect(named.diagnostics[0].message == "test 头必须位于同一行");
    expect(anonymous.diagnostics[0].message == "test 头必须位于同一行");
}

test "Diagnostic: #load sharing a line" {
    before := transpile_source("x := 1; #load \"a.jai\";\n", expand_ctx());
    after := transpile_source("#load \"a.jai\"; x := 1;\n", expand_ctx());
    expect(before.diagnostics.count == 1 && after.diagnostics.count == 1);
    expect(before.diagnostics[0].line == 1 && before.diagnostics[0].column == 9);
    expect(before.diagnostics[0].message == "#load 必须独占其行");
    expect(after.diagnostics[0].column == 1);
}

test "Diagnostic: statement after a stripped }" {
    source := "test \"x\" { body(); } after();\n";
    result := transpile_source(source, strip_ctx(targets = Load_Target.[]));
    expect(result.diagnostics.count == 1);
    d := result.diagnostics[0];
    expect(d.line == 1 && d.column == 22 && d.message == "test block 闭括号后不得有其他语句");
}

test "Diagnostic: unterminated test block" {
    source := "test \"forever\" {\n    expect(1, 1);\n";
    result := transpile_source(source, expand_ctx());
    expect(result.diagnostics.count == 1);
    d := result.diagnostics[0];
    expect(d.line == 1 && d.column == 1 && d.message == "test block 缺少闭合 }");
}

test "Diagnostic: missing view target in strip mode" {
    result := transpile_source("#load \"helper.jai\";\n", strip_ctx(targets = Load_Target.[]));
    expect(result.diagnostics.count == 1);
    expect(result.diagnostics[0].message == "in-package #load 缺少视图目标");
}

test "Line fidelity: view line counts match the source" {
    inputs := string.[
        "test \"a\" {\n    body();\n}\n",
        "test \"x\" { body(); }\n\ntest \"y\" {\n}\n",
        "#load \"h.jai\";\ntest \"a\" { }\n",
    ];
    for input: inputs {
        expand := transpile_source(input, expand_ctx());
        strip := transpile_source(input, strip_ctx(targets = Load_Target.[.{from = "src/h.jai", to = "v"}]));
        expect(expand.diagnostics.count == 0 && strip.diagnostics.count == 0);
        expect(count_lines(expand.view) == count_lines(input));
        expect(count_lines(strip.view) == count_lines(input));
    }
}

test "Line endings: CRLF normalized to LF" {
    result := transpile_source("test \"x\" {\r\n}\r\n", expand_ctx());
    expect(result.view == "juice_test_1 :: () -> () {\n} @test\n");
}

test "Named test reuses the decoded source token" {
    result := transpile_source("test \"a\\tb\" { }\n", expand_ctx());
    expect(result.tests.count == 1);
    expect(result.tests[0].name == "a\tb");
}

test "if test {} is not an anchor" {
    source := "if test { work(); }\n";
    result := transpile_source(source, expand_ctx());
    expect(result.view == source && result.tests.count == 0);
}

test "String decode keeps unknown escapes" {
    expect(decode_jai_string("C:\\Users") == "C:\\Users");
}

test "String decode and quote roundtrip" {
    decoded := decode_jai_string("a\\nb\\\"c\\\\d");
    expect(decoded == "a\nb\"c\\d");
    expect(quote_jai_string(decoded) == "\"a\\nb\\\"c\\\\d\"");
}

test "String escaping" {
    expect(escape_jai_string("C:\\a\"b") == "C:\\\\a\\\"b");
}

test "Load target resolution" {
    resolved, ok := resolve_load_target("src/foo.jai", "bar.jai");
    expect(ok && resolved == "src/bar.jai");
    resolved, ok = resolve_load_target("src/foo.jai", "../x.jai");
    expect(ok && resolved == "x.jai");
    _, ok = resolve_load_target("src/foo.jai", "../../x.jai");
    expect(!ok);
    _, ok = resolve_load_target("src/foo.jai", "C:/x.jai");
    expect(!ok);
    _, ok = resolve_load_target("src/foo.jai", "/x.jai");
    expect(!ok);
    resolved, ok = resolve_load_target("foo.jai", "bar.jai");
    expect(ok && resolved == "bar.jai");
    resolved, ok = resolve_load_target("src/foo.jai", "sub\\x.jai");
    expect(ok && resolved == "src/sub/x.jai");
    _, ok = resolve_load_target("src/foo.jai", "");
    expect(!ok);
}

// ---------------------------------------------------------------------------
// Content-addressed cache pure functions (ticket 0020)
// ---------------------------------------------------------------------------

// The key is a deterministic 16-hex-char hash; every component (relative
// path, source content, mode, version) participates in it.
test "Cache key is deterministic and component-sensitive" {
    key := transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION);
    expect(key == transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION));
    expect(key.count == 16);
    for ch: key {
        expect(is_hex_digit(ch));
    }
    expect(key != transpile_view_key("src/b.jai", "x := 1;\n", .EXPAND, Load_Target.[], JUICE_VERSION));
    expect(key != transpile_view_key("src/a.jai", "x := 2;\n", .EXPAND, Load_Target.[], JUICE_VERSION));
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .STRIP, Load_Target.[], JUICE_VERSION));
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], "1"));
    // The omitted version defaults to the juice version constant.
    expect(transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[]) == key);
}

// Merkle chain (issue 0008 resolution 5): in build mode the load rewrite
// targets embed the target views' hash directories, so a parent's key changes
// whenever a loaded view's key changes — and stays deterministically
// computable in dependency order.
test "Cache key forms a Merkle chain in build mode" {
    child := transpile_view_key("src/b.jai", "b := 1;\n", .STRIP, Load_Target.[], "1");
    child_other := transpile_view_key("src/b.jai", "b := 2;\n", .STRIP, Load_Target.[], "1");

    targets: [..] Load_Target;
    array_add(*targets, .{from = "src/b.jai", to = tprint("C:/pkg/target/transpile/%1/src/b.jai", child)});
    parent := transpile_view_key("src/a.jai", "#load \"b.jai\";\n", .STRIP, targets, "1");

    // The rewrite table participates in the key...
    expect(parent != transpile_view_key("src/a.jai", "#load \"b.jai\";\n", .STRIP, Load_Target.[], "1"));
    // ...and carries the child key, so the parent key tracks the child.
    targets_other: [..] Load_Target;
    array_add(*targets_other, .{from = "src/b.jai", to = tprint("C:/pkg/target/transpile/%1/src/b.jai", child_other)});
    expect(parent != transpile_view_key("src/a.jai", "#load \"b.jai\";\n", .STRIP, targets_other, "1"));
    // From-side changes rewrite the same way and must change the key too.
    targets_from: [..] Load_Target;
    array_add(*targets_from, .{from = "src/c.jai", to = tprint("C:/pkg/target/transpile/%1/src/b.jai", child)});
    expect(parent != transpile_view_key("src/a.jai", "#load \"b.jai\";\n", .STRIP, targets_from, "1"));
}

// Collision-avoiding path shape (issue 0007): <transpile_dir>/<hash>/<rel>
// mirrors the package-relative structure inside the hash directory, so
// "src/a/x.jai" and "src/a_x.jai" stay distinct where a flattened layout
// would collide.
test "Cache view path mirrors the relative structure" {
    dir := "C:/pkg/target/transpile";
    expect(transpile_hash_dir(dir, "abcd1234") == "C:/pkg/target/transpile/abcd1234");
    expect(transpile_view_path(dir, "abcd1234", "src/a/x.jai") == "C:/pkg/target/transpile/abcd1234/src/a/x.jai");
    expect(transpile_view_path(dir, "abcd1234", "src/a_x.jai") != transpile_view_path(dir, "abcd1234", "src/a/x.jai"));
    // The rel path is mirrored, not flattened into the hash directory name.
    expect(transpile_view_path(dir, "abcd1234", "src/a/x.jai") != transpile_hash_dir(dir, "abcd1234_src_a_x.jai"));
    // Backslash inputs are normalized to forward slashes.
    expect(transpile_view_path("C:\\pkg\\target\\transpile", "abcd1234", "src/a.jai") == "C:/pkg/target/transpile/abcd1234/src/a.jai");
}

// ---------------------------------------------------------------------------
// Golden / negative harness
// ---------------------------------------------------------------------------

Case_Config :: struct {
    mode:        Transpile_Mode = .EXPAND;
    path:        string;
    next_number: s64 = 1;
    load_targets: [..] Load_Target;
}

read_case_config :: (dir: string) -> Case_Config {
    config: Case_Config;
    content, ok := read_entire_file(tprint("%1/config.txt", dir), log_errors = false);
    if !ok return config;
    lines := split(content, "\n");
    for line: lines {
        trimmed := trim(line);
        if trimmed == "" || starts_with(trimmed, "#") continue;
        eq := -1;
        for i: 0..trimmed.count-1 {
            if trimmed[i] == #char "=" {
                eq = i;
                break;
            }
        }
        if eq <= 0 continue;
        key := slice(trimmed, 0, eq);
        value := slice(trimmed, eq + 1, trimmed.count - eq - 1);
        if key == "mode" {
            if value == "strip" config.mode = .STRIP;
        } else if key == "path" {
            config.path = copy_string(value);
        } else if key == "next_number" {
            number, parsed, _ := string_to_int(value);
            if parsed config.next_number = number;
        } else if key == "load_target" {
            eq2 := -1;
            for i: 0..value.count-1 {
                if value[i] == #char "=" {
                    eq2 = i;
                    break;
                }
            }
            if eq2 > 0 {
                array_add(*config.load_targets, .{
                    from = copy_string(slice(value, 0, eq2)),
                    to = copy_string(slice(value, eq2 + 1, value.count - eq2 - 1)),
                });
            }
        }
    }
    return config;
}

tp_string_less :: (a: string, b: string) -> bool {
    n := min(a.count, b.count);
    for i: 0..n-1 {
        if a[i] != b[i] return a[i] < b[i];
    }
    return a.count < b.count;
}

tp_sort_strings :: (list: [..] string) {
    for i: 1..list.count-1 {
        if i >= list.count break;
        key := list[i];
        j := i - 1;
        while j >= 0 && tp_string_less(key, list[j]) {
            list[j+1] = list[j];
            j -= 1;
        }
        list[j+1] = key;
    }
}

// A case directory's input files in production scan order (issue 0003,
// ticket 0019): within each directory, files first (lexicographic by name),
// then subdirectories (lexicographic), recursing. The driver golden derives
// its view list, mapping table and test numbering from this exact order.
collect_case_files :: (dir: string) -> [..] string {
    files: [..] string;
    collect_case_files_rec(dir, "", *files);
    return files;
}

collect_case_files_rec :: (dir: string, rel_prefix: string, files: *[..] string) {
    scan: Case_Dir_Scan;
    visited := visit_files(dir, false, *scan, case_dir_scan_visitor, visit_files = true, visit_directories = true);
    if !visited return;
    tp_sort_strings(scan.files);
    tp_sort_strings(scan.dirs);
    for name: scan.files {
        // driver.jai / first.jai are the case's own expected products,
        // never inputs.
        if ends_with(name, ".jai") && !ends_with(name, ".view.jai") && name != "driver.jai" && name != "first.jai" {
            array_add(files, tprint("%1%2", rel_prefix, name));
        }
    }
    for name: scan.dirs {
        if name.count > 0 && name[0] == #char "." continue;
        collect_case_files_rec(tprint("%1/%2", dir, name), tprint("%1%2/", rel_prefix, name), files);
    }
}

Case_Dir_Scan :: struct {
    files: [..] string;
    dirs:  [..] string;
}

case_dir_scan_visitor :: (info: *File_Visit_Info, scan: *Case_Dir_Scan) {
    if info.is_directory {
        array_add(*scan.dirs, copy_string(info.short_name));
    } else {
        array_add(*scan.files, copy_string(info.short_name));
    }
}

// The package root the generated products refer to. Expected files spell it
// as the <abs> placeholder (docs/transpiled-output-formatting.md §4.2).
golden_root :: () -> string {
    return juice_root();
}

// Replace every occurrence of the absolute root prefix with "<abs>", so the
// generated driver/metaprogram text compares byte for byte against the
// machine-independent expected files.
normalize_golden_abs :: (text: string) -> string {
    root := golden_root();
    result := text;
    while true {
        index := find_index_from_left(result, root);
        if index < 0 break;
        result = tprint("%1<abs>%2", slice(result, 0, index), slice(result, index + root.count, result.count - index - root.count));
    }
    return result;
}

compare_or_update :: (expected_path: string, actual: string, update: bool) -> bool {
    if update {
        ok := write_entire_file(expected_path, actual);
        print("[GOLDEN UPDATE] wrote %\n", expected_path);
        return ok;
    }
    expected, ok := read_entire_file(expected_path);
    if !ok {
        print("[GOLDEN FAIL] %: expected file missing\n", expected_path);
        return false;
    }
    if expected == actual {
        print("[GOLDEN PASS] %\n", expected_path);
        return true;
    }
    print("[GOLDEN FAIL] % (expected % bytes, actual % bytes)\n", expected_path, expected.count, actual.count);
    first_diff := 0;
    while first_diff < expected.count && first_diff < actual.count && expected[first_diff] == actual[first_diff] first_diff += 1;
    from := max(first_diff - 30, 0);
    print("  expected: ...%...\n", slice(expected, from, min(90, expected.count - from)));
    print("  actual:   ...%...\n", slice(actual, from, min(90, actual.count - from)));
    return false;
}

case_context :: (config: Case_Config, case_name: string, file: string) -> Transpile_Context {
    ctx: Transpile_Context;
    ctx.mode = config.mode;
    ctx.path = ifx config.path != "" then config.path else tprint("%1/%2", case_name, file);
    ctx.next_test_number = config.next_number;
    ctx.load_targets = config.load_targets;
    return ctx;
}

run_golden_cases :: (update: bool) -> bool {
    all_ok := true;
    for case_name: GOLDEN_CASES {
        dir := tprint("%1/tests/data/transpile/golden/%2", juice_root(), case_name);
        config := read_case_config(dir);
        files := collect_case_files(dir);
        if files.count == 0 {
            print("[GOLDEN FAIL] %1: no input files\n", dir);
            all_ok = false;
            continue;
        }
        next := config.next_number;
        // Driver inputs accumulated in enumeration order: every file exactly
        // once, its case-relative path, and the content-addressed test-mode
        // view path (the driver is a test-program product; the key derives
        // from the same source the view was generated from).
        driver_files: [..] Test_Source_File;
        driver_view_paths: [..] string;
        matches: [..] Test_Entry;
        for file: files {
            source, ok := read_entire_file(tprint("%1/%2", dir, file));
            if !ok {
                print("[GOLDEN FAIL] %1/%2: cannot read input\n", dir, file);
                all_ok = false;
                continue;
            }
            ctx := case_context(config, case_name, file);
            ctx.next_test_number = next;
            result := transpile_source(source, ctx);
            if result.diagnostics.count > 0 {
                for d: result.diagnostics {
                    print("[GOLDEN FAIL] %1/%2: diagnostic %3:%4,%5: %6\n", dir, file, ctx.path, d.line, d.column, d.message);
                }
                all_ok = false;
                continue;
            }
            next += result.tests.count;
            if !compare_or_update(tprint("%1/%2.view.jai", dir, file), result.view, update) all_ok = false;

            key := transpile_view_key(ctx.path, source, .EXPAND, Load_Target.[], JUICE_VERSION);
            array_add(*driver_view_paths, tprint("%1/target/transpile/%2/%3", golden_root(), key, ctx.path));
            file_rec: Test_Source_File;
            file_rec.rel_path = ctx.path;
            array_add(*driver_files, file_rec);
            for entry: result.tests array_add(*matches, entry);
        }
        // Every case locks the generated driver and metaprogram too
        // (docs/transpiled-output-formatting.md §4.1); absolute paths are
        // normalized to the <abs> placeholder before comparing.
        driver_text := generate_test_driver(driver_files, driver_view_paths, matches);
        if !compare_or_update(tprint("%1/driver.jai", dir), normalize_golden_abs(driver_text), update) all_ok = false;
        first_text := generate_test_metaprogram(
            tprint("%1/target/transpile/driver.jai", golden_root()),
            tprint("%1/modules", golden_root()),
            tprint("%1/target", golden_root()));
        if !compare_or_update(tprint("%1/first.jai", dir), normalize_golden_abs(first_text), update) all_ok = false;
    }
    return all_ok;
}

run_negative_cases :: (update: bool) -> bool {
    all_ok := true;
    for case_name: NEGATIVE_CASES {
        dir := tprint("%1/tests/data/transpile/negative/%2", juice_root(), case_name);
        config := read_case_config(dir);
        files := collect_case_files(dir);
        rendered: String_Builder;
        total := 0;
        for file: files {
            source, ok := read_entire_file(tprint("%1/%2", dir, file));
            if !ok {
                print("[NEGATIVE FAIL] %1/%2: cannot read input\n", dir, file);
                all_ok = false;
                continue;
            }
            ctx := case_context(config, case_name, file);
            result := transpile_source(source, ctx);
            total += result.diagnostics.count;
            for d: result.diagnostics {
                print_to_builder(*rendered, "%1:%2,%3: %4\n", ctx.path, d.line, d.column, d.message);
            }
        }
        if total == 0 {
            print("[NEGATIVE FAIL] %1: expected diagnostics, got none\n", dir);
            all_ok = false;
            continue;
        }
        if !compare_or_update(tprint("%1/diagnostic.txt", dir), builder_to_string(*rendered), update) all_ok = false;
    }
    return all_ok;
}

test "Golden baselines" {
    print("--- golden baselines ---\n");
    expect(run_golden_cases(wants_update()));
}

test "Negative cases" {
    print("--- negative cases ---\n");
    expect(run_negative_cases(wants_update()));
}

// ---------------------------------------------------------------------------
// Compile-and-run matrix (docs/transpiled-output-formatting.md §4.1):
// package-level fixtures under tests/data/transpile/run/, executed end to
// end via the real juice.exe `test` command; exit codes and the output
// contract are asserted (no full-output goldens).
// ---------------------------------------------------------------------------

tp_juice_exe :: () -> string {
    return tprint("%1/target/juice.exe", juice_root());
}

tp_run_juice_test :: (fixture: string, pattern := "") -> Process_Result, string, string {
    juice := tp_juice_exe();
    fixture_abs := tprint("%1/tests/data/transpile/run/%2", juice_root(), fixture);
    args: [..] string;
    array_add(*args, juice);
    array_add(*args, "test");
    if pattern != "" array_add(*args, pattern);
    result, output, errors, _ := run_command(..args, working_directory = fixture_abs, capture_and_return_output = true);
    return result, output, errors;
}

tp_expect_exit :: (name: string, result: Process_Result, want: s32) -> bool {
    if result.type == .EXITED && result.exit_code == want return true;
    print("[run %1] exit result %2/%3, want %4\n", name, result.type, result.exit_code, want);
    return false;
}

// Normalize CRLF to LF so expected blocks compare regardless of the child
// process's native line endings.
tp_normalize_crlf :: (s: string) -> string {
    has_cr := false;
    for ch: s {
        if ch == #char "\r" {
            has_cr = true;
            break;
        }
    }
    if !has_cr return s;
    builder: String_Builder;
    cursor := 0;
    i := 0;
    while i < s.count {
        if s[i] == #char "\r" {
            print_to_builder(*builder, "%", slice(s, cursor, i - cursor));
            print_to_builder(*builder, "\n");
            if i + 1 < s.count && s[i+1] == #char "\n" i += 1;
            cursor = i + 1;
        }
        i += 1;
    }
    if cursor < s.count print_to_builder(*builder, "%", slice(s, cursor, s.count - cursor));
    return builder_to_string(*builder);
}

tp_output_matches :: (name: string, output: string, needles: [] string, want := true) -> bool {
    normalized := tp_normalize_crlf(output);
    for needle: needles {
        found := find_index_from_left(normalized, needle) >= 0;
        if found != want {
            print("[run %1] output %2 '%3'\n", name, ifx found then "unexpectedly contains" else "missing", needle);
            print("  output was:\n%\n", output);
            return false;
        }
    }
    return true;
}

// 1-based line of the first occurrence of `needle` in `file`; 0 when missing.
fixture_line :: (file: string, needle: string) -> s64 {
    source, ok := read_entire_file(file);
    if !ok return 0;
    index := find_index_from_left(source, needle);
    if index < 0 return 0;
    line := 1;
    for i: 0..index-1 {
        if source[i] == #char "\n" line += 1;
    }
    return line;
}

// LIB packages have no effective target; `juice test` still discovers and
// runs every test in the package (spec 0013 US 23).
test "Run: LIB package passes via juice test" {
    result, output, _ := tp_run_juice_test("lib-package");
    expect(tp_expect_exit("lib", result, 0));
    expect(tp_output_matches("lib", output, string.["[juice Test] Found 3 tests; compiling test program..."]));
    anon_line := fixture_line(tprint("%1/tests/data/transpile/run/lib-package/module.jai", juice_root()), "test {");
    expect(anon_line != 0);
    expect(tp_output_matches("lib", output, string.[
        tprint("[test] lib arithmetic\n[test] lib strings\n[test] module.jai:%1\n3 passed, 0 failed\n", anon_line),
    ]));
}

// Pattern filtering end to end: a hit runs exactly the matched tests, a
// zero-hit pattern succeeds with an explanation and skips the build
// (spec 0013 US 16/17).
test "Run: pattern hit filters the executed tests" {
    result, output, _ := tp_run_juice_test("lib-package", "strings");
    expect(tp_expect_exit("pattern-hit", result, 0));
    expect(tp_output_matches("pattern-hit", output, string.[
        "[juice Test] Found 1 tests; compiling test program...",
        "[test] lib strings\n1 passed, 0 failed\n",
    ]));
    expect(tp_output_matches("pattern-hit", output, string.["[test] lib arithmetic"], want = false));
}

test "Run: zero-hit pattern succeeds with an explanation" {
    result, output, _ := tp_run_juice_test("lib-package", "zzz");
    expect(tp_expect_exit("pattern-zero", result, 0));
    expect(tp_output_matches("pattern-zero", output, string.["[juice Test] No tests matched 'zzz'."]));
}

// Crash semantics (spec 0013 US 28): a bare assert inside a test crashes the
// compiler — non-zero exit, no clean per-test attribution line and no
// summary; the crash point stays attributable by the [test] start line, and
// the compiler's own assert noise surfaces on stderr.
test "Run: bare-assert crash is non-zero without clean attribution" {
    result, output, errors := tp_run_juice_test("crash-package");
    if result.type != .EXITED || result.exit_code == 0 {
        print("[run crash] exit result %1/%2, want non-zero\n", result.type, result.exit_code);
    }
    expect(result.type == .EXITED && result.exit_code != 0);
    expect(tp_output_matches("crash", output, string.[
        "[test] crashy",
        "[juice ERROR] Test compilation failed.",
    ]));
    // No clean attribution: no mapped original-path failure line on stdout...
    expect(tp_output_matches("crash", output, string.["src/main.jai:"], want = false));
    // ...and no N passed / M failed summary.
    expect(tp_output_matches("crash", output, string.[" passed, "], want = false));
    expect(tp_output_matches("crash", errors, string.["Assertion failed!"]));
}
