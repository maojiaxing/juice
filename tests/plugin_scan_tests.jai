// ---------------------------------------------------------------------------
// Plugin scan + registration codegen tests (ticket 025): the lexical anchor
// recognition matrix (the is_test_anchor technique — anchored shapes and
// the false-positive surface), the scan-order determinism with the module
// name derivation and the entry-probe precedence, the two-segment
// registration file shape (byte for byte) and the landing path, plus the
// E2E full chain over the synthetic fixture plugin package: production scan
// -> registration file -> real jai child compiling driver + registration +
// fixture modules -> merged registry execution (transpile face + hooks).
// Ticket 043 adds the workspace-level scan matrix: real fixture workspaces
// (real package.jai manifests through the production discovery face) pin the
// declaration-driven selection (ticket 056: Package.plugins order, member
// location by package name, import shims, unknown-id / zero-plugin /
// multi-plugin failures), the cross-package module-name arbitration (tie and
// probe-rank cases) and the unscannable-root failure channel. The 040 review
// fixes extend it: the probe-rank winner's POSITION (it must stay in its own
// declaration segment), an unreadable source failing the scan (ok=false,
// US 27) through the workspace channel, and the real repository root's
// declaration surface (exactly the one lint plugin hit). Ticket 050 adds the
// distribution contract pin: the canonical member's manifest, evaluated
// through the same production discovery face, declares zero dependencies —
// juice_core is tool-provided, never a workspace DEP. Ticket 056 migrates
// the whole workspace matrix from root-DEP activation to Package.plugins
// declarations.
//
// src/plugin_scan.jai is a bootstrap #load target and stays test-free; its
// tests live here (tests/), per the test organization rule: referenced by
// no #load, collected into the test program by Test discovery's
// full-package scan. Good-test standard: only external behavior is pinned
// (given sources / packages -> hits / generated text / child output); the
// scan internals are never asserted. The scratch fixtures live under
// target/plugin-scan-tests/ (session artifacts — root-level target/ is
// excluded from test discovery and from the plugin scan itself).
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";
#import "File";
#import "String";

#if OS == .WINDOWS {
    // The exclusive-open read-failure test (review fix F1) mirrors the
    // artifact_is_running discipline (src/commands/build.jai): a share-mode-0
    // handle makes every later open fail with a sharing violation.
    #import "Windows";
    #import "Windows_Utf8";
}

// ===========================================================================
// Anchor matrix helpers
// ===========================================================================

// A minimal anchored declaration source (the return type is deliberately
// unresolved — the scan is lexical, the scratch sources never compile).
ANCHORED_SOURCE :: "get_juice_plugin :: () -> *X { return null; } @juice_plugin\n";

// Whether any token position in the source carries the anchor.
source_has_anchor :: (source: string) -> bool {
    s := normalize_view_line_endings(source);
    tokens := lex_source(s);
    i := 0;
    while i < tokens.count {
        if is_juice_plugin_anchor(s, tokens, i) return true;
        i += 1;
    }
    return false;
}

// ===========================================================================
// Anchor recognition matrix
// ===========================================================================

test "插件扫描锚点：尾注挂 get_juice_plugin 声明命中" {
    expect(source_has_anchor(ANCHORED_SOURCE));
    // A chain of notes before the plugin note still hangs the anchor.
    expect(source_has_anchor("get_juice_plugin :: () -> *X { return null; } @a @juice_plugin\n"));
    // A body-less declaration carries the note at its tail too.
    expect(source_has_anchor("get_juice_plugin :: () -> *X; @juice_plugin\n"));
    // A noted declaration before the anchor must not hide the statement
    // boundary.
    expect(source_has_anchor("f :: () { } @note\nget_juice_plugin :: () -> *X { return null; } @juice_plugin\n"));
    // The plugin note's exact text (single source: JUICE_PLUGIN_NOTE).
    expect(JUICE_PLUGIN_NOTE == "@juice_plugin");
}

test "插件扫描锚点：无注记/注记挂别处/调用位/文本内注记不命中" {
    // The declaration without the tail note is not anchored.
    expect(!source_has_anchor("get_juice_plugin :: () -> *X { return null; }\n"));
    // The note hanging on another declaration is not an anchor.
    expect(!source_has_anchor("other :: () { } @juice_plugin\n"));
    // A reference at a non-statement position is not a declaration.
    expect(!source_has_anchor("p.get_juice_plugin();\n"));
    expect(!source_has_anchor("x := get_juice_plugin;\n"));
    // Note text inside a string or a comment never surfaces as tokens.
    expect(!source_has_anchor("NOTE :: \"@juice_plugin\";\n"));
    expect(!source_has_anchor("// @juice_plugin\n"));
    // A near-miss note text does not match.
    expect(!source_has_anchor("get_juice_plugin :: () -> *X { return null; } @juice_pluginx\n"));
    expect(!source_has_anchor("get_juice_plugin :: () -> *X { return null; } @juice_plugi\n"));
    // The note must hang on this declaration's own tail — a note on a
    // following declaration does not attach.
    expect(!source_has_anchor("get_juice_plugin :: () -> *X { return null; }\nother :: () { } @juice_plugin\n"));
}

