#import "Basic";
#import "Testing";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";

// POSIX is only a real module on Unix targets; the install copies it guards are
// compiled out on Windows, so the import goes out with them.
#if OS != .WINDOWS {
    #import "POSIX";
}

// ---------------------------------------------------------------------------
// Installation-unit compatibility (spec 0087 decision 28 and Testing decision
// 7, acceptance group A16; ticket 0094).
//
// The shipped product is one unit: the executable plus the modules directory
// adjacent to it. This file pins both halves of that contract:
//
//   - the compatibility marker the publish step lands beside the artifacts
//     (format, digests, contract identifiers) and its parse/verify surface,
//     exercised on hand-written fixtures in a scratch directory — the
//     failure-injection seam through the current module interface;
//   - the real CLI running next to a complete, a missing, a mixed and a
//     mismatched modules tree, including an installation used from a project
//     outside this repository (build, run, test, update and an offline case).
//
// Named `proc :: () {} @test` blocks only, so `juice test publication_install`
// selects them.
//
// Fixture discipline: every directory is fresh per case (the Windows
// recursive delete is asynchronous), and the external installation lives in
// the machine temporary root because the ticket requires it to be outside the
// repository.
// ---------------------------------------------------------------------------

// One fresh scratch directory per case under this worktree's target tree.
ic_scratch :: (name: string) -> string {
    root := copy_string(tprint("%1/install-compat/%2", otter_target_dir(), name));
    for 1..1000 {
        candidate := copy_string(tprint("%1-%2", root, it));
        if file_exists(candidate) continue;
        return candidate;
    }
    return root;
}

// One fresh directory in the machine temporary root — outside this repository,
// which is what the external acceptance case requires.
ic_external_scratch :: (name: string) -> string {
    base := get_env("TEMP");
    #if OS != .WINDOWS {
        base = get_env("TMPDIR");
        if base == "" base = "/tmp";
    }
    if base == "" base = get_env("TMP");
    if base == "" base = ".";
    root := copy_string(tprint("%1/juice-0094-%2", base, name));
    for 1..1000 {
        candidate := copy_string(tprint("%1-%2", root, it));
        if file_exists(candidate) continue;
        return candidate;
    }
    return root;
}

// Write one fixture file. The content is copied before the path is built
// (tprint allocates in the temporary allocator).
ic_write :: (dir: string, relative_path: string, content: string) -> bool {
    content_copy := copy_string(content);
    path := copy_string(tprint("%1/%2", dir, relative_path));
    if !make_directory_if_it_does_not_exist(path_strip_filename(path), recursive = true) return false;
    return write_entire_file(path, content_copy);
}

// One text from lines plus a trailing newline — the shape of a file fixture.
ic_lines :: (lines: [] string) -> string {
    builder: String_Builder;
    for line, index: lines {
        if index > 0 print_to_builder(*builder, "\n");
        print_to_builder(*builder, "%", line);
    }
    print_to_builder(*builder, "\n");
    return builder_to_string(*builder);
}

// The published texts of the real definition source, in the publication order
// `install_artifact_paths` uses: the Juice face, Testing, juice_core, the
// discovery source, then the plugin face closure copies in
// JUICE_CORE_LOAD_FILES order.
ic_real_published_texts :: () -> ([..] string, bool) {
    texts: [..] string;
    source, source_ok := read_entire_file(tprint("%1/src/module.jai", otter_root()));
    if !source_ok return texts, false;
    discovery, discovery_ok := read_entire_file(tprint("%1/src/test_discovery.jai", otter_root()));
    if !discovery_ok return texts, false;
    juice, juice_ok := publish_juice_module(source);
    testing, testing_ok := publish_testing_module(source);
    core, core_ok := publish_juice_core(source);
    if !juice_ok || !testing_ok || !core_ok return texts, false;
    array_add(*texts, juice);
    array_add(*texts, testing);
    array_add(*texts, core);
    array_add(*texts, discovery);
    for file: JUICE_CORE_LOAD_FILES {
        closure, closure_ok := read_entire_file(tprint("%1/src/%2", otter_root(), file));
        if !closure_ok return texts, false;
        array_add(*texts, closure);
    }
    return texts, true;
}

// The `JUICE_PLUGIN_ABI_VERSION` declaration line from its single source
// (src/plugin.jai), the way the build extracts `JUICE_VERSION`.
ic_plugin_abi_line :: () -> (string, bool) {
    source, source_ok := read_entire_file(tprint("%1/src/plugin.jai", otter_root()));
    if !source_ok return "", false;
    line, line_ok := extract_constant_line(source, "JUICE_PLUGIN_ABI_VERSION");
    return line, line_ok;
}

