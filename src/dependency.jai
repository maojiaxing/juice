#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";

// The dependency layer: import shims and workspace dependency preparation
// (spec section 3.3/3.6, old juice dependency.jai semantics). Dependencies
// are consumed only through generated import shims under
// <root>/target/packages — never by linking the source directory (the
// compiler canonicalizes junctions and rejects an import whose name
// mismatches the real directory name, and a directory next to its shim
// collides as "both single-file and directory form"). Every dependency gets
// exactly one shim that #loads the real entry by path.
//
// Closure discipline (spec section 3.6): there is no transitive closure —
// every package declares its full dependency closure explicitly. A workspace
// member is consumed only when a package declares it as a DEP by name; the
// declaration links the member directory directly (member link, never a
// fetch). Relative DEP sources anchor at the process cwd, which is the
// package root (juice never chdirs), so relative sources must point at
// members (which link by name instead) or at root-relative paths.
//
// DEP.name is used verbatim and never validated: a hetero-name DEP
// ({name = "juice_core", source = ...} + #import "juice_core") is the
// official cross-package form. The shim lands under the declared name.
//
// The Package face is consumed through the namespaced Juice binding
// (src/juice_module.jai), as in the workspace/target layers. The dependency
// strip front (shim rewriting for test-bearing closures, ticket 027's b5
// wiring over ticket 026's view layer) lives at the end of this file — the
// build and test commands share it.

Source_Type :: enum {
    LOCAL_PATH;
    GIT_URL;
}

detect_source_type :: (source: string) -> Source_Type {
    if source == "" return .LOCAL_PATH;
    if starts_with(source, "file://") return .LOCAL_PATH;

    git_schemas :: string.[
        "https://", "http://", "git://", "ssh://", "git+https://", "git+ssh://"
    ];
    for schema: git_schemas {
        if starts_with(source, schema) return .GIT_URL;
    }

    if starts_with(source, "git@") && contains(source, ":") return .GIT_URL;
    if ends_with(source, ".git") return .GIT_URL;
    return .LOCAL_PATH;
}

clean_local_path :: (source: string) -> string {
    if starts_with(source, "file://") return advance(source, 7);
    return source;
}

File_Search_Context :: struct {
    target_name: string;
    results:     [..] string;
}

file_search_visitor :: (info: *File_Visit_Info, user_data: *File_Search_Context) {
    if info.short_name == user_data.target_name {
        array_add(*user_data.results, copy_string(info.full_name));
    }
}

find_files_recursive :: (dir: string, filename: string) -> [..] string {
    ctx: File_Search_Context;
    ctx.target_name = filename;
    visit_files(dir, true, *ctx, file_search_visitor, visit_directories = false);
    return ctx.results;
}

// Local dependency directory: <package root>/target/packages/. A pure
// derivation of root_dir; the dependency module owns it uniformly.
packages_dir :: (root_dir: string) -> string {
    return target_packages_dir(package_target_dir(root_dir));
}

// The consuming package's private dependency import directory
// (<package root>/target/imports): the only place this package's dependency
// import names are written, so no sibling package can resolve them.
dependency_imports_dir :: (package_root: string) -> string {
    return target_imports_dir(package_target_dir(package_root));
}

// The package root a resolved plan's target directory belongs to
// (package_target_dir appends exactly one "/target").
package_root_of_target_dir :: (target_dir: string) -> string {
    suffix :: "/target";
    if ends_with(target_dir, suffix) return slice(target_dir, 0, target_dir.count - suffix.count);
    return target_dir;
}

