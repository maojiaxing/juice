#import "Basic";
#import "String";

// ---------------------------------------------------------------------------
// The target layout (2026-10-22 architecture review, Candidate 2): the single
// source of the package's target/ directory layout. A caller learns fourteen
// pure path functions and nothing else; the zone names, the join rules and the
// platform executable suffix live here. The literal outputs are the spec
// contract (artifact root §2.1/§3.1, modules tree §9, transpile tree §7.2)
// and are pinned by tests/target_layout_tests.jai.
//
// This module is a bootstrap #load target and must stay test-free (the
// build.jai closure contract); its tests live in tests/ (the test
// organization rule). It has no Juice dependency and no filesystem access:
// callers own existence checks and directory creation.
//
// Zone ownership:
// - target_build_dir: the build session zone — generated build drivers
//   (bootstrap meta/version-check, build-<target>.jai) plus the compiler
//   intermediates for build and test programs
// - target_modules_dir: the published module faces (installation contract)
// - target_transpile_dir: the content-addressed view tree, the Testing
//   compile view (transpile/testing-module/) and the test runner entry
// - target_plugins_dir: the plugin registration / host session artifacts
// - target_packages_dir: the dependency import shims (compile input)
// - target_tests_dir: test scratch (pruned at the start of every test run)
// - target_recovery_dir: crash-recovery backups (never pruned by the test
//   command; clean removes the whole target tree)
// - target_evidence_dir: session evidence/logs (manual, ephemeral)
// - target_artifact_path / target_handoff_copy_path: the executable and its
//   LNK1104 hand-off copy (the copy must stay in target_dir: modules_dir is
//   <exe dir>/modules)
// ---------------------------------------------------------------------------

// The two file-private join helpers (the public interface is the semantic
// names below; a generic zone accessor never reaches callers, so a zone name
// cannot leak back to a call site).
#scope_file;

target_zone_dir :: (target_dir: string, zone_name: string) -> string {
    return front_slashes(tprint("%1/%2", target_dir, zone_name));
}

target_executable_path :: (target_dir: string, base_name: string) -> string {
    #if OS == .WINDOWS {
        return front_slashes(tprint("%1/%2.exe", target_dir, base_name));
    } else {
        return front_slashes(tprint("%1/%2", target_dir, base_name));
    }
}

#scope_export;

// The package's unified target/ directory root. Artifacts land directly in
// it (spec §2.1: no profile sublayers).
package_target_dir :: (package_root: string) -> string {
    return front_slashes(tprint("%1/target", package_root));
}

// The published module tree: Juice/ (directory module), Testing.jai,
// juice_core.jai and juice_internal/ (spec §9.2). Installed next to the
// executable.
target_modules_dir :: (target_dir: string) -> string {
    return target_zone_dir(target_dir, "modules");
}

// The build session zone: the generated build drivers (bootstrap-meta.jai,
// bootstrap-version-check.jai, build-<target>.jai) and the compiler
// intermediates for build and test programs (.obj/.lib/.exp/.pdb/
// .added_strings_*). Session artifacts, regenerated every run.
target_build_dir :: (target_dir: string) -> string {
    return target_zone_dir(target_dir, "build");
}

// The transpile view tree: content-addressed hash directories, deps/, the
// bootstrap PLAIN subtree, the Testing compile view and the test runner entry.
target_transpile_dir :: (target_dir: string) -> string {
    return target_zone_dir(target_dir, "transpile");
}

// The Testing module compile view directory (target/transpile/
// testing-module): a view like every other transpile product, rewritten
// before each build/test run.
target_testing_module_dir :: (target_dir: string) -> string {
    return target_zone_dir(target_transpile_dir(target_dir), "testing-module");
}

// The plugin registration file and PRESTEP host session artifacts
// (target/plugins).
target_plugins_dir :: (target_dir: string) -> string {
    return target_zone_dir(target_dir, "plugins");
}

// The dependency import shim directory (target/packages): the compiler
// import path for dependencies and workspace members.
target_packages_dir :: (target_dir: string) -> string {
    return target_zone_dir(target_dir, "packages");
}

// Test scratch (target/tests): the test command prunes the whole zone at the
// start of every run; every test's scratch root lives here.
target_tests_dir :: (target_dir: string) -> string {
    return target_zone_dir(target_dir, "tests");
}

// Crash-recovery backups (target/recovery): the bootstrap missing-source
// tests park a source here before removing it. Excluded from the test
// command's prune — a crashed run's backup is the only copy. Clean removes
// the whole target tree.
target_recovery_dir :: (target_dir: string) -> string {
    return target_zone_dir(target_dir, "recovery");
}

// Session evidence/logs (target/evidence): audit and run logs written by the
// development workflow, never by the tool. Ephemeral like every target
// artifact (clean deletes it); persistent acceptance evidence belongs in
// docs/implementation/.
target_evidence_dir :: (target_dir: string) -> string {
    return target_zone_dir(target_dir, "evidence");
}

// The executable artifact path: target/<name>.exe on Windows, target/<name>
// elsewhere.
target_artifact_path :: (target_dir: string, target_name: string) -> string {
    return target_executable_path(target_dir, target_name);
}

// The LNK1104 hand-off copy: target/<name>-build.exe. The copy must stay in
// target_dir because juice_modules_dir() derives <exe dir>/modules.
target_handoff_copy_path :: (target_dir: string, target_name: string) -> string {
    return target_executable_path(target_dir, tprint("%1-build", target_name));
}

// A generated session driver at the caller's file name (bootstrap-meta.jai,
// bootstrap-version-check.jai, build-<target>.jai, test_runner.jai).
target_session_driver_path :: (target_dir: string, file_name: string) -> string {
    return target_zone_dir(target_dir, file_name);
}

// A test scratch root under the test zone (target/tests/<name>).
target_scratch_dir :: (target_dir: string, name: string) -> string {
    return target_zone_dir(target_tests_dir(target_dir), name);
}
