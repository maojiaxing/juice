// ---------------------------------------------------------------------------
// Member plugin unit tests (ticket 061): the `juice-plugin-jaix` member's
// own suite, run with the member root as the package root (`juice test` from
// packages/juice-plugin-jaix). The shared Phase-1 unit matrix migrated here
// from the root tests (ticket 058's tests/jaix_plugin_tests.jai) because the
// value now lives in this member: identity and options schema, the package
// scan matrix (the plugin's own walk and exclusion set), executable
// resolution, the pre-step orchestration through the injected spawn seam,
// and the driver-litter predicate and cleanup.
//
// The real-chain E2E (real otter executable + real jaix CLI through the
// member + host form) stays at the repository root — the member root cannot
// reach the repository's test support declarations (otter_root, the child
// runners), and a member test program only scans its own package.
//
// The module itself stays test-free (the host and the test metaprogram
// compile it directly); all helpers here are prefixed jp_ (the single
// namespace convention).
// ---------------------------------------------------------------------------

#import "Basic";
#import "Compiler";
#import "Testing";
#import "File";
#import "File_Utilities";
#import "String";
#import "juice_core";

// ===========================================================================
// Scratch roots (the member root as the package root)
// ===========================================================================

// The member package root: the generated test driver declares
// JUICE_TEST_PACKAGE_ROOT (the test program's intermediate path is
// <member root>/target/build after C5, so Build_Options.intermediate_path no
// longer yields the root).
jp_member_root :: () -> string {
    return JUICE_TEST_PACKAGE_ROOT;
}

// Remove a directory tree (Jai's rmdir needs backslashes on Windows — the
// cmd builtin parses forward-slash segments as switches).
jp_delete_dir :: (path: string) -> bool {
    if !file_exists(path) return true;
    #if OS == .WINDOWS {
        res := run_command("cmd", "/c", "rmdir", "/S", "/Q", jaix_path_backslashes(path));
        return res.exit_code == 0;
    } else {
        res := run_command("rm", "-rf", path);
        return res.exit_code == 0;
    }
}

// "/"-to-"\" copy for cmd invocations (the member cannot use the tool's
// internal path_safety helper).
jaix_path_backslashes :: (path: string) -> string {
    result := copy_string(path);
    for i: 0..result.count-1 {
        if result[i] == #char "/" result[i] = #char "\\";
    }
    return result;
}

// A fresh scratch root under the member's target/ (session products only).
jp_scratch :: (name: string) -> string {
    root := jaix_path_slashes(tprint("%1/target/jaix-plugin-tests/%2", jp_member_root(), name));
    jp_delete_dir(root);
    make_directory_if_it_does_not_exist(root, recursive = true);
    return root;
}

// Write one package-relative file under a scratch root (parents created).
jp_write :: (root: string, rel: string, content: string) -> bool {
    path := tprint("%1/%2", root, rel);
    if !make_directory_if_it_does_not_exist(path_strip_filename(path), recursive = true) return false;
    return write_entire_file(path, content);
}

// ===========================================================================
// Recording spawn fake (the run_jaix_prestep seam)
// ===========================================================================

JP_SPAWN: [..] string;
JP_SPAWN_EXIT: s64 = 0;
JP_SPAWN_STDERR: string = "";

jp_reset_spawn :: () {
    array_reset(*JP_SPAWN);
    JP_SPAWN_EXIT = 0;
    JP_SPAWN_STDERR = "";
}

jp_fake_spawn :: (exe: string, input: string, output: string, config: string, driver_dir: string) -> (exit_code: s64, stderr: string) {
    array_add(*JP_SPAWN, tprint("%1|%2|%3|%4|%5", exe, input, output, config, driver_dir));
    return JP_SPAWN_EXIT, JP_SPAWN_STDERR;
}

// The pre-step context over a scratch root (the stage state the host fills
// before dispatching PRESTEP). The stage lives on the heap — the context
// outlives this call (a stack stage would dangle).
jp_prestep_context :: (root: string, diags: *[..] Lifecycle_Diagnostic) -> Lifecycle_Context {
    stage := New(Prestep_Stage);
    stage.root_dir = root;
    ctx: Lifecycle_Context;
    ctx.diagnostics = diags;
    ctx.prestep = cast(*void) stage;
    return ctx;
}

// ===========================================================================
// Identity and options
// ===========================================================================

