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
// ticket 056 made it declaration-driven, and ticket 0092 replaced the member
// name guess with independent typed sources (spec 0087 decisions 21/23).
// scan_workspace_plugins consumes the discovery snapshot (Workspace_Discovery)
// and the consuming package's Package.plugins declarations: built-in ids are
// skipped, and every other declaration resolves its OWN PATH / GIT / WORKSPACE
// source plus a public-module selection through resolve_plugin_sources — no
// ordinary dependency and no member-name guess is involved, so a provider may
// be any reachable package. The selected module must carry exactly one plugin
// entry (zero = capability missing, several = ambiguity), the same actual
// plugin must not be enabled twice, and no selected module may already be an
// ordinary dependency module. Each enablement is linked through one import shim
// named after its DECLARATION id, so the registration and the generated test
// metaprogram can `#import "<id>"`; the entry file's own name never becomes an
// import name. Root dependencies never activate plugins. Every failure is a
// fatal diagnostic + ok = false (the loud channel), and the merged registration
// file lands at <target_dir>/plugins/registration.jai
// (workspace_plugin_registration_path; the per-package helper stays).
//
// The per-package scan (scan_plugin_package) stays as the package-level probe the
// E2E fixtures and the read-failure channel use; its entry-probe naming
// (plugin_module_name / plugin_probe_rank) is that face's own convention and is
// no longer how a declared plugin gets its import name.
//
// Load order: the workspace-level function references Workspace_Discovery
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

// One discovered plugin module. `module_name` is the #import name the
// registration file writes: the DECLARATION id for a declared external plugin
// ([..] from resolve_plugin_sources), the entry probe's derivation for the
// per-package scan. `rel_path` is the entry file relative to the package that
// owns it (the scanned package, or the enabled provider package) and
// `abs_path` its machine path — a report name and a read path, never swapped.
Plugin_Scan_Hit :: struct {
    module_name: string;  // the #import name in the generated registration
                          // file
    rel_path:    string;  // package-relative path ("/" separated)
    abs_path:    string;
}

// One scan-side report: a non-fatal dropped duplicate (the per-package scan's
// probe arbitration), a source file that could not be read, or a
// declaration-level failure of a plugin enablement (unusable source, provider
// without a declaration, ambiguous or missing module export, zero/multiple
// plugin entries in the selected module, the same plugin enabled twice, a
// module already selected as an ordinary dependency). A dropped duplicate is
// non-fatal (ok stays true); every other report is fatal (fatal = true,
// ok = false — a broken plugin declaration/package must fail the command, never
// degrade into "no plugins"). The walk failure stays the ok=false channel
// without a diagnostic — the collect_scan_files convention.
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
// dropped with a diagnostic.
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

// ---------------------------------------------------------------------------
// Independent plugin sources (ticket 0092, spec 0087 decisions 21/23)
// ---------------------------------------------------------------------------

// One plugin source request: the discovery snapshot (workspace root + members),
// the consuming package whose `plugins` list is being resolved, and the
// resolution environment (Git record reuse / offline / update mode) the typed
// source selection reuses from ticket 0091.
Plugin_Source_Request :: struct {
    discovery:   Workspace_Discovery;
    consumer:    Normalized_Package;
    environment: Resolution_Environment;
}

// One enabled external plugin: the resolved provider package, the public
// module the declaration selected (the plugin entry lives there), the module's
// entry file and the import name the registration file binds. `identity` is the
// ACTUAL identity (source + resolved commit + provider directory + export) the
// duplicate rule compares — different names, spellings or option rows never
// bypass it (spec 0087 decision 21). `anchor_rel_path` stays the
// provider-package-relative entry path a scan hit reports (a machine path is
// never a report name).
Resolved_Plugin_Source :: struct {
    id:                string;
    declaration_index: int;
    package_dir:       string;
    module_export:     string;
    entry_path:        string;
    import_name:       string;
    identity:          string;
    anchor_rel_path:   string;
}

