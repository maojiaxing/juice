#import "Basic";

// ---------------------------------------------------------------------------
// Command selection (spec 0087 decisions 17-20, 23, 27; ticket 0093).
//
// build, run, test and update share one path: the nearest declaration is
// located (workspace layer), the requested package set is validated
// (select_workspace_packages), every selected package's product declarations
// are resolved, and the dependency resolution runs for exactly that set. Only
// then does the command do its own work — and a package set is never filtered
// down to "the packages that happen to have programs" to guess an intent.
//
// The flags are also the dispatcher's argument contract, so an invalid flag or
// a contradictory selection is rejected at plan time, before any handler runs.
// ---------------------------------------------------------------------------

Command_Flags :: struct {
    request:             Package_Selection_Request;
    offline:             bool;
    positionals:         [..] string;
    // The arguments after a `--` separator. Only `run` accepts a separator: they
    // travel to the launched program verbatim (decision 19).
    separator_arguments: [..] string;
    has_separator:       bool;
}

selection_flag_rejection :: (report_errors: bool, message: string) -> bool {
    if report_errors print("[juice ERROR] %\n", message);
    return false;
}

// Parse the shared selection surface plus the command's own positional
// arguments. `max_positionals` and `allow_separator` are the only per-command
// differences: build/update take none, test takes the pattern, run takes the
// program name and the `--` passthrough.
parse_command_flags :: (
    arguments: [] string,
    max_positionals: int,
    allow_separator: bool,
    report_errors: bool = true
) -> (Command_Flags, bool) {
    flags: Command_Flags;
    // The request's lists are slices (the workspace seam's shape), so they are
    // filled as resizable arrays and published once at the end.
    names: [..] string;
    paths: [..] string;
    all_members := false;
    index := 0;
    while index < arguments.count {
        argument := arguments[index];
        if argument == "--" {
            if !allow_separator return flags, selection_flag_rejection(report_errors, "This command does not accept a '--' argument separator.");
            flags.has_separator = true;
            index += 1;
            while index < arguments.count {
                array_add(*flags.separator_arguments, arguments[index]);
                index += 1;
            }
            break;
        }
        if argument == "--offline" {
            flags.offline = true;
            index += 1;
            continue;
        }
        if argument == "--workspace" {
            all_members = true;
            index += 1;
            continue;
        }
        if argument == "-p" || argument == "--package" {
            if index + 1 >= arguments.count {
                if report_errors print("[juice ERROR] %1 requires a package name.\n", argument);
                return flags, false;
            }
            array_add(*names, arguments[index + 1]);
            index += 2;
            continue;
        }
        if argument == "--package-path" {
            if index + 1 >= arguments.count return flags, selection_flag_rejection(report_errors, "--package-path requires a workspace-relative package directory.");
            array_add(*paths, arguments[index + 1]);
            index += 2;
            continue;
        }
        if starts_with(argument, "-") return flags, selection_flag_rejection(report_errors, tprint("Unknown option: %", argument));
        array_add(*flags.positionals, argument);
        index += 1;
    }
    flags.request = .{all_members = all_members, names = names, paths = paths};
    if flags.positionals.count > max_positionals {
        return flags, selection_flag_rejection(report_errors, "Too many arguments.");
    }
    return flags, true;
}

command_selection_arguments_are_valid :: (arguments: [] string, max_positionals: int, allow_separator: bool) -> bool {
    _, ok := parse_command_flags(arguments, max_positionals, allow_separator, report_errors = false);
    return ok;
}

resolution_mode_for :: (flags: Command_Flags) -> Resolution_Mode {
    return ifx flags.offline then Resolution_Mode.OFFLINE else Resolution_Mode.NORMAL;
}

// The root package of a prepared workspace, with its directory filled from the
// discovery root. The production path fills both from the manifest load; the
// function-level fixtures build a Prepared_Workspace by hand and set only
// discovery.root_dir, so this is the one place the two spellings are reconciled
// (and an empty scan root can never escape into a drive-wide walk).
root_package_of :: (prepared: *Prepared_Workspace) -> Normalized_Package {
    package := prepared.discovery.root_package;
    if package.dir == "" package.dir = prepared.discovery.root_dir;
    return package;
}

// One selected package with the products its declaration resolves to. The
// relative path is the workspace-relative directory the selection reported (the
// batch report and the diagnostics name packages that way).
Selected_Package :: struct {
    package:       Normalized_Package;
    relative_path: string;
    plans:         [] Artifact_Plan;
}

