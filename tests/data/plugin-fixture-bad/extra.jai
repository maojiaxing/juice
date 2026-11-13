// Fixture plugin package second plugin (ticket 029 E2E): the duplicate —
// same id as the entry (module.jai), same version, no faces. The merge
// must reject the duplicate registration loudly (diagnostic + ok=false) —
// the second bad-package face next to the line-fidelity violation in the
// entry. Like the entry, this module imports the plugin face by name
// (#import "juice_core" — the published module, landed by
// ensure_published_modules).
#import "Basic";
#import "juice_core";

Extra_Plugin :: struct {
    using base: Juice_Plugin;
    config: string = "";
}

get_juice_plugin :: () -> *Extra_Plugin {
    plugin := New(Extra_Plugin);
    plugin.id = "bad-shared";
    plugin.version = "1.0.0";
    plugin.options = cast(*void) plugin;
    return plugin;
} @juice_plugin
