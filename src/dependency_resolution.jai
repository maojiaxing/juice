#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

// Typed dependency resolution (spec 0087 decisions 9-15 and 26). This module
// replaces the single-level, name-driven preparation in dependency.jai for
// production commands; dependency.jai keeps the shim format, the strip front
// and the legacy driver entry points.
//
// A resolution context is one consuming package inside one consumer project:
// the consumer root (the project, and the resolution-state context), the
// declaring package, and an explicit content/state environment plus mode. No
// process-global "current project" is consulted, so two consumers in one
// process keep independent selections (decision 14).
//
// Observable contract:
//   * Sources come only from the declared PATH/GIT/WORKSPACE variant. There is
//     no package-name search, no version-range rule and no same-name member
//     override (decisions 9, 10).
//   * Modules are flat path/name/alias selections. One actual module (provider
//     identity plus export) may be selected once per consumer; a final import
//     name may not shadow the consumer's own modules, another direct import or
//     a standard Jai module (decision 11).
//   * The consumer's own declared modules are import names of that package:
//     its programs and its other modules import them by public name, exactly
//     like a provider uses its siblings. Their shims are package-private (the
//     package's own target/packages), so two packages may declare the same
//     module name and one package's own modules never become another package's
//     import names (stories 37, decision 11).
//   * Providers resolve their own dependencies, may use their own sibling
//     modules, and keep both out of the consumer's direct imports: provider
//     modules carry mangled private names and their sources compile through a
//     consumer-private view (decisions 11, 12, 24). Package cycles fail with
//     the complete chain.
//   * Git selections live in the resolution state keyed by consumer context,
//     declaring package and source selector - never by reference name, alias or
//     module list. Ordinary reuse never contacts the remote; missing content is
//     restored for the recorded commit only; update refreshes the complete
//     graph; offline reuses complete cache/state and accepts a new record only
//     for a full commit id whose content is already present (decisions 13-15).
//   * The complete graph validates before any state is published, and the state
//     file is replaced atomically: a failure keeps the old selections and fails
//     the operation. A later compile failure does not roll anything back.

RESOLUTION_STANDARD_MODULE_NAMES :: string.[
    "Basic", "String", "File", "File_Utilities", "Process", "Compiler", "System",
    "Windows", "Windows_Utf8", "POSIX", "Testing", "Juice", "Math", "Sort",
    "Random", "Thread", "Time", "Hash", "JSON", "SSL", "HTTP", "Socket",
];

// The directories a provider source view never copies: build outputs, Git
// internals and locally generated import shims. `modules` is NOT excluded: a
// declared product entry may live under `modules/` (an S01 review fixture and the
// S16b workspace-root provider both do), and the view must contain every file the
// exported entry's shim will load. Skipping it copied the provider without its
// entry and the compile failed with "Unable to open file ... modules/root.jai".
RESOLUTION_VIEW_EXCLUDED_DIRECTORIES :: string.["target", ".git", ".build"];

Resolved_Node :: struct {
    name:           string;
    dir:            string;
    identity:       string;
    declaring_key:  string;
    reference_name: string;
    parent_index:   int;
    depth:          int;
    source_kind:    Juice.Source_Kind;
    source_url:     string;
    commit:         string;
    boundary_root:  string;
    package:        Normalized_Package;
    exports:        [] Effective_Target;
    visiting:       bool;
    resolved:       bool;
    private_prefix: string;
    view_dir:       string;
}

// One module selection: an edge from the declaring package (owner) to the
// provider package. local_name is the name the declaring package itself uses in
// its sources; import_name is the name its shim carries (a consumer-facing
// alias for direct selections, a mangled private name for provider-internal
// ones).
Resolved_Module :: struct {
    owner_index:      int;
    package_index:    int;
    export_name:      string;
    local_name:       string;
    import_name:      string;
    entry_path:       string;
    reference_name:   string;
    consumer_visible: bool;
}

// A provider's own export materialized under a private name so its sibling
// sources can import each other without exposing the module outward.
Resolved_Private_Module :: struct {
    package_index: int;
    export_name:   string;
    import_name:   string;
    entry_path:    string;
}

Workspace_Membership :: struct {
    boundary_root:    string;
    workspace_root:   string;
    packages:         [] Normalized_Package;
    has_root_package: bool;
    valid:            bool;
    error:            string;
}

// One import shim: the file name the compiler resolves and the entry it loads.
// directory is the shim directory that owns the name, so a resolution writes a
// package's own modules into that package's target/packages and its dependency
// import names into the consumer root's. Names are unique per directory, never
// globally: two packages may each declare a module of the same name.
Import_Shim :: struct {
    directory:   string;
    import_name: string;
    entry_path:  string;
}

Resolution_Graph :: struct {
    success:          bool;
    error:            string;
    consumer_root:    string;
    // The initiating consumer package inside the context. Two members of one
    // workspace are two consumers of a shared provider, so their selections are
    // recorded apart even though one state file holds both.
    consumer_key:     string;
    // The consuming package's private dependency import directory.
    consumer_shim_directory: string;
    consumer_index:   int;
    mode:             Resolution_Mode;
    state:            Resolution_State;
    nodes:            [..] Resolved_Node;
    modules:          [..] Resolved_Module;
    private_modules:  [..] Resolved_Private_Module;
    selections:       [..] Resolved_Selection;
    memberships:      [..] Workspace_Membership;
    consumer_exports: [..] string;
    shims:            [..] Import_Shim;
    // Every directory this resolution owns shims in. Each one is regenerated
    // wholesale, so a removed declaration never leaves a stale shim behind.
    shim_directories: [..] string;
}