// Publish the real installation set into an arbitrary modules directory
// through the production writer.
ic_publish_real_set :: (modules_dir: string) -> bool {
    texts, texts_ok := ic_real_published_texts();
    if !texts_ok return false;
    abi_line, abi_ok := ic_plugin_abi_line();
    if !abi_ok return false;
    failure, published := publish_install_set(modules_dir, abi_line, texts);
    if !published {
        print("[install-compat] publishing the installation set failed: %\n", failure);
        return false;
    }
    return true;
}

// ===========================================================================
// Slice 1: the marker's content contract
// ===========================================================================

publication_install_digest_vectors :: () {
    // Independent known-good FNV-1a 64 vectors: the artifact digest is that
    // function rendered as 16 lowercase hex characters.
    expect(install_artifact_digest("") == "cbf29ce484222325");
    expect(install_artifact_digest("a") == "af63dc4c8601ec8c");
    expect(install_artifact_digest("abc") == "e71fa2190541574b");
    expect(install_artifact_digest("foobar") == "85944171f73967e8");
} @test

publication_install_artifact_paths :: () {
    modules_dir := "X:/install/modules";
    paths := install_artifact_paths(modules_dir);
    expected_relative := string.[
        "Juice/module.jai",
        "Testing.jai",
        "juice_core.jai",
        "juice_internal/test_discovery.jai",
        "juice_internal/plugin_face/transpile.jai",
        "juice_internal/plugin_face/transpile_plugin.jai",
        "juice_internal/plugin_face/lifecycle.jai",
        "juice_internal/plugin_face/plugin.jai",
    ];
    expect(paths.count == expected_relative.count);
    expect(expected_relative.count == 4 + JUICE_CORE_LOAD_FILES.count);
    for path, index: paths {
        expect(path.relative_path == expected_relative[index], "artifact %: %", index, path.relative_path);
        expect(path.absolute_path == tprint("X:/install/modules/%1", expected_relative[index]));
    }
    expect(install_manifest_path(modules_dir) == "X:/install/modules/juice_internal/install_manifest.txt");
} @test

publication_install_manifest_layout :: () {
    modules_dir := "X:/install/modules";
    abi_line := "JUICE_PLUGIN_ABI_VERSION :: 1;";
    texts := string.["juice", "testing", "core", "discovery", "t", "tp", "lc", "p"];
    text, ok := publish_install_manifest(modules_dir, abi_line, texts);
    expect(ok, "the marker must be generated for a complete set");
    // The marker's exact shape: three contract identifiers, the artifact count,
    // then one module-relative path with its digest per artifact (the digests
    // are the independent FNV-1a vectors above applied to these fixture texts).
    expected := ic_lines(string.[
        "juice-install-manifest 1",
        "compatibility 1",
        "plugin_abi 1",
        "artifacts 8",
        "Juice/module.jai 86e9ef2ca8c5027f",
        "Testing.jai c2fe2fb77ae839bb",
        "juice_core.jai 0bf2fb911980759e",
        "juice_internal/test_discovery.jai 3aee27985d1c5355",
        "juice_internal/plugin_face/transpile.jai af63e94c860202a3",
        "juice_internal/plugin_face/transpile_plugin.jai 08c84007b56acc89",
        "juice_internal/plugin_face/lifecycle.jai 08ad3d07b553ffb8",
        "juice_internal/plugin_face/plugin.jai af63ed4c8602096f",
    ]);
    expect(text == expected, "the marker must describe the published set exactly");
    // No machine-specific path may reach the marker: it travels with the unit.
    expect(find_index_from_left(text, "X:/install") < 0, "the marker must not record the landing directory");
} @test

publication_install_manifest_rejects_bad_input :: () {
    modules_dir := "X:/install/modules";
    good_texts := string.["juice", "testing", "core", "discovery", "t", "tp", "lc", "p"];
    short_texts := string.["juice", "testing", "core", "discovery", "t", "tp", "lc"];
    text, ok := publish_install_manifest(modules_dir, "JUICE_PLUGIN_ABI_VERSION :: 1;", short_texts);
    expect(!ok && text == "", "an incomplete artifact set must not produce a marker");
    text, ok = publish_install_manifest(modules_dir, "JUICE_PLUGIN_ABI_VERSIONX :: 1;", good_texts);
    expect(!ok && text == "", "a wrong constant name must not produce a marker");
    text, ok = publish_install_manifest(modules_dir, "JUICE_PLUGIN_ABI_VERSION :: ;", good_texts);
    expect(!ok && text == "", "a missing value must not produce a marker");
    text, ok = publish_install_manifest(modules_dir, "JUICE_PLUGIN_ABI_VERSION :: seven;", good_texts);
    expect(!ok && text == "", "a non-numeric value must not produce a marker");
    text, ok = publish_install_manifest(modules_dir, "JUICE_PLUGIN_ABI_VERSION :: 1; trailing", good_texts);
    expect(!ok && text == "", "trailing text after the declaration must not produce a marker");
} @test

