// ---------------------------------------------------------------------------
// The jaix member plugin at the repository root (ticket 061, spec §8.3):
// integration and E2E coverage for the Phase 2 form. The member's unit
// matrix lives in packages/juice-plugin-jaix/tests/jaix_plugin_tests.jai and
// runs with the member root as its package; this file covers the parts that
// need the repository's test support (otter_root, the real executable child
// runners, the published modules):
//
// - the command-side registry no longer carries a static extension plugin
//   (the Phase-1 seam is gone; jaix is a member, resolved through the
//   command-level prepare + PRESTEP host);
// - the real jaix build/test E2E (the Phase-1 cases) under the member + host
//   form: a scratch copy of tests/data/jaix-demo with the real member tree
//   copied beside it, the real otter executable and the real jaix CLI
//   (PATH injection — the fixture declares no exe option);
// - the member package root runs its own suite;
// - the installed-layout E2E: a scratch install (executable + adjacent
//   modules/, no sibling src/ or target/), the real member package, the jaix
//   declaration and the full host chain, plus the missing-member,
//   missing-shim and missing-plugin-face negatives.
//
// All helpers are prefixed jp_ (the single-program test namespace
// convention). E2E availability: the sibling jaix-cli build
// (<projects>/jaix-cli/target/jaix.exe) is required; the tests assert its
// existence loudly instead of skipping, so an environment without the CLI
// shows up as a failure (the no-silent-skip rule).
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";

#if OS == .WINDOWS {
    jp_kernel32_env :: #system_library "kernel32";
    // The symbol name must stay exact: #foreign binds by the declared name.
    SetEnvironmentVariableA :: (lpName: *u8, lpValue: *u8) -> s32 #foreign jp_kernel32_env;
}

// ===========================================================================
// Paths and scratch helpers
// ===========================================================================

// The sibling jaix CLI build (otter and jaix-cli sit side by side in the
// projects directory).
jp_jaix_exe :: () -> string {
    return path_slashes(tprint("%1/../jaix-cli/target/jaix.exe", otter_root()));
}

// The real member package tree in this repository.
jp_member_package :: () -> string {
    return path_slashes(tprint("%1/packages/juice-plugin-jaix", otter_root()));
}

// The jaix-demo fixture.
jp_demo_fixture :: () -> string {
    return path_slashes(tprint("%1/tests/data/jaix-demo", otter_root()));
}

// Remove a directory tree (cmd's rmdir needs backslashes on Windows).
jp_delete_dir :: (path: string) -> bool {
    if !file_exists(path) return true;
    #if OS == .WINDOWS {
        res := run_command("cmd", "/c", "rmdir", "/S", "/Q", path_backslashes(path));
        return res.exit_code == 0;
    } else {
        res := run_command("rm", "-rf", path);
        return res.exit_code == 0;
    }
}

// Copy the real member tree (byte for byte; its session target/ is skipped
// so no stale products travel into a scratch workspace) to dest.
jp_copy_member_tree :: (dest: string) -> bool {
    source := jp_member_package();
    jp_delete_dir(dest);
    // copy_directory's root creation is non-recursive: create the parent
    // chain first (the scratch names are nested under target/).
    if !make_directory_if_it_does_not_exist(path_strip_filename(dest), recursive = true) return false;
    copy_directory(source, dest);
    jp_delete_dir(package_target_dir(dest));
    for rel: string.["package.jai", "module.jai", "tests/jaix_plugin_tests.jai"] {
        source_text, source_ok := read_entire_file(tprint("%1/%2", source, rel));
        dest_text, dest_ok := read_entire_file(tprint("%1/%2", dest, rel));
        if !source_ok || !dest_ok || source_text != dest_text return false;
    }
    return true;
}