test "Jaix plugin: identity, PRESTEP mount and the options schema" {
    plugin := get_juice_plugin();
    expect(plugin.id == "juice-plugin-jaix");
    expect(plugin.version == "0.1.0");
    // The unified face: no transpile face, no lint face, exactly one PRESTEP
    // before hook (the pre-step posture).
    expect(plugin.transpile == null && plugin.lint == null);
    expect(plugin.hooks.count == 1);
    expect(plugin.hooks[0].stage == .PRESTEP && plugin.hooks[0].position == .before);
    expect(plugin.hooks[0].hook == jaix_prestep_hook);
    // The options channel points at the plugin instance itself (the apply /
    // validate / plugin_state contract).
    expect(plugin.options != null && cast(*Jaix_Plugin) plugin.options == plugin);
    // The schema: config + exe, both defaulting to "".
    expect(plugin.options_schema.count == 2);
    expect(plugin.options_schema[0].name == "config" && plugin.options_schema[1].name == "exe");
    expect((cast(*string) plugin.options_schema[0].default).* == "");
    expect((cast(*string) plugin.options_schema[1].default).* == "");

    // apply writes the typed members; an unknown key is the plugin's error.
    expect(plugin.options_schema[0].apply(plugin.options, "config", "jaix.config.jai") == "");
    expect(plugin.config == "jaix.config.jai");
    expect(plugin.options_schema[1].apply(plugin.options, "exe", "tools/jaix.exe") == "");
    expect(plugin.exe == "tools/jaix.exe");
    expect(plugin.options_schema[0].apply(plugin.options, "mystery", "x") == "unknown option 'mystery'");

    // validate: an exe without a config rejects; a config alone passes.
    expect(plugin.options_schema[0].validate(plugin.options) == "");
    plugin.config = "";
    expect(plugin.options_schema[0].validate(plugin.options) == "option 'exe' requires 'config'");
    plugin.exe = "";
    expect(plugin.options_schema[0].validate(plugin.options) == "");
}

test "Jaix plugin: the member identity resolves through the declared config surface" {
    // The member's value goes through the same merge/resolver the host uses:
    // declaration version and options arrive at the typed members, and the
    // slot options pointer is the plugin instance.
    plugins: [..] *Juice_Plugin;
    array_add(*plugins, as_plugin(get_juice_plugin()));
    merged := merge_plugins(plugins);
    expect(merged.ok);
    expect(merged.registry.count == 1);

    config: Plugin_Config = .{
        id      = "juice-plugin-jaix",
        version = "0.1.0",
        options = Option_Row.[
            .{key = "config", value = "jaix.config.jai"},
            .{key = "exe",    value = "tools/jaix.exe"},
        ],
    };
    resolved := resolve_plugin_configs(merged.registry, Plugin_Config.[config]);
    expect(resolved.ok);
    expect(resolved.hook_table.count == 1);
    expect(resolved.hook_table[0].hooks[0].stage == .PRESTEP);
    expect(resolved.hook_table[0].hooks[0].position == .before);
    expect(resolved.slot_options.count == 1);
    slot_plugin := cast(*Jaix_Plugin) resolved.slot_options[0];
    expect(slot_plugin.config == "jaix.config.jai");
    expect(slot_plugin.exe == "tools/jaix.exe");
    // No declared transpile face: the default pipeline stays (the pre-step
    // declaration must never disable transpiling).
    expect(resolved.pipeline.count == 2);
    expect(resolved.pipeline[0].name == "load" && resolved.pipeline[1].name == "test-block");

    // The declaration gates: a wrong version and exe-without-config reject.
    // Each gate check starts from a fresh plugin value — the resolver's
    // options apply mutates the instance, so a reused registry would carry
    // the earlier rows.
    gate_plugins: [..] *Juice_Plugin;
    array_add(*gate_plugins, as_plugin(get_juice_plugin()));
    gate_merged := merge_plugins(gate_plugins);
    bad_version := resolve_plugin_configs(gate_merged.registry, Plugin_Config.[.{id = "juice-plugin-jaix", version = "9.9.9"}]);
    expect(!bad_version.ok);
    expect(bad_version.diagnostics.count == 1);
    expect(bad_version.diagnostics[0].message == "plugin version mismatch: juice-plugin-jaix (declared 9.9.9, plugin 0.1.0)");
    bad_options := resolve_plugin_configs(gate_merged.registry, Plugin_Config.[.{
        id      = "juice-plugin-jaix",
        version = "0.1.0",
        options = Option_Row.[.{key = "exe", value = "tools/jaix.exe"}],
    }]);
    expect(!bad_options.ok);
    expect(bad_options.diagnostics.count == 1);
    expect(bad_options.diagnostics[0].message == "invalid plugin options: juice-plugin-jaix (option 'exe' requires 'config')");
}

