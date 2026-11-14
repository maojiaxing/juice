#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// Target tests: effective-target derivation, the conflict matrix and
// artifact planning (old juice target.jai inline test semantics, migrated to
// the sister test file per the test organization rule). Fixture packages
// live under tests/data/target-*; library_fixture_package lives in
// tests/test_support.jai. Resolved artifact paths are deterministic —
// normalize_existing_path + path_slashes — so shims and plans are asserted
// byte for byte.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Validation matrix: the portable path gates (the target face of
// path_safety, ticket 009).
// ---------------------------------------------------------------------------

test "Portable filename gate" {
    expect(!path_is_portable_filename(""));
    expect(!path_is_portable_filename("."));
    expect(!path_is_portable_filename(".."));
    expect(!path_is_portable_filename("app."));
    expect(!path_is_portable_filename("app "));
    expect(!path_is_portable_filename("a/b"));
    expect(!path_is_portable_filename("a\\b"));
    expect(!path_is_portable_filename("a:b"));
    expect(!path_is_portable_filename("a*b"));
    expect(!path_is_portable_filename("a?b"));
    expect(!path_is_portable_filename("a\"b"));
    expect(!path_is_portable_filename("a<b"));
    expect(!path_is_portable_filename("a>b"));
    expect(!path_is_portable_filename("a|b"));
    expect(!path_is_portable_filename("CON"));
    expect(!path_is_portable_filename("prn"));
    expect(!path_is_portable_filename("AUX"));
    expect(!path_is_portable_filename("nul"));
    expect(!path_is_portable_filename("COM1"));
    expect(!path_is_portable_filename("LPT9"));
    expect(path_is_portable_filename("app"));
    expect(path_is_portable_filename("app.exe"));
    expect(path_is_portable_filename("a.b"));
}

test "Portable relative .jai path gate" {
    expect(!path_is_portable_relative_jai(""));
    expect(!path_is_portable_relative_jai("/abs/main.jai"));
    expect(!path_is_portable_relative_jai("C:/abs/main.jai"));
    expect(!path_is_portable_relative_jai("../escape.jai"));
    expect(!path_is_portable_relative_jai("a/../b.jai"));
    expect(!path_is_portable_relative_jai("noext"));
    expect(path_is_portable_relative_jai("main.jai"));
    expect(path_is_portable_relative_jai("src/main.jai"));
}

// ---------------------------------------------------------------------------
// Resolution matrix: explicit target validation, the LIB conflict, the
// duplicate-name conflict, and package identity.
// ---------------------------------------------------------------------------

test "Resolution rejects an unnamed explicit target" {
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.executables = Declared_Product.[.{name = "", entry = "src/main.jai"}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_TARGET_NAME && result.plans.count == 0);
    expect(result.error_message == "executables[0]: Product name must be a Jai identifier; provide an explicit legal name.");
}

test "Resolution rejects a target without an entry file" {
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.executables = Declared_Product.[.{name = "app", entry = ""}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_TARGET_SOURCE && result.plans.count == 0);
}

test "Resolution rejects a target name that is not portable" {
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.executables = Declared_Product.[.{name = "a/b", entry = "src/main.jai"}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_TARGET_NAME && result.plans.count == 0);
    expect(result.error_message == "executables[0]: Product name must be a Jai identifier; provide an explicit legal name.");
}

test "Resolution rejects a target source that is not portable" {
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.executables = Declared_Product.[.{name = "app", entry = "C:/abs/main.jai"}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_TARGET_SOURCE && result.plans.count == 0);
    expect(result.error_message == "executables[0]: Product entry must be a package-relative .jai path.");
}

test "Resolution rejects a missing target source" {
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.executables = Declared_Product.[.{name = "app", entry = "src/missing.jai"}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .SOURCE_NOT_FOUND && result.plans.count == 0);
    expect(result.error_message == "executables[0]: Product entry does not exist: src/missing.jai");
}

test "Resolution rejects a target source that is not a regular file" {
    scratch := otter_scratch("target-test-dir-source");
    delete_directory_full(scratch);
    make_directory_if_it_does_not_exist(tprint("%1/src/entry.jai", scratch), recursive = true);
    defer delete_directory_full(scratch);
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = scratch;
    pkg.executables = Declared_Product.[.{name = "app", entry = "src/entry.jai"}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .SOURCE_NOT_REGULAR && result.plans.count == 0);
    expect(result.error_message == "executables[0]: Product entry is not a regular link-free file: src/entry.jai");
}

test "Resolution builds a plan for a valid declaration" {
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.executables = Declared_Product.[.{name = "app", entry = "src/main.jai"}];
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

test "Explicit targets resolve to separate artifact plans" {
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.executables = Declared_Product.[
        .{name = "app", entry = "src/main.jai"},
        .{name = "tool", entry = "src/commands/help.jai"},
    ];
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 2);
    expect(result.plans[0].target.name == "app" && result.plans[1].target.name == "tool");
    expect(result.plans[0].artifact_path != result.plans[1].artifact_path);
}

// Declaration uniqueness is case-insensitive: artifact paths must stay
// unambiguous on Windows ("App" and "app" would collide as App.exe/app.exe).
test "Duplicate target names are rejected case-insensitively" {
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.executables = Declared_Product.[
        .{name = "App", entry = "src/main.jai"},
        .{name = "app", entry = "src/main.jai"},
    ];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .DUPLICATE_TARGET_NAME && result.plans.count == 0);
    expect(result.error_message == "Duplicate product name: app");
}