// A scratch copy of the demo fixture as a full workspace: the fixture files,
// the real member under packages/juice-plugin-jaix and no target/ yet. The
// caller decides whether the package declaration carries the exe option.
jp_demo_workspace :: (name: string) -> string {
    root := otter_scratch(tprint("jaix-member-e2e/%1", name));
    jp_delete_dir(root);
    if !make_directory_if_it_does_not_exist(root, recursive = true) return "";
    copy_directory(jp_demo_fixture(), root);
    jp_delete_dir(package_target_dir(root));
    if !jp_copy_member_tree(tprint("%1/packages/juice-plugin-jaix", root)) return "";
    return root;
}

// Rewrite the demo package declaration with an absolute exe option (the
// installed-layout runs must not depend on the caller's PATH).
jp_write_demo_package_with_exe :: (root: string) -> bool {
    exe := path_slashes(jp_jaix_exe());
    builder: String_Builder;
    append(*builder, "#import \"Juice\";\n\n");
    append(*builder, "PACKAGE :: Package.{\n");
    append(*builder, "    name    = \"jaix-demo\",\n");
    append(*builder, "    version = \"0.1.0\",\n");
    append(*builder, "    type    = .BIN,\n");
    append(*builder, "    targets = Target.[.{name = \"jaix-demo\", main_file = \"src/main.jai\"}],\n");
    append(*builder, "    workspace = .{ members = string.[\"packages/juice-plugin-jaix\"] },\n");
    append(*builder, "    plugins = Plugin_Declaration.[\n");
    append(*builder, "        .{\n");
    append(*builder, "            id      = \"juice-plugin-jaix\",\n");
    append(*builder, "            version = \"0.1.0\",\n");
    append(*builder, "            options = Plugin_Option.[\n");
    append(*builder, "                .{key = \"config\", value = \"jaix.config.jai\"},\n");
    print_to_builder(*builder, "                .{key = \"exe\", value = %1},\n", quote_jai_string(exe));
    append(*builder, "            ],\n");
    append(*builder, "        },\n");
    append(*builder, "    ],\n");
    append(*builder, "};\n");
    return build_seam_write(root, "package.jai", builder_to_string(*builder));
}

// A scratch install: the real executable plus the whole published modules
// tree (recursively, the plugin face closure copies included), and nothing
// else — no sibling src/ or target/ (the installed-layout contract).
jp_install_layout :: (name: string) -> (bin_dir: string, modules_dir: string) {
    layout := otter_scratch(tprint("jaix-installed-e2e/%1", name));
    jp_delete_dir(layout);
    bin := tprint("%1/bin", layout);
    modules := tprint("%1/modules", bin);
    if !make_directory_if_it_does_not_exist(modules, recursive = true) return "", "";
    if !copy_file(otter_exe(), tprint("%1/juice.exe", bin)) return "", "";
    if !ensure_published_modules() return "", "";
    copy_directory(plugin_face_modules_dir(), modules);
    if !file_exists(tprint("%1/juice_core.jai", modules)) return "", "";
    if is_directory(tprint("%1/src", layout)) return "", "";
    if is_directory(package_target_dir(layout)) return "", "";
    return bin, modules;
}

// Put the CLI's directory at the front of the test program's PATH so the
// spawned juice children resolve the pre-step's "jaix" through the
// production probe. Idempotent: a repeated call keeps one prefix entry.
jp_prepend_jaix_to_path :: () {
    #if OS == .WINDOWS {
        dir := path_strip_filename(jp_jaix_exe());
        while dir.count > 0 && (dir[dir.count - 1] == #char "/" || dir[dir.count - 1] == #char "\\") dir.count -= 1;
        current := get_env("PATH");
        prefix := tprint("%1;", dir);
        if !starts_with(current, prefix) {
            SetEnvironmentVariableA(temp_c_string("PATH"), temp_c_string(tprint("%1%2", prefix, current)));
        }
    }
}

// Whether any root-level .jai file is driver litter (the pre-step must keep
// the package root clean: the CLI drivers land in target/jaix-drivers). The
// predicate is the member's own convention, restated here — the member
// module is not part of the root test program (it compiles through the
// registration import, a namespaced binding).
jp_root_has_litter :: (root: string) -> bool {
    names: [..] string;
    visit_files(root, false, *names, jp_root_file_collect,
        visit_files = true, visit_directories = false,
        visit_symlinks = false, follow_directory_symlinks = false);
    for name: names {
        if !ends_with(name, ".jai") continue;
        if jp_is_driver_litter(path_slashes(tprint("%1/%2", root, name))) return true;
    }
    return false;
}

