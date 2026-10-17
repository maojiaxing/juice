// ---------------------------------------------------------------------------
// Scan walk: the shared package-scan skeleton behind the test command's
// discovery walk (commands/test.jai's collect_test_files) and the jaix
// pre-step's whole-package scan (jaix_front.jai's collect_jaix_files) —
// spec 054 decision 7, ticket 0057 (the 0050 strip-front convergence
// direction). One walk implementation, two thin consumer wrappers: each
// wrapper owns only its exclusion predicates and its error message; the
// walk orchestration, the raw entry collection, the deterministic
// enumeration and the path helpers live here.
//
// The walk contract: recursive from the package root via visit_files
// (directories and files, no symlink following), with two injectable
// exclusion predicates — Jai has no closures, so the predicates arrive as
// proc values over a consumer-owned context pointer (the pre-step seam
// posture). Enumeration is the deterministic DFS order: per directory,
// files first (lexicographic by name), then subdirectories (lexicographic),
// recursing. A failed walk (unscannable root) returns ok = false — the
// failure channel; the message is the consumer's ("test sources" vs "jaix
// sources" stay distinct).
//
// The jaix driver litter predicate (spec 054 decision 5/6) also lives
// here — one implementation, referenced by both wrappers' file exclusion
// predicates.
//
// Loaded by main.jai before jaix_front.jai and commands/test.jai, and not
// #loaded by the bootstrap build.jai metaprogram directly, so inline test
// blocks are allowed (they enter the bootstrap closure through src/main.jai
// and get stripped like every other src file).
// ---------------------------------------------------------------------------

#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

// One scanned file: the package-relative path ("/" separated, mirrors the
// package directory structure) and the absolute path of the source file.
// The shared record of both walks — the test discovery walk and the jaix
// pre-step scan return it (the closure probe keeps its own
// Build_Source_File: a probe record, not a scan record).
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
// jaix pre-step's spawn order derive from it.
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

// ---------------------------------------------------------------------------
// Driver litter exclusion (spec 054 decision 5, ticket 0058): a scanned
// .jai file is generated jaix driver litter, not package source, when a
// line in its head starts with the literal marker comment. The jaix CLI
// writes the marker as the driver's identification line —
// "// jaix transpile driver：JAIX_TRANSPILE_PROTOCOL=…" — right after the
// imports/#load/#run preamble (measured on disk: the first line is
// "#import \"Basic\";" and the marker sits within the first ~400 bytes), so
// the match scans lines inside a bounded head window — a partial read,
// never the whole file; the scan is the hot path. The protocol version
// after the literal prefix does not participate in the match: stable
// across jaix versions. Content-based rather than name-based, and
// unconditional (no jaix marker gating): legacy pre-dot-prefix hash-named
// litter is excluded too. An unreadable file is not litter — the real
// diagnostic is the consumer's (the transpile step or the compile).
// ---------------------------------------------------------------------------

// The literal marker prefix; a litter line starts with it at column 0.
JAIX_DRIVER_MARKER :: "// jaix transpile driver";

// Head window in bytes the litter check inspects. The real driver's marker
// line sits within the first ~400 bytes (imports, the #load config line,
// the #run block), so a small bounded read covers it with margin.
DRIVER_HEAD_SCAN_LIMIT :: 1024;

