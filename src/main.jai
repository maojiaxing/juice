#import "Basic";
#import "System";

// The command dispatcher wiring (ticket 010) with ticket 008's workspace
// layer: src/workspace.jai (member validation + the EMPTY -> DISCOVERED ->
// PREPARED phase machine) is the first production consumer of ticket 007's
// src modules, so juice_module.jai leads the #load list (007 chain
// convention) followed by the modules workspace.jai depends on. Ticket 009
// adds target.jai / dependency.jai after workspace.jai — the state machine
// seams' production defaults reference them (old juice load order: xdg →
// path_safety → manifest → workspace → target → dependency). Ticket 011
// adds metaprogram.jai before the commands — the build command generates
// its compile metaprogram through it. Tickets 012/013 land the real
// clean/run/version command handlers. Ticket 018 lands the real test
// command: scan_walk.jai (the file-collection skeleton), test_discovery.jai
// (the pure discovery surface the command's Test_Path_Pair references) and
// test_runner.jai (the driver/metaprogram generators + the COMPILE front)
// join the closure before commands/test.jai.
//
// Ticket 027 lands the transpile layer (1c): the transpile family
// (transpile → transpile_plugin → transpile_cache → transpile_front, the
// old juice order) joins after dependency.jai — dependency.jai's strip
// front consumes the view layer; lifecycle.jai (the hook mechanism) and
// plugin.jai (the plugin surface + built-in registry) follow; module.jai
// (the compatibility declaration face) joins before plugin.jai because the
// built-in plugin ids are single-sourced there; transpile_config.jai
// (declared pipeline → pipeline assembly) follows; metaprogram.jai loads
// after transpile.jai so its generated text uses the canonical quote pair
// (ticket 022's retirement condition). Ticket 037 adds publication.jai
// after metaprogram.jai: the test command derives the published internal
// discovery artifact's path through the landing helper family. Ticket 045
// adds plugin_scan.jai at the tail of the src modules: the test command's
// COMPILE stage consumes the workspace-level plugin scan (ticket 043), and
// the file's workspace/discovery references require juice_module.jai,
// dependency.jai, plugin.jai, scan_walk.jai and the transpile lexer first.
#load "juice_module.jai";
#load "xdg.jai";
#load "path_safety.jai";
#load "manifest.jai";
#load "workspace.jai";
#load "target.jai";
#load "dependency.jai";
#load "transpile.jai";
#load "transpile_plugin.jai";
#load "transpile_cache.jai";
#load "transpile_front.jai";
// The target layout (the single source of the target/ zone roots and landing
// paths). The target/dependency layers above reference it by forward
// declaration; build.jai loads it in its bootstrap closure too.
#load "target_layout.jai";
#load "lifecycle.jai";
#load "module.jai";
#load "plugin.jai";
#load "transpile_config.jai";
#load "metaprogram.jai";
// Ticket 037 lands publication.jai: the test command derives the published
// discovery artifact's path from the running executable's modules directory
// (test_discovery_module_path), the same landing helper family the build
// metaprogram publishes with — one path source for producer and consumer.
#load "publication.jai";
#load "scan_walk.jai";
#load "test_discovery.jai";
#load "test_runner.jai";
// Ticket 045 lands plugin_scan.jai in the tool closure: the test command's
// COMPILE stage scans the root package's declared member dependencies and
// writes the workspace registration file. The workspace-level scan needs
// juice_module.jai (Juice.Workspace_Discovery) and dependency.jai
// (find_workspace_member) first; its older references (plugin.jai's anchor
// note, scan_walk, the transpile lexer) are all earlier in the list too, so
// the file sits at the tail of the src modules.
#load "plugin_scan.jai";
// Ticket 060 lands the command-level plugin prepare + the PRESTEP-only
// plugin host: build and test call the one shared prepare (scan, member
// shims, registration file), and a declared member hooks plugin is loaded
// through a generated host driver whose record file returns the pre-step
// effects. The module consumes plugin_scan.jai, plugin.jai,
// transpile_config.jai, lifecycle.jai and manifest.jai, all loaded above.
#load "plugin_host.jai";
#load "commands/command.jai";
#load "commands/build.jai";
#load "commands/run.jai";
#load "commands/clean.jai";
#load "commands/test.jai";
#load "commands/version.jai";
#load "dispatcher.jai";
#load "commands/help.jai";

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
    // The caches juice manages (manifest evaluator temp files, git repo
    // caches) land in the XDG cache home; the other derived paths
    // (packages_dir etc.) are derived from root_dir by their respective
    // owners. ctx.workspace zero-initializes to the EMPTY phase; discovery
    // fills it on the first command that prepares the workspace.
    ctx.cache_dir = tprint("%1/juice", get_cache_home());
    result := dispatch_command(COMMAND_REGISTRY, command, *ctx, command_arguments);
    if !result.success exit(1);
}