// Content-marker litter check: a line starting with the driver marker inside
// the bounded head window.
jp_is_driver_litter :: (path: string) -> bool {
    f, open_ok := file_open(path);
    if !open_ok return false;
    defer file_close(*f);
    buffer: [1024] u8;
    read_ok, count := file_read(f, buffer.data, 1024);
    if !read_ok return false;
    head: string;
    head.data = buffer.data;
    head.count = count;
    rest := head;
    while true {
        found, line, tail := split_from_left(rest, #char "\n");
        if line.count > 0 && line[line.count-1] == #char "\r" line.count -= 1;
        if starts_with(line, "// jaix transpile driver") return true;
        if !found break;
        rest = tail;
    }
    return false;
}

jp_root_file_collect :: (info: *File_Visit_Info, names: *[..] string) {
    if info.is_directory return;
    array_add(names, copy_string(info.short_name));
}

// Substring search over an already-read text.
jp_text_contains :: (text: string, needle: string) -> bool {
    return find_index_from_left(text, needle) >= 0;
}

// ===========================================================================
// The command-side registry: no static extension seam
// ===========================================================================

test "Jaix member: the command registry holds built-ins only and jaix resolves as a member" {
    registry := command_plugin_registry();
    expect(registry.count == 2);
    expect(registry[0].id == "load" && registry[1].id == "test-block");
    expect(is_command_static_plugin_id("load"));
    expect(is_command_static_plugin_id("test-block"));
    // The Phase-1 static extension id (ticket 058) is no longer a command
    // registry value: the declaration names a workspace member now.
    expect(!is_command_static_plugin_id("juice-plugin-jaix"));
    expect(!is_command_static_plugin_id("juice-plugin-lint"));

    // The member's value carries the declaration identity and the acquisition
    // anchor the command-level scan matches.
    member_source, member_ok := read_entire_file(tprint("%1/module.jai", jp_member_package()));
    expect(member_ok);
    expect(find_index_from_left(member_source, "get_juice_plugin :: () -> *Jaix_Plugin") >= 0);
    expect(find_index_from_left(member_source, "} @juice_plugin") >= 0);
    expect(find_index_from_left(member_source, "#import \"juice_core\";") >= 0);
}

// ===========================================================================
// E2E: the real jaix build/test cases under the member + host form
// ===========================================================================

test "E2E: jaix pre-step build compiles the mirror through the member and host" {
    expect(file_exists(jp_jaix_exe()));
    jp_prepend_jaix_to_path();
    root := jp_demo_workspace("build");
    expect(root != "");
    defer jp_delete_dir(root);

    result, output, _ := run_otter_child_at(root, string.["build"]);
    expect(expect_exit("jaix-member build", result, 0, "build child"));
    // The pre-step ran inside the generated host (its stdout passes through
    // the child's inherited handles), and the build compiled the mirror entry.
    expect(child_output_contains("jaix-member build", output, "[juice] Running jaix pre-step (2 files) -> target/jaix/..."));
    expect(child_output_contains("jaix-member build", output, "[juice Build] Compiling Target 'jaix-demo' (src/main.jai) -> target/..."));

    // The host driver and its record file are session artifacts; the records
    // carry the substitution, the config drop and OK=1.
    expect(file_exists(plugin_host_path(package_target_dir(root))));
    records, records_ok := read_entire_file(plugin_host_records_path(package_target_dir(root)));
    expect(records_ok);
    expect(find_index_from_left(records, "SUBSTITUTE=src/main.jai|") >= 0);
    expect(find_index_from_left(records, "DROP=jaix.config.jai") >= 0);
    expect(find_index_from_left(records, "OK=1") >= 0);

    // The artifact runs the lowered code: the try error propagation really
    // executed (success and error paths).
    artifact := target_artifact_path(package_target_dir(root), "jaix-demo");
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("jaix-member artifact", run_result, 0, "build child"));
    expect(child_output_contains("jaix-member artifact", run_output, "double(20): NONE 40"));
    expect(child_output_contains("jaix-member artifact", run_output, "double(-6): NEGATIVE 0"));

    // The entry compiles the mirror path directly (no closure probe, no
    // transpile view): the generated build metaprogram quotes it.
    metaprogram := target_session_driver_path(target_build_dir(package_target_dir(root)), tprint("build-jaix-demo.jai"));
    expect(file_contains(metaprogram, path_slashes(tprint("%1/target/jaix/src/main.jai", root))));

    // The mirror: untouched files are byte-identical to the originals (the
    // round-trip identity), the try file is lowered, the test block file and
    // the config stay out, and the sidecar maps landed.
    mirror := tprint("%1/target/jaix", root);
    main_original, ok := read_entire_file(tprint("%1/src/main.jai", root));
    expect(ok);
    main_view, ok2 := read_entire_file(tprint("%1/src/main.jai", mirror));
    expect(ok2 && main_view == main_original);
    calc_view, ok3 := read_entire_file(tprint("%1/src/calc.jai", mirror));
    expect(ok3);
    expect(find_index_from_left(calc_view, "try_0_err, try_0_v := half(n);") >= 0);
    expect(!file_exists(tprint("%1/src/calc_tests.jai", mirror)));
    expect(!file_exists(tprint("%1/jaix.config.jai", mirror)));
    expect(file_exists(tprint("%1/src/calc.jai.map", mirror)));
    expect(file_exists(tprint("%1/src/main.jai.map", mirror)));

    // The CLI's session drivers landed in the pinned driver directory, not
    // next to the package sources.
    expect(is_directory(tprint("%1/target/jaix-drivers", root)));
    expect(!jp_root_has_litter(root));
}

