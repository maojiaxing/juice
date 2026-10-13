#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import "Juice";

Target_Resolution_Error :: enum {
    NONE;
    INVALID_PACKAGE_ROOT;
    INVALID_PACKAGE_NAME;
    INVALID_PACKAGE_VERSION;
    INVALID_TARGET_NAME;
    INVALID_TARGET_SOURCE;
    DUPLICATE_TARGET_NAME;
    SOURCE_NOT_FOUND;
    SOURCE_NOT_REGULAR;
    SOURCE_OUTSIDE_PACKAGE;
    LIBRARY_TARGET_CONFLICT;
    MODULE_ENTRY_NOT_FOUND;
}

Target_Resolution_Result :: struct {
    success:      bool;
    targets:      [] Effective_Target;
    error:        Target_Resolution_Error;
    error_message: string;
    // The package role after UNSPECIFIED has been resolved by convention.
    package_type:  Package_Type;
}

Artifact_Plan_Result :: struct {
    success:      bool;
    plans:        [] Artifact_Plan;
    error:        Target_Resolution_Error;
    error_message: string;
    // The package role after UNSPECIFIED has been resolved by convention.
    package_type:  Package_Type;
}

make_resolution_failure :: (error: Target_Resolution_Error, message: string) -> Target_Resolution_Result {
    return .{success = false, error = error, error_message = copy_string(message)};
}

make_artifact_failure :: (error: Target_Resolution_Error, message: string) -> Artifact_Plan_Result {
    return .{success = false, error = error, error_message = copy_string(message)};
}

validate_package_identity :: (pkg: Package) -> Target_Resolution_Result, bool {
    if !path_is_portable_filename(pkg.name) {
        return make_resolution_failure(.INVALID_PACKAGE_NAME, "Package name must be a nonempty portable filename."), false;
    }
    if pkg.version == "" {
        return make_resolution_failure(.INVALID_PACKAGE_VERSION, "Package version must be nonempty."), false;
    }
    if pkg.dir == "" || !path_exists_as_directory(pkg.dir) {
        return make_resolution_failure(.INVALID_PACKAGE_ROOT, "Package root must be an existing real directory."), false;
    }
    return .{}, true;
}

make_effective_target :: (pkg: Package, name: string, main_file: string) -> Effective_Target, Target_Resolution_Error, string {
    if !path_is_portable_filename(name) {
        return .{}, .INVALID_TARGET_NAME, "Target name must be a nonempty portable filename.";
    }
    if !path_is_portable_relative_jai(main_file) {
        return .{}, .INVALID_TARGET_SOURCE, "Target main_file must be a portable package-relative .jai path.";
    }

    package_root, root_ok := normalize_existing_path(pkg.dir);
    if !root_ok {
        return .{}, .INVALID_PACKAGE_ROOT, "Package root could not be normalized.";
    }

    source_spelling := tprint("%1/%2", package_root, path_slashes(main_file));
    source_entry := inspect_path_entry(source_spelling);
    if !source_entry.exists {
        return .{}, .SOURCE_NOT_FOUND, tprint("Target source file does not exist: %1", main_file);
    }
    if source_entry.is_symlink || source_entry.is_junction || source_entry.is_directory {
        return .{}, .SOURCE_NOT_REGULAR, tprint("Target source is not a regular file: %1", main_file);
    }

    source_path, source_ok := normalize_existing_path(source_spelling);
    if !source_ok {
        return .{}, .SOURCE_NOT_FOUND, tprint("Target source could not be normalized: %1", main_file);
    }
    if !path_is_within(package_root, source_path) {
        return .{}, .SOURCE_OUTSIDE_PACKAGE, tprint("Target source escapes package root: %1", main_file);
    }

    target: Effective_Target;
    target.name = copy_string(name);
    target.main_file = copy_string(path_slashes(main_file));
    target.source_path = copy_string(source_path);
    return target, .NONE, "";
}

// Convention lookup for a library's import entry: module.jai at the package
// root first, then src/module.jai. Both are what "#import <package name>"
// resolves to once the package is linked into a dependency directory.
library_import_entry :: (pkg: Package) -> string, bool {
    package_root, root_ok := normalize_existing_path(pkg.dir);
    if !root_ok return "", false;
    for candidate: string.["module.jai", "src/module.jai"] {
        spelling := tprint("%1/%2", package_root, candidate);
        entry := inspect_path_entry(spelling);
        if entry.exists && !entry.is_directory && !entry.is_symlink && !entry.is_junction {
            return copy_string(spelling), true;
        }
    }
    return "", false;
}

// An unspecified package role is derived from convention: declared targets or
// the default executable entry mean BIN; an import entry means LIB; anything
// else stays BIN (a package with nothing to build).
derive_package_type :: (pkg: Package) -> Package_Type {
    if pkg.targets.count > 0 return .BIN;
    default_entry := tprint("%1/src/main.jai", path_slashes(pkg.dir));
    if path_exists_as_regular_file(default_entry) return .BIN;
    _, has_import_entry := library_import_entry(pkg);
    if has_import_entry return .LIB;
    return .BIN;
}