publication_install_manifest_parse :: () {
    modules_dir := "X:/install/modules";
    texts := string.["juice", "testing", "core", "discovery", "t", "tp", "lc", "p"];
    text, ok := publish_install_manifest(modules_dir, "JUICE_PLUGIN_ABI_VERSION :: 3;", texts);
    expect(ok);
    manifest, parsed := parse_install_manifest(text);
    expect(parsed, "a generated marker must parse");
    expect(manifest.manifest_version == INSTALL_MANIFEST_VERSION);
    expect(manifest.compatibility == INSTALL_COMPATIBILITY_VERSION);
    expect(manifest.plugin_abi == 3);
    expect(manifest.artifacts.count == texts.count);
    expect(manifest.artifacts[0].relative_path == "Juice/module.jai");
    expect(manifest.artifacts[0].digest == "86e9ef2ca8c5027f");

    // Every malformed shape fails instead of degrading into an empty set.
    bad: Install_Manifest;
    bad_ok := false;
    bad, bad_ok = parse_install_manifest("");
    expect(!bad_ok && bad.artifacts.count == 0, "an empty marker must not parse");
    bad, bad_ok = parse_install_manifest(ic_lines(string.["juice-install-manifest 1"]));
    expect(!bad_ok, "a header-only marker must not parse");
    bad, bad_ok = parse_install_manifest(ic_lines(string.[
        "juice-install-manifest 1", "compatibility 1", "plugin_abi 1", "artifacts 2",
        "Juice/module.jai 86e9ef2ca8c5027f"]));
    expect(!bad_ok, "a short artifact list must not parse");
    bad, bad_ok = parse_install_manifest(ic_lines(string.[
        "juice-install-manifest 1", "compatibility 1", "plugin_abi 1", "artifacts 1",
        "Juice/module.jai 86e9ef2ca8c5027f", "Testing.jai c2fe2fb77ae839bb"]));
    expect(!bad_ok, "a long artifact list must not parse");
    bad, bad_ok = parse_install_manifest(ic_lines(string.[
        "juice-install-manifest 1", "compatibility 1", "plugin_abi 1", "artifacts 1",
        "Juice/module.jai"]));
    expect(!bad_ok, "an artifact line without a digest must not parse");
    bad, bad_ok = parse_install_manifest(ic_lines(string.[
        "juice-install-manifest 1", "compatibility 1", "plugin_abi 1", "artifacts 1",
        "Juice/module.jai 86e9ef2ca8c5027f extra"]));
    expect(!bad_ok, "an artifact line with trailing text must not parse");
    bad, bad_ok = parse_install_manifest(ic_lines(string.[
        "juice-install-manifest 1", "compatibility x", "plugin_abi 1", "artifacts 1",
        "Juice/module.jai 86e9ef2ca8c5027f"]));
    expect(!bad_ok, "a non-numeric contract identifier must not parse");
    bad, bad_ok = parse_install_manifest(ic_lines(string.[
        "juice-install-manifest 1", "compatibility 1", "plugin_abi 1", "artifacts 1",
        "Juice/module.jai 86e9ef2ca8c5027f", "unexpected 1"]));
    expect(!bad_ok, "trailing lines must not parse");
    bad, bad_ok = parse_install_manifest(ic_lines(string.[
        "juice-install-manifest 1", "compatibility 1", "plugin_abi 1", "artifacts 1",
        "/install/Juice/module.jai 86e9ef2ca8c5027f"]));
    expect(!bad_ok, "an absolute artifact path must not parse");
} @test

// ===========================================================================
// Slice 2: verification over a real directory
// ===========================================================================

publication_install_verify_complete :: () {
    modules_dir := ic_scratch("verify-complete");
    defer delete_directory_full(modules_dir);
    expect(ic_publish_real_set(modules_dir));

    abi_line, abi_ok := ic_plugin_abi_line();
    expect(abi_ok);
    abi_value, abi_value_ok := constant_integer_value(abi_line, "JUICE_PLUGIN_ABI_VERSION");
    expect(abi_value_ok);
    check := verify_install(modules_dir, abi_value);
    expect(check.ok, "a complete installation must verify: %", check.reason);
    expect(check.reason == "");

    // The plugin entry contract is part of the unit: an executable whose ABI
    // differs from the marker's rejects the installation.
    check = verify_install(modules_dir, abi_value + 1);
    expect(!check.ok);
    expect(find_index_from_left(check.reason, "plugin ABI") >= 0, "the reason must name the plugin ABI: %", check.reason);
} @test

