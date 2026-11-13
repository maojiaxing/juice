// ---------------------------------------------------------------------------
// View cache tests (ticket 026): the content-addressed key and the path
// helpers (old juice tests/transpile_tests.jai "content-addressed cache pure
// functions" + transpile_plugin_tests.jai "cache-key pipeline description"
// semantics, rewritten not copied). Pinned behavior: the key is a
// deterministic 16-lowercase-hex hash; every component (relative path,
// source, mode, contract version, pipeline description, EXPAND starting test
// number and load rewrite table) participates in it.
// The contract version keeps otter keys out of the old juice key space; the
// path helpers mirror the package-relative structure and keep the dependency
// subtree distinct.
//
// Key constraint (same as the other sibling test files): src modules are
// bootstrap #load targets / entry closure members — test blocks would be
// illegal inside them, so the modules stay test-free and their tests live
// here (tests/), per the test organization rule: referenced by no #load,
// collected into the test program by Test discovery's full-package scan.
// This file contains only test blocks and their helper declarations; zero
// production code coupling. Good-test standard: only external behavior is
// pinned (given inputs -> key / path strings), never the serialization
// internals.
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";

// ===========================================================================
// Key components
// ===========================================================================

// The key is a deterministic 16-hex-char hash; every component (relative
// path, source content, mode, contract version, pipeline description and the
// EXPAND starting test number) participates in it.
test "Cache key is deterministic and component-sensitive" {
    key := transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION);
    expect(key == transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION));
    expect(key.count == 16);
    for ch: key {
        expect(is_hex_digit(ch));
    }
    expect(key != transpile_view_key("src/b.jai", "x := 1;\n", .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION));
    expect(key != transpile_view_key("src/a.jai", "x := 2;\n", .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION));
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .STRIP, Load_Target.[], VIEW_CONTRACT_VERSION));
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], "otter-0.1.2"));
    // A different pipeline description changes the key.
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION, .[test_block_plugin()]));
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION, default_transpile_pipeline(), 2));
    // STRIP views do not number generated tests.
    expect(transpile_view_key("src/a.jai", "x := 1;\n", .STRIP, Load_Target.[], VIEW_CONTRACT_VERSION, .[], 1)
        == transpile_view_key("src/a.jai", "x := 1;\n", .STRIP, Load_Target.[], VIEW_CONTRACT_VERSION, .[], 2));
    // The omitted version defaults to the otter contract version constant;
    // the omitted (or empty) pipeline defaults to the default pipeline
    // description.
    expect(transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[]) == key);
    expect(transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION, default_transpile_pipeline()) == key);
    expect(transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION, Transpile_Plugin.[]) == key);
}

// The otter contract version deliberately separates otter keys from old
// juice keys (spec §11.9 choice): the same inputs with old juice's version
// component never produce the same key, so the two tools never mix their
// view trees when they run over the same package root.
test "Cache key: the otter contract version keeps otter keys out of the old juice key space" {
    expect(VIEW_CONTRACT_VERSION != "0.1.0");
    expect(transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION)
        != transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], "0.1.0"));
}

// Merkle chain: in build mode the load rewrite targets embed the target
// views' hash directories, so a parent's key changes whenever a loaded
// view's key changes — and stays deterministically computable in dependency
// order.
test "Cache key forms a Merkle chain in build mode" {
    child := transpile_view_key("src/b.jai", "b := 1;\n", .STRIP, Load_Target.[], "1");
    child_other := transpile_view_key("src/b.jai", "b := 2;\n", .STRIP, Load_Target.[], "1");

    targets: [..] Load_Target;
    array_add(*targets, .{from = "src/b.jai", to = tprint("C:/pkg/target/transpile/%1/src/b.jai", child)});
    parent := transpile_view_key("src/a.jai", "#load \"b.jai\";\n", .STRIP, targets, "1");

    // The rewrite table participates in the key...
    expect(parent != transpile_view_key("src/a.jai", "#load \"b.jai\";\n", .STRIP, Load_Target.[], "1"));
    // ...and carries the child key, so the parent key tracks the child.
    targets_other: [..] Load_Target;
    array_add(*targets_other, .{from = "src/b.jai", to = tprint("C:/pkg/target/transpile/%1/src/b.jai", child_other)});
    expect(parent != transpile_view_key("src/a.jai", "#load \"b.jai\";\n", .STRIP, targets_other, "1"));
    // From-side changes rewrite the same way and must change the key too.
    targets_from: [..] Load_Target;
    array_add(*targets_from, .{from = "src/c.jai", to = tprint("C:/pkg/target/transpile/%1/src/b.jai", child)});
    expect(parent != transpile_view_key("src/a.jai", "#load \"b.jai\";\n", .STRIP, targets_from, "1"));
}

