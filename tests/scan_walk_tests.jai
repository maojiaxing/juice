#import "Basic";
#import "Testing";
#import "File";
#import "File_Utilities";
#import "String";

// ---------------------------------------------------------------------------
// Scan walk tests (ticket 015): the shared walk skeleton's matrix — the
// injected exclusion set applied in scan order, the failure channel and the
// path helpers (old juice scan_walk.jai inline test semantics, migrated to
// the sibling test file — src modules stay test-free for the bootstrap
// #load discipline). The walk skeleton is declared in src/scan_walk.jai; the
// scratch fixtures derive from otter_root() and build_seam_write
// (tests/test_support.jai). The consumer-owned exclusion sets (the test
// command's dot/target/tests/data/modules faces, ticket 018) exercise the
// same injected-predicate mechanism this matrix pins.
// ---------------------------------------------------------------------------

// The test's exclusion context: the scan root plus the member boundaries
// (the production wrapper shape — ticket 018's collect context consumes
// the workspace discovery snapshot the same way).
Scan_Test_Context :: struct {
    root:        string;
    member_dirs: [..] string;
}

scan_test_dir_excluded :: (info: *File_Visit_Info, ctx: *Scan_Test_Context) -> bool {
    if info.short_name.count > 0 && info.short_name[0] == #char "." return true;
    for member: ctx.member_dirs {
        if paths_equal(info.full_name, member) return true;
    }
    return false;
}

scan_test_file_excluded :: (info: *File_Visit_Info, ctx: *Scan_Test_Context) -> bool {
    if info.short_name.count > 0 && info.short_name[0] == #char "." return true;
    if !ends_with(info.short_name, ".jai") return true;
    return false;
}

test "Scan walk: the skeleton applies injected exclusions in scan order" {
    root := otter_scratch("scan-walk-order");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "b_root.jai", ""));
    expect(build_seam_write(root, "a_root.jai", ""));
    expect(build_seam_write(root, "notes.txt", ""));
    expect(build_seam_write(root, ".hidden.jai", ""));
    expect(build_seam_write(root, "sub/calc.jai", ""));
    expect(build_seam_write(root, "sub/beta.jai", ""));
    expect(build_seam_write(root, "sub/.dotdir/x.jai", ""));
    expect(build_seam_write(root, "member-a/y.jai", ""));
    expect(build_seam_write(root, "member-a/nested/z.jai", ""));

    ctx: Scan_Test_Context;
    ctx.root = root;
    array_add(*ctx.member_dirs, copy_string(tprint("%1/member-a", root)));
    files, ok := collect_scan_files(root, *ctx, scan_test_dir_excluded, scan_test_file_excluded);
    expect(ok);
    // Excluded: the non-.jai extension, the dot entries at any depth and
    // the pruned member-a subtree (the member boundary mechanism — an
    // excluded directory cuts its whole subtree). Order: root files first,
    // then sub/ — files before subdirectories, both lexicographic.
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
    ctx.root = tprint("%1/tests/data/no-such-package", otter_root());
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