// The command's validated selection: the prepared workspace (dependency
// resolution for exactly these packages) plus one entry per selected package in
// stable workspace-relative directory order.
Command_Selection :: struct {
    prepared: *Prepared_Workspace;
    packages: [] Selected_Package;
}

// The one selection entry point build/run/test/update consume. `mode` is the
// resolution mode the command runs under (NORMAL, OFFLINE, or UPDATE for
// `juice update`); `force_dependencies` prepares the dependency graph even when
// a selected package has no program (test and update have no artifact to gate
// on, and build must validate dependencies before reporting "no programs").
select_command_packages :: (
    command_context: *Command_Context,
    flags: Command_Flags,
    mode: Resolution_Mode,
    force_dependencies: bool = false,
    resolve: #type (pkg: Normalized_Package) -> Artifact_Plan_Result = resolve_artifact_plans
) -> (Command_Selection, bool) {
    command_context.workspace.environment.mode = mode;
    // A contradictory selection is rejected here — before discovery, so the
    // diagnostic names the conflict rather than some downstream consequence
    // (decision 18/70: the whole selection is validated before any command
    // work).
    if flags.request.all_members && (flags.request.names.count > 0 || flags.request.paths.count > 0) {
        print("[juice ERROR] --workspace cannot be combined with --package or --package-path.\n");
        return .{}, false;
    }
    // Discovery validates every member declaration before the selection is
    // consulted: an invalid unselected member blocks the operation instead of
    // letting a batch run over a half-understood workspace (decision 20).
    if !ensure_workspace_discovered(command_context.root_dir, command_context.cache_dir, *command_context.workspace) return .{}, false;

    selection := select_workspace_packages(command_context.workspace.discovery, command_context.workspace.invocation_dir, flags.request);
    if !selection.success {
        print("[juice ERROR] %\n", selection.error);
        return .{}, false;
    }

    command_selection: Command_Selection;
    selected_entries: [..] Selected_Package;
    for selected_package, index: selection.packages {
        plans := resolve(selected_package);
        if !plans.success {
            print("[juice ERROR] Package '%': %\n", selected_package.name, plans.error_message);
            return .{}, false;
        }
        entry: Selected_Package;
        entry.package = selected_package;
        entry.relative_path = copy_string(selection.paths[index]);
        entry.plans = plans.plans;
        array_add(*selected_entries, entry);
    }
    command_selection.packages = selected_entries;

    // The dependency preparation seam reads the same selection, so only the
    // selected packages' graphs are fetched (decision 20).
    command_context.workspace.selection = selection;
    prepared := ensure_workspace_prepared(command_context.root_dir, command_context.cache_dir, *command_context.workspace, force_dependencies = force_dependencies);
    if prepared == null return .{}, false;
    command_selection.prepared = prepared;
    return command_selection, true;
}

// ---------------------------------------------------------------------------
// Batch execution (decision 20): the packages run in the selection's stable
// order, the first failure stops the batch, and the report names the completed,
// failed and not-executed scope. A package that already succeeded is never
// rolled back — the scope report is what makes that visible.
// ---------------------------------------------------------------------------
Package_Batch :: struct {
    operation:    string;
    completed:    [..] string;
    failed:       string;
    not_executed: [..] string;
    total:        int;
}

package_batch_report_failure :: (batch: *Package_Batch) {
    if batch.total <= 1 return;
    if batch.completed.count > 0 {
        print("[juice] %1: completed %2\n", batch.operation, join_paths(batch.completed, ", "));
    } else {
        print("[juice] %: no package completed.\n", batch.operation);
    }
    print("[juice] %1: failed %2\n", batch.operation, batch.failed);
    if batch.not_executed.count > 0 {
        print("[juice] %1: not executed %2\n", batch.operation, join_paths(batch.not_executed, ", "));
    } else {
        print("[juice] %: no package left unexecuted.\n", batch.operation);
    }
}

// Record the failure at `index` and fill the not-executed tail.
package_batch_fail :: (batch: *Package_Batch, selection: *Command_Selection, index: int) {
    batch.failed = copy_string(selection.packages[index].relative_path);
    remaining := index + 1;
    while remaining < selection.packages.count {
        array_add(*batch.not_executed, copy_string(selection.packages[remaining].relative_path));
        remaining += 1;
    }
}

// Compose a "a, b, c" list for the batch report.
join_paths :: (paths: [] string, separator: string) -> string {
    builder: String_Builder;
    for path, index: paths {
        if index > 0 print_to_builder(*builder, "%", separator);
        print_to_builder(*builder, "%", path);
    }
    return builder_to_string(*builder);
}