// Import directories every compile gets beyond jai's own defaults: the
// juice module directory (adjacent to the running executable, holds
// Testing.jai/Juice.jai), the compiled package's own module shims and the
// consumer root's dependency shim directory when they exist. Build and test
// share this derivation — the test program's "#import <dependency name>"
// (including workspace members) and "#import <own module name>" resolve
// through the shim directories exactly like a build does.
//
// own_packages_dir is the directory of the compiled package's own declared
// modules (target/packages of that package): importing names are
// package-scoped, so a workspace member's own modules never become another
// package's import names.
compiler_import_directories :: (dependency_import_dir: string, own_packages_dir: string = "") -> [..] string {
    dirs: [..] string;

    global_modules_dir := juice_modules_dir();
    if is_directory(global_modules_dir) array_add(*dirs, global_modules_dir);

    // The package's own import names come before its dependency imports: the
    // package that declares a module name owns it (decision 11).
    if own_packages_dir != "" && !paths_equal(own_packages_dir, dependency_import_dir) && is_directory(own_packages_dir) {
        array_add(*dirs, path_slashes(own_packages_dir));
    }
    if is_directory(dependency_import_dir) {
        array_add(*dirs, path_slashes(dependency_import_dir));
    }
    return dirs;
}

find_package_in_repo :: (cache_dir: string, repo_dir: string, target_pkg_name: string) -> string, bool {
    manifest_files := find_files_recursive(repo_dir, "package.jai");
    defer array_free(manifest_files);

    for manifest_path: manifest_files {
        pkg_dir := get_directory_path(manifest_path);
        pkg, ok := load_package_manifest(cache_dir, pkg_dir);
        if ok && pkg.name == target_pkg_name return pkg_dir, true;
    }
    return "", false;
}

// Consume the discovery snapshot; never re-execute workspace manifests.
resolve_and_fetch_dependencies :: (root_dir: string, cache_dir: string, member_packages: [] Normalized_Package) -> bool {
    return resolve_and_fetch_dependencies_with_modules(root_dir, cache_dir, member_packages, "");
}

resolve_and_fetch_dependencies_with_modules :: (root_dir: string, cache_dir: string, member_packages: [] Normalized_Package, modules_dir: string) -> bool {
    if !make_directory_if_it_does_not_exist(packages_dir(root_dir), recursive = true) return false;
    return fetch_workspace_dependencies(root_dir, cache_dir, member_packages, modules_dir = modules_dir);
}

// A workspace member is consumed through the local dependency directory: the
// declaring package lists it as a dependency, and preparation registers an
// import shim so consumers resolve it with a plain "#import <name>".
link_workspace_member_dependency :: (root_dir: string, member: Normalized_Package) -> bool {
    return ensure_import_shim(packages_dir(root_dir), member.name, member.dir);
}

// One import shim's generated content: a comment line plus a single #load of
// the dependency entry. Single source of the shim format.
dependency_shim_content :: (name: string, entry: string) -> string {
    return tprint("// Generated by juice: import shim for package '%1'.\n#load \"%2\";\n", name, entry);
}

// "#import <name>" below the dependency directory resolves <name>.jai (a
// plain file). We never link the source directory itself: the compiler
// canonicalizes junctions and rejects imports whose name mismatches the real
// directory, and a directory next to its shim collides as "both single-file
// and directory form". So every dependency gets exactly one generated shim
// that loads the real entry by path — any of the three entry layouts
// (module.jai at the root, src/module.jai, or a single <name>.jai file). No
// manifest is required, so plain Jai modules work as dependencies too; a
// directory with none of the layouts writes no shim and leaves resolution to
// the compiler's own error.
ensure_import_shim :: (packages_dir: string, name: string, source_dir: string) -> bool {
    abs_source, ok := normalize_existing_path(source_dir);
    if !ok return false;

    entries :: string.["module.jai", "src/module.jai"];
    for entry: entries {
        candidate := tprint("%1/%2", abs_source, entry);
        if file_exists(candidate) {
            return write_entire_file(tprint("%1/%2.jai", packages_dir, name), dependency_shim_content(name, candidate));
        }
    }

    single_file := tprint("%1/%2.jai", abs_source, name);
    if file_exists(single_file) {
        return write_entire_file(tprint("%1/%2.jai", packages_dir, name), dependency_shim_content(name, single_file));
    }

    // No recognizable layout; leave resolution to the compiler's own error.
    return true;
}