publication_install_verify_missing_marker :: () {
    modules_dir := ic_scratch("verify-no-marker");
    defer delete_directory_full(modules_dir);
    expect(ic_publish_real_set(modules_dir));
    expect(file_delete(install_manifest_path(modules_dir)));
    check := verify_install(modules_dir, 1);
    expect(!check.ok);
    expect(find_index_from_left(check.reason, "marker") >= 0, "the reason must name the marker: %", check.reason);
} @test

publication_install_verify_marker_epoch :: () {
    modules_dir := ic_scratch("verify-epoch");
    defer delete_directory_full(modules_dir);
    expect(ic_publish_real_set(modules_dir));
    abi_line, abi_ok := ic_plugin_abi_line();
    expect(abi_ok);
    texts, texts_ok := ic_real_published_texts();
    expect(texts_ok);

    // A marker from another release: the same artifact set and content, a
    // different compatibility epoch. Built from the generated text so the
    // fixture proves the verifier reads the marker, not the file contents.
    marker, marker_ok := publish_install_manifest(modules_dir, abi_line, texts);
    expect(marker_ok);
    epoch_line := tprint("compatibility %1\n", INSTALL_COMPATIBILITY_VERSION);
    epoch_at := find_index_from_left(marker, epoch_line);
    expect(epoch_at >= 0, "the generated marker must carry the compatibility line");
    stale := tprint("%1compatibility %2\n%3",
                    slice(marker, 0, epoch_at),
                    INSTALL_COMPATIBILITY_VERSION + 1,
                    slice(marker, epoch_at + epoch_line.count, marker.count - epoch_at - epoch_line.count));
    expect(ic_write(modules_dir, "juice_internal/install_manifest.txt", stale));
    check := verify_install(modules_dir, 1);
    expect(!check.ok);
    expect(find_index_from_left(check.reason, "compatibility") >= 0, "the reason must name compatibility: %", check.reason);
} @test

publication_install_verify_missing_and_mixed :: () {
    modules_dir := ic_scratch("verify-missing-mixed");
    defer delete_directory_full(modules_dir);
    expect(ic_publish_real_set(modules_dir));

    // A missing published artifact — the plugin support source case.
    support_path := copy_string(tprint("%1/juice_internal/plugin_face/lifecycle.jai", modules_dir));
    original, original_ok := read_entire_file(support_path);
    expect(original_ok);
    expect(file_delete(support_path));
    check := verify_install(modules_dir, 1);
    expect(!check.ok);
    expect(find_index_from_left(check.reason, "lifecycle.jai") >= 0, "the reason must name the missing artifact: %", check.reason);

    // Mixed installation: one artifact replaced by other content while the
    // marker still describes the published set.
    expect(write_entire_file(support_path, "// a different release's source\n"));
    check = verify_install(modules_dir, 1);
    expect(!check.ok);
    expect(find_index_from_left(check.reason, "lifecycle.jai") >= 0, "the reason must name the mismatched artifact: %", check.reason);
    expect(find_index_from_left(check.reason, "content") >= 0, "the reason must say the content differs: %", check.reason);

    expect(write_entire_file(support_path, original));
    check = verify_install(modules_dir, 1);
    expect(check.ok, "restoring the published content must verify again: %", check.reason);

    // An artifact set the marker does not describe at all (a different
    // release's artifact list) is rejected before any file is read.
    short_marker := ic_lines(string.[
        "juice-install-manifest 1", "compatibility 1", "plugin_abi 1", "artifacts 4",
        "Juice/module.jai e4715c31ef07c9c8", "Testing.jai 6b10b015c063138e",
        "juice_core.jai 8c954fb8fa3717c8", "juice_internal/test_discovery.jai 4c95109422d44753"]);
    expect(ic_write(modules_dir, "juice_internal/install_manifest.txt", short_marker));
    check = verify_install(modules_dir, 1);
    expect(!check.ok);
    expect(find_index_from_left(check.reason, "artifacts") >= 0, "the reason must name the artifact count: %", check.reason);
} @test

// ===========================================================================
// Slice 3: the real executable next to its modules directory
// ===========================================================================

// The published CLI gate's diagnostic, in the operator's terms.
IC_GATE_HEADLINE :: "[juice ERROR] This juice executable and its adjacent modules directory are not one compatible installation.";
IC_GATE_NO_FALLBACK :: "juice does not fall back to another installation or to development sources.";