test "E2E: jaix pre-step test compiles the mirror and keeps the mixed package" {
    expect(file_exists(jp_jaix_exe()));
    jp_prepend_jaix_to_path();
    root := jp_demo_workspace("test");
    expect(root != "");
    defer jp_delete_dir(root);

    result, output, _ := run_otter_child_at(root, string.["test"]);
    expect(expect_exit("jaix-member test", result, 0, "test child"));
    expect(child_output_contains("jaix-member test", output, "[juice] Running jaix pre-step (2 files) -> target/jaix/..."));
    // The numbering face: three tests from the original test block file,
    // numbered 1..3 (the config drop never shifts the sequence).
    expect(output_matches("jaix-member test", output, string.[
        "[test] juice_test_1",
        "[test] juice_test_2",
        "[test] juice_test_3",
        "3 passed, 0 failed",
    ]));

    transpile_dir := transpile_tree_dir(root);
    metaprogram_text, meta_ok := read_entire_file(tprint("%1/test_runner.jai", transpile_dir));
    expect(meta_ok);
    // The path mapping keeps the original package-relative paths; the
    // dropped config has no pair (and no view).
    expect(jp_text_contains(metaprogram_text, "original = \"src/calc.jai\""));
    expect(jp_text_contains(metaprogram_text, "original = \"src/calc_tests.jai\""));
    expect(jp_text_contains(metaprogram_text, "original = \"src/main.jai\""));
    expect(!jp_text_contains(metaprogram_text, "original = \"jaix.config.jai\""));

    // The embedded driver's view list names both source views.
    package_views := test_program_package_view_paths(metaprogram_text);
    calc_view_path := "";
    tests_view_path := "";
    for view: package_views {
        if ends_with(view, "/src/calc.jai") calc_view_path = view;
        if ends_with(view, "/src/calc_tests.jai") tests_view_path = view;
    }

    // The mirror file is the EXPAND input: its view carries the lowering.
    expect(calc_view_path != "");
    calc_view, calc_ok := read_entire_file(calc_view_path);
    expect(calc_ok);
    expect(find_index_from_left(calc_view, "try_0_err, try_0_v := half(n);") >= 0);
    // The original extension statement is gone from the view (the source
    // file's comment mentions it, so the check anchors the statement's own
    // line shape).
    expect(find_index_from_left(calc_view, "\n    x := try half(n);") < 0);

    // The test block file stays on its original path: its view rewrites the
    // blocks into the numbered procedures (the original source is the input).
    expect(tests_view_path != "");
    tests_view, tests_ok := read_entire_file(tests_view_path);
    expect(tests_ok);
    expect(find_index_from_left(tests_view, "juice_test_1 :: () -> () {") >= 0);
    expect(find_index_from_left(tests_view, "juice_test_3 :: () -> () {") >= 0);

    // The mirror and the driver directory exist (the pre-step really ran).
    expect(file_exists(tprint("%1/target/jaix/src/calc.jai", root)));
    expect(is_directory(tprint("%1/target/jaix-drivers", root)));
}

