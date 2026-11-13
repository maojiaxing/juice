// ---------------------------------------------------------------------------
// Target layout contract (2026-10-22 architecture review, Candidate 2): the
// literal outputs of the layout module. This is the one test that pins the
// layout's byte-level contract; every other caller and test crosses the
// Target_Layout interface. The module itself stays test-free (bootstrap
// #load discipline); this file is collected by Test discovery like every
// sibling test file.
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";

test "Target layout: the zone roots and landing paths are the documented literals" {
    target_dir := package_target_dir("C:\\pkg");
    expect(target_dir == "C:/pkg/target");
    expect(target_modules_dir(target_dir) == "C:/pkg/target/modules");
    expect(target_build_dir(target_dir) == "C:/pkg/target/build");
    expect(target_transpile_dir(target_dir) == "C:/pkg/target/transpile");
    expect(target_testing_module_dir(target_dir) == "C:/pkg/target/transpile/testing-module");
    expect(target_plugins_dir(target_dir) == "C:/pkg/target/plugins");
    expect(target_packages_dir(target_dir) == "C:/pkg/target/packages");
    expect(target_tests_dir(target_dir) == "C:/pkg/target/tests");
    expect(target_recovery_dir(target_dir) == "C:/pkg/target/recovery");
    expect(target_evidence_dir(target_dir) == "C:/pkg/target/evidence");
    #if OS == .WINDOWS {
        expect(target_artifact_path(target_dir, "app") == "C:/pkg/target/app.exe");
        expect(target_handoff_copy_path(target_dir, "app") == "C:/pkg/target/app-build.exe");
    } else {
        expect(target_artifact_path(target_dir, "app") == "C:/pkg/target/app");
        expect(target_handoff_copy_path(target_dir, "app") == "C:/pkg/target/app-build");
    }
    expect(target_session_driver_path(target_build_dir(target_dir), "bootstrap-meta.jai") == "C:/pkg/target/build/bootstrap-meta.jai");
    expect(target_scratch_dir(target_dir, "build-probe") == "C:/pkg/target/tests/build-probe");
    // Nested scratch names stay under the test zone.
    expect(target_scratch_dir(target_dir, "plugin-host-tests/case") == "C:/pkg/target/tests/plugin-host-tests/case");
}