// ===========================================================================
// Scan order + module names + probe precedence
// ===========================================================================

plugin_scan_scratch_root :: () -> string {
    return otter_scratch("plugin-scan-tests");
}

test "插件扫描：词法序扫描 + 模块名派生矩阵" {
    root := tprint("%1/scan-matrix", plugin_scan_scratch_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    // Anchored: root module.jai (dir name), zed.jai (stem), src/module.jai
    // ("<dir>/src"), sub/extra.jai (stem). Not anchored or excluded:
    // decoy.jai (no anchor), target/ignored.jai (root-level target/),
    // .hidden.jai (dot entry), notes.txt (non-.jai).
    expect(build_seam_write(root, "module.jai", ANCHORED_SOURCE));
    expect(build_seam_write(root, "zed.jai", ANCHORED_SOURCE));
    expect(build_seam_write(root, "src/module.jai", ANCHORED_SOURCE));
    expect(build_seam_write(root, "sub/extra.jai", ANCHORED_SOURCE));
    expect(build_seam_write(root, "decoy.jai", "NOTE :: \"@juice_plugin\";\n"));
    expect(build_seam_write(root, "target/ignored.jai", ANCHORED_SOURCE));
    expect(build_seam_write(root, ".hidden.jai", ANCHORED_SOURCE));
    expect(build_seam_write(root, "notes.txt", ANCHORED_SOURCE));

    scan := scan_plugin_package(root);
    expect(scan.ok);
    expect(scan.diagnostics.count == 0);
    expect(scan.hits.count == 4);
    // Scan order (files first, lexicographic, then subdirectories
    // lexicographic): module.jai, zed.jai, src/module.jai, sub/extra.jai.
    expect(scan.hits[0].module_name == "scan-matrix" && scan.hits[0].rel_path == "module.jai");
    expect(scan.hits[1].module_name == "zed" && scan.hits[1].rel_path == "zed.jai");
    expect(scan.hits[2].module_name == "scan-matrix/src" && scan.hits[2].rel_path == "src/module.jai");
    expect(scan.hits[3].module_name == "sub/extra" && scan.hits[3].rel_path == "sub/extra.jai");
    // The abs paths point at the real scratch files.
    expect(scan.hits[0].abs_path == path_slashes(tprint("%1/module.jai", root)));
}

test "插件扫描：重复模块名按探测序裁定" {
    // module.jai (probe rank 1) beats <dir>.jai (rank 3) — both derive the
    // package directory name.
    root := tprint("%1/dup-probe", plugin_scan_scratch_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "dup-probe.jai", ANCHORED_SOURCE));
    expect(build_seam_write(root, "module.jai", ANCHORED_SOURCE));
    scan := scan_plugin_package(root);
    expect(scan.ok);
    expect(scan.hits.count == 1);
    expect(scan.hits[0].rel_path == "module.jai");
    expect(scan.diagnostics.count == 1);
    expect(scan.diagnostics[0].rel_path == "dup-probe.jai");

    // Equal ranks (two anchored declarations in one file derive the same
    // module name): the earlier declaration in scan order wins.
    root2 := tprint("%1/dup-equal", plugin_scan_scratch_root());
    delete_directory_full(root2);
    defer delete_directory_full(root2);
    expect(build_seam_write(root2, "extra.jai", tprint("%1%1", ANCHORED_SOURCE, ANCHORED_SOURCE)));
    scan2 := scan_plugin_package(root2);
    expect(scan2.ok);
    expect(scan2.hits.count == 1);
    expect(scan2.hits[0].rel_path == "extra.jai");
    expect(scan2.diagnostics.count == 1);
    expect(scan2.diagnostics[0].rel_path == "extra.jai");
}

test "插件扫描：不可扫根失败通道" {
    scan := scan_plugin_package(tprint("%1/does-not-exist", plugin_scan_scratch_root()));
    expect(!scan.ok);
    expect(scan.hits.count == 0);
}