// A jaix syntax failure fails the build: the child's diagnostics pass
// through on stderr, the host reports OK=0, the exit code is nonzero and no
// artifact exists.
test "E2E: a jaix transpile failure propagates diagnostics and produces no artifact" {
    expect(file_exists(jp_jaix_exe()));
    jp_prepend_jaix_to_path();
    root := path_slashes(otter_scratch("jaix-member-e2e/fail"));
    jp_delete_dir(root);
    defer jp_delete_dir(root);
    expect(jp_copy_member_tree(tprint("%1/packages/juice-plugin-jaix", root)));
    expect(build_seam_write(root, "package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"jaix-fail\",\n    version = \"1\",\n    type    = .BIN,\n    targets = Target.[.{name = \"jaix-fail\", main_file = \"src/main.jai\"}],\n    workspace = .{ members = string.[\"packages/juice-plugin-jaix\"] },\n    plugins = Plugin_Declaration.[\n        .{id = \"juice-plugin-jaix\", version = \"0.1.0\", options = Plugin_Option.[.{key = \"config\", value = \"jaix.config.jai\"}]},\n    ],\n};\n"));
    expect(build_seam_write(root, "jaix.config.jai",
        "#import \"jaix\";\nJaix_Plugin_Try_Catch :: #import \"Jaix_Plugin_Try_Catch\";\n\nget_config :: () -> Jaix_Config {\n    p := Jaix_Plugin_Try_Catch.get_plugin();\n    return .{ plugins = plugins_of(as_plugin(p)) };\n}\n"));
    expect(build_seam_write(root, "src/main.jai", "main :: () {\n    try half(1) catch;\n}\n"));

    result, output, errors := run_otter_child_at(root, string.["build"]);
    expect(expect_exit("jaix-member fail", result, 1, "build child"));
    // The jaix child's diagnostics pass through on stderr; the plugin's
    // failure summary returns through the host record file and the parent
    // prints it with the plain [juice ERROR] convention.
    expect(output_matches("jaix-member fail", errors, string.["src/main.jai", "Error:"]));
    expect(child_output_contains("jaix-member fail", output, "[juice ERROR] jaix pre-step failed for src/main.jai"));
    expect(child_output_contains("jaix-member fail", output, "[juice ERROR] The plugin host reported a pre-step failure."));
    expect(!file_exists(target_artifact_path(package_target_dir(root), "jaix-fail")));
}

