// ---------------------------------------------------------------------------
// Jaix guard (tickets 059/061, spec §8.3; the jaix-plugin map's hard
// constraint "Phase 1 扫整个 src/"): after the declaration/protocol hard cut
// (055) and the pre-step plugin (058), the command core and every other src
// module must carry no jaix knowledge at all — "命令与核心不再认识 jaix".
// This architecture guard scans every .jai file under src/ as source text
// (comments and string literals included, by design) for the
// case-insensitive token "jaix"/"JAIX" and fails with file:line:column
// evidence on any hit.
//
// Ticket 061 emptied the whitelist: the plugin moved from src/jaix_plugin.jai
// into the packages/juice-plugin-jaix member package, so src/ is now scanned
// with no allowance at all. The allowance mechanism stays (an empty list) so
// the negative self-test can still prove the scanner catches a violation —
// it runs over a scratch root carrying a seeded violation instead of over the
// now-clean src/ tree.
//
// Same discipline as the retirement guard: the scan root is src/ alone, so
// this file and the tests/data fixtures may carry the token freely.
// ---------------------------------------------------------------------------

#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import "Testing";

// One allowance: a whole file (line = "") or one exact trimmed line of a
// file. Phase 2 (ticket 061) has no allowed files — the list is empty.
Jaix_Guard_Allowance :: struct {
    path: string;   // package-relative, "/" separated
    line: string;   // "" = whole file; otherwise the exact trimmed line text
}

JAIX_GUARD_WHITELIST :: Jaix_Guard_Allowance.[];

// The guard's needle: a case-insensitive substring match (covers jaix/JAIX/
// Jaix and every compound such as jaix_plugin or juice-plugin-jaix).
JAIX_GUARD_NEEDLE :: "jaix";

Jaix_Guard_Hit :: struct {
    line:   s64;
    column: s64;
    text:   string;   // the trimmed original line
}

Jaix_Guard_Offender :: struct {
    path:   string;
    line:   s64;
    column: s64;
    text:   string;
}

// Every occurrence of the needle in one source text, line by line. Comments
// and string literals are included by design — this is a text scan, not a
// lexer, so a "harmless mention" cannot slip past.
jaix_guard_find_hits :: (source: string) -> [..] Jaix_Guard_Hit {
    hits: [..] Jaix_Guard_Hit;
    lines := split(source, "\n");
    for line, index: lines {
        lower := to_lower_copy(line);
        search_from := 0;
        while true {
            at := find_index_from_left(lower, JAIX_GUARD_NEEDLE, search_from);
            if at < 0 break;
            hit: Jaix_Guard_Hit;
            hit.line = index + 1;
            hit.column = at + 1;
            hit.text = trim(line, " \r\t");
            array_add(*hits, hit);
            search_from = at + 1;
        }
    }
    return hits;
}

// Whether the whitelist covers one hit: a whole-file entry admits every line
// of its file; a line entry admits exactly its trimmed text in its own file.
jaix_guard_allowed :: (path: string, hit: Jaix_Guard_Hit, whitelist: [] Jaix_Guard_Allowance) -> bool {
    for allowance: whitelist {
        if allowance.path != path continue;
        if allowance.line == "" return true;
        if allowance.line == hit.text return true;
    }
    return false;
}

// The scan set: every .jai under <root>/src (recursive).
jaix_guard_scan_files :: (root: string) -> [..] string {
    files: [..] string;
    visit_files(path_slashes(tprint("%1/src", root)), true, *files, jg_scan_visitor,
        visit_symlinks = false, follow_directory_symlinks = false);
    return files;
}

jg_scan_visitor :: (info: *File_Visit_Info, files: *[..] string) {
    if info.is_directory return;
    if info.is_symlink return;
    if !ends_with(info.short_name, ".jai") return;
    array_add(files, copy_string(info.full_name));
}

