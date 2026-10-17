// Package configuration -> transpile pipeline assembly (spec 0060 decision
// 6, ticket 0063): maps a package's declared plugin list (the manifest
// protocol's TRANSPILE_PLUGIN records) onto the registered built-in
// plugins — declaration order = pipeline order. Zero declarations yield an
// empty pipeline, which resolve_pipeline (transpile_plugin.jai) resolves to
// the default — undeclared packages keep today's behavior exactly, and a
// view's pipeline never disagrees with its key (both go through the same
// single-point convention).
//
// The manifest validation gate (validate_transpile_pipeline, manifest.jai)
// rejects unknown ids at load time, so production declarations are always
// total over the built-in registry; the lookup still skips unknown ids
// defensively rather than failing on programmatically constructed packages.
// Not a bootstrap #load target: bootstrap builds juice itself and never
// evaluates a package manifest (the default pipeline applies there).

#import "Basic";
#import "Juice";
#import "Testing";

resolve_transpile_pipeline :: (decls: [] Transpile_Plugin_Declaration) -> [..] Transpile_Plugin {
    pipeline: [..] Transpile_Plugin;
    for decl: decls {
        if decl.id == TRANSPILE_PLUGIN_LOAD_ID {
            array_add(*pipeline, load_plugin());
        } else if decl.id == TRANSPILE_PLUGIN_TEST_BLOCK_ID {
            array_add(*pipeline, test_block_plugin());
        }
    }
    return pipeline;
}

// ---------------------------------------------------------------------------
// Inline tests: the declaration -> registry mapping, the registry-constant
// sync lock, and the gate's agreement with the real registry identities.
// ---------------------------------------------------------------------------

test "Transpile pipeline assembly preserves declaration order" {
    pipeline := resolve_transpile_pipeline(.[
        .{id = "test-block", version = "1.0.0"},
        .{id = "load", version = "1.0.0"},
    ]);
    expect(pipeline.count == 2);
    expect(pipeline[0].name == "test-block");
    expect(pipeline[1].name == "load");
}

test "Transpile pipeline assembly of zero declarations yields an empty pipeline" {
    pipeline := resolve_transpile_pipeline(.[]);
    expect(pipeline.count == 0);
    // The empty-means-default resolution stays the single-point convention
    // (resolve_pipeline), not the assembly's job.
    resolved := resolve_pipeline(pipeline);
    expect(resolved.count == 2);
    expect(resolved[0].name == "load");
    expect(resolved[1].name == "test-block");
}

test "Transpile pipeline assembly skips unknown ids defensively" {
    pipeline := resolve_transpile_pipeline(.[
        .{id = "load", version = "1.0.0"},
        .{id = "mystery", version = "1.0.0"},
    ]);
    expect(pipeline.count == 1);
    expect(pipeline[0].name == "load");
}

// The sync lock: the built-in id constants in modules/Juice.jai (the legal
// declaration set the manifest validation gate checks against) and the
// built-in registry identities in transpile_plugin.jai must agree — the
// gate must accept exactly the ids the assembly resolves.
test "Transpile pipeline validation and assembly agree on the built-in registry" {
    pkg: Package = .{name = "demo", version = "1", transpile = .{plugins = .[
        .{id = load_plugin().name, version = load_plugin().version},
        .{id = test_block_plugin().name, version = test_block_plugin().version},
    ]}};
    ok, message := validate_transpile_pipeline(pkg);
    expect(ok, tprint("gate rejected the real registry identities: %1", message));

    pipeline := resolve_transpile_pipeline(pkg.transpile.plugins);
    expect(pipeline.count == 2);
    expect(pipeline[0].name == load_plugin().name);
    expect(pipeline[0].version == load_plugin().version);
    expect(pipeline[1].name == test_block_plugin().name);
    expect(pipeline[1].version == test_block_plugin().version);
}
