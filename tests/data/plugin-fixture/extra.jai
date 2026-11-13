// Fixture plugin package second plugin (ticket 025 E2E): convention 3 —
// a file stem module (#import "extra"), pinning the scan order next to the
// entry (the walk yields extra.jai before module.jai). This plugin
// contributes only one after-COMPILE lifecycle hook.
#import "Basic";
#import "juice_core";

Extra_Plugin :: struct {
    using base: Juice_Plugin;
    config: string = "";
}

extra_after_compile :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    array_add(ctx.diagnostics, .{level = .INFO, message = "extra-after-compile"});
    return true;
}

get_juice_plugin :: () -> *Extra_Plugin {
    plugin := New(Extra_Plugin);
    plugin.id = "extra";
    plugin.version = "1.0.0";
    plugin.options = cast(*void) plugin;
    array_add(*plugin.hooks, .{stage = .COMPILE, position = .after, hook = extra_after_compile});
    return plugin;
} @juice_plugin