find_workspace_member :: (member_packages: [] Normalized_Package, name: string) -> Normalized_Package, bool {
    for pkg: member_packages {
        if pkg.name == name return pkg, true;
    }
    return .{}, false;
}

fetch_workspace_dependencies :: (
    root_dir: string,
    cache_dir: string,
    member_packages: [] Normalized_Package,
    fetch: #type (root_dir: string, cache_dir: string, dep: Dependency_Reference, modules_dir: string = "") -> bool = fetch_dependency,
    link_member: #type (root_dir: string, member: Normalized_Package) -> bool = link_workspace_member_dependency,
    modules_dir: string = ""
) -> bool {
    for pkg: member_packages {
        for dep: pkg.dependencies {
            if dep.source.kind == .WORKSPACE {
                for selection: dep.modules {
                    workspace_root := root_dir;
                    if member_packages.count > 0 && member_packages[0].dir != "" workspace_root = member_packages[0].dir;
                    expected := lexical_absolute_path(tprint("%/%", workspace_root, selection.path));
                    found := false;
                    for member: member_packages {
                        if !paths_equal(member.dir, expected) continue;
                        found = true;
                        if !link_member(root_dir, member) return false;
                    }
                    if !found { print("[juice ERROR] WORKSPACE source must select a member directory.\n"); return false; }
                }
                if dep.modules_omitted && dep.modules.count == 0 { print("[juice ERROR] WORKSPACE dependency must select a member module in this implementation stage.\n"); return false; }
                continue;
            }
            dependency := dep;
            if dependency.source.kind == .PATH && pkg.dir != "" && !path_is_absolute_portable(dependency.source.path) {
                dependency.source.path = lexical_absolute_path(tprint("%/%", pkg.dir, dependency.source.path));
            }
            if !fetch(root_dir, cache_dir, dependency, modules_dir) {
                print("[juice ERROR] Failed to fetch dependency: %1\n", dep.name);
                return false;
            }
        }
    }
    return true;
}

fetch_dependency :: (root_dir: string, cache_dir: string, dep: Dependency_Reference, modules_dir: string = "") -> bool {
    source_root := "";
    if dep.source.kind == .PATH {
        source_root = dep.source.path;
        // Workspace callers already resolve PATH against the declaring package.
        // root_dir controls output placement, which may be a separate scratch root.
        if !path_is_absolute_portable(source_root) source_root = lexical_absolute_path(source_root);
    } else if dep.source.kind == .GIT {
        selector := dep.source.rev;
        if selector == "" selector = dep.source.tag;
        if selector == "" selector = dep.source.branch;
        source_root = get_git_repo_cache_path(tprint("%/git_repos", cache_dir), dep.source.url, selector);
        if !ensure_git_repo_cloned(dep.source.url, selector, source_root) return false;
    } else {
        print("[juice ERROR] Dependency source requires PATH, GIT or a qualified workspace member.\n");
        return false;
    }
    selections := dep.modules;
    if dep.modules_omitted && selections.count == 0 selections = .[.{}];
    for selection: selections {
        logical := normalize_package_relative_path(selection.path);
        if !logical.success { print("[juice ERROR] Dependency module path escapes its source root.\n"); return false; }
        provider_root := tprint("%/%", source_root, logical.path);
        provider, loaded := load_package_manifest(cache_dir, provider_root, modules_dir);
        if !loaded || !provider.has_package return false;
        products := resolve_product_list(provider, provider.modules, provider.modules_omitted, true);
        if !products.success return false;
        chosen: Effective_Target;
        found := false;
        for product: products.targets {
            if selection.name == "" {
                if products.targets.count != 1 continue;
            } else if !ascii_names_equal(selection.name, product.name) continue;
            chosen = product;
            found = true;
        }
        if !found { print("[juice ERROR] Dependency module selection is missing or ambiguous: %\n", dep.name); return false; }
        import_name := ifx selection.alias == "" then chosen.name else selection.alias;
        if !declaration_identifier_is_valid(import_name) return false;
        if !write_entire_file(tprint("%/%.jai", packages_dir(root_dir), import_name), dependency_shim_content(import_name, chosen.source_path)) return false;
    }
    return true;
}

