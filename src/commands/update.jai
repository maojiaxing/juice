#import "Basic";

// `juice update` (spec 0087 decision 19): refresh the dependency resolution
// graph only — no compilation, no test execution. It resolves every Git source
// in the complete direct/transitive graph of the selected consumer packages,
// records the new selections, and reports the outcome.
//
// Full command selection and flag wiring (--workspace/-p/--package-path) belongs
// to ticket 0093; this command carries only the resolution mode switch this
// ticket must prove end to end, plus the offline conflict rule (decision 14:
// update and offline are mutually exclusive).

UPDATE_COMMAND :: Command.{
    name          = "update",
    description   = "Refresh dependency resolution selections without compiling",
    usage         = "juice update",
    prerequisites = string.[],
    handler       = update_command,
    validate_arguments = build_arguments_are_valid,
};

update_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    mode, remaining, rejected := split_offline_flag(arguments);
    if rejected || remaining.count > 0 {
        print("[juice ERROR] Usage: %\n", UPDATE_COMMAND.usage);
        return false;
    }
    if mode == .OFFLINE {
        print("[juice ERROR] update cannot run offline: an update always contacts the Git sources.\n");
        return false;
    }
    ctx.workspace.environment.mode = .UPDATE;
    // update refreshes the graph even for a package with no executable, so the
    // preparation step is forced (the same flag Test uses for its shim needs).
    prepared := ensure_workspace_prepared(ctx.root_dir, ctx.cache_dir, *ctx.workspace, force_dependencies = true);
    if prepared == null return false;
    print("[juice] Dependency resolution graph updated.\n");
    return true;
}
