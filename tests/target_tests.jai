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
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.targets = Juice.Target.[.{name = "", main_file = "src/main.jai"}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_TARGET_NAME && result.plans.count == 0);
    expect(result.error_message == "Explicit target 0 has required name and main_file fields.");
}

test "Resolution rejects a target without an entry file" {
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.targets = Juice.Target.[.{name = "app", main_file = ""}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_TARGET_NAME && result.plans.count == 0);
}

test "Resolution rejects a target name that is not portable" {
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.targets = Juice.Target.[.{name = "a/b", main_file = "src/main.jai"}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_TARGET_NAME && result.plans.count == 0);
    expect(result.error_message == "Target name must be a nonempty portable filename.");
}

test "Resolution rejects a target source that is not portable" {
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.targets = Juice.Target.[.{name = "app", main_file = "C:/abs/main.jai"}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_TARGET_SOURCE && result.plans.count == 0);
    expect(result.error_message == "Target main_file must be a portable package-relative .jai path.");
}

test "Resolution rejects a missing target source" {
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.targets = Juice.Target.[.{name = "app", main_file = "src/missing.jai"}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .SOURCE_NOT_FOUND && result.plans.count == 0);
    expect(result.error_message == "Target source file does not exist: src/missing.jai");
}

test "Resolution rejects a target source that is not a regular file" {
    scratch := otter_scratch("target-test-dir-source");
    delete_directory_full(scratch);
    make_directory_if_it_does_not_exist(tprint("%1/src/entry.jai", scratch), recursive = true);
    defer delete_directory_full(scratch);
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = scratch;
    pkg.targets = Juice.Target.[.{name = "app", main_file = "src/entry.jai"}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .SOURCE_NOT_REGULAR && result.plans.count == 0);
    expect(result.error_message == "Target source is not a regular file: src/entry.jai");
}

test "Resolution builds a plan for a valid declaration" {
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.targets = Juice.Target.[.{name = "app", main_file = "src/main.jai"}];
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
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.targets = Juice.Target.[
        .{name = "app", main_file = "src/main.jai"},
        .{name = "tool", main_file = "src/main.jai"},
    ];
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 2);
    expect(result.plans[0].target.name == "app" && result.plans[1].target.name == "tool");
    expect(result.plans[0].artifact_path != result.plans[1].artifact_path);
}

// Declaration uniqueness is case-insensitive: artifact paths must stay
// unambiguous on Windows ("App" and "app" would collide as App.exe/app.exe).
test "Duplicate target names are rejected case-insensitively" {
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.targets = Juice.Target.[
        .{name = "App", main_file = "src/main.jai"},
        .{name = "app", main_file = "src/main.jai"},
    ];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .DUPLICATE_TARGET_NAME && result.plans.count == 0);
    expect(result.error_message == "Target name collides with another target: app");
}

test "Exact duplicate target names are rejected" {
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.targets = Juice.Target.[
        .{name = "app", main_file = "src/main.jai"},
        .{name = "app", main_file = "src/main.jai"},
    ];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .DUPLICATE_TARGET_NAME && result.plans.count == 0);
}

test "Distinct names with case differences pass" {
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = otter_root();
    pkg.targets = Juice.Target.[
        .{name = "App", main_file = "src/main.jai"},
        .{name = "Appl", main_file = "src/main.jai"},
    ];
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 2);
}

test "Package identity rejects a non-portable name" {
    pkg: Juice.Package;
    pkg.name    = "a/b";
    pkg.version = "1";
    pkg.dir     = otter_root();
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_PACKAGE_NAME && result.plans.count == 0);
    expect(result.error_message == "Package name must be a nonempty portable filename.");
}

test "Package identity rejects an empty version" {
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "";
    pkg.dir     = otter_root();
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .INVALID_PACKAGE_VERSION && result.plans.count == 0);
    expect(result.error_message == "Package version must be nonempty.");
}

test "Package identity rejects a missing root" {
    pkg: Juice.Package;
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

test "Library package rejects executable targets" {
    pkg := library_fixture_package();
    pkg.targets = Juice.Target.[.{name = "app", main_file = "src/main.jai"}];
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .LIBRARY_TARGET_CONFLICT && result.plans.count == 0);
    expect(result.error_message == "Library package 'libdemo' cannot declare executable targets.");
}