// The plugin-source resolution product. ok=false means the command must stop
// before any hook runs; the diagnostics keep declaration order.
Plugin_Source_Resolution :: struct {
    sources:     [..] Resolved_Plugin_Source;
    diagnostics: [..] Plugin_Scan_Diagnostic;
    ok:          bool;
}

// The actual identity of one plugin module: `source key | commit | provider dir
// | export name`. Two enablements agreeing on all four are one plugin.
plugin_source_identity :: (commit: string, package_dir: string, export_name: string) -> string {
    key := ifx commit == "" then "local" else tprint("commit:%", commit);
    return tprint("%1|%2|%3", key, path_slashes(package_dir), export_name);
}

// One resolved module reference (a plugin enablement or a dependency
// declaration): the provider package directory, the selected public module, its
// entry file, and the identity/commit the source resolution produced.
Reference_Module :: struct {
    ok:          bool;
    error:       string;
    commit:      string;
    provider_dir: string;
    package:     Normalized_Package;
    export_name: string;
    entry_path:  string;
    identity:    string;
}

// Resolve one typed source + module selection to a provider package and one of
// its PUBLIC modules (spec 0087 decisions 9-12 reused verbatim: PATH is
// relative to the declaring package, WORKSPACE resolves inside the workspace
// root and only to members, GIT goes through the shared content cache with
// record reuse). No name guessing: an omitted module name adopts the single
// public export and an ambiguous one fails.
resolve_reference_module :: (
    declaring_dir: string,
    discovery: Workspace_Discovery,
    environment: Resolution_Environment,
    source: Source_Reference,
    selection: Module_Reference
) -> Reference_Module {
    out: Reference_Module;

    source_root := "";
    if source.kind == .PATH {
        if source.path == "" {
            out.error = "path source is empty";
            return out;
        }
        candidate := source.path;
        if !path_is_absolute_portable(candidate) candidate = tprint("%1/%2", declaring_dir, source.path);
        normalized, normalized_ok := normalize_existing_path(candidate);
        if !normalized_ok {
            out.error = tprint("path source could not be normalized: %", source.path);
            return out;
        }
        source_root = normalized;
    } else if source.kind == .WORKSPACE {
        if discovery.root_dir == "" || !discovery.has_workspace {
            out.error = "workspace source needs a workspace declaration";
            return out;
        }
        source_root = path_slashes(discovery.root_dir);
    } else if source.kind == .GIT {
        if source.url == "" {
            out.error = "Git source has an empty URL";
            return out;
        }
        commit := "";
        state := read_resolution_state(resolution_state_file(environment, discovery.root_dir));
        if state.corrupt {
            out.error = state.error;
            return out;
        }
        declaring_key := resolution_declaring_key_git(source.url, "", "");
        recorded := -1;
        if environment.mode != .UPDATE {
            recorded = find_resolved_selection(state, declaring_key, source.url, source.branch, source.tag, source.rev);
        }
        if recorded >= 0 {
            commit = state.selections[recorded].commit;
        } else if environment.mode == .OFFLINE {
            if source.rev != "" && is_full_commit_id(source.rev) commit = source.rev;
            if commit == "" {
                out.error = tprint("offline resolution has no recorded plugin source for %", source.url);
                return out;
            }
        } else {
            resolved, resolution_error := git_resolve_selector(environment, source.url, source.branch, source.tag, source.rev);
            if resolution_error != "" {
                out.error = resolution_error;
                return out;
            }
            commit = resolved;
        }
        content_dir, content_error := git_ensure_content(environment, source.url, commit);
        if content_error != "" {
            out.error = content_error;
            return out;
        }
        out.commit = commit;
        source_root = path_slashes(content_dir);
    } else {
        out.error = "an explicit PATH, GIT or WORKSPACE source is required";
        return out;
    }

    logical := normalize_package_relative_path(selection.path);
    if !logical.success {
        out.error = tprint("module path escapes its source root: %", selection.path);
        return out;
    }
    if source.kind == .WORKSPACE {
        expected := ifx logical.path == "." then source_root else tprint("%1/%2", source_root, logical.path);
        normalized_expected, expected_ok := normalize_existing_path(expected);
        if !expected_ok {
            out.error = tprint("workspace module path does not exist: %", selection.path);
            return out;
        }
        member := false;
        for candidate: discovery.member_packages {
            if paths_equal(candidate.dir, normalized_expected) member = true;
        }
        if !member {
            out.error = tprint("workspace source selects a directory that is not a workspace member: %", selection.path);
            return out;
        }
    }

    provider_spelling := ifx logical.path == "." then source_root else tprint("%1/%2", source_root, logical.path);
    provider_dir, provider_ok := normalize_existing_path(provider_spelling);
    if !provider_ok {
        out.error = tprint("module path could not be normalized: %", selection.path);
        return out;
    }
    if !resolution_path_within(source_root, provider_dir) {
        out.error = tprint("module path escapes its source root: %", selection.path);
        return out;
    }

    // The provider must be a package with a declaration: plugins come from
    // DECLARED public modules, never from an undeclared directory. A workspace
    // member is already normalized by discovery, so its declaration is reused
    // instead of being evaluated again.
    package: Normalized_Package;
    package_ok := false;
    for member: discovery.member_packages {
        if !paths_equal(member.dir, provider_dir) continue;
        package = member;
        package_ok = true;
        break;
    }
    if !package_ok package, package_ok = load_package_manifest(tprint("%1/manifest", package_target_dir(discovery.root_dir)), provider_dir);
    if !package_ok || !package.has_package {
        out.error = tprint("provider package has no declaration: %", path_slashes(provider_dir));
        return out;
    }
    if path_slashes(package.dir) != path_slashes(provider_dir) {
        package.dir = path_slashes(provider_dir);
    }
    out.package = package;
    out.provider_dir = path_slashes(provider_dir);

    exports := resolve_product_list(package, package.modules, package.modules_omitted, true);
    if !exports.success {
        out.error = tprint("provider package products are invalid: %", exports.error);
        return out;
    }
    export, selection_error := resolution_select_export(exports.targets, selection);
    if selection_error != "" {
        out.error = selection_error;
        return out;
    }
    out.export_name = export.name;
    out.entry_path = path_slashes(export.source_path);
    out.identity = plugin_source_identity(out.commit, provider_dir, export.name);
    out.ok = true;
    return out;
}

