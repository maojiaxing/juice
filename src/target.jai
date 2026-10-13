#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import "Juice";
#import "Testing";

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

// ---------------------------------------------------------------------------
// 内联测试（票 0034 自旧 tests/ 迁移）：effective-target 与
// artifact-plan 解析的回归测试。无名显式 target 用例锁住旧版 Juice 会把
// "-exe ''" 送进编译器的声明形状——Windows 丢弃空参数使 "-output_path" 滑
// 成裸输入文件。Fixture 路径派生自 juice_root()（tests/test_support.jai）。
// ---------------------------------------------------------------------------

test "Resolution rejects an unnamed explicit target" {
    pkg: Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = juice_root();
    pkg.targets = Target.[.{name = "", main_file = "src/main.jai"}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_TARGET_NAME && result.plans.count == 0);
}

test "Resolution rejects a target without an entry file" {
    pkg: Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = juice_root();
    pkg.targets = Target.[.{name = "app", main_file = ""}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_TARGET_NAME && result.plans.count == 0);
}

test "Resolution builds a plan for a valid declaration" {
    pkg: Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = juice_root();
    pkg.targets = Target.[.{name = "app", main_file = "src/main.jai"}];
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 1);
    plan := result.plans[0];
    expect(plan.target.name == "app");
    artifact_suffix: string;
    #if OS == .WINDOWS {
        artifact_suffix = "/target/app.exe";
    } else {
        artifact_suffix = "/target/app";
    }
    expect(ends_with(plan.artifact_path, artifact_suffix));
}

// A LIB package is an import source: it declares no executable targets and
// resolves to zero plans once its module.jai import entry is verified
// （library_fixture_package 见 tests/test_support.jai）。

test "Library package rejects executable targets" {
    pkg := library_fixture_package();
    pkg.targets = Target.[.{name = "app", main_file = "src/main.jai"}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .LIBRARY_TARGET_CONFLICT && result.plans.count == 0);
}

test "Library package requires a module.jai import entry" {
    pkg := library_fixture_package();
    pkg.dir = juice_root();  // 仓库根没有 module.jai
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .MODULE_ENTRY_NOT_FOUND && result.plans.count == 0);
}

test "Library package resolves to no plans" {
    result := resolve_artifact_plans(library_fixture_package());
    expect(result.success && result.plans.count == 0);
}

// Without an explicit type, the package role is derived from convention:
// src/main.jai means an executable package, an import entry means a library.
test "Unspecified type derives library from root entry" {
    pkg: Package;
    pkg.name    = "libdemo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data/lib-module", juice_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 0 && result.package_type == .LIB);
}

test "Unspecified type derives library from src entry" {
    pkg: Package;
    pkg.name    = "libdemo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data/lib-src-module", juice_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 0 && result.package_type == .LIB);
}

test "Unspecified type derives bin from default entry" {
    pkg: Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data/bin-package", juice_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 1);
    expect(result.package_type == .BIN && result.plans[0].target.name == "demo");
}

test "Unspecified type without any entry stays bin" {
    pkg: Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data", juice_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 0 && result.package_type == .BIN);
}

test "Explicit library accepts a src/module.jai entry" {
    pkg := library_fixture_package();
    pkg.dir = tprint("%1/tests/data/lib-src-module", juice_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 0 && result.package_type == .LIB);
}