// A declared exe that does not exist fails the pre-step with the clear
// error before any spawn: no artifact, no mirror, no driver directory.
test "E2E: a missing jaix executable fails the pre-step with a clear error" {
    root := path_slashes(otter_scratch("jaix-member-e2e/noexe"));
    jp_delete_dir(root);
    defer jp_delete_dir(root);
    expect(jp_copy_member_tree(tprint("%1/packages/juice-plugin-jaix", root)));
    expect(build_seam_write(root, "package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"jaix-noexe\",\n    version = \"1\",\n    type    = .BIN,\n    targets = Target.[.{name = \"jaix-noexe\", main_file = \"src/main.jai\"}],\n    workspace = .{ members = string.[\"packages/juice-plugin-jaix\"] },\n    plugins = Plugin_Declaration.[\n        .{id = \"juice-plugin-jaix\", version = \"0.1.0\", options = Plugin_Option.[\n            .{key = \"config\", value = \"jaix.config.jai\"},\n            .{key = \"exe\", value = \"no-such-jaix.exe\"},\n        ]},\n    ],\n};\n"));
    expect(build_seam_write(root, "jaix.config.jai", "// config\n"));
    expect(build_seam_write(root, "src/main.jai", "main :: () {}\n"));

    result, output, _ := run_otter_child_at(root, string.["build"]);
    expect(expect_exit("jaix-member noexe", result, 1, "build child"));
    expect(child_output_contains("jaix-member noexe", output, "[juice ERROR] jaix executable not found: "));
    expect(child_output_contains("jaix-member noexe", output, "[juice ERROR] The plugin host reported a pre-step failure."));
    expect(!file_exists(target_artifact_path(package_target_dir(root), "jaix-noexe")));
    expect(!file_exists(tprint("%1/target/jaix", root)));
    expect(!file_exists(tprint("%1/target/jaix-drivers", root)));
}

// An undeclared package keeps the zero pre-step behavior: no plugin, no
// host, no mirror.
test "E2E: an undeclared package runs no pre-step and spawns no host" {
    root := path_slashes(otter_scratch("jaix-member-e2e/undeclared"));
    jp_delete_dir(root);
    defer jp_delete_dir(root);
    expect(build_seam_write(root, "package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"plain\",\n    version = \"1\",\n    type    = .BIN,\n    targets = Target.[.{name = \"plain\", main_file = \"src/main.jai\"}],\n};\n"));
    expect(build_seam_write(root, "src/main.jai", "#import \"Basic\";\n\nmain :: () { print(\"plain\\n\"); }\n"));

    result, output, _ := run_otter_child_at(root, string.["build"]);
    expect(expect_exit("jaix-member plain", result, 0, "build child"));
    expect(output_matches("jaix-member plain", output, string.["[juice] Running jaix pre-step"], want = false));
    expect(child_output_contains("jaix-member plain", output, "[juice] Build completed successfully!"));
    expect(file_exists(target_artifact_path(package_target_dir(root), "plain")));
    expect(!file_exists(tprint("%1/target/jaix", root)));
    expect(!file_exists(plugin_host_path(package_target_dir(root))));
    expect(!is_directory(target_plugins_dir(package_target_dir(root))));
}

// ===========================================================================
// E2E: the member package root runs its own suite
// ===========================================================================

test "E2E: the jaix member package root runs its own suite green" {
    member_root := jp_member_package();
    // Session products only (under the member's target/): regenerate them so
    // stale views can never shadow the run, and leave the member source tree
    // untouched.
    jp_delete_dir(package_target_dir(member_root));
    defer jp_delete_dir(package_target_dir(member_root));
    result, output, errors := run_otter_child_at(member_root, string.["test"]);
    expect(expect_exit("jaix-member-root", result, 0));
    // The member's own unit matrix passes (ordering is not pinned); every
    // test name is snake_case, so the shipped lint rule stays silent.
    expect(output_matches("jaix-member-root", output, string.["17 passed, 0 failed"]));
    expect(output_matches("jaix-member-root", errors, string.["[juice lint]"], want = false));
}

// ===========================================================================
// E2E: installed layout (exe + adjacent modules/, no sibling src/target)
// ===========================================================================

