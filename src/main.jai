#import "Basic";
#import "System";

#import "Juice";

#load "xdg.jai";
#load "path_safety.jai";
#load "manifest.jai";
#load "workspace.jai";
#load "target.jai";
#load "dependency.jai";
#load "transpile.jai";
#load "transpile_cache.jai";
#load "transpile_front.jai";
#load "metaprogram.jai";
#load "scan_walk.jai";
#load "jaix_front.jai";
#load "commands/command.jai";
#load "commands/build.jai";
#load "commands/run.jai";
#load "commands/clean.jai";
#load "commands/test.jai";
#load "commands/registry.jai";
#load "dispatcher.jai";

main :: () {
    auto_release_temp();

    args := get_command_line_arguments();
    command := ifx args.count > 1 then args[1] else "build";
    command_arguments: [..] string;
    if args.count > 2 {
        for i: 2..args.count-1 array_add(*command_arguments, args[i]);
    }

    ctx: Command_Context;
    ctx.root_dir = get_working_directory();
    // The caches Juice manages (manifest evaluator temp files, git repo
    // caches) land in the XDG cache home; the other derived paths
    // (packages_dir etc.) are derived from root_dir by their respective
    // owners (after the Build_Driver teardown).
    ctx.cache_dir = tprint("%1/juice", get_cache_home());
    result := dispatch_command(COMMAND_REGISTRY, command, *ctx, command_arguments);
    if !result.success exit(1);
}