test "插件扫描：源读取失败 = ok=false 响亮失败（保留诊断 + 工作区同频道）" {
    root := tprint("%1/read-failure", plugin_scan_scratch_root());
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "locked.jai", ANCHORED_SOURCE));

    // Deterministic read failure (US 27), Windows-first: hold the source
    // with an exclusive read handle (share mode 0 — the artifact_is_running
    // open discipline), so the scan's own open fails with a sharing
    // violation. No injection seam: the scan sees a genuinely unreadable
    // source file.
    #if OS == .WINDOWS {
        wide_path, wide_ok, _ := utf8_to_wide(path_slashes(tprint("%1/locked.jai", root)));
        expect(wide_ok);
        handle := CreateFileW(wide_path, GENERIC_READ, share_mode = 0, creation = OPEN_EXISTING);
        expect(handle != INVALID_HANDLE_VALUE);
        if handle != INVALID_HANDLE_VALUE {
            scan := scan_plugin_package(root);

            // The workspace scan propagates the read failure through the
            // same ok=false channel the test command checks: a broken plugin
            // package fails loudly instead of degrading into "no plugins".
            // Both scans run while the exclusive handle is held.
            discovery: Juice.Workspace_Discovery;
            discovery.root_dir = "C:/plugin-workspace-read-failure";
            discovery.has_package = true;
            discovery.root_package.name = "read-failure-root";
            discovery.root_package.plugins = Juice.Plugin_Declaration.[.{id = "read-failure-member", version = "0.1.0"}];
            discovery.member_packages = Juice.Package.[.{name = "read-failure-member", dir = root}];
            workspace_scan := scan_workspace_plugins(discovery);
            CloseHandle(handle);

            expect(!scan.ok);
            expect(scan.hits.count == 0);
            expect(scan.diagnostics.count == 1);
            expect(scan.diagnostics[0].rel_path == "locked.jai");
            expect(scan.diagnostics[0].message == "could not read plugin source");
            expect(!workspace_scan.ok);
        }
    }
}

// ===========================================================================
// Workspace-level scan (ticket 043): real fixture workspaces through the
// production discovery face
// ===========================================================================

plugin_workspace_fixture_root :: (fixture_name: string) -> string {
    return path_slashes(tprint("%1/tests/data/%2", otter_root(), fixture_name));
}

// Discovery through the production face: every fixture manifest is a real
// package.jai evaluated by real jai children against the published module
// faces (ensure_published_modules). The cache directory is a session
// artifact under target/ (excluded from test discovery and from the plugin
// scan).
discover_plugin_workspace_fixture :: (fixture_name: string) -> Juice.Workspace_Discovery, bool {
    ensure_published_modules();
    cache := path_slashes(otter_scratch(tprint("plugin-scan-tests/workspace-cache/%1", fixture_name)));
    discovery, ok := discover_workspace(plugin_workspace_fixture_root(fixture_name), cache, plugin_face_modules_dir());
    return discovery, ok;
}

test "工作区插件扫描：按 Package.plugins 声明序（优先于目录序），未声明成员与 DEP 不扫描" {
    discovery, ok := discover_plugin_workspace_fixture("plugin-workspace");
    expect(ok && discovery.has_package);
    root := plugin_workspace_fixture_root("plugin-workspace");
    defer delete_directory_full(package_target_dir(root));

    // The fixture declares zeta-plugin first and alpha-plugin second; the
    // workspace.members order and the package directory order both put
    // alpha-plugin first — the scan follows the declarations. plain-member
    // (a member) is not declared and carries no anchor; external-lib is an
    // ordinary dependency naming no member. Neither is scanned: the root
    // dependencies never activate plugins. Each declared member provides
    // exactly one plugin and gets its import shim (the retired DEP
    // activation's member-link role).
    scan := scan_workspace_plugins(discovery);
    expect(scan.ok);
    expect(scan.hits.count == 2);
    expect(scan.diagnostics.count == 0);
    expect(scan.hits[0].module_name == "zeta-plugin");
    expect(paths_equal(scan.hits[0].abs_path, tprint("%1/packages/zeta-plugin/module.jai", root)));
    expect(scan.hits[1].module_name == "alpha-plugin");
    expect(paths_equal(scan.hits[1].abs_path, tprint("%1/packages/alpha-plugin/module.jai", root)));
    expect(file_contains(tprint("%1/zeta-plugin.jai", packages_dir(root)), "import shim for package 'zeta-plugin'"));
    expect(file_contains(tprint("%1/alpha-plugin.jai", packages_dir(root)), "import shim for package 'alpha-plugin'"));
    expect(!file_exists(tprint("%1/plain-member.jai", packages_dir(root))));
}