// ===========================================================================
// Scan matrix
// ===========================================================================

test "Jaix plugin: the scan applies the exclusion set in scan order" {
    root := jp_scratch("scan");
    defer jp_delete_dir(root);
    expect(jp_write(root, "package.jai", "PACKAGE :: Package.{};\n"));
    expect(jp_write(root, "jaix.config.jai", "// config\n"));
    expect(jp_write(root, ".hidden.jai", "// dot file\n"));
    expect(jp_write(root, "notes.txt", "not jai\n"));
    expect(jp_write(root, ".hidden_dir/inside.jai", "// dot dir\n"));
    expect(jp_write(root, "lib_deep/package.jai", "// nested manifest is user code\n"));
    expect(jp_write(root, "src/main.jai", "main :: () {}\n"));
    expect(jp_write(root, "src/calc.jai", "half :: (n: int) -> int { return n / 2; }\n"));
    expect(jp_write(root, "src/calc_tests.jai", "test \"demo\" { }\n"));
    expect(jp_write(root, "src/sub/deep.jai", "deep :: 1;\n"));
    expect(jp_write(root, "src/target/ok.jai", "ok :: 2;\n"));
    expect(jp_write(root, "src/.dotdir/x.jai", "// dot dir nested\n"));
    expect(jp_write(root, "target/stale.jai", "// managed product\n"));
    expect(jp_write(root, "member/own.jai", "member :: 3;\n"));

    member_dirs: [..] string;
    array_add(*member_dirs, tprint("%1/member", root));
    files, ok := collect_jaix_files(root, "jaix.config.jai", member_dirs);
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
        expect(files[i].abs_path == jaix_path_slashes(tprint("%1/%2", root, expected[i])));
    }
}

test "Jaix plugin: the scan excludes driver litter" {
    root := jp_scratch("scan-litter");
    defer jp_delete_dir(root);
    expect(jp_write(root, "package.jai", "PACKAGE :: Package.{};\n"));
    expect(jp_write(root, "9f1120f8dbedfeaa.jai", "#import \"Basic\";\n#load \"C:/pkg/jaix.config.jai\";\n\n// jaix transpile driver：JAIX_TRANSPILE_PROTOCOL=2\n"));
    expect(jp_write(root, "src/main.jai", "main :: () {}\n"));

    files, ok := collect_jaix_files(root, "jaix.config.jai", string.[]);
    expect(ok);
    expect(files.count == 1);
    expect(files[0].rel_path == "src/main.jai");
}

test "Jaix plugin: the scan rejects a missing package root" {
    _, ok := collect_jaix_files(tprint("%1/target/no-such-package", jp_member_root()), "c", string.[]);
    expect(!ok);
}

// ===========================================================================
// Executable resolution
// ===========================================================================

test "Jaix plugin: exe resolution prefers the option and resolves against the root" {
    root := jp_scratch("exe");
    defer jp_delete_dir(root);
    expect(jp_write(root, "tools/jaix.exe", ""));
    plugin := get_juice_plugin();
    plugin.exe = "tools/jaix.exe";
    exe, ok := resolve_jaix_exe(plugin, root);
    expect(ok && exe == jaix_path_slashes(tprint("%1/tools/jaix.exe", root)));
    // An absolute option is used as-is.
    plugin.exe = jaix_path_slashes(tprint("%1/tools/jaix.exe", root));
    exe, ok = resolve_jaix_exe(plugin, root);
    expect(ok && exe == jaix_path_slashes(tprint("%1/tools/jaix.exe", root)));
}

test "Jaix plugin: exe resolution falls back to the PATH probe in entry order" {
    root := jp_scratch("path");
    defer jp_delete_dir(root);
    expect(jp_write(root, "a/jaix.exe", ""));
    expect(jp_write(root, "b/jaix.exe", ""));
    plugin := get_juice_plugin();
    path_value := tprint("%1/a;%1/b", root, root);
    exe, ok := resolve_jaix_exe(plugin, root, path_value);
    expect(ok && exe == jaix_path_slashes(tprint("%1/a/jaix.exe", root)));
}

test "Jaix plugin: a missing executable fails with the clear error" {
    plugin := get_juice_plugin();
    plugin.exe = "no-such-jaix.exe";
    _, ok := resolve_jaix_exe(plugin, "some-root");
    expect(!ok);
    plugin.exe = "";
    _, ok = resolve_jaix_exe(plugin, "some-root", "C:/nowhere");
    expect(!ok);
}

