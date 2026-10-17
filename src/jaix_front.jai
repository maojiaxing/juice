// ---------------------------------------------------------------------------
// jaix front: the shared pre-step module for the jaix pre-step (spec 055
// decision 5/6/7): the whole-package scan (test discovery family exclusion
// rules plus the juice test block skip), the per-file jaix transpile spawn
// orchestration and the target/jaix/ mirror (package-relative structure,
// sidecar .map files land with the CLI's default behavior).
//
// Consumers: the Build command via the program-level #load (main.jai load
// order: ... -> transpile_front.jai -> metaprogram.jai -> this file, before
// commands/build.jai); the Test command wiring (ticket 059) reuses the same
// front. Not #loaded by the bootstrap build.jai metaprogram directly, so
// inline test blocks are allowed (they enter the bootstrap closure through
// src/main.jai and get stripped like every other src file).
//
// The scan contract: recursive from the package root, excluding dot entries
// at any depth, non-lowercase-.jai files, the root manifest, the root-level
// target/ (the mirror landing spot — excluded to prevent recursion),
// workspace member subtrees (boundary from the discovery snapshot) and
// links of any kind; enumeration order is the same deterministic DFS — per
// directory, files first (lexicographic) then subdirectories
// (lexicographic). The walk itself is the shared scan walk
// (src/scan_walk.jai); this module owns only the jaix exclusion set and the
// jaix-specific error message. Two additions over the test discovery set:
// the marker's config file is skipped (jaix's parser cannot round-trip the
// config shape, and the config is jaix's compile-time input rather than a
// transpile input), and files containing juice test blocks are skipped —
// jaix cannot parse test blocks without its test block plugin, and the
// marker config excludes that plugin (spec 055 US 18 double processing
// exclusion), so juice's own test block files keep their original transpile
// path and stay out of the mirror.
//
// The spawn contract (spec 055 decision 7): per file
// `jaix transpile <abs input> -o <abs output> --config <abs config>` — all
// absolute paths (jai switches the child's cwd during #run — 049 偏差 ⑭,
// 053 钉住). The child's stderr passes through verbatim; any nonzero exit fails
// the pre-step (command failure, no compile, no artifact). The mirror
// parents are created by juice before each spawn (jaix's driver writes the
// output without creating parent directories).
//
// The executable resolution: the marker exe field (non-empty) wins — a
// package-relative path resolves against the package root, an absolute path
// is used as-is; otherwise the PATH is probed for "jaix" ("jaix.exe" on
// Windows). A missing executable fails with a clear error before any spawn.
// ---------------------------------------------------------------------------

#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";

// ---------------------------------------------------------------------------
// Scan (test discovery family): the whole-package scan the pre-step mirrors.
// The walk is the shared scan walk (src/scan_walk.jai); this wrapper owns
// the jaix exclusion set (no root-level tests/data//modules/ exclusion,
// plus the config skip and the juice test block skip) and the jaix-specific
// error message.
// ---------------------------------------------------------------------------

Jaix_Collect_Context :: struct {
    root:        string;
    config_rel:  string;
    member_dirs: [..] string;
}

// Full-package scan: recursively collects every lowercase ".jai" source
// from the package root under the exclusion set documented in the file
// header. Member boundaries come from the workspace discovery snapshot
// (root package first), consumed without merging into discovery — the test
// discovery posture.
collect_jaix_files :: (prepared: *Prepared_Workspace) -> [] Scan_File, bool {
    collect: Jaix_Collect_Context;
    collect.root = prepared.discovery.root_dir;
    collect.config_rel = path_slashes(prepared.discovery.root_package.jaix.config);
    for pkg, index: prepared.discovery.member_packages {
        if index == 0 continue;
        array_add(*collect.member_dirs, copy_string(pkg.dir));
    }
    files, ok := collect_scan_files(collect.root, *collect, jaix_collect_directory_excluded, jaix_collect_file_excluded);
    if !ok {
        print("[juice ERROR] Could not scan package root for jaix sources: %\n", collect.root);
        return Scan_File.[], false;
    }
    return files, true;
}

// Directory-side exclusions: dot entries at any depth; the root-level
// target/ (managed products, the mirror landing spot); workspace member
// subtrees; and links of any kind — visit_files already skips symlink
// entries itself, Windows junctions surface as plain directories there, so
// they are inspected explicitly in line with the path_safety posture.
jaix_collect_directory_excluded :: (info: *File_Visit_Info, collect: *Jaix_Collect_Context) -> bool {
    if info.short_name.count > 0 && info.short_name[0] == #char "." return true;
    rel := scan_rel_path(info.full_name, collect.root);
    if paths_equal(rel, "target") return true;
    for member: collect.member_dirs {
        if paths_equal(info.full_name, member) return true;
    }
    entry := inspect_path_entry(info.full_name);
    return entry.is_symlink || entry.is_junction;
}

