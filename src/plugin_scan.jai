// Plugin package scan + registration codegen (ticket 025): the third-party
// plugin discovery mechanism (spec §5.2, candidate (c)). The shared
// scan_walk skeleton (ticket 015) walks the plugin package in the
// deterministic DFS lexical order; the lexical anchor recognition finds the
// plugin modules — `get_juice_plugin` declarations carrying the
// @juice_plugin tail note (JUICE_PLUGIN_NOTE in src/plugin.jai is the
// single source of the note text; the juice is_test_anchor technique:
// lexical determination on the token stream, no syntax parsing — note text
// inside strings or comments never surfaces as tokens); the entry probe
// derives each hit's #import name; and the registration codegen emits the
// two-segment registration file (spec §5.2 decision 10):
//
//   JUICE_PLUGIN_<i> :: #import "<module name>";   // segment 1: per-name
//   JUICE_HOOK_<i>: [..] Lifecycle_Hook;           // segment 2: hook
//                                                  //   assembly entries
//   get_scanned_plugins() / get_scanned_hook_entries()  // the assembly
//
// The scan order IS the registration order (spec §5.2): walk order feeds
// the generated declaration order feeds the merge order. The generated file
// lands under target/ (a session artifact: regenerated every run, removed
// by clean with the whole target tree, never checked in, never part of the
// bootstrap #load set) — plugin_registration_path derives the landing path.
//
// Entry probe (spec §5.2): module.jai → src/module.jai → <name>.jai. The
// probe determines the #import name the generated file writes:
// - <root>/module.jai     -> the package directory name (member identity,
//   C§7.3's #import-by-name convention);
// - <root>/src/module.jai -> "<dir>/src";
// - any other file        -> its package-relative path minus ".jai"
//   (path-scoped — sub/extra.jai -> "sub/extra"; at the root this is the
//   file stem, the <name>.jai convention). Slash module names resolve
//   through the import directories (spike-pinned); the package root itself
//   is one of the import directories the consumer passes.
// Two hits deriving the same module name are resolved by probe precedence
// (lower rank wins; equal ranks: the earlier hit in scan order wins) — the
// loser is dropped with a diagnostic, keeping the registration list
// deterministic. Module names never need escaping: they derive from
// directory/file names, and quote characters cannot appear in a Windows
// file name.
//
// Jai has no runtime top-level execution (research A E1/E2/E4 — top-level
// calls and call-bearing initializers are compile errors), so "loading =
// joining the table" exists only as generated code executing explicitly:
// the generated file binds the module names as compile-time constants and
// executes the per-name get_juice_plugin() calls inside the assembly
// procedure (the Metaprogram_Plugins per-name codegen shape — its calls run
// inside a procedure body for the same reason). The generated file's types
// (Juice_Plugin, Lifecycle_Hook, as_plugin) come from the consumer's scope:
// the consumer loads the registration file into a scope where the plugin
// face is visible — the published juice_core module (target/modules, landed
// by the build publish step; the E2E publishes it through the same
// generators). Either way the consumer's scope and the plugin modules'
// scopes must share ONE name-imported module:
// #load-ing the same face file into two scopes would create incompatible
// duplicate types (spike-pinned).
//
// Ticket 043 added the workspace-level stage on top of the per-package scan;
// ticket 056 makes it declaration-driven. scan_workspace_plugins consumes
// the discovery snapshot (Juice.Workspace_Discovery) and the root package's
// Package.plugins declarations: built-in ids are skipped, every other id
// must name a workspace member (member plugin id = package name), and each
// declared member is scanned with scan_plugin_package in declaration order.
// The declared member gets its import shim through the ordinary member link
// (ensure_import_shim), so its module name resolves for the generated
// registration / test metaprogram; root dependencies never activate
// plugins. Cross-package same-module-name collisions resolve by the same
// probe precedence (a later winner replaces the earlier hit at its own
// declaration position) and are reported as non-fatal diagnostics. An
// unknown id, a member with zero or several plugin anchors, and any
// unscannable member root (an unreadable source file included, US 27) leave
// ok = false (the loud failure channel), and the merged registration file
// lands at <target_dir>/plugins/registration.jai
// (workspace_plugin_registration_path; the per-package helper stays).
//
// Load order: the workspace-level function references Juice.Workspace_Discovery
// (the namespaced binding declared in src/juice_module.jai) and
// find_workspace_member (src/dependency.jai) — a program that #loads this
// file must load juice_module.jai and dependency.jai first. The file's older
// program-scope references (plugin.jai's anchor note, scan_walk, the
// transpile lexer) make the safe closure position late in the src list —
// ticket 045 places the #load after test_runner.jai. The test program's
// full-package lexical order satisfies the requirement today.
//
// This module is a bootstrap #load target and must stay test-free; its
// tests live in tests/plugin_scan_tests.jai (0053 rule). main.jai stays
// untouched — the first production consumer is ticket 027.