// ===========================================================================
// Pre-step orchestration (the spawn seam): substitution table and drop set
// ===========================================================================

test "Jaix plugin: the pre-step spawns per file with absolute paths into the mirror" {
    root := jp_scratch("prestep");
    defer jp_delete_dir(root);
    expect(jp_write(root, "package.jai", "PACKAGE :: Package.{};\n"));
    expect(jp_write(root, "jaix.config.jai", "// config\n"));
    expect(jp_write(root, "src/main.jai", "main :: () {}\n"));
    expect(jp_write(root, "src/calc.jai", "half :: (n: int) -> int { return n / 2; }\n"));
    expect(jp_write(root, "fake-jaix.exe", ""));

    plugin := get_juice_plugin();
    plugin.config = "jaix.config.jai";
    plugin.exe = "fake-jaix.exe";
    diags: [..] Lifecycle_Diagnostic;
    ctx := jp_prestep_context(root, *diags);
    jp_reset_spawn();
    expect(run_jaix_prestep(*ctx, plugin, jp_fake_spawn));

    // The config file itself is skipped (the compile-time input, not a
    // transpile input); every other scanned file spawns once, in scan
    // order.
    expect(JP_SPAWN.count == 2);
    expected := string.[
        jaix_path_slashes(tprint("%1/fake-jaix.exe|%1/src/calc.jai|%1/target/jaix/src/calc.jai|%1/jaix.config.jai|%1/target/jaix-drivers", root)),
        jaix_path_slashes(tprint("%1/fake-jaix.exe|%1/src/main.jai|%1/target/jaix/src/main.jai|%1/jaix.config.jai|%1/target/jaix-drivers", root)),
    ];
    expect(JP_SPAWN.count == expected.count);
    for i: 0..expected.count-1 {
        expect(JP_SPAWN[i] == expected[i]);
    }

    // The stage effects: every mirror file is a substitution (original rel
    // path -> mirror absolute path), the config is a drop.
    stage := cast(*Prestep_Stage) ctx.prestep;
    expect(stage.substitutions.count == 2);
    expect(stage.substitutions[0].original == "src/calc.jai");
    expect(stage.substitutions[0].replacement == jaix_path_slashes(tprint("%1/target/jaix/src/calc.jai", root)));
    expect(stage.substitutions[1].original == "src/main.jai");
    expect(stage.drops.count == 1 && stage.drops[0] == "jaix.config.jai");

    // The mirror parents exist on disk (the fake does not write files) and
    // the CLI driver directory was created.
    expect(is_directory(jaix_path_slashes(tprint("%1/target/jaix/src", root))));
    expect(is_directory(jaix_path_slashes(tprint("%1/target/jaix-drivers", root))));
}

test "Jaix plugin: a nonzero spawn fails the pre-step fast with stderr passthrough" {
    root := jp_scratch("prestep-fail");
    defer jp_delete_dir(root);
    expect(jp_write(root, "jaix.config.jai", "// config\n"));
    expect(jp_write(root, "src/main.jai", "main :: () {}\n"));
    expect(jp_write(root, "fake-jaix.exe", ""));

    plugin := get_juice_plugin();
    plugin.config = "jaix.config.jai";
    plugin.exe = "fake-jaix.exe";
    diags: [..] Lifecycle_Diagnostic;
    ctx := jp_prestep_context(root, *diags);
    jp_reset_spawn();
    JP_SPAWN_EXIT = 1;
    JP_SPAWN_STDERR = "boom: bad syntax\n";
    expect(!run_jaix_prestep(*ctx, plugin, jp_fake_spawn));
    // The first scanned file fails the pre-step; the failure lands as an
    // ERROR diagnostic (the dispatch fails the stage on it).
    expect(JP_SPAWN.count == 1);
    expect(diags.count == 1);
    expect(diags[0].level == .ERROR);
    expect(diags[0].message == "jaix pre-step failed for src/main.jai");
    stage := cast(*Prestep_Stage) ctx.prestep;
    expect(stage.substitutions.count == 0);
}

test "Jaix plugin: a declared config that does not exist fails before any spawn" {
    root := jp_scratch("prestep-noconfig");
    defer jp_delete_dir(root);
    expect(jp_write(root, "fake-jaix.exe", ""));
    expect(jp_write(root, "src/main.jai", "main :: () {}\n"));

    plugin := get_juice_plugin();
    plugin.config = "no-such.config.jai";
    plugin.exe = "fake-jaix.exe";
    diags: [..] Lifecycle_Diagnostic;
    ctx := jp_prestep_context(root, *diags);
    jp_reset_spawn();
    expect(!run_jaix_prestep(*ctx, plugin, jp_fake_spawn));
    expect(JP_SPAWN.count == 0);
    expect(diags.count == 1 && diags[0].level == .ERROR);
    expect(find_index_from_left(diags[0].message, "jaix config not found: ") >= 0);
}