// A delivered installation: the real executable plus its adjacent modules
// directory, and nothing else.
Ic_Install :: struct {
    bin_dir:     string;
    modules_dir: string;
    exe:         string;
}

ic_install_paths :: (layout: string) -> Ic_Install {
    install: Ic_Install;
    install.bin_dir = copy_string(tprint("%1/bin", layout));
    install.modules_dir = copy_string(tprint("%1/bin/modules", layout));
    install.exe = copy_string(target_artifact_path(install.bin_dir, "juice"));
    return install;
}

// Jai's copy_file creates the destination with the host's default file mode, so on
// Unix a copied executable arrives as 0644 and cannot be launched — the whole point
// of an install unit. Re-apply the SOURCE's own permission bits after the copy: the
// destination is the one file this fixture just created inside its own layout, and
// no mode is hard-coded because the build's umask is not the contract.
ic_preserve_exec_mode :: (source: string, destination: string) -> bool {
    #if OS == .WINDOWS {
        // Windows carries executability in the extension, not in a mode word.
        return true;
    } else {
        info: POSIX.stat_t;
        if POSIX.stat(temp_c_string(source), *info) != 0 return false;
        return POSIX.chmod(temp_c_string(destination), info.st_mode) == 0;
    }
}

ic_create_install :: (layout: string) -> Ic_Install {
    install := ic_install_paths(layout);
    if !make_directory_if_it_does_not_exist(install.bin_dir, recursive = true) return install;
    if !copy_file(otter_exe(), install.exe) return install;
    if !ic_preserve_exec_mode(otter_exe(), install.exe) return install;
    if !ic_publish_real_set(install.modules_dir) return install;
    return install;
}

ic_install_is_complete :: (install: Ic_Install) -> bool {
    if !file_exists(install.exe) return false;
    return file_exists(install_manifest_path(install.modules_dir));
}

ic_run_install :: (install: Ic_Install, working_dir: string, arguments: [] string) -> (Process_Result, string, string) {
    args: [..] string;
    array_add(*args, install.exe);
    for argument: arguments array_add(*args, argument);
    result, output, errors, _ := run_command(..args, working_directory = working_dir, capture_and_return_output = true);
    return result, output, errors;
}

// The smallest project a command needs: one declaration, one program.
ic_write_minimal_app :: (app: string) -> bool {
    declaration := copy_string(ic_lines(string.[
        "#import \"Juice\";",
        "",
        "PACKAGE :: Package.{",
        "    name = \"app\",",
        "    version = \"0.1.0\",",
        "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],",
        "};",
    ]));
    if !ic_write(app, "package.jai", declaration) return false;
    return ic_write(app, "src/main.jai", "#import \"Basic\";\n\nmain :: () { print(\"install-ok\\n\"); }\n");
}

ic_app_artifact :: (app: string) -> string {
    return target_artifact_path(package_target_dir(app), "app");
}

// Rewrite one marker line (the marker is plain text by design, so an older or
// edited marker is exactly what an operator with a mixed install has on disk).
ic_rewrite_marker :: (modules_dir: string, needle: string, replacement: string) -> bool {
    path := install_manifest_path(modules_dir);
    text, read_ok := read_entire_file(path);
    if !read_ok return false;
    at := find_index_from_left(text, needle);
    if at < 0 return false;
    updated := copy_string(tprint("%1%2%3",
        slice(text, 0, at),
        replacement,
        slice(text, at + needle.count, text.count - at - needle.count)));
    return write_entire_file(path, updated);
}

publication_install_cli_complete :: () {
    layout := ic_scratch("cli-complete");
    defer delete_directory_full(layout);
    install := ic_create_install(layout);
    expect(ic_install_is_complete(install));
    app := copy_string(tprint("%1/app", layout));
    expect(ic_write_minimal_app(app));

    // A complete unit runs ordinary commands without any installation noise.
    result, output, errors := ic_run_install(install, app, string.["build"]);
    expect(expect_exit("install-complete build", result, 0, "installation"));
    expect(output_matches("install-complete build", output, string.[IC_GATE_HEADLINE], want = false));
    expect(output_matches("install-complete build", errors, string.[IC_GATE_HEADLINE], want = false));
    expect(file_exists(ic_app_artifact(app)), "the build must produce the program");

    result, output, errors = ic_run_install(install, app, string.["version"]);
    expect(expect_exit("install-complete version", result, 0, "installation"));
    expect(child_output_contains("install-complete version", output, "juice 0.1.0"));
} @test