test "工作区插件扫描：跨包同名模块同级累积序裁定（先声明者胜）+ 非致命诊断" {
    discovery, ok := discover_plugin_workspace_fixture("plugin-workspace-dup");
    expect(ok && discovery.has_package);
    root := plugin_workspace_fixture_root("plugin-workspace-dup");
    defer delete_directory_full(package_target_dir(root));

    scan := scan_workspace_plugins(discovery);
    expect(scan.ok);
    expect(scan.hits.count == 1);
    expect(scan.hits[0].module_name == "extra");
    // Equal probe ranks (both hit files are extra.jai): the earlier
    // declaration's hit stays; the second is dropped.
    expect(paths_equal(scan.hits[0].abs_path, tprint("%1/packages/first-plugin/extra.jai", root)));
    expect(scan.diagnostics.count == 1);
    expect(!scan.diagnostics[0].fatal);
    expect(scan.diagnostics[0].rel_path == "extra.jai");
    expect(contains(scan.diagnostics[0].message, "duplicate plugin module name extra"));
}

test "工作区插件扫描：跨包低探测序胜（与声明序无关）+ 命中位置守声明序 + 非致命诊断" {
    discovery, ok := discover_plugin_workspace_fixture("plugin-workspace-rank");
    expect(ok && discovery.has_package);
    root := plugin_workspace_fixture_root("plugin-workspace-rank");
    defer delete_directory_full(package_target_dir(root));

    // alpha-first (declared first) yields module.jai ("alpha-first");
    // zeta-extra (declared second) yields extra.jai ("extra", rank 3);
    // packages/extra (declared third) yields module.jai ("extra", rank 1).
    // The lower probe rank wins the "extra" collision regardless of
    // declaration order (the rank-3 hit is dropped with a diagnostic) — and
    // the winner lands at the THIRD package's position: it must follow
    // alpha-first's surviving hit (declaration order, then intra-package
    // scan order), never hoist into the dropped hit's slot.
    scan := scan_workspace_plugins(discovery);
    expect(scan.ok);
    expect(scan.hits.count == 2);
    expect(scan.hits[0].module_name == "alpha-first");
    expect(paths_equal(scan.hits[0].abs_path, tprint("%1/packages/alpha-first/module.jai", root)));
    expect(scan.hits[1].module_name == "extra");
    expect(paths_equal(scan.hits[1].abs_path, tprint("%1/packages/extra/module.jai", root)));
    expect(scan.diagnostics.count == 1);
    expect(scan.diagnostics[0].rel_path == "extra.jai");
    expect(contains(scan.diagnostics[0].message, "duplicate plugin module name extra"));
}

test "工作区插件扫描：不可扫成员根 = ok=false 响亮失败通道" {
    missing := path_slashes(tprint("%1/missing-member", plugin_scan_scratch_root()));
    delete_directory_full(missing);

    // A constructed snapshot stands in for a stale discovery result whose
    // member directory disappeared: the scan must fail loudly, not degrade
    // into "no plugins".
    discovery: Juice.Workspace_Discovery;
    discovery.root_dir = "C:/plugin-workspace-ghost";
    discovery.has_package = true;
    discovery.root_package.name = "ghost-root";
    discovery.root_package.plugins = Juice.Plugin_Declaration.[.{id = "ghost-member"}];
    discovery.member_packages = Juice.Package.[.{name = "ghost-member", dir = missing}];

    scan := scan_workspace_plugins(discovery);
    expect(!scan.ok);
}

test "工作区插件扫描：未知成员插件 id = 致命诊断" {
    // "mystery" is neither a built-in id nor a workspace member: the
    // declaration-driven scan rejects it loudly (the command fails before
    // any compile).
    discovery: Juice.Workspace_Discovery;
    discovery.root_dir = "C:/plugin-workspace-unknown";
    discovery.has_package = true;
    discovery.root_package.name = "unknown-root";
    discovery.root_package.plugins = Juice.Plugin_Declaration.[.{id = "mystery", version = "1"}];
    discovery.member_packages = Juice.Package.[.{name = "unknown-root", dir = "C:/plugin-workspace-unknown"}];

    scan := scan_workspace_plugins(discovery);
    expect(!scan.ok);
    expect(scan.hits.count == 0);
    expect(scan.diagnostics.count == 1);
    expect(scan.diagnostics[0].fatal);
    expect(scan.diagnostics[0].rel_path == "mystery");
    expect(scan.diagnostics[0].message == "Unknown plugin id: mystery");
}

