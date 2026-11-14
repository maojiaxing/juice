#import "Basic";
#import "File_Utilities";
#import "Process";

// The run command (spec 0087 decision 19, ticket 0093): run compiles exactly
// one selected program and launches it. It is NOT a build prerequisite chain —
// the dispatcher plans no prerequisite for run, so an unrelated program of the
// same package is never compiled, and the package-level plugin preparation runs
// once for the one program (decision 23/94).
//
// The order is the contract:
//   1. the shared selection (location/flags, decision 17/18) must come down to
//      exactly one package — run never filters out packages without programs to
//      guess an intent;
//   2. inside that package the program comes from an explicit name, else the
//      declared default_run, else the only program (no first-item or package-name
//      fallback — decision 72);
//   3. only that program's plan is compiled, through the same PRESTEP/TRANSPILE/
//      COMPILE stages build uses, so the derived view and plugin preparation are
//      identical to a build of the same program;
//   4. everything after `--` is passed to the program verbatim, and the child's
//      exit code becomes the command's.

RUN_COMMAND :: Command.{
    name          = "run",
    description   = "Compile and run one selected program",
    usage         = "juice run [program] [-- args...]",
    flag_help     = "  Selection: --workspace | -p/--package <name> | --package-path <dir>, and --offline; arguments after '--' reach the program",
    prerequisites = string.[],
    handler       = run_command_handler,
    validate_arguments = run_arguments_are_valid,
};

run_arguments_are_valid :: (arguments: [] string) -> bool {
    return command_selection_arguments_are_valid(arguments, 1, true);
}

run_command_handler :: (ctx: *Command_Context, arguments: [] string) -> bool {
    flags, flags_ok := parse_command_flags(arguments, 1, true);
    if !flags_ok {
        print_command_usage(RUN_COMMAND);
        return false;
    }
    selection, selected := select_command_packages(ctx, flags, resolution_mode_for(flags), force_dependencies = true);
    if !selected return false;

    // The one-package cardinality gate runs before any compilation.
    if selection.packages.count != 1 {
        selected_paths: [..] string;
        for selected_package: selection.packages array_add(*selected_paths, selected_package.relative_path);
        print("[juice ERROR] run requires exactly one selected package; % selected: %.\n",
              selection.packages.count, join_paths(selected_paths, ", "));
        return false;
    }
    selected_package := selection.packages[0];
    plan, chosen := select_run_plan(selected_package, flags.positionals);
    if !chosen return false;

    // Only the selected program is compiled (decision 73).
    plans: [..] Artifact_Plan;
    array_add(*plans, plan);
    if !build_package(selection.prepared, selected_package.package, plans) return false;

    return launch_selected_plan(plan, selected_package.package.dir, flags.separator_arguments);
}

// The program selection inside the one selected package (decision 19/72): an
// explicit name (exact spelling — declaration uniqueness is case-insensitive,
// the command line is not), else the declared default_run, else the only
// program. An invalid default_run is already rejected by product resolution, so
// reaching the default_run branch with no match can only mean the declaration
// changed underneath us; it still fails instead of falling back.
select_run_plan :: (selected: Selected_Package, positionals: [] string) -> (Artifact_Plan, bool) {
    if selected.plans.count == 0 {
        print("[juice ERROR] Package '%' has no executable program to run.\n", selected.package.name);
        return .{}, false;
    }
    requested := ifx positionals.count == 1 then positionals[0] else "";
    if requested != "" {
        for plan: selected.plans {
            if plan.target.name == requested return plan, true;
        }
        print("[juice ERROR] Package '%' has no program named '%'.\n", selected.package.name, requested);
        return .{}, false;
    }
    if selected.package.default_run != "" {
        for plan: selected.plans {
            if ascii_names_equal(plan.target.name, selected.package.default_run) return plan, true;
        }
        print("[juice ERROR] Package '%' declares default_run '%', which names no program.\n", selected.package.name, selected.package.default_run);
        return .{}, false;
    }
    if selected.plans.count == 1 return selected.plans[0], true;

    program_names: [..] string;
    for plan: selected.plans array_add(*program_names, plan.target.name);
    print("[juice ERROR] Package '%1' declares %2 programs and no default_run; name one of: %3.\n",
          selected.package.name, selected.plans.count, join_paths(program_names, ", "));
    return .{}, false;
}

// The launch seam: the separator arguments travel to the program verbatim
// (decision 19). Tests drive this seam with a recording fake.
launch_selected_plan :: (
    plan: Artifact_Plan,
    package_root: string,
    arguments: [] string,
    launch: #type (plan: Artifact_Plan, package_root: string, arguments: [] string) -> bool = run_artifact_plan
) -> bool {
    return launch(plan, package_root, arguments);
}

run_artifact_plan :: (plan: Artifact_Plan, package_root: string, arguments: [] string) -> bool {
    if !revalidate_artifact_plan(plan, package_root) {
        print("[juice ERROR] Refusing unsafe artifact path: %\n", plan.artifact_path);
        return false;
    }
    if !file_exists(plan.artifact_path) {
        print("[juice ERROR] Could not find executable to run: %\n", plan.artifact_path);
        return false;
    }

    print("[juice Run] Launching % ...\n\n", plan.artifact_path);
    spawn_arguments: [..] string;
    array_add(*spawn_arguments, plan.artifact_path);
    for argument: arguments array_add(*spawn_arguments, argument);
    result := run_command(..spawn_arguments);
    return result.exit_code == 0;
}
