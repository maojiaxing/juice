// Fixture member plugin (ticket 060): one Juice_Plugin contributing a PRESTEP
// `before` hook and a four-row options schema. The command-level prepare
// scans this package (the @juice_plugin tail note anchors get_juice_plugin),
// links it through its import shim and the spawned PRESTEP-only host loads
// the value — the parent process never does. The hook is deliberately
// option-driven so the E2E pins the whole host protocol: options apply in the
// host, table effects return through the record file, the parent consumes
// them exactly like an in-process hook's.
//
// juice_core is the tool-provided module face (resolved from the executable's
// adjacent modules directory); this package declares no tool dependency.
#import "Basic";
#import "juice_core";

Prestep_Plugin_Options :: struct {
    entry:       string = "";
    replacement: string = "";
    drop:        string = "";
    message:     string = "";
}

Prestep_Plugin :: struct {
    using base: Juice_Plugin;
    config: Prestep_Plugin_Options;
}

// Module-held option defaults (Config_Option.default points at stable
// storage; the framework reads them, never writes).
PRESTEP_DEFAULT_ENTRY: string = "";
PRESTEP_DEFAULT_REPLACEMENT: string = "";
PRESTEP_DEFAULT_DROP: string = "";
PRESTEP_DEFAULT_MESSAGE: string = "";

prestep_apply_option :: (options: *void, key: string, value: string) -> string {
    plugin := cast(*Prestep_Plugin) options;
    if key == "entry" {
        plugin.config.entry = value;
        return "";
    }
    if key == "replacement" {
        plugin.config.replacement = value;
        return "";
    }
    if key == "drop" {
        plugin.config.drop = value;
        return "";
    }
    if key == "message" {
        plugin.config.message = value;
        return "";
    }
    return tprint("unknown option '%'", key);
}

// The post-assembly check: a substitution needs both halves; an unpaired
// entry (or replacement) is a declaration mistake. The first schema row
// carries the validator so a rejection reports exactly once.
prestep_validate_options :: (options: *void) -> string {
    plugin := cast(*Prestep_Plugin) options;
    if plugin.config.entry != "" && plugin.config.replacement == "" return "option 'entry' requires 'replacement'";
    if plugin.config.replacement != "" && plugin.config.entry == "" return "option 'replacement' requires 'entry'";
    return "";
}

// The PRESTEP before hook: reads its typed options through the plugin_state
// slot (the resolver applied the rows to the same pointer), then returns the
// stage effects through the shared prestep_add_* rules. The replacement path
// resolves against the stage's root (the substitution table carries absolute
// replacement paths).
prestep_before_hook :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    if state == null return false;
    plugin := cast(*Prestep_Plugin) state;
    if ctx.prestep == null return false;
    stage := cast(*Prestep_Stage) ctx.prestep;
    if plugin.config.message != "" {
        array_add(ctx.diagnostics, .{level = .INFO, message = plugin.config.message});
    }
    if plugin.config.entry != "" {
        // The stage root is already "/"-separated (the host embedded the
        // command's normalized root); the replacement is package-relative.
        replacement := tprint("%1/%2", stage.root_dir, plugin.config.replacement);
        if !prestep_add_substitution(ctx, plugin.config.entry, replacement) return false;
    }
    if plugin.config.drop != "" {
        if !prestep_add_drop(ctx, plugin.config.drop) return false;
    }
    return true;
}

get_juice_plugin :: () -> *Prestep_Plugin {
    plugin := New(Prestep_Plugin);
    plugin.id = "prestep-plugin";
    plugin.version = "0.1.0";
    plugin.options = cast(*void) plugin;
    array_add(*plugin.hooks, .{stage = .PRESTEP, position = .before, hook = prestep_before_hook});
    array_add(*plugin.options_schema, config_option("entry", *PRESTEP_DEFAULT_ENTRY, prestep_apply_option, prestep_validate_options));
    array_add(*plugin.options_schema, config_option("replacement", *PRESTEP_DEFAULT_REPLACEMENT, prestep_apply_option, null));
    array_add(*plugin.options_schema, config_option("drop", *PRESTEP_DEFAULT_DROP, prestep_apply_option, null));
    array_add(*plugin.options_schema, config_option("message", *PRESTEP_DEFAULT_MESSAGE, prestep_apply_option, null));
    return plugin;
} @juice_plugin