publication_install_cli_missing_artifact :: () {
    layout := ic_scratch("cli-missing");
    defer delete_directory_full(layout);
    install := ic_create_install(layout);
    expect(ic_install_is_complete(install));
    app := copy_string(tprint("%1/app", layout));
    expect(ic_write_minimal_app(app));

    // A published artifact is gone: every command fails before it touches the
    // project, and nothing is compiled.
    testing_path := copy_string(tprint("%1/Testing.jai", install.modules_dir));
    expect(file_delete(testing_path));
    result, output, errors := ic_run_install(install, app, string.["build"]);
    expect(expect_exit("install-missing build", result, 1, "installation"));
    combined := tprint("%\n%", output, errors);
    expect(child_output_contains("install-missing build", combined, IC_GATE_HEADLINE));
    expect(child_output_contains("install-missing build", combined, "Testing.jai"));
    expect(!file_exists(ic_app_artifact(app)), "a broken installation must not build anything");

    // The gate is not specific to build: any command refuses to run.
    result, output, errors = ic_run_install(install, app, string.["version"]);
    expect(expect_exit("install-missing version", result, 1, "installation"));
    combined = tprint("%\n%", output, errors);
    expect(child_output_contains("install-missing version", combined, IC_GATE_HEADLINE));
} @test

publication_install_cli_mixed_set :: () {
    layout := ic_scratch("cli-mixed");
    defer delete_directory_full(layout);
    install := ic_create_install(layout);
    expect(ic_install_is_complete(install));
    app := copy_string(tprint("%1/app", layout));
    expect(ic_write_minimal_app(app));

    // One artifact from another release, everything else untouched: the marker
    // still describes the published content, so the digest is what catches it.
    core_path := copy_string(tprint("%1/juice_core.jai", install.modules_dir));
    expect(write_entire_file(core_path, "// juice_core from another release\n"));
    result, output, errors := ic_run_install(install, app, string.["build"]);
    expect(expect_exit("install-mixed build", result, 1, "installation"));
    combined := tprint("%\n%", output, errors);
    expect(child_output_contains("install-mixed build", combined, IC_GATE_HEADLINE));
    expect(child_output_contains("install-mixed build", combined, "juice_core.jai"));
    expect(child_output_contains("install-mixed build", combined, "content digest mismatch"));
    expect(!file_exists(ic_app_artifact(app)));
} @test

publication_install_cli_marker_mismatch :: () {
    layout := ic_scratch("cli-marker");
    defer delete_directory_full(layout);
    install := ic_create_install(layout);
    expect(ic_install_is_complete(install));
    app := copy_string(tprint("%1/app", layout));
    expect(ic_write_minimal_app(app));

    // A marker from another release's contract: compatibility epoch first.
    expect(ic_rewrite_marker(install.modules_dir, "compatibility 1", "compatibility 7"));
    result, output, errors := ic_run_install(install, app, string.["build"]);
    expect(expect_exit("install-epoch build", result, 1, "installation"));
    combined := tprint("%\n%", output, errors);
    expect(child_output_contains("install-epoch build", combined, IC_GATE_HEADLINE));
    expect(child_output_contains("install-epoch build", combined, "compatibility 7"));

    // Then the plugin entry ABI, which is checked independently of the epoch.
    expect(ic_rewrite_marker(install.modules_dir, "compatibility 7", "compatibility 1"));
    expect(ic_rewrite_marker(install.modules_dir, "plugin_abi 1", "plugin_abi 4"));
    result, output, errors = ic_run_install(install, app, string.["build"]);
    expect(expect_exit("install-abi build", result, 1, "installation"));
    combined = tprint("%\n%", output, errors);
    expect(child_output_contains("install-abi build", combined, "plugin ABI 4"));

    // A missing marker at all is an incomplete installation, not a licence to
    // discover one elsewhere.
    expect(file_delete(install_manifest_path(install.modules_dir)));
    result, output, errors = ic_run_install(install, app, string.["build"]);
    expect(expect_exit("install-no-marker build", result, 1, "installation"));
    combined = tprint("%\n%", output, errors);
    expect(child_output_contains("install-no-marker build", combined, "the installation marker is missing"));
} @test