test "Exact duplicate target names are rejected" {
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.executables = Declared_Product.[
        .{name = "app", entry = "src/main.jai"},
        .{name = "app", entry = "src/main.jai"},
    ];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .DUPLICATE_TARGET_NAME && result.plans.count == 0);
}

test "Distinct names with case differences pass" {
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.executables = Declared_Product.[
        .{name = "App", entry = "src/main.jai"},
        .{name = "Appl", entry = "src/commands/help.jai"},
    ];
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 2);
}

test "Package identity rejects a non-portable name" {
    pkg: Normalized_Package;
    pkg.name    = "a/b";
    pkg.version = "1";
    pkg.dir     = otter_root();
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_PACKAGE_NAME && result.plans.count == 0);
    expect(result.error_message == "Package name must match [A-Za-z0-9][A-Za-z0-9._-]*.");
}

test "Package identity rejects an empty version" {
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "";
    pkg.dir     = otter_root();
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_PACKAGE_VERSION && result.plans.count == 0);
    expect(result.error_message == "Package version must be nonempty.");
}

test "Package identity rejects a missing root" {
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_scratch("nonexistent-pkg-root");
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_PACKAGE_ROOT && result.plans.count == 0);
    expect(result.error_message == "Package root must be an existing real directory.");
}

// ---------------------------------------------------------------------------
// Library packages: import sources only — declared targets are a hard
// error, the import entry is required, and a valid library resolves to zero
// plans.
// ---------------------------------------------------------------------------

test "Modules and executables coexist" {
    pkg := library_fixture_package();
    pkg.dir = otter_root();
    pkg.executables = Declared_Product.[.{name = "app", entry = "src/main.jai"}];
    result := resolve_effective_targets(pkg);
    expect(result.success && result.targets.count == 1);
    expect(result.modules.count == 1 && result.targets[0].name == "app");
}

// tests/data has no module.jai at its root or under src/, so the library
// entry lookup fails (old juice used its repository root the same way).
test "A package without module entries has zero modules" {
    pkg := library_fixture_package();
    pkg.dir = tprint("%1/tests/data", otter_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 0);
    expect(result.error_message == "");
}

test "Library package resolves to no plans" {
    result := resolve_artifact_plans(library_fixture_package());
    expect(result.success && result.plans.count == 0);
}

test "Explicit library accepts a src/module.jai entry" {
    pkg := library_fixture_package();
    pkg.dir = tprint("%1/tests/data/target-lib-src-module", otter_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 0);
}

// ---------------------------------------------------------------------------
// UNSPECIFIED derivation: declared targets or src/main.jai mean BIN, an
// import entry means LIB, anything else stays BIN (a package with nothing to
// build).
// ---------------------------------------------------------------------------

test "Unspecified type derives library from root entry" {
    pkg: Normalized_Package;
    pkg.name    = "libdemo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data/target-lib-module", otter_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 0);
}

test "Unspecified type derives library from src entry" {
    pkg: Normalized_Package;
    pkg.name    = "libdemo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data/target-lib-src-module", otter_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 0);
}

test "Unspecified type derives bin from default entry" {
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data/target-bin-package", otter_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 1);
    expect(result.plans[0].target.name == "demo");
}

test "Unspecified type without any entry stays bin" {
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data", otter_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 0);
}

// A directory at the implicit entry path is not a regular file.
test "Implicit src/main.jai must be a regular file" {
    scratch := otter_scratch("target-test-nonregular");
    delete_directory_full(scratch);
    make_directory_if_it_does_not_exist(tprint("%1/src/main.jai", scratch), recursive = true);
    defer delete_directory_full(scratch);
    pkg: Normalized_Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = scratch;
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .SOURCE_NOT_REGULAR && result.plans.count == 0);
    expect(result.error_message == "Product entry is not a regular link-free file: src/main.jai");
}

// ---------------------------------------------------------------------------
// The shared build/run gate: a resolved plan stays valid only while its
// paths sit inside a safe real package root and its declaration stays
// portable.
// ---------------------------------------------------------------------------

test "Artifact plan revalidation gate" {
    root := otter_root();
    plan: Artifact_Plan;
    plan.target = .{name = "app", main_file = "src/main.jai"};
    plan.target_dir = package_target_dir(root);
    plan.artifact_path = target_artifact_path(package_target_dir(root), "app");
    expect(revalidate_artifact_plan(plan, root));

    escaping: Artifact_Plan;
    escaping.target = .{name = "app", main_file = "src/main.jai"};
    escaping.target_dir = tprint("%1/../escape", root);
    escaping.artifact_path = tprint("%1/../escape/app.exe", root);
    expect(!revalidate_artifact_plan(escaping, root));

    bad_name: Artifact_Plan;
    bad_name.target = .{name = "", main_file = "src/main.jai"};
    bad_name.target_dir = package_target_dir(root);
    bad_name.artifact_path = target_artifact_path(package_target_dir(root), "app");
    expect(!revalidate_artifact_plan(bad_name, root));

    bad_entry: Artifact_Plan;
    bad_entry.target = .{name = "app", main_file = "main.txt"};
    bad_entry.target_dir = package_target_dir(root);
    bad_entry.artifact_path = target_artifact_path(package_target_dir(root), "app");
    expect(!revalidate_artifact_plan(bad_entry, root));
}