get_directory_path :: (file_path: string) -> string {
    if file_path == "" return "";

    last_slash := -1;
    for i: 0..file_path.count-1 {
        ch := file_path[i];
        if ch == #char "/" || ch == #char "\\" last_slash = i;
    }

    if last_slash == -1 return ".";
    if last_slash == 0 return "/";
    return slice(file_path, 0, last_slash);
}

get_git_repo_cache_path :: (base_dir: string, url: string, version: string) -> string {
    builder: String_Builder;
    for i: 0..url.count-1 {
        ch := url[i];
        if (ch >= #char "a" && ch <= #char "z") ||
           (ch >= #char "A" && ch <= #char "Z") ||
           (ch >= #char "0" && ch <= #char "9") {
            append(*builder, ch);
        } else {
            append(*builder, #char "_");
        }
    }

    if version != "" print_to_builder(*builder, "_%", version);
    sanitized := builder_to_string(*builder);
    return tprint("%1/%2", base_dir, sanitized);
}

ensure_git_repo_cloned :: (url: string, version: string, dst_dir: string) -> bool {
    if file_exists(dst_dir) {
        res_fetch := run_command("git", "-C", dst_dir, "fetch", "--all");
        if res_fetch.exit_code != 0 return false;
    } else {
        res_clone := run_command("git", "clone", url, dst_dir);
        if res_clone.exit_code != 0 return false;
    }

    if version != "" {
        res_checkout := run_command("git", "-C", dst_dir, "checkout", version);
        if res_checkout.exit_code != 0 return false;
    }
    return true;
}

delete_directory_full :: (path: string) -> bool {
    if !file_exists(path) && !path_is_symlink(path) return true;
    #if OS == .WINDOWS {
        // rmdir parses forward-slash path segments as option switches, so the
        // argument must use backslashes throughout.
        res := run_command("cmd", "/c", "rmdir", "/S", "/Q", path_backslashes(path));
        return res.exit_code == 0;
    } else {
        res := run_command("rm", "-rf", path);
        return res.exit_code == 0;
    }
}

// ---------------------------------------------------------------------------
// Dependency strip front (ticket 027, the b5 wiring over ticket 026's view
// layer; old juice prepare_dependency_strip_views semantics — the reference
// face, rewritten not copied): the import shim is the entry into a
// dependency closure — when a consumer references a dependency via
// `#import <name>`, the compiler #loads the dependency's import entry
// directly through the shim under target/packages. Dependency sources with
// inlined test blocks cannot be compiled by jai directly, so this front
// handles each shim: parse the entry path -> probe the entry's literal
// in-package #load closure with the dependency package as root
// (probe_package_closure, lives in src/transpile_front.jai) -> when the
// closure contains test blocks, view the whole closure with STRIP (the
// all-or-nothing semantics), landing under
// target/transpile/deps/<name>/..., and rewrite the shim's #load to the
// entry view. Test-free dependencies get zero transpile and their shims
// stay untouched. Build and Test share this front; test blocks inside
// dependencies are neither discovered nor executed (Test discovery never
// scans dependency packages) — both paths only make them compilable.
// ---------------------------------------------------------------------------

// File name (with extension) of a path; the complement of get_directory_path.
get_filename :: (file_path: string) -> string {
    last_slash := -1;
    for i: 0..file_path.count-1 {
        if file_path[i] == #char "/" || file_path[i] == #char "\\" last_slash = i;
    }
    return slice(file_path, last_slash + 1, file_path.count - last_slash - 1);
}

// Deterministic shim enumeration: every *.jai file directly under the
// dependency directory, minus its extension, in lexicographic order.
Shim_Scan_Context :: struct {
    names: [..] string;
}

shim_scan_visitor :: (info: *File_Visit_Info, ctx: *Shim_Scan_Context) {
    if info.is_directory return;
    if info.short_name.count == 0 || info.short_name[0] == #char "." return;
    if !ends_with(info.short_name, ".jai") return;
    array_add(*ctx.names, copy_string(slice(info.short_name, 0, info.short_name.count - 4)));
}

// Lexicographic order for a string list, in place. One implementation owns the
// insertion sort both the shim enumeration and the resolution source list use,
// so the two enumerations cannot drift apart.
sort_strings_lexicographically :: (names: [] string) {
    for i: 1..names.count-1 {
        if i >= names.count break;
        key := names[i];
        j := i - 1;
        while j >= 0 && compare(names[j], key) > 0 {
            names[j+1] = names[j];
            j -= 1;
        }
        names[j+1] = key;
    }
}

collect_shim_names :: (packages_dir: string) -> [..] string, bool {
    ctx: Shim_Scan_Context;
    visited := visit_files(packages_dir, false, *ctx, shim_scan_visitor, visit_directories = false);
    if !visited return ctx.names, false;
    sort_strings_lexicographically(ctx.names);
    return ctx.names, true;
}

// The #load target literal of a generated import shim: the dependency entry's
// absolute path. Returns false when the shim does not match the generated
// shape (a hand-written shim stays untouched; the compiler's own error
// reports whatever is wrong with it).
shim_load_target :: (source: string) -> string, bool {
    tokens := lex_source(source);
    i := 0;
    while i < tokens.count {
        tok := tokens[i];
        if tok.kind == .DIRECTIVE && token_text(source, tok) == "#load" && i + 2 < tokens.count
            && tokens[i+1].kind == .STRING && token_text(source, tokens[i+2]) == ";" {
            target := tokens[i+1];
            return decode_jai_string(slice(source, target.start + 1, target.end - target.start - 2)), true;
        }
        i += 1;
    }
    return "", false;
}

// The dependency strip front shared by build and test: for every import shim
// in the dependency directory, probe the dependency entry's closure; a
// closure containing test blocks is viewed wholesale and the shim is
// regenerated pointing at the entry's strip view. Test-free dependencies,
// missing entries and hand-written shims stay untouched (zero transpile,
// zero cache; the compiler's own error reports whatever is wrong with
// them). The strip views always use the default pipeline: dependency
// packages' manifests are not retained past preparation, so their closures
// resolve the empty pipeline to the default (spec 0060 decision 6 — today's
// behavior exactly). The per-file transpile step is the built-in
// transpile_build_file: the transpile seam is the TRANSPILE at mount's
// replacement surface at the stage level (ticket 027), not a parameter
// here.
prepare_dependency_strip_views :: (root_dir: string, import_directory: string) -> bool {
    packages := import_directory;
    if !is_directory(packages) return true;

    shims, ok := collect_shim_names(packages);
    if !ok {
        print("[juice ERROR] Could not scan the dependency shim directory: %\n", packages);
        return false;
    }
    for name: shims {
        shim_path := tprint("%1/%2.jai", packages, name);
        source, read_ok := read_entire_file(shim_path);
        if !read_ok continue;
        entry_abs, parsed := shim_load_target(source);
        if !parsed || !path_exists_as_regular_file(entry_abs) continue;

        closure, probe_ok := probe_package_closure(get_directory_path(entry_abs), get_filename(entry_abs));
        if !probe_ok return false;
        if !closure_has_tests(closure) continue;

        state: Strip_View_State;
        state.transpile_dir = transpile_tree_dir(root_dir);
        state.dep_name = name;
        state.layout = .CONTENT_ADDRESSED;
        state.closure = closure;
        state.transpile = transpile_build_file;
        for _: closure {
            array_add(*state.states, 0);
            array_add(*state.view_paths, "");
        }
        entry_view, view_ok := view_of_file(*state, 0);   // DFS preorder: entry first
        if !view_ok return false;

        if !write_entire_file(shim_path, dependency_shim_content(name, entry_view)) {
            print("[juice ERROR] Could not rewrite import shim for dependency '%'.\n", name);
            return false;
        }
    }
    return true;
}