test "Jaix plugin: an undeclared config is the no-op shape" {
    root := jp_scratch("prestep-noop");
    defer jp_delete_dir(root);
    plugin := get_juice_plugin();   // config stays ""
    diags: [..] Lifecycle_Diagnostic;
    ctx := jp_prestep_context(root, *diags);
    jp_reset_spawn();
    expect(jaix_prestep_hook(*ctx, cast(*void) plugin));
    expect(JP_SPAWN.count == 0);
    stage := cast(*Prestep_Stage) ctx.prestep;
    expect(stage.substitutions.count == 0 && stage.drops.count == 0);
}

test "Jaix plugin: missing hook wiring fails with an ERROR diagnostic" {
    // A null options slot (the dispatch's missing-slot shape).
    diags: [..] Lifecycle_Diagnostic;
    ctx: Lifecycle_Context;
    ctx.diagnostics = *diags;
    expect(!jaix_prestep_hook(*ctx, null));
    expect(diags.count == 1 && diags[0].level == .ERROR);

    // A declared config without the PRESTEP stage slot.
    plugin := get_juice_plugin();
    plugin.config = "jaix.config.jai";
    diags2: [..] Lifecycle_Diagnostic;
    ctx2: Lifecycle_Context;
    ctx2.diagnostics = *diags2;
    expect(!jaix_prestep_hook(*ctx2, cast(*void) plugin));
    expect(diags2.count == 1 && diags2[0].level == .ERROR);
}

// ===========================================================================
// Driver litter: identification and cleanup
// ===========================================================================

test "Jaix plugin: the head marker identifies real and legacy drivers" {
    root := jp_scratch("litter");
    defer jp_delete_dir(root);

    // The real driver shape, hash-named without a dot (legacy
    // pre-dot-prefix naming): the marker line is not the first line.
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

test "Jaix plugin: CRLF line endings tolerate the carriage return" {
    root := jp_scratch("litter-crlf");
    defer jp_delete_dir(root);
    crlf := tprint("%1/crlf.jai", root);
    expect(write_entire_file(crlf, "#import \"Basic\";\r\n#load \"c.jai\";\r\n// jaix transpile driver root_dir = C:/pkg\r\n"));
    expect(is_jaix_driver_litter(crlf));
}

test "Jaix plugin: user files stay in — marker past the head window or not at line start" {
    root := jp_scratch("litter-keep");
    defer jp_delete_dir(root);

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

    // An unreadable file is not litter — the real diagnostic stays with the
    // consumer.
    expect(!is_jaix_driver_litter(tprint("%1/no-such.jai", root)));
}

test "Jaix plugin: the cleanup removes root driver litter and drops the paths" {
    root := jp_scratch("litter-clean");
    defer jp_delete_dir(root);
    expect(jp_write(root, "package.jai", "PACKAGE :: Package.{};\n"));
    expect(jp_write(root, "cafebabe01234567.jai", "#import \"Basic\";\n// jaix transpile driver：JAIX_TRANSPILE_PROTOCOL=2\n"));
    expect(jp_write(root, ".jaix-deadbeef.jai", "// jaix transpile driver root_dir = C:/pkg\n"));
    expect(jp_write(root, "user.jai", "user :: 1;\n"));
    expect(jp_write(root, "notes.txt", "// jaix transpile driver but not jai\n"));

    diags: [..] Lifecycle_Diagnostic;
    ctx := jp_prestep_context(root, *diags);
    expect(clean_jaix_driver_litter(*ctx));
    expect(!file_exists(tprint("%1/cafebabe01234567.jai", root)));
    expect(!file_exists(tprint("%1/.jaix-deadbeef.jai", root)));
    expect(file_exists(tprint("%1/user.jai", root)));
    expect(file_exists(tprint("%1/notes.txt", root)));
    stage := cast(*Prestep_Stage) ctx.prestep;
    expect(stage.drops.count == 2);
    // Enumeration order of the root entries is the filesystem's; the drop
    // set only needs to carry both removed names.
    expect(prestep_is_dropped(stage, "cafebabe01234567.jai"));
    expect(prestep_is_dropped(stage, ".jaix-deadbeef.jai"));
}