resolution_fail :: (graph: *Resolution_Graph, message: string) -> bool {
    graph.success = false;
    graph.error = message;
    return false;
}

resolution_find_node :: (graph: *Resolution_Graph, identity: string) -> int {
    for node, index: graph.nodes {
        if node.identity == identity return index;
    }
    return -1;
}

resolution_sanitized_identifier :: (text: string) -> string {
    builder: String_Builder;
    for byte: text {
        alphanumeric := (byte >= #char "a" && byte <= #char "z") || (byte >= #char "A" && byte <= #char "Z") || (byte >= #char "0" && byte <= #char "9") || byte == #char "_";
        append(*builder, ifx alphanumeric then byte else #char "_");
    }
    return builder_to_string(*builder);
}

resolution_private_module_name :: (node: *Resolved_Node, export_name: string) -> string {
    if node.private_prefix == "" {
        digest := u64_hex(hash_text_fnv1a(node.identity));
        node.private_prefix = tprint("%1__%2", resolution_sanitized_identifier(node.name), slice(digest, 0, 8));
    }
    return tprint("%1__%2", resolution_sanitized_identifier(export_name), node.private_prefix);
}

resolution_standard_module_name :: (name: string) -> bool {
    for standard: RESOLUTION_STANDARD_MODULE_NAMES {
        if ascii_names_equal(standard, name) return true;
    }
    return false;
}

// The parent directory of a consumer root: the local development sibling
// boundary. Decision 12 keeps sibling-directory ability for local references
// while a Git checkout stays a hard boundary.
resolution_sibling_boundary :: (root: string) -> string {
    if root == "" return "";
    slash := find_index_from_right(root, #char "/");
    if slash <= 0 return root;
    parent := slice(root, 0, slash);
    #if OS == .WINDOWS {
        if parent.count == 2 && parent[1] == #char ":" return root;
    }
    return parent;
}

resolution_path_within :: (boundary: string, candidate: string) -> bool {
    if boundary == "" return true;
    if paths_equal(boundary, candidate) return true;
    return path_is_within(boundary, candidate);
}

// Workspace membership visible from a declaring package, bounded by its source
// boundary: a local package may find an ancestor workspace of its own project,
// while a package inside a Git checkout sees only a workspace declared inside
// that same checkout and never borrows the consumer's members (decision 12).
resolution_membership_for :: (graph: *Resolution_Graph, request: Dependency_Preparation_Request, ceiling_root: string, start_dir: string) -> Workspace_Membership {
    for membership: graph.memberships {
        if membership.boundary_root == ceiling_root return membership;
    }
    membership: Workspace_Membership;
    membership.boundary_root = ceiling_root;
    candidate := start_dir;
    while candidate != "" {
        if file_exists(tprint("%/package.jai", candidate)) {
            declaration, loaded := load_package_manifest(request.cache_dir, candidate, request.modules_dir);
            if !loaded {
                membership.error = tprint("Provider declaration is invalid: %", candidate);
                array_add(*graph.memberships, membership);
                return membership;
            }
            if declaration.has_workspace {
                discovery, discovered := discover_workspace(candidate, request.cache_dir, request.modules_dir);
                if !discovered {
                    membership.error = tprint("Provider workspace is invalid: %", candidate);
                    array_add(*graph.memberships, membership);
                    return membership;
                }
                // The declaring package must actually belong to that workspace;
                // a workspace declaration elsewhere in the tree is not enough.
                declaring_is_member := false;
                for member: discovery.member_packages {
                    if paths_equal(member.dir, start_dir) declaring_is_member = true;
                }
                if !declaring_is_member {
                    membership.error = tprint("The declaring package % is not a member of the workspace at %", start_dir, candidate);
                    array_add(*graph.memberships, membership);
                    return membership;
                }
                membership.workspace_root = candidate;
                membership.packages = discovery.member_packages;
                membership.has_root_package = discovery.has_package;
                membership.valid = true;
                array_add(*graph.memberships, membership);
                return membership;
            }
        }
        if ceiling_root != "" {
            if paths_equal(candidate, ceiling_root) || !path_is_within(ceiling_root, candidate) break;
        }
        candidate = workspace_parent_directory(candidate);
    }
    membership.error = tprint("WORKSPACE source requires a workspace member; none is declared within %", ifx ceiling_root == "" then start_dir else ceiling_root);
    array_add(*graph.memberships, membership);
    return membership;
}

resolution_cycle_chain :: (graph: *Resolution_Graph, repeated_index: int, owner_index: int) -> string {
    path: [..] string;
    walker := owner_index;
    while walker >= 0 {
        array_add(*path, graph.nodes[walker].name);
        walker = graph.nodes[walker].parent_index;
    }
    builder: String_Builder;
    index := path.count - 1;
    while index >= 0 {
        print_to_builder(*builder, "% -> ", path[index]);
        index -= 1;
    }
    print_to_builder(*builder, "%", graph.nodes[repeated_index].name);
    return builder_to_string(*builder);
}

// Add (or reuse) one provider package node. Reuse is by source identity: two
// selections of the same package from the same source share one node, and a
// provider still on the resolution stack is a package cycle.
resolution_add_provider :: (graph: *Resolution_Graph, request: Dependency_Preparation_Request, owner_index: int, provider_dir: string, source_kind: Juice.Source_Kind, source_url: string, commit: string, boundary_root: string, reference_name: string) -> int, bool {
    identity := tprint("path:%", provider_dir);
    if source_kind == .GIT identity = tprint("git:%1@%2:%3", source_url, commit, provider_dir);
    existing := resolution_find_node(graph, identity);
    if existing >= 0 {
        if graph.nodes[existing].visiting {
            graph.error = tprint("Dependency package cycle: %", resolution_cycle_chain(graph, existing, owner_index));
            return -1, false;
        }
        return existing, true;
    }
    if !path_exists_as_directory(provider_dir) {
        graph.error = tprint("Dependency provider package is missing: %", provider_dir);
        return -1, false;
    }
    declaration, loaded := load_package_manifest(request.cache_dir, provider_dir, request.modules_dir);
    if !loaded {
        graph.error = tprint("Dependency provider declaration is invalid: %", provider_dir);
        return -1, false;
    }
    if !declaration.has_package {
        graph.error = tprint("Dependency provider has no package declaration: %", provider_dir);
        return -1, false;
    }
    exports := resolve_product_list(declaration, declaration.modules, declaration.modules_omitted, true);
    if !exports.success {
        graph.error = tprint("Dependency provider products are invalid: %", provider_dir);
        return -1, false;
    }

    node: Resolved_Node;
    node.name = declaration.name;
    node.dir = provider_dir;
    node.identity = identity;
    node.reference_name = reference_name;
    node.parent_index = owner_index;
    node.depth = ifx owner_index >= 0 then graph.nodes[owner_index].depth + 1 else 0;
    node.source_kind = source_kind;
    node.source_url = source_url;
    node.commit = commit;
    node.boundary_root = boundary_root;
    node.package = declaration;
    node.exports = exports.targets;
    if source_kind == .GIT {
        node.declaring_key = resolution_scoped_declaring_key(graph, resolution_declaring_key_git(source_url, commit, provider_dir));
    } else {
        // A local provider resolves its own dependencies as that provider.
        node.declaring_key = resolution_scoped_declaring_key(graph, resolution_declaring_key_local(graph.consumer_root, provider_dir));
    }
    node.visiting = true;
    array_add(*graph.nodes, node);
    return graph.nodes.count - 1, true;
}

resolution_module_name_taken :: (graph: *Resolution_Graph, import_name: string) -> bool {
    for module: graph.modules {
        if module.consumer_visible && ascii_names_equal(module.import_name, import_name) return true;
    }
    return false;
}

// The initiating consumer package's identity inside the resolution context, a
// prefix of every declaring key so two members sharing one provider keep
// independent transitive selections (decision 14: the record distinguishes the
// initiating consumer, the declaring package and the selector).
resolution_consumer_key :: (consumer_root: string, consumer_package: Normalized_Package) -> string {
    return resolution_declaring_key_local(consumer_root, consumer_package.dir);
}

resolution_scoped_declaring_key :: (graph: *Resolution_Graph, base_key: string) -> string {
    if graph.consumer_key == "" return base_key;
    return tprint("consumer:%1|%2", graph.consumer_key, base_key);
}

resolution_add_consumer_module :: (graph: *Resolution_Graph, package_index: int, export_name: string, import_name: string, entry_path: string, reference_name: string) -> bool {
    for module: graph.modules {
        if !module.consumer_visible continue;
        if module.package_index == package_index && ascii_names_equal(module.export_name, export_name) {
            graph.error = tprint("Dependency module '%' is selected more than once (reference '%'); one actual module may be selected once per package.", export_name, reference_name);
            return false;
        }
        if ascii_names_equal(module.import_name, import_name) {
            graph.error = tprint("Dependency import name '%' is declared twice (reference '%').", import_name, reference_name);
            return false;
        }
    }
    for own_export: graph.consumer_exports {
        if ascii_names_equal(own_export, import_name) {
            graph.error = tprint("Dependency import name '%' shadows a module of the consuming package.", import_name);
            return false;
        }
    }
    if resolution_standard_module_name(import_name) {
        graph.error = tprint("Dependency import name '%' shadows a standard compiler module.", import_name);
        return false;
    }
    if !declaration_identifier_is_valid(import_name) {
        graph.error = tprint("Dependency import name is not a valid module name: %", import_name);
        return false;
    }
    array_add(*graph.modules, .{
        owner_index      = graph.consumer_index,
        package_index    = package_index,
        export_name      = export_name,
        local_name       = import_name,
        import_name      = import_name,
        entry_path       = entry_path,
        reference_name   = reference_name,
        consumer_visible = true,
    });
    return true;
}

// One provider-internal selection: the provider's own import name is rewritten
// to a mangled private name so the outermost consumer cannot import it. The
// same identity and final-name rules a consumer obeys apply here (decision 11):
// one actual module per owner, one local name per owner, and no local name that
// shadows one of the provider's own exports.
resolution_add_provider_module :: (graph: *Resolution_Graph, owner_index: int, package_index: int, export_name: string, local_name: string, entry_path: string, reference_name: string) -> bool {
    owner := graph.nodes[owner_index];
    for module: graph.modules {
        if module.owner_index != owner_index continue;
        if module.package_index == package_index && ascii_names_equal(module.export_name, export_name) {
            graph.error = tprint("Dependency module '%' is selected more than once by package '%' (reference '%').", export_name, owner.name, reference_name);
            return false;
        }
        if ascii_names_equal(module.local_name, local_name) {
            graph.error = tprint("Dependency import name '%' is declared twice by package '%' (reference '%').", local_name, owner.name, reference_name);
            return false;
        }
    }
    for export: owner.exports {
        if ascii_names_equal(export.name, local_name) {
            graph.error = tprint("Dependency import name '%' shadows a module of package '%' (reference '%').", local_name, owner.name, reference_name);
            return false;
        }
    }
    if !declaration_identifier_is_valid(local_name) {
        graph.error = tprint("Dependency import name is not a valid module name: %", local_name);
        return false;
    }
    private_name := resolution_private_module_name(*graph.nodes[package_index], export_name);
    array_add(*graph.modules, .{
        owner_index      = owner_index,
        package_index    = package_index,
        export_name      = export_name,
        local_name       = local_name,
        import_name      = private_name,
        entry_path       = entry_path,
        reference_name   = reference_name,
        consumer_visible = false,
    });
    return true;
}

resolution_select_export :: (exports: [] Effective_Target, selection: Module_Reference) -> (Effective_Target, string) {
    if selection.name == "" {
        if exports.count == 1 return exports[0], "";
        if exports.count == 0 return .{}, "Provider exposes no modules; name the export explicitly.";
        return .{}, "Module selection is ambiguous; the provider exposes several modules.";
    }
    for export: exports {
        if ascii_names_equal(export.name, selection.name) return export, "";
    }
    return .{}, tprint("Provider does not export module '%'.", selection.name);
}

// Resolve one Git source to a commit plus its content directory, honoring the
// recorded selection unless the mode demands (or forbids) a new resolution.
resolution_resolve_git :: (graph: *Resolution_Graph, request: Dependency_Preparation_Request, declaring_key: string, source: Source_Reference) -> (string, string, string) {
    selector_identity := git_selector_identity(source.branch, source.tag, source.rev);
    recorded := -1;
    if request.environment.mode != .UPDATE {
        recorded = find_resolved_selection(graph.state, declaring_key, source.url, source.branch, source.tag, source.rev);
    }

    commit := "";
    if recorded >= 0 {
        commit = graph.state.selections[recorded].commit;
    } else if request.environment.mode == .OFFLINE {
        // The only record a full commit id may establish without a record: its
        // content is already in the cache. Floating and short selectors are
        // rejected rather than guessed.
        if source.rev != "" && is_full_commit_id(source.rev) {
            checkout := git_content_checkout_directory(request.environment, source.url, source.rev);
            current, current_ok := git_checkout_commit(checkout);
            if current_ok && current == source.rev commit = source.rev;
        }
        if commit == "" {
            return "", "", tprint("Offline resolution has no recorded selection for % (%).", source.url, selector_identity);
        }
    } else {
        resolved, resolution_error := git_resolve_selector(request.environment, source.url, source.branch, source.tag, source.rev);
        if resolution_error != "" return "", "", resolution_error;
        commit = resolved;
    }

    content_dir, content_error := git_ensure_content(request.environment, source.url, commit);
    if content_error != "" return "", "", content_error;
    array_add(*graph.selections, .{
        declaring_key = declaring_key,
        url           = source.url,
        branch        = source.branch,
        tag           = source.tag,
        rev           = source.rev,
        commit        = commit,
    });
    return commit, content_dir, "";
}

// Resolve every dependency reference of one node: source qualification module
// selections and provider recursion. The first violation fails the graph; this
// phase writes nothing.
resolution_resolve_node :: (graph: *Resolution_Graph, request: Dependency_Preparation_Request, node_index: int) -> bool {
    if graph.nodes[node_index].resolved return true;
    node := graph.nodes[node_index];
    for dependency: node.package.dependencies {
        source_root := "";
        source_kind := dependency.source.kind;
        source_url := "";
        commit := "";
        boundary_root := node.boundary_root;
        membership: Workspace_Membership;

        if source_kind == .PATH {
            raw := dependency.source.path;
            if raw == "" return resolution_fail(graph, tprint("Dependency '%' has an empty path source.", dependency.name));
            candidate := raw;
            if !path_is_absolute_portable(candidate) candidate = tprint("%1/%2", node.dir, raw);
            normalized, normalized_ok := normalize_existing_path(candidate);
            if !normalized_ok return resolution_fail(graph, tprint("Dependency '%' path source could not be normalized: %", dependency.name, raw));
            if node.source_kind == .GIT {
                // Inside a Git checkout the edge stays inside that checkout and
                // keeps the repository/commit provenance of the declaring node.
                if !resolution_path_within(node.boundary_root, normalized) {
                    return resolution_fail(graph, tprint("Dependency '%' path source escapes its Git checkout: %", dependency.name, raw));
                }
                source_kind = .GIT;
                source_url = node.source_url;
                commit = node.commit;
            } else {
                // A local PATH is anchored at the declaring package only; there
                // is no consumer-parent ceiling (decision 8).
                boundary_root = graph.consumer_root;
            }
            source_root = normalized;
        } else if source_kind == .GIT {
            if dependency.source.url == "" return resolution_fail(graph, tprint("Dependency '%' has an empty Git URL.", dependency.name));
            resolved_commit, content_dir, git_error := resolution_resolve_git(graph, request, node.declaring_key, dependency.source);
            if git_error != "" return resolution_fail(graph, git_error);
            commit = resolved_commit;
            source_root = content_dir;
            source_url = dependency.source.url;
            boundary_root = content_dir;
        } else if source_kind == .WORKSPACE {
            start := node.dir;
            // A local declaring package may find an ancestor workspace of its own
            // project; a provider inside a Git checkout can only see a workspace
            // inside that checkout.
            membership_ceiling := ifx node.source_kind == .GIT then node.boundary_root else "";
            membership = resolution_membership_for(graph, request, membership_ceiling, start);
            if !membership.valid return resolution_fail(graph, membership.error);
            // WORKSPACE uses the same flat module selection as every other
            // source: an omitted list accepts the root package's sole export,
            // while a pure workspace (no root package) must name a member.
            if dependency.modules_omitted && !membership.has_root_package {
                return resolution_fail(graph, tprint("Dependency '%' WORKSPACE source root has no package; select a member module explicitly.", dependency.name));
            }
            for selection: dependency.modules {
                logical := normalize_package_relative_path(selection.path);
                if !logical.success return resolution_fail(graph, tprint("Dependency '%' WORKSPACE path escapes the workspace: %", dependency.name, selection.path));
                expected := ifx logical.path == "." then membership.workspace_root else tprint("%1/%2", membership.workspace_root, logical.path);
                matched := false;
                for member: membership.packages {
                    if paths_equal(member.dir, expected) matched = true;
                }
                if !matched {
                    return resolution_fail(graph, tprint("Dependency '%' WORKSPACE source selects a directory that is not a workspace member: %", dependency.name, selection.path));
                }
            }
            source_root = membership.workspace_root;
            boundary_root = membership.boundary_root;
        } else {
            return resolution_fail(graph, tprint("Dependency '%' requires an explicit PATH, GIT or WORKSPACE source.", dependency.name));
        }

        selections: [..] Module_Reference;
        if dependency.modules_omitted {
            array_add(*selections, .{path = "."});
        } else {
            if dependency.modules.count == 0 {
                return resolution_fail(graph, tprint("Dependency '%' declares an empty module list; the provider capability does not match.", dependency.name));
            }
            for selection: dependency.modules array_add(*selections, selection);
        }

        for selection: selections {
            logical := normalize_package_relative_path(selection.path);
            if !logical.success {
                return resolution_fail(graph, tprint("Dependency '%' module path escapes its source root: %", dependency.name, selection.path));
            }
            provider_dir := ifx logical.path == "." then source_root else tprint("%1/%2", source_root, logical.path);
            provider_dir_normalized, provider_ok := normalize_existing_path(provider_dir);
            if !provider_ok return resolution_fail(graph, tprint("Dependency '%' module path could not be normalized: %", dependency.name, selection.path));
            if !resolution_path_within(source_root, provider_dir_normalized) {
                return resolution_fail(graph, tprint("Dependency '%' module path escapes its source root: %", dependency.name, selection.path));
            }
            provider_index, added := resolution_add_provider(graph, request, node_index, provider_dir_normalized, source_kind, source_url, commit, boundary_root, dependency.name);
            if !added {
                graph.success = false;
                return false;
            }
            provider := graph.nodes[provider_index];
            export, selection_error := resolution_select_export(provider.exports, selection);
            if selection_error != "" return resolution_fail(graph, tprint("Dependency '%': %", dependency.name, selection_error));
            local_name := ifx selection.alias == "" then export.name else selection.alias;
            // Every selection is recorded, even when the provider node is already
            // resolved: selecting the same actual module twice must still fail.
            if node_index == graph.consumer_index {
                if !resolution_add_consumer_module(graph, provider_index, export.name, local_name, export.source_path, dependency.name) return false;
            } else {
                if !resolution_add_provider_module(graph, node_index, provider_index, export.name, local_name, export.source_path, dependency.name) return false;
            }
            if !graph.nodes[provider_index].resolved {
                if !resolution_resolve_node(graph, request, provider_index) return false;
                graph.nodes[provider_index].visiting = false;
                graph.nodes[provider_index].resolved = true;
            }
            // Recursion may have reallocated the node array; restore this node's
            // working copy so the remaining references see the same values.
            graph.nodes[node_index] = node;
        }
    }
    return true;
}

resolution_register_private_exports :: (graph: *Resolution_Graph) {
    for node, index: graph.nodes {
        if index == graph.consumer_index continue;
        for export: node.exports {
            private_name := resolution_private_module_name(*graph.nodes[index], export.name);
            duplicate := false;
            for existing: graph.private_modules {
                if existing.package_index == index && ascii_names_equal(existing.export_name, export.name) duplicate = true;
            }
            if duplicate continue;
            array_add(*graph.private_modules, .{
                package_index = index,
                export_name   = export.name,
                import_name   = private_name,
                entry_path    = export.source_path,
            });
        }
    }
    // A provider's own import names persist even when the node was resolved
    // before its exports were registered; refresh the prefixes so sibling
    // rewrites and private modules agree.
}

resolution_private_name_for :: (graph: *Resolution_Graph, package_index: int, export_name: string) -> string {
    for module: graph.private_modules {
        if module.package_index == package_index && ascii_names_equal(module.export_name, export_name) return module.import_name;
    }
    return "";
}

// Rewrite #import "<local name>" statements to the resolved private name. Only
// string-literal imports of names the provider itself uses are touched; every
// other line stays byte-identical.
resolution_rewrite_imports :: (source: string, keys: [..] string, values: [..] string) -> (string, int) {
    tokens := lex_source(source);
    builder: String_Builder;
    cursor := 0;
    changes := 0;
    for token, index: tokens {
        if token.kind != .DIRECTIVE continue;
        if token_text(source, token) != "#import" continue;
        if index + 2 >= tokens.count continue;
        string_token := tokens[index + 1];
        semicolon := tokens[index + 2];
        if string_token.kind != .STRING || token_text(source, semicolon) != ";" continue;
        name := decode_jai_string(slice(source, string_token.start + 1, string_token.end - string_token.start - 2));
        replacement := "";
        for key, key_index: keys {
            if ascii_names_equal(key, name) replacement = values[key_index];
        }
        if replacement == "" continue;
        append(*builder, slice(source, cursor, string_token.start - cursor));
        print_to_builder(*builder, "\"%\"", replacement);
        // Token end is one past the closing quote, so the cursor keeps the
        // following `;` in the copied remainder.
        cursor = string_token.end;
        changes += 1;
    }
    if changes == 0 return source, 0;
    append(*builder, slice(source, cursor, source.count - cursor));
    return builder_to_string(*builder), changes;
}

resolution_collect_package_files :: (package_dir: string) -> [..] string, bool {
    Collect :: struct {
        root:  string;
        files: [..] string;
    }
    collect: Collect;
    collect.root = package_dir;
    visitor :: (info: *File_Visit_Info, collect: *Collect) {
        if info.is_directory {
            for excluded: RESOLUTION_VIEW_EXCLUDED_DIRECTORIES {
                if ascii_names_equal(info.short_name, excluded) info.descend_into_directory = false;
            }
            return;
        }
        if !ends_with(info.short_name, ".jai") return;
        array_add(*collect.files, copy_string(info.full_name));
    }
    visited := visit_files(package_dir, true, *collect, visitor, visit_files = true, visit_directories = true, visit_symlinks = false, follow_directory_symlinks = false);
    if !visited return collect.files, false;
    // Stable, deterministic file order: the same lexicographic sort the shim
    // enumeration uses.
    sort_strings_lexicographically(collect.files);
    return collect.files, true;
}

// Build the consumer-private source view for one provider when its sources use
// names that must be rewritten (its own exports or its dependency imports).
// Sources under the shared checkout stay untouched: the view is a copy under
// the consumer's own target/ directory (decision 12).
resolution_create_view :: (graph: *Resolution_Graph, request: Dependency_Preparation_Request, node_index: int) -> (string, bool) {
    node := graph.nodes[node_index];
    keys: [..] string;
    values: [..] string;
    for module: graph.modules {
        if module.owner_index != node_index continue;
        array_add(*keys, module.local_name);
        array_add(*values, module.import_name);
    }
    for export: node.exports {
        private_name := resolution_private_name_for(graph, node_index, export.name);
        if private_name == "" continue;
        array_add(*keys, export.name);
        array_add(*values, private_name);
    }
    if keys.count == 0 return "", true;

    files, collected := resolution_collect_package_files(node.dir);
    if !collected {
        graph.error = tprint("Could not scan the provider sources: %", node.dir);
        return "", false;
    }

    // Probe first: only a provider whose sources actually use a rewritten name
    // needs a private view; everything else compiles its shared sources
    // directly, read-only.
    used := false;
    for file: files {
        source, read_ok := read_entire_file(file);
        if !read_ok {
            graph.error = tprint("Could not read the provider source: %", file);
            return "", false;
        }
        _, changes := resolution_rewrite_imports(source, keys, values);
        if changes > 0 used = true;
    }
    if !used return "", true;

    // Decision 12: the view is the CONSUMER package's private copy, so it lands in
    // that package's own target/ — the same tree its dependency shims use
    // (dependency_imports_dir(consumer_package.dir)). Using the discovery root put
    // a member's view under the workspace root while the shim pointed at the view's
    // path from the provider's side, so path and content disagreed.
    consumer_dir := graph.nodes[graph.consumer_index].dir;
    view_dir := tprint("%1/deps/%2", package_target_dir(consumer_dir), resolution_sanitized_key(node.identity));
    delete_directory_full(view_dir);
    for file: files {
        source, read_ok := read_entire_file(file);
        if !read_ok {
            graph.error = tprint("Could not read the provider source: %", file);
            return "", false;
        }
        rewritten, _ := resolution_rewrite_imports(source, keys, values);
        relative := slice(file, node.dir.count + 1, file.count - node.dir.count - 1);
        destination := tprint("%1/%2", view_dir, relative);
        if !make_directory_if_it_does_not_exist(get_directory_path(destination), recursive = true) {
            graph.error = tprint("Could not create the provider view directory: %", get_directory_path(destination));
            return "", false;
        }
        if !write_entire_file(destination, rewritten) {
            graph.error = tprint("Could not write the provider view file: %", destination);
            return "", false;
        }
    }
    graph.nodes[node_index].view_dir = view_dir;
    return view_dir, true;
}

// The path a shim must load: the provider entry itself, or its private view.
resolution_effective_entry :: (graph: *Resolution_Graph, package_index: int, entry_path: string) -> string {
    node := graph.nodes[package_index];
    if node.view_dir == "" return entry_path;
    if !starts_with(entry_path, node.dir) return entry_path;
    relative := slice(entry_path, node.dir.count + 1, entry_path.count - node.dir.count - 1);
    return tprint("%1/%2", node.view_dir, relative);
}

resolution_add_shim_directory :: (graph: *Resolution_Graph, directory: string) {
    for existing: graph.shim_directories {
        if paths_equal(existing, directory) return;
    }
    array_add(*graph.shim_directories, copy_string(directory));
}

resolution_add_shim :: (graph: *Resolution_Graph, directory: string, import_name: string, entry_path: string) -> bool {
    for shim: graph.shims {
        if !paths_equal(shim.directory, directory) continue;
        if shim.import_name != import_name continue;
        if shim.entry_path == entry_path return true;
        graph.error = tprint("Import name '%' resolves to two different modules.", import_name);
        return false;
    }
    array_add(*graph.shims, .{directory = copy_string(directory), import_name = copy_string(import_name), entry_path = entry_path});
    return true;
}

// The consumer's own modules keep their public names, but their shims are the
// package's own (decision 11): the package that declares the name owns it.
resolution_plan_own_module_shims :: (graph: *Resolution_Graph) -> bool {
    consumer := graph.nodes[graph.consumer_index];
    directory := packages_dir(consumer.dir);
    for export: consumer.exports {
        if !resolution_add_shim(graph, directory, export.name, export.source_path) return false;
    }
    return true;
}

resolution_plan_shims :: (graph: *Resolution_Graph) -> bool {
    if !resolution_plan_own_module_shims(graph) return false;
    // Consumer-visible selections and provider-internal rewrites live in the
    // consuming package's own import directory: its programs, tests, modules
    // and plugin host search that path and no sibling package does.
    directory := graph.consumer_shim_directory;
    if directory == "" return resolution_fail(graph, "The consuming package has no dependency import directory.");
    for module: graph.modules {
        entry := resolution_effective_entry(graph, module.package_index, module.entry_path);
        if !resolution_add_shim(graph, directory, module.import_name, entry) return false;
    }
    for module: graph.private_modules {
        entry := resolution_effective_entry(graph, module.package_index, module.entry_path);
        if !resolution_add_shim(graph, directory, module.import_name, entry) return false;
    }
    return true;
}

// Write the import shims, one directory at a time: every owned directory is
// regenerated so a removed declaration stops resolving (no stale shim
// survives), and each directory carries only the names it owns.
resolution_write_shims :: (graph: *Resolution_Graph) -> bool {
    for directory: graph.shim_directories {
        if !make_directory_if_it_does_not_exist(directory, recursive = true) return false;

        existing, scanned := collect_shim_names(directory);
        if !scanned {
            graph.error = tprint("Could not scan the import shim directory: %", directory);
            return false;
        }
        for name: existing {
            file_delete(tprint("%1/%.jai", directory, name));
        }
        for shim: graph.shims {
            if !paths_equal(shim.directory, directory) continue;
            path := tprint("%1/%.jai", directory, shim.import_name);
            if !write_entire_file(path, dependency_shim_content(shim.import_name, shim.entry_path)) {
                graph.error = tprint("Could not write the dependency import shim: %", path);
                return false;
            }
        }
    }
    return true;
}

// Merge this resolution's records over the context's previous file: records this
// pass re-resolved are replaced, records of other declaring packages are kept so
// a member update cannot erase a sibling member's selections.
resolution_publish_state :: (graph: *Resolution_Graph, request: Dependency_Preparation_Request) -> bool {
    if !resolution_publish_selections(request.environment, graph.consumer_root, graph.selections, graph.state) {
        graph.error = tprint("Could not publish the dependency resolution state for %", graph.consumer_root);
        return false;
    }
    return true;
}

// Merge this pass's records over a previous state file and publish the result:
// records this pass re-resolved are replaced, records of other declaring
// packages are kept so a member update cannot erase a sibling member's
// selections. One merge implementation serves the immediate and the deferred
// publication paths, so a deferred commit cannot quietly drop a sibling's
// record.
resolution_publish_selections :: (
    environment: Resolution_Environment,
    consumer_root: string,
    current_selections: [] Resolved_Selection,
    previous_state: Resolution_State
) -> bool {
    merged: [..] Resolved_Selection;
    for previous: previous_state.selections {
        superseded := false;
        for current: current_selections {
            if previous.declaring_key != current.declaring_key continue;
            if previous.url != current.url || previous.branch != current.branch || previous.tag != current.tag || previous.rev != current.rev continue;
            superseded = true;
        }
        if !superseded array_add(*merged, previous);
    }
    for current: current_selections array_add(*merged, current);
    return publish_resolution_state(environment, consumer_root, merged);
}

resolution_resolve_consumer :: (
    request: Dependency_Preparation_Request,
    consumer_package: Normalized_Package,
    defer_publication := false
) -> Resolution_Graph {
    graph: Resolution_Graph;
    graph.success = true;
    graph.consumer_root = request.discovery.root_dir;
    graph.mode = request.environment.mode;
    graph.consumer_index = 0;
    graph.consumer_key = resolution_consumer_key(graph.consumer_root, consumer_package);
    graph.state = read_resolution_state(resolution_state_file(request.environment, request.discovery.root_dir));
    if graph.state.corrupt {
        graph.success = false;
        graph.error = graph.state.error;
        return graph;
    }

    consumer_exports := resolve_product_list(consumer_package, consumer_package.modules, consumer_package.modules_omitted, true);
    if !consumer_exports.success {
        graph.success = false;
        graph.error = tprint("Package products are invalid: %", consumer_package.name);
        return graph;
    }
    for export: consumer_exports.targets array_add(*graph.consumer_exports, export.name);
    // The dependency import directory is always regenerated; the package's own
    // one only when it declares modules, or when an earlier run left it behind
    // (a declaration that lost its module list must still stop resolving).
    if request.shim_root_override != "" {
        // A provider resolved on a consumer's behalf: one private directory holds
        // this provider's import names, and its own modules stay out of it (the
        // provider's own module is linked by the plugin shim, not by a name here).
        graph.consumer_shim_directory = request.shim_root_override;
    } else {
        graph.consumer_shim_directory = dependency_imports_dir(consumer_package.dir);
        own_directory := packages_dir(consumer_package.dir);
        if consumer_exports.targets.count > 0 || is_directory(own_directory) resolution_add_shim_directory(*graph, own_directory);
    }
    resolution_add_shim_directory(*graph, graph.consumer_shim_directory);

    node: Resolved_Node;
    node.name = consumer_package.name;
    node.dir = consumer_package.dir;
    node.identity = tprint("path:%", consumer_package.dir);
    node.declaring_key = resolution_scoped_declaring_key(*graph, resolution_declaring_key_local(graph.consumer_root, consumer_package.dir));
    node.parent_index = -1;
    node.depth = 0;
    node.source_kind = .PATH;
    node.boundary_root = graph.consumer_root;
    node.package = consumer_package;
    node.exports = consumer_exports.targets;
    node.visiting = true;
    array_add(*graph.nodes, node);

    if !resolution_resolve_node(*graph, request, 0) {
        graph.success = false;
        return graph;
    }
    resolution_register_private_exports(*graph);

    // Views, in provider order, then shims, then state: a failure anywhere keeps
    // the previous state file and fails the operation (decision 15).
    for node, index: graph.nodes {
        if index == graph.consumer_index continue;
        view_dir, view_ok := resolution_create_view(*graph, request, index);
        if !view_ok return graph;
    }
    if !resolution_plan_shims(*graph) {
        graph.success = false;
        return graph;
    }
    if !defer_publication && !resolution_publish_state(*graph, request) {
        graph.success = false;
        return graph;
    }
    graph.success = true;
    return graph;
}

// Production preparation entry (the workspace layer's default seam): resolve the
// default package selection, then each selected package's complete graph. All
// graphs validate before any shim or state is published, so a failure leaves the
// workspace untouched.
resolve_dependencies_for_workspace :: (request: Dependency_Preparation_Request) -> bool {
    return resolve_dependencies_into(request, true, null);
}

// The command-level entry: resolve exactly as production does, but hand the
// merged selections to the caller instead of publishing them, so the command
// can commit after its own validations (decision 15).
resolve_dependencies_deferred :: (request: Dependency_Preparation_Request, pending: *Prepared_Workspace) -> bool {
    return resolve_dependencies_into(request, false, pending);
}

resolve_dependencies_into :: (request: Dependency_Preparation_Request, publish: bool, pending: *Prepared_Workspace) -> bool {
    if request.discovery.root_dir == "" {
        print("[juice ERROR] Dependency resolution requires a discovered workspace.\n");
        return false;
    }
    selection := request.selection;
    if !selection.success {
        selection = select_workspace_packages(request.discovery, request.invocation_dir, .{});
        if !selection.success {
            print("[juice ERROR] %\n", selection.error);
            return false;
        }
    }
    graphs: [..] Resolution_Graph;
    for package: selection.packages {
        graph := resolution_resolve_consumer(request, package, defer_publication = !publish || pending != null);
        if !graph.success {
            print("[juice ERROR] %\n", graph.error);
            return false;
        }
        array_add(*graphs, graph);
    }

    // One shim set serves the selected packages of this command; a name owned
    // by two packages in DIFFERENT directories is two names (own modules are
    // package-scoped), while a name mapped twice inside one directory is a
    // conflict and fails before anything is written.
    combined: Resolution_Graph;
    combined.success = true;
    for *graph: graphs {
        for directory: graph.shim_directories resolution_add_shim_directory(*combined, directory);
        for shim: graph.shims {
            for existing: combined.shims {
                if !paths_equal(existing.directory, shim.directory) continue;
                if ascii_names_equal(existing.import_name, shim.import_name) && existing.entry_path != shim.entry_path {
                    print("[juice ERROR] Selected packages map the import name '%' to two different modules in %.\n", shim.import_name, shim.directory);
                    return false;
                }
            }
            array_add(*combined.shims, shim);
        }
    }
    if !resolution_write_shims(*combined) {
        print("[juice ERROR] %\n", combined.error);
        return false;
    }
    // The caller asked to commit later: hand it the merged selections of every
    // selected package's graph. The command publishes them as one transaction
    // after its own validations (decision 15), so a failing new selection never
    // replaces a working record.
    if pending != null {
        pending.pending_publication = true;
        pending.pending_consumer_root = request.discovery.root_dir;
        pending.pending_environment = request.environment;
        for graph: graphs {
            for selection_record: graph.selections array_add(*pending.pending_selections, selection_record);
        }
    }
    return true;
}

// Import preparation for plugins and later command layers (decision 12): the
// directory that carries one consuming package's private import names. Shared
// provider sources are never modified; every derived view lives under that
// package's own target/.
resolution_import_directories :: (package_root: string) -> [..] string {
    directories: [..] string;
    directory := dependency_imports_dir(package_root);
    if is_directory(directory) array_add(*directories, path_slashes(directory));
    return directories;
}