test "工作区插件扫描：成员包必须恰好提供一个插件（零个/多个 = 致命诊断）" {
    root := path_slashes(tprint("%1/decl-checks", plugin_scan_scratch_root()));
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(build_seam_write(root, "packages/empty-member/module.jai", "PLAIN_MEMBER_MARKER :: true;\n"));
    expect(build_seam_write(root, "packages/multi-member/module.jai", ANCHORED_SOURCE));
    expect(build_seam_write(root, "packages/multi-member/extra.jai", ANCHORED_SOURCE));

    // A declared member without a plugin anchor: declaration = activation,
    // so a member that is not a plugin package is a loud error.
    empty_discovery: Juice.Workspace_Discovery;
    empty_discovery.root_dir = root;
    empty_discovery.has_package = true;
    empty_discovery.root_package.name = "decl-checks-root";
    empty_discovery.root_package.plugins = Juice.Plugin_Declaration.[.{id = "empty-member", version = "0.1.0"}];
    empty_discovery.member_packages = Juice.Package.[
        .{name = "decl-checks-root", dir = root},
        .{name = "empty-member", dir = tprint("%1/packages/empty-member", root)},
    ];
    empty_scan := scan_workspace_plugins(empty_discovery);
    expect(!empty_scan.ok && empty_scan.hits.count == 0);
    expect(empty_scan.diagnostics.count == 1);
    expect(empty_scan.diagnostics[0].fatal);
    expect(empty_scan.diagnostics[0].message == "Member package provides no plugin: empty-member");

    // A declared member with two anchored plugin modules: v1 allows exactly
    // one plugin per package.
    multi_discovery: Juice.Workspace_Discovery;
    multi_discovery.root_dir = root;
    multi_discovery.has_package = true;
    multi_discovery.root_package.name = "decl-checks-root";
    multi_discovery.root_package.plugins = Juice.Plugin_Declaration.[.{id = "multi-member", version = "0.1.0"}];
    multi_discovery.member_packages = Juice.Package.[
        .{name = "decl-checks-root", dir = root},
        .{name = "multi-member", dir = tprint("%1/packages/multi-member", root)},
    ];
    multi_scan := scan_workspace_plugins(multi_discovery);
    expect(!multi_scan.ok && multi_scan.hits.count == 0);
    expect(multi_scan.diagnostics.count == 1);
    expect(multi_scan.diagnostics[0].fatal);
    expect(multi_scan.diagnostics[0].message == "Member package provides multiple plugins: multi-member");
}

test "工作区插件扫描：内置 id 跳过扫描（无成员也无 I/O）" {
    discovery: Juice.Workspace_Discovery;
    discovery.root_dir = "C:/plugin-workspace-builtins";
    discovery.has_package = true;
    discovery.root_package.name = "builtins-root";
    discovery.root_package.plugins = Juice.Plugin_Declaration.[
        .{id = "load", version = "1.0.0"},
        .{id = "test-block", version = "1.0.0"},
    ];
    discovery.member_packages = Juice.Package.[.{name = "builtins-root", dir = "C:/plugin-workspace-builtins"}];

    scan := scan_workspace_plugins(discovery);
    expect(scan.ok && scan.hits.count == 0 && scan.diagnostics.count == 0);
    // The built-ins resolve to the static registry; no member link and no
    // shim directory are produced.
    expect(!is_directory("C:/plugin-workspace-builtins/target/packages"));
}

test "工作区分发契约：规范成员包清单零依赖（juice_core 由工具提供）" {
    // The distribution contract (parent 048 decision 9, ticket 050): the
    // canonical member is a plain, copyable source package, so its manifest
    // must declare no dependencies. juice_core is the tool-provided module
    // face the installed executable resolves from <exe>/modules; a DEP
    // naming it (at any checkout-relative source) makes the package
    // non-portable. The real manifest is evaluated through the production
    // discovery face — no source-text pin — so any edit that reintroduces a
    // tool dependency fails here.
    ensure_published_modules();
    cache := path_slashes(otter_scratch("plugin-scan-cache/member-contract"));
    discovery, ok := discover_workspace(otter_root(), cache, plugin_face_modules_dir());
    expect(ok && discovery.has_package);

    member, found := find_workspace_member(discovery.member_packages, "juice-plugin-lint");
    expect(found);
    expect(member.name == "juice-plugin-lint");
    expect(member.dependencies.count == 0);
    // The member form stays a LIB with its root module and its own tests
    // under tests/ (parent decision 10).
    expect(member.type == .LIB);
    expect(file_exists(tprint("%1/module.jai", member.dir)));
    expect(file_exists(tprint("%1/tests/lint_rule_tests.jai", member.dir)));
}