// Count the plugin entry anchors of the selected public module: its own entry
// file plus every file that entry reaches through literal in-package #load
// edges. The module VALUE is what counts, not the spelling location, so an
// entry that only `#load`s its implementation file carrying the single
// get_juice_plugin is valid. Lexical recognition only (the contract above), so
// the closure need not compile. The second result is the module's closure text
// in probe order, used by the hooks-face probe.
plugin_entry_anchor_count :: (package_root: string, entry_path: string) -> (s64, string, bool) {
    entry_rel := scan_rel_path(entry_path, package_root);
    closure, probe_ok := probe_package_closure(package_root, entry_rel);
    if !probe_ok return 0, "", false;
    count: s64 = 0;
    builder: String_Builder;
    for file: closure {
        source, read_ok := read_entire_file(tprint("%1/%2", package_root, file.file.rel_path));
        if !read_ok return 0, "", false;
        normalized := normalize_view_line_endings(source);
        tokens := lex_source(normalized);
        for i: 0..tokens.count-1 {
            if is_juice_plugin_anchor(normalized, tokens, i) count += 1;
        }
        print_to_builder(*builder, "%\n", normalized);
    }
    return count, builder_to_string(*builder), true;
}

// Whether the consumer's ordinary dependencies already select this exact
// provider module (spec 0087 decision 21: 同一插件模块不得再被本消费包的普通
// dependencies 选择 — one actual module, one role). The dependency declarations
// are resolved through the same typed path, so a different spelling still
// collides while a DIFFERENT export of the same provider stays legal (that is
// how a provider offers an ordinary API beside its plugin module).
plugin_dependency_module_conflict :: (request: Plugin_Source_Request, candidate: Resolved_Plugin_Source) -> string {
    consumer := request.consumer;
    for dependency: consumer.dependencies {
        selections: [..] Module_Reference;
        if dependency.modules_omitted {
            array_add(*selections, Module_Reference.{path = "."});
        } else {
            for module: dependency.modules array_add(*selections, module);
        }
        for selection: selections {
            reference := resolve_reference_module(consumer.dir, request.discovery, request.environment, dependency.source, selection);
            if !reference.ok continue;
            if reference.identity != candidate.identity continue;
            return tprint("plugin module is already selected by the ordinary dependency '%': %", dependency.name, candidate.id);
        }
    }
    return "";
}