#import "Basic";
#import "File";
#import "String";

// ---------------------------------------------------------------------------
// Scan result shapes
// ---------------------------------------------------------------------------

// One discovered plugin module: the #import name the registration file
// writes (the entry probe's derivation) plus the anchored file's paths.
Plugin_Scan_Hit :: struct {
    module_name: string;  // the #import name in the generated registration
                          // file
    rel_path:    string;  // package-relative path ("/" separated)
    abs_path:    string;
}

// One scan-side report: a dropped duplicate registration, a source file
// that could not be read, or a declaration-level failure (unknown plugin
// id, a member without/multiple plugin anchors, an unlinkable member). A
// dropped duplicate is non-fatal (ok stays true); every other report is
// fatal (fatal = true, ok = false — a broken plugin declaration/package
// must fail the command, never degrade into "no plugins"). The walk failure
// stays the ok=false channel without a diagnostic — the collect_scan_files
// convention.
Plugin_Scan_Diagnostic :: struct {
    rel_path: string;  // the dropped or unreadable file (or the declared id
                       // for declaration-level reports)
    message:  string;
    fatal:    bool;    // true = the report fails the whole scan (ok=false)
}

Plugin_Scan_Result :: struct {
    hits:        [..] Plugin_Scan_Hit;         // scan order = registration
                                               // order
    diagnostics: [..] Plugin_Scan_Diagnostic;  // scan-side reports: dropped
                                               // duplicates (non-fatal) and
                                               // unreadable sources (ok=false)
    ok:          bool;                         // scan usable: the walk
                                               // succeeded and every
                                               // candidate source was
                                               // readable (an unscannable
                                               // root is ok=false with no
                                               // hits)
    // Whether any scanned source file mentions the plugin hooks face (the
    // IDENT token "hooks") — the ticket 060 command-level prepare's
    // conservative host trigger. The parent process cannot load a member
    // plugin's value without the host, so this lexical probe decides whether
    // spawning one could possibly be useful: a plugin contributing hooks
    // necessarily references its `plugin.hooks` contribution somewhere in
    // the package sources (the value construction may live in a helper file,
    // so the whole package is probed). A false positive only spawns a host
    // that resolves no PRESTEP hooks and reports OK; a false negative is
    // impossible for a plugin that spells its hooks face. Over-approximation
    // never affects correctness — the host always executes the real values.
    has_hooks:   bool;
}

// ---------------------------------------------------------------------------
// The scan
// ---------------------------------------------------------------------------

// The scan wrapper's context: the scan root plus the package name (the
// package directory name — the identity the entry probe derives module
// names from).
Plugin_Scan_Context :: struct {
    root:     string;
    pkg_name: string;
}

// The scan root's directory name (the package identity). path_strip_filename
// keeps the trailing separator (String module semantics), so the name is
// the root's tail after it.
package_dir_name :: (root: string) -> string {
    parent := path_strip_filename(root);
    return slice(root, parent.count, root.count - parent.count);
}

// Directory-side exclusions: dot entries at any depth; the root-level
// target/ (managed products — the test collection posture); links of any
// kind (junctions surface as plain directories to visit_files, so they are
// inspected explicitly, the path_safety posture).
plugin_scan_directory_is_excluded :: (info: *File_Visit_Info, collect: *Plugin_Scan_Context) -> bool {
    if info.short_name.count > 0 && info.short_name[0] == #char "." return true;
    rel := scan_rel_path(info.full_name, collect.root);
    if paths_equal(rel, "target") return true;
    entry := inspect_path_entry(info.full_name);
    return entry.is_symlink || entry.is_junction;
}

