#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

Target_Resolution_Error :: enum {
    NONE; INVALID_PACKAGE_ROOT; INVALID_PACKAGE_NAME; INVALID_PACKAGE_VERSION;
    INVALID_TARGET_NAME; INVALID_TARGET_SOURCE; DUPLICATE_TARGET_NAME;
    DUPLICATE_TARGET_SOURCE; SOURCE_NOT_FOUND; SOURCE_NOT_REGULAR;
    SOURCE_OUTSIDE_PACKAGE; AMBIGUOUS_MODULE_ENTRY; MODULE_ENTRY_NOT_FOUND;
    INVALID_DEFAULT_RUN;
}
Target_Resolution_Result :: struct {
    success: bool;
    modules: [] Effective_Target;
    targets: [] Effective_Target;
    error: Target_Resolution_Error;
    error_message: string;
}
Artifact_Plan_Result :: struct {
    success: bool;
    plans: [] Artifact_Plan;
    error: Target_Resolution_Error;
    error_message: string;
}
make_resolution_failure :: (error: Target_Resolution_Error, message: string) -> Target_Resolution_Result {
    return .{error = error, error_message = copy_string(message)};
}
make_artifact_failure :: (error: Target_Resolution_Error, message: string) -> Artifact_Plan_Result {
    return .{error = error, error_message = copy_string(message)};
}
validate_package_identity :: (pkg: Normalized_Package) -> Target_Resolution_Result, bool {
    if !package_name_is_valid(pkg.name) return make_resolution_failure(.INVALID_PACKAGE_NAME, "Package name must match [A-Za-z0-9][A-Za-z0-9._-]*."), false;
    if pkg.version == "" return make_resolution_failure(.INVALID_PACKAGE_VERSION, "Package version must be nonempty."), false;
    if pkg.dir == "" || !path_exists_as_directory(pkg.dir) || !path_chain_is_link_free(pkg.dir) return make_resolution_failure(.INVALID_PACKAGE_ROOT, "Package root must be an existing real directory."), false;
    return .{}, true;
}
make_effective_target :: (pkg: Normalized_Package, name: string, main_file: string) -> Effective_Target, Target_Resolution_Error, string {
    if !declaration_identifier_is_valid(name) return .{}, .INVALID_TARGET_NAME, "Product name must be a Jai identifier; provide an explicit legal name.";
    logical := normalize_package_relative_path(main_file);
    if !logical.success || !ends_with_nocase(logical.path, ".jai") return .{}, .INVALID_TARGET_SOURCE, "Product entry must be a package-relative .jai path.";
    source := path_slashes(tprint("%/%", pkg.dir, logical.path));
    entry := inspect_path_entry(source);
    if !entry.exists return .{}, .SOURCE_NOT_FOUND, tprint("Product entry does not exist: %", main_file);
    if !path_chain_is_link_free(source) || entry.is_directory return .{}, .SOURCE_NOT_REGULAR, tprint("Product entry is not a regular link-free file: %", main_file);
    source_path, ok := normalize_existing_path(source);
    if !ok return .{}, .SOURCE_NOT_FOUND, tprint("Could not normalize product entry: %", main_file);
    if !path_is_within(pkg.dir, source_path) return .{}, .SOURCE_OUTSIDE_PACKAGE, "Product entry escapes package root.";
    return .{name = copy_string(name), main_file = copy_string(logical.path), source_path = source_path}, .NONE, "";
}
resolve_product_list :: (pkg: Normalized_Package, declarations: [] Declared_Product, omitted: bool, is_module: bool) -> Target_Resolution_Result {
    products: [..] Effective_Target;
    if omitted && declarations.count == 0 {
        candidates: [] string = .["src/main.jai"];
        if is_module candidates = .["module.jai", "src/module.jai"];
        for candidate: candidates {
            if !inspect_path_entry(tprint("%/%", pkg.dir, candidate)).exists continue;
            product, error, message := make_effective_target(pkg, pkg.name, candidate);
            if error != .NONE return make_resolution_failure(error, message);
            array_add(*products, product);
        }
        if products.count > 1 return make_resolution_failure(.AMBIGUOUS_MODULE_ENTRY, "Both module.jai and src/module.jai exist; declare modules explicitly.");
    } else {
        for declaration, index: declarations {
            name := declaration.name;
            if !declaration.name_present {
                if declarations.count != 1 return make_resolution_failure(.INVALID_TARGET_NAME, "Every item in a multiple-product list must declare name.");
                name = pkg.name;
            }
            product, error, message := make_effective_target(pkg, name, declaration.entry);
            if error != .NONE return make_resolution_failure(error, tprint("%[%]: %", ifx is_module then "modules" else "executables", index, message));
            for previous: products {
                if ascii_names_equal(previous.name, product.name) return make_resolution_failure(.DUPLICATE_TARGET_NAME, tprint("Duplicate product name: %", name));
                if paths_equal(previous.source_path, product.source_path) return make_resolution_failure(.DUPLICATE_TARGET_SOURCE, tprint("Duplicate product entry: %", declaration.entry));
            }
            array_add(*products, product);
        }
    }
    return .{success = true, targets = products};
}
resolve_effective_targets :: (pkg: Normalized_Package) -> Target_Resolution_Result {
    if !pkg.has_package return .{success = true};
    identity, ok := validate_package_identity(pkg);
    if !ok return identity;
    modules := resolve_product_list(pkg, pkg.modules, pkg.modules_omitted, true);
    if !modules.success return modules;
    executables := resolve_product_list(pkg, pkg.executables, pkg.executables_omitted, false);
    if !executables.success return executables;
    if pkg.default_run != "" {
        found := false;
        for executable: executables.targets if ascii_names_equal(executable.name, pkg.default_run) found = true;
        if !found return make_resolution_failure(.INVALID_DEFAULT_RUN, "default_run must name a declared executable.");
    }
    return .{success = true, modules = modules.targets, targets = executables.targets};
}
library_import_entry :: (pkg: Normalized_Package) -> string, bool {
    result := resolve_product_list(pkg, pkg.modules, pkg.modules_omitted, true);
    if !result.success || result.targets.count != 1 return "", false;
    return result.targets[0].source_path, true;
}

make_artifact_plan :: (pkg: Normalized_Package, target: Effective_Target) -> Artifact_Plan, bool {
    package_root, root_ok := normalize_existing_path(pkg.dir);
    if !root_ok return .{}, false;

    // Artifacts land directly in the unified target/ directory root.
    target_dir := package_target_dir(package_root);
    artifact_path := target_artifact_path(target_dir, target.name);

    plan: Artifact_Plan;
    plan.target = target;
    plan.target_dir = copy_string(target_dir);
    plan.artifact_path = copy_string(artifact_path);
    return plan, true;
}

resolve_artifact_plans :: (pkg: Normalized_Package) -> Artifact_Plan_Result {
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
    return .{success = true, plans = plans};
}

// The shared gate build and run both use before touching an artifact plan:
// the package root is a safe real directory, the plan's paths stay inside
// it, and the target declaration is still portable. Any existing target
// directory must be a real directory; any existing artifact must be a plain
// file (never a directory/symlink/junction).
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
