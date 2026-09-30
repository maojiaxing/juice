#import "Basic";
#import "Process";
#import "File";
#import "File_Utilities";
#import "String";
#import "Juice";

BUILD_COMMAND :: Command.{
    name          = "build",
    description   = "Build all targets in the root package",
    usage         = "juice build",
    prerequisites = string.["prepare-workspace"],
    visible       = true,
    handler       = build_command,
};

build_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if !command_arguments_are_valid(BUILD_COMMAND, arguments) return false;
    prepared := get_prepared_workspace(*ctx.workspace);
    if prepared == null {
        print("[juice ERROR] Command 'build' requires workspace preparation.\n");
        return false;
    }
    if !build_prepared_workspace(ctx.driver, prepared) return false;
    print("[juice] Build completed successfully!\n");
    return true;
}

compiler_import_arguments :: (driver: *Build_Driver) -> [..] string {
    args: [..] string;
    args.allocator = temp;

    exe_path := get_path_of_running_executable();
    bin_dir  := path_strip_filename(exe_path);
    global_modules_dir := to_forward_slashes(tprint("%1/../modules", bin_dir));
    if is_directory(global_modules_dir) array_add(*args, "-import_dir", global_modules_dir);

    if is_directory(driver.packages_dir) {
        array_add(*args, "-import_dir", to_forward_slashes(driver.packages_dir));
    }
    return args;
}

// Revalidate the whole build input before compiling anything, so an unsafe
// plan cannot produce a partial build. Plan structure and paths are owned by
// this gate; compile_artifact_plan pre-checks only its own source file.
revalidate_build_plans :: (prepared: *Prepared_Workspace) -> bool {
    package_root := prepared.discovery.root_dir;
    root_entry := inspect_path_entry(package_root);
    if !root_entry.exists || !root_entry.is_directory || root_entry.is_symlink || root_entry.is_junction {
        print("[juice ERROR] Package root changed or is unsafe before build.\n");
        return false;
    }

    for plan: prepared.artifact_plans {
        if !revalidate_artifact_plan(plan, package_root) {
            print("[juice ERROR] Artifact path became unsafe before build: %\n", plan.artifact_path);
            return false;
        }
        source_entry := inspect_path_entry(plan.target.source_path);
        if !source_entry.exists || source_entry.is_directory || source_entry.is_symlink || source_entry.is_junction {
            print("[juice ERROR] Target source became unsafe before build: %\n", plan.target.source_path);
            return false;
        }
    }
    return true;
}

compile_artifact_plan :: (driver: *Build_Driver, plan: Artifact_Plan) -> bool {
    source_file := to_forward_slashes(plan.target.source_path);
    if !path_exists_as_regular_file(source_file) {
        print("[juice ERROR] Target source file not found: %\n", source_file);
        return false;
    }

    if !make_directory_if_it_does_not_exist(plan.result_dir, recursive = true) {
        print("[juice ERROR] Could not create result directory: %\n", plan.result_dir);
        return false;
    }

    print("[juice Build] Compiling Target '%' (%) -> result/...\n", plan.target.name, plan.target.main_file);

    args: [..] string;
    array_add(*args, "jai");
    array_add(*args, source_file);
    array_add(*args, "-exe", plan.target.name);
    array_add(*args, "-output_path", plan.result_dir);

    import_args := compiler_import_arguments(driver);
    for arg: import_args array_add(*args, arg);

    result := run_command(..args);
    if result.exit_code != 0 {
        print("[juice ERROR] Compilation failed for target '%'.\n", plan.target.name);
        return false;
    }

    if !file_exists(plan.artifact_path) {
        print("[juice ERROR] Compiler did not produce expected artifact: %\n", plan.artifact_path);
        return false;
    }
    return true;
}

// The compile seam mirrors run's launch and clean's validate/delete seams:
// production handlers use the default; tests cross the same interface with a
// recording adapter instead of invoking the real compiler.
build_prepared_workspace :: (
    driver: *Build_Driver,
    prepared: *Prepared_Workspace,
    compile: #type (driver: *Build_Driver, plan: Artifact_Plan) -> bool = compile_artifact_plan
) -> bool {
    // Empty target sets are an intentional no-op. In particular, do not
    // create result/ and do not prepare dependencies for such a package.
    if prepared.artifact_plans.count == 0 return true;
    if !revalidate_build_plans(prepared) return false;

    for plan: prepared.artifact_plans {
        if !compile(driver, plan) return false;
    }
    return true;
}
