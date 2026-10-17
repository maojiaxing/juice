// jaix demo config: the try/catch built-in plugin. Juice's own test block
// mechanism stays out of the jaix config (the double processing exclusion —
// the mixed-package seam): juice test block files keep their original juice
// path and are not mirrored.
#import "jaix";
Jaix_Plugin_Try_Catch :: #import "Jaix_Plugin_Try_Catch";

get_config :: () -> Jaix_Config {
    p := Jaix_Plugin_Try_Catch.get_plugin();
    p.options = .{ error_convention = .MULTI_RETURN };
    return .{ plugins = plugins_of(as_plugin(p)) };
}
