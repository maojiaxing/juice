// ---------------------------------------------------------------------------
// Test discovery: the pure-function surface behind the test metaprogram's
// note enumeration (spec section 7.1, tickets 016/017). The generated test
// metaprogram (ticket 017) #loads this file and wires these functions into
// its message loop: filter procedure headers by note text, reject duplicate
// names at collection time, order deterministically, number the list and
// isolate file sources — the primitives (ticket 016) plus the two wiring
// composites the generated text threads together (ticket 017):
// collect_test_entries consumes the accumulated header stream and
// generate_test_runner_code produces the injected call table. Pure functions
// over lists and strings only — no compiler state, no I/O — so the whole
// surface is directly testable (#load direct tests in
// tests/test_command_tests.jai).
//
// Test-free by chain convention (the bootstrap #load set discipline): the
// test metaprogram compiles this file at test program build time, where a
// test block would be illegal. Wired into main.jai's #load closure by
// ticket 018 (the test command references Test_Path_Pair — the 010
// deviation 5 convention); the generated test metaprogram also #loads this
// file at test program build time.
// ---------------------------------------------------------------------------

#import "Basic";
#import "String";

// A note matches the test convention when its text is exactly "test" or
// starts with "test(" (the parameterized form). Substring matches do not
// qualify — compiler-internal notes like PrintLike/NoProfile must never be
// mis-collected (research N section 1.4 point 3).
note_matches_test :: (text: string) -> bool {
    if text == "test" return true;
    return starts_with(text, "test(");
}

// One procedure header is a test when its name is non-empty and at least
// one of its notes matches the test convention (spec section 7.1: the note
// match plus name != "").
header_is_test :: (name: string, note_texts: [] string) -> bool {
    if name == "" return false;
    for text: note_texts {
        if note_matches_test(text) return true;
    }
    return false;
}

// Number of digits the numeric prefix comparison parses: beyond this the
// "juice_test_" prefix falls back to plain lexicographic order (test
// counters never reach s64 scale in practice; the guard keeps the parse
// total and the comparison well-defined).
NUMERIC_PREFIX_DIGIT_LIMIT :: 18;