publication_install_cli_no_fallback :: () {
    layout := ic_scratch("cli-no-fallback");
    defer delete_directory_full(layout);
    install := ic_create_install(layout);
    expect(ic_install_is_complete(install));
    app := copy_string(tprint("%1/app", layout));
    expect(ic_write_minimal_app(app));

    // Two alternative module sources an older juice would have fallen back to,
    // both complete and byte-identical to a real publication:
    //   <layout>/modules      — the retired <exe>/../modules global layout;
    //   <layout>/src          — sibling development sources.
    global_modules := copy_string(tprint("%1/modules", layout));
    global_src := copy_string(tprint("%1/src", layout));
    expect(make_directory_if_it_does_not_exist(global_modules, recursive = true));
    copy_directory(install.modules_dir, global_modules);
    expect(make_directory_if_it_does_not_exist(global_src, recursive = true));
    copy_directory(copy_string(tprint("%1/src", otter_root())), global_src);

    // Break the adjacent unit only: the alternatives must stay unused.
    testing_path := copy_string(tprint("%1/Testing.jai", install.modules_dir));
    expect(file_delete(testing_path));
    result, output, errors := ic_run_install(install, app, string.["build"]);
    expect(expect_exit("install-no-fallback build", result, 1, "installation"));
    combined := tprint("%\n%", output, errors);
    expect(child_output_contains("install-no-fallback build", combined, IC_GATE_HEADLINE));
    expect(child_output_contains("install-no-fallback build", combined, IC_GATE_NO_FALLBACK));
    expect(child_output_contains("install-no-fallback build", combined, "Testing.jai"));
    expect(!file_exists(ic_app_artifact(app)), "no alternative installation may satisfy the build");

    // Positive control in the same layout: repair exactly the adjacent unit and
    // the very same invocation works, so the failure above was the installation
    // and not the project.
    expect(ic_publish_real_set(install.modules_dir));
    result, output, errors = ic_run_install(install, app, string.["build"]);
    expect(expect_exit("install-repaired build", result, 0, "installation"));
    expect(file_exists(ic_app_artifact(app)));
} @test

// ===========================================================================
// Slice 4: a project outside this repository, using the published installation
// ===========================================================================

// The external project's declaration: one public module, one program, the
// builtin plugin pair explicitly declared, a PATH provider, a Git provider, a
// workspace member and a default program. Every declaration field of the new
// public face that the acceptance needs is exercised from outside the
// repository.
ic_external_project_declaration :: (git_url: string) -> string {
    git_line := copy_string(tprint("        .{name = \"git_provider\", source = .{kind = .GIT, git = .{url = \"%1\"}}, modules = .[.{alias = \"Git_Lib\"}]},", git_url));
    return ic_lines(string.[
        "#import \"Juice\";",
        "",
        "PACKAGE :: Package.{",
        "    name = \"external_app\",",
        "    version = \"0.1.0\",",
        "    description = \"外部安装验收：仓库外工程\",",
        "    modules = .[.{name = \"external_app\", entry = \"src/module.jai\"}],",
        "    executables = .[.{name = \"external_app\", entry = \"src/main.jai\"}],",
        "    default_run = \"external_app\",",
        "    dependencies = Dependency.[",
        "        .{name = \"path_provider\", source = .{kind = .PATH, path = \"../provider\"}, modules = .[.{alias = \"Path_Lib\"}]},",
        git_line,
        "        .{name = \"member\", source = .{kind = .WORKSPACE}, modules = .[.{path = \"packages/member\", alias = \"Member_Lib\"}]},",
        "    ],",
        "    plugins = Plugin_Declaration.[",
        "        .{builtin = \"load\"},",
        "        .{builtin = \"test-block\"},",
        "    ],",
        "    workspace = .{",
        "        members = string.[\"packages/member\"],",
        "    },",
        "};",
    ]);
}

