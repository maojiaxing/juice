// ---------------------------------------------------------------------------
// Scan walk: the shared package-scan skeleton behind the test command's
// discovery walk (commands/test.jai's collect_test_files, ticket 018) and
// 1c's plugin package scan — old juice scan_walk.jai semantics (spec 054
// decision 7 / ticket 0057 shape, reference 1a section 12). One walk
// implementation, two thin consumer wrappers: each wrapper owns only its
// exclusion predicates and its error message; the walk orchestration, the
// raw entry collection, the deterministic enumeration and the path helpers
// live here.
//
// The shared walk: recursive from the package root via visit_files
// (directories and files, no symlink following), with two injectable
// exclusion predicates — Jai has no closures, so the predicates arrive as
// proc values over a consumer-owned context pointer (the pre-step seam
// posture). Enumeration is the deterministic DFS order: per directory,
// files first (lexicographic by name), then subdirectories (lexicographic),
// recursing. A failed walk (unscannable root) returns ok = false — the
// failure channel; the message is the consumer's ("test sources" vs plugin
// packages stay distinct).
//
// Test-free by chain convention (the bootstrap #load set discipline): the
// walk matrix lives in tests/scan_walk_tests.jai. Wired into main.jai's
// #load closure by ticket 018's collect_test_files (commands/test.jai loads
// after it — the 010 deviation 5 convention). paths_equal and path_slashes
// come from path_safety.jai (application scope of the same program, the old
// juice posture).
// ---------------------------------------------------------------------------

#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

// One scanned file: the package-relative path ("/" separated, mirrors the
// package directory structure) and the absolute path of the source file.
// The shared record of both walks — the test discovery walk and the plugin
// package scan return it.
Scan_File :: struct {
    rel_path: string;
    abs_path: string;
}

// Raw walk entries (short name plus full path) collected during the walk;
// the deterministic enumeration consumes them after the walk.
Scan_Entry :: struct {
    short_name: string;
    full_name:  string;
}

// The walk's internal state: the scan root, the collected raw entries, the
// consumer-owned context and the two exclusion predicates. Polymorphic over
// the consumer context type — the same posture as visit_files itself.
Scan_Walk_Context :: struct ($T: Type) {
    root:          string;
    files:         [..] Scan_Entry;
    dirs:          [..] Scan_Entry;
    user_data:     T;
    dir_excluded:  (info: *File_Visit_Info, user_data: T) -> bool;
    file_excluded: (info: *File_Visit_Info, user_data: T) -> bool;
}

// The shared walk: recursively collects the package's files under the two
// injected exclusion predicates and enumerates them in scan order. An
// excluded directory prunes its subtree. Returns ok = false when the root
// cannot be scanned (the failure channel — the consumer prints its own
// message).
collect_scan_files :: (
    root: string,
    user_data: $T,
    dir_excluded: #type (info: *File_Visit_Info, user_data: T) -> bool,
    file_excluded: #type (info: *File_Visit_Info, user_data: T) -> bool
) -> [] Scan_File, bool {
    walk: Scan_Walk_Context(T);
    walk.root = root;
    walk.user_data = user_data;
    walk.dir_excluded = dir_excluded;
    walk.file_excluded = file_excluded;
    visited := visit_files(root, true, *walk, scan_collect_visitor,
        visit_files = true, visit_directories = true,
        visit_symlinks = false, follow_directory_symlinks = false);
    if !visited return Scan_File.[], false;
    return enumerate_scan_files(*walk), true;
}

scan_collect_visitor :: (info: *File_Visit_Info, walk: *Scan_Walk_Context($T)) {
    if info.is_directory {
        if walk.dir_excluded(info, walk.user_data) {
            info.descend_into_directory = false;
            return;
        }
        entry: Scan_Entry;
        entry.short_name = copy_string(info.short_name);
        entry.full_name  = copy_string(info.full_name);
        array_add(*walk.dirs, entry);
        return;
    }
    if walk.file_excluded(info, walk.user_data) return;
    entry: Scan_Entry;
    entry.short_name = copy_string(info.short_name);
    entry.full_name  = copy_string(info.full_name);
    array_add(*walk.files, entry);
}

// Directory part of a walk entry without the trailing separator
// (path_strip_filename keeps it; the walk roots and dir names do not).
scan_entry_parent :: (full_name: string) -> string {
    parent := path_strip_filename(full_name);
    while parent.count > 0 && (parent[parent.count - 1] == #char "/" || parent[parent.count - 1] == #char "\\") parent.count -= 1;
    return parent;
}

// Package-relative path of a scanned absolute path: everything after the
// package root prefix, "/" separated.
scan_rel_path :: (absolute: string, root: string) -> string {
    rel := path_slashes(absolute);
    prefix := path_slashes(root);
    if prefix.count > 0 && prefix[prefix.count - 1] == #char "/" prefix.count -= 1;
    if rel.count > prefix.count return slice(rel, prefix.count + 1, rel.count - prefix.count - 1);
    return rel;
}

// Deterministic DFS enumeration in scan order: within each directory,
// files first (lexicographic by name), then subdirectories (lexicographic),
// recursing. The test command's transpile, call and report order and the
// plugin package scan's spawn order derive from it.
enumerate_scan_files :: (walk: Scan_Walk_Context($T)) -> [..] Scan_File {
    out: [..] Scan_File;
    stack: [..] string;
    array_add(*stack, copy_string(walk.root));
    while stack.count > 0 {
        dir := stack[stack.count - 1];
        stack.count -= 1;
        dir_files: [..] Scan_Entry;
        dir_subdirs: [..] Scan_Entry;
        for entry: walk.files {
            if paths_equal(scan_entry_parent(entry.full_name), dir) array_add(*dir_files, entry);
        }
        for entry: walk.dirs {
            if paths_equal(scan_entry_parent(entry.full_name), dir) array_add(*dir_subdirs, entry);
        }
        sort_scan_entries(dir_files);
        sort_scan_entries(dir_subdirs);
        for entry: dir_files {
            file: Scan_File;
            file.abs_path = path_slashes(entry.full_name);
            file.rel_path = scan_rel_path(entry.full_name, walk.root);
            array_add(*out, file);
        }
        // Push in reverse so the subdirectories pop in sorted order.
        i := dir_subdirs.count;
        while i > 0 {
            i -= 1;
            array_add(*stack, dir_subdirs[i].full_name);
        }
    }
    return out;
}

sort_scan_entries :: (entries: [] Scan_Entry) {
    for i: 1..entries.count-1 {
        if i >= entries.count break;
        key := entries[i];
        j := i - 1;
        while j >= 0 && compare(entries[j].short_name, key.short_name) > 0 {
            entries[j+1] = entries[j];
            j -= 1;
        }
        entries[j+1] = key;
    }
}