// File-side exclusions: dot entries at any depth, non-lowercase-.jai
// extensions, the scan root's own manifest (a nested source file that
// happens to be named package.jai is user code and stays scanned), the
// marker's config file (jaix's parser cannot round-trip the config shape —
// `X :: #import "X"` — and the config is jaix's compile-time input, not a
// transpile input; spec 055 decision 5's "scanned, identity view harmless"
// premise does not hold), and files containing juice test blocks — the
// mixed-package seam: jaix cannot parse test blocks without its test block
// plugin, and the marker config excludes that plugin (US 18 double
// processing exclusion), so juice's own test block files keep their
// original transpile path. An unreadable file stays included: the jaix
// child's own read-failure diagnostic passes through.
jaix_collect_file_excluded :: (info: *File_Visit_Info, collect: *Jaix_Collect_Context) -> bool {
    if info.short_name.count > 0 && info.short_name[0] == #char "." return true;
    if !ends_with(info.short_name, ".jai") return true;
    if info.short_name == "package.jai" && paths_equal(scan_entry_parent(info.full_name), collect.root) return true;
    if collect.config_rel != "" && paths_equal(scan_rel_path(info.full_name, collect.root), collect.config_rel) return true;
    source, ok := read_entire_file(info.full_name, log_errors = false);
    if ok && source_has_test_block(source) return true;
    return false;
}

// ---------------------------------------------------------------------------
// Mirror paths (spec 055 decision 6): target/jaix/ with the package-
// relative structure mirrored inside; the sidecar <file>.map files land
// next to the views by the CLI's default behavior.
// ---------------------------------------------------------------------------

jaix_mirror_dir :: (root_dir: string) -> string {
    return path_slashes(tprint("%1/target/jaix", root_dir));
}

jaix_mirror_view_path :: (root_dir: string, rel_path: string) -> string {
    return path_slashes(tprint("%1/%2", jaix_mirror_dir(root_dir), path_slashes(rel_path)));
}

// ---------------------------------------------------------------------------
// Executable resolution (spec 055 decision 4): the marker exe field
// (non-empty) wins — package-relative resolves against the package root,
// absolute is used as-is; otherwise the PATH is probed for "jaix"
// ("jaix.exe" on Windows, the v1 probe checks the .exe extension only).
// A missing executable fails with a clear error.
// ---------------------------------------------------------------------------

resolve_jaix_exe :: (marker: Jaix_Prestep, root_dir: string, path_value := "") -> (exe: string, ok: bool) {
    // The "" sentinel means the real process PATH (default parameter values
    // cannot be imperative calls); tests inject a crafted PATH string.
    path := path_value;
    if path == "" path = get_env("PATH");
    if marker.exe != "" {
        declared := ifx path_is_absolute_portable(marker.exe)
            then path_slashes(marker.exe)
            else path_slashes(tprint("%1/%2", root_dir, marker.exe));
        if file_exists(declared) && !is_directory(declared) return declared, true;
        print("[juice ERROR] jaix executable not found: %\n", declared);
        return "", false;
    }

    #if OS == .WINDOWS {
        separator := ";";
        candidate_name := "jaix.exe";
    } else {
        separator := ":";
        candidate_name := "jaix";
    }
    entries := split(path, separator);
    for entry: entries {
        if entry == "" continue;
        candidate := path_slashes(tprint("%1/%2", entry, candidate_name));
        if file_exists(candidate) && !is_directory(candidate) return candidate, true;
    }
    print("[juice ERROR] jaix executable not found: 'jaix' is not on PATH (declare exe in the package's jaix marker).\n");
    return "", false;
}

// ---------------------------------------------------------------------------
// The pre-step orchestration (spec 055 decision 7)
// ---------------------------------------------------------------------------

// The production per-file spawn: jaix transpile with all-absolute paths
// (input/output/config) and stderr captured for the passthrough. The
// exit-code contract: 0 = success, anything else = the pre-step fails.
spawn_jaix_transpile :: (exe: string, input: string, output: string, config: string) -> (exit_code: s64, stderr: string) {
    result, _, errors, _ := run_command(exe, "transpile", input, "-o", output, "--config", config, capture_and_return_output = true);
    if result.type == .EXITED return result.exit_code, errors;
    return 1, errors;
}