publication_install_external_project :: () {
    root := ic_external_scratch("external");
    defer delete_directory_full(root);

    // The installation under test is the published unit and nothing else: no
    // sibling src/, no sibling target/, and it is outside the repository.
    install := ic_create_install(copy_string(tprint("%1/install", root)));
    expect(ic_install_is_complete(install));
    expect(!is_directory(copy_string(tprint("%1/install/src", root))));
    expect(!starts_with(path_slashes(install.bin_dir), path_slashes(otter_root())),
           "the installation must live outside this repository");

    // Isolated XDG roots for the child processes (the shared suite contract:
    // restore them, or later E2E children resolve into this case's tree).
    dr_isolate(root);
    defer dr_restore_env();

    // The providers: a sibling PATH package and a local Git repository, both
    // real packages with one public module.
    provider := copy_string(tprint("%1/provider", root));
    expect(ic_write(provider, "package.jai", ic_lines(string.[
        "#import \"Juice\";", "", "PACKAGE :: Package.{",
        "    name = \"path_provider\",", "    version = \"0.1.0\",", "};"])));
    expect(ic_write(provider, "module.jai", "Path_Value :: 21;\n"));

    repository := copy_string(tprint("%1/git_provider", root));
    expect(dr_git_init(repository));
    expect(ic_write(repository, "package.jai", ic_lines(string.[
        "#import \"Juice\";", "", "PACKAGE :: Package.{",
        "    name = \"git_provider\",", "    version = \"0.1.0\",", "};"])));
    expect(ic_write(repository, "module.jai", "Git_Value :: 34;\n"));
    commit := copy_string(dr_git_commit_all(repository, "provider"));
    expect(commit.count == 40);

    // The project.
    project := copy_string(tprint("%1/project", root));
    git_url := copy_string(path_slashes(repository));
    expect(ic_write(project, "package.jai", ic_external_project_declaration(git_url)));
    expect(ic_write(project, "src/module.jai", "External_Value :: 1;\n"));
    expect(ic_write(project, "src/main.jai", ic_lines(string.[
        "#import \"Basic\";",
        "#import \"Path_Lib\";",
        "#import \"Git_Lib\";",
        "#import \"Member_Lib\";",
        "",
        "main :: () { print(\"path=%1 git=%2 member=%3\\n\", Path_Value, Git_Value, Member_Value); }"])));
    expect(ic_write(project, "packages/member/package.jai", ic_lines(string.[
        "#import \"Juice\";", "", "PACKAGE :: Package.{",
        "    name = \"member\",", "    version = \"0.1.0\",", "};"])));
    expect(ic_write(project, "packages/member/module.jai", "Member_Value :: 55;\n"));
    expect(ic_write(project, "tests/project_tests.jai", ic_lines(string.[
        "#import \"Testing\";",
        "",
        "external_project_test :: () {",
        "    expect(External_Value == 1);",
        "} @test"])));

    // build: the published artifact set compiles the new declaration surface
    // from outside the repository (the declaration is evaluated by the
    // published Juice face, the modules import through the published shims).
    result, output, errors := ic_run_install(install, project, string.["build"]);
    expect(expect_exit("external build", result, 0, "external"));
    artifact := target_artifact_path(package_target_dir(project), "external_app");
    expect(file_exists(artifact), "the external project must produce its program");

    // run: default_run resolves, and the three providers' values arrive.
    result, output, errors = ic_run_install(install, project, string.["run"]);
    expect(expect_exit("external run", result, 0, "external"));
    expect(child_output_contains("external run", output, "path=21 git=34 member=55"));

    // test: the published Testing face and the test-block plugin run outside
    // the repository.
    result, output, errors = ic_run_install(install, project, string.["test"]);
    expect(expect_exit("external test", result, 0, "external"));
    expect(child_output_contains("external test", output, "1 passed, 0 failed"));

    // The provider's exact commit is materialized in this project's own content
    // cache and its selection is recorded in its own resolution state — both
    // under the isolated XDG roots, outside the repository.
    expect(dr_content_has_commit(root, commit), "the external project must resolve the provider's recorded commit");
    state_files := file_list(copy_string(tprint("%1/xdg-state/juice", root)), recursive = true);
    has_state := false;
    for name: state_files {
        if ends_with(name, "resolution.state") has_state = true;
    }
    expect(has_state, "the external project's resolution selection must be recorded");

    // offline: the recorded selection and complete content serve a fully
    // offline build (nothing is fetched, the same commit is compiled).
    result, output, errors = ic_run_install(install, project, string.["build", "--offline"]);
    expect(expect_exit("external offline build", result, 0, "external"));

    // update: refreshes the resolution graph only; offline it is a usage
    // error before any package work.
    result, output, errors = ic_run_install(install, project, string.["update", "--offline"]);
    expect(expect_exit("external offline update", result, 1, "external"));
    combined := tprint("%\n%", output, errors);
    expect(child_output_contains("external offline update", combined, "update cannot run offline"));
    result, output, errors = ic_run_install(install, project, string.["update"]);
    expect(expect_exit("external update", result, 0, "external"));

    // A missing content cache offline fails instead of fetching: the offline
    // guarantee is the recorded content, not a silent clone.
    content_root := copy_string(tprint("%1/xdg-cache/juice/content", root));
    expect(is_directory(content_root), "the Git content must be cached outside the repository");
    dr_delete_wait(content_root);
    result, output, errors = ic_run_install(install, project, string.["build", "--offline"]);
    expect(expect_exit("external offline without content", result, 1, "external"));

    // Online again: the same commit is restored and the build is green.
    result, output, errors = ic_run_install(install, project, string.["build"]);
    expect(expect_exit("external rebuild", result, 0, "external"));
    result, output, errors = ic_run_install(install, project, string.["run"]);
    expect(expect_exit("external rerun", result, 0, "external"));
    expect(child_output_contains("external rerun", output, "path=21 git=34 member=55"));
} @test