// Resolve every external plugin enablement of the consumer package (spec 0087
// decisions 21/23): each declaration independently selects a source, a package
// location and a public module; no ordinary dependency and no member-name
// guess is required. Built-in references are skipped (they resolve in-process).
// Failures (in declaration order) — an unusable source, a provider without a
// declaration, a module selection that names no/several public modules, a
// selected module with zero plugin entries (capability missing), a selected
// module with several (entry ambiguity), the same actual plugin enabled twice,
// and a module the ordinary dependencies already selected.
resolve_plugin_sources :: (request: Plugin_Source_Request) -> Plugin_Source_Resolution {
    out: Plugin_Source_Resolution;
    out.ok = true;

    identities: [..] string;
    identity_ids: [..] string;
    for declaration, declaration_index: request.consumer.plugins {
        if declaration.builtin continue;

        source: Source_Reference;
        source.kind = declaration.source.kind;
        source.path = declaration.source.path;
        source.url = declaration.source.url;
        source.branch = declaration.source.branch;
        source.tag = declaration.source.tag;
        source.rev = declaration.source.rev;

        resolved := resolve_reference_module(request.consumer.dir, request.discovery, request.environment, source, declaration.module);
        if !resolved.ok {
            array_add(*out.diagnostics, .{rel_path = declaration.id, message = tprint("Plugin '%' source: %", declaration.id, resolved.error), fatal = true});
            out.ok = false;
            continue;
        }

        count, _, read_ok := plugin_entry_anchor_count(resolved.provider_dir, resolved.entry_path);
        if !read_ok {
            array_add(*out.diagnostics, .{rel_path = declaration.id, message = tprint("Plugin module source could not be read: %", resolved.entry_path), fatal = true});
            out.ok = false;
            continue;
        }
        if count == 0 {
            array_add(*out.diagnostics, .{rel_path = declaration.id, message = tprint("Plugin capability missing: module '%' of package '%' has no plugin entry", resolved.export_name, resolved.package.name), fatal = true});
            out.ok = false;
            continue;
        }
        if count > 1 {
            array_add(*out.diagnostics, .{rel_path = declaration.id, message = tprint("ambiguous plugin entry: module '%' of package '%' has % entries", resolved.export_name, resolved.package.name, count), fatal = true});
            out.ok = false;
            continue;
        }

        candidate: Resolved_Plugin_Source;
        candidate.id = declaration.id;
        candidate.declaration_index = declaration_index;
        candidate.package_dir = resolved.provider_dir;
        candidate.module_export = resolved.export_name;
        candidate.entry_path = resolved.entry_path;
        candidate.import_name = declaration.id;
        candidate.identity = resolved.identity;
        candidate.anchor_rel_path = scan_rel_path(resolved.entry_path, resolved.provider_dir);

        conflict := "";
        for identity, i: identities {
            if identity != candidate.identity continue;
            conflict = tprint("the same plugin is enabled twice ('%' and '%' select %)", identity_ids[i], declaration.id, candidate.module_export);
        }
        if conflict == "" conflict = plugin_dependency_module_conflict(request, candidate);
        if conflict != "" {
            array_add(*out.diagnostics, .{rel_path = declaration.id, message = conflict, fatal = true});
            out.ok = false;
            continue;
        }

        array_add(*identities, candidate.identity);
        array_add(*identity_ids, candidate.id);
        array_add(*out.sources, candidate);
    }
    return out;
}

