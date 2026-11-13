#import "Basic";
#import "File";
#import "File_Utilities";

// The clean command (spec section 4.6 clean sequence, the old juice
// commands/clean.jai semantics): discovery without preparation (clean needs
// no dependency or plan resolution) -> path collection (the root package's
// and every member's target/ directory, spec section 3.5) -> validate every
// path first, then delete. Clean never touches legacy result/ and .packages
// directories. The command obtains a fresh discovery snapshot directly:
// the state machine's ensure entry rejects the manifest-less root that
// clean deliberately supports (old juice inline test "Clean without a
// manifest uses the current root") and prints a "Package discovered" line
// old juice clean never emits.
//
// The Package face is consumed through the namespaced Juice binding
// (src/juice_module.jai), as in the other command layers.

CLEAN_COMMAND :: Command.{
    name          = "clean",
    description   = "Remove Juice outputs and local dependency links",
    usage         = "juice clean",
    prerequisites = string.[],
    handler       = clean_command,
};

clean_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if !command_arguments_are_valid(CLEAN_COMMAND, arguments) return false;

    discovery, ok := discover_workspace(ctx.root_dir, ctx.cache_dir);
    if !ok {
        print("[juice ERROR] Clean discovery failed; no files were deleted.\n");
        return false;
    }
    return clean_discovered_workspace(ctx.root_dir, discovery);
}

clean_path_is_safe :: (path: string) -> bool {
    entry := inspect_path_entry(path);
    if !entry.exists return true;
    if entry.is_symlink || entry.is_junction {
        print("[juice ERROR] Refusing to delete symlink/junction: %\n", path);
        return false;
    }
    return entry.is_directory;
}

// The two seams keep the old juice shapes (#type (path: string) -> bool
// each): the validation gate and the deletion step cross the real
// filesystem in production, and tests cross the same interface with
// recording fakes. Validation runs over every collected path before any
// deletion — one unsafe path deletes nothing. The delete loop does not
// abort on a failure: it reports "Could not delete" and keeps deleting the
// remaining paths (old juice semantics).
clean_discovered_workspace :: (
    root_dir: string,
    discovery: Juice.Workspace_Discovery,
    validate_path: #type (path: string) -> bool = clean_path_is_safe,
    delete_path: #type (path: string) -> bool = delete_directory_full
) -> bool {
    paths: [..] string;

    // Clean deletes the whole target/ directory of the root package and
    // every validated workspace member (spec section 3.5: each package owns
    // its own target/). Legacy result/ and .packages directories are no
    // longer managed and are never touched.
    if discovery.has_package {
        for member: discovery.member_packages {
            array_add(*paths, package_target_dir(member.dir));
        }
    } else {
        array_add(*paths, package_target_dir(root_dir));
    }

    // Validate every deletion target before deleting any of them.
    for path: paths {
        if !validate_path(path) return false;
    }

    print("[juice Clean] Cleaning output directories...\n");
    all_ok := true;
    for path: paths {
        if !delete_path(path) {
            print("[juice ERROR] Could not delete: %\n", path);
            all_ok = false;
        }
    }
    if all_ok print("[juice Clean] Workspace cleaned.\n");
    return all_ok;
}