// File-side exclusions: dot entries at any depth; non-.jai extensions.
plugin_scan_file_is_excluded :: (info: *File_Visit_Info, collect: *Plugin_Scan_Context) -> bool {
    if info.short_name.count > 0 && info.short_name[0] == #char "." return true;
    if !ends_with(info.short_name, ".jai") return true;
    return false;
}

// The plugin package scan: the shared walk (deterministic DFS lexical
// order) under the plugin exclusion predicates, then the lexical anchor
// recognition per file in scan order. Every anchored declaration is a hit;
// same-name hits resolve by probe precedence (see the module header). An
// unreadable source file is reported as a diagnostic and fails the result
// (ok = false, US 27) while the remaining files still scan — the caller must
// treat the whole result as unusable, but the reports stay complete (the
// workspace scan's failure posture).
scan_plugin_package :: (root: string) -> Plugin_Scan_Result {
    result: Plugin_Scan_Result;
    collect: Plugin_Scan_Context;
    collect.root = path_slashes(root);
    while collect.root.count > 0 && collect.root[collect.root.count - 1] == #char "/" collect.root.count -= 1;
    collect.pkg_name = package_dir_name(collect.root);
    files, ok := collect_scan_files(collect.root, *collect, plugin_scan_directory_is_excluded, plugin_scan_file_is_excluded);
    if !ok return result;
    result.ok = true;

    for file: files {
        source, read_ok := read_entire_file(file.abs_path);
        if !read_ok {
            // A read failure is loud: keep the report, fail the whole scan
            // result (US 27), and keep scanning so the reports stay complete.
            array_add(*result.diagnostics, .{rel_path = file.rel_path, message = "could not read plugin source", fatal = true});
            result.ok = false;
            continue;
        }
        s := normalize_view_line_endings(source);
        tokens := lex_source(s);
        i := 0;
        while i < tokens.count {
            // The hooks-face probe (ticket 060): one IDENT token named
            // "hooks" anywhere in the package marks the scan result — the
            // prepare's conservative host trigger (see Plugin_Scan_Result).
            if tokens[i].kind == .IDENT && token_text(s, tokens[i]) == "hooks" result.has_hooks = true;
            if is_juice_plugin_anchor(s, tokens, i) {
                hit: Plugin_Scan_Hit;
                hit.module_name = plugin_module_name(file.rel_path, collect.pkg_name);
                hit.rel_path = file.rel_path;
                hit.abs_path = file.abs_path;
                place_scan_hit(*result, hit);
            }
            i += 1;
        }
    }
    return result;
}

// Add a hit to a per-package scan result, resolving a same-module-name
// collision by probe precedence (lower rank wins; equal ranks: the earlier
// hit in scan order wins — the entry probe order, spec §5.2). The loser is
// dropped with a diagnostic. The workspace-level merge does not reuse this
// in-place replacement: it must keep each package's segment in DEP order
// (place_workspace_scan_hit).
place_scan_hit :: (result: *Plugin_Scan_Result, hit: Plugin_Scan_Hit) {
    for h, i: result.hits {
        if h.module_name != hit.module_name continue;
        existing_rank := plugin_probe_rank(h.rel_path);
        new_rank := plugin_probe_rank(hit.rel_path);
        if existing_rank <= new_rank {
            array_add(*result.diagnostics, .{rel_path = hit.rel_path, message = tprint("duplicate plugin module name % (dropped %)", hit.module_name, hit.rel_path)});
        } else {
            array_add(*result.diagnostics, .{rel_path = h.rel_path, message = tprint("duplicate plugin module name % (dropped %)", h.module_name, h.rel_path)});
            result.hits[i] = hit;
        }
        return;
    }
    array_add(*result.hits, hit);
}

// ---------------------------------------------------------------------------
// Workspace-level scan, declaration-driven (tickets 043/056)
// ---------------------------------------------------------------------------