// Parses the numeric "juice_test_" prefix of a name. Returns ok = false
// when the name does not carry the prefix followed by at least one digit.
// number is the numeric value of the digit run; rest is everything after
// it (research N risk 6 ruling: prefix strip + numeric part + remainder
// lexicographic).
parse_test_number_prefix :: (name: string) -> (number: s64, rest: string, ok: bool) {
    prefix := "juice_test_";
    if !starts_with(name, prefix) return 0, "", false;
    digits_start := prefix.count;
    if digits_start >= name.count return 0, "", false;
    if name[digits_start] < #char "0" || name[digits_start] > #char "9" return 0, "", false;
    digits_end := digits_start;
    while digits_end < name.count && name[digits_end] >= #char "0" && name[digits_end] <= #char "9" digits_end += 1;
    digits_count := digits_end - digits_start;
    if digits_count > NUMERIC_PREFIX_DIGIT_LIMIT return 0, "", false;
    number: s64 = 0;
    for i: digits_start..digits_end-1 {
        number = number * 10 + cast(s64) (name[i] - #char "0");
    }
    return number, slice(name, digits_end, name.count - digits_end), true;
}

// The deterministic test order (spec section 7.1 point 2, research N risk
// 6 ruling): name comparison with a numeric-aware "juice_test_N" prefix —
// when both names carry the prefix, the numeric parts compare as numbers
// and the remainders lexicographically (juice_test_2 sorts before
// juice_test_10); a final tiebreak on the raw name keeps the order total
// (juice_test_2 vs juice_test_02 are distinct collected names). Everything
// else compares as plain strings.
test_name_less :: (a: string, b: string) -> bool {
    a_num, a_rest, a_ok := parse_test_number_prefix(a);
    b_num, b_rest, b_ok := parse_test_number_prefix(b);
    if a_ok && b_ok {
        if a_num != b_num return a_num < b_num;
        rest_cmp := compare(a_rest, b_rest);
        if rest_cmp != 0 return rest_cmp < 0;
        return compare(a, b) < 0;
    }
    return compare(a, b) < 0;
}

// In-place insertion sort into the deterministic order. The collected test
// lists are small; insertion sort is stable, so equal names keep their
// collection order (duplicates are rejected before sorting anyway).
sort_test_names :: (names: [] string) {
    for i: 1..names.count-1 {
        if i >= names.count break;
        key := names[i];
        j := i - 1;
        while j >= 0 && test_name_less(key, names[j]) {
            names[j+1] = names[j];
            j -= 1;
        }
        names[j+1] = key;
    }
}

// Duplicate detection: the first index whose name equals an earlier entry's
// name, or -1 when all names are unique. The metaprogram rejects duplicates
// at collection time with a diagnostic (ticket 003 decision 5 — collisions
// must not silently shadow).
first_duplicate_test_name :: (names: [] string) -> s64 {
    for i: 0..names.count-1 {
        for j: 0..i-1 {
            if names[i] == names[j] return i;
        }
    }
    return -1;
}

// One numbered test entry: the global continuation number plus the name.
Numbered_Test :: struct {
    number: s64;
    name:   string;
}

// The global numbering continuation (juice t3 semantics, spec section
// 7.3): the names — already in the deterministic order — receive
// consecutive numbers starting at `start`; the caller threads the
// continuation across the whole program by passing the next start.
number_tests :: (names: [] string, start: s64 = 1) -> [] Numbered_Test {
    out: [..] Numbered_Test;
    for name, index: names {
        array_add(*out, .{number = start + cast(s64) index, name = name});
    }
    return out;
}

// File-source isolation (spec section 7.1 point 2): a discovered
// declaration's enclosing load path may contribute tests only when it is in
// the package's view file set or in the whitelist (the driver-injected
// compile views — the Testing module view family). Dependency closure
// declarations entering the message stream through shims are thereby
// excluded — the compiler-level equivalent of juice's "Dependency tests are
// neither discovered nor executed". Exact string comparison: the
// metaprogram normalizes both sides to the compiler's fully-pathed form
// before calling.
source_path_allowed :: (path: string, package_view_paths: [] string, whitelist_paths: [] string) -> bool {
    for p: package_view_paths {
        if p == path return true;
    }
    for p: whitelist_paths {
        if p == path return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Collection wiring composites (tickets 017/018): the generated test
// metaprogram threads these functions into its message loop — one consumes
// the accumulated header stream, one filters the collected list by the
// embedded pattern, the third produces the injected runner code. All stay
// pure over lists and strings (no compiler state, no I/O), so the whole
// wiring is directly testable.
// ---------------------------------------------------------------------------

// One accumulated header record: the test's procedure name plus the
// fully-pathed filename of its enclosing load (the source-isolation key,
// normalized to the compiler's fully-pathed form by the metaprogram).
Collected_Test_Source :: struct {
    name: string;
    path: string;
}

// One embedded path-mapping rewrite pair (spec section 7.2): `view` is the
// compiled file's absolute path as #caller_location reports it, `original`
// is the package-relative path printed in its place. The injected code
// assigns these into path_mapping (the published module's Path_Pair) —
// structurally identical, kept local so this file stays independent of the
// module face.
Test_Path_Pair :: struct {
    view:     string;
    original: string;
}

// The collection wiring (spec section 7.1): isolates sources by enclosing
// load path, orders names deterministically, rejects duplicates at
// collection time and numbers the result with the global numbering
// continuation (juice t3 semantics — the caller threads `numbering_start`).
// Returns the numbered entries plus the duplicate name ("" = none); the
// metaprogram turns a non-empty duplicate name into a compile error.
collect_test_entries :: (sources: [] Collected_Test_Source, package_view_paths: [] string, whitelist_paths: [] string, numbering_start: s64 = 1) -> (entries: [] Numbered_Test, duplicate_name: string) {
    isolated: [..] Collected_Test_Source;
    for source: sources {
        if source_path_allowed(source.path, package_view_paths, whitelist_paths) array_add(*isolated, source);
    }
    names: [..] string;
    for source: isolated array_add(*names, source.name);
    sort_test_names(names);
    duplicate_index := first_duplicate_test_name(names);
    if duplicate_index >= 0 return Numbered_Test.[], copy_string(names[duplicate_index]);
    return number_tests(names, numbering_start), "";
}

// The pattern filter (spec section 7.3, ticket 018): applied after
// collection — a non-empty pattern keeps every entry whose name contains it
// (substring, case-sensitive — the old juice filter semantics), the empty
// pattern keeps everything. Discovery never sees the filter: collection,
// ordering, duplicate rejection and numbering all run before it, so a
// filtered run never renumbers the remaining tests.
filter_test_entries :: (entries: [] Numbered_Test, pattern: string) -> [] Numbered_Test {
    if pattern == "" return entries;
    out: [..] Numbered_Test;
    for entry: entries {
        if find_index_from_left(entry.name, pattern) >= 0 array_add(*out, entry);
    }
    return out;
}

// The injected runner code (spec section 7.2): the old juice driver run-list
// shape (test.jai:502-517) — the path mapping reset and rewrite, one run
// call per numbered entry, and the finish() aggregate turning a non-zero
// failure count into a compile error. The metaprogram adds the returned text
// with add_build_string after .PHASE == .TYPECHECKED_ALL_WE_CAN (single
// compilation, no two-compilation probe): the injected #run executes at
// compile time, failures continue and finish() aggregates the exit code.
//
// The runner drives the published bare names (ticket 035's single register):
// every test program consumes the published Testing face through the
// driver's `#import "Testing"`, so run/finish/path_mapping are the same
// declarations the test bodies' bare assertions write. Driving one face on
// both sides is what makes the finish gate count failures — a split face
// (the retired prefixed-runner shape) counted nothing and let failing tests
// exit 0. The path-map rewrite is what maps failure coordinates back to the
// original package-relative lines.
generate_test_runner_code :: (entries: [] Numbered_Test, pairs: [] Test_Path_Pair) -> string {
    builder: String_Builder;
    print_to_builder(*builder, "#run {\n");
    print_to_builder(*builder, "    array_reset(*path_mapping);\n");
    for pair: pairs {
        print_to_builder(*builder, "    array_add(*path_mapping, .{ view = %1, original = %2 });\n",
            quote_test_string(pair.view), quote_test_string(pair.original));
    }
    for entry: entries {
        print_to_builder(*builder, "    run(%1, %2);\n", quote_test_string(entry.name), entry.name);
    }
    print_to_builder(*builder, "    if finish() != 0 assert(false);\n");
    print_to_builder(*builder, "}\n");
    return builder_to_string(*builder);
}

#scope_file;

// --- String-literal quoting for the generated runner code. File-private
// (src/transpile.jai owns the program-level quote_jai_string pair since
// ticket 022; src/metaprogram.jai keeps prefixed local copies until the
// build closure loads transpile.jai first — this file lands in the same
// full-package test scan, and the quoting faces stay independent until a
// later transpile layer consolidates them). ---

TEST_HEX_CHARS :: "0123456789abcdef";

escape_test_string :: (s: string) -> string {
    builder: String_Builder;
    for ch: s {
        if ch == #char "\\" { print_to_builder(*builder, "\\\\"); }
        else if ch == #char "\"" { print_to_builder(*builder, "\\\""); }
        else if ch == #char "\n" { print_to_builder(*builder, "\\n"); }
        else if ch == #char "\t" { print_to_builder(*builder, "\\t"); }
        else if ch == #char "\r" { print_to_builder(*builder, "\\r"); }
        else if ch < 32 {
            print_to_builder(*builder, "\\x%1%2", TEST_HEX_CHARS[ch >> 4], TEST_HEX_CHARS[ch & 15]);
        }
        else {
            tmp: [1] u8;
            tmp[0] = ch;
            print_to_builder(*builder, "%", to_string(tmp.data, 1));
        }
    }
    return builder_to_string(*builder);
}

quote_test_string :: (s: string) -> string {
    return tprint("\"%1\"", escape_test_string(s));
}