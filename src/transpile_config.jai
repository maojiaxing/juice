// Package configuration -> plugin resolution (spec 004 decision 18, ticket
// 027; 2026-10-21 design revision, ticket 056): maps a package's declared
// Plugin_Declaration list — the manifest protocol's PLUGIN records, the
// Juice module face the discovery snapshot carries — onto the resolved
// plugin products through resolve_plugin_configs (src/plugin.jai), the
// single landing point for the transpile pipeline, the hook table and the
// options application. Declaration order = pipeline order = hook
// registration order = lint observation order. Zero declarations resolve to
// the default [load, test-block] pipeline (the resolver's face default,
// consistent with resolve_pipeline), so undeclared packages keep today's
// behavior and a view's pipeline never disagrees with its key.
//
// The command-side registry (ticket 058; Phase 2 since ticket 061): the
// built-in values only. The former static extension seam (the Phase-1 static
// pre-step plugin's module supplying its value through static_builtin_plugins)
// is gone — the pre-step plugin is a member package now, so its value lives
// in the generated host and the test metaprogram. Declarations naming a
// registry id resolve in-process; every other id names a workspace member
// (the Phase-2 boundary: member values live in the PRESTEP host and the
// generated test metaprogram), so this adapter filters those out of the
// config list before resolving. Member identity is validated by the
// declaration-driven workspace scan (scan_workspace_plugins: unknown member =
// loud error); member version/options validation happens where the values
// exist. The runtime-dependent test-program pipeline is not used by the
// command process (the test program resolves its own declared member faces).
//
// plugin_configs_from_declarations is the generated test metaprogram's
// config source: it embeds only member-plugin declarations, because the
// generated program's registry holds exactly the built-in values plus the
// scanned member values — a static built-in declaration has no value there
// and is already validated command-side by resolve_package_plugins.
//
// This module joins the build closure (main.jai, ticket 027): the build and
// test commands resolve every package's declared pipeline through it. The
// built-in id constants are the registry's single source (src/module.jai,
// consumed by plugin.jai's builtins); plugin.jai's registry is the value
// source. This module must stay test-free; its unit tests live in
// tests/build_transpile_tests.jai (0053 rule).

#import "Basic";

// The command-side plugin registry: the built-in transpile values, in
// declaration order. Every command-side plugin consumer (the declaration
// resolver below and the workspace scan's built-in skip in
// src/plugin_scan.jai) reads the same registry, so a registry id is treated
// exactly like load / test-block everywhere. Member plugin values never
// exist in this process (they live in the PRESTEP host / test metaprogram).
command_plugin_registry :: () -> [..] *Juice_Plugin {
    return builtin_plugins();
}

// Whether the id names a static built-in plugin of the command process (a
// registry value: load / test-block). A declaration naming one of these is
// resolved command-side and never passes through the member scan or the
// generated test program.
is_command_static_plugin_id :: (id: string) -> bool {
    for plugin: command_plugin_registry() {
        if plugin.id == id return true;
    }
    return false;
}

// The command-side declaration -> resolver adapter. The command registry is
// the value source (no member values exist in this process — see the
// header), then the declarations naming a registry id become Plugin_Config
// rows in declaration order. Non-registry ids (member plugin identities) are
// skipped here.
resolve_package_plugins :: (decls: [] Juice.Plugin_Declaration) -> Resolved_Plugins {
    registry := command_plugin_registry();

    configs: [..] Plugin_Config;
    for decl: decls {
        is_builtin := false;
        for plugin: registry {
            if plugin.id == decl.id is_builtin = true;
        }
        if !is_builtin continue;

        config: Plugin_Config;
        config.id = decl.id;
        config.version = decl.version;
        // The declaration options slice -> the shared Option_Row array (a
        // slice field cannot array_add; rebuild and assign the view).
        rows: [..] Option_Row;
        for opt: decl.options array_add(*rows, .{ key = opt.key, value = opt.value });
        config.options = rows;
        array_add(*configs, config);
    }
    return resolve_plugin_configs(registry, configs);
}

// The full declaration -> shared config conversion for the generated test
// metaprogram. Only declarations naming a workspace member are embedded: the
// generated program's registry holds the built-in values plus the scanned
// member values, so a built-in declaration (load / test-block) would resolve
// to an unknown id there — it is validated command-side by
// resolve_package_plugins instead. Member declarations keep their
// declaration order (the generated program's lint observation order),
// including repeated ids (the resolver reports the duplicate where the
// values exist).
plugin_configs_from_declarations :: (decls: [] Juice.Plugin_Declaration, member_packages: [] Juice.Package) -> [..] Plugin_Config {
    configs: [..] Plugin_Config;
    for decl: decls {
        is_member := false;
        for pkg: member_packages {
            if pkg.name == decl.id is_member = true;
        }
        if !is_member continue;

        config: Plugin_Config;
        config.id = decl.id;
        config.version = decl.version;
        rows: [..] Option_Row;
        for opt: decl.options array_add(*rows, .{ key = opt.key, value = opt.value });
        config.options = rows;
        array_add(*configs, config);
    }
    return configs;
}