// The workspace-level scan: Package.plugins is the only activation surface
// (spec §5.2 design revision 2026-10-21). Each declaration names a plugin:
// built-in ids (load / test-block) resolve to the static registry and are
// skipped by the scan; every other id must name a workspace member (member
// plugin id = package name). Declarations are processed in declaration
// order; a declared member package is scanned by scan_plugin_package (the
// deterministic intra-package lexical order) and must provide exactly one
// anchored plugin (the v1 one-plugin-per-package rule). The declared member
// is linked through the ordinary member import shim
// (link_workspace_member_dependency -> ensure_import_shim), so the
// registration file and the test metaprogram can `#import "<member name>"`
// — the member link the retired root-DEP activation used to provide. Root
// dependencies never activate plugins and are not read here.
//
// Failure posture: an unknown id (not a built-in and not a workspace
// member), a declared member providing zero or several plugins, an
// unscannable member root (walk failure or unreadable source) and a failed
// member link are all loud failures — fatal diagnostic + ok=false. The
// remaining declarations are still processed so the reports stay complete;
// consumers must treat the whole result as unusable when ok is false.
scan_workspace_plugins :: (discovery: Juice.Workspace_Discovery) -> Plugin_Scan_Result {
    result: Plugin_Scan_Result;
    result.ok = true;
    shim_dir_ready := false;

    for decl: discovery.root_package.plugins {
        // Built-in ids resolve to the command registry (this process already
        // holds those values): load / test-block. Nothing to scan or link.
        if is_command_static_plugin_id(decl.id) continue;

        // Member plugin id = member package name (v1 rule). An id that names
        // no member is an unknown plugin — loud failure.
        member, is_member := find_workspace_member(discovery.member_packages, decl.id);
        if !is_member {
            array_add(*result.diagnostics, .{rel_path = decl.id, message = tprint("Unknown plugin id: %", decl.id), fatal = true});
            result.ok = false;
            continue;
        }

        member_scan := scan_plugin_package(member.dir);
        for diagnostic: member_scan.diagnostics array_add(*result.diagnostics, diagnostic);
        if !member_scan.ok {
            // Unscannable root or unreadable source (US 27): the reports are
            // already copied; the result is unusable. No hit is added.
            result.ok = false;
            continue;
        }
        if member_scan.hits.count == 0 {
            array_add(*result.diagnostics, .{rel_path = decl.id, message = tprint("Member package provides no plugin: %", decl.id), fatal = true});
            result.ok = false;
            continue;
        }
        if member_scan.hits.count > 1 {
            array_add(*result.diagnostics, .{rel_path = decl.id, message = tprint("Member package provides multiple plugins: %", decl.id), fatal = true});
            result.ok = false;
            continue;
        }
        // The scanned package's hooks-face probe joins the workspace result:
        // the command-level prepare spawns the PRESTEP host only when some
        // declared member could contribute hooks (ticket 060).
        if member_scan.has_hooks result.has_hooks = true;

        // The declared member is linked through the ordinary member import
        // shim (reuse the member link; the binding dir is created lazily).
        if !shim_dir_ready {
            shim_dir := packages_dir(discovery.root_dir);
            if !make_directory_if_it_does_not_exist(shim_dir, recursive = true) {
                array_add(*result.diagnostics, .{rel_path = decl.id, message = tprint("Could not create the plugin shim directory: %", shim_dir), fatal = true});
                result.ok = false;
                continue;
            }
            shim_dir_ready = true;
        }
        if !link_workspace_member_dependency(discovery.root_dir, member) {
            array_add(*result.diagnostics, .{rel_path = decl.id, message = tprint("Could not link member plugin package: %", decl.id), fatal = true});
            result.ok = false;
            continue;
        }

        place_workspace_scan_hit(*result, member_scan.hits[0]);
    }
    return result;
}

// Add one member-package hit to the workspace-level accumulation. A
// same-module collision keeps the lower probe rank; equal ranks keep the
// earlier hit in accumulation order (the earlier declaration). A later
// winner is removed from its earlier slot and appended — its own declaration
// position. The loser is dropped with the in-package diagnostic shape
// (non-fatal). Since the declaration-driven scan processes one hit per
// declared member, cross-package collisions are the only remaining case.
place_workspace_scan_hit :: (result: *Plugin_Scan_Result, hit: Plugin_Scan_Hit) {
    for h, i: result.hits {
        if h.module_name != hit.module_name continue;
        existing_rank := plugin_probe_rank(h.rel_path);
        new_rank := plugin_probe_rank(hit.rel_path);
        if existing_rank <= new_rank {
            array_add(*result.diagnostics, .{rel_path = hit.rel_path, message = tprint("duplicate plugin module name % (dropped %)", hit.module_name, hit.rel_path)});
        } else {
            array_add(*result.diagnostics, .{rel_path = h.rel_path, message = tprint("duplicate plugin module name % (dropped %)", h.module_name, h.rel_path)});
            array_ordered_remove_by_index(*result.hits, i);
            array_add(*result.hits, hit);
        }
        return;
    }
    array_add(*result.hits, hit);
}