// The shared pre-step: resolve the executable, scan the whole package and
// jaix-transpile every scanned file into the target/jaix/ mirror. An
// absent marker is a no-op (zero behavior change); any spawn failure
// (nonzero exit — transpile diagnostics, config errors, write failures)
// fails the pre-step with the child's stderr passed through verbatim. The
// injectable transpile step is the seam tests cross with recording
// adapters instead of the real jaix executable (the build/test command
// seam posture).
run_jaix_prestep :: (
    prepared: *Prepared_Workspace,
    transpile: #type (exe: string, input: string, output: string, config: string) -> (exit_code: s64, stderr: string) = spawn_jaix_transpile
) -> bool {
    marker := prepared.discovery.root_package.jaix;
    if marker.config == "" return true;
    exe, exe_ok := resolve_jaix_exe(marker, prepared.discovery.root_dir);
    if !exe_ok return false;
    files, scan_ok := collect_jaix_files(prepared);
    if !scan_ok return false;
    config := path_slashes(tprint("%1/%2", prepared.discovery.root_dir, path_slashes(marker.config)));

    print("[juice] Running jaix pre-step (%1 files) -> target/jaix/...\n", files.count);
    for file: files {
        output := jaix_mirror_view_path(prepared.discovery.root_dir, file.rel_path);
        // The parent must exist before the spawn: jaix's driver writes the
        // output without creating parent directories.
        if !make_directory_if_it_does_not_exist(path_strip_filename(output), recursive = true) {
            print("[juice ERROR] Could not create mirror directory for %\n", file.rel_path);
            return false;
        }
        exit_code, stderr := transpile(exe, file.abs_path, output, config);
        if exit_code != 0 {
            if stderr.count > 0 print("%", stderr, to_standard_error = true);
            print("[juice ERROR] jaix pre-step failed for %\n", file.rel_path);
            return false;
        }
    }
    return true;
}

// ---------------------------------------------------------------------------
// Inline tests: the scan exclusion matrix, the executable resolution
// matrix and the pre-step orchestration seam. Shared helpers
// (build_seam_write, the fake spawn recording globals, reset_jaix_spawn)
// live in tests/test_support.jai.
// ---------------------------------------------------------------------------

// Full scan rules over a temp fixture: the test discovery exclusion family
// plus the config skip and the juice test block skip. Excluded: dot entries
// at any depth, non-.jai files, the root manifest, the root-level target/,
// the marker's config file, the member subtree. Included despite same
// names elsewhere: a nested package.jai, a nested target/ directory. The
// juice test block file stays out.
test "Jaix front: the scan applies the exclusion set in scan order" {
    root := tprint("%1/target/jaix-front-scan", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", "PACKAGE :: Package.{};\n"));
    expect(build_seam_write(root, "jaix.config.jai", "// config\n"));
    expect(build_seam_write(root, ".hidden.jai", "// dot file\n"));
    expect(build_seam_write(root, "notes.txt", "not jai\n"));
    expect(build_seam_write(root, ".hidden_dir/inside.jai", "// dot dir\n"));
    expect(build_seam_write(root, "lib_deep/package.jai", "// nested manifest is user code\n"));
    expect(build_seam_write(root, "src/main.jai", "main :: () {}\n"));
    expect(build_seam_write(root, "src/calc.jai", "half :: (n: int) -> int { return n / 2; }\n"));
    expect(build_seam_write(root, "src/calc_tests.jai", "test \"demo\" { }\n"));
    expect(build_seam_write(root, "src/sub/deep.jai", "deep :: 1;\n"));
    expect(build_seam_write(root, "src/target/ok.jai", "ok :: 2;\n"));
    expect(build_seam_write(root, "src/.dotdir/x.jai", "// dot dir nested\n"));
    expect(build_seam_write(root, "target/stale.jai", "// managed product\n"));
    expect(build_seam_write(root, "member/own.jai", "member :: 3;\n"));

    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.discovery.root_package = .{name = "root", version = "1", jaix = .{config = "jaix.config.jai"}};
    prepared.discovery.member_packages = Package.[
        .{name = "root", dir = root},
        .{name = "member", dir = tprint("%1/member", root)},
    ];
    files, ok := collect_jaix_files(*prepared);
    expect(ok);
    expected := string.[
        "lib_deep/package.jai",
        "src/calc.jai",
        "src/main.jai",
        "src/sub/deep.jai",
        "src/target/ok.jai",
    ];
    if files.count != expected.count {
        print("[jaix scan] got %1 files, want %2\n", files.count, expected.count);
        for file: files print("[jaix scan] got %\n", file.rel_path);
    }
    expect(files.count == expected.count);
    for i: 0..expected.count-1 {
        expect(files[i].rel_path == expected[i]);
        expect(files[i].abs_path == tprint("%1/%2", root, expected[i]));
    }
}

test "Jaix front: the scan rejects a missing package root" {
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = tprint("%1/tests/data/no-such-package", juice_root());
    _, ok := collect_jaix_files(*prepared);
    expect(!ok);
}

// ---------------------------------------------------------------------------
// Executable resolution matrix
// ---------------------------------------------------------------------------

test "Jaix front: exe resolution prefers the marker and resolves relative to the root" {
    root := tprint("%1/target/jaix-front-exe", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "tools/jaix.exe", ""));
    exe, ok := resolve_jaix_exe(.{config = "c", exe = "tools/jaix.exe"}, root);
    expect(ok && exe == tprint("%1/tools/jaix.exe", root));
    // An absolute marker exe is used as-is.
    exe, ok = resolve_jaix_exe(.{config = "c", exe = tprint("%1/tools/jaix.exe", root)}, root);
    expect(ok && exe == tprint("%1/tools/jaix.exe", root));
}