test "E2E: an installed juice runs the real jaix member through the host" {
    expect(file_exists(jp_jaix_exe()));
    bin_dir, modules_dir := jp_install_layout("positive");
    expect(bin_dir != "");
    installed_exe := tprint("%1/juice.exe", bin_dir);
    root := jp_demo_workspace("installed-workspace");
    expect(root != "");
    defer jp_delete_dir(otter_scratch("jaix-installed-e2e"));
    defer jp_delete_dir(root);
    // The declaration carries the CLI's absolute path: an installed run must
    // not depend on the caller's PATH.
    expect(jp_write_demo_package_with_exe(root));
    // The install's own face contract: the published juice_core joins its
    // closure only by relative #load, and the whole modules tree is free of
    // the build machine path.
    core_text, core_ok := read_entire_file(tprint("%1/juice_core.jai", modules_dir));
    expect(core_ok);
    expect(find_index_from_left(core_text, otter_root()) < 0);
    scan := scan_published_tree(modules_dir);
    expect(scan.ok, "the installed modules tree leaks the build machine: %", scan.failure);
    expect(scan.files == 3 + 1 + JUICE_CORE_LOAD_FILES.count);

    // The installed executable builds the scratch workspace: the prepare
    // locates the copied member, the host loads it and the pre-step
    // substitutes the mirror entry.
    result, output, errors, _ := run_command(installed_exe, "build", working_directory = root, capture_and_return_output = true);
    expect(expect_exit("jaix-installed", result, 0));
    expect(child_output_contains("jaix-installed", output, "[juice] Running jaix pre-step (2 files) -> target/jaix/..."));
    expect(child_output_contains("jaix-installed", output, "[juice Build] Compiling Target 'jaix-demo' (src/main.jai) -> target/..."));
    expect(output_matches("jaix-installed", errors, string.["Error:"], want = false));
    artifact := target_artifact_path(package_target_dir(root), "jaix-demo");
    expect(file_exists(artifact));
    run_result, run_output, _, _ := run_command(artifact, capture_and_return_output = true);
    expect(expect_exit("jaix-installed artifact", run_result, 0));
    expect(child_output_contains("jaix-installed artifact", run_output, "double(20): NONE 40"));
    // The session artifacts landed in the scratch workspace, not the install.
    expect(file_exists(plugin_host_path(package_target_dir(root))));
    expect(file_exists(workspace_plugin_registration_path(package_target_dir(root))));
    expect(!is_directory(target_plugins_dir(package_target_dir(bin_dir))));

    // The installed executable tests the same workspace: the mixed package
    // (mirror views plus the original test block file) runs 3 tests.
    result, output, errors = run_command(installed_exe, "test", working_directory = root, capture_and_return_output = true);
    expect(expect_exit("jaix-installed test", result, 0));
    expect(output_matches("jaix-installed test", output, string.[
        "[test] juice_test_1",
        "[test] juice_test_2",
        "[test] juice_test_3",
        "3 passed, 0 failed",
    ]));

    // Negative: delete exactly one installed plugin-face closure copy — from
    // the scratch install only — and rerun. The host program's `#import
    // "juice_core"` reaches the missing closure: the host compile fails
    // loudly before the build compile, never a green or zero-plugin run.
    missing_closure := juice_plugin_face_file_path(modules_dir, "plugin.jai");
    expect(file_exists(missing_closure));
    expect(file_delete(missing_closure));
    result, output, errors = run_command(installed_exe, "build", working_directory = root, capture_and_return_output = true);
    expect(expect_exit("jaix-installed missing-face", result, 1));
    expect(child_output_contains("jaix-installed missing-face", errors, "Unable to open file"));
    expect(child_output_contains("jaix-installed missing-face", errors, "plugin_face/plugin.jai"));
    expect(child_output_contains("jaix-installed missing-face", output, "[juice ERROR] Plugin host failed (exit "));
}