// ---------------------------------------------------------------------------
// Lexical anchor recognition
// ---------------------------------------------------------------------------

// The ident part of the plugin note ("@juice_plugin" minus the "@") —
// derived from JUICE_PLUGIN_NOTE (src/plugin.jai), the single source of the
// note text, so the scan follows any future note-text change.
plugin_note_ident :: () -> string {
    return slice(JUICE_PLUGIN_NOTE, 1, JUICE_PLUGIN_NOTE.count - 1);
}

// Statement position for the anchor: the previous significant token is ";",
// "}", "{" or absent. Note groups (@ident ...) after a declaration are
// skipped backward — a noted declaration before the anchor must not hide
// the statement boundary.
anchor_statement_position :: (s: string, tokens: [] Token, index: s64) -> bool {
    j := index - 1;
    while j >= 1 && tokens[j - 1].kind == .PUNCT && token_text(s, tokens[j - 1]) == "@" {
        j -= 2;
    }
    if j < 0 return true;
    text := token_text(s, tokens[j]);
    return text == ";" || text == "}" || text == "{";
}

// The lexical anchor: a get_juice_plugin declaration (IDENT
// "get_juice_plugin" + "::") at statement position whose tail note is the
// plugin note. The determination is lexical on the token stream (the
// is_test_anchor technique — no syntax parsing): strings and comments were
// consumed by the lexer, so note text inside them never surfaces as tokens;
// the note search is confined to the declaration's own tail (after the
// body's matching closing brace, or after the terminating semicolon of a
// body-less declaration), so notes on other declarations never attach.
is_juice_plugin_anchor :: (s: string, tokens: [] Token, index: s64) -> bool {
    if index + 1 >= tokens.count return false;
    if tokens[index].kind != .IDENT || token_text(s, tokens[index]) != "get_juice_plugin" return false;
    if tokens[index + 1].kind != .PUNCT || token_text(s, tokens[index + 1]) != "::" return false;
    if !anchor_statement_position(s, tokens, index) return false;

    // The declaration's end: the matching close of the body brace, or the
    // first ";" (a body-less declaration — the note still attaches at the
    // tail).
    end := -1;
    j := index + 2;
    while j < tokens.count {
        text := token_text(s, tokens[j]);
        if tokens[j].kind == .PUNCT && text == "{" {
            close, found := find_matching_close(s, tokens, j);
            if !found return false;
            end = close;
            break;
        }
        if tokens[j].kind == .PUNCT && text == ";" {
            end = j;
            break;
        }
        j += 1;
    }
    if end < 0 return false;

    // The tail: a chain of notes may precede the plugin note (@a @b
    // @juice_plugin); the plugin note must hang on this declaration.
    k := end + 1;
    while k + 1 < tokens.count && tokens[k].kind == .PUNCT && token_text(s, tokens[k]) == "@" {
        if tokens[k + 1].kind == .IDENT && token_text(s, tokens[k + 1]) == plugin_note_ident() return true;
        k += 2;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Entry probe: module names and precedence
// ---------------------------------------------------------------------------

// The entry probe's #import-name derivation (spec §5.2): module.jai at the
// package root carries the package directory name (member identity);
// src/module.jai carries "<dir>/src"; any other file carries its
// package-relative path minus ".jai" (path-scoped — at the root this is
// the file stem). Slash module names resolve through the import
// directories (spike-pinned); the package root itself is one of the import
// directories the consumer passes.
plugin_module_name :: (rel_path: string, pkg_name: string) -> string {
    if rel_path == "module.jai" return pkg_name;
    if rel_path == "src/module.jai" return tprint("%1/src", pkg_name);
    return slice(rel_path, 0, rel_path.count - 4);  // strip ".jai"
}

// The probe precedence: module.jai beats src/module.jai beats any other
// file. Same-name hits keep the lower rank (equal ranks: the earlier hit in
// scan order — the entry probe order, spec §5.2).
plugin_probe_rank :: (rel_path: string) -> s64 {
    if rel_path == "module.jai" return 1;
    if rel_path == "src/module.jai" return 2;
    return 3;
}

// ---------------------------------------------------------------------------
// Registration codegen
// ---------------------------------------------------------------------------

// The registration file's landing path: target/plugins/<package>/
// registration.jai — under target/, so it is a session artifact
// (regenerated every run, removed by clean with the whole target tree,
// never checked in).
plugin_registration_path :: (target_dir: string, package_name: string) -> string {
    return path_slashes(tprint("%1/%2/registration.jai", target_plugins_dir(target_dir), package_name));
}

// The workspace-level merged registration file's landing path:
// <target_dir>/plugins/registration.jai — one file for the whole workspace
// (ticket 043, parent decision 4; regenerated every run, removed by clean
// with the whole target tree, never checked in). The per-package variant
// above stays for the synthetic fixture E2E.
workspace_plugin_registration_path :: (target_dir: string) -> string {
    return path_slashes(tprint("%1/registration.jai", target_plugins_dir(target_dir)));
}

// The two-segment registration file (spec §5.2 decision 10), scan order =
// declaration order. Segment 1 binds each module name as a compile-time
// constant (the per-name import — a top-level call is illegal in Jai, so
// the binding and the call split); segment 2 declares one JUICE_HOOK_<i>
// entry per scanned plugin. The assembly procedure executes the per-name
// get_juice_plugin() calls explicitly in scan order and fills the hook
// entries — generated code executing is the only "load = join the table"
// form (research A E1/E2, L§5.4). get_scanned_hook_entries() joins the
// entries into one explicit scan-order table (read it after
// get_scanned_plugins(), which fills the entries).
generate_plugin_registration :: (hits: [] Plugin_Scan_Hit) -> string {
    builder: String_Builder;
    append(*builder, "// juice plugin registration — generated session artifact: regenerated every\n");
    append(*builder, "// run, removed by clean with target/, never edited. Scan order = the\n");
    append(*builder, "// declaration order below (spec §5.2).\n");
    append(*builder, "\n");
    append(*builder, "// Segment 1: the per-name imports, scan order. The module names resolve\n");
    append(*builder, "// through the import directories (the scan's entry probe conventions).\n");
    for hit, i: hits {
        print_to_builder(*builder, "JUICE_PLUGIN_%1 :: #import \"%2\";\n", i, hit.module_name);
    }
    append(*builder, "\n");
    append(*builder, "// Segment 2: hook assembly — one JUICE_HOOK_<i> entry per scanned plugin\n");
    append(*builder, "// (that plugin's hooks contribution), scan order. The entries are filled\n");
    append(*builder, "// by the assembly below: Jai has no runtime top-level execution, so\n");
    append(*builder, "// \"loading = joining the table\" exists only as generated code executing\n");
    append(*builder, "// explicitly (research A E1/E2, L§5.4).\n");
    for hit, i: hits {
        print_to_builder(*builder, "JUICE_HOOK_%1: [..] Lifecycle_Hook;\n", i);
    }
    append(*builder, "\n");
    append(*builder, "// The assembly: the per-name explicit calls, scan order (registration\n");
    append(*builder, "// order). A top-level procedure call is illegal in Jai (research A\n");
    append(*builder, "// E1/E2/E4), so the calls execute here.\n");
    append(*builder, "get_scanned_plugins :: () -> [..] *Juice_Plugin {\n");
    append(*builder, "    plugins: [..] *Juice_Plugin;\n");
    for hit, i: hits {
        print_to_builder(*builder, "    p_%1 := JUICE_PLUGIN_%1.get_juice_plugin();\n", i);
        print_to_builder(*builder, "    JUICE_HOOK_%1 = p_%1.hooks;\n", i);
        print_to_builder(*builder, "    array_add(*plugins, as_plugin(p_%1));\n", i);
    }
    append(*builder, "    return plugins;\n");
    append(*builder, "}\n");
    append(*builder, "\n");
    append(*builder, "// The hook-entry view of the assembly (scan order) — the segment above\n");
    append(*builder, "// joined into one explicit table.\n");
    append(*builder, "get_scanned_hook_entries :: () -> [..] Lifecycle_Hook {\n");
    append(*builder, "    entries: [..] Lifecycle_Hook;\n");
    for hit, i: hits {
        print_to_builder(*builder, "    for h: JUICE_HOOK_%1 array_add(*entries, h);\n", i);
    }
    append(*builder, "    return entries;\n");
    append(*builder, "}\n");
    return builder_to_string(*builder);
}
