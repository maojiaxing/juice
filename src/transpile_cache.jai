// Content-addressed view cache (ticket 026): pure key/path computation, no
// IO — the key is a hash of the package-relative path, the source content,
// the mode (build/test), the pipeline output contract version, the pipeline
// description (the ordered name+version sequence of the plugins that
// produce the view — a plugin rename, a version bump or a pipeline reorder
// changes the key precisely), the test mode's starting test number, and
// the build mode's #load rewrite targets.
// Because a strip view's rewrite strings embed the target views' hash
// directories, the keys form a Merkle chain — a parent's key depends on its
// children's keys and stays deterministically computable in dependency
// order. Views live at <transpile_dir>/<hash>/<rel_path>: the package-relative
// structure is mirrored inside the hash directory so distinct files can never
// collide by name ("src/a/x.jai" vs "src/a_x.jai").
//
// The pipeline description comes from src/transpile_plugin.jai:
// Transpile_Plugin identity + resolve_pipeline (an empty registry resolves
// to the default pipeline, the same convention the runner applies — a view
// and its key always reflect the same pipeline). An omitted or empty
// pipeline means the default.
//
// Old juice src/transpile_cache.jai semantics (the reference face, rewritten
// not copied). This module is a bootstrap #load target and must stay
// test-free; its unit tests live in tests/transpile_cache_tests.jai (0053
// rule). main.jai stays untouched — the first production consumers are the
// command wiring tickets (027/028).

#import "Basic";
#import "Hash";

// Version component of the cache key: the pipeline output contract version
// (spec 004 decision 19 — old juice's JUICE_VERSION semantic). The name
// JUICE_VERSION stays with the product version constant
// (src/commands/version.jai, ticket 013 — the `juice version` contract);
// this module defines its own contract version, and the two are free to
// diverge: per-plugin output contracts are expressed by the pipeline
// description component (name+version) — a plugin version bump invalidates
// precisely; this constant covers the runner-level contract (view layout,
// driver format, the key's own serialization shape). The "otter-" prefix is
// deliberate: otter keys never share the old juice key space (spec §11.9 —
// no mixing with the existing view trees); old hash directories are
// abandoned in place and disappear with `clean` (no active cleanup). Bump
// the numeric part when that contract changes in a way no plugin version
// expresses.
VIEW_CONTRACT_VERSION :: "otter-0.1.1";

// Normalize backslashes to forward slashes (local to keep this module
// self-contained; the repo-wide helper lives in path_safety.jai).
cache_slashes :: (path: string) -> string {
    result := copy_string(path);
    for i: 0..result.count-1 {
        if result[i] == #char "\\" result[i] = #char "/";
    }
    return result;
}

// FNV-1a 64-bit over the serialized key components, rendered as 16 lowercase
// hex characters.
hash_hex :: (s: string) -> string {
    hash := fnv1a_hash(s.data, s.count);
    out: [16] u8;
    for i: 0..15 {
        nibble := cast(s64) ((hash >> cast(u64) (4 * (15 - i))) & 0xf);
        out[i] = cast(u8) ifx nibble < 10 then #char "0" + nibble else #char "a" + (nibble - 10);
    }
    // to_string views the stack buffer; copy before returning.
    return copy_string(to_string(out.data, 16));
}

// Content-addressed cache key. `load_targets` is the build-mode rewrite
// table (empty for test-mode views and for build-mode files without
// in-package loads). Its `to` strings embed the target views' hash
// directories, so the parent key changes whenever a loaded view's key
// changes (Merkle chain). `pipeline` is the registry that produces the view:
// its description (the ordered name+version sequence, in declaration order)
// joins the key, so a plugin rename, a version bump or a pipeline reorder
// invalidates the view precisely. An omitted or empty pipeline means the
// default pipeline (resolve_pipeline — the runner's own convention), and an
// omitted version means the otter contract version constant. EXPAND views
// also depend on next_test_number: changing an earlier file's test count
// must invalidate later views even when their own source is unchanged.
// STRIP views do not number tests and ignore this component.
transpile_view_key :: (
    rel_path: string,
    source: string,
    mode: Transpile_Mode,
    load_targets: [] Load_Target,
    version := VIEW_CONTRACT_VERSION,
    pipeline: [] Transpile_Plugin = .[],
    next_test_number: s64 = 1
) -> string {
    resolved := resolve_pipeline(pipeline);
    builder: String_Builder;
    print_to_builder(*builder, "%1\0%2\0%3\0%4\0",
        rel_path,
        source,
        ifx mode == .EXPAND then "test" else "build",
        version);
    if mode == .EXPAND {
        print_to_builder(*builder, "%1\0", next_test_number);
    }
    print_to_builder(*builder, "%1\0", resolved.count);
    for plugin: resolved {
        print_to_builder(*builder, "%1\0%2\0", plugin.name, plugin.version);
    }
    print_to_builder(*builder, "%1\0", load_targets.count);
    for target: load_targets {
        print_to_builder(*builder, "%1\0%2\0", target.from, target.to);
    }
    return hash_hex(builder_to_string(*builder));
}

// Hash directory inside the transpile tree: <transpile_dir>/<hash>.
transpile_hash_dir :: (transpile_dir: string, key: string) -> string {
    return tprint("%1/%2", cache_slashes(transpile_dir), key);
}

// Cached view path: <transpile_dir>/<hash>/<rel_path>. The package-relative
// structure is mirrored inside the hash directory so views never collide by
// name ("src/a/x.jai" vs "src/a_x.jai" would collide if flattened).
transpile_view_path :: (transpile_dir: string, key: string, rel_path: string) -> string {
    return tprint("%1/%2/%3", cache_slashes(transpile_dir), key, rel_path);
}

// Dependency strip view path: <transpile_dir>/deps/<name>/<hash>/<rel_path>.
// Dependency closures are viewed into the consumer's transpile tree under a
// per-dependency subtree, so distinct dependencies can never collide by name
// (two deps both holding "src/context.jai" share a key only when their views
// are byte-identical; the subtree keeps their paths distinct either way).
transpile_dependency_view_path :: (transpile_dir: string, key: string, name: string, rel_path: string) -> string {
    return tprint("%1/deps/%2/%3/%4", cache_slashes(transpile_dir), name, key, rel_path);
}

// The transpile subtree root: <package root>/target/transpile/. Views, the
// test driver and the test metaprogram products all live under it (Target
// directory, CONTEXT.md). Build and Test derive it from the same package
// root (old juice's build_transpile_dir/test_transpile_dir were verbatim
// duplicates, consolidated here).
transpile_tree_dir :: (package_root: string) -> string {
    return target_transpile_dir(package_target_dir(package_root));
}