test "工作区插件扫描：真实仓库根声明面（生产发现 + 扫描声明序成员插件）" {
    // The production discovery face on the real repository root: the root
    // package's workspace.members provides the members and Package.plugins
    // declares them (ticket 056 — no root DEP activation; ticket 061 adds the
    // jaix member). The cache is a session artifact under target/ (excluded
    // from test discovery and from the plugin scan); the member links land
    // under target/packages.
    ensure_published_modules();
    cache := path_slashes(otter_scratch("plugin-scan-cache/repo-root"));
    discovery, ok := discover_workspace(otter_root(), cache, plugin_face_modules_dir());
    expect(ok && discovery.has_package);
    expect(discovery.root_package.name == "juice");
    expect(discovery.root_package.plugins.count == 2);
    expect(discovery.root_package.plugins[0].id == "juice-plugin-lint");
    expect(discovery.root_package.plugins[1].id == "juice-plugin-jaix");
    // The design revision's migration pin: the members are not root
    // dependencies (dependencies never activate plugins).
    for dep: discovery.root_package.dependencies {
        expect(dep.name != "juice-plugin-lint");
        expect(dep.name != "juice-plugin-jaix");
    }

    scan := scan_workspace_plugins(discovery);
    expect(scan.ok);
    expect(scan.diagnostics.count == 0);
    expect(scan.hits.count == 2);
    expect(scan.hits[0].module_name == "juice-plugin-lint");
    expect(scan.hits[0].rel_path == "module.jai");
    expect(scan.hits[1].module_name == "juice-plugin-jaix");
    expect(scan.hits[1].rel_path == "module.jai");
    // The jaix member carries the hooks face: the prepare's conservative
    // host trigger reports it on the repository root.
    expect(scan.has_hooks);
}

// ===========================================================================
// Registration codegen shape
// ===========================================================================

test "注册 codegen：两段形状按扫描序（逐字节）" {
    hits := Plugin_Scan_Hit.[
        .{module_name = "extra", rel_path = "extra.jai", abs_path = "C:/p/extra.jai"},
        .{module_name = "plugin-fixture", rel_path = "module.jai", abs_path = "C:/p/module.jai"},
    ];
    expected: String_Builder;
    append(*expected, "// juice plugin registration — generated session artifact: regenerated every\n");
    append(*expected, "// run, removed by clean with target/, never edited. Scan order = the\n");
    append(*expected, "// declaration order below (spec §5.2).\n");
    append(*expected, "\n");
    append(*expected, "// Segment 1: the per-name imports, scan order. The module names resolve\n");
    append(*expected, "// through the import directories (the scan's entry probe conventions).\n");
    append(*expected, "JUICE_PLUGIN_0 :: #import \"extra\";\n");
    append(*expected, "JUICE_PLUGIN_1 :: #import \"plugin-fixture\";\n");
    append(*expected, "\n");
    append(*expected, "// Segment 2: hook assembly — one JUICE_HOOK_<i> entry per scanned plugin\n");
    append(*expected, "// (that plugin's hooks contribution), scan order. The entries are filled\n");
    append(*expected, "// by the assembly below: Jai has no runtime top-level execution, so\n");
    append(*expected, "// \"loading = joining the table\" exists only as generated code executing\n");
    append(*expected, "// explicitly (research A E1/E2, L§5.4).\n");
    append(*expected, "JUICE_HOOK_0: [..] Lifecycle_Hook;\n");
    append(*expected, "JUICE_HOOK_1: [..] Lifecycle_Hook;\n");
    append(*expected, "\n");
    append(*expected, "// The assembly: the per-name explicit calls, scan order (registration\n");
    append(*expected, "// order). A top-level procedure call is illegal in Jai (research A\n");
    append(*expected, "// E1/E2/E4), so the calls execute here.\n");
    append(*expected, "get_scanned_plugins :: () -> [..] *Juice_Plugin {\n");
    append(*expected, "    plugins: [..] *Juice_Plugin;\n");
    append(*expected, "    p_0 := JUICE_PLUGIN_0.get_juice_plugin();\n");
    append(*expected, "    JUICE_HOOK_0 = p_0.hooks;\n");
    append(*expected, "    array_add(*plugins, as_plugin(p_0));\n");
    append(*expected, "    p_1 := JUICE_PLUGIN_1.get_juice_plugin();\n");
    append(*expected, "    JUICE_HOOK_1 = p_1.hooks;\n");
    append(*expected, "    array_add(*plugins, as_plugin(p_1));\n");
    append(*expected, "    return plugins;\n");
    append(*expected, "}\n");
    append(*expected, "\n");
    append(*expected, "// The hook-entry view of the assembly (scan order) — the segment above\n");
    append(*expected, "// joined into one explicit table.\n");
    append(*expected, "get_scanned_hook_entries :: () -> [..] Lifecycle_Hook {\n");
    append(*expected, "    entries: [..] Lifecycle_Hook;\n");
    append(*expected, "    for h: JUICE_HOOK_0 array_add(*entries, h);\n");
    append(*expected, "    for h: JUICE_HOOK_1 array_add(*entries, h);\n");
    append(*expected, "    return entries;\n");
    append(*expected, "}\n");
    expect(generate_plugin_registration(hits) == builder_to_string(*expected));
}