test "Jaix front: exe resolution falls back to the PATH probe in entry order" {
    root := tprint("%1/target/jaix-front-path", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "a/jaix.exe", ""));
    expect(build_seam_write(root, "b/jaix.exe", ""));
    path_value := tprint("%1/a;%1/b", root, root);
    exe, ok := resolve_jaix_exe(.{config = "c"}, root, path_value);
    expect(ok && exe == tprint("%1/a/jaix.exe", root));
}

test "Jaix front: a missing executable fails with the clear error" {
    _, ok := resolve_jaix_exe(.{config = "c", exe = "no-such-jaix.exe"}, "some-root");
    expect(!ok);
    _, ok = resolve_jaix_exe(.{config = "c"}, "some-root", "C:/nowhere");
    expect(!ok);
}

// ---------------------------------------------------------------------------
// Pre-step orchestration seam: the spawn fake records each call and returns
// the canned exit code/stderr (reset_jaix_spawn lives in
// tests/test_support.jai).
// ---------------------------------------------------------------------------

test "Jaix front: the pre-step spawns per file with absolute paths into the mirror" {
    root := tprint("%1/target/jaix-front-seam", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "package.jai", "PACKAGE :: Package.{};\n"));
    expect(build_seam_write(root, "jaix.config.jai", "// config\n"));
    expect(build_seam_write(root, "src/main.jai", "main :: () {}\n"));
    expect(build_seam_write(root, "src/calc.jai", "half :: (n: int) -> int { return n / 2; }\n"));
    expect(build_seam_write(root, "fake-jaix.exe", ""));

    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.discovery.root_package = .{name = "demo", version = "1", jaix = .{config = "jaix.config.jai", exe = "fake-jaix.exe"}};
    reset_jaix_spawn();
    expect(run_jaix_prestep(*prepared, fake_jaix_spawn));

    // The config file itself is skipped (jaix's compile-time input, not a
    // transpile input); every other scanned file spawns once.
    expect(test_jaix_spawn_calls == 2);
    expected := string.[
        tprint("%1/fake-jaix.exe|%1/src/calc.jai|%1/target/jaix/src/calc.jai|%1/jaix.config.jai", root),
        tprint("%1/fake-jaix.exe|%1/src/main.jai|%1/target/jaix/src/main.jai|%1/jaix.config.jai", root),
    ];
    expect(test_jaix_spawned.count == expected.count);
    for i: 0..expected.count-1 {
        expect(test_jaix_spawned[i] == expected[i]);
    }
    // The mirror parents exist on disk (the fake does not write files).
    expect(path_exists_as_directory(tprint("%1/target/jaix/src", root)));
}

test "Jaix front: a nonzero spawn fails the pre-step fast with stderr passthrough" {
    root := tprint("%1/target/jaix-front-fail", juice_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "jaix.config.jai", "// config\n"));
    expect(build_seam_write(root, "src/main.jai", "main :: () {}\n"));
    expect(build_seam_write(root, "fake-jaix.exe", ""));

    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = root;
    prepared.discovery.root_package = .{name = "demo", version = "1", jaix = .{config = "jaix.config.jai", exe = "fake-jaix.exe"}};
    reset_jaix_spawn();
    test_jaix_spawn_exit = 1;
    test_jaix_spawn_stderr = "boom: bad syntax\n";
    expect(!run_jaix_prestep(*prepared, fake_jaix_spawn));
    // The first scanned file (src/main.jai — the config is skipped) fails
    // the pre-step.
    expect(test_jaix_spawn_calls == 1);
}

test "Jaix front: an absent marker is a no-op" {
    prepared: Prepared_Workspace;
    prepared.discovery.root_dir = "somewhere";
    reset_jaix_spawn();
    expect(run_jaix_prestep(*prepared, fake_jaix_spawn));
    expect(test_jaix_spawn_calls == 0);
}