// The view cache key embeds the ordered name+version sequence of the
// registry that produces the view, so a plugin rename, a version bump or a
// pipeline reorder each changes the key precisely.
test "Cache key: pipeline description is component-sensitive" {
    base: [..] Transpile_Plugin;
    array_add(*base, load_plugin());
    array_add(*base, test_block_plugin());
    key := transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION, base);
    expect(key == transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION, base));

    // Name change -> key change (same version, same order, same input).
    renamed: [..] Transpile_Plugin;
    array_add(*renamed, load_plugin());
    renamed_block := test_block_plugin();
    renamed_block.name = "test-block-renamed";
    array_add(*renamed, renamed_block);
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION, renamed));

    // Version change -> key change.
    bumped: [..] Transpile_Plugin;
    array_add(*bumped, load_plugin());
    bumped_block := test_block_plugin();
    bumped_block.version = "1.0.1";
    array_add(*bumped, bumped_block);
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION, bumped));

    // Order change -> key change.
    reversed: [..] Transpile_Plugin;
    array_add(*reversed, test_block_plugin());
    array_add(*reversed, load_plugin());
    expect(key != transpile_view_key("src/a.jai", "x := 1;\n", .EXPAND, Load_Target.[], VIEW_CONTRACT_VERSION, reversed));
}

// ===========================================================================
// Path helpers
// ===========================================================================

// Collision-avoiding path shape: <transpile_dir>/<hash>/<rel> mirrors the
// package-relative structure inside the hash directory, so "src/a/x.jai"
// and "src/a_x.jai" stay distinct where a flattened layout would collide;
// dependency closures get their own per-dependency subtree; the tree root
// derives from the package root.
test "Cache view path mirrors the relative structure" {
    dir := "C:/pkg/target/transpile";
    expect(transpile_hash_dir(dir, "abcd1234") == "C:/pkg/target/transpile/abcd1234");
    expect(transpile_view_path(dir, "abcd1234", "src/a/x.jai") == "C:/pkg/target/transpile/abcd1234/src/a/x.jai");
    expect(transpile_view_path(dir, "abcd1234", "src/a_x.jai") != transpile_view_path(dir, "abcd1234", "src/a/x.jai"));
    // The rel path is mirrored, not flattened into the hash directory name.
    expect(transpile_view_path(dir, "abcd1234", "src/a/x.jai") != transpile_hash_dir(dir, "abcd1234_src_a_x.jai"));
    // Backslash inputs are normalized to forward slashes.
    expect(transpile_view_path("C:\\pkg\\target\\transpile", "abcd1234", "src/a.jai") == "C:/pkg/target/transpile/abcd1234/src/a.jai");

    // The dependency subtree keeps distinct dependencies apart.
    expect(transpile_dependency_view_path(dir, "abcd1234", "dep-a", "src/context.jai") == "C:/pkg/target/transpile/deps/dep-a/abcd1234/src/context.jai");
    expect(transpile_dependency_view_path(dir, "abcd1234", "dep-b", "src/context.jai") != transpile_dependency_view_path(dir, "abcd1234", "dep-a", "src/context.jai"));
    expect(transpile_dependency_view_path(dir, "abcd1234", "dep-a", "src/context.jai") != transpile_view_path(dir, "abcd1234", "src/context.jai"));

    // The transpile subtree root.
    expect(transpile_tree_dir("C:\\pkg") == "C:/pkg/target/transpile");
}
