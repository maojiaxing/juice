#import "Basic";
#import "Testing";
#import "File_Utilities";

// A normal declared module entry, not the legacy modules/Testing.jai layout.
// Its extra marker makes using the host's already-published Testing observable.
testing_package_declared_entry_is_the_only_test_instance :: () {
    root := otter_scratch("testing-standard-package");
    delete_directory_full(root);
    defer delete_directory_full(root);
    source, source_ok := read_entire_file(tprint("%1/packages/testing/src/module.jai", otter_root()));
    expect(source_ok);
    expect(build_seam_write(root, "package.jai", #string END
#import "Juice";
PACKAGE :: Package.{name = "testing-probe", version = "1", modules = .[.{name = "Testing", entry = "src/module.jai"}], executables = .[], plugins = .[]};
END
    ));
    expect(build_seam_write(root, "src/module.jai", tprint("%1\nTESTING_MEMBER_MARKER :: 7129;\n", source)));
    for explicit_import: bool.[false, true] {
        import_line := ifx explicit_import then "#import \"Testing\";\n" else "";
        expect(build_seam_write(root, "tests/scenario.jai", tprint("%1member_source_is_used :: () { expect(TESTING_MEMBER_MARKER == 7129); } @test\n", import_line)));
        result, output, errors := run_otter_child_at(root, .["test"]);
        expect(expect_exit("declared-Testing-source", result, 0));
        expect(output_matches("declared-Testing-source", tprint("%1\n%2", output, errors), .["member_source_is_used", "1 passed, 0 failed"]));

        // A single failing assertion must reach the same register that the
        // injected runner finishes. A duplicate loaded instance can mask it.
        expect(build_seam_write(root, "tests/scenario.jai", tprint("%1member_failure_is_counted :: () { expect(TESTING_MEMBER_MARKER == 7129); fail(\"member-register-failure\"); } @test\n", import_line)));
        failed, failed_output, failed_errors := run_otter_child_at(root, .["test"]);
        expect(expect_exit("declared-Testing-register", failed, 1));
        expect(output_matches("declared-Testing-register", tprint("%1\n%2", failed_output, failed_errors), .["member-register-failure", "0 passed, 1 failed"]));
    }
    expect(file_delete(tprint("%1/src/module.jai", root)));
    missing, _, _ := run_otter_child_at(root, .["test"]);
    expect(expect_exit("declared-Testing-missing-source", missing, 1));
} @test