test "E2E: an installed juice fails loudly when the jaix member is missing" {
    expect(file_exists(jp_jaix_exe()));
    bin_dir, _ := jp_install_layout("missing-member");
    expect(bin_dir != "");
    defer jp_delete_dir(otter_scratch("jaix-installed-e2e"));
    installed_exe := tprint("%1/juice.exe", bin_dir);
    // The workspace declares the plugin but lists no member package: the
    // command-level prepare's declaration scan rejects the unknown id before
    // any host or compile.
    root := path_slashes(otter_scratch("jaix-installed-e2e/missing-member-workspace"));
    jp_delete_dir(root);
    defer jp_delete_dir(root);
    expect(build_seam_write(root, "package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"missing-member\",\n    version = \"1\",\n    type    = .BIN,\n    targets = Target.[.{name = \"missing-member\", main_file = \"src/main.jai\"}],\n    plugins = Plugin_Declaration.[\n        .{id = \"juice-plugin-jaix\", version = \"0.1.0\", options = Plugin_Option.[.{key = \"config\", value = \"jaix.config.jai\"}]},\n    ],\n};\n"));
    expect(build_seam_write(root, "jaix.config.jai", "// config\n"));
    expect(build_seam_write(root, "src/main.jai", "main :: () {}\n"));

    result, output, _, _ := run_command(installed_exe, "build", working_directory = root, capture_and_return_output = true);
    expect(expect_exit("jaix-installed missing-member", result, 1));
    expect(child_output_contains("jaix-installed missing-member", output, "[juice ERROR] juice-plugin-jaix: Unknown plugin id: juice-plugin-jaix"));
    expect(child_output_contains("jaix-installed missing-member", output, "[juice ERROR] Could not prepare the workspace's plugin declarations."));
    expect(!file_exists(target_artifact_path(package_target_dir(root), "missing-member")));
    // No host was spawned, no registration landed.
    expect(!file_exists(plugin_host_path(package_target_dir(root))));
    expect(!file_exists(workspace_plugin_registration_path(package_target_dir(root))));
}

test "E2E: an installed juice fails loudly when the member shim cannot land" {
    expect(file_exists(jp_jaix_exe()));
    bin_dir, _ := jp_install_layout("missing-shim");
    expect(bin_dir != "");
    defer jp_delete_dir(otter_scratch("jaix-installed-e2e"));
    installed_exe := tprint("%1/juice.exe", bin_dir);
    root := path_slashes(otter_scratch("jaix-installed-e2e/missing-shim-workspace"));
    jp_delete_dir(root);
    defer jp_delete_dir(root);
    // The declared member package has no importable entry layout (no
    // module.jai / src/module.jai / <name>.jai): the member link writes no
    // import shim, so the generated registration's module import cannot
    // resolve and the host compile fails. This is the "missing shim" face —
    // a declared plugin whose value can never be imported must never degrade
    // into a silent zero-plugin run.
    expect(build_seam_write(root, "packages/jaix-copy/package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"jaix-copy\",\n    version = \"0.1.0\",\n    type    = .LIB,\n};\n"));
    expect(build_seam_write(root, "packages/jaix-copy/plugin.jai",
        "get_juice_plugin :: () -> *X { plugin.hooks; return null; } @juice_plugin\n"));
    expect(build_seam_write(root, "package.jai",
        "#import \"Juice\";\n\nPACKAGE :: Package.{\n    name    = \"missing-shim\",\n    version = \"0.1.0\",\n    type    = .BIN,\n    targets = Target.[.{name = \"missing-shim\", main_file = \"src/main.jai\"}],\n    workspace = .{ members = string.[\"packages/jaix-copy\"] },\n    plugins = Plugin_Declaration.[\n        .{id = \"jaix-copy\", version = \"0.1.0\"},\n    ],\n};\n"));
    expect(build_seam_write(root, "src/main.jai", "main :: () {}\n"));

    result, output, errors, _ := run_command(installed_exe, "build", working_directory = root, capture_and_return_output = true);
    expect(expect_exit("jaix-installed missing-shim", result, 1));
    expect(child_output_contains("jaix-installed missing-shim", output, "[juice ERROR] Plugin host failed (exit "));
    // The host compiler names the unresolvable plugin module import.
    expect(child_output_contains("jaix-installed missing-shim", errors, "Unable to find a module called 'plugin'"));
    expect(!file_exists(target_artifact_path(package_target_dir(root), "missing-shim")));
    // The link really wrote nothing: the member has no recognized entry.
    expect(!file_exists(tprint("%1/jaix-copy.jai", packages_dir(root))));
}