is_jaix_driver_litter :: (path: string) -> bool {
    f, open_ok := file_open(path);
    if !open_ok return false;
    defer file_close(*f);
    buffer: [DRIVER_HEAD_SCAN_LIMIT] u8;
    read_ok, count := file_read(f, buffer.data, DRIVER_HEAD_SCAN_LIMIT);
    if !read_ok return false;
    head: string;
    head.data = buffer.data;
    head.count = count;
    rest := head;
    while true {
        found, line, tail := split_from_left(rest, #char "\n");
        // CRLF tolerance: a trailing carriage return stays out of the match.
        if line.count > 0 && line[line.count-1] == #char "\r" line.count -= 1;
        if starts_with(line, JAIX_DRIVER_MARKER) return true;
        if !found break;
        rest = tail;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Inline tests: the walk skeleton matrix — one custom exclusion set
// exercises the orchestration, the enumeration order, the failure channel
// and the path helpers once (the consumers' own matrices cover their
// exclusion sets), plus the driver litter predicate matrix.
// build_seam_write and juice_root live in tests/test_support.jai.
// ---------------------------------------------------------------------------

Scan_Test_Context :: struct {
    root: string;
}

scan_test_dir_excluded :: (info: *File_Visit_Info, ctx: *Scan_Test_Context) -> bool {
    if info.short_name.count > 0 && info.short_name[0] == #char "." return true;
    if paths_equal(info.full_name, tprint("%1/skip_dir", ctx.root)) return true;
    return false;
}

scan_test_file_excluded :: (info: *File_Visit_Info, ctx: *Scan_Test_Context) -> bool {
    if info.short_name.count > 0 && info.short_name[0] == #char "." return true;
    if !ends_with(info.short_name, ".jai") return true;
    return false;
}

test "Scan walk: the skeleton applies injected exclusions in scan order" {
    root := tprint("%1/target/scan-walk-order", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "b_root.jai", ""));
    expect(build_seam_write(root, "a_root.jai", ""));
    expect(build_seam_write(root, "notes.txt", ""));
    expect(build_seam_write(root, ".hidden.jai", ""));
    expect(build_seam_write(root, "sub/calc.jai", ""));
    expect(build_seam_write(root, "sub/beta.jai", ""));
    expect(build_seam_write(root, "sub/.dotdir/x.jai", ""));
    expect(build_seam_write(root, "skip_dir/y.jai", ""));
    expect(build_seam_write(root, "skip_dir/nested/z.jai", ""));

    ctx: Scan_Test_Context;
    ctx.root = root;
    files, ok := collect_scan_files(root, *ctx, scan_test_dir_excluded, scan_test_file_excluded);
    expect(ok);
    // Excluded: the non-.jai extension, the dot entries at any depth and
    // the pruned skip_dir subtree. Order: root files first, then sub/ —
    // files before subdirectories, both lexicographic.
    expected := string.[
        "a_root.jai",
        "b_root.jai",
        "sub/beta.jai",
        "sub/calc.jai",
    ];
    if files.count != expected.count {
        print("[scan walk] got %1 files, want %2\n", files.count, expected.count);
        for file: files print("[scan walk] got %\n", file.rel_path);
    }
    expect(files.count == expected.count);
    for i: 0..expected.count-1 {
        expect(files[i].rel_path == expected[i]);
        expect(files[i].abs_path == tprint("%1/%2", root, expected[i]));
    }
}

test "Scan walk: an unscannable root fails the walk" {
    ctx: Scan_Test_Context;
    ctx.root = tprint("%1/tests/data/no-such-package", juice_root());
    files, ok := collect_scan_files(ctx.root, *ctx, scan_test_dir_excluded, scan_test_file_excluded);
    expect(!ok);
    expect(files.count == 0);
}

test "Scan walk: the path helpers" {
    expect(scan_entry_parent("C:/pkg/src/main.jai") == "C:/pkg/src");
    expect(scan_entry_parent("C:/pkg/") == "C:/pkg");
    expect(scan_rel_path("C:/pkg/src/main.jai", "C:/pkg") == "src/main.jai");
    expect(scan_rel_path("C:/pkg/main.jai", "C:/pkg/") == "main.jai");
    expect(scan_rel_path("C:/pkg", "C:/pkg") == "C:/pkg");
}

// The driver litter predicate matrix: the real on-disk driver shape (the
// marker sits after the imports/#load/#run preamble, not on the first
// line), the first-line variant, the literal prefix-only match, CRLF
// tolerance, and the no-false-positive faces (marker past the head window,
// marker not at column 0, unreadable file).
test "Driver litter: the head marker identifies real and legacy drivers" {
    root := tprint("%1/target/driver-litter", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(root, recursive = true));

    // The real driver shape, hash-named without a dot (legacy
    // pre-dot-prefix jaix): the marker line is not the first line.
    driver := tprint("%1/aabbccddeeff00112233.jai", root);
    expect(write_entire_file(driver, "#import \"Basic\";\n#import \"Compiler\";\n#import \"File\";\n\n#load \"C:/pkg/config.jai\";\n\n#run {\n    set_build_options_dc(.{do_output=false});\n    main();\n}\n\n// jaix transpile driver：JAIX_TRANSPILE_PROTOCOL=2\n// jaix transpile driver root_dir = C:/pkg\n"));
    expect(is_jaix_driver_litter(driver));

    // A marker on the first line matches too.
    first_line := tprint("%1/first-line.jai", root);
    expect(write_entire_file(first_line, "// jaix transpile driver：JAIX_TRANSPILE_PROTOCOL=1\n"));
    expect(is_jaix_driver_litter(first_line));

    // The literal prefix alone decides; the content after it does not
    // participate in the match.
    prefix_only := tprint("%1/prefix-only.jai", root);
    expect(write_entire_file(prefix_only, "// jaix transpile driver anything after\n"));
    expect(is_jaix_driver_litter(prefix_only));
}

test "Driver litter: CRLF line endings tolerate the carriage return" {
    root := tprint("%1/target/driver-litter-crlf", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(root, recursive = true));
    crlf := tprint("%1/crlf.jai", root);
    expect(write_entire_file(crlf, "#import \"Basic\";\r\n#load \"c.jai\";\r\n// jaix transpile driver root_dir = C:/pkg\r\n"));
    expect(is_jaix_driver_litter(crlf));
}

test "Driver litter: user files stay in — marker past the head window or not at line start" {
    root := tprint("%1/target/driver-litter-keep", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(root, recursive = true));

    // The marker past the bounded head window: a user file mentioning the
    // driver convention deep in its body stays scanned.
    filler: String_Builder;
    for 1..40 append(*filler, "// a long filler comment line with no marker in it\n");
    append(*filler, "// jaix transpile driver mention beyond the window\n");
    deep := tprint("%1/deep.jai", root);
    expect(write_entire_file(deep, builder_to_string(*filler)));
    expect(!is_jaix_driver_litter(deep));

    // The marker not at column 0: an indented mention stays scanned.
    indented := tprint("%1/indented.jai", root);
    expect(write_entire_file(indented, "    // jaix transpile driver indented\n"));
    expect(!is_jaix_driver_litter(indented));

    // An unreadable file is not litter — the real diagnostic stays with
    // the consumer.
    expect(!is_jaix_driver_litter(tprint("%1/no-such.jai", root)));
}