test "注册 codegen：零命中仍产全形" {
    expected: String_Builder;
    append(*expected, "// juice plugin registration — generated session artifact: regenerated every\n");
    append(*expected, "// run, removed by clean with target/, never edited. Scan order = the\n");
    append(*expected, "// declaration order below (spec §5.2).\n");
    append(*expected, "\n");
    append(*expected, "// Segment 1: the per-name imports, scan order. The module names resolve\n");
    append(*expected, "// through the import directories (the scan's entry probe conventions).\n");
    append(*expected, "\n");
    append(*expected, "// Segment 2: hook assembly — one JUICE_HOOK_<i> entry per scanned plugin\n");
    append(*expected, "// (that plugin's hooks contribution), scan order. The entries are filled\n");
    append(*expected, "// by the assembly below: Jai has no runtime top-level execution, so\n");
    append(*expected, "// \"loading = joining the table\" exists only as generated code executing\n");
    append(*expected, "// explicitly (research A E1/E2, L§5.4).\n");
    append(*expected, "\n");
    append(*expected, "// The assembly: the per-name explicit calls, scan order (registration\n");
    append(*expected, "// order). A top-level procedure call is illegal in Jai (research A\n");
    append(*expected, "// E1/E2/E4), so the calls execute here.\n");
    append(*expected, "get_scanned_plugins :: () -> [..] *Juice_Plugin {\n");
    append(*expected, "    plugins: [..] *Juice_Plugin;\n");
    append(*expected, "    return plugins;\n");
    append(*expected, "}\n");
    append(*expected, "\n");
    append(*expected, "// The hook-entry view of the assembly (scan order) — the segment above\n");
    append(*expected, "// joined into one explicit table.\n");
    append(*expected, "get_scanned_hook_entries :: () -> [..] Lifecycle_Hook {\n");
    append(*expected, "    entries: [..] Lifecycle_Hook;\n");
    append(*expected, "    return entries;\n");
    append(*expected, "}\n");
    expect(generate_plugin_registration(Plugin_Scan_Hit.[]) == builder_to_string(*expected));
}

test "落点：target/plugins/<包名>/registration.jai 与工作区级扁平落点" {
    expect(plugin_registration_path("C:/p/target", "alpha") == "C:/p/target/plugins/alpha/registration.jai");
    // Ticket 043: the workspace-level merged registration file.
    expect(workspace_plugin_registration_path("C:/p/target") == "C:/p/target/plugins/registration.jai");
}

// ===========================================================================
// E2E: the synthetic fixture plugin package, full chain
// ===========================================================================