// Package-relative path of a scanned absolute path ("/" separated).
jg_rel_path :: (absolute: string, root: string) -> string {
    rel := path_slashes(absolute);
    prefix := path_slashes(root);
    while prefix.count > 0 && (prefix[prefix.count - 1] == #char "/" || prefix[prefix.count - 1] == #char "\\") prefix.count -= 1;
    if rel.count > prefix.count return slice(rel, prefix.count + 1, rel.count - prefix.count - 1);
    return rel;
}

// The scan: every offender in the src tree, whitelist applied. An unreadable
// file is itself an offender (line 0) — the guard never silently passes over
// its scan set.
jaix_guard_scan :: (root: string, whitelist: [] Jaix_Guard_Allowance) -> [..] Jaix_Guard_Offender {
    offenders: [..] Jaix_Guard_Offender;
    for path: jaix_guard_scan_files(root) {
        rel := jg_rel_path(path, root);
        source, ok := read_entire_file(path);
        if !ok {
            array_add(*offenders, .{path = rel, text = "unreadable"});
            continue;
        }
        for hit: jaix_guard_find_hits(source) {
            if jaix_guard_allowed(rel, hit, whitelist) continue;
            offender: Jaix_Guard_Offender;
            offender.path = rel;
            offender.line = hit.line;
            offender.column = hit.column;
            offender.text = hit.text;
            array_add(*offenders, offender);
        }
    }
    return offenders;
}

// The evidence line the guard prints for one offender.
jaix_guard_offender_line :: (offender: Jaix_Guard_Offender) -> string {
    return tprint("%1:%2:%3: %4", offender.path, offender.line, offender.column, offender.text);
}

// The removed protocol/type names from the 055 hard cut (spec §2.2/§11.12):
// the old record key's emission shape and the retired declaration type
// names. The built-in id constants TRANSPILE_PLUGIN_LOAD_ID /
// TRANSPILE_PLUGIN_TEST_BLOCK_ID stay — they are the reserved ids, not the
// retired record — hence the emitted-record shape as the needle.
removed_protocol_needles :: () -> [..] string {
    needles: [..] string;
    array_add(*needles, "TRANSPILE_PLUGIN=");
    array_add(*needles, "Transpile_Plugin_Declaration");
    array_add(*needles, "Transpile_Pipeline_Declaration");
    array_add(*needles, "Transpile_Plugin_Option");
    array_add(*needles, "Jaix_Prestep");
    array_add(*needles, "JAIX_CONFIG");
    array_add(*needles, "JAIX_EXE");
    return needles;
}

test "Jaix guard: the text matcher detects both spellings in comments and strings" {
    source := "// jaix comment\nname := \"JAIX_VALUE\";\nplain := 1;\nx := \"jaix\";\n";
    hits := jaix_guard_find_hits(source);
    expect(hits.count == 3);
    expect(hits[0].line == 1 && hits[0].column == 4);
    expect(hits[1].line == 2 && hits[1].column == 10);
    expect(hits[2].line == 4 && hits[2].column == 7);

    // Every occurrence on one line is reported (the scan cannot stop at the
    // first hit and hide the rest).
    expect(jaix_guard_find_hits("jaix jaix\n").count == 2);

    // Near misses stay clean.
    expect(jaix_guard_find_hits("jai := 1;\nja1x := 2;\n").count == 0);
}

test "Jaix guard: the whitelist is empty after the member move" {
    expect(JAIX_GUARD_WHITELIST.count == 0);

    // Nothing is admitted — not even the former plugin module path or the
    // retired structural entry load line (both are gone from src/).
    plugin_hit: Jaix_Guard_Hit = .{line = 1, column = 1, text = "// jaix plugin"};
    expect(!jaix_guard_allowed("src/jaix_plugin.jai", plugin_hit, JAIX_GUARD_WHITELIST));
    entry_load: Jaix_Guard_Hit = .{line = 1, column = 7, text = "#load \"jaix_plugin.jai\";"};
    expect(!jaix_guard_allowed("src/main.jai", entry_load, JAIX_GUARD_WHITELIST));
}

test "Jaix guard: the scanner turns red on a seeded violation (negative self-test)" {
    // The real scan is green today (the next tests), so the red channel is
    // proven over a scratch root: one seeded violation must surface with
    // path:line:column evidence. A guard that could never fail would be
    // worthless.
    root := otter_scratch("jaix-guard-negative");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(tprint("%1/src", root), recursive = true));
    expect(write_entire_file(tprint("%1/src/clean.jai", root), "plain := 1;\n"));
    expect(write_entire_file(tprint("%1/src/violation.jai", root), "// harmless\njaix_value := 2;\n"));
    offenders := jaix_guard_scan(root, JAIX_GUARD_WHITELIST);
    expect(offenders.count == 1);
    expect(offenders[0].path == "src/violation.jai");
    expect(offenders[0].line == 2);
    expect(offenders[0].column == 1);
    expect(find_index_from_left(jaix_guard_offender_line(offenders[0]), "src/violation.jai:2:1:") == 0);
}

test "Jaix guard: the static plugin module and its entry load line are gone" {
    // The Phase-1 whitelist entries must not linger as dead paths: the member
    // move deleted the module and the tool entry's #load line. A stale
    // allowance would otherwise silently weaken the guard.
    expect(!file_exists(path_slashes(tprint("%1/src/jaix_plugin.jai", otter_root()))));
    main_source, main_ok := read_entire_file(path_slashes(tprint("%1/src/main.jai", otter_root())));
    expect(main_ok);
    expect(jaix_guard_find_hits(main_source).count == 0);
}

test "Jaix guard: src carries no jaix token at all (empty whitelist)" {
    offenders := jaix_guard_scan(otter_root(), JAIX_GUARD_WHITELIST);
    for offender: offenders print("[jaix guard] %\n", jaix_guard_offender_line(offender));
    expect(offenders.count == 0);
}

test "Jaix guard: the removed jaix/transpile protocol names leave no residue in src" {
    needles := removed_protocol_needles();
    offenders: [..] string;
    for path: jaix_guard_scan_files(otter_root()) {
        rel := jg_rel_path(path, otter_root());
        source, ok := read_entire_file(path);
        if !ok {
            array_add(*offenders, tprint("%1: unreadable", rel));
            continue;
        }
        for needle: needles {
            if find_index_from_left(source, needle) < 0 continue;
            array_add(*offenders, tprint("%1: %2", rel, needle));
        }
    }
    for offender: offenders print("[jaix guard] %\n", offender);
    expect(offenders.count == 0);
}