// A LIB package is an import source, never a compiled output: it declares no
// executable targets and is only validated for importability.
validate_library_package :: (pkg: Package) -> Target_Resolution_Result {
    if pkg.targets.count > 0 {
        return make_resolution_failure(.LIBRARY_TARGET_CONFLICT, tprint("Library package '%' cannot declare executable targets.", pkg.name));
    }

    _, found := library_import_entry(pkg);
    if !found {
        return make_resolution_failure(.MODULE_ENTRY_NOT_FOUND, "Library package must provide module.jai at the package root or src/module.jai.");
    }
    return .{success = true, package_type = .LIB};
}

resolve_effective_targets :: (pkg: Package) -> Target_Resolution_Result {
    identity_result, identity_ok := validate_package_identity(pkg);
    if !identity_ok return identity_result;

    targets: [..] Effective_Target;

    effective_type := pkg.type;
    if effective_type == .UNSPECIFIED effective_type = derive_package_type(pkg);

    if effective_type == .LIB {
        library_result := validate_library_package(pkg);
        if !library_result.success return library_result;
        return .{success = true, targets = targets, package_type = .LIB};
    }

    if pkg.targets.count == 0 {
        implicit_source := tprint("%1/src/main.jai", path_slashes(pkg.dir));
        implicit_entry := inspect_path_entry(implicit_source);
        if implicit_entry.exists && (implicit_entry.is_symlink || implicit_entry.is_junction || implicit_entry.is_directory) {
            return make_resolution_failure(.SOURCE_NOT_REGULAR, "Implicit src/main.jai is not a regular file.");
        }
        if implicit_entry.exists {
            target, error, message := make_effective_target(pkg, pkg.name, "src/main.jai");
            if error != .NONE return make_resolution_failure(error, message);
            array_add(*targets, target);
        }

        return .{success = true, targets = targets, package_type = .BIN};
    }

    for declaration, declaration_index: pkg.targets {
        if declaration.name == "" || declaration.main_file == "" {
            return make_resolution_failure(.INVALID_TARGET_NAME, tprint("Explicit target % has required name and main_file fields.", declaration_index));
        }

        for previous, previous_index: pkg.targets {
            if previous_index >= declaration_index break;
            if equal_nocase(previous.name, declaration.name) {
                return make_resolution_failure(.DUPLICATE_TARGET_NAME, tprint("Target name collides with another target: %1", declaration.name));
            }
        }

        target, error, message := make_effective_target(pkg, declaration.name, declaration.main_file);
        if error != .NONE return make_resolution_failure(error, message);
        array_add(*targets, target);
    }

    return .{success = true, targets = targets, package_type = .BIN};
}

make_artifact_plan :: (pkg: Package, target: Effective_Target) -> Artifact_Plan, bool {
    package_root, root_ok := normalize_existing_path(pkg.dir);
    if !root_ok return .{}, false;

    // Artifacts land directly in the unified target/ directory root.
    target_dir := tprint("%1/target", package_root);
    #if OS == .WINDOWS {
        artifact_name := tprint("%1.exe", target.name);
    } else {
        artifact_name := target.name;
    }
    artifact_path := tprint("%1/%2", target_dir, artifact_name);

    plan: Artifact_Plan;
    plan.target = target;
    plan.target_dir = copy_string(target_dir);
    plan.artifact_path = copy_string(artifact_path);
    return plan, true;
}

resolve_artifact_plans :: (pkg: Package) -> Artifact_Plan_Result {
    target_result := resolve_effective_targets(pkg);
    if !target_result.success {
        return make_artifact_failure(target_result.error, target_result.error_message);
    }

    plans: [..] Artifact_Plan;
    for target: target_result.targets {
        plan, ok := make_artifact_plan(pkg, target);
        if !ok return make_artifact_failure(.INVALID_PACKAGE_ROOT, "Could not construct artifact path.");
        array_add(*plans, plan);
    }
    return .{success = true, plans = plans, package_type = target_result.package_type};
}

revalidate_artifact_plan :: (plan: Artifact_Plan, package_root: string) -> bool {
    root_entry := inspect_path_entry(package_root);
    if !root_entry.exists || !root_entry.is_directory || root_entry.is_symlink || root_entry.is_junction return false;
    if !path_is_within(package_root, plan.target_dir) return false;
    if !path_is_within(package_root, plan.artifact_path) return false;
    target_entry := inspect_path_entry(plan.target_dir);
    if target_entry.exists && (!target_entry.is_directory || target_entry.is_symlink || target_entry.is_junction) return false;
    artifact_entry := inspect_path_entry(plan.artifact_path);
    if artifact_entry.exists && (artifact_entry.is_directory || artifact_entry.is_symlink || artifact_entry.is_junction) return false;
    if !path_is_portable_filename(plan.target.name) return false;
    if !path_is_portable_relative_jai(plan.target.main_file) return false;
    return true;
}