test "E2E：fixture 插件包全链（扫描→注册文件→真编译→合并执行）" {
    fixture_root := path_slashes(tprint("%1/tests/data/plugin-fixture", otter_root()));

    // The production scan sees exactly the two anchored modules, in walk
    // order (extra.jai before module.jai — files first, lexicographic);
    // the decoy contributes nothing.
    scan := scan_plugin_package(fixture_root);
    expect(scan.ok);
    expect(scan.diagnostics.count == 0);
    expect(scan.hits.count == 2);
    expect(scan.hits[0].module_name == "extra" && scan.hits[0].rel_path == "extra.jai");
    expect(scan.hits[1].module_name == "plugin-fixture" && scan.hits[1].rel_path == "module.jai");

    // The registration file lands under target/ via the production path
    // helper (session artifact — removed with target/ by clean).
    registration_path := plugin_registration_path(otter_target_dir(), "plugin-fixture");
    expect(registration_path == path_slashes(plugin_registration_path(otter_target_dir(), "plugin-fixture")));

    // The full chain child: writes the registration, seeds the face,
    // generates the driver, spawns the real jai compiler. The configs are
    // the fixture's declared plugin ids (the resolver input, ticket 056).
    result, output, errors := run_plugin_scan_child("plugin-fixture", "fixture_mark", Plugin_Config.[
        .{id = "extra", version = "1.0.0"},
        .{id = "plugin-fixture", version = "1.0.0"},
    ]);
    if expect_exit("plugin-scan", result, 0) {
        ok := true;
        // The assembled registry: two plugins; the resolver selects both
        // declared faces — one transpile face (the extra plugin contributes
        // hooks only), two hook registrations, no lint.
        ok &= output_matches("plugin-scan", output, string.[
            "plugins=2",
            "merged-ok=true",
            "merge-diags=0",
            "resolved-ok=true",
            "resolve-diags=0",
            "pipeline=1",
            "pipeline-name=fixture-mark",
            "lint=0",
            "hook-regs=2",
            "hook-entries=2",
            "hook-entry=COMPILE-after",
            "hook-entry=TRANSPILE-before",
            "transpile-diags=0",
            "transpile-view=x := FIXTURE_SEEN;",
            "before-ran=true",
            "before-diag=fixture-before-transpile",
            "after-ran=true",
            "after-diag=extra-after-compile",
        ]);
        expect(ok);
    }
    // The landing file exists with the two segments in scan order.
    expect(file_contains(registration_path, "JUICE_PLUGIN_0 :: #import \"extra\";"));
    expect(file_contains(registration_path, "JUICE_PLUGIN_1 :: #import \"plugin-fixture\";"));
    expect(file_contains(registration_path, "JUICE_HOOK_0: [..] Lifecycle_Hook;"));
    expect(file_contains(registration_path, "JUICE_HOOK_1: [..] Lifecycle_Hook;"));
}

test "E2E：坏 fixture 插件包全链（扫描→注册→合并/解析响亮拒绝）" {
    fixture_root := path_slashes(tprint("%1/tests/data/plugin-fixture-bad", otter_root()));

    // The production scan sees the two anchored modules (extra.jai before
    // module.jai — files first, lexicographic). A bad package scans exactly
    // like a good one; the rejections happen later, at merge and resolve.
    scan := scan_plugin_package(fixture_root);
    expect(scan.ok);
    expect(scan.diagnostics.count == 0);
    expect(scan.hits.count == 2);
    expect(scan.hits[0].module_name == "extra" && scan.hits[0].rel_path == "extra.jai");
    expect(scan.hits[1].module_name == "plugin-fixture-bad" && scan.hits[1].rel_path == "module.jai");

    registration_path := plugin_registration_path(otter_target_dir(), "plugin-fixture-bad");

    // The full chain child: writes the registration, seeds the face,
    // generates the driver, spawns the real jai compiler. The declared id is
    // the duplicate both fixture plugins claim.
    result, output, errors := run_plugin_scan_child("plugin-fixture-bad", "bad_mark", Plugin_Config.[
        .{id = "bad-shared", version = "1.0.0"},
    ]);
    if expect_exit("plugin-scan-bad", result, 0) {
        ok := true;
        // The merge rejects the duplicate id loudly: ok=false, one
        // diagnostic naming the duplicate. The resolver then sees one
        // declared id matching two registry values — the v1 one-package-
        // one-plugin rule — and contributes no faces (ok=false): the
        // pipeline falls back to the default. The product is filled
        // regardless (jaix shape); only ok=false blocks the caller.
        ok &= output_matches("plugin-scan-bad", output, string.[
            "plugins=2",
            "merged-ok=false",
            "merge-diags=1",
            "merge-diag=duplicate plugin registration: bad-shared",
            "resolved-ok=false",
            "resolve-diags=1",
            "resolve-diag=plugin package provides multiple plugins: bad-shared",
            "pipeline=2",
            "pipeline-name=load",
            "pipeline-name=test-block",
        ]);
        // The ambiguous plugin's transpile face never joins the pipeline, so
        // its two-line edit cannot run: the marked source passes through
        // unchanged (the line-fidelity gate's own matrix lives in
        // tests/transpile_plugin_tests.jai).
        ok &= output_matches("plugin-scan-bad", output, string.[
            "transpile-diags=0",
            "transpile-view=x := bad_mark;",
        ]);
        expect(ok);
    }
    // The landing file exists with the two segments in scan order (the
    // bad package's registration file is generated the same way).
    expect(file_contains(registration_path, "JUICE_PLUGIN_0 :: #import \"extra\";"));
    expect(file_contains(registration_path, "JUICE_PLUGIN_1 :: #import \"plugin-fixture-bad\";"));
}