// The workspace-level scan: Package.plugins is the only activation surface
// (spec §5.2 design revision 2026-10-21; independent sources since ticket
// 0092). Each declaration names a plugin: built-in ids (load / test-block)
// resolve to the static command registry and are skipped; every other id
// resolves its OWN typed source + public-module selection through
// resolve_plugin_sources — no ordinary dependency and no member-name guess is
// required, and the provider may be any package reachable through a PATH,
// WORKSPACE or GIT source. The selected module must carry exactly one plugin
// entry (zero = capability missing, several = ambiguity) and the same actual
// plugin must not be enabled twice or already be selected as an ordinary
// dependency module.
//
// Each resolved source is linked through one import shim under
// target/packages/<id>.jai, so the registration file and the test
// metaprogram can `#import "<id>"`. Root dependencies never activate plugins
// and are read only for the duplicate-role check.
//
// Failure posture: every failure is a fatal diagnostic + ok=false. The
// remaining declarations are still processed so the reports stay complete;
// consumers must treat the whole result as unusable when ok is false.
scan_workspace_plugins :: (discovery: Workspace_Discovery) -> Plugin_Scan_Result {
    request: Plugin_Source_Request;
    request.discovery = discovery;
    request.consumer = discovery.root_package;
    resolved := resolve_plugin_sources(request);
    return plugin_scan_result_from_sources(discovery, resolved);
}

// The scan result over a resolved source set: the hits (declaration order =
// registration order) plus the member import shims. The hooks-face probe runs
// over each selected module entry, so the command-level prepare spawns the
// PRESTEP host only when a plugin can actually contribute hooks.
plugin_scan_result_from_sources :: (discovery: Workspace_Discovery, resolved: Plugin_Source_Resolution) -> Plugin_Scan_Result {
    result: Plugin_Scan_Result;
    result.ok = resolved.ok;
    for diagnostic: resolved.diagnostics array_add(*result.diagnostics, diagnostic);
    if !resolved.ok return result;

    shim_dir_ready := false;
    for source: resolved.sources {
        // Every enabled external plugin needs the host: only a compiled child
        // can read the module's real values, and the ABI/options check must not
        // depend on whether the entry happens to spell its hooks face
        // (decision 22: unknown or invalid options fail before any hook).
        result.has_hooks = true;

        if !shim_dir_ready {
            shim_dir := packages_dir(discovery.root_dir);
            if !make_directory_if_it_does_not_exist(shim_dir, recursive = true) {
                array_add(*result.diagnostics, .{rel_path = source.id, message = tprint("Could not create the plugin shim directory: %", shim_dir), fatal = true});
                result.ok = false;
                break;
            }
            shim_dir_ready = true;
        }
        shim_path := tprint("%1/%2.jai", packages_dir(discovery.root_dir), source.import_name);
        if !write_entire_file(shim_path, dependency_shim_content(source.import_name, source.entry_path)) {
            array_add(*result.diagnostics, .{rel_path = source.id, message = tprint("Could not link the plugin module: %", source.id), fatal = true});
            result.ok = false;
            break;
        }

        hit: Plugin_Scan_Hit;
        hit.module_name = source.import_name;
        hit.rel_path = source.anchor_rel_path;
        hit.abs_path = source.entry_path;
        array_add(*result.hits, hit);
    }
    return result;
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

// The consuming package's private derived view root:
// <target_dir>/plugins/derived/<package>. Every physical plugin output lands
// here and nowhere else (spec 0087 decision 24: 物理输出限于消费工程私有派生区);
// the source tree and any shared Git checkout stay read-only. Regenerated per
// operation: the prepare clears it before the hooks run, so only this round's
// registrations can be consumed.
package_derived_view_root :: (target_dir: string, package_name: string) -> string {
    name := package_name;
    if name == "" name = "package";
    return path_slashes(tprint("%1/derived/%2", target_plugins_dir(target_dir), name));
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
