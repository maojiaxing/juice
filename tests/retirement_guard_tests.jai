// ---------------------------------------------------------------------------
// Old-juice retirement guard (ticket 036, spec 006 decision 13): the sibling
// repository is out of the development loop, so no source, test, build or
// package file may reference its path again. This file scans src/, tests/,
// build.jai and package.jai for the forbidden sibling-repository path forms
// and fails on any hit. docs/ is outside the scan roots on purpose: the
// research corpus keeps historical source anchors as provenance
// documentation, not run dependencies (spec 006 decision 9) — the last test
// below pins that those references really are there and really are exempt.
//
// The needle strings are constructed from segments at runtime: this file
// lives under tests/ and the scan covers itself, so a literal needle here
// would be a self-inflicted hit.
// ---------------------------------------------------------------------------

#import "Basic";
#import "File_Utilities";
#import "String";
#import "Testing";

// The forbidden path forms: the sibling repository referenced relative to
// the package root, and its modules directory referenced by name — in both
// separators (Jai sources are slash-separated; Windows paths and prose can
// carry backslashes).
old_juice_path_needles :: () -> [..] string {
    needles: [..] string;
    array_add(*needles, tprint("..%1%2", "/", "juice"));
    array_add(*needles, tprint("..%1%2", "\\", "juice"));
    array_add(*needles, tprint("%1%2%3", "juice", "/", "modules"));
    array_add(*needles, tprint("%1%2%3", "juice", "\\", "modules"));
    return needles;
}

// Every forbidden form present in a text (needle order; empty = clean).
old_juice_path_hits :: (text: string) -> [] string {
    hits: [..] string;
    for needle: old_juice_path_needles() {
        if find_index_from_left(text, needle) >= 0 array_add(*hits, copy_string(needle));
    }
    return hits;
}

// 1-based line and column of a needle's first occurrence — the evidence
// line format the scan prints for an offending file.
guard_line_col :: (text: string, needle: string) -> (line: s64, col: s64) {
    index := find_index_from_left(text, needle);
    if index < 0 return 0, 0;
    line := 1;
    line_start := 0;
    for i: 0..index-1 {
        if text[i] == #char "\n" {
            line += 1;
            line_start = i + 1;
        }
    }
    return line, index - line_start + 1;
}

// The scan set: every .jai file under src/ and tests/ (recursive), plus the
// root build and package files. docs/research is deliberately absent.
guard_scan_visitor :: (info: *File_Visit_Info, files: *[..] string) {
    if info.is_directory return;
    if info.is_symlink return;
    if !ends_with(info.short_name, ".jai") return;
    array_add(files, copy_string(info.full_name));
}

collect_guard_scan_files :: () -> [] string {
    files: [..] string;
    roots := string.[tprint("%1/src", otter_root()), tprint("%1/tests", otter_root())];
    for root: roots {
        visit_files(root, true, *files, guard_scan_visitor, visit_symlinks = false, follow_directory_symlinks = false);
    }
    array_add(*files, tprint("%1/build.jai", otter_root()));
    array_add(*files, tprint("%1/package.jai", otter_root()));
    return files;
}

test "Old-juice retirement guard: the matcher detects constructed path forms" {
    needles := old_juice_path_needles();
    expect(needles.count == 4);

    // One synthetic text carrying all four forms — assembled from the
    // needles themselves, so this file never contains them literally.
    sample := tprint("a %1 b %2 c %3 d %4 e", needles[0], needles[1], needles[2], needles[3]);
    expect(old_juice_path_hits(sample).count == 4);

    // Near misses stay clean: a different sibling directory and the
    // product's own module name.
    expect(old_juice_path_hits("x ../other y juice/core z").count == 0);
}

test "Old-juice retirement guard: the guard's own source does not self-hit" {
    self_path := tprint("%1/tests/retirement_guard_tests.jai", otter_root());
    source, ok := read_entire_file(self_path);
    expect(ok);
    expect(old_juice_path_hits(source).count == 0);
}

test "Old-juice retirement guard: no scanned file references the sibling repository" {
    files := collect_guard_scan_files();
    expect(files.count > 2);
    offenders: [..] string;
    for path: files {
        source, ok := read_entire_file(path);
        if !ok {
            array_add(*offenders, tprint("%1: unreadable", path));
            continue;
        }
        hits := old_juice_path_hits(source);
        for hit: hits {
            line, col := guard_line_col(source, hit);
            array_add(*offenders, tprint("%1:%2:%3: %4", path, line, col, hit));
        }
    }
    for offender: offenders print("[retirement guard] %\n", offender);
    expect(offenders.count == 0);
}

test "Old-juice retirement guard: docs/research historical references stay exempt" {
    research_file := tprint("%1/docs/research/otter-refactor-research.md", otter_root());
    source, ok := read_entire_file(research_file);
    expect(ok);
    // The corpus does carry the historical source anchors; the scan roots
    // never include docs/, which is the exemption — provenance, not a run
    // dependency.
    expect(old_juice_path_hits(source).count > 0);
}