// tests/data has no module.jai at its root or under src/, so the library
// entry lookup fails (old juice used its repository root the same way).
test "Library package requires a module.jai import entry" {
    pkg := library_fixture_package();
    pkg.dir = tprint("%1/tests/data", otter_root());
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .MODULE_ENTRY_NOT_FOUND && result.plans.count == 0);
    expect(result.error_message == "Library package must provide module.jai at the package root or src/module.jai.");
}

test "Library package resolves to no plans" {
    result := resolve_artifact_plans(library_fixture_package());
    expect(result.success && result.plans.count == 0 && result.package_type == .LIB);
}

test "Explicit library accepts a src/module.jai entry" {
    pkg := library_fixture_package();
    pkg.dir = tprint("%1/tests/data/target-lib-src-module", otter_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 0 && result.package_type == .LIB);
}

// ---------------------------------------------------------------------------
// UNSPECIFIED derivation: declared targets or src/main.jai mean BIN, an
// import entry means LIB, anything else stays BIN (a package with nothing to
// build).
// ---------------------------------------------------------------------------

test "Unspecified type derives library from root entry" {
    pkg: Juice.Package;
    pkg.name    = "libdemo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data/target-lib-module", otter_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 0 && result.package_type == .LIB);
}

test "Unspecified type derives library from src entry" {
    pkg: Juice.Package;
    pkg.name    = "libdemo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data/target-lib-src-module", otter_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 0 && result.package_type == .LIB);
}

test "Unspecified type derives bin from default entry" {
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data/target-bin-package", otter_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 1);
    expect(result.package_type == .BIN && result.plans[0].target.name == "demo");
}

test "Unspecified type without any entry stays bin" {
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data", otter_root());
    result := resolve_artifact_plans(pkg);
    expect(result.success && result.plans.count == 0 && result.package_type == .BIN);
}

// A directory at the implicit entry path is not a regular file.
test "Implicit src/main.jai must be a regular file" {
    scratch := otter_scratch("target-test-nonregular");
    delete_directory_full(scratch);
    make_directory_if_it_does_not_exist(tprint("%1/src/main.jai", scratch), recursive = true);
    defer delete_directory_full(scratch);
    pkg: Juice.Package;
    pkg.name    = "demo";
    pkg.version = "1";
    pkg.dir     = scratch;
    result := resolve_artifact_plans(pkg);
    expect(!result.success && result.error == .SOURCE_NOT_REGULAR && result.plans.count == 0);
    expect(result.error_message == "Implicit src/main.jai is not a regular file.");
}

// ---------------------------------------------------------------------------
// The shared build/run gate: a resolved plan stays valid only while its
// paths sit inside a safe real package root and its declaration stays
// portable.
// ---------------------------------------------------------------------------

test "Artifact plan revalidation gate" {
    root := otter_root();
    plan: Juice.Artifact_Plan;
    plan.target = .{name = "app", main_file = "src/main.jai"};
    plan.target_dir = package_target_dir(root);
    plan.artifact_path = target_artifact_path(package_target_dir(root), "app");
    expect(revalidate_artifact_plan(plan, root));

    escaping: Juice.Artifact_Plan;
    escaping.target = .{name = "app", main_file = "src/main.jai"};
    escaping.target_dir = tprint("%1/../escape", root);
    escaping.artifact_path = tprint("%1/../escape/app.exe", root);
    expect(!revalidate_artifact_plan(escaping, root));

    bad_name: Juice.Artifact_Plan;
    bad_name.target = .{name = "", main_file = "src/main.jai"};
    bad_name.target_dir = package_target_dir(root);
    bad_name.artifact_path = target_artifact_path(package_target_dir(root), "app");
    expect(!revalidate_artifact_plan(bad_name, root));

    bad_entry: Juice.Artifact_Plan;
    bad_entry.target = .{name = "app", main_file = "main.txt"};
    bad_entry.target_dir = package_target_dir(root);
    bad_entry.artifact_path = target_artifact_path(package_target_dir(root), "app");
    expect(!revalidate_artifact_plan(bad_entry, root));
}
