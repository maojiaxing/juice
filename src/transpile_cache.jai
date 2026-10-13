// Content-addressed view cache for transpiled products (ticket 0020, ADR
// 0003, issue 0008 resolution 5). Pure key/path computation, no IO: the key
// is a hash of the package-relative path, the source content, the mode
// (build/test) and the juice version, plus the build mode's #load rewrite
// targets. Because a strip view's rewrite strings embed the target views'
// hash directories, the keys form a Merkle chain — a parent's key depends on
// its children's keys and stays deterministically computable in dependency
// order. Views live at <transpile_dir>/<hash>/<rel_path>: the package-relative
// structure is mirrored inside the hash directory so distinct files can never
// collide by name (issue 0007: "src/a/x.jai" vs "src/a_x.jai").

#import "Basic";
#import "Hash";
#import "String";

// Version component of the cache key. Bump whenever the transpiler's output
// contract changes (view layout, driver format); old hash directories are
// abandoned in place and disappear with `clean` (no active cleanup).
JUICE_VERSION :: "0.1.0";

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

// Content-addressed cache key. `load_targets` is the build-mode rewrite table
// (empty for test-mode views and for build-mode files without in-package
// loads). Its `to` strings embed the target views' hash directories, so the
// parent key changes whenever a loaded view's key changes (Merkle chain).
transpile_view_key :: (
    rel_path: string,
    source: string,
    mode: Transpile_Mode,
    load_targets: [] Load_Target,
    version := JUICE_VERSION
) -> string {
    builder: String_Builder;
    print_to_builder(*builder, "%1\0%2\0%3\0%4\0",
        rel_path,
        source,
        ifx mode == .EXPAND then "test" else "build",
        version);
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

// The transpile subtree root: <package root>/target/transpile/. Views, the
// test driver and the test metaprogram products all live under it (Target
// directory, CONTEXT.md). Build and Test derive it from the same package
// root (票 0036：build_transpile_dir/test_transpile_dir 逐字同体，收口于此)。
transpile_tree_dir :: (package_root: string) -> string {
    return tprint("%1/target/transpile", cache_slashes(package_root));
}
