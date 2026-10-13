#import "Basic";
#import "Juice";
#import "Testing";

// Fixture paths derive from juice_root()（src/test_support.jai，组织决议
// 0027）：所有测试共享声明集中于此文件，测试程序程序级共享。

// Regression tests for effective-target and artifact-plan resolution.
// The unnamed-explicit-target cases lock the declaration shape that used to
// reach the compiler as "-exe ''" on older Juice builds; Windows drops the
// empty argument, shifting "-output_path" into a bare input file.

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
// （library_fixture_package 见 src/test_support.jai）。

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
